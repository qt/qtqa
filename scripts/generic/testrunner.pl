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

package QtQA::App::TestRunner;

=head1 NAME

testrunner - helper script to safely run autotests

=head1 SYNOPSIS

  # Run one autotest safely...
  $ path/to/testrunner [options] -- some/tst_test1

  # Run many autotests safely... (from within a Qt project)
  # A maximum runtime of 2 minutes each...
  $ make check "TESTRUNNER=path/to/testrunner --timeout 120 --"
  # Will run:
  #   path/to/testrunner --timeout 120 -- some/tst_test1
  #   path/to/testrunner --timeout 120 -- some/tst_test2
  # etc...

  # Run many autotests and capture the logs to $HOME/test-logs, while also
  # displaying the logs as they are written
  $ make check "TESTRUNNER=path/to/testrunner --tee-logs $HOME/test-logs --timeout 120 --"

  # Will generate:
  #
  #   $HOME/test-logs/testcase1-00.txt
  #   $HOME/test-logs/testcase2-00.txt
  #

This script is a wrapper for running autotests safely and ensuring that
uniform results are generated.  It is designed to integrate with Qt's
`make check' feature.

Some features of this script depend on QTestLib-style autotests, while others
are usable for any kind of autotest.

=head1 OPTIONS

=over

=item B<--help>

Print this message.

=item B<-->

Separates the options to testrunner from the test command and arguments (mandatory).

=item B<--timeout> <value>

If the test takes longer than <value> seconds, it will be killed, and
the testrunner will exit with a non-zero exit code to indicate failure.

=item B<-C> <directory>

=item B<--chdir> <directory>

Change to the specified directory before running the test.

=item B<--label> <label>

Use the given label as the human-readable name of this test in certain
output messages. May be omitted.

=item B<-v>

=item B<--verbose>

Print a line with some information before the test begins and after the
test completes.

For example:

  $ testrunner --verbose -- ./tst_mytest -silent
  QtQA::App::TestRunner: begin mytest: [./tst_mytest] [-silent]
  Testing tst_MyTest
  QFATAL : tst_MyTest::buggyTest() Cannot quux the fnord
  QtQA::App::TestRunner: Process exited due to signal 6; dumped core
  QtQA::App::TestRunner: end mytest: [./tst_mytest] [-silent], signal 6

The lines are guaranteed to match C</^QtQA::App::TestRunner: begin (?<label>[^:]+):/>
and C</^QtQA::App::TestRunner: end (?<label>[^:]+):/>, where 'label' is the label set
by the --label command-line option with any ':' characters replaced with '_', but
the format is otherwise undefined.

This is primarily used to unambiguously identify which output belongs to
which test, from a log containing many consecutive test runs.

=item B<--capture-logs> <directory>

The output of the test will be stored in a file under the given <directory>.
The directory is created if it doesn't yet exist.

As long as only one test is run at a time, it is guaranteed that a unique name
is used for the log file, so that tests will not clobber each other's output.
The specific naming strategy is undefined.

The behavior of this option is affected by the logging options passed to the
test:

=over

=item *

In the normal case, the combined stdout/stderr of the test is saved
into the log file.

=item *

If the test is run with a testlib old-style output file specifier, e.g. C<-o somefile>,
then the testrunner modifies the C<-o> value passed to the test so that the
test writes to a file under the given <directory>.  If the test also writes anything
to stdout/stderr, that will be appended to the log file.  It is considered an error
if the test doesn't generate the log file.

=item *

If the test is run with testlib new-style output file specifiers,
e.g. C<-o somefile.xml,xml -o -,txt>, then the testrunner modifies the C<-o> values
similarly as described above.  However, only the non-stdout streams are captured;
any logger explicitly set to stdout is passed through untouched.
Again, it is considered an error if the test doesn't generate all the expected log
files.

=back

Note that in the C<-o> cases, output is not guaranteed to be completely silent;
messages from the testrunner itself (such as the output generated by C<--verbose>)
may be printed to standard error, since it would not be safe to print them to the
log file while the test itself is also writing to that file.

For example, if the following command is run:

  testrunner --capture-logs $HOME/test-logs -- ./tst_qstring -o testlog.xml,xml -o -,txt

...then testrunner may run the test as:

  ./tst_qstring -o $HOME/test-logs/qstring-testlog-00.xml,xml -o -,txt

...and if $HOME/test-logs/qstring-testlog-00.xml does not exist when the test completes,
the test will be considered a failure.

=item B<--tee-logs> <directory>

Exactly like C<--capture-logs directory>, except that stdout/stderr from the autotest
are also written to stdout/stderr of the testrunner, rather than only being written
to the captured log file.

When using the testlib multiple-file logger, with stdout as one of the logger
destinations, --tee-logs and --capture-logs are identical.  This is intentional,
as testlib is already implementing its own tee-like behavior.

=item B<--sync-output>

Buffer and synchronize outputs to avoid interleaved output from multiple tests
in parallel.

When this option is in use, each concurrent testrunner instance will co-operate
to ensure that each test's output appears as a contiguous block.  The output from
each test will be buffered until the test completes, then written to standard output
as a single block.

This provides the benefit of a more readable test log, but has the downside
that a test which is currently running provides no progress information.

As a side effect of this option, standard output and standard error from the test
may be merged.

=item B<--plugin> <plugin>

Loads the specified testrunner plugin to customize behavior.

May be specified multiple times to load multiple plugins.

When multiple plugins are specified, they are activated in the order they are given
on the command line.  This may have no effect, or it may alter the ordering of some
output, or it may have more profound effects, depending on the behavior of the
plugins.

Plugins customize the behavior of the testrunner in various ways.  The exact
list of plugins is platform-specific and undefined.  Some plugins which may
be available include:

=over

=item core

Attempt to intercept core dumps from any crashing process, and append a backtrace
to the test log.  (Linux and Mac only, not recommended on Mac)

=item crashreporter

Attempt to find and print crash logs from the CrashReporter service from any
crashing process.  (Mac only)

=item flaky

When a test fails, run it again, to help determine if it is unstable.
Accepts the following options:

=over

=item B<--flaky-mode worst>

When a test is flaky, use the worst result (default).

=item B<--flaky-mode best>

When a test is flaky, use the best result.

=item B<--flaky-mode ignore>

When a test is flaky, ignore the result.

=back

See the flaky plugin's perldoc for more discussion.

=item testcocoon

After a test is run, it will check for the source coverage database csmes and the execution report csexe.
If found the csexe is imported into the test csmes and a global csmes is created or updated.
This global coverage database with execution report gathers all tests results. The "local" test csmes
and csexe are deleted to save space. Note: It makes sense only if the module is built with coverage enabled.

=over

=item B<--testcocoon-tests-output> <fullpath>

Full path to csmes database (to create) where all the tests coverage results are gathered.
The file should not exist to avoid data corruption.

=item B<--testcocoon-qt-gitmodule-dir> <directory>

Full path of git dir module. Used to retrieve the plugins csmes.

=back

See the testcocoon plugin's perldoc for more discussion.

=back

=back

=head1 CAVEATS

Note that, if a test is killed (e.g. due to a timeout), no attempt is made
to terminate the entire process tree spawned by that test (if any), as this
appears to be impractical.  In practice, that means any helper programs run
by a test may be left running if the test is killed.

It is possible that the usage of this script may alter the apparent ordering
of stdout/stderr lines from the test, though this is expected to be rare
enough to be negligible.

As an implementation detail, this script may retain the entire stdout/stderr
of the test in memory until the script exits.  This will make it inappropriate
for certain uses; for example, if your test is expected to run for one day
and print 100MB of text to stdout, testrunner will use (at least) 100MB of
memory, which is possibly unacceptable.

Currently, it is not advisable to combine the --capture-logs / --tee-logs
options with tests run in XML mode, as testrunner may append messages to the
log which are not valid XML.

=cut

use Getopt::Long qw(
    GetOptionsFromArray
    :config pass_through
);

use Carp;
use Capture::Tiny qw( capture_merged );
use Cwd qw( realpath );
use English qw( -no_match_vars );
use Fcntl qw( :flock );
use File::Basename;
use File::HomeDir;
use File::Path qw( mkpath );
use File::Spec::Functions;
use File::chdir;
use IO::File;
use IO::Handle;
use List::Util qw( first sum );
use Pod::Usage qw( pod2usage );
use Readonly;
use Timer::Simple;
use Win32::Status;

# We may be run from `scripts' or from `bin' via symlink.
# Support both cases for finding our own modules.
use FindBin;
use lib (
    first { -d $_ } ("$FindBin::Bin/../lib/perl5", "$FindBin::Bin/../scripts/lib/perl5")
);

