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

use strict;
use warnings;
use v5.10;

=head1 NAME

testconfig_enforcer - set Qt CI test configurations enforcing when appropriate

=head1 SYNOPSIS

  # from a daily cron job, or similar...
  ./testconfig_enforcer.pl --testconfig-path [path to local qtqa/testconfig]

Check the latest test results on testresults.qt.io, cross-reference
with the settings in the testconfig repository, and push a commit removing
any appropriate `forcesuccess' or `*insignificant*' properties.

=head2 OPTIONS

=over

=item --testconfig-path PATH

Path to a local clone of the qtqa/testconfig repository.
This must exist prior to running the script.

=item --no-update

If set, do not attempt to update the local testconfig clone to the newest
version.

=item --dry-run

If set, use `--dry-run' when performing the git push to gerrit; in other words,
the commit is not actually pushed. A `git log' in the local testconfig repository
will show what would have been pushed.

=item --reviewer <reviewer1> [ --reviewer <reviewer2> ... ]

=item -r <reviewer1> [ -r <reviewer2> ... ]

Add the named reviewer(s) to the change in gerrit.
Reviewers may be specified by email address or username.

=item --random

Randomly remove some properties regardless of the test results.

For testing purposes only (i.e. to make it likely that the script will decide
to do something, since the stable state is always that there is nothing to do).

=item --author-only

When creating the git commit, only set the git author field to this script's
identity; don't set the git committer field.

Use this if pushing to gerrit fails due to missing "forge identity" permissions.

=item --man

Show extended documentation (man page).

=back

=head1 DESCRIPTION

When introducing new test configurations into the Qt Project CI system, the
standard practice is to first introduce the configurations in a non-enforcing
mode, then progressively set configurations enforcing for each project as they
are verified passing. The latter can be partially automated by this script,
which performs roughly the following steps:

=over

=item *

updates the qtqa/testconfig repository to the latest version

=item *

enumerates all properties under qtqa/testconfig which represent a non-enforcing
(or partially non-enforcing) test configuration - e.g. forcesuccess, qt.tests.insignificant

=item *

for each non-enforcing test configuration, the latest successful test log is downloaded
from testresults.qt.io and scanned; if the log indicates that the test
configuration would pass if it were enforcing, the appropriate files are removed from
the local copy of qtqa/testconfig

=item *

local changes to qtqa/testconfig are committed and pushed to gerrit for review

=back

The script attempts to re-use the same Change-Id for each commit until that commit
is accepted; for example, if run daily and nobody reviews the generated commits
for three days, there will be one change with three patch sets rather than three
changes.

=cut

package QtQA::QtTestconfigEnforcer;

use Const::Fast;
use English qw(-no_match_vars);
use File::Basename;
use File::Find::Rule;
use File::chdir;
use Getopt::Long qw(GetOptionsFromArray);
use LWP::UserAgent::Determined;
use Memoize;
use Pod::Usage;
use Text::Wrap;
use autodie;

use FindBin;
use lib "$FindBin::Bin/../lib/perl5";

use QtQA::Gerrit;

const my $CI_BASE_URL => 'http://testresults.qt.io/ci';

const my $BOT_NAME => 'Qt Testconfig Enforcer Bot';

const my @UNDESIRABLES => qw(
    forcesuccess
    qt.tests.insignificant
    qt.qtqa-tests.insignificant
);

