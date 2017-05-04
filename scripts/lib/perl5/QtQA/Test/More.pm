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

package QtQA::Test::More;
use strict;
use warnings;

use Carp;
use Cwd qw(abs_path);
use Data::Dumper;
use IO::File;
use File::Basename;
use File::Spec::Functions;
use File::Which;
use List::MoreUtils qw( any );
use Params::Validate qw( :all );
use Readonly;
use Test::More;
use English qw( -no_match_vars );

use base 'Exporter';
Readonly our @EXPORT_OK => qw(
    is_or_like
    create_mock_command
    find_qmake
);
Readonly our %EXPORT_TAGS => ( all => \@EXPORT_OK );

Readonly my $QT_VERSION => 5;

## no critic (Subroutines::RequireArgUnpacking)
#  This policy does not work nicely with Params::Validate

# subs used internally by public API
sub _mock_command_step_filename;
sub _mock_command_write_command;
sub _mock_command_write_step_file;

#=================================== public API ===================================================

sub is_or_like
{
    my ($actual, $expected, $testname) = @_;

    return if !defined($expected);

    if (ref($expected) eq 'Regexp') {
        if ($testname) {
            $testname .= ' (regex match)';
            @_         = (@_[0..1], $testname);
        }
        goto &like;
    }

    elsif (ref($expected) eq 'ARRAY') {
        my @expected = @{$expected};
        my $out = 1;
        my $i = 0;
        while ($out && @expected) {
            $out &&= is_or_like( $actual, shift( @expected ), "$testname ($i)" );
            ++$i;
        }
        return $out;
    }

    if ($testname) {
        $testname .= ' (exact match)';
        @_         = (@_[0..1], $testname);
    }
    goto &is;
}


sub create_mock_command
{
    my %options = validate(@_, {
            name        =>  1,
            directory   =>  1,
            sequence    =>  { type => ARRAYREF },
    });

    my ($name, $directory, $sequence_ref) = @options{ qw(name directory sequence) };

    croak "`$directory' is not an existing directory" if (! -d $directory);
    croak 'name is empty'                             if (! $name);

    my $script = File::Spec->catfile( $directory, $name );
    croak "`$script' already exists" if (-e $script);

    my @sequence = @{$sequence_ref};

    # We use data files like:
    #
    #  command.step-NN
    #
    # ... to instruct the command on what to do.
    #
    # Each time the command is run, it will read and delete the lowest-numbered step file.
    #
    # We arbitrarily choose 2 digits, meaning a maximum of 100 steps.
    #
    # Note that we intentionally support having 0 steps.
    # This means that we create a command which simply dies immediately if it is called.
    # This may be used to test that a command is _not_ called, or to satisfy code which
    # requires some command to be in PATH but does not actually invoke it.
    Readonly my $MAX => 100;
    croak "test sequence is too large! Maximum of $MAX steps permitted"
        if (@sequence > $MAX);

    # Verify that none of the step files exist
    Readonly my @FILENAMES => map { _mock_command_step_filename($script, $_) } ( 0..($MAX-1) );

    croak "step file(s) still exist in $directory - did you forget to clean this up since an "
         .'earlier test?'
        if (any { -e $_ } @FILENAMES);

    my $step_number = 0;
    foreach my $step (@sequence) {
        my $validated_step = eval {
            validate_with(
                params => [ $step ],
                spec => {
                    stdout   => { default => q{} },
                    stderr   => { default => q{} },
                    exitcode => { default => 0 },
                    delay    => { default => 0 },
                },
            );
        };

        croak "at step $step_number of test sequence: $EVAL_ERROR" if ($EVAL_ERROR);

        my $filename = $FILENAMES[ $step_number++ ];
        _mock_command_write_step_file( $filename, $validated_step );
    }

    _mock_command_write_command( $script, @FILENAMES[0..($step_number-1)] );

    return;
}

#=================================== internals ====================================================

sub _mock_command_step_filename
{
    my ($script, $i) = @_;
    return sprintf( '%s.step-%02d', $script, $i );
}

sub _mock_command_write_step_file
{
    my ($filename, $data) = @_;

    # $data is something like:
    #
    #   { stdout => 'something', stderr => 'something', exitcode => 43 }
    #
    # We want to write literally a string like the above to the step file.
    #
    my $data_code = Data::Dumper->new( [ $data ] )->Terse( 1 )->Dump( );

    my $fh = IO::File->new( $filename, '>' )
        || croak "open $filename for write: $!";

    $fh->print( "$data_code;\n" );

    $fh->close( )
        || croak "close $filename after write: $!";

    return;
}

