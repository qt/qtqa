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
use File::Spec::Functions;
use File::Temp qw( tempdir );
use FindBin;
use Getopt::Long;
use IO::Handle;
use Readonly;
use Test::More;
use Time::HiRes qw( sleep );

use lib "$FindBin::Bin/../../lib/perl5";
use QtQA::Test::More qw( is_or_like );

Readonly my $WINDOWS => ($OSNAME =~ m{mswin32}i);

# Directory containing some helper scripts
Readonly my $HELPER_DIR => catfile( $FindBin::Bin, 'helpers' );

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
    "-I$FindBin::Bin/../../lib/perl5",
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
     || $WINDOWS                           # windows: no sane way to tell for now, so be safe
                                           #          and always act like we're an admin
     || ($OSNAME            =~ m{darwin}i) # mac:     users other than root may have elevated
                                           #          permissions, so play it safe
;

# Pattern matching --verbose 'begin' line, without trailing \n.
Readonly my $TESTRUNNER_VERBOSE_BEGIN
    => qr{\QQtQA::App::TestRunner: begin \E.*?:\Q [perl]\E[^\n]*};

# Pattern matching --verbose 'end' line, without trailing \n.
# Ends with [^\n]*, so it can match or not match the exit status portion,
# as appropriate.
Readonly my $TESTRUNNER_VERBOSE_END
    => qr{\QQtQA::App::TestRunner: end \E[^:]+\Q: \E[^\n]*};

# Returns expected error text when a nonexistent $cmd is run
sub error_nonexistent_command
{
    my ($cmd) = @_;

    # Note subtle difference here: on Unix, it is QtQA::App::TestRunner who
    # determines that the command doesn't exist.  On Windows, there is always
    # an intermediate cmd.exe (due to the way system() works on Windows), and
    # that process is the one who determines that the command doesn't exist.
    if ($WINDOWS) {
        return "'$cmd' is not recognized as an internal or external command,\n"
              ."operable program or batch file.\n";
    }

    return "QtQA::App::TestRunner: $cmd: No such file or directory\n";
}

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

    my @expected_logfiles
        = $arg_ref->{ expected_logfiles } ? @{ $arg_ref->{ expected_logfiles } }
        : $expected_logfile               ? ( $expected_logfile )
        :                                   ();

    my @expected_logtexts
        = $arg_ref->{ expected_logtexts } ? @{ $arg_ref->{ expected_logtexts } }
        : $expected_logtext               ? ( $expected_logtext )
        :                                   ();

    if (scalar(@expected_logfiles) != scalar(@expected_logtexts)) {
        die 'test error: expected_logfiles and expected_logtexts count do not match!';
    }

    foreach my $logfile (@expected_logfiles) {
        # Ensure the log file doesn't exist prior to the test (should "never" happen)
        ok( ! -e $logfile, "$testname $logfile doesn't exist prior to test" );
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
    return if (!@expected_logfiles);

    my $i = 0;
    foreach my $logfile (@expected_logfiles) {
        return if (!ok( -e $logfile, "$testname created $logfile" ));

        my $logtext = read_file( $logfile );   # dies on error
        is_or_like( $logtext, $expected_logtexts[$i], "$testname $logfile logtext is as expected" );
        ++$i;
    }

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
    my @output_filenames;
    my $output_content;
    my $skip_log;

    GetOptions(
        'o=s'               =>  \@output_filenames,
        'maxwarnings=s'     =>  sub {},             # don't care, just emulating testlib
        'exitcode=i'        =>  \$exitcode,
        'skip-log'          =>  \$skip_log,
    ) || die;

    # If skiplog is set, we ignore the -o option, to simulate a badly behaved test
    # which has been passed -o but ignored it (e.g. because QTest::qExec was used
    # incorrectly).
    if ($skip_log) {
        @output_filenames = ('-');
    }

    if (!@output_filenames) {
        @output_filenames = ('-');
    }

    $output_content = shift @ARGV;

    confess 'internal error: not enough arguments'
        if (!$output_content);

    confess "internal error: `$output_content' is not valid testdata"
        if (!$TEST_OUTPUT{$output_content});

    foreach my $filename_and_format (@output_filenames) {
        my $filename;
        my $format;

        if ($filename_and_format =~ m{,}) {
            ($filename, $format) = split(/,/, $filename_and_format);
        }
        else {
            $filename = $filename_and_format;
        }

        my $content = $TEST_OUTPUT{$output_content};

        # When printing more than one log, prefix with the format,
        # to verify that we're really getting the right log in the right place.
        if ($format) {
            $content = [
                $STREAM_OUTPUT => "format:$format\n",
                @{ $content },
            ];
        }

        print_testdata({
            content     =>  $content,
            filename    =>  $filename,
        });
    }

    exit $exitcode;
}

