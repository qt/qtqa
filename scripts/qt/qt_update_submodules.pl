#!/usr/bin/env perl
#############################################################################
##
## Copyright (C) 2012 Nokia Corporation and/or its subsidiary(-ies).
## Contact: http://www.qt-project.org/
##
## This file is part of the Quality Assurance module of the Qt Toolkit.
##
## $QT_BEGIN_LICENSE:LGPL$
## GNU Lesser General Public License Usage
## This file may be used under the terms of the GNU Lesser General Public
## License version 2.1 as published by the Free Software Foundation and
## appearing in the file LICENSE.LGPL included in the packaging of this
## file. Please review the following information to ensure the GNU Lesser
## General Public License version 2.1 requirements will be met:
## http://www.gnu.org/licenses/old-licenses/lgpl-2.1.html.
##
## In addition, as a special exception, Nokia gives you certain additional
## rights. These rights are described in the Nokia Qt LGPL Exception
## version 1.1, included in the file LGPL_EXCEPTION.txt in this package.
##
## GNU General Public License Usage
## Alternatively, this file may be used under the terms of the GNU General
## Public License version 3.0 as published by the Free Software Foundation
## and appearing in the file LICENSE.GPL included in the packaging of this
## file. Please review the following information to ensure the GNU General
## Public License version 3.0 requirements will be met:
## http://www.gnu.org/copyleft/gpl.html.
##
## Other Usage
## Alternatively, this file may be used in accordance with the terms and
## conditions contained in a signed written agreement between you and Nokia.
##
##
##
##
##
##
## $QT_END_LICENSE$
##
#############################################################################

use strict;
use warnings;
use v5.10;

use FindBin;
use lib "$FindBin::Bin/../lib/perl5";

package QtQA::QtUpdateSubmodules;
use base qw(QtQA::TestScript);

use Capture::Tiny qw( tee );
use Carp;
use English qw( -no_match_vars );
use File::Spec::Functions;
use Readonly;
use Text::Trim;
use autodie;