BEGIN {
    # Proc::Reliable is not reliable on Windows
    if ($OSNAME !~ m{win32}i) {
        require AutoLoader;
        require Proc::Reliable;
        Proc::Reliable->import( );
    }
    else {
        require QtQA::Proc::Reliable::Win32;
        QtQA::Proc::Reliable::Win32->import( );
    }
}

#use Smart::Comments;    # uncomment for debugging

# a long time, but not forever
Readonly my $LONG_TIME => 60*60*24*7;

# default values for some command-line options
Readonly my %DEFAULTS => (
    timeout => $LONG_TIME,
    verbose => 0,
);

# exit code for strange process issues, such as a failure to fork
# or failure to waitpid; this is expected to be extremely rare,
# so the exit code is unusual
Readonly my $EXIT_PROCESS_ERROR => 96;

# exit code if subprocess dies due to signal; not all that rare
# (tests crash or hang frequently), so the exit code is not too unusual
Readonly my $EXIT_PROCESS_SIGNALED => 3;

# exit code if we can't capture logs as requested
Readonly my $EXIT_LOGGING_ERROR => 58;

# initial content of created log files
Readonly my $INITIAL_LOG_CONTENT => 'Log file created by '.__PACKAGE__;

# default fractional value for timeout duration warning
Readonly my $TIMEOUT_DURATION_WARNING => .75;

sub new
{
    my ($class) = @_;

    my $self = bless {}, $class;
    return $self;
}

sub run
{
    my ($self, @args) = @_;

    %{$self} = ( %DEFAULTS, %{$self} );

    my $tee_logs;

    GetOptionsFromArray( \@args,
        'help|?'            =>  sub { pod2usage(1) },
        'timeout=i'         =>  \$self->{ timeout },
        'capture-logs=s'    =>  \$self->{ capture_logs },
        'plugin=s'          =>  \@{$self->{ plugin_names }},
        'tee-logs=s'        =>  \$tee_logs,
        'sync-output'       =>  \$self->{ sync_output },
        'C|chdir=s'         =>  \$CWD,
        'v|verbose'         =>  \$self->{ verbose },
        'label=s'           =>  \$self->{ label },
    ) || pod2usage(2);

    # tee-logs implies that we both capture the logs, and print the output like `tee'
    if ($tee_logs) {
        $self->{ capture_logs } = $tee_logs;
        $self->{ tee          } = 1;
    }

    # note: plugins may consume additional arguments
    $self->plugins_init( \@args );

    # Chomp the remaining --, if any
    if (@args && $args[0] eq '--') {
        shift @args;
    }

    if ($self->{ sync_output }) {
        $self->do_subprocess_with_sync_output( @args );
    }
    else {
        $self->do_subprocess( @args );
    }

    $self->exit_appropriately( );

    return;
}