#==================================================================================================

# Calculate a set of regular expressions to match sequences of lines.
#
# Input: a list of arrayrefs, each containing a sequence of lines (strings or regular expressions,
# _without_ trailing \n)
#
# Returns: an arrayref containing a set of regular expressions.  Some text satisfies _all_ the
# line sequences only if _all_ the regular expressions match.
#
# The primary use case for this function is to match the output of commands/logs where
# both STDOUT and STDERR should be separately checked.  In this case, there are multiple output
# streams, and the order of output from each stream can be guaranteed but the order of output
# _between_ streams cannot.
#
# Example:
#
#   my $rx = rx_for_lines(
#       [
#           "stdout line one",
#           "stdout line two",
#       ],
#       [
#           "stderr line one",
#           "stderr line two",
#       ],
#   );
#   is_or_like( $some_text, $rx );
#
# In this example, is_or_like will pass only if the following is true:
#
#   - $some_text contains exactly 4 lines of output
#   - $some_text contains both "stdout line one\n" and "stdout line two\n", in that order
#   - $some_text contains both "stderr line one\n" and "stderr line two\n", in that order
#
# The comparison will succeed regardless of the order of stdout/stderr interleaving
# (as long as line-based flushing was used on stdout/stderr).
#
sub rx_for_lines
{
    my (@line_refs) = @_;

    my @out;

    my $line_count = 0;

    foreach my $lines (@line_refs) {
        my @rx_lines = map {
            if (ref($_) eq 'Regexp') {
                "$_";
            } else {
                quotemeta($_).'\n'
            }
        } @{$lines};
        $line_count += scalar( @rx_lines );

        my $rx;

        # First line
        $rx .= q{
            (?:         # First line may appear in two cases:
                \A      # (1) very first line in the text
                |
                \n      # (2) not the first line in the text
            )
        };

        # Rest of lines
        $rx .= join( q{
            .*?       # 0 or more of any character between lines
            (?<=\n)   # lines must follow a \n (but that must not be consumed, because
                      # it may be the \n at the end of the previously matched line)
        }, @rx_lines );

        push @out, qr{$rx}xms;
    }

    # The above regular expressions ensure we get all lines in the correct order.
    # Finally, add an rx to make sure we got exactly the correct amount of lines.
    push @out, qr/
        \A                             # beginning ...
        (?: [^\n]* \n ){$line_count}   # exactly $line_count newline characters
        [^\n]*                         # maybe some other stuff between last \n and end of text
        \z                             # end
    /xms;

    return \@out;
}

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
        skip( 'unsafe to run this test as superuser', 1 ) if ($IS_SUPERUSER);

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
        expected_logtext => rx_for_lines(
            [map { encode_utf8($_) } qw(
                1:testlog:早上好
                2:testlog:你好马？
                1:stdout:早上好
                2:stdout:你好马？
                3:stdout:早上好
                4:stdout:你好马？
                3:testlog:早上好
                4:testlog:你好马？
            )],
            [map { encode_utf8($_) } qw(
                1:stderr:早上好
                2:stderr:你好马？
                3:stderr:早上好
                4:stderr:你好马？
            )],
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
        expected_logtext => rx_for_lines(
            [map { encode_utf8($_) } qw(
                1:testlog:早上好
                2:testlog:你好马？
                1:stdout:早上好
                2:stdout:你好马？
                3:stdout:早上好
                4:stdout:你好马？
                3:testlog:早上好
                4:testlog:你好马？
            )],
            [map { encode_utf8($_) } qw(
                1:stderr:早上好
                2:stderr:你好马？
                3:stderr:早上好
                4:stderr:你好马？
            )],
        ),
    });
    run_one_test({
        testname         => 'mixed with capture',
        testrunner_args  => [ '--sync-output', '--verbose', '--capture-logs', $tempdir, '--'],
        command_args     => [ 'mixed' ],
        expected_logfile => "$tempdir/perl-02.txt",
        expected_logtext => rx_for_lines(
            [
                $TESTRUNNER_VERBOSE_BEGIN,
                qw(
                    1:testlog
                    2:testlog
                    1:stdout
                    2:stdout
                    3:stdout
                    4:stdout
                    3:testlog
                    4:testlog
                ),
                qr{$TESTRUNNER_VERBOSE_END, exit code 0},
            ],
            [qw(
                1:stderr
                2:stderr
                3:stderr
                4:stderr
            )],
        ),
    });



    ###############################################################################################
    # Test capture with the usage of -o;
    # in this case, the test writes some of its stuff correctly to the log,
    # but the stuff which instead goes directly to stdout/stderr will be appended to the end
    # of the log by the testrunner.
    rmtree( $tempdir );
    run_one_test({
        testname         => 'mixed_nonascii with capture and verbose and -o',
        testrunner_args  => [ '--capture-logs', $tempdir, '--verbose', '--' ],
        command_args     => [ '--exitcode', 12, '-o', 'testlog.log', 'mixed_nonascii' ],
        expected_success => 0,
        # note the naming convention with -o is to reuse the basename and extension
        expected_logfile => "$tempdir/perl-testlog-00.log",
        expected_logtext => rx_for_lines(
            [map { encode_utf8($_) } qw(
                1:testlog:早上好
                2:testlog:你好马？
                3:testlog:早上好
                4:testlog:你好马？
                ),
                q{},
                qq{QtQA::App::TestRunner: test output additional content directly to stdout/stderr:},
            ],
            [map { encode_utf8($_) } qw(
                1:stderr:早上好
                2:stderr:你好马？
                3:stderr:早上好
                4:stderr:你好马？
            )],
            [map { encode_utf8($_) } qw(
                1:stdout:早上好
                2:stdout:你好马？
                3:stdout:早上好
                4:stdout:你好马？
            )],
        ),
        # Known limitation: with --capture-logs and -o, these messages can't go to
        # the captured log, because they may be printed before the test has created
        # the log file.
        expected_stderr => qr{
            \A
            $TESTRUNNER_VERBOSE_BEGIN \n
            $TESTRUNNER_VERBOSE_END \Q, exit code 12\E\n
            \z
        }xms,
    });
    run_one_test({
        testname         => 'mixed with capture and -o',
        testrunner_args  => [ '--capture-logs', $tempdir, '--' ],
        command_args     => [ '-o', 'testlog.log', 'mixed' ],
        expected_logfile => "$tempdir/perl-testlog-01.log",
        expected_logtext => rx_for_lines(
            [qw(
                1:testlog
                2:testlog
                3:testlog
                4:testlog
                ),
                q{},
                qq{QtQA::App::TestRunner: test output additional content directly to stdout/stderr:},
            ],
            [qw(
                1:stderr
                2:stderr
                3:stderr
                4:stderr
            )],
            [qw(
                1:stdout
                2:stdout
                3:stdout
                4:stdout
            )],
        ),
    });
    run_one_test({
        testname         => 'mixed with capture and -o and tee',
        testrunner_args  => [ '--sync-output', '--tee-logs', $tempdir, '--' ],
        command_args     => [ '-o', 'testlog.log', 'mixed' ],
        expected_logfile => "$tempdir/perl-testlog-02.log",
        expected_logtext => rx_for_lines(
            [qw(
                1:testlog
                2:testlog
                3:testlog
                4:testlog
                ),
                q{},
                qq{QtQA::App::TestRunner: test output additional content directly to stdout/stderr:},
            ],
            [qw(
                1:stderr
                2:stderr
                3:stderr
                4:stderr
            )],
            [qw(
                1:stdout
                2:stdout
                3:stdout
                4:stdout
            )],
        ),
        # because we used --sync-output, stdout and stderr are merged
        expected_stdout  =>
            "1:stderr\n2:stderr\n"
           ."1:stdout\n2:stdout\n"
           ."3:stdout\n4:stdout\n"
           ."3:stderr\n4:stderr\n"
        ,
    });



    ###############################################################################################
    # Capture with the new testlib simultaneous loggers.
    # If we capture with:
    #
    #   -o file1,fmt1 -o file2,fmt2 -o -,fmt3
    #
    # ... then the testrunner should capture file1 and file2, but should pass through the third
    # stream (fmt3) to stdout as normal.  stderr is also passed through uncaptured.
    #
    run_one_test({
        testname         => 'mixed_nonascii new style -o, capture, multiple logs',
        testrunner_args  => [ '--capture-logs', $tempdir, '--' ],
        command_args     => [ '-o', 'testlog.xml,xml', '-o', 'testlog.xunitxml,xunitxml', '-o', '-,txt', 'mixed_nonascii' ],
        expected_logfiles => [ "$tempdir/perl-testlog-00.xml", "$tempdir/perl-testlog-00.xunitxml" ],
        expected_logtexts => [

            # first log: xml format
            encode_utf8(
                "format:xml\n"
               ."1:testlog:早上好\n"
               ."2:testlog:你好马？\n"
               ."3:testlog:早上好\n"
               ."4:testlog:你好马？\n"
            ),

            # second log: xunitxml format
            encode_utf8(
                "format:xunitxml\n"
               ."1:testlog:早上好\n"
               ."2:testlog:你好马？\n"
               ."3:testlog:早上好\n"
               ."4:testlog:你好马？\n"
            ),
        ],
        expected_stdout  => encode_utf8(
            # we get the first portion of stdout also from the first two loggers
            "1:stdout:早上好\n2:stdout:你好马？\n"
           ."3:stdout:早上好\n4:stdout:你好马？\n"
           ."1:stdout:早上好\n2:stdout:你好马？\n"
           ."3:stdout:早上好\n4:stdout:你好马？\n"
           ."format:txt\n"
           ."1:testlog:早上好\n2:testlog:你好马？\n"
           ."1:stdout:早上好\n2:stdout:你好马？\n"
           ."3:stdout:早上好\n4:stdout:你好马？\n"
           ."3:testlog:早上好\n4:testlog:你好马？\n"
        ),
        expected_stderr  => encode_utf8(
            (
                "1:stderr:早上好\n2:stderr:你好马？\n"
               ."3:stderr:早上好\n4:stderr:你好马？\n"
            ) x 3   # three loggers, so printed three times
        ),
    });



    ###############################################################################################
    # Tee with the new testlib simultaneous loggers.
    # If we tee with:
    #
    #   -o file1,fmt1 -o file2,fmt2 -o -,fmt3
    #
    # ... the behavior is exactly the same as capture-logs.
    # It is explicitly documented that tee-logs and capture-logs is the same thing in the
    # multi-logger case, since testlib already is implementing the tee-like behavior.
    #
    run_one_test({
        testname         => 'mixed_nonascii new style -o, tee, multiple logs, one stdout',
        testrunner_args  => [ '--tee-logs', $tempdir, '--' ],
        command_args     => [ '-o', 'testlog.xml,xml', '-o', 'testlog.txt,txt', '-o', '-,txt', 'mixed_nonascii' ],
        expected_logfiles => [ "$tempdir/perl-testlog-01.xml", "$tempdir/perl-testlog-00.txt" ],
        expected_logtexts => [

            # first log: xml format, non-log text is not captured
            encode_utf8(
                "format:xml\n"
               ."1:testlog:早上好\n"
               ."2:testlog:你好马？\n"
               ."3:testlog:早上好\n"
               ."4:testlog:你好马？\n"
            ),

            # second log: text format, non-log text is not captured
            encode_utf8(
                "format:txt\n"
               ."1:testlog:早上好\n"
               ."2:testlog:你好马？\n"
               ."3:testlog:早上好\n"
               ."4:testlog:你好马？\n"
            ),
        ],
        expected_stdout  => encode_utf8(
            # we get the first portion of stdout also from the first two loggers
            "1:stdout:早上好\n2:stdout:你好马？\n"
           ."3:stdout:早上好\n4:stdout:你好马？\n"
           ."1:stdout:早上好\n2:stdout:你好马？\n"
           ."3:stdout:早上好\n4:stdout:你好马？\n"
           ."format:txt\n"
           ."1:testlog:早上好\n2:testlog:你好马？\n"
           ."1:stdout:早上好\n2:stdout:你好马？\n"
           ."3:stdout:早上好\n4:stdout:你好马？\n"
           ."3:testlog:早上好\n4:testlog:你好马？\n"
        ),
        expected_stderr  => encode_utf8(
            (
                "1:stderr:早上好\n2:stderr:你好马？\n"
               ."3:stderr:早上好\n4:stderr:你好马？\n"
            ) x 3   # three loggers, so printed three times
        ),
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
        expected_logtext => rx_for_lines(
            [map { encode_utf8($_) } qw(
                1:testlog:早上好
                2:testlog:你好马？
                1:stdout:早上好
                2:stdout:你好马？
                3:stdout:早上好
                4:stdout:你好马？
                3:testlog:早上好
                4:testlog:你好马？
            )],
            [map { encode_utf8($_) } qw(
                1:stderr:早上好
                2:stderr:你好马？
                3:stderr:早上好
                4:stderr:你好马？
            )],
        ),
    });
    run_one_test({
        testname         => 'mixed with capture and tricky arguments',
        testrunner_args  => [ '--capture-logs', $tempdir, '--' ],
        command_args     => [ '-maxwarnings', '-o', 'mixed' ],
        expected_logfile => "$tempdir/perl-01.txt",
        expected_logtext => rx_for_lines(
            [qw(
                1:testlog
                2:testlog
                1:stdout
                2:stdout
                3:stdout
                4:stdout
                3:testlog
                4:testlog
            )],
            [qw(
                1:stderr
                2:stderr
                3:stderr
                4:stderr
            )],
        ),
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
        expected_logtext => rx_for_lines(
            [
                q{Log file created by QtQA::App::TestRunner},
                q{},
                q{QtQA::App::TestRunner: FAIL! Test was badly behaved, the `-o' argument was ignored.},
                q{QtQA::App::TestRunner: stdout/stderr follows:},
                qw(
                    1:testlog
                    2:testlog
                    1:stdout
                    2:stdout
                    3:stdout
                    4:stdout
                    3:testlog
                    4:testlog
                )
            ],
            [qw(
                1:stderr
                2:stderr
                3:stderr
                4:stderr
            )],
        ),
    });
    run_one_test({
        testname         => 'mixed_nonascii with capture and ignored -o',
        testrunner_args  => [ '--capture-logs', $tempdir, '--' ],
        command_args     => [ '--exitcode', 23, '-o', 'testlog.log.txt',
                              '--skip-log', 'mixed_nonascii' ],
        expected_success => 0,
        expected_logfile => "$tempdir/perl-testlog.log-00.txt",
        expected_logtext => rx_for_lines(
            [
                q{Log file created by QtQA::App::TestRunner},
                q{},
                q{QtQA::App::TestRunner: FAIL! Test was badly behaved, the `-o' argument was ignored.},
                q{QtQA::App::TestRunner: stdout/stderr follows:},
                map { encode_utf8($_) } qw(
                    1:testlog:早上好
                    2:testlog:你好马？
                    1:stdout:早上好
                    2:stdout:你好马？
                    3:stdout:早上好
                    4:stdout:你好马？
                    3:testlog:早上好
                    4:testlog:你好马？
                )
            ],
            [map { encode_utf8($_) } qw(
                1:stderr:早上好
                2:stderr:你好马？
                3:stderr:早上好
                4:stderr:你好马？
            )],
        ),
    });
    run_one_test({
        testname         => 'mixed_nonascii with capture and ignored -o and tee',
        testrunner_args  => [ '--tee-logs', $tempdir, '--' ],
        command_args     => [ '-o', 'testlog.log.txt', '--skip-log', 'mixed_nonascii' ],
        expected_logtext => rx_for_lines(
            [
                q{Log file created by QtQA::App::TestRunner},
                q{},
                q{QtQA::App::TestRunner: FAIL! Test was badly behaved, the `-o' argument was ignored.},
                q{QtQA::App::TestRunner: stdout/stderr follows:},
                map { encode_utf8($_) } qw(
                    1:testlog:早上好
                    2:testlog:你好马？
                    1:stdout:早上好
                    2:stdout:你好马？
                    3:stdout:早上好
                    4:stdout:你好马？
                    3:testlog:早上好
                    4:testlog:你好马？
                )
            ],
            [map { encode_utf8($_) } qw(
                1:stderr:早上好
                2:stderr:你好马？
                3:stderr:早上好
                4:stderr:你好马？
            )],
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
        expected_logtext => error_nonexistent_command('command_which_does_not_exist'),
        expected_stderr  => "",
        expected_success => 0,
    });
    run_one_test({
        testname         => 'tee error nonexistent process',
        testrunner_args  => [ '--tee-logs', $tempdir, '--'],
        command          => [ 'command_which_does_not_exist' ],
        expected_logfile => "$tempdir/command_which_does_not_exist-01.txt",
        expected_logtext => error_nonexistent_command('command_which_does_not_exist'),
        expected_stderr  => error_nonexistent_command('command_which_does_not_exist'),
        expected_success => 0,
    });

    my $crash_script = catfile( $HELPER_DIR, 'dereference_bad_pointer.pl' );
    my $crash_rx = ($WINDOWS)
        ? "QtQA::App::TestRunner: Process exited with exit code 0xC0000005 (STATUS_ACCESS_VIOLATION)\n"
        : qr{\AQtQA::App::TestRunner: Process exited due to signal 11(; dumped core)?\n\z}ms;
    run_one_test({
        testname         => 'capture error crashing',
        testrunner_args  => [ '--capture-logs', $tempdir, '--'],
        command          => [ 'perl', $crash_script ],
        expected_logfile => "$tempdir/perl-00.txt",
        expected_logtext => $crash_rx,
        expected_stderr  => "",
        expected_success => 0,
    });
    run_one_test({
        testname         => 'tee error crashing',
        testrunner_args  => [ '--tee-logs', $tempdir, '--'],
        command          => [ 'perl', $crash_script ],
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