# All properties used by this script.
Readonly my @PROPERTIES => (
    q{base.dir}                => q{top-level source directory of Qt},

    q{location}                => q{location hint for git mirrors (`oslo' or `brisbane'); }
                                . q{only useful inside of Nokia LAN},

    q{qt.git.push}             => q{if 1, really push the commit (if any)},

    q{qt.git.push.dry-run}     => q{if 1, do a dry-run push (only used if qt.git.push is set)},

    q{qt.git.url}              => q{giturl of the repo to push to (only used if qt.git.push }
                                . q{is set)},

    q{qt.git.ref}              => q{the ref to push to (only used if qt.git.push is set)},

    q{qt.init-repository.args} => q{additional arguments for init-repository; e.g., use }
                                . q{-module-subset argument to only update a subset of modules},
);

# Map from submodule to the ref which should be tracked.
# When omitted, defaults to `refs/heads/master'.
Readonly my %SUBMODULE_TRACKING_REF => (
    qtquick3d   =>  'refs/heads/qml2',
);

# Author and committer to be used for commits by this script.
Readonly my $GIT_USER_NAME  => 'Qt Submodule Update Bot';
Readonly my $GIT_USER_EMAIL => 'qt_submodule_update_bot@ovi.com';

# Message to be used for commits by this script.
Readonly my $COMMIT_MESSAGE => 'Updated submodules.';

sub new
{
    my ($class, @args) = @_;

    my $self = $class->SUPER::new;

    $self->set_permitted_properties( @PROPERTIES );
    $self->get_options_from_array( \@args );

    bless $self, $class;
    return $self;
}

sub read_and_store_configuration
{
    my $self = shift;

    $self->read_and_store_properties(
        'base.dir'                => \&QtQA::TestScript::default_common_property,
        'location'                => \&QtQA::TestScript::default_common_property,
        'qt.git.push'             => 0,
        'qt.git.push.dry-run'     => 0,
        'qt.git.url'              => 'ssh://qt_submodule_update_bot@codereview.qt-project.org:29418/qt/qt5',
        'qt.git.ref'              => 'refs/for/master',
        'qt.init-repository.args' => q{},
    );

    return;
}

sub run
{
    my ($self) = @_;

    $self->read_and_store_configuration;
    $self->run_init_repository;
    $self->update_submodules;
    if ($self->git_commit && $self->{ 'qt.git.push' }) {
        $self->git_push;
    }
    $self->post_git_submodule_summary;

    return;
}

sub run_init_repository
{
    my ($self) = @_;

    my $base_dir = $self->{ 'base.dir' };
    my $location = $self->{ 'location' };
    my $args = $self->{ 'qt.init-repository.args' };

    chdir $base_dir;

    my @init_repository_arguments = ( '-force' );
    if (defined( $location ) && ($location eq 'brisbane')) {
        push @init_repository_arguments, '-brisbane-nokia-developer';
    }
    elsif (defined( $location )) {
        push @init_repository_arguments, '-nokia-developer';
    }

    push @init_repository_arguments, (split /\s+/, $args);

    $self->exe( 'perl', './init-repository', @init_repository_arguments );

    return;
}

# Returns 1 if a commit was done, 0 if there was nothing to do.
sub git_commit
{
    my ($self) = @_;

    my $base_dir = $self->{ 'base.dir' };

    # Did anything actually change?
    chdir $base_dir;
    eval { $self->exe( 'git diff-files --quiet' ) };
    if (!$@) {
        # If diff-files exits with 0 exit code, there is no diff.
        warn 'It seems like there are no changes to be made';
        return 0;
    };

    # Yes, there is a diff. Do the commit.
    # Ensure author, committer are set to the right values.
    local $ENV{ GIT_AUTHOR_NAME }     = $GIT_USER_NAME;
    local $ENV{ GIT_COMMITTER_NAME }  = $GIT_USER_NAME;
    local $ENV{ GIT_AUTHOR_EMAIL }    = $GIT_USER_EMAIL;
    local $ENV{ GIT_COMMITTER_EMAIL } = $GIT_USER_EMAIL;
    $self->exe(
        'git',
        'commit',
        '-m',
        $self->commit_message(),
        '--only',
        '--',
        $self->submodules()
    );

    return 1;
}

sub commit_message
{
    my ($self) = @_;

    return "$COMMIT_MESSAGE\n\nChange-Id: ".$self->change_id();
}

# Returns the Change-Id used for gerrit.
#
# Technically, the value here does not really matter.
# However, it is nice to use the same Change-Id for contiguous update attempts,
# if the previous update attempt failed.
#
# For example, consider this scenario:
#
#  - on Monday morning, this script attempts an update of qt5.git and pushes
#    it to gerrit.  It is staged, but rejected due to a regression.
#
#  - during the day, someone fixes the problem.
#
#  - on Tuesday morning, the script again attempts an update of qt5.git.
#
#    This time, it should succeed as the regression is allegedly fixed.
#
#    It is preferable to update the gerrit change from yesterday with a second
#    attempt (patch set 2), rather than creating a whole new gerrit change
#    (which would make the prior change useless and require someone to abandon
#    it).
#
# To accomplish this, the Change-Id is based on the SHA1 of the last successful
# update from this script.  Note there's a race condition: we could make use
# of a Change-Id which is in INTEGRATING state.  We choose not to care about
# this for now.
#
sub change_id
{
    my ($self) = @_;

    my $base_dir = $self->{ 'base.dir' };

    # Find the most recent commit from this author
    my $author = "$GIT_USER_NAME <$GIT_USER_EMAIL>";
    my ($change_id) = trim $self->exe_qx(
        'git',
        "--git-dir=$base_dir/.git",
        'rev-list',
        '-n1',
        '--fixed-strings',
        "--author=$author",
        'HEAD',
    );

    if (!$change_id) {
        warn "It seems like this repo currently has no commits from $author";

        # Use hash of this script for an arbitrary but stable Change-Id
        ($change_id) = trim $self->exe_qx( 'git', 'hash-object', '--', $0 );

        confess "Somehow failed to calculate any Change-Id" if (!$change_id);
    }

    # Check if we seem to have this change id already.
    # This can happen if an author other than ourself has already used the change id.
    my ($found) = trim $self->exe_qx(
        'git',
        "--git-dir=$base_dir/.git",
        'log',
        '-n1000',   # don't search too far
        "--grep=I$change_id",
        'HEAD',
    );

    if ($found) {
        warn "The desired Change-Id, I$change_id, is unexpectedly already used!\n"
            ."Falling back to a random Change-Id...\n";
        $change_id = $self->random_change_id( );
    }

    return "I$change_id";
}

# Returns a random change id, used as a last resort if none of the calculated change ids
# are available.
sub random_change_id
{
    my ($self) = @_;

    return sprintf(
        # 40 hex digits (32 bits gives 8 hex digits)
        "%08x" x 5,
        map { rand()*(2**32) } (1..5)
    );
}

# Push the current HEAD of base.dir to some repository.
sub git_push
{
    my ($self) = @_;

    my $base_dir            = $self->{ 'base.dir' };
    my $qt_git_url          = $self->{ 'qt.git.url' };
    my $qt_git_ref          = $self->{ 'qt.git.ref' };
    my $qt_git_push_dry_run = $self->{ 'qt.git.push.dry-run' };

    chdir $base_dir;

    my @cmd = qw(git push --verbose);

    if ($qt_git_push_dry_run) {
        warn 'qt.git.push.dry-run is set, so I am only pretending to push';
        push @cmd, '--dry-run';
    }

    push @cmd, $qt_git_url, "HEAD:$qt_git_ref";

    $self->exe( @cmd );

    return;
}

# Updates all submodules to their latest available SHA1.
# Note that this may change the SHA1 of the submodules, but won't add the
# changes to the index or create a commit.
sub update_submodules
{
    my ($self) = @_;

    foreach my $submodule ($self->submodules()) {
        $self->update_submodule( $submodule );
    }

    return;
}

# Updates the given $submodule to the latest available SHA1.
sub update_submodule
{
    my ($self, $submodule) = @_;

    my $base_dir = $self->{ 'base.dir' };

    my $ref = $SUBMODULE_TRACKING_REF{ $submodule } // 'refs/heads/master';

    # Note that we always use the giturl stored in .gitmodules, even though
    # init-repository may have used some other giturl.
    #
    # This is considered the canonical source for git module URLs.
    #
    # If we naively used whatever giturl init-repository had set up, we could
    # (for example) accidentally push some SHA1 which had been made available
    # on some local mirror but not yet pushed to gitorious.org.
    my @cmd      = ( qw(git config --file), "$base_dir/.gitmodules", "submodule.$submodule.url" );
    my ($giturl) = trim $self->exe_qx( @cmd );

    if (!$giturl) {
        confess "Command `@cmd' did not output a giturl";
    }

    chdir catfile($base_dir, $submodule);
    $self->exe( qw(git fetch --verbose), $giturl, "+$ref:refs/heads/updated_submodule" );

    # We will only allow fast-forwards in this automated process.
    # The reasoning is that, if someone has manually done some update other than
    # a fast-forward (e.g. temporarily setting some SHA1 from a particular bugfix branch),
    # they probably expect it to stay this way and not be automatically changed back.
    # However, we will warn about it.

    my ($head)      = trim $self->exe_qx( qw(git rev-parse --verify HEAD) );
    my ($updated)   = trim $self->exe_qx( qw(git rev-parse --verify updated_submodule) );
    my ($mergebase) = trim $self->exe_qx( qw(git merge-base), $head, $updated );

    # merge-base should always equal current HEAD if this is a fast-forward
    # (including the case where HEAD and updated_submodule are equal)
    if ($mergebase ne $head) {
        warn "Warning: will not update $submodule because the desired update is not fast-forward.\n"
            ."  current HEAD: $head\n"
            ."  updated HEAD: $updated\n"
            ."  from ref:     $ref\n"
            ."  from giturl:  $giturl\n";
        return;
    }

    $self->exe( qw(git reset --hard updated_submodule) );

    return;
}

# Returns a list of all submodules
sub submodules
{
    my ($self) = @_;

    if (! exists $self->{ submodules }) {

        # This method of listing the submodules may seem a little more complex than necessary,
        # but we are trying to:
        #
        #  - respect submodule's `foreach' API and not look into the implementation details
        #  - automatically ignore any unexpected extra STDOUT from `submodule foreach'
        #
        my ($output, undef) = tee {
            $self->exe( 'git', 'submodule', '--quiet', 'foreach', 'echo module: $name' );
        };

        foreach my $line (split /\n/, $output) {
            $line =~ qr{^module: (.+)$} or next;
            push @{$self->{ submodules }}, $1;
        }
    }

    return @{$self->{ submodules }};
}

# Given a giturl pointing to gerrit, decompose it into parts
sub gerrit_giturl_split
{
    my ($self, $giturl) = @_;

    my %out;

    if ($giturl =~ m{
        \A
        ssh://
        (?:
            ([\w\-]+) @     # optional username
        )?
        (
            [\w\-.]+        # hostname
        )
        (?:
            : (\d+)         # optional port number
        )?
        (?:
            /
            ( [\w\/]+? )    # project name, e.g. qt/qt5
            (?: \.git )?    # possible useless .git at the end
        )
        \z
    }xms) {
        %out = (
            user    =>  $1,
            host    =>  $2,
            port    =>  $3,
            project =>  $4,
        );
    }
    else {
        warn "Could not figure out gerrit details from giturl `$giturl'";
    }

    return %out;
}

# Assumes that HEAD is the commit we've just created
sub post_git_submodule_summary
{
    my ($self) = @_;

    my $qt_git_url          = $self->{ 'qt.git.url' };
    my $qt_git_push         = $self->{ 'qt.git.push' };
    my $qt_git_push_dry_run = $self->{ 'qt.git.push.dry-run' };

    my ($summary) = trim $self->exe_qx( qw(git submodule summary HEAD^) );

    print "Summary of changes:\n$summary\n";

    # Indent all text by two spaces, causing gerrit to consider it preformatted
    $summary = q{  }.join(qq{\n  }, split( qq{\n}, $summary ) );

    # Quote the text for posting to gerrit.
    # gerrit's quoting is quite bizarre.  This quoting should be unnecessary
    # since we are passing this as a separate argument anyway, but gerrit seems to
    # join all the arguments and parse them again, requiring double quoting.
    $summary =~ s{"}{}g;
    $summary = qq{"$summary"};


    my %gerrit = $self->gerrit_giturl_split( $qt_git_url );
    if (!$gerrit{ host }) {
        # not gerrit, nothing to be done
        return;
    }

    if (!$qt_git_push) {
        # didn't really push, nothing to be done
        return;
    };

    my ($head) = trim $self->exe_qx( qw(git rev-parse HEAD) );

    my @ssh_post_comment = (
        'ssh',
        '-oBatchMode=yes',

        $gerrit{ port }
            ? ('-p', $gerrit{ port })
            : ()
        ,

        $gerrit{ user }
            ? $gerrit{ user }.'@'.$gerrit{ host }
            : $gerrit{ host }
        ,

        'gerrit',
        'review',
        $head,
        '--message', $summary,
        '--project', $gerrit{ project },
        '--code-review', '0',
    );

    # dry run requested, just print what we would do
    if ($qt_git_push_dry_run) {
        warn 'qt.git.push.dry-run is set; if it were not, I would now run: '
            .join(' ', @ssh_post_comment);
        return;
    }

    $self->exe( @ssh_post_comment );

    return;
}

QtQA::QtUpdateSubmodules->new(@ARGV)->run unless caller;
1;

__END__

=head1 NAME

qt_update_submodules.pl - make a commit which updates all qt submodules

=head1 SYNOPSIS

  cd ~/path/to/qt5
  qtqa/qt_update_submodules.pl [options]

Creates a commit which updates all submodules of Qt, according to some
internally coded policy.

  qtqa/qt_update_submodules.pl --qt-git-push 1

Do the same, and attempt to really push the commit into Qt (e.g. via gerrit)

=head1 DESCRIPTION

Qt5 consists of many modules, and one "mother" repository (qt/qt5.git)
which contains references to each module.

In practice, we would like to keep the SHA1s used in this repo as up-to-date
as possible to some tracking branch for each module.  However, we also only
want qt/qt5.git to contain a combination of SHA1s which is known to work
together.  This script helps to facilitate such a setup.

The expected usage of this script is:

=over

=item *

Periodically (e.g. daily), this script is run on qt5.git.
It updates all submodules to the latest SHA1 for each tracked branch (typically
`master'), and pushes the change to gerrit.

=item *

In gerrit, a human does a brief sanity check of the update, and marks
it as approved for integration.

=item *

The CI system connected to gerrit tests the update.  If it passes, it's accepted.
If it fails, it's rejected.  A human is expected to analyze the failure and make
sure it's handled.  An example of a failure is a change to qtbase which does
not break any qtbase autotests, but breaks one qtdeclarative autotest.

=item *

The next day, this script is run again.  If the previous update attempt failed,
the change in gerrit will be updated with another attempt; otherwise, a new
change is created and the testing process starts over again.

=back


=cut
