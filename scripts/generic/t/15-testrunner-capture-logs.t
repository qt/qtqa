#!/usr/bin/env perl
use 5.010;
use strict;
use warnings;
use utf8;

=head1 NAME

15-testrunner-capture-logs.t - tests for testrunner.pl's log capturing

=head1 SYNOPSIS

  perl ./15-testrunner-capture-logs.t [--debug]

This test will run the testrunner.pl script with various types of logging
from subprocesses, verifying that the logs are captured correctly.

If --debug is given, temporary files are left behind for inspection after
the test completes.

=cut

use Capture::Tiny qw( capture );
use Carp;
use Encode qw( encode_utf8 );
use English qw( -no_match_vars );
use File::Path qw( rmtree );
use File::Slurp qw( read_file );
use File::Temp qw( tempdir );
use FindBin;
use Getopt::Long;
use IO::Handle;
use Readonly;
use Test::More;
use Time::HiRes qw( sleep );

use lib "$FindBin::Bin/../../lib/perl5";
use Qt::Test::More qw( is_or_like );

# Stream markers for use in TEST_OUTPUT
Readonly my $STREAM_OUTPUT        => 1;  # well-behaved output, to stdout or to -o testlog
Readonly my $STREAM_ERROR         => 2;  # standard error
Readonly my $STREAM_OUTPUT_STDOUT => 3;  # badly behaved output, goes to stdout even in -o mode

# Various test texts we can output
Readonly my %TEST_OUTPUT => (
    mixed => [
        $STREAM_OUTPUT        => "1:testlog\n2:testlog\n",
        $STREAM_ERROR         => "1:stderr\n2:stderr\n",
        $STREAM_OUTPUT_STDOUT => "1:stdout\n2:stdout\n",
        $STREAM_OUTPUT_STDOUT => "3:stdout\n4:stdout\n",
        $STREAM_ERROR         => "3:stderr\n4:stderr\n",
        $STREAM_OUTPUT        => "3:testlog\n4:testlog\n",
    ],
    mixed_nonascii => [
        $STREAM_OUTPUT        => encode_utf8( "1:testlog:早上好\n2:testlog:你好马？\n" ),
        $STREAM_ERROR         => encode_utf8( "1:stderr:早上好\n2:stderr:你好马？\n" ),
        $STREAM_OUTPUT_STDOUT => encode_utf8( "1:stdout:早上好\n2:stdout:你好马？\n" ),
        $STREAM_OUTPUT_STDOUT => encode_utf8( "3:stdout:早上好\n4:stdout:你好马？\n" ),
        $STREAM_ERROR         => encode_utf8( "3:stderr:早上好\n4:stderr:你好马？\n" ),
        $STREAM_OUTPUT        => encode_utf8( "3:testlog:早上好\n4:testlog:你好马？\n" ),
    ],
);

# Command used to output the above and handle `-o somefile' in testlib-compatible way
Readonly my @TEST_COMMAND => (
    'perl',     # force `perl', not `$EXECUTABLE_NAME', as test log naming depends on it
    '-e',
    "do q{$0} || die; run_from_subprocess( )",  # call run_from_subprocess in this file
    '--',                                       # tell perl interpreter not to handle any more args
);

# Testrunner script
Readonly my @TESTRUNNER => (
    $EXECUTABLE_NAME,
    "$FindBin::Bin/../testrunner.pl",
);

# Whether or not we appear to have superuser permissions (used to skip one test)
Readonly my $IS_SUPERUSER
    =>  ($EFFECTIVE_USER_ID == 0)          # unix:    are we root?
     || ($OSNAME            =~ m{win32}i)  # windows: no sane way to tell for now, so be safe
                                           #          and always act like we're an admin
;

