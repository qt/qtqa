#!/usr/bin/env perl
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

=item B<--timeout> <value>

If the test takes longer than <value> seconds, it will be killed, and
the testrunner will exit with a non-zero exit code to indicate failure.

B<NOTE>: not yet supported on Windows.

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

If the test is run with a testlib-style output file specifier, e.g. C<-o somefile>,
then the testrunner modifies the C<-o> value passed to the test so that the
test writes to a file under the given <directory>.  If the test also writes anything
to stdout/stderr, that will be appended to the log file.  It is considered an error
if the test doesn't generate the log file.

=back

For example, if the following command is run:

  testrunner --capture-logs $HOME/test-logs -- ./tst_qstring -o testlog.txt

...then testrunner may run the test as:

  ./tst_qstring -o $HOME/test-logs/qstring-testlog-00.txt

...and if $HOME/test-logs/qstring-testlog-00.txt does not exist when the test completes,
the test will be considered a failure.

B<NOTE>: not yet supported on Windows.

=item B<--tee-logs> <directory>

Exactly like C<--capture-logs directory>, except that stdout/stderr from the autotest
are also written to stdout/stderr of the testrunner, rather than only being written
to the captured log file.

B<NOTE>: not yet supported on Windows.

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
to the test log.  (Linux only)

=item flaky

When a test fails, run it again, to help determine if it is unstable.

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

When using --capture-logs / --tee-logs, it is possible for tests to clobber
each other's logs if (1) there exist several tests with the same basename,
and (2) tests are being run in parallel.  This is considered a low priority,
as tests are already known to be generally unsafe to run in parallel.

Currently, it is not advisable to combine the --capture-logs / --tee-logs
options with tests run in XML mode, as testrunner may append messages to the
log which are not valid XML.

=cut

use Getopt::Long qw(
    GetOptionsFromArray
    :config pass_through require_order
);

use Carp;
use Cwd qw( realpath );
use English qw( -no_match_vars );
use File::Basename;
use File::Path qw( mkpath );
use File::Spec::Functions;
use IO::Handle;
use Pod::Usage qw( pod2usage );
use Readonly;

BEGIN {
    # Proc::Reliable is not reliable on Windows
    if ($OSNAME !~ m{win32}i) {
        require Proc::Reliable;
        Proc::Reliable->import( );
    }
}

#use Smart::Comments;    # uncomment for debugging

# a long time, but not forever
Readonly my $LONG_TIME => 60*60*24*7;

# default values for some command-line options
Readonly my %DEFAULTS => (
    timeout => $LONG_TIME,
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

    my $win = ($OSNAME =~ m{win32}i);
    my $disable = sub {
        warn "FIXME: option `$_[0]' is currently not implemented on $OSNAME";
    };

    GetOptionsFromArray( \@args,
        'help|?'            =>  sub { pod2usage(1) },
        'timeout=i'         =>  ($win ? $disable : \$self->{ timeout }),
        'capture-logs=s'    =>  ($win ? $disable : \$self->{ capture_logs }),
        'plugin=s'          =>  \@{$self->{ plugin_names }},
        'tee-logs=s'        =>  ($win ? $disable : \$tee_logs),
    ) || pod2usage(2);

    # tee-logs implies that we both capture the logs, and print the output like `tee'
    if ($tee_logs) {
        $self->{ capture_logs } = $tee_logs;
        $self->{ tee          } = 1;
    }

    $self->plugins_init( );

    $self->do_subprocess( @args );
    $self->exit_appropriately( );

    return;
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
        $basename .= '-'.$args_ref->{ basename };
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

    return $candidate;
}

# Returns the logfile which should be used.  Generates a new filename if necessary.
sub logfile
{
    my ($self) = @_;

    if (!$self->{ logfile }) {
        $self->set_logfile( $self->generate_unique_logfile_name( ) );
    }

    return $self->{ logfile };
}

# Sets the logfile which should be used.
sub set_logfile
{
    my ($self, $logfile) = @_;

    $self->{ logfile } = $logfile;

    return;
}