# Returns this test's label (human-readable name)
sub label
{
    my ($self) = @_;

    # If not explicitly set from command-line, calculate on first
    # use as the basename of the test command.
    if (!$self->{ label }) {
        my $basename = basename( ($self->command())[0] );
        $self->{ label } = $basename;
    }

    return $self->{ label };
}

# When there is an error relating to logging, print a message and exit.
#
# Parameters:
#   $message    -   error message to print (one line)
#
sub exit_with_logging_error
{
    my ($self, $message) = @_;

    my $directory = $self->{ capture_logs };

    $self->print_info(
        "cannot capture logs to $directory as requested:\n"
       ."$message\n"
       ."please check the test environment.\n"
    );

    # We're about to do an emergency exit; in sync-output mode, flush
    # the buffer (even if we don't have a lock on the output lockfile)
    $self->flush_sync_output_buffer( );

    exit $EXIT_LOGGING_ERROR;
}

# Generate a unique (not yet existing) filename for a test log.
# The log filename is based on the command we are about to run.
#
# capture_logs mode must be enabled.
#
# Parameters:
#   A hash ref with the following keys, all optional:
#     basename  =>  string to append to the file's basename.
#     suffix    =>  string to append to the end of the filename.
#
# Example:
#
#  # when running tst_qstring...
#
#  my $filename = $self->generate_unique_logfile_name( );
#  # filename is now: some/directory/tst_qstring-00.txt
#
#  $filename = $self->generate_unique_logfile_name({basename=>'testlog', suffix=>'.log'});
#  # filename is now: some/directory/tst_qstring-testlog-00.log
#
sub generate_unique_logfile_name
{
    my ($self, $args_ref) = @_;

    my $directory = $self->{ capture_logs };
    return if (!$directory);

    my $lockfile = catfile( $self->datadir(), '.qtqa-testrunner-logfile-lock' );
    my $lockfh = IO::File->new( $lockfile, '>>' ) || $self->exit_with_logging_error( "open $lockfile: $!" );
    flock( $lockfh, LOCK_EX ) || die "flock $lockfile: $!";

    # We need to come up with a unique filename.
    # Our chosen naming pattern is:
    #
    #   <basename>-<number>.<type>
    #
    # e.g., for tst_qstring,
    #
    #   tst_qstring-00.txt
    #   tst_qstring-01.txt
    #   ...
    #
    # We fail if there are already 100 files named like the above.
    # This would be indicative of some problem with the test setup.
    #
    my $suffix   = $args_ref->{ suffix } || '.txt';
    my $basename = basename( ($self->command())[0] );

    # basename is now e.g. tst_qstring

    if (defined $args_ref->{ basename }) {
        my $original_basename = $args_ref->{ basename };
        if ($original_basename eq '-') {
            $original_basename = 'stdout';
        }
        $basename .= "-$original_basename";
    }

    # basename is now e.g. tst_qstring-testlog

    $basename = catfile( $directory, $basename );

    # basename is now e.g. path/to/capturedir/tst_qstring-testlog

    my $i = 0;
    my $candidate;
    while ($i <= 99) {
        $candidate = sprintf( '%s-%02d%s', $basename, $i, $suffix );
        last if (! -e $candidate);
        ++$i;
    }

    if (-e $candidate) {
        $self->exit_with_logging_error(
            "$directory seems to be already full of files named like $basename-XX.$suffix"
        );
    }

    # Ensure the file exists before we release the lock, so that other testrunner instances
    # won't clobber it.  The file is initialized with some text so we can identify that it
    # was created by us.
    my $fh = $self->create_and_open_logfile( $candidate, "$INITIAL_LOG_CONTENT\n" );
    close( $fh );
    flock( $lockfh, LOCK_UN ) || die "flock $lockfile (unlock): $!";

    return $candidate;
}

# Returns path to a local data dir suitable for lock files and state files,
# creating it if necessary.
sub datadir
{
    my ($self) = @_;

    my $path = File::HomeDir->my_data();
    $self->safe_mkpath( $path ) || $self->exit_with_logging_error( "mkpath $path: $!" );

    return;
}

# Creates a log file at the given $filename, and returns an open file handle.
# The file's contents are initialized to $content (if set).
# The file is truncated if it already exists.
#
# The log may later be checked for the existence of $content to decide if the
# log file has been correctly overwritten by the test process.
sub create_and_open_logfile
{
    my ($self, $filename, $content) = @_;

    my $logdir = dirname( $filename );
    $self->safe_mkpath( $logdir ) || $self->exit_with_logging_error( "mkpath $logdir: $!" );

    open( my $fh, '>', $filename ) || $self->exit_with_logging_error( "open $filename for write: $!" );

    if (defined $content) {
        print $fh $content;
    }

    return $fh;
}

# Returns a hashref for the logfiles which should be used.  Generates a new filename if necessary.
# The hash keys are filenames and values are testlib-compatible log formats (e.g. `txt' for plain
# text).
sub logfiles
{
    my ($self) = @_;

    if (!$self->{ logfiles }) {
        $self->set_logfiles( $self->generate_unique_logfile_name( ) => 'txt' );
    }

    return $self->{ logfiles };
}

