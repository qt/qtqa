#!/usr/bin/env perl
#############################################################################
##
## Copyright (C) 2017 The Qt Company Ltd and/or its subsidiary(-ies).
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
use 5.010;
use strict;
use warnings;

=head1 NAME

10-git-qtqa-combine.t - basic git-qtqa-combine test

=cut

use English qw(-no_match_vars);
use File::Spec::Functions;
use File::Temp qw(tempdir);
use File::chdir;
use FindBin;
use Readonly;
use Test::More;
use autodie;

use lib "$FindBin::Bin/../../lib/perl5";

Readonly my $GIT_COMBINE => catfile( $FindBin::Bin, '..', 'git-qtqa-combine' );

# Like system(), but die on failure.
sub system_or_die
{
    my (@cmd) = @_;
    if (system( @cmd ) != 0) {
        die "@cmd exited with status $?";
    }
}

# Create an empty file with the given $filename, if it does not yet exist.
sub touch
{
    my ($filename) = @_;
    open( my $fh, '>>', $filename );
    close( $fh );
    return;
}

# Given a $ref and (optional) $dir, returns the SHA1 of that $ref.
# $dir defaults to '.' if omitted.
sub get_ref
{
    my ($ref, $dir) = @_;
    if (!$dir) {
        $dir = '.';
    }

    local $CWD = $dir;

    my $commit = qx(git rev-parse "$ref");
    ($? == 0) || die;

    chomp $commit;
    return $commit;
}

# Given a $rev (ref or SHA1), returns a list of parent commits of that revision.
sub get_parent_commits
{
    my ($rev) = @_;

    my $out = qx(git log -n1 "$rev" --format=format:%P);
    ($? == 0) || die;

    chomp $out;
    my @parents = split( /\s/, $out );
    return @parents;
}

# Creates a git repo and populates some refs.
# Takes the following named arguments:
#
#  dir => the directory where the repo shall be created.
#  refs => a hashref with git ref names as keys, and
#          arrayrefs containing filenames to create as values.
#
# All created files are empty.
sub make_git_repo
{
    my (%args) = @_;

    my $dir = $args{ dir };
    my %refs = %{ $args{ refs } || {} };

    system_or_die( 'git', 'init', '--quiet', $dir );

    local $CWD = $dir;

    # Allow pushing to checked out branch
    system_or_die( 'git', 'config', 'receive.denyCurrentBranch', 'ignore' );

    if (!%refs) {
        return;
    }

    # For simplicity, we always have one initial commit from which all others are descended.
    touch( 'dummy' );
    system_or_die( 'git', 'add', 'dummy' );
    system_or_die( 'git', 'commit', '--quiet', '-m', 'Initial commit' );

    my $initial_commit = get_ref( 'refs/heads/master' );

    my $last_ref;

    system_or_die( 'git', 'checkout', '--quiet', '-b', '_workbranch' );

    while (my ($ref, $files_arrayref) = each %refs) {
        my @files = @{ $files_arrayref };

        system_or_die( 'git', 'reset', '--quiet', '--hard', $initial_commit );
        system_or_die( 'git', 'rm', '--quiet', 'dummy' );
        foreach my $file (@files) {
            touch( $file );
        }
        system_or_die( 'git', 'add', @files );
        system_or_die( 'git', 'commit', '--quiet', '-m', 'Committed files' );
        my $commit = get_ref( 'refs/heads/_workbranch' );
        system_or_die( 'git', 'update-ref', $ref, $commit );

        $last_ref = $ref;
    }

    system_or_die( 'git', 'checkout', '--quiet', $last_ref );
    system_or_die( 'git', 'branch', '-D', '_workbranch' );

    if (!$refs{ 'refs/heads/master' }) {
        system_or_die( 'git', 'branch', '-D', 'master' );
    }

    return;
}

# Verify the state of a particular ref in a particular git repo.
# Takes an argument hash with the following keys:
#
#   dir => directory of the git repo (defaults to '.')
#   ref => git ref to check
#   testname => name of the test, for Test::More messages
#   expected_files => arrayref of expected files to be present
#                     when 'ref' is checked out
#   expected_parents => arrayref of expected parent SHA1s of 'ref'
#
sub verify_git_state
{
    my (%args) = @_;

    my $dir = $args{ dir } || '.';
    my $ref = $args{ 'ref' };
    my $testname = $args{ testname };
    my @expected_files = @{ $args{ expected_files } || [] };
    my @expected_parents = @{ $args{ expected_parents } || [] };

    local $CWD = $dir;

    system_or_die( qw(git reset --hard --quiet), $ref );

    my @files = sort glob '*';

    is_deeply(
        \@files,
        [ sort @expected_files ],
        "$testname: correct files exist"
    );

    my @parents = get_parent_commits( $ref );
    is_deeply(
        [ sort @parents ],
        [ sort @expected_parents ],
        "$testname: merge commit parents look correct"
    );

    return;
}

