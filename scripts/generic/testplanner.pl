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

use 5.010;
use strict;
use warnings;

package QtQA::App::TestPlanner;

=head1 NAME

testplanner - construct a test plan for a set of testcases

=head1 SYNOPSIS

  # Make a plan to run all available tests under this directory ...
  $ testplanner --input path/to/tests --output testplan.txt

  # Then run them all
  $ testscheduler --timeout 120 -j4 --sync-output --plan testplan.txt

testplanner will iterate through a build tree, collecting information
about autotests and preparing a test plan to be used by testrunner.

=head2 OPTIONS

=over

=item B<--input> PATH (mandatory)

Specifies the build tree from which a testplan should be created.

=item B<--output> PATH (mandatory)

Specifies the output test plan filename.

=item B<--make> MAKE

Customize the make command to be used for `make check'.
Defaults to `nmake' on Windows and `make' everywhere else.

=back

Further options may be passed to the testcases themselves.
These should be separated from testplanner options with a '--'.
For example:

  testplanner --input . --output plan.txt -- -silent -no-crash-handler

... to create a testplan which will run the tests with
"-silent -no-crash-handler" arguments.

=head1 DESCRIPTION

testplanner creates a testplan according to the contents of a given
build tree.

testplanner is primarily designed to work with qmake.

