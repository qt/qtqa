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
use List::MoreUtils qw(any apply);
use Pod::Usage;
use Readonly;

use FindBin;
use lib "$FindBin::Bin/../lib/perl5";

use autodie;

use QtQA::QMake::Project;

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
# currently does not actually modify the test plan in any way,
# just does a basic sanity check that it exists, can be parsed,
# and summarizes it.
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

    my $count = 0;
    my $fh = IO::File->new( $filename, '<' ) || die "open $filename: $!";
    while (my $line = <$fh>) {
        ++$count;
        eval $line;  ## no critic (ProhibitStringyEval) - no way around it
        if (my $error = $@) {
            die "$filename:$count: error: $error";
        }
    }

    print inflect "Test plan generated for NO(test,$count) at $filename\n";

    return;
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

    # no globbing necessary on platforms other than Windows.
    if (!$WINDOWS) {
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
    my $output = $self->{ output };

    my $prj = QtQA::QMake::Project->new( $makefile );

    # Due to QTCREATORBUG-7170, we cannot let QtQA::QMake::Project use jom
    $prj->set_make( ($make =~ m{\bjom}i) ? 'nmake' : $make );

    # Collect all interesting info about the tests.
    my @qmake_tests = qw(
        parallel_test
        insignificant_test
    );
    my @qmake_scalar_values = qw(
        TARGET
    );
    my @qmake_keys = (@qmake_tests, @qmake_scalar_values);

    my %info = (
        args => [ $testcase, @args ],
        cwd => $CWD,
        map( { my $v = $prj->test( $_ ); $_ => $v } @qmake_tests),
        map( { my $v = $prj->values( $_ ); $_ => $v } @qmake_scalar_values),
    );

    # flatten info before passing to Data::Dumper
    @info{ @qmake_keys } = apply { $_ = "$_" } @info{ @qmake_keys };

    # add a nice "label", which is the primary human-readable name for the
    # test in test reports.
    $info{ label } = basename( $info{ TARGET } );

    my $dumper = Data::Dumper->new( [ \%info ] );
    $dumper->Indent( 0 );   # all output on one line
    $dumper->Terse( 1 );    # omit leading $VAR1
    $dumper->Sortkeys( 1 ); # get a predictable order
    $dumper->Useqq( 1 );    # handle special characters safely (although none are expected)

    my $info_string = $dumper->Dump( );

    # trivial sanity check: should be just one line
    if ($info_string =~ m{\n}) {
        die "internal error: multiple lines in testcase info string:\n$info_string";
    }

    # Now write the info to the testplan (single line).
    open( my $fh, '>>', $output );
    flock( $fh, LOCK_EX );
    seek( $fh, 0, SEEK_END );
    print $fh "$info_string\n";
    flock( $fh, LOCK_UN );
    close( $fh );

    print "  testplan: $info{ label }\n";

    return;
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