sub _mock_command_write_command
{
    my ($command_file, @step_files) = @_;

    my $step_files_code = Data::Dumper->new( [ \@step_files ] )->Terse( 1 )->Dump( );

    my $fh = IO::File->new( $command_file, '>' )
        || croak "open $command_file for write: $!";

    $fh->print( q|#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use Data::Dumper;
use English qw(-no_match_vars);

binmode( STDOUT, ':utf8' );
binmode( STDERR, ':utf8' );

my $step_files = | . $step_files_code . q|;
foreach my $file (@{$step_files}) {
    next if (! -e $file);
    my $data = do $file;

    die "couldn't parse $file: $@"     if $@;
    die "couldn't do $file: $!"        if (! defined $data);
    die "$file did not give a hashref" if (ref($data) ne 'HASH');
    die "couldn't unlink $file: $!"    if (! unlink( $file ));

    local $OUTPUT_AUTOFLUSH = 1;
    print STDOUT $data->{stdout};
    print STDERR $data->{stderr};
    sleep( $data->{delay} ) if $data->{delay};
    exit $data->{exitcode};
}

die "no more test steps!\n"
   .'A mocked command created by QtQA::Test::More::create_mock_command was run '
   ."more times than expected.\n"
   .'I expected to be run at most '.scalar(@{$step_files}).' time(s), reading '
   ."instructions from these files:\n".Dumper($step_files)
   .'...but the files do not exist!';|
    );

    $fh->close( )                   || croak "close $command_file after write: $!";
    # On most OS, we simply need to make the script have executable permission
    if ($OSNAME !~ m{win32}i) {
        chmod( 0755, $command_file ) || croak "chmod $command_file: $!";
    }

    # On Windows, we cannot directly execute the above script as a command.
    # Make a .bat file which executes it.
    else {
        $fh = IO::File->new( "$command_file.bat", '>' )
            || croak "open $command_file.bat for write: $!";

        # %~dp0 == the full path to the directory containing the .bat
        # %*    == all arguments

        $fh->print( '@perl.exe %~dp0'.basename( $command_file )." %*\n" );
        $fh->close( ) || croak "close $command_file.bat after write: $!";
    }

    return;
}

sub find_qmake
{
    # Try to find the "right" qmake - not particularly easy.
    my $this_dir = $INC{ 'QtQA/Test/More.pm' };
    if (!$this_dir) {
        diag "Warning: can't find QtQA/Test/More.pm in %INC.  Included unusually?\n"
            ."find_qmake() will probably fail.";
        $this_dir = '.';
    }
    $this_dir = dirname( $this_dir );

    my $repo_base = catfile( $this_dir, qw(.. .. .. .. ..) );
    my $qmake = catfile( $repo_base, qw(.. qtbase bin qmake) );
    if ($OSNAME =~ m{win32}i) {
        $qmake .= '.exe';
    }

    if (-f $qmake) {
        $qmake = abs_path $qmake;
        diag "Using qmake from sibling qtbase: $qmake";
        return $qmake;
    }

    # OK, then just try to use qmake from PATH
    $qmake = which 'qmake';
    my $output = qx("$qmake" -v 2>&1);
    if ($? == 0 && $output =~ m{Using Qt version $QT_VERSION}) {
        diag "Using qmake from PATH: $qmake\n$output";
        return $qmake;
    }

    diag 'Warning: no qmake found';

    return;
}



=head1 NAME

QtQA::Test::More -  a handful of test utilities in the spirit of Test::More

=head1 SYNOPSIS

  use Test::More;
  use QtQA::Test::More;

  # use regular Test::More functions where appropriate...
  is( $actual, $expected, 'value is as expected' );

  # ... and additional QtQA::Test::More functions where useful
  is_or_like( $actual, $expected, 'value matches expected' );

This module holds various test helper functions which have been found useful
when writing autotests for the scripts in this repository.

Any code which is used in more than one test, and not readily provided by an existing
CPAN module, is a candidate for addition to this module.

This module does not export any methods by default.

=head1 METHODS

=over

=item B<is_or_like>( ACTUAL, EXPECTED, [ TESTNAME ] )

If EXPECTED is a reference to a Regexp, calls L<Test::More::like> with the given
parameters.

If EXPECTED is a scalar, calls L<Test::More::is>.

If EXPECTED is a reference to an Array, calls B<is_or_like> once for each element
in the array (stopping at the first failure).  This is mostly provided as an
alternative to writing extremely complicated regular expressions.

In the testlog, TESTNAME will have the string ' (exact match)' or ' (regex match)'
appended to it, so that it is clear which form of comparison was used.
If the Array-reference form is used, the TESTNAME will also have the current array index
appended.

