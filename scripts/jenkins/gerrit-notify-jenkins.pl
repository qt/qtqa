#!/usr/bin/env perl
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

=head1 NAME

gerrit-notify-jenkins.pl - notify Jenkins about Gerrit updates, without polling

=head1 SYNOPSIS

  ./gerrit-notify-jenkins.pl \
    --gerrit-url ssh://gerrit.example.com:29418/ \
    --jenkins-url http://jenkins.example.com/jenkins

Connects to 'gerrit stream-events' on gerrit.example.com port 29418 and invokes
the git SCM plugin's notifyCommit URL on jenkins.example.com each time a ref
is updated.

This script runs an infinite loop and will attempt to re-connect to gerrit any
time an error occurs.

Logging of this script may be configured by the PERL_ANYEVENT_VERBOSE and
PERL_ANYEVENT_LOG environment variables (see 'perldoc AnyEvent::Log')

=head2 OPTIONS

=over

=item --gerrit-url <URL>

The ssh URL for gerrit.

It must be possible to invoke 'gerrit stream-events' over ssh to this host and port.

=item --jenkins-url <URL>

Base URL of Jenkins.

=back

=head2 NOTIFIED URLS

The Jenkins notifyCommit mechanism expects the following URL to be activated when
changes occur to some relevant git repository:

  <jenkins_url>/git/notifyCommit?url=<git_url>

However, there are many possible URLs referring to the same git repository;
for example, an ssh URL with or without hostname, or a URL using an alias set up
in .ssh/config or .gitconfig, or http vs https vs ssh URLs for the same repository.

This script has no way of knowing which git URLs are being tracked by Jenkins.
Therefore, it notifies of all commonly used git URL styles for gerrit, including:

  ssh://<gerrit_host>:<gerrit_port>/<gerrit_project>
  ssh://<gerrit_host>:<gerrit_port>/<gerrit_project>.git
  ssh://<gerrit_host>/<gerrit_project>
  ssh://<gerrit_host>/<gerrit_project>.git
  http://<gerrit_host>/p/<gerrit_project>
  http://<gerrit_host>/p/<gerrit_project>.git
  https://<gerrit_host>/p/<gerrit_project>
  https://<gerrit_host>/p/<gerrit_project>.git

Apart from the minor additional network traffic, it is harmless to notify for
unused git URLs.

If the notifications appear to be not working, check that the relevant Jenkins
projects are using a URL matching one of the above forms.

=head2 JENKINS SETUP

Jenkins must be set up using the Git SCM plugin (at least version 1.1.14) and
SCM polling must be enabled. The notification mechanism works by activating the
polling, so it won't do anything if polling is disabled. Of course, the poll
frequency should be low, otherwise there is little benefit from using this script.

It is recommended not to rely on this script as the sole mechanism for triggering
Jenkins builds, since it is always possible for events to be lost (e.g. if the
connection to gerrit or Jenkins is temporarily interrupted). A poll schedule
like the following is a good compromise:

  H */2 * * *

This will cause Jenkins to poll the repository once every two hours (at a random
minute of the hour). Therefore, in the unusual case of events being lost, Jenkins
would still determine that a change has occurred within a maximum of two hours.

=cut

package QtQA::App::GerritNotifyJenkins;
use strict;
use warnings;

use AnyEvent::HTTP;
use AnyEvent::Handle;
use AnyEvent::Util;
use Coro::AnyEvent;
use Coro;
use Data::Dumper;
use English qw( -no_match_vars );
use File::Spec::Functions;
use FindBin;
use Getopt::Long qw( GetOptionsFromArray );
use Pod::Usage;
use URI;

use lib catfile( $FindBin::Bin, qw(.. lib perl5) );
use QtQA::Gerrit;

# Given a gerrit $project (e.g. 'qt/qtbase'), returns a list of all git URLs commonly
# used to refer to that project (e.g. ssh with port number, ssh without port number,
# http, https, ...)
sub generate_urls
{
    my ($self, $project) = @_;

    my $base = URI->new( $self->{ gerrit_url } );

    my @out;

    # ssh without port
    push @out, 'ssh://' . $base->host() . $base->path() . "/$project";

    # ssh with port
    if ($base->port()) {
        push @out, 'ssh://' . $base->host() . ':' . $base->port() . $base->path() . "/$project";
    }

    # http
    push @out, 'http://' . $base->host() . $base->path() . '/p/' . $project;

    # https
    push @out, 'https://' . $base->host() . $base->path() . '/p/' . $project;

    @out = (
        @out,
        map { "$_.git" } @out,
    );

    return @out;
}

