#############################################################################
##
## Copyright (C) 2017 The Qt Company Ltd.
## Contact: https://www.qt.io/licensing/
##
## This file is part of the Quality Assurance module of the Qt Toolkit.
##
## $QT_BEGIN_LICENSE:GPL-EXCEPT$
## Commercial License Usage
## Licensees holding valid commercial Qt licenses may use this file in
## accordance with the commercial license agreement provided with the
## Software or, alternatively, in accordance with the terms contained in
## a written agreement between you and The Qt Company. For licensing terms
## and conditions see https://www.qt.io/terms-conditions. For further
## information use the contact form at https://www.qt.io/contact-us.
##
## GNU General Public License Usage
## Alternatively, this file may be used under the terms of the GNU
## General Public License version 3 as published by the Free Software
## Foundation with exceptions as appearing in the file LICENSE.GPL3-EXCEPT
## included in the packaging of this file. Please review the following
## information to ensure the GNU General Public License requirements will
## be met: https://www.gnu.org/licenses/gpl-3.0.html.
##
## $QT_END_LICENSE$
##
#############################################################################
package QtQA::Gerrit;
use strict;
use warnings;

use AnyEvent::Handle;
use AnyEvent::Util;
use AnyEvent;
use Carp;
use English qw(-no_match_vars);
use Params::Validate qw(:all);
use URI;

use QtQA::AnyEvent::Util;

use base 'Exporter';
our @EXPORT_OK = qw(
    stream_events
    git_environment
    next_change_id
    random_change_id
    review
);

## no critic (RequireArgUnpacking) - does not play well with Params::Validate

sub stream_events
{
    my (%args) = @_;

    my $url = $args{ url } || croak 'missing url argument';
    my $on_event = $args{ on_event } || croak 'missing on_event argument';
    my $on_error = $args{ on_error } || sub {
        my ($handle, $error) = @_;
        warn __PACKAGE__ . ": $error\n";
        return 1;
    };

    my $INIT_SLEEP = 2;
    my $MAX_SLEEP = 60*10;
    my $sleep = $INIT_SLEEP;

    my @ssh = (
        @{ _gerrit_parse_url( $url )->{ cmd } },
        'stream-events'
    );

    my $out = {};

    my $cleanup = sub {
        my ($handle) = @_;
        delete $handle->{ timer };
        if (my $r_h = delete $handle->{ r_h }) {
            $r_h->destroy();
        }
        if (my $cv = delete $handle->{ cv }) {
            $cv->cb( sub {} );
            if (my $pid = $handle->{ pid }) {
                kill( 15, $pid );
            }
        }
    };

    my $restart;

    my $handle_error = sub {
        my ($handle, $error) = @_;
        my $retry;
        eval {
            $retry = $on_error->( $handle, $error );
        };
        if ($retry) {
            # retry after $sleep seconds only
            $handle->{ timer } = AnyEvent->timer( after => $sleep, cb => sub { $restart->( $handle ) } );
            $sleep *= 2;
            if ($sleep > $MAX_SLEEP) {
                $sleep = $MAX_SLEEP;
            }
        } else {
            $cleanup->( $handle );
        }
    };

    $restart = sub {
        my ($handle) = @_;
        $cleanup->( $handle );

        $sleep = $INIT_SLEEP;

        my ($r, $w) = portable_pipe();

        $handle->{ r_h } = AnyEvent::Handle->new(
            fh => $r,
        );
        $handle->{ r_h }->on_error(
            sub {
                my (undef, undef, $error) = @_;
                $handle_error->( $handle, $error );
            }
        );

        # run stream-events with stdout connected to pipe ...
        $handle->{ cv } = run_cmd(
            \@ssh,
            '>' => $w,
            '$$' => \$handle->{ pid },
        );
        $handle->{ cv }->cb(
            sub {
                my ($status) = shift->recv();
                $handle_error->( $handle, "ssh exited with status $status" );
            }
        );

        my %read_req;
        %read_req = (
            # read one json item at a time
            json => sub {
                my ($h, $data) = @_;

                # every successful read resets sleep period
                $sleep = $INIT_SLEEP;

                $on_event->( $handle, $data );
                $h->push_read( %read_req );
            }
        );
        $handle->{ r_h }->push_read( %read_req );
    };

    my $stash = {};
    $restart->( $stash );
    return guard {
        $cleanup->( $stash );
    };
}