This function is intended for use in specifying sets of testdata where most of the
data can be specified precisely, but some cases require matching instead.  For
example:

  # check various system commands work as expected
  my %TESTDATA = (
    # basic check for working shell
    'echo' => {
      command          => [ '/bin/sh', '-c', 'echo Hello' ],
      expected_stdout  => "Hello\n",    # precisely specified
      expected_stderr  => "",           # precisely specified
    },
    # make sure mktemp respects --tmpdir and TEMPLATE as we expect
    'mktemp' => {
      command          => [ '/bin/mktemp', '--dry-run', '--tmpdir=/custom', 'my-dir.XXXXXX' ],
      expected_stdout  => qr{\A /custom/my-dir \. [a-zA-Z0-9]{6} \n \z}xms, # can't be precise
      expected_stderr  => "",                                               # precisely specified
    },
  );

  # ... and later:
  while (my ($testname, $testdata) = each %TESTDATA) {
    my ($stdout, $stderr) = capture { system( @{$testdata->{command}} ) };

    is_or_like( $stdout, $testdata->{ expected_stdout } );
    is_or_like( $stderr, $testdata->{ expected_stderr } );
  }

Another example, demonstrating usage of the arrayref form:

  my $output = qx(perl -e "print qq{Hello\n}; print STDERR qq{Warning!\n}; print qq{World\n}" 2>&1);

  # We cannot 100% guarantee the order in which the stdout/stderr arrived,
  # but we can guarantee that the "Hello" line comes before "World" and that
  # there are 3 lines
  is_or_like( $output, [
    qr{(\A|\n)Warning!\n}ms,               # STDERR line is present
    qr{(\A|\n)Hello\n.*?(?<=\n)World\n}ms, # STDOUT lines are present, in the right order
    qr{\A([^\n]+\n){3}\z}ms,               # exactly three lines are present
  ]);


=item B<create_mock_command>( OPTIONS )

Creates a mock command whose behavior is defined by the content of OPTIONS.

The purpose of this function is to facilitate the testing of code which interacts
with possibly failing external processes.  This is made clear with an example: to
test how a script handles temporary network failures from git, the following code
could be used:

  create_mock_command(
    name        =>  'git',
    directory   =>  $tempdir,
    sequence    =>  [
      # first two times, simulate the server hanging up for unknown reasons after
      # a few seconds
      { stdout => q{}, stderr => "fatal: The remote end hung up unexpectedly\n", exitcode => 2, delay => 3 },
      { stdout => q{}, stderr => "fatal: The remote end hung up unexpectedly\n", exitcode => 2, delay => 3 },
      # on the third try, complete successfully
      { stdout => q{}, stderr => q{},                                            exitcode => 0 },
    ],
  );

  # make the above mocked git first in PATH...
  local $ENV{PATH} = $tempdir . ':' . $ENV{PATH};

  # and verify that some code can robustly handle the above errors (but warned about them)
  my $result;
  my ($stdout, $stderr) = capture { $result = $git->clone('git://example.com/repo') };
  ok( $result );
  is( $stderr, "Warning: 3 attempt(s) required to successfully complete git operation\n" );

OPTIONS is a hash or hashref with the following keys:

=over

=item name

The basename of the command, e.g. `git'.

=item directory

The directory in which the command should be created, e.g. `/tmp/command-test'.

This should be a temporary directory, because B<create_mock_command> will write
some otherwise useless data files to this directory.  The caller is responsible
for creating and deleting this directory (and prepending it to $ENV{PATH}, if
that is appropriate).

=item sequence

The test sequence which should be simulated by the command.

This is a reference to an array of hashrefs, each of which has these keys:

=over

=item stdout

Standard output to be written by the command.

=item stderr

Standard error to be written by the command.

=item exitcode

The exit code for the command.

=item delay

Delay, in seconds, to wait after the command has printed its output and before
the command exits.

=back

Each time the mock command is executed, the next element in the array is used
to determine the command's behavior.  For example, with this sequence:

  sequence => [
    { stdout => q{},    stderr => "example.com: host not found\n", exitcode => 2 },
    { stdout => "OK\n", stderr => q{},                             exitcode => 0 },
  ]

... the first time the command is run, it will print "example.com: host not found"
to standard error, and exit with exit code 2 (failure).  The second time the
command is run, it will print "OK" to standard output, and exit with exit code 0
(success).  (It is an error to run the command a third time - if this is done, it
will die, noisily).

=back

=item B<find_qmake>

Attempts to find and return a qmake command string suitable for running from
within a test:

=over

=item *

If the "qtqa" directory has a sibling "qtbase" directory, the qmake from that
qtbase will be used, if available.  The full path to qmake is returned.

=item *

Otherwise, if a qmake from Qt 5 is in PATH, it will be used.
The string "qmake" is returned.

=item *

Otherwise, an undefined value is returned.

=back

=back



=cut

1;