# Sets the logfiles which should be used.
sub set_logfiles
{
    my ($self, %logfiles) = @_;

    $self->{ logfiles } = \%logfiles;

    return;
}

# Like File::Path::mkpath, but does not fail if multiple processes mkpath() concurrently.
# On success, or if the path already exists, returns 1.
# On failure, returns 0.
sub safe_mkpath
{
    my ($self, $path) = @_;

    # $path could be created by another process in parallel; this is why we need
    # a check both before and after the mkpath().
    if (! -d $path && !mkpath( $path )) {
        sleep 1;
        return (-d $path);
    }

    return 1;
}

# Creates new logfiles, and returns an arrayref of open filehandles to them.
# The logfiles will be initialized with $content, if given.
sub create_and_open_logfiles
{
    my ($self, $content) = @_;

    my $logfiles = $self->logfiles( );
    my @out;

    while (my ($logfile, $format) = each %{ $logfiles }) {
        my $fh = $self->create_and_open_logfile( $logfile, $content );
        push @out, $fh;
    }

    return \@out;
}

# Set up logging where the subprocess tried to log to a file via `-o'
# and we intercepted it to write to a different file.
#
# Parameters:
#   $proc       -   a Proc::Reliable instance
#   $args_ref   -   hashref as returned by parse_and_rewrite_testlib_args_for_logging
#
sub setup_file_to_file_logging
{
    my ($self, $proc, $args_ref) = @_;

    # As the logfiles, we'll use the rewritten -o options...
    $self->set_logfiles( %{ $args_ref->{ replaced_output } } );

    # ...but we do _not_ create or open it, as the subprocess is expected to do this.
    $self->{ subprocess_creates_logfile } = 1;

    # We'd better create the directory if it doesn't exist - testlib won't do this.
    my $logdir = $self->{ capture_logs };
    if (!$self->safe_mkpath( $logdir )) {
        $self->exit_with_logging_error( "mkpath $logdir: $!" );
    }

    my $print_sub = sub {
        $self->proc_reliable_print_to_logbuffer(@_);
        if ($self->{ tee } || $self->{ subprocess_logs_to_stdout }) {
            $self->proc_reliable_print_to_handle(@_);
        }
    };

    $proc->stdout_cb( $print_sub );
    $proc->stderr_cb( $print_sub );

    return;
}

# Set up logging where the subprocess is logging only by stdout/stderr
# and we intercepted them to write to a file.
sub setup_stream_to_file_logging
{
    my ($self, $proc) = @_;

    $self->{ logfh } = $self->create_and_open_logfiles( );

    my $print_sub = sub {
        $self->proc_reliable_print_to_log(@_);
        if ($self->{ tee } || $self->{ subprocess_logs_to_stdout }) {
            $self->proc_reliable_print_to_handle(@_);
        }
    };

    $proc->stdout_cb( $print_sub );
    $proc->stderr_cb( $print_sub );

    return;
}

# Attempt to parse the subprocess arguments as testlib-style arguments,
# and rewrite them in such a way that logs may be captured.
#
# May change the executed command.
#
# Returns a reference to a hash with at least the following keys:
#
#   replaced_output =>  ref to an array of new filenames passed to -o, or undef if no -o
#
sub parse_and_rewrite_testlib_args_for_logging
{
    my ($self) = @_;

    my @args    = $self->command( );
    my $command = shift @args;

    my $out = {};
    my @rewritten_args;

    my $parser = Getopt::Long::Parser->new( );
    $parser->configure(qw(
        no_auto_abbrev
        no_bundling
        no_getopt_compat
        no_gnu_compat
        no_ignore_case
        pass_through
        permute
        prefix_pattern=-
    ));

    # Accept an argument via <> (i.e. an `unknown' argument), without modifying it in any way.
    my $sub_accept_unknown_argument = sub {
        push @rewritten_args, @_;
    };

    # Accept an argument which takes a value.
    # This has to prepend `-' back to the option name, as Getopt::Long strips
    # that before calling us (unlike in the <> case).
    my $sub_accept_argument_with_value = sub {
        my ($option, $value) = @_;
        push @rewritten_args, "-$option", $value;
    };

    # Accept and rewrite the -o argument
    my $sub_accept_rewrite_output_argument = sub {
        my ($option, $value) = @_;

        my ($filename, $format) = split(/,/, $value);

        if ($filename eq '-') {
            # remember that we explicitly asked to log to stdout, so we know
            # not to warn about it later, and to pass it through.
            $self->{ subprocess_logs_to_stdout } = 1;

            # Do not rewrite the `-o -,fmt' args.
            # We explicitly do not attempt to capture or tee in this case,
            # to keep things simple.
            return $sub_accept_argument_with_value->( $option, $value );
        }

        my ($basename, undef, $suffix) = fileparse( $filename, qr{\.[^.]*} );
        $filename = $self->generate_unique_logfile_name({
            basename    =>  $basename,
            suffix      =>  $suffix,
        });

        push @rewritten_args, "-$option";
        push @rewritten_args, ( $format ? "$filename,$format" : $filename );
        $out->{ replaced_output }{ $filename } = $format || 'txt';
    };

    # Note that Getopt::Long object-oriented interface oddly has no way to read
    # from anything other than @ARGV.  So, we have a choice to either (1) kludge
    # @ARGV, or (2) kludge via Getopt::Long::Configure, neither of which is
    # particularly attractive.  But localizing @ARGV seems the least error-prone.
    local @ARGV = @args;

    while (@ARGV) {
        $parser->getoptions(

            # -o option which we want to rewrite...
            'o=s'   =>  $sub_accept_rewrite_output_argument,

            # Parse all other testlib arguments which take a value.
            # We must parse these even though we don't use them.
            # If we didn't, we would be tricked by weird command lines like:
            #
            #   -maxwarnings -o something
            #
            # ... which should be parsed as ("-maxwarnings=-o", "something"   )
            #     and not                   ("-maxwarnings"   , "-o=something")
            #
            map( { +"$_=s" => $sub_accept_argument_with_value } qw(
                eventdelay
                graphicssystem
                iterations
                keydelay
                maxwarnings
                median
                minimumvalue
                mousedelay
                seed
            )),

            # keep any other arguments exactly as they are
            '<>'    =>  $sub_accept_unknown_argument,

        ) || return;

        # If we stopped at a --, then store it and continue; testlib does not stop argument
        # processing on --, so neither do we.
        if (@ARGV && $ARGV[0] eq '--') {
            shift @ARGV;
            push @rewritten_args, '--';
        }
    }

    # Overwrite command iff we found and munged the -o option
    if ($out->{ replaced_output }) {
        $self->set_command( $command, @rewritten_args );
    }

    return $out;
}