sub random_change_id
{
    return 'I'.sprintf(
        # 40 hex digits, one 32 bit integer gives 8 hex digits,
        # therefore 5 random integers
        "%08x" x 5,
        map { rand()*(2**32) } (1..5)
    );
}

sub next_change_id
{
    if (!$ENV{ GIT_AUTHOR_NAME } || !$ENV{ GIT_AUTHOR_EMAIL }) {
        carp __PACKAGE__ . ': git environment is not set, using random Change-Id';
        return random_change_id( );
    }

    # First preference: change id is the last SHA used by this bot.
    my $author = "$ENV{ GIT_AUTHOR_NAME } <$ENV{ GIT_AUTHOR_EMAIL }>";
    my $change_id = qx(git rev-list -n1 --fixed-strings "--author=$author" HEAD);
    if (my $error = $?) {
        carp __PACKAGE__ . qq{: no previous commits from "$author" were found};
    } else {
        chomp $change_id;
    }

    # Second preference: for a stable but random change-id, use hash of the bot name
    if (!$change_id) {
        $change_id = qx(echo "$author" | git hash-object --stdin);
        if (my $error = $?) {
            carp __PACKAGE__ . qq{: git hash-object failed};
        } else {
            chomp $change_id;
        }
    }

    # Check if we seem to have this change id already.
    # This can happen if an author other than ourself has already used the change id.
    if ($change_id) {
        my $found = qx(git log -n1000 "--grep=I$change_id" HEAD);
        if (!$? && $found) {
            carp __PACKAGE__ . qq{: desired Change-Id $change_id is already used};
            undef $change_id;
        }
    }

    if ($change_id) {
        return "I$change_id";
    }

    carp __PACKAGE__ . q{: falling back to random Change-Id};

    return random_change_id( );
}

sub git_environment
{
    my (%options) = validate(
        @_,
        {
            bot_name => 1,  # mandatory
            bot_email => 0,
            author_only => 0,
        }
    );

    $options{ bot_email } ||= 'noreply@qt-project.org';

    my %env = %ENV;

    $env{ GIT_AUTHOR_NAME } = $options{ bot_name };
    $env{ GIT_AUTHOR_EMAIL } = $options{ bot_email };

    unless ($options{ author_only }) {
        $env{ GIT_COMMITTER_NAME } = $options{ bot_name };
        $env{ GIT_COMMITTER_EMAIL } = $options{ bot_email };
    }

    return %env;
}

# options to QtQA::Gerrit::review which map directly to options to
# "ssh <somegerrit> gerrit review ..."
my %GERRIT_REVIEW_OPTIONS = (
    abandon => { type => BOOLEAN, default => 0 },
    message => { type => SCALAR, default => undef },
    project => { type => SCALAR, default => undef },
    restore => { type => BOOLEAN, default => 0 },
    stage => { type => BOOLEAN, default => 0 },
    submit => { type => BOOLEAN, default => 0 },
    (map { $_ => { regex => qr{^[-+]?\d+$}, default => undef } } qw(
        code_review
        sanity_review
        verified
    ))
);