# Creates a new, empty logfile, and returns an open filehandle to it.
sub create_and_open_logfile
{
    my ($self) = @_;

    my $logfile = $self->logfile( );
    my $logdir  = dirname( $logfile );

    if (! -d $logdir && ! mkpath( $logdir )) {
        $self->exit_with_logging_error( "mkpath $logdir: $!" );
    }

    open( my $fh, '>', $logfile ) || $self->exit_with_logging_error( "open $logfile: $!" );
    return $fh;
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

    # As the logfile, we'll use the rewritten -o option...
    $self->set_logfile( $args_ref->{ replaced_output } );

    # ...but we do _not_ create or open it, as the subprocess is expected to do this.
    $self->{ subprocess_creates_logfile } = 1;

    # We'd better create the directory if it doesn't exist - testlib won't do this.
    my $logdir = $self->{ capture_logs };
    if ((! -d $logdir) && (! mkpath( $logdir ))) {
        $self->exit_with_logging_error( "mkpath $logdir: $!" );
    }

    my $print_sub = sub {
        $self->proc_reliable_print_to_logbuffer(@_);
        if ($self->{ tee }) {
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

    $self->{ logfh } = $self->create_and_open_logfile( );

    my $print_sub = sub {
        $self->proc_reliable_print_to_log(@_);
        if ($self->{ tee }) {
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
#   replaced_output =>  the new value passed to -o, or undef if -o wasn't found
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

        my ($basename, undef, $suffix) = fileparse( $value, qr{\.[^.]*} );
        $out->{ replaced_output } = $self->generate_unique_logfile_name({
            basename    =>  $basename,
            suffix      =>  $suffix,
        });

        push @rewritten_args, "-$option";
        push @rewritten_args, $out->{ replaced_output };
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

# Finish up the logging of $proc, which should have completed by now.
# Additional messages about $proc may be printed if errors occurred.
sub finalize_logging
{
    my ($self) = @_;

    my $proc = $self->proc( );

    # Extra text to put to the log.
    my $extra_log = "";

    # Print out any messages from the Proc::Reliable; this will include information
    # such as "process timed out", etc.
    my $msg = $proc->msg( );
    if ($msg) {
        # Don't mention the `Exceeded retry limit'; we never retry, so it would only be
        # confusing.  Note that this can (and often will) reduce $msg to nothing.
        $msg =~ s{ ^ Exceeded \s retry \s limit \s* }{}xms;
    }

    $extra_log .= $self->format_info( $msg );

    my $status = $proc->status( );
    if ($status == -1 && !$msg) {
        # we should have a msg, but avoid being entirely silent if we don't
        $extra_log .= $self->format_info( "Proc::Reliable failed to run process for unknown reasons\n" );
    }

    my $signal = ($status & 127);
    if ($signal) {
        my $coredumped = ($status & 128);
        $extra_log .= $self->format_info(
            "Process exited due to signal $signal"
           .($coredumped ? '; dumped core' : q{})
           ."\n"
        );
    }

    # Proc::Reliable gives an exit code of 255 if the binary doesn't exist.
    # Try to give a helpful hint about this case.
    # This is racy and not guaranteed to be correct.
    my $exitcode = ($status >> 8);
    if ($exitcode == 255) {
        my $command = ($self->command( ))[0];
        if (! -e $command) {
            $extra_log .= $self->format_info( "$command: No such file or directory\n" );
        }
    }

    if (!$self->{ subprocess_creates_logfile }) {
        # If the logfile was created by us and not the subprocess, or if there was no log
        # file at all, then there is nothing more to finalize.
        # We just have to print the extra log text.
        $self->print_to_log_or_stderr( $extra_log );
        return;
    }

    # In this case, we expect the subprocess to have created a log file, so we have to
    # check that (and also append to it if necessary).
    my $logfile = $self->logfile( );

    if (! -f $logfile) {
        # It is considered an error if the test failed to create the logfile.
        $self->{ force_failure_exitcode } ||= $EXIT_LOGGING_ERROR;
        $self->append_logbuffer_to_logfile( $extra_log . $self->format_info(
            "FAIL! Test was badly behaved, the `-o' argument was ignored.\n"
           ."stdout/stderr follows:\n"
        ));
    }
    else {
        $self->append_logbuffer_to_logfile( $extra_log . $self->format_info(
            "test output additional content directly to stdout/stderr:\n"
        ));
    }

    return;
}

# If we captured any stdout/stderr from the subprocess which hasn't yet been logged,
# append it to the logfile.  If $prefix is given, it is appended to the log file
# prior to other text.
sub append_logbuffer_to_logfile
{
    my ($self, $prefix) = @_;

    # nothing to do if no output was captured
    return if (! defined $self->{ logbuffer });

    my $text = $prefix . $self->{ logbuffer };

    my $logfile = $self->logfile( );

    # If the logfile already exists, we'll put a newline to separate our messages
    # from the existing messages.
    if (-e $logfile) {
        $text = "\n".$text;
    }

    open( my $fh, '>>', $self->logfile( ) )
        || $self->exit_with_logging_error( "open $logfile for append: $!" );

    $fh->print( $text );

    close( $fh )
        || $self->exit_with_logging_error( "close $logfile after append: $!" );

    # Empty the buffer
    return;
}

# Callback for Proc::Reliable which simply prints to the given handle (i.e. non-capturing).
# The first parameter to the callback is the correct IO handle (STDOUT or STDERR)
sub proc_reliable_print_to_handle
{
    my ($self, $handle, @to_print) = @_;

    # flush so we print as much as possible if we're killed without completing
    $handle->printflush( @to_print );

    return;
}

# Callback for Proc::Reliable which prints to a unique log file.
sub proc_reliable_print_to_log
{
    my ($self, $handle, @to_print) = @_;

    # $handle is ignored, instead we print to the log file.
    $self->{ logfh }->printflush( @to_print );

    return;
}

# Print a message to the logfile (if any), or STDERR (if no log), or both (in tee-logs mode)
sub print_to_log_or_stderr
{
    my ($self, @to_print) = @_;

    # flush so the log contains as much as possible if we're killed without completing
    if ($self->{ logfh }) {
        $self->{ logfh }->printflush( @to_print );
    }
    if (!$self->{ logfh } || $self->{ tee }) {
        STDERR->printflush( @to_print );
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

    if ($OSNAME =~ m{win32}i) {
        return $self->create_proc_win32( );
    }

    my $proc = Proc::Reliable->new( );

    $proc->stdin_error_ok( 1 );                 # OK if child does not read all stdin
    $proc->num_tries( 1 );                      # don't automatically retry on error
    $proc->child_exit_time( $LONG_TIME );       # don't consider it an error if the test
                                                # doesn't quit soon after closing stdout
    $proc->time_per_try( $self->{timeout} );    # don't run for longer than this
    $proc->maxtime( $self->{timeout} );         # ...and again (need to set both)
    $proc->want_single_list( 0 );               # force stdout/stderr handled separately

    # Default callbacks just print everything as we receive it.
    # The logging setup function is permitted to change these callbacks.
    $proc->stdout_cb( sub { $self->proc_reliable_print_to_handle(@_) } );
    $proc->stderr_cb( sub { $self->proc_reliable_print_to_handle(@_) } );

    return $proc;
}

sub create_proc_win32
{
    my ($self) = @_;

    return do {
        package QtQA::App::TestRunner::SimpleProc;  ## no critic

        # Implements the minimal subset of Proc::Reliable's API
        # in order to allow testrunner to run the process and not crash

        sub new {  ## no critic
            my ($class) = @_;

            my $self = bless {
                status => 0,
            }, $class;

            return $self;
        }

        sub run {
            my ($self, $command_ref) = @_;

            $self->{ status } = system( @{$command_ref} );

            return;
        }

        sub status {
            my ($self) = @_;

            return $self->{ status };
        }

        sub msg {
            return;
        }

        QtQA::App::TestRunner::SimpleProc->new( );
    };
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

    my $keep_running = 1;
    my $attempt = 1;
    my $force_failure_exitcode;

    while ($keep_running) {

        # Plugins may ask us to force a failure.
        # We clear this at each run so that we only consider forced failures
        # during the _last_ run.
        $force_failure_exitcode = 0;

        $self->plugins_about_to_run( );

        {
            # Put the attempt number into the environment for these reasons:
            #
            #  - makes it easier to write autotests for this feature
            #
            #  - (hopefully) captures the information in core dumps etc
            #    about how many times the test has been run
            #
            local $ENV{ QTQA_APP_TESTRUNNER_ATTEMPT } = $attempt;

            $proc->run( [ $self->command( ) ] );
        }

        my $result = $self->plugins_run_completed( );

        $force_failure_exitcode = $result->{ force_failure_exitcode };

        # We may retry the test any number of times, if some plugin asks us to.
        $keep_running = $result->{ retry };
        ++$attempt;
    }

    $self->{ force_failure_exitcode } ||= $force_failure_exitcode;

    $self->finalize_logging( );

    return $proc;
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
#   new( testrunner => $self )
#     Called as each plugin is created.  `testrunner' is a reference to the testrunner object.
#     Should return a plugin object.
#
#   about_to_run( )
#     Called prior to running the process.
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
    my ($self) = @_;

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
            $plugin_class->new( testrunner => $self )
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