# Basic test combining three input repos into one output, then updating when
# one of the input repos is modified.
sub test_basic_combine
{
    local $CWD = tempdir( 'git-qtqa-combine.XXXXXX', TMPDIR => 1, CLEANUP => 1 );

    mkdir 'work';

    my @all_in = qw(in1 in2 in3);

    for my $in (@all_in) {
        make_git_repo(
            dir => $in,
            refs => {
                'refs/heads/master' => [ "file_from_$in" ],
            },
        );
    }
    make_git_repo( dir => 'out1' );

    my (@all_in_revs) = map { get_ref( 'refs/heads/master', $_ ) } @all_in;

    my @cmd = (
        $GIT_COMBINE,
        qw(--workdir work),
        map( { ('--in', "url=$CWD/$_", 'ref=refs/heads/master') } @all_in ),
        '--out', "url=$CWD/out1", 'ref=refs/heads/master',
    );

    is( system( @cmd ), 0, 'basic: exit code 0' );

    my %state = (
        dir => 'out1',
        'ref' => 'refs/heads/master',
        expected_files => [ map { "file_from_$_" } @all_in ],
        expected_parents => \@all_in_revs,
    );

    verify_git_state( testname => 'basic', %state );

    # Check that running again is a no-op
    is( system( @cmd ), 0, 'basic no-op: exit code 0' );
    verify_git_state( testname => 'basic no-op', %state );

    # Check that, if only one of the inputs now changes, the change is merged OK
    # and the merge commit only merges the new history.
    my $old_out_rev = get_ref( 'refs/heads/master', 'out1' );
    my $new_in2_rev;

    # Create a new commit in 'in2'; the file from in2 is renamed so we can tell if
    # the content change is correctly merged.
    {
        local $CWD = 'in2';
        system_or_die( 'git', 'checkout', '--quiet', 'master' );
        system_or_die( 'git', 'mv', 'file_from_in2', 'renamed_file_from_in2' );
        system_or_die( 'git', 'commit', '--quiet', '-m', 'Moved a file' );
        $new_in2_rev = get_ref( 'refs/heads/master' );
    }

    is( system( @cmd ), 0, 'basic update: exit code 0' );

    # file rename should be reflected in the update ...
    $state{ expected_files } = [ 'file_from_in1', 'renamed_file_from_in2', 'file_from_in3' ];
    # and the merge commit should only be merging the changed input repo into the output repo
    $state{ expected_parents } = [ $old_out_rev, $new_in2_rev ];
    verify_git_state( testname => 'basic update', %state );

    return;
}

# Test combining three input repositories into two output repositories in a few different
# ways, with a single command line and with usage of 'files' patterns.
sub test_multi_combine_with_files
{
    local $CWD = tempdir( 'git-qtqa-combine.XXXXXX', TMPDIR => 1, CLEANUP => 1 );

    mkdir 'work';

    my @all_in = qw(in1 in2 in3);
    my @all_out = qw(out1 out2);

    for my $in (@all_in) {
        make_git_repo(
            dir => $in,
            refs => {
                "refs/heads/$in" => [ "file_from_$in.txt", "file_from_$in.cpp" ],
                # Let in2 have a "master" branch, while the others don't.
                # This checks that having an unused master branch doesn't hurt, and
                # having no master branch also doesn't hurt.
                (($in eq 'in2') ? ("refs/heads/master" => [ "some_other_file.txt" ]) : ()),
            },
        );
    }
    for my $out (@all_out) {
        make_git_repo( dir => $out );
    }

    my ($in1_rev, $in2_rev, $in3_rev) = map { get_ref( "refs/heads/$_", $_ ) } @all_in;

    is(
        system(
            $GIT_COMBINE,
            qw(--workdir work),
            '--in',  "url=$CWD/in1",   'ref=refs/heads/in1', 'files=*.txt',
            '--in',  "url=$CWD/in2",   'ref=refs/heads/in2', 'files=*.cpp',
            '--out', "url=$CWD/out1",  'ref=refs/heads/one_txt_two_cpp',
            '--in',  "url=$CWD/in1",   'ref=refs/heads/in1', 'files=*.cpp',
            '--in',  "url=$CWD/in2",   'ref=refs/heads/in2', 'files=*.txt',
            '--out', "url=$CWD/out1",  'ref=refs/heads/one_cpp_two_txt',
            '--in',  "url=$CWD/in2",   'ref=refs/heads/in2', 'files=*.cpp',
            '--in',  "url=$CWD/in3",   'ref=refs/heads/in3', 'files=*.txt',
            '--out', "url=$CWD/out2",  'ref=refs/heads/two_cpp_three_txt',
        ),
        0,
        'multi: exit code 0'
    );

    verify_git_state(
        testname => 'multi one_txt_two_cpp',
        dir => 'out1',
        'ref' => 'refs/heads/one_txt_two_cpp',
        expected_files => [ 'file_from_in1.txt', 'file_from_in2.cpp' ],
        expected_parents => [ $in1_rev, $in2_rev ],
    );

    verify_git_state(
        testname => 'multi one_cpp_two_txt',
        dir => 'out1',
        'ref' => 'refs/heads/one_cpp_two_txt',
        expected_files => [ 'file_from_in1.cpp', 'file_from_in2.txt' ],
        expected_parents => [ $in1_rev, $in2_rev ],
    );

    verify_git_state(
        testname => 'multi two_cpp_three_txt',
        dir => 'out2',
        'ref' => 'refs/heads/two_cpp_three_txt',
        expected_files => [ 'file_from_in2.cpp', 'file_from_in3.txt' ],
        expected_parents => [ $in2_rev, $in3_rev ],
    );

    return;
}