# Set up for logging of $proc, which should not yet be started.
sub setup_logging
{
    my ($self) = @_;

    return if (!$self->{ capture_logs });

    my $proc = $self->proc( );

    # We need to check if the test is being run with a `-o' option to write to a particular
    # log file.  If it is, then we will rewrite that option and expect the test script to
    # create the log file.  Otherwise, we will create the log file ourself.
    my $args_ref = $self->parse_and_rewrite_testlib_args_for_logging( );

    if ($args_ref->{ replaced_output }) {
        $self->setup_file_to_file_logging( $proc, $args_ref );
    }
    else {
        $self->setup_stream_to_file_logging( $proc );
    }

    return;
}

# Print info about proc's termination (if any)
sub proc_print_exit_info
{
    my ($self) = @_;

    my $proc = $self->proc( );

    # Print out any messages from the Proc::Reliable; this will include information
    # such as "process timed out", etc.
    my $msg = $proc->msg( );
    if ($msg) {
        # Don't mention the `Exceeded retry limit'; we never retry, so it would only be
        # confusing.  Note that this can (and often will) reduce $msg to nothing.
        $msg =~ s{ ^ Exceeded \s retry \s limit \s* }{}xms;
    }

    # Print out a warning message if the process took longer than a certain percentage
    # of the timeout amount.
    my $test_duration = int( $self->{ timer }[-1]->elapsed( ) );
    my $warning_threshold = $self->{ timeout } * $TIMEOUT_DURATION_WARNING;
    if ($test_duration > $warning_threshold && $test_duration < $self->{ timeout }) {
        $msg .= "warning: test duration ($test_duration seconds) is dangerously close to maximum permitted time ($self->{ timeout } seconds)\n";
        $msg .= "warning: Either modify the test to reduce its runtime, or use a higher timeout.\n";
    }

    my $status = $proc->status( );
    if ($status == -1 && !$msg) {
        # we should have a msg, but avoid being entirely silent if we don't
        $msg = "Proc::Reliable failed to run process for unknown reasons\n";
    }

    # "abnormal exit" (e.g. a crashing process) has very different behavior
    # on Windows vs other platforms.
    if ($OSNAME =~ m{mswin32}i) {
        $msg .= $self->check_abnormal_exit_win32( $status );
    } else {
        $msg .= $self->check_abnormal_exit( $status );
    }

    $self->print_info( $msg );
    return;
}

# Given an exit $status, returns some string describing the abnormal exit
# condition, or an empty string if the process exited normally.
sub check_abnormal_exit
{
    my ($self, $status) = @_;

    my $out = q{};

    my $signal = ($status & 127);
    if ($signal) {
        my $coredumped = ($status & 128);
        $out .=
            "Process exited due to signal $signal"
           .($coredumped ? '; dumped core' : q{})
           ."\n"
        ;
    }

    # Proc::Reliable gives an exit code of 255 if the binary doesn't exist.
    # Try to give a helpful hint about this case.
    # This is racy and not guaranteed to be correct.
    # Note this logic does not apply to Windows, because the system shell is
    # always used there, and it already complains when the command is not
    # found.
    my $exitcode = ($status >> 8);
    if ($exitcode == 255) {
        my $command = ($self->command( ))[0];
        if (! -e $command) {
            $out .= "$command: No such file or directory\n";
        }
    }

    return $out;
}

# Given an exit $status, returns some string describing the abnormal exit
# condition, or an empty string if the process exited normally.
# Note that this is heuristic, because Windows does not really have any
# concept of exiting normally or abnormally.
sub check_abnormal_exit_win32
{
    my ($self, $status) = @_;

    my $out = q{};

    my $exitcode = ($status >> 8);

    # If the exitcode is greater than 16 bits, it is most likely an abnormal
    # error condition.  Print it in hex form to make it more recognizable
    # and searchable.
    if ($exitcode & 0xFFFF0000) {
        $out .= sprintf( "Process exited with exit code 0x%X", $exitcode );

        # Do we also have some text form of this status code?
        if (my $str = $Win32::Status::INTEGER_TO_SYMBOL{ $exitcode }) {
            $out .= " ($str)";
        }

        $out .= "\n";
    }

    return $out;
}

# Returns 1 iff $filename appears to contain a valid test log.
#
# "valid" currently means "exists, and was not created by testrunner.pl"
#
sub looks_like_valid_log
{
    my ($self, $filename) = @_;

    if (! -f $filename) {
        return 0;
    }

    open( my $fh, '<', $filename ) ## no critic
        || $self->exit_with_logging_error( "open $filename for read: $!" );

    my $firstline = <$fh>;
    if ($firstline && $firstline eq "$INITIAL_LOG_CONTENT\n") {
        return 0;
    }

    return 1;
}