# Try hard to do a successful http_get to $url.
#
# Most kinds of errors will cause the request to be retried, repeatedly.
# Will eventually die if not successful.
#
# Blocking; expected to be called from within a coro.
#
sub robust_http_get
{
    my ($url) = @_;

    my $MAX_ATTEMPTS = 8;
    my $MAX_SLEEP = 60;

    my $attempt = 1;
    my $sleep = 2;

    while (1) {
        http_get( $url, Coro::rouse_cb() );
        my (undef, $headers) = Coro::rouse_wait();
        if ($headers->{ Status } =~ m{^2}) {
            # success!
            last;
        }

        my $error = "[attempt $attempt]: $headers->{ Status } $headers->{ Reason }";
        ++$attempt;

        if ($attempt > $MAX_ATTEMPTS) {
            die "failed after repeated attempts. Last error: $error\n";
        }

        AE::log(warn => "$error, trying again in $sleep seconds");

        Coro::AnyEvent::sleep( $sleep );

        $sleep *= 2;
        if ($sleep > $MAX_SLEEP) {
            $sleep = $MAX_SLEEP;
        }
    }

    return;
}

# Notify Jenkins of updates to $project.
#
# This will (asychronously) hit all URLs returned by generate_urls.
#
sub do_notify_commit
{
    my ($self, $project) = @_;

    my @gerrit_urls = $self->generate_urls( $project );
    my $notify_commit_url = URI->new( $self->{ jenkins_url } . '/git/notifyCommit' );

    # spawn all HTTP requests async, don't bother waiting for them
    foreach my $gerrit_url (@gerrit_urls) {
        async {
            my $url = $notify_commit_url->clone();
            $url->query_form( url => $gerrit_url );

            eval {
                robust_http_get( $url->as_string() );
            };
            if (my $error = $EVAL_ERROR) {
                AE::log(warn => "notify to $url failed: $error\n");
            } else {
                AE::log(debug => "notified $url");
            }
        }
    }

    return;
}

# Process an $event seen from gerrit stream-events.
#
# The $event has already been parsed from JSON into perl data (a hashref is expected).
#
sub handle_event
{
    my ($self, $event) = @_;

    # only hashes are expected
    if (ref($event) ne 'HASH') {
        AE::log(warn => 'unexpected gerrit event: ' . Dumper( $event ) . "\n");
        return;
    }

    # ref-updated is the only interesting event for us
    if ($event->{ type } ne 'ref-updated') {
        return;
    }

    my $project = $event->{ refUpdate }{ project };
    my $ref = $event->{ refUpdate }{ refName };

    AE::log(debug => "$ref updated on $project, spawning notifyCommit");

    $self->do_notify_commit( $project );

    return;
}

# Main loop.
#
# Connect to gerrit stream-events and process the events.
#
# This should never exit. It will repeatedly re-connect to gerrit if the connection is disrupted.
sub do_stream_events
{
    my ($self) = @_;

    my $watcher = QtQA::Gerrit::stream_events(
        url => $self->{ gerrit_url },
        on_event => sub {
            my (undef, $data) = @_;
            $self->handle_event( $data );
        },
    );

    # In normal usage, this is the only output.
    # This is just to give some confidence to the user that we're doing anything at all...
    print "Entering main loop.\n";

    AE::cv()->recv();

    AE::log(error => 'internal error: main loop unexpectedly finished');
    return;
}

# Entry point.
sub run
{
    my ($self, @args) = @_;

    GetOptionsFromArray(
        \@args,
        'help|h' => sub { pod2usage(2) },
        'gerrit-url=s' => \$self->{ gerrit_url },
        'jenkins-url=s' => \$self->{ jenkins_url },
    ) || die $!;

    if (!$self->{ gerrit_url }) {
        die "Missing mandatory --gerrit-url argument\n";
    }
    $self->{ gerrit_url } =~ s{/+\z}{};

    if (!$self->{ jenkins_url }) {
        die "Missing mandatory --jenkins-url argument\n";
    }
    $self->{ jenkins_url } =~ s{/+\z}{};

    local $OUTPUT_AUTOFLUSH = 1;

    $self->do_stream_events();

    return;
}

sub new
{
    my ($class) = @_;
    return bless {}, $class;
}


QtQA::App::GerritNotifyJenkins->new( )->run( @ARGV ) unless caller;
1;