# Test usage of the 'submodule' option
sub test_submodule_combine
{
    local $CWD = tempdir( 'git-qtqa-combine.XXXXXX', TMPDIR => 1, CLEANUP => 1 );

    mkdir 'work';

    foreach my $in (qw(in1 in2)) {
        make_git_repo(
            dir => $in,
            refs => {
                'refs/heads/master' => [ "file_from_$in" ],
            },
        );
    }
    make_git_repo(
        dir => 'sub',
        refs => {
            'refs/heads/master' => [ 'file_from_sub' ],
        },
    );

    # Let in2 have sub as a submodule.
    {
        local $CWD = 'in2';
        system_or_die( 'git', 'checkout', '--quiet', 'master' );
        system_or_die( 'git', 'submodule', 'add', "$CWD/../sub", 'sub' );
        system_or_die( 'git', 'commit', '-m', 'Added submodule' );
    }

    my ($in1_rev, $sub_rev) = map { get_ref( 'refs/heads/master', $_ ) } qw(in1 sub);

    make_git_repo( dir => 'out1' );

    my @cmd = (
        $GIT_COMBINE,
        qw(--workdir work),
        '--in',  "url=$CWD/in1", 'ref=refs/heads/master',
        '--in',  "url=$CWD/in2", 'ref=refs/heads/master', 'submodule=sub',
        '--out', "url=$CWD/out1", 'ref=refs/heads/master',
    );

    is( system( @cmd ), 0, 'submodule: exit code 0' );

    my %state = (
        dir => 'out1',
        'ref' => 'refs/heads/master',
        expected_files => [ 'file_from_in1', 'file_from_sub' ],
        expected_parents => [ $in1_rev, $sub_rev ],
    );

    verify_git_state( testname => 'submodule', %state );

    # Create a new commit in 'sub'
    my $new_sub_rev;
    {
        local $CWD = 'sub';
        system_or_die( 'git', 'checkout', '--quiet', 'master' );
        system_or_die( 'git', 'mv', 'file_from_sub', 'renamed_file_from_sub' );
        system_or_die( 'git', 'commit', '--quiet', '-m', 'Moved a file' );
        $new_sub_rev = get_ref( 'refs/heads/master' );
    }

    # Check that running again is a no-op; i.e. the new commit in 'sub' is _not_ taken,
    # because the parent repo wasn't updated.
    is( system( @cmd ), 0, 'submodule no-op: exit code 0' );
    verify_git_state( testname => 'submodule no-op', %state );

    my $old_out_rev = get_ref( 'refs/heads/master', 'out1' );

    # Now update submodule pointer
    {
        local $CWD = 'in2';
        {
            local $CWD = 'sub';
            system_or_die( 'git', 'fetch', '--quiet', "../../sub", 'refs/heads/master' );
            system_or_die( 'git', 'reset', '--hard', 'FETCH_HEAD' );
        }
        system_or_die( 'git', 'add', 'sub' );
        system_or_die( 'git', 'commit', '-m', 'Updated submodule.' );
    }

    is( system( @cmd ), 0, 'submodule update: exit code 0' );

    # file rename should be reflected in the update ...
    $state{ expected_files } = [ 'file_from_in1', 'renamed_file_from_sub' ];
    # and the merge commit should only be merging the changed input repo (submodule) into the output repo
    $state{ expected_parents } = [ $old_out_rev, $new_sub_rev ];
    verify_git_state( testname => 'basic update', %state );

    return;
}

sub run
{
    if ($OSNAME =~ m{win32}i) {
        plan skip_all => "git-qtqa-combine is not supported on $OSNAME";
    }

    # set a fake git user.name and user.email for the test;
    # the account under which this test is running might not
    # have any set
    local $ENV{ GIT_COMMITTER_NAME } = '10-git-qtqa-combine.t';
    local $ENV{ GIT_COMMITTER_EMAIL } = 'autotest@example.com';
    local $ENV{ GIT_AUTHOR_NAME } = $ENV{ GIT_COMMITTER_NAME };
    local $ENV{ GIT_AUTHOR_EMAIL } = $ENV{ GIT_COMMITTER_EMAIL };

    test_basic_combine;
    test_multi_combine_with_files;
    test_submodule_combine;
    done_testing;

    return;
}

run if (!caller);
1;