# Finish up the logging of $proc, which should have completed by now.
sub finalize_logging
{
    my ($self) = @_;

    if (!$self->{ subprocess_creates_logfile }) {
        # If the logfile was created by us and not the subprocess, or if there was no log
        # file at all, then there is nothing to finalize.
        return;
    }

    # In this case, we expect the subprocess to have created a log file, so we have to
    # check that (and also append to it if necessary).
    my $logfiles = $self->logfiles( );
    my $all_logfiles_valid = 1;

    foreach my $logfile (keys %{ $logfiles }) {
        if (!$self->looks_like_valid_log( $logfile )) {
            $all_logfiles_valid = 0;
            last;
        }
    }

    # Expected to create some log files, but didn't do so?
    if (!$all_logfiles_valid) {
        $self->{ force_failure_exitcode } ||= $EXIT_LOGGING_ERROR;
        $self->append_logbuffer_to_logfiles( $self->format_info(
            "FAIL! Test was badly behaved, the `-o' argument was ignored.\n"
           ."stdout/stderr follows:\n"
        ));
    }
    # Unexpectedly wrote some stuff to stdout/stderr ?
    elsif (!$self->{ subprocess_logs_to_stdout }) {
        $self->append_logbuffer_to_logfiles( $self->format_info(
            "test output additional content directly to stdout/stderr:\n"
        ));
    }

    return;
}

# If we captured any stdout/stderr from the subprocess which hasn't yet been logged,
# append it to the logfiles.  If $prefix is given, it is appended to the log files
# prior to other text.
sub append_logbuffer_to_logfiles
{
    my ($self, $prefix) = @_;

    # nothing to do if no output was captured
    return if (! defined $self->{ logbuffer });

    my $text = $prefix . $self->{ logbuffer };

    my $logfiles = $self->logfiles( );

    while (my ($logfile, $format) = each %{ $logfiles }) {
        # Do _not_ add the messages for formats other than plaintext.
        # That would create invalid XML, for example.
        next unless $format eq 'txt';

        # If the logfile already exists, we'll put a newline to separate our messages
        # from the existing messages.
        if (-e $logfile) {
            $text = "\n".$text;
        }

        open( my $fh, '>>', $logfile )
            || $self->exit_with_logging_error( "open $logfile for append: $!" );

        $fh->print( $text );

        close( $fh )
            || $self->exit_with_logging_error( "close $logfile after append: $!" );
    }

    return;
}

# Callback for Proc::Reliable which prints to the given handle,
# or if --sync-output is enabled, prints to a buffer to be output later.
# The first parameter to the callback is the correct IO handle (STDOUT or STDERR)
sub proc_reliable_print_to_handle
{
    my ($self, $handle, @to_print) = @_;

    if ($self->{ sync_output }) {
        # --sync-output mode, buffer for later.
        # $handle is ignored, all output is merged into one buffer.
        # This is a documented limitation of --sync-output
        $self->{ sync_output_buffer } .= join( q{}, @to_print );
    }
    else {
        # flush so we print as much as possible if we're killed without completing
        $handle->printflush( @to_print );
    }

    return;
}

# Callback for Proc::Reliable which prints to a unique log file.
sub proc_reliable_print_to_log
{
    my ($self, $handle, @to_print) = @_;

    # $handle is ignored, instead we print to the log file.
    foreach my $fh (@{ $self->{ logfh }}) {
        $fh->printflush( @to_print );
    }

    return;
}

# Print a message to the right place, which means:
#  - the logfiles (if any), or...
#  - sync_output_buffer (if --sync-output mode), or...
#  - STDERR (if no log and no --sync-output mode), or...
#  - both (a logfile) AND (sync_output_buffer OR STDERR) (if tee-logs mode)
#
sub print_to_log_or_stderr
{
    my ($self, @to_print) = @_;

    # flush so the log contains as much as possible if we're killed without completing
    foreach my $fh (@{ $self->{ logfh }}) {
        $fh->printflush( @to_print );
    }
    if (!$self->{ logfh } || !@{ $self->{ logfh } } || $self->{ tee }) {
        if ($self->{ sync_output }) {
            # --sync-output mode, buffer for later.
            $self->{ sync_output_buffer } .= join( q{}, @to_print );
        }
        else {
            STDERR->printflush( @to_print );
        }
    }

    return;
}

# Callback for Proc::Reliable which stores the text in memory.
sub proc_reliable_print_to_logbuffer
{
    my ($self, $handle, @to_print) = @_;

    # $handle is ignored, meaning that we are merging STDOUT and STDERR.
    foreach my $chunk (@to_print) {
        $self->{ logbuffer } .= $chunk;
    }

    return;
}

# Creates and returns a process object.
# On all platforms other than Windows, this is a Proc::Reliable object.
# On Windows, it is currently a stub missing many features.
sub create_proc
{
    my ($self) = @_;

    my $proc;
    if ($OSNAME =~ m{win32}i) {
        $proc = $self->create_proc_win32( );
        # There are no Windows-only options
    } else {
        $proc = Proc::Reliable->new( );

        # These options only work for platforms other than Windows
        $proc->stdin_error_ok( 1 );                 # OK if child does not read all stdin
        $proc->num_tries( 1 );                      # don't automatically retry on error
        $proc->child_exit_time( $LONG_TIME );       # don't consider it an error if the test
                                                    # doesn't quit soon after closing stdout
        $proc->time_per_try( $self->{timeout} );    # don't run for longer than this
        $proc->want_single_list( 0 );               # force stdout/stderr handled separately
    }

    # These options work for all platforms

    $proc->maxtime( $self->{timeout} );

    # Default callbacks just print everything as we receive it.
    # The logging setup function is permitted to change these callbacks.
    $proc->stdout_cb( sub { $self->proc_reliable_print_to_handle(@_) } );
    $proc->stderr_cb( sub { $self->proc_reliable_print_to_handle(@_) } );

    return $proc;
}