# Do a test run for a single dataset.
#
# Parameters:
#  a single hashref, with keys (all optional):
#   command          =>   command to run (defaults to @TEST_COMMAND)
#   command_args     =>   arrayref of extra args to pass to command (defaults to nothing)
#   testname         =>   test name passed into Test::More functions
#   testrunner_args  =>   arrayref of extra args to pass to testrunner
#   expected_success =>   0 if testrunner is expected to fail (non-zero exit code)
#   expected_stdout  =>   expected standard output of subprocess (text or regex)
#   expected_stderr  =>   expected standard error of subprocess (text or regex)
#   expected_logfile =>   expected log file which should be created by subprocess (if any)
#   expected_logtext =>   expected content of the above logfile (text or regex)
#
sub run_one_test
{
    my ($arg_ref) = @_;

    my @command          = @{$arg_ref->{ command }              // \@TEST_COMMAND};
    my @command_args     = @{$arg_ref->{ command_args }         // []};
    my @testrunner_args  = @{$arg_ref->{ testrunner_args }      // ['--']};
    my $expected_success =   $arg_ref->{ expected_success }     // 1;
    my $expected_stdout  =   $arg_ref->{ expected_stdout }      // "";
    my $expected_stderr  =   $arg_ref->{ expected_stderr }      // "";
    my $expected_logfile =   $arg_ref->{ expected_logfile };
    my $expected_logtext =   $arg_ref->{ expected_logtext }     // "";
    my $testname         =   $arg_ref->{ testname };

    if ($expected_logfile) {
        # Ensure the log file doesn't exist prior to the test (should "never" happen)
        ok( ! -e $expected_logfile, "$testname logfile doesn't exist prior to test" );
    }

    my $status;
    my ($stdout, $stderr) = capture {
        $status = system( @TESTRUNNER, @testrunner_args, @command, @command_args );
    };

    if ($expected_success) {
        is( $status, 0, "$testname exited with zero exit code" );
    }
    else {
        isnt( $status, 0, "$testname exited with non-zero exit code" );
    }

    is_or_like( $stdout, $expected_stdout, "$testname stdout is as expected" );
    is_or_like( $stderr, $expected_stderr, "$testname stderr is as expected" );

    # The rest of the verification steps are only applicable if a log file is expected and created
    return if (!$expected_logfile);
    return if (!ok( -e $expected_logfile, "$testname created $expected_logfile" ));

    my $logtext = read_file( $expected_logfile );   # dies on error
    is_or_like( $logtext, $expected_logtext, "$testname logtext is as expected" );

    return;
}

#============================== subprocess parts ==================================================
# These are never called in the main test process, they are called by `perl -e' subprocesses

# Open and return a writable FH to the specified $filename (which may be - for STDOUT)
sub open_log_fh
{
    my ($filename) = @_;

    if ($filename eq '-') {
        return IO::Handle->new_from_fd(fileno(STDOUT), 'w') || confess "internal error: open STDOUT for write: $!";
    }

    open( my $out, '>', $filename ) || confess "internal error: open $filename for write: $!";
    return $out;
}

# Iterate through a set of testdata and print each chunk to the correct stream.
#
# Parameters:
#   a hashref with the following keys:
#     content   =>  test data array (a value from %TEST_OUTPUT)
#     filename  =>  the file to be used as a log file (or - for STDOUT)
#
sub print_testdata
{
    my ($arg_ref) = @_;

    my $content  = $arg_ref->{ content };
    my $filename = $arg_ref->{ filename };

    my $log_fh = open_log_fh( $filename );

    # $content is an arrayref of (stream, text) pairs, which determine what
    # text is printed and to which stream(s).  For example:
    #
    # [
    #     $STREAM_STDOUT  =>  'This line should be printed to STDOUT',
    #     $STREAM_STDERR  =>  'This line should be printed to STDERR',
    # ]
    #

    my @text_chunks = @{$content};
    while (@text_chunks) {
        my $stream = shift @text_chunks;
        my $text   = shift @text_chunks;

        confess 'internal error: odd number of elements in testdata' if (! defined $text);

        # These prints are all flushed to ensure that line ordering is correct in the case
        # where $log_fh is another handle to STDOUT or STDERR.
        if ($stream == $STREAM_OUTPUT) {
            $log_fh->printflush( $text );
        }
        elsif ($stream == $STREAM_ERROR) {
            STDERR->printflush( $text );
        }
        elsif ($stream == $STREAM_OUTPUT_STDOUT) {
            STDOUT->printflush( $text );
        }
        else {
            confess "internal error: bad test stream $stream in testdata";
        }

        # This is effectively a yield to the parent process, to give it a chance to read
        # our output one line at a time.  If we don't do this, we may easily fill up both
        # the buffers in the parent connected to our stdout/stderr, and information about
        # the order is lost.
        sleep 0.05;
    }

    close( $log_fh ) || confess "internal error: close $filename after write: $!";

    return;
}

# Primary entry point for test subprocess.
sub run_from_subprocess
{
    my $exitcode        = 0;
    my $output_filename = '-';
    my $output_content;
    my $skip_log;

    GetOptions(
        'o=s'               =>  \$output_filename,
        'maxwarnings=s'     =>  sub {},             # don't care, just emulating testlib
        'exitcode=i'        =>  \$exitcode,
        'skip-log'          =>  \$skip_log,
    ) || die;

    # If skiplog is set, we ignore the -o option, to simulate a badly behaved test
    # which has been passed -o but ignored it (e.g. because QTest::qExec was used
    # incorrectly).
    if ($skip_log) {
        $output_filename = '-';
    }

    $output_content = shift @ARGV;

    confess 'internal error: not enough arguments'
        if (!$output_content);

    confess "internal error: `$output_content' is not valid testdata"
        if (!$TEST_OUTPUT{$output_content});

    print_testdata({
        content     =>  $TEST_OUTPUT{$output_content},
        filename    =>  $output_filename,
    });

    exit $exitcode;
}

#==================================================================================================

# Primary entry point for the test.
sub run
{
    my $debug;

    GetOptions(
        'debug' => \$debug,
    ) || die;

    my $tempdir = tempdir( 'qtqa-test-capture-logs.XXXXXX', TMPDIR => 1, CLEANUP => !$debug );
    if ($debug) {
        diag( "Using $tempdir as temporary directory" );
    }


    ###############################################################################################
    # Basic controls to ensure output is correct when there is no capturing
    run_one_test({
        testname         => 'mixed no capturing failing',
        command_args     => [ '--exitcode', 2, 'mixed' ],
        expected_stdout  =>
            "1:testlog\n2:testlog\n"
           ."1:stdout\n2:stdout\n"
           ."3:stdout\n4:stdout\n"
           ."3:testlog\n4:testlog\n"
        ,
        expected_stderr  =>
            "1:stderr\n2:stderr\n"
           ."3:stderr\n4:stderr\n"
        ,
        expected_success => 0,
    });
    run_one_test({
        testname         => 'mixed_nonascii no capturing',
        command_args     => [ 'mixed_nonascii' ],
        expected_stdout  => encode_utf8(
            "1:testlog:早上好\n2:testlog:你好马？\n"
           ."1:stdout:早上好\n2:stdout:你好马？\n"
           ."3:stdout:早上好\n4:stdout:你好马？\n"
           ."3:testlog:早上好\n4:testlog:你好马？\n"
        ),
        expected_stderr  => encode_utf8(
            "1:stderr:早上好\n2:stderr:你好马？\n"
           ."3:stderr:早上好\n4:stderr:你好马？\n"
        ),
    });


    ###############################################################################################
    # Test simple capture error cases without -o
    SKIP: {
        skip( 'unsafe to run this test as superuser' ) if ($IS_SUPERUSER);

        # We've assumed that /some_notexist_dir:
        #   - does not exist, and
        #   - cannot be created by testrunner (because we're not superuser)
        #
        run_one_test({
            testname         => 'mixed, capture error',
            testrunner_args  => [ '--capture-logs', '/some_notexist_dir', '--'],
            command_args     => [ 'mixed' ],
            expected_stderr  => qr{\Amkdir /some_notexist_dir: Permission denied}ms,
            expected_success => 0,
        });
    }


    ###############################################################################################
    # Test regular capture without -o;
    # since -o is not used, it should capture everything
    rmtree( $tempdir );     # testrunner should create the logdir if necessary
    run_one_test({
        testname         => 'mixed_nonascii with capture',
        testrunner_args  => [ '--capture-logs', $tempdir, '--'],
        command_args     => [ '--exitcode', 3, 'mixed_nonascii' ],
        expected_success => 0,
        expected_logfile => "$tempdir/perl-00.txt",
        expected_logtext => encode_utf8(
            "1:testlog:早上好\n2:testlog:你好马？\n"
           ."1:stderr:早上好\n2:stderr:你好马？\n"
           ."1:stdout:早上好\n2:stdout:你好马？\n"
           ."3:stdout:早上好\n4:stdout:你好马？\n"
           ."3:stderr:早上好\n4:stderr:你好马？\n"
           ."3:testlog:早上好\n4:testlog:你好马？\n"
        ),
    });
    run_one_test({
        testname         => 'mixed_nonascii with tee',
        testrunner_args  => [ '--tee-logs', $tempdir, '--'],
        command_args     => [ 'mixed_nonascii' ],
        expected_logfile => "$tempdir/perl-01.txt", # we didn't clean up, so a new filename is used
        # tee, so stdout and stderr are both captured, and printed:
        expected_stdout  => encode_utf8(
            "1:testlog:早上好\n2:testlog:你好马？\n"
           ."1:stdout:早上好\n2:stdout:你好马？\n"
           ."3:stdout:早上好\n4:stdout:你好马？\n"
           ."3:testlog:早上好\n4:testlog:你好马？\n"
        ),
        expected_stderr  => encode_utf8(
            "1:stderr:早上好\n2:stderr:你好马？\n"
           ."3:stderr:早上好\n4:stderr:你好马？\n"
        ),
        expected_logtext => encode_utf8(
            "1:testlog:早上好\n2:testlog:你好马？\n"
           ."1:stderr:早上好\n2:stderr:你好马？\n"
           ."1:stdout:早上好\n2:stdout:你好马？\n"
           ."3:stdout:早上好\n4:stdout:你好马？\n"
           ."3:stderr:早上好\n4:stderr:你好马？\n"
           ."3:testlog:早上好\n4:testlog:你好马？\n"
        ),
    });
    run_one_test({
        testname         => 'mixed with capture',
        testrunner_args  => [ '--capture-logs', $tempdir, '--'],
        command_args     => [ 'mixed' ],
        expected_logfile => "$tempdir/perl-02.txt",
        expected_logtext =>
            "1:testlog\n2:testlog\n"
           ."1:stderr\n2:stderr\n"
           ."1:stdout\n2:stdout\n"
           ."3:stdout\n4:stdout\n"
           ."3:stderr\n4:stderr\n"
           ."3:testlog\n4:testlog\n"
        ,
    });



    ###############################################################################################
    # Test capture with the usage of -o;
    # in this case, the test writes some of its stuff correctly to the log,
    # but the stuff which instead goes directly to stdout/stderr will be appended to the end
    # of the log by the testrunner.
    rmtree( $tempdir );
    run_one_test({
        testname         => 'mixed_nonascii with capture and -o',
        testrunner_args  => [ '--capture-logs', $tempdir, '--' ],
        command_args     => [ '--exitcode', 12, '-o', 'testlog.log', 'mixed_nonascii' ],
        expected_success => 0,
        # note the naming convention with -o is to reuse the basename and extension
        expected_logfile => "$tempdir/perl-testlog-00.log",
        expected_logtext => encode_utf8(
            "1:testlog:早上好\n2:testlog:你好马？\n"
           ."3:testlog:早上好\n4:testlog:你好马？\n"
           ."\nQt::App::TestRunner: test output additional content directly to stdout/stderr:\n"
           ."1:stderr:早上好\n2:stderr:你好马？\n"
           ."1:stdout:早上好\n2:stdout:你好马？\n"
           ."3:stdout:早上好\n4:stdout:你好马？\n"
           ."3:stderr:早上好\n4:stderr:你好马？\n"
        ),
    });
    run_one_test({
        testname         => 'mixed with capture and -o',
        testrunner_args  => [ '--capture-logs', $tempdir, '--' ],
        command_args     => [ '-o', 'testlog.log', 'mixed' ],
        expected_logfile => "$tempdir/perl-testlog-01.log",
        expected_logtext =>
            "1:testlog\n2:testlog\n"
           ."3:testlog\n4:testlog\n"
           ."\nQt::App::TestRunner: test output additional content directly to stdout/stderr:\n"
           ."1:stderr\n2:stderr\n"
           ."1:stdout\n2:stdout\n"
           ."3:stdout\n4:stdout\n"
           ."3:stderr\n4:stderr\n"
        ,
    });
    run_one_test({
        testname         => 'mixed with capture and -o and tee',
        testrunner_args  => [ '--tee-logs', $tempdir, '--' ],
        command_args     => [ '-o', 'testlog.log', 'mixed' ],
        expected_logfile => "$tempdir/perl-testlog-02.log",
        expected_logtext =>
            "1:testlog\n2:testlog\n"
           ."3:testlog\n4:testlog\n"
           ."\nQt::App::TestRunner: test output additional content directly to stdout/stderr:\n"
           ."1:stderr\n2:stderr\n"
           ."1:stdout\n2:stdout\n"
           ."3:stdout\n4:stdout\n"
           ."3:stderr\n4:stderr\n"
        ,
        expected_stdout  =>
            "1:stdout\n2:stdout\n"
           ."3:stdout\n4:stdout\n"
        ,
        expected_stderr  =>
            "1:stderr\n2:stderr\n"
           ."3:stderr\n4:stderr\n"
        ,
    });



    ###############################################################################################
    # Make sure the options parser doesn't get tricked by bizarre options like
    # `-maxwarnings -o somefile', where -o is a value and not an option
    run_one_test({
        testname         => 'mixed_nonascii with capture and tricky arguments',
        testrunner_args  => [ '--capture-logs', $tempdir, '--' ],
        command_args     => [ '--exitcode', 50, '-maxwarnings', '-o', 'mixed_nonascii' ],
        expected_success => 0,
        expected_logfile => "$tempdir/perl-00.txt",
        # despite appearances, there was no -o option, so we expect a "raw" capture of everything
        expected_logtext => encode_utf8(
            "1:testlog:早上好\n2:testlog:你好马？\n"
           ."1:stderr:早上好\n2:stderr:你好马？\n"
           ."1:stdout:早上好\n2:stdout:你好马？\n"
           ."3:stdout:早上好\n4:stdout:你好马？\n"
           ."3:stderr:早上好\n4:stderr:你好马？\n"
           ."3:testlog:早上好\n4:testlog:你好马？\n"
        ),
    });
    run_one_test({
        testname         => 'mixed with capture and tricky arguments',
        testrunner_args  => [ '--capture-logs', $tempdir, '--' ],
        command_args     => [ '-maxwarnings', '-o', 'mixed' ],
        expected_logfile => "$tempdir/perl-01.txt",
        expected_logtext =>
            "1:testlog\n2:testlog\n"
           ."1:stderr\n2:stderr\n"
           ."1:stdout\n2:stdout\n"
           ."3:stdout\n4:stdout\n"
           ."3:stderr\n4:stderr\n"
           ."3:testlog\n4:testlog\n"
        ,
    });



    ###############################################################################################
    # test capture when -o is passed to test, but is ignored (badly behaved test)
    rmtree( $tempdir );
    run_one_test({
        testname         => 'mixed with capture and ignored -o',
        testrunner_args  => [ '--capture-logs', $tempdir, '--' ],
        command_args     => [ '-o', 'testlog.log', '--skip-log', 'mixed' ],
        expected_success => 0,  # failure should be forced even though exit code of test is 0
        expected_logfile => "$tempdir/perl-testlog-00.log",
        expected_logtext =>
            "Qt::App::TestRunner: FAIL! Test was badly behaved, the `-o' argument was ignored.\n"
           ."Qt::App::TestRunner: stdout/stderr follows:\n"
           ."1:testlog\n2:testlog\n"
           ."1:stderr\n2:stderr\n"
           ."1:stdout\n2:stdout\n"
           ."3:stdout\n4:stdout\n"
           ."3:stderr\n4:stderr\n"
           ."3:testlog\n4:testlog\n"
        ,
    });
    run_one_test({
        testname         => 'mixed_nonascii with capture and ignored -o',
        testrunner_args  => [ '--capture-logs', $tempdir, '--' ],
        command_args     => [ '--exitcode', 23, '-o', 'testlog.log.txt',
                              '--skip-log', 'mixed_nonascii' ],
        expected_success => 0,
        expected_logfile => "$tempdir/perl-testlog.log-00.txt",
        expected_logtext => encode_utf8(
            "Qt::App::TestRunner: FAIL! Test was badly behaved, the `-o' argument was ignored.\n"
           ."Qt::App::TestRunner: stdout/stderr follows:\n"
           ."1:testlog:早上好\n2:testlog:你好马？\n"
           ."1:stderr:早上好\n2:stderr:你好马？\n"
           ."1:stdout:早上好\n2:stdout:你好马？\n"
           ."3:stdout:早上好\n4:stdout:你好马？\n"
           ."3:stderr:早上好\n4:stderr:你好马？\n"
           ."3:testlog:早上好\n4:testlog:你好马？\n"
        ),
    });
    run_one_test({
        testname         => 'mixed_nonascii with capture and ignored -o and tee',
        testrunner_args  => [ '--tee-logs', $tempdir, '--' ],
        command_args     => [ '-o', 'testlog.log.txt', '--skip-log', 'mixed_nonascii' ],
        expected_logtext => encode_utf8(
            "Qt::App::TestRunner: FAIL! Test was badly behaved, the `-o' argument was ignored.\n"
           ."Qt::App::TestRunner: stdout/stderr follows:\n"
           ."1:testlog:早上好\n2:testlog:你好马？\n"
           ."1:stderr:早上好\n2:stderr:你好马？\n"
           ."1:stdout:早上好\n2:stdout:你好马？\n"
           ."3:stdout:早上好\n4:stdout:你好马？\n"
           ."3:stderr:早上好\n4:stderr:你好马？\n"
           ."3:testlog:早上好\n4:testlog:你好马？\n"
        ),
        expected_stdout  => encode_utf8(
            "1:testlog:早上好\n2:testlog:你好马？\n"
           ."1:stdout:早上好\n2:stdout:你好马？\n"
           ."3:stdout:早上好\n4:stdout:你好马？\n"
           ."3:testlog:早上好\n4:testlog:你好马？\n"
        ),
        expected_stderr  => encode_utf8(
            "1:stderr:早上好\n2:stderr:你好马？\n"
           ."3:stderr:早上好\n4:stderr:你好马？\n"
        ),
        expected_logfile => "$tempdir/perl-testlog.log-01.txt",
        expected_success => 0,
    });


    ###############################################################################################
    # test that Proc::Reliable errors are correctly captured/teed
    rmtree( $tempdir );
    run_one_test({
        testname         => 'capture error nonexistent process',
        testrunner_args  => [ '--capture-logs', $tempdir, '--'],
        command          => [ 'command_which_does_not_exist' ],
        expected_logfile => "$tempdir/command_which_does_not_exist-00.txt",
        expected_logtext => 'Qt::App::TestRunner: command_which_does_not_exist: '
                           ."No such file or directory\n",
        expected_stderr  => "",
        expected_success => 0,
    });
    run_one_test({
        testname         => 'tee error nonexistent process',
        testrunner_args  => [ '--tee-logs', $tempdir, '--'],
        command          => [ 'command_which_does_not_exist' ],
        expected_logfile => "$tempdir/command_which_does_not_exist-01.txt",
        expected_logtext => 'Qt::App::TestRunner: command_which_does_not_exist: '
                           ."No such file or directory\n",
        expected_stderr  => 'Qt::App::TestRunner: command_which_does_not_exist: '
                           ."No such file or directory\n",
        expected_success => 0,
    });

    my $crash_rx
        = qr{\AQt::App::TestRunner: Process exited due to signal 11(; dumped core)?\n\z}ms;
    run_one_test({
        testname         => 'capture error crashing',
        testrunner_args  => [ '--capture-logs', $tempdir, '--'],
        command          => [ 'perl', '-e', 'kill 11, $$' ],
        expected_logfile => "$tempdir/perl-00.txt",
        expected_logtext => $crash_rx,
        expected_stderr  => "",
        expected_success => 0,
    });
    run_one_test({
        testname         => 'tee error crashing',
        testrunner_args  => [ '--tee-logs', $tempdir, '--'],
        command          => [ 'perl', '-e', 'kill 11, $$' ],
        expected_logfile => "$tempdir/perl-01.txt",
        expected_logtext => $crash_rx,
        expected_stderr  => $crash_rx,
        expected_success => 0,
    });


    done_testing( );

    return;
}

run if (!caller);
1;