sub review
{
    my $commit_or_change = shift;
    my (%options) = validate(
        @_,
        {
            url => 1,
            on_success => { type => CODEREF, default => undef },
            on_error => { type => CODEREF, default =>
                sub {
                    my ($c, @rest) = @_;
                    warn __PACKAGE__."::review: error (for $c): ", @rest;
                }
            },
            %GERRIT_REVIEW_OPTIONS,
        }
    );

    my $parsed_url = _gerrit_parse_url( $options{ url } );
    my @cmd = (
        @{ $parsed_url->{ cmd } },
        'review',
        $commit_or_change,
    );

    # project can be filled in by explicit 'project' argument, or from URL, or left blank
    $options{ project } ||= $parsed_url->{ project };

    while (my ($key, $spec) = each %GERRIT_REVIEW_OPTIONS) {
        my $value = $options{ $key };

        # code_review -> --code-review
        my $cmd_key = $key;
        $cmd_key =~ s{_}{-}g;
        $cmd_key = "--$cmd_key";

        if ($spec->{ type } && $spec->{ type } eq BOOLEAN) {
            if ($value) {
                push @cmd, $cmd_key;
            }
        } elsif (defined($value)) {
            push @cmd, $cmd_key, _quote_gerrit_arg( $value );
        }
    }

    my $cv = QtQA::AnyEvent::Util::run_cmd(
        \@cmd,
        retry => 1,
    );

    my $cmdstr;
    {
        local $LIST_SEPARATOR = '] [';
        $cmdstr = "[@cmd]";
    }

    $cv->cb(sub {
        my $status = shift->recv();
        if ($status && $options{ on_error }) {
            $options{ on_error }->( $commit_or_change, "$cmdstr exited with status $status" );
        }
        if (!$status && $options{ on_success }) {
            $options{ on_success }->( $commit_or_change );
        }
        # make sure we stay alive until this callback is executed
        undef $cv;
    });

    return;
}

# parses a gerrit URL and returns a hashref with following keys:
#   cmd => arrayref, base ssh command for interacting with gerrit
#   project => the gerrit project name (e.g. "qtqa/testconfig")
sub _gerrit_parse_url
{
    my ($url) = @_;

    if (!ref($url) || !$url->isa( 'URI' )) {
        $url = URI->new( $url );
    }

    if ($url->scheme() ne 'ssh') {
        croak "gerrit URL $url is not supported; only ssh URLs are supported\n";
    }

    my $project = $url->path();
    # remove useless leading/trailing components
    $project =~ s{\A/+}{};
    $project =~ s{\.git\z}{}i;

    return {
        cmd => [
            'ssh',
            '-oBatchMode=yes',          # never do interactive prompts
            '-oServerAliveInterval=30', # try to avoid the server silently dropping connection
            ($url->port() ? ('-p', $url->port()) : ()),
            ($url->user() ? ($url->user() . '@') : q{}) . $url->host(),
            'gerrit',
        ],
        project => $project,
    };
}