sub create_proc_win32
{
    my ($self) = @_;

    return QtQA::Proc::Reliable::Win32->new( );
}

sub do_subprocess_with_sync_output
{
    my ($self, @args) = @_;

    my $lockfile = catfile( $self->datadir(), '.qtqa-testrunner-lock' );
    my $fh = IO::File->new( $lockfile, '>>' ) || die "open $lockfile: $!";

    # The output will be buffered while we run the subprocess ...
    $self->{ sync_output_buffer } = q{};
    $self->do_subprocess( @args );
    # ...and we can't output until we can get the lock
    flock($fh, LOCK_EX) || die "flock $lockfile: $!";

    $self->flush_sync_output_buffer( );

    $fh->close( ) || die "close $lockfile: $!";
    return;
}

# Empties the sync_output_buffer, printing its content to stdout.
sub flush_sync_output_buffer
{
    my ($self) = @_;

    if (my $buffer = $self->{ sync_output_buffer }) {
        local $OUTPUT_AUTOFLUSH = 1;
        print $buffer;
        $self->{ sync_output_buffer } = q{};
    }

    return;
}

# Run a subprocess for the given @command, and do all appropriate logging.
# A Proc::Reliable encapsulating the process is returned, after the process completes.
sub do_subprocess
{
    my ($self, @command) = @_;

    @command || die 'not enough arguments';

    $self->set_command( @command );

    my $proc = $self->create_proc();

    $self->set_proc( $proc );

    $self->setup_logging( );  # this is allowed to modify the command

    $self->print_test_begin_info( );

    my $keep_running = 1;
    my $attempt = 1;
    my $force_failure_exitcode;
    my $kill_cmd = "killall -v \"iPhone Simulator\"";

    # creates an array to store the timer details for each attempt
    $self->{ timer } = [];

    while ($keep_running) {

        # Plugins may ask us to force a failure.
        # We clear this at each run so that we only consider forced failures
        # during the _last_ run.
        $force_failure_exitcode = 0;

        push @{$self->{ timer }}, Timer::Simple->new( );

        my @command = $self->command( );

        # Running test in iOS simulator, with ios-sim
        if ( $ENV{QT_TEST_USE_IOS_SIM} ) {
            # Apps are launched as ios-sim launch <tst_app> --args <tst_app args >
            my $app = shift @command;
            unshift @command, 'ios-sim', 'launch', $app,'--args';
            # Looks like ios-sim can't re-launch the simulator properly, so we'll kill it
            qx{${kill_cmd}};
        }

        $self->plugins_about_to_run( \@command );

        {
            # Put the attempt number into the environment for these reasons:
            #
            #  - makes it easier to write autotests for this feature
            #
            #  - (hopefully) captures the information in core dumps etc
            #    about how many times the test has been run
            #
            local $ENV{ QTQA_APP_TESTRUNNER_ATTEMPT } = $attempt;

            $proc->run( \@command );
        }

        $self->proc_print_exit_info( );

        my $result = $self->plugins_run_completed( );

        $force_failure_exitcode = $result->{ force_failure_exitcode };

        # We may retry the test any number of times, if some plugin asks us to.
        $keep_running = $result->{ retry };
        $self->{ timer }[-1]->stop( );
        ++$attempt;
    }

    $self->{ force_failure_exitcode } ||= $force_failure_exitcode;

    $self->print_test_end_info( );

    $self->finalize_logging( );

    return $proc;
}

sub pretty_printed_command
{
    my ($self) = @_;

    my @out = map {
        my $arg = $_;
        $arg =~ s{\n}{\\n}g;    # make sure we can never break across lines
        "[$arg]"
    } $self->command( );

    return @out;
}

# Prints line prior to running a test, depending on verbosity.
sub print_test_begin_info
{
    my ($self) = @_;

    return unless ($self->{ verbose });

    my $label = $self->label( );
    $label =~ s{:}{_}g;

    my @command = $self->pretty_printed_command( );

    $self->print_info( "begin $label @ $CWD: @command\n" );

    return;
}

# Prints line after a test has completed, depending on verbosity.
sub print_test_end_info
{
    my ($self) = @_;

    return unless ($self->{ verbose });

    my $label = $self->label( );
    $label =~ s{:}{_}g;

    my $proc = $self->proc( );
    my $status = $proc->status( );

    my $seconds = sum( map { $_->elapsed( ) } @{$self->{ timer }});

    # If it was at least two seconds, only report the integer part.
    # For very fast tests, we report the fractional part as well - mostly
    # because "0 seconds" looks weird.
    if ($seconds > 1) {
        $seconds = int($seconds);
    }

    my $message = "end $label: $seconds seconds";

    if ($status == -1) {
        $message .= ", status -1 (unusual error)";
    } elsif ((my $signal = ($status & 127)) && $OSNAME !~ m{win32}i) {
        $message .= ", signal $signal";
    } else {
        my $exitcode = ($status >> 8);
        if ($exitcode == 0 && $self->{ force_failure_exitcode }) {
            $message .= ", exit code $self->{ force_failure_exitcode } (forced)";
        } else {
            $message .= ", exit code $exitcode";
        }
    }

    $self->print_info( "$message\n" );

    return;
}