Any test which would be run by the `make check' command under the
build tree will be included in the test plan.  This is normally
achieved by using CONFIG+=testcase in a testcase .pro file.
Custom `check' targets may also be used, but these B<must> support
the $(TESTRUNNER) parameter to `make check' as CONFIG+=testcase does.

The precise output format of testplanner is undefined, but it
is plaintext and may be influenced by values from the buildsystem
such as:

=over

=item CONFIG+=insignificant_test

Indicates the result of the test can be ignored.

=item CONFIG+=parallel_test

Indicates the test is safe to run in parallel with other tests.

=item testcase.timeout=I<timeout>

The maximum permitted runtime of the test, in seconds.

=back



=cut

use Data::Dumper;
use English qw(-no_match_vars);
use Fcntl qw(LOCK_EX LOCK_UN SEEK_END);
use File::Basename;
use File::Spec::Functions qw(:ALL);
use File::chdir;
use Getopt::Long;
use IO::File;
use Lingua::EN::Inflect qw(inflect);
use List::MoreUtils qw(any apply all pairwise each_arrayref);
use Pod::Usage;
use QMake::Project;
use Readonly;
use Scalar::Defer qw(force);

use FindBin;
use lib "$FindBin::Bin/../lib/perl5";

use autodie;

Readonly my $WINDOWS => ($OSNAME =~ m{win32}i);

sub new
{
    my ($class) = @_;
    return bless {
        this_script => rel2abs( $0 ),
    }, $class;
}

sub run
{
    my ($self, @args) = @_;

    my $testcase;

    local @ARGV = @args;
    GetOptions(
        'help|?' => sub { pod2usage(0) },
        'input=s' => \$self->{ input },
        'output=s' => \$self->{ output },
        'make=s' => \$self->{ make },
        'makefile=s' => \$self->{ makefile },
        'testcase' => \$testcase,
    ) || pod2usage(2);

    # Testcase mode; we're calling ourselves for one specific testcase.
    # The remaining args are the testcase command and arguments.
    if ($testcase) {
        return $self->plan_testcase( @ARGV );
    }

    foreach my $arg (qw(input output)) {
        $self->{ $arg } || die "Missing mandatory --$arg argument";
    }

    # We can't safely handle arguments with spaces.
    # The processing of TESTARGS within the makefile depends on the exact
    # shell being used, which is generally quite difficult to determine
    # (e.g. mingw32-make uses sh.exe if it is in PATH, cmd.exe otherwise).
    # It's not impossible to support this, but we won't bother until
    # it becomes necessary.
    if (any { m{ } } @ARGV) {
        die 'sorry, it is currently not supported to pass arguments with '
           ."spaces while generating a test plan.\nYour arguments were:\n"
           .(join(' ', map { "[$_]" } @ARGV));
    }

    # We're going to pass output to subprocesses with a different
    # working directory, we'd better make it absolute
    $self->{ output } = rel2abs( $self->{ output } );

    # And also delete it if it currently exists
    if (-e $self->{ output }) {
        unlink( $self->{ output } );
    }

    if (!$self->{ make }) {
        $self->{ make } = $self->default_make( );
    }

    $self->run_make_check( @ARGV );
    $self->finalize_test_plan( $self->{ output } );

    return;
}

# finalize the test plan;
# this may modify the test plan slightly (e.g. changing some labels to ensure
# there are no duplicate testcase names).
sub finalize_test_plan
{
    my ($self, $filename) = @_;

    if (! -e $filename) {
        warn "No tests found under $self->{ input }\n";

        # No tests? make an empty testplan.
        open( my $fh, '>', $filename ) || die "open $filename for create: $!";
        close( $fh ) || die "close $filename after create: $!";

        return;
    }

    my @tests;
    my $count = 0;
    my $fh = IO::File->new( $filename, '<' ) || die "open $filename: $!";
    while (my $line = <$fh>) {
        ++$count;
        my $test = eval $line;  ## no critic (ProhibitStringyEval) - no way around it
        if (my $error = $@) {
            die "$filename:$count: error: $error";
        }
        push @tests, $test;
    }

    if ($self->ensure_distinct_labels( \@tests )) {
        # modified - have to write it back out again.
        open( my $fh, '>', $filename ) || die "open $filename for truncate: $!";
        close( $fh ) || die "close $filename after truncate: $!";
        $self->write_testcase( @tests );
    }

    print inflect "Test plan generated for NO(test,$count) at $filename\n";

    return;
}

# Ensures that all tests referred to by $all_tests_ref (arrayref) have a unique
# label.  Returns 1 if the labels had to be modified in order to achieve this.
#
# Currently the labels may be modified by finding the first unique word in a
# test's CWD and command combined.  For example, for these two tests:
#
#   /build/qtdeclarative/tests/auto/tst_examples/tst_examples
#   /build/qtquick1/tests/auto/tst_examples/tst_examples
#
# Their default label would be "tst_examples"; this function would amend them
# to "tst_examples (qtdeclarative)" and "tst_examples (qtquick1)".
#
sub ensure_distinct_labels
{
    my ($self, $all_tests_ref) = @_;

    my $modified = 0;

    # Build a map from each label to a list of tests with that label
    my %tests_by_label;
    foreach my $test (@{ $all_tests_ref }) {
        my $label = $test->{ label };
        push @{ $tests_by_label{ $label } }, $test;
    }

    while (my ($label, $tests_ref) = each %tests_by_label) {
        my @tests = @{ $tests_ref };
        next unless @tests > 1; # nothing to be done if already unique ...

        # found something not unique, we'll have to modify it.
        $modified = 1;

        # For each test, make a string containing that test's CWD and command/args.
        # There must be some difference in this value between the tests (otherwise
        # it is the same test!)
        #
        # Example:
        #   "/build/qtdeclarative/tests/auto/tst_examples ./tst_examples"
        #   "/build/qtquick1/tests/auto/tst_examples ./tst_examples"
        #
        my @cwd_and_args = map { join(' ', $_->{ cwd }, @{ $_->{ args }}) } @tests;

        # Find the first unique word from each CWD-and-args string.
        #
        # Example:
        #   ("qtdeclarative", "qtquick1")
        #
        my @words = $self->find_first_unique_word( @cwd_and_args );

        # append the unique words to the label.
        pairwise {
            # this line avoids "used only once: possible typo" warnings
            our ($a, $b);
            if ($b) {
                $a->{ label } .= " ($b)"
            }
        } @tests, @words;
    }

    return $modified;
}

# Given a list of @input strings, returns a list (of the same size) of output words.
# Each word is the first unique word from each string (where "word" is defined in
# the perl regular expression sense).
sub find_first_unique_word
{
    my ($self, @input) = @_;

    # Split on word boundaries, and also consume the non-word characters (e.g.
    # directory separators).
    # Conceptually, this gives us a two-dimensional array where the rows are input
    # strings and columns are individual words in that string.
    my @input_words = map { [
        split( /\W*\b\W*/, $_ )
    ] } @input;

    # Prepare output, initialized as a list of empty strings, already at the right size.
    my @output = (q{}) x (scalar(@input));

    # Iterate over each column in the array ...
    my $ea = each_arrayref @input_words;
    while (my @words = $ea->()) {

        # for each output not yet set ...
        for (my $i = 0; $i < @output; ++$i) {
            next if ($output[$i]);

            # if the word at this column is unique, set it as output.
            my $word = $words[$i];
            next unless $word;
            my $count = scalar( grep { $_ eq $word } @words );
            if ($count == 1) {
                $output[$i] = $word;
            }
        }

        # terminate if all output has been set.
        last if all { $_ } @output;
    }

    return @output;
}

sub default_make
{
    my ($self) = @_;

    if ($WINDOWS) {
        return 'nmake';
    }

    return 'make';
}

# Returns 'GNU', 'MS' or 'unknown' depending on the type of make
sub make_flavor
{
    my ($self) = @_;

    my $make = $self->{ make };

    if ($make =~ m{\bjom|\bnmake}i) {
        return 'MS';
    }
    if ($make =~ m{\bgmake|\bmake|\bmingw32-make}) {
        return 'GNU';
    }
    return 'unknown';
}

# Returns text usable within make to evaluate the current makefile.
sub makefile_var
{
    my ($self) = @_;

    if ($self->make_flavor( ) eq 'MS') {
        # FIXME: how to accurately figure out the calling Makefile on Windows?
        # We know $(MAKEDIR) points to the right directory, but the actual
        # filename appears not exposed in any way.
        #
        # Since there's no way to accurately determine it, we instead glob for
        # all "Makefile*", and decide ourselves which one is the right one
        # (e.g. discounting Makefile.Release and Makefile.Debug).
        #
        # Note that for nmake specifically, and not jom, it is necessary to
        # double-escape the variable ($$), otherwise it is evaluated too early.
        # It's not entirely clear why this is necessary for nmake and not for
        # other tools; the method which nmake uses to pass "TESTRUNNER" etc
        # args to submakes appears to be undocumented.
        my $out = '$(MAKEDIR)\Makefile*';
        if ($self->{ make } =~ m{\bnmake}i) {
            $out = '$'.$out;
        }
        return $out;
    }

    # $(CURDIR): initial working directory of make.
    # $(firstword $(MAKEFILE_LIST)): first processed Makefile.
    return '$(CURDIR)/$(firstword $(MAKEFILE_LIST))';
}

sub resolved_makefile
{
    my ($self) = @_;

    my $makefile = $self->{ makefile } || 'Makefile';

    # no globbing necessary on makefile flavors other than MS.
    if ($self->make_flavor() ne 'MS') {
        return $makefile;
    }

    my @globbed = glob $makefile;

    # Omit .Debug and .Release makefiles.  There should be a top-level makefile.
    @globbed = grep { $_ !~ m{\. (?:Debug|Release) \z}xms } @globbed;

    if (!@globbed) {
         die "In $CWD, no makefile found (looking for: $makefile)\n";
    }

    # If we found only one makefile, great!  That's the one.
    # This is the expected case, the vast majority of the time.
    if (@globbed == 1) {
        return $globbed[0];
    }

    # Otherwise, call out to our helper script which can figure out the calling
    # makefile from the process table.
    my $calling_makefile = qx("$EXECUTABLE_NAME" "$FindBin::Bin/print_calling_makefile.pl");
    my $status = $?;
    chomp $calling_makefile;

    # Worst case scenario - we can't figure out the makefile at all.
    # Give up.
    if (!$calling_makefile || $status) {
        die "Error: ambiguous makefiles:\n"
            .join( q{}, map { "  $_\n" } @globbed );
    }

    # $calling_makefile would most likely be a relative path, make it absolute.
    # It is resolved relative to whatever directory was used in the glob pattern.
    if (!file_name_is_absolute( $calling_makefile )) {
        $calling_makefile = rel2abs( $calling_makefile, dirname( $makefile ) );
    }

    return $calling_makefile;
}

sub plan_testcase
{
    my ($self, $testcase, @args) = @_;

    my $make = $self->{ make };
    my $makefile = $self->resolved_makefile( );

    my $prj = QMake::Project->new( $makefile );

    # Due to QTCREATORBUG-7170, we cannot let QMake::Project use jom
    $prj->set_make( ($make =~ m{\bjom}i) ? 'nmake' : $make );

    # Collect all interesting info about the tests.
    my @qmake_tests = qw(
        parallel_test
        insignificant_test
    );
    my @qmake_scalar_values = qw(
        TARGET
        testcase.timeout
    );
    my @qmake_keys = (@qmake_tests, @qmake_scalar_values);

    my %info = (
        args => [ $testcase, @args ],
        cwd => $CWD,
        map( { my $v = $prj->test( $_ ); $_ => $v } @qmake_tests),
        map( { my $v = $prj->values( $_ ); $_ => $v } @qmake_scalar_values),
    );

    # flatten info before passing to Data::Dumper
    @info{ @qmake_keys } = apply { $_ = force $_ } @info{ @qmake_keys };

    # Eliminate any undefined values
    if (my @undefined = grep { !defined( $info{ $_ }) } @qmake_keys) {
        delete @info{ @undefined };
    }

    # add a nice "label", which is the primary human-readable name for the
    # test in test reports.
    $info{ label } = basename( $info{ TARGET } );

    # Now write the info to the testplan.
    $self->write_testcase( \%info );

    print "  testplan: $info{ label }\n";

    return;
}

# Write all of the given testcase @info (array of hashrefs) to the output file.
sub write_testcase
{
    my ($self, @info) = @_;

    my $output = $self->{ output };

    my @info_strings = map { $self->testcase_to_string( $_ ) } @info;
    my $text = join( "\n", @info_strings )."\n";

    # Now write the info to the testplan (single line).
    open( my $fh, '>>', $output );
    flock( $fh, LOCK_EX );
    seek( $fh, 0, SEEK_END );
    print $fh $text;
    flock( $fh, LOCK_UN );
    close( $fh );

    return;
}

# Given a testcase $info hashref, returns a serialized string representing
# the info.  Guaranteed not to contain any newlines.
sub testcase_to_string
{
    my ($self, $info) = @_;

    my $dumper = Data::Dumper->new( [ $info ] );
    $dumper->Indent( 0 );   # all output on one line
    $dumper->Terse( 1 );    # omit leading $VAR1
    $dumper->Sortkeys( 1 ); # get a predictable order
    $dumper->Useqq( 1 );    # handle special characters safely (although none are expected)

    my $info_string = $dumper->Dump( );

    # trivial sanity check: should be just one line
    if ($info_string =~ m{\n}) {
        die "internal error: multiple lines in testcase info string:\n$info_string";
    }

    return $info_string;
}

sub run_make_check
{
    my ($self, @args) = @_;

    local $CWD = $self->{ input };

    # We are going to pass TESTRUNNER and TESTARGS to `make check'.
    # If these are already set in the environment, they may interfere with
    # our own values, so remove them.
    # In practice, this occurs when `nmake check' is used to run the selftests in
    # the qtqa repository.
    my %clean_env = %ENV;
    delete @clean_env{qw(TESTARGS TESTRUNNER)};
    local %ENV = %clean_env;

    my $make = $self->{ make };
    my $output = $self->{ output };
    my $this_script = $self->{ this_script };

    my @command = ( $make );

    my $make_flavor = $self->make_flavor( );

    if ($make_flavor eq 'GNU') {
        push @command, '-s', '-j4';
    } elsif ($make_flavor eq 'MS') {
        push @command, '/NOLOGO', '/S';
        if ($make =~ m{\bjom}i) {
            push @command, '-j4';
        }
    } else {
        warn "Unknown make command $make.  May be slow and noisy.\n";
    }

    my $makefile_var = $self->makefile_var( );
    my $subcmd = "$EXECUTABLE_NAME $this_script --make $make --makefile $makefile_var --output $output --testcase";

    push @command, (
        'check',
        "TESTRUNNER=$subcmd --",
        "TESTARGS=".join(' ', @args),   # note: we know there are no spaces in any of @args
    );

    if (my $status = system( @command )) {
        die "testplan generation failed; @command exited with status $status (exit code ".($status >> 8).')';
    }

    return;
}

#==================================================================================================

QtQA::App::TestPlanner->new( )->run( @ARGV ) if (!caller);
1;