# quotes an argument to be passed to gerrit, if necessary.
sub _quote_gerrit_arg
{
    my ($string) = @_;
    if ($string !~ m{ }) {
        return $string;
    }
    $string =~ s{'}{}g;
    return qq{'$string'};
}

=head1 NAME

QtQA::Gerrit - interact with Gerrit code review tool

=head1 SYNOPSIS

  use AnyEvent;
  use QtQA::Gerrit qw(stream_events);

  # alert me when new patch sets arrive in ssh://codereview.qt-project.org:29418/qt/myproject
  my $stream = stream_events(
    url => 'ssh://codereview.qt-project.org:29418/',
    on_event => sub {
      my (undef, $event) = @_;
      if ($event->{type} eq 'patchset-added' && $event->{change}{project} eq 'qt/myproject') {
        system("xmessage", "New patch set arrived!");
      }
    }
  );

  AE::cv()->recv(); # must run an event loop for callbacks to be activated

This module provides some utility functions for interacting with the Gerrit code review tool.

This module is an L<AnyEvent> user and may be used with any event loop supported by AnyEvent.

=head1 METHODS

=over

=item B<stream_events> url => $gerrit_url

Connect to "gerrit stream-events" on the given gerrit host and register one or more callbacks
for events. Returns an opaque handle to the stream-events connection; the connection will be
aborted if the handle is destroyed.

$gerrit_url should be a URL with ssh schema referring to a valid Gerrit installation
(e.g. "ssh://user@gerrit.example.com:29418/").

Supported callbacks are documented below. All callbacks receive the stream-events
handle as their first argument.

=over

=item on_event => $cb->($handle, $data)

Called when an event has been received.
$data is a reference to a hash representing the event.

See the Gerrit documentation for information on the possible events:
L<http://gerrit.googlecode.com/svn/documentation/2.2.1/cmd-stream-events.html>

=item on_error => $cb->($handle, $error)

Called when an error occurs in the connection.
$error is a human-readable string.

Examples of errors include network disruptions between your host and the Gerrit server,
or the ssh process being killed unexpectedly. Receiving any kind of error means that
some Gerrit events may be lost.

If this callback returns a true value, stream_events will attempt to reconnect
to Gerrit and resume processing; otherwise, the connection is terminated and no more
events will occur.

The default error callback will warn and return 1, retrying on all errors.

=back

=item B<review> $commit_or_change, url => $gerrit_url, ...

Wrapper for the `gerrit review' command; add a comment and/or update the status
of a change in gerrit.

$commit_or_change is mandatory, and is either a git commit (in abbreviated or
full 40-digit form), or a gerrit change number and patch set separated by a comment
(e.g. 3404,3 refers to patch set 3 of the gerrit change accessible at
http://gerrit.example.com/3404). The latter form is deprecated and may be removed in
some version of gerrit.

$gerrit_url is also mandatory and should be a URL with ssh schema referring to a
valid Gerrit installation (e.g. "ssh://user@gerrit.example.com:29418/").
The URL may optionally contain the relevant gerrit project.

All other arguments are optional, and include:

=over

=item on_success => $cb->( $commit_or_change )

=item on_error => $cb->( $commit_or_change, $error )

Callbacks invoked when the operation succeeds or fails.

=item abandon => 1|0

=item message => $string

=item project => $string

=item restore => 1|0

=item stage => 1|0

=item submit => 1|0

=item code_review => $number

=item sanity_review => $number

=item verified => $number

These options are passed to the `gerrit review' command.
For information on their usage, please see the output of `gerrit review --help'
on your gerrit installation, or see documentation at
http://gerrit.googlecode.com/svn/documentation/2.2.1/cmd-review.html

Note that certain options can be disabled on a per-site basis.
`gerrit review --help' will show only those options which are enabled on the given site.

=back

=item B<random_change_id>

Returns a random Change-Id (the character 'I' followed by 40 hexadecimal digits),
suitable for usage as the Change-Id field in a commit to be pushed to gerrit.

=item B<next_change_id>

Returns the 'next' Change-Id which should be used for a commit created by the current
git author/committer (which should be set by L<git_environment> prior to calling this
method). The current working directory must be within a git repository.

This method is suitable for usage within a script which periodically creates commits
for review, but should have only one outstanding review (per branch) at any given time.
The returned Change-Id is (hopefully) unique, and stable; it only changes when a new
commit arrives in the git repository from the current script.

For example, consider a script which is run once per day to clone a repository,
generate a change and push it for review. If this function is used to generate the
Change-Id on the commit, the script will update the same change in gerrit until that
change is merged. Once the change is merged, next_change_id returns a different value,
resulting in a new change.  This ensures the script has a maximum of one pending review
any given time.

If any problems occur while determining the next Change-Id, a warning is printed and
a random Change-Id is returned.

=item B<git_environment>( bot_name => $name, bot_email => $email, author_only => [0|1] )

Returns a copy of %ENV modified suitably for the creation of git commits by a script/bot.

Options:

=over

=item bot_name

The human-readable name of the bot.  Mandatory.

=item bot_email

The email address of the bot.  Defaults to noreply@qt-project.org.

=item author_only

If 1, the environment is only modified for the git I<author>, and not the git I<committer>.
Depending on the gerrit setup, this may be required to avoid complaints about missing
"Forge Identity" permissions.

Defaults to 0.

=back

When generating commits for review in gerrit, this method may be used in conjunction
with L<next_change_id> to ensure this bot has only one outstanding change for review
at any time, as in the following example:

    local %ENV = git_environment(
        bot_name => 'Qt Indent Bot',
        bot_email => 'indent-bot@qt-project.org',
    );

    # fix up indenting in all the .cpp files
    (system('indent *.cpp') == 0) || die 'indent failed';

    # then commit and push them;
    # commits are authored and committed by 'Qt Indent Bot <indent-bot@qt-project.org>'.
    # usage of next_change_id() ensures that this bot has a maximum of one outstanding
    # change for review
    my $message = "Fixed indentation\n\nChange-Id: ".next_change_id();
    (system('git add -u *.cpp') == 0) || die 'git add failed';
    (system('git', 'commit', '-m', $message) == 0) || die "git commit failed";
    (system('git push gerrit HEAD:refs/for/master') == 0) || die "git push failed";

=back

=cut

1;