# Returns a plain text $msg formatted into something suitable for printing.
# The formatted message may contain some kind of additional info to make it clear
# in build/test logs that the message comes from testrunner.
sub format_info
{
    my ($self, $msg) = @_;

    return "" if (!$msg);

    # Prefix every line with __PACKAGE__ so it is clear where this message comes from
    my $prefix = __PACKAGE__ . ': ';
    $msg =~ s{ \n (?! \z ) }{\n$prefix}gxms;   # replace all newlines except the trailing one
    $msg = $prefix.$msg;

    return $msg;
}

# Print a $msg to the log or stderr, after formatting it via format_info.
sub print_info
{
    my ($self, $msg) = @_;

    return if (!$msg);

    $self->print_to_log_or_stderr( $self->format_info( $msg ) );

    return;
}

# Exit the process with an appropriate exit code, according to the state of
# $proc.
# The testrunner usually exits with same exit code as the child, unless some
# unusual error has occurred.
sub exit_appropriately
{
    my ($self) = @_;

    my $proc = $self->proc( );

    my $status = $proc->status( );
    if ($status == -1) {
        exit( $EXIT_PROCESS_ERROR );
    }

    if ($status & 127) {
        exit( $EXIT_PROCESS_SIGNALED );
    }

    my $exitcode = ($status >> 8);

    # Allow a failure exit code to be forced, for e.g. log validation problems, etc.
    if ($exitcode == 0 && $self->{ force_failure_exitcode }) {
        exit( $self->{ force_failure_exitcode } );
    }

    exit( $exitcode );
}

sub proc
{
    my ($self) = @_;

    return $self->{ proc };
}

sub set_proc
{
    my ($self, $proc) = @_;

    $self->{ proc } = $proc;

    return;
}

sub command
{
    my ($self) = @_;

    return @{$self->{ command_and_args }};
}

sub set_command
{
    my ($self, @command) = @_;

    $self->{ command_and_args } = \@command;

    return;
}

#============================== functions relating to plugins =====================================

# Any .pm file in the testrunner-plugins directory is a plugin.
# For example, a file named `core.pm' will be loaded if testrunner is run with `--plugin core'.
#
# The plugin interface consists of:
#
#   new( testrunner => $self, argv => \@args )
#     Called as each plugin is created.
#     `testrunner' is a reference to the testrunner object.
#     `argv' is a reference to any remaining unprocessed command line arguments.
#     Plugins may use argv to implement additional options.
#     Should return a plugin object.
#
#   about_to_run( \@argv )
#     Called prior to running the process.
#     `argv' is a reference to the command and arguments about to be run; the plugin
#     is permitted to rewrite these.
#     Should return nothing.
#
#   run_completed( )
#     Called after running the process.
#     Should return nothing, or a hashref with the following keys:
#       retry                  =>  if 1, testrunner is requested to run this test again
#       force_failure_exitcode =>  if non-zero, the exit code of testrunner is forced to this,
#                                  even if the test succeeded
#
# Plugins are permitted to do anything.  So, take care :)

sub plugins_init
{
    my ($self, $argv_ref) = @_;

    my @plugin_names = @{$self->{ plugin_names } // []};

    my $plugin_dir = catfile(
        dirname( realpath( $0 ) ),  # directory containing this script (symlinks resolved)
        'testrunner-plugins',
    );

    ### Requested plugins: @plugin_names
    ### Looking in       : $plugin_dir

    foreach my $plugin_name (@plugin_names) {
        my $plugin_file = catfile( $plugin_dir, "$plugin_name.pm" );
        if (! -f $plugin_file) {
            croak "requested plugin $plugin_name does not exist (looked at $plugin_file)";
        }

        require $plugin_file;

        my $plugin_class  = __PACKAGE__ . "::Plugin::$plugin_name";
        my $plugin_object = eval {
            $plugin_class->new( testrunner => $self, argv => $argv_ref )
        };

        if (! $plugin_object) {
            croak "internal error: $plugin_file loaded OK, "
                 ."but $plugin_class could not be instantiated: $@";
        }

        ### Loaded plugin: $plugin_class

        push @{$self->{ plugin_objects }}, $plugin_object;
    }

    return;
}

sub plugins_about_to_run
{
    my ($self, @args) = @_;

    foreach my $plugin (@{$self->{ plugin_objects }}) {
        ### about_to_run on plugin: $plugin
        if ($plugin->can( 'about_to_run' )) {
            $plugin->about_to_run( @args )
        }
    }

    return;
}

sub plugins_run_completed
{
    my ($self, @args) = @_;

    # These are the keys understood in the return value of run_completed
    my @possible_option_keys = qw(
        force_failure_exitcode
        retry
    );

    # All options are disabled by default
    my %options = map { $_ => 0 } @possible_option_keys;

    foreach my $plugin (@{$self->{ plugin_objects }}) {
        my $plugin_options;

        ### run_completed on plugin: $plugin
        if ($plugin->can( 'run_completed' )) {
            $plugin_options = $plugin->run_completed( @args );
        }

        if ($plugin_options && ref($plugin_options) eq 'HASH') {
            %options = map {
                # plugins may turn options on, never off
                $_ => ($options{$_} || $plugin_options->{$_})
            } @possible_option_keys;
        }
    }

    return \%options;
}

#==================================================================================================

QtQA::App::TestRunner->new( )->run( @ARGV ) if (!caller);
1;