const my $MAGIC_REMOVE_PATTERN => qr{This may indicate it is safe to remove ["']?([a-zA-Z0-9\-_\.]+)["']?\.};

const my $GERRIT_SERVER => 'codereview.qt-project.org';
const my $GERRIT_PORT => 29418;
const my $GERRIT_PROJECT => 'qtqa/testconfig';
const my $GERRIT_URL => "ssh://$GERRIT_SERVER:$GERRIT_PORT/$GERRIT_PROJECT";
const my $GERRIT_SRC_REF => 'refs/heads/master';
const my $GERRIT_DEST_REF => 'refs/for/master';

my $RAND = 0;

# system(), but die on failure
sub exe
{
    my (@cmd) = @_;
    system( @cmd );
    if ($? != 0) {
        die "@cmd exited with status $?";
    }
}

# Returns all files which need to be checked for deletion
sub find_files_to_check
{
    return File::Find::Rule
        ->file( )
        ->name( @UNDESIRABLES )
        ->in( 'projects' );
}

# Given a property filename, returns a tuple of
# ($project, $stage, $property)
sub parse_filename
{
    my ($file) = @_;
    return unless $file =~ m{
        projects/
        ([^/]+)
        /stages/
        ([^/]+)
        /(?:properties/)?
        ([^/]+)
        \z
    }xms;

    return ($1, $2, $3);
}

# Returns the URL of the latest successful build of a given project and stage
sub latest_log_url
{
    my ($project, $stage) = @_;
    return "$CI_BASE_URL/$project/latest-success/$stage/log.txt.gz";
}

# Return content of the given $url, or an empty string if the resource
# doesn't exist (e.g. a test configuration which has never been executed)
sub get_content_from_url
{
    my ($url) = @_;
    my $browser = LWP::UserAgent::Determined->new( );
    my $response = $browser->get( $url );
    if ($response->is_success) {
        return $response->decoded_content;
    } elsif ($response->code( ) == 404) {
        # Treat 404 non-fatal, it generally means the stage hasn't been run yet.
        return q{};
    } elsif ($response->code( ) == 403) {
        return q{};
    }
    die $response->decoded_content;
}

# Returns a set of all testconfig properties (basename only) which appear
# to be safely removable according to the log at $url.
# The returned set may include 'forcesuccess', although that is technically
# not a property.
sub removable_properties
{
    my ($url) = @_;
    my $data = get_content_from_url( $url );
    my %out;

    while ($data =~ m{$MAGIC_REMOVE_PATTERN}g) {
        ++$out{ $1 };
    }

    return %out;
}
# memoize to avoid needlessly fetching and scanning the log multiple times
memoize( 'removable_properties' );

# Calculates if the given property $file should be removed.
# If so, returns the URL used as evidence for removal of the file; otherwise,
# returns nothing.
# May fetch logs from testresults.
sub should_remove
{
    my ($file) = @_;
    my ($project, $stage, $key) = parse_filename( $file );

    if (!$key) {
        # some uncheckable special case.
        return;
    }

    my $url = latest_log_url( $project, $stage );

    # for test purposes
    if ($RAND && int(rand(5)) == 1) {
        return $url;
    }

    my %removable = removable_properties( $url );
    if ($removable{ $key }) {
        return $url;
    }
    return;
}

# Given a list of files @to_check, checks them all and returns
# a hash of the form:
#   (
#       "url1" => [ "file1", "file2", ...],
#       "url2" => [ "file3", ... ],
#       ...
#   )
# ... where the returned filenames represent property files to be removed,
# and the returned URLs contain the evidence used to decide that they should
# be removed.
sub find_files_to_remove
{
    my (@to_check) = @_;
    my %logs;

    foreach my $file (@to_check) {
        {
            local $OUTPUT_AUTOFLUSH = 1;
            print "$file ... ";
        }
        if (my ($url) = should_remove( $file )) {
            print "can be removed :)\n";
            push @{ $logs{ $url } }, $file;
        } else {
            print "needs to stay for now :(\n";
        }
    }

    return %logs;
}

# Given output from find_files_to_remove,
# creates a git commit which removes said files,
# with a reasonable commit message.
#
# Returns a ($change_id, $sha1) tuple for the generated commit
# (which is guaranteed to be at HEAD when the function returns).
sub create_git_commit
{
    my (%to_remove) = @_;
    my %projects;

    my @all_files = map { @{$_} } values %to_remove;
    foreach my $file (@all_files) {
        exe( qw(git rm -f), $file );
        my ($project) = parse_filename( $file );
        # "QtBase_master_Integration" => "QtBase"
        ($project) = split(/_/, $project);
        ++$projects{ $project };
    }

    my @projects = sort keys %projects;

    # We say 'some configs' if there's more than one file removed.
    # If there's only one file removed, we try to get it directly in the summary,
    # e.g.
    #
    #  QtBase: set win32-msvc2010 enforcing
    #
    my $some_configs = 'some configs';
    my $these_are = 'These are';
    my $they_stay = 'they stay';
    if (@all_files == 1) {
        my (undef, $stage) = parse_filename( $all_files[0] );
        $some_configs = $stage;
        $some_configs =~ s/_/ /g;
        $these_are = 'This is';
        $they_stay = 'it stays';
    }

    local $LIST_SEPARATOR = ', ';
    my $message_summary = "@projects: set $some_configs enforcing";
    my $message_body = "$these_are passing. Make sure $they_stay that way.";

    if (length( $message_summary ) > 75) {
        # If we can't reasonably fit all affected projects into the oneline summary,
        # put them in the body instead.
        $message_summary = 'Set various configurations enforcing';
        local $Text::Wrap::columns = 75;
        $message_body = wrap(
            q{},
            q{},
            "These configs on @projects are passing. Make sure they stay that way."
        );
    }

    my $change_id = QtQA::Gerrit::next_change_id( );
    $message_body .= "\n\nChange-Id: $change_id";

    {
        no autodie qw(open);  # autodie open doesn't support |- by default
        open( my $fh, '|-', qw(git commit -F -) ) || die "open git commit: $!";
        print $fh "$message_summary\n\n$message_body";
        close( $fh ) || die "close git commit: $! ($?)";
    }

    my $sha1 = qx(git rev-parse HEAD);
    chomp $sha1;

    return ($change_id, $sha1);
}

# Add a message to the commit $sha1 in gerrit.
# The message will advise the approver(s) to check all relevant logs
# (according to the values in %removed) before accepting the change.
#
# This is important because some test configurations which were passing
# at the time the commit was generated might become failing by the time
# the commit is reviewed.
sub add_gerrit_message
{
    my ($sha1, %removed) = @_;
    my $message = "Before submitting, please check these logs:";

    while (my ($url, $files_ref) = each %removed) {
        local $LIST_SEPARATOR = ', ';
        my @properties = map { basename($_) } @{ $files_ref };
        $message .= "\n\n* $url (@properties)";
    }

    my $cv = AE::cv();
    QtQA::Gerrit::review(
        $sha1,
        url => $GERRIT_URL,
        message => $message,
        project => $GERRIT_PROJECT,
        on_success => sub { $cv->send() },
        on_error => sub { $cv->croak(@_) },
    );
    $cv->recv();

    return;
}

sub new
{
    my ($self, @args) = @_;
    my $out = bless {
        update => 1,
    }, $self;

    GetOptionsFromArray( \@args,
        'h|help|?' => sub { pod2usage(1) },
        'man' => sub { pod2usage(-verbose => 2) },
        'testconfig-path=s' => \$out->{ testconfig_path },
        'author-only' => \$out->{ author_only },
        'update!' => \$out->{ update },
        'dry-run' => \$out->{ dry_run },
        'r|reviewer=s@' => \$out->{ reviewers },
        'random' => \$RAND,
    ) || die;

    if (!$out->{ testconfig_path }) {
        die 'missing mandatory --testconfig-path argument';
    }

    return $out;
}

sub run
{
    my ($self) = @_;
    local $CWD = $self->{ testconfig_path };
    local %ENV = QtQA::Gerrit::git_environment(
        bot_name => $BOT_NAME,
        author_only => $self->{ author_only },
    );

    if ($self->{ update }) {
        exe( qw(git fetch), $GERRIT_URL, $GERRIT_SRC_REF );
        exe( qw(git reset --hard FETCH_HEAD) );
    }

    my @to_check = find_files_to_check( );
    my %to_remove = find_files_to_remove( @to_check );

    if (!%to_remove) {
        print "Nothing to be done.\n";
        return;
    }

    my ($change_id, $sha1) = create_git_commit( %to_remove );

    my @git_push = (
        qw(git push --verbose),
        $self->{ dry_run } ? '--dry-run' : (),
    );

    if (my @reviewers = @{ $self->{ reviewers } || [] }) {
        push @git_push, "--receive-pack=git receive-pack ".join(' ', map { "--reviewer=$_" } @reviewers);
    }

    push @git_push, (
        $GERRIT_URL,
        "HEAD:$GERRIT_DEST_REF",
    );

    {
        local $LIST_SEPARATOR = '] [';
        print "Running: [@git_push]\n";
    }

    exe( @git_push );

    if (!$self->{ dry_run }) {
        add_gerrit_message( $sha1, %to_remove );
    }

    return;
}

QtQA::QtTestconfigEnforcer->new( @ARGV )->run( ) unless caller;
1;
