#!/usr/bin/env perl
use 5.010;
use strict;
use warnings;

=head1 NAME

21-testrunner-flaky.t - test testrunner's `flaky' plugin for unstable tests

=head1 SYNOPSIS

  perl ./21-testrunner-flaky.t

This test will run the testrunner.pl script with some artificially unstable
processes and verify that the flaky plugin generates the expected output.

=cut

use Capture::Tiny qw( capture );
use English qw( -no_match_vars );
use File::Basename;
use File::Slurp qw( read_file );
use File::Temp qw( tempdir );
use FindBin;
use Readonly;
use Test::More;

use lib "$FindBin::Bin/../../lib/perl5";
use QtQA::Test::More qw( is_or_like );

# error from a stable failing test
Readonly my $ERROR_STABLE_FAILURE => <<'END_MESSAGE';
QtQA::App::TestRunner: test failed, running again to see if it is flaky...
QtQA::App::TestRunner: test failure could be reproduced twice consecutively
END_MESSAGE

# perl to simulate a test which fails, then succeeds.
Readonly my $PERL_VANISHING_FAILURE => <<'END_SCRIPT';
$|++;
if ($ENV{ QTQA_APP_TESTRUNNER_ATTEMPT } == 1) {
    print qq{First attempt; failing...\n};
    exit 13;
}
print qq{Second attempt; causing much vexation by passing!\n};
END_SCRIPT

# perl to simulate a test which eventually fails, then eventually succeeds.
Readonly my $PERL_VANISHING_FAILURE_TIMEOUT_WARNING => <<'END_SCRIPT';
sleep 2;
$|++;
if ($ENV{ QTQA_APP_TESTRUNNER_ATTEMPT } == 1) {
    print qq{First attempt; failing...\n};
    exit 13;
}
print qq{Second attempt; causing much vexation by passing!\n};
END_SCRIPT

# stdout from the above
Readonly my $OUTPUT_VANISHING_FAILURE => <<'END_MESSAGE';
First attempt; failing...
Second attempt; causing much vexation by passing!
END_MESSAGE

# error from the above
Readonly my $ERROR_VANISHING_FAILURE => <<'END_MESSAGE';
QtQA::App::TestRunner: test failed, running again to see if it is flaky...
QtQA::App::TestRunner: test failed on first attempt and passed on second attempt!
QtQA::App::TestRunner:   first attempt:  exited with exit code 13
QtQA::App::TestRunner: the test seems to be flaky, please fix this
END_MESSAGE

# above, in `pass' flaky mode
Readonly my $ERROR_VANISHING_FAILURE_MODE_BEST => $ERROR_VANISHING_FAILURE . <<"END_MESSAGE";
QtQA::App::TestRunner: this flaky test is being treated as a PASS
END_MESSAGE

# above, in `fail' flaky mode
Readonly my $ERROR_VANISHING_FAILURE_MODE_WORST => $ERROR_VANISHING_FAILURE . <<"END_MESSAGE";
QtQA::App::TestRunner: this flaky test is being treated as a FAIL
END_MESSAGE

# above, in `ignore' flaky mode
Readonly my $ERROR_VANISHING_FAILURE_MODE_IGNORE => $ERROR_VANISHING_FAILURE . <<"END_MESSAGE";
QtQA::App::TestRunner: this flaky test is being ignored
END_MESSAGE

# perl to simulate a test which fails by crashing, then succeeds.
Readonly my $PERL_VANISHING_CRASH => <<'END_SCRIPT';
$|++;
if ($ENV{ QTQA_APP_TESTRUNNER_ATTEMPT } == 1) {
    print qq{First attempt; crashing...\n};
    kill 11, $$;
}
print qq{Second attempt; causing much vexation by passing!\n};
END_SCRIPT

# stdout from the above
Readonly my $OUTPUT_VANISHING_CRASH => <<'END_MESSAGE';
First attempt; crashing...
Second attempt; causing much vexation by passing!
END_MESSAGE

# helper regexes for building up the larger regexes below
Readonly my $RE => {
    flaky_first_fail  => qr{
\QQtQA::App::TestRunner: test failed, running again to see if it is flaky...\E\n
    }xms,

    core_backtrace    => qr{
\QQtQA::App::TestRunner: ============================== backtrace follows: ==============================\E \n
(?:QtQA::App::TestRunner: [^\n]+ \n)*
\QQtQA::App::TestRunner: Program terminated with signal \E(?:11|SIGSEGV)\Q, Segmentation fault.\E                           \n
(?:QtQA::App::TestRunner: [^\n]+ \n)*
\QQtQA::App::TestRunner: ================================================================================\E \n
    }xms,

    exited_with_signal11 => ($OSNAME =~ m{win32}i) ? qr{} : qr{
\QQtQA::App::TestRunner: Process exited due to signal 11; dumped core\E                                     \n
    }xms,

    exited_with_any_signal => ($OSNAME =~ m{win32}i) ? qr{} : qr{
\QQtQA::App::TestRunner: Process exited due to signal \E \d+ (?:\Q; dumped core\E)?                         \n
    }xms,

    flaky_second_pass => qr{
\QQtQA::App::TestRunner: test failed on first attempt and passed on second attempt!\E                       \n
\QQtQA::App::TestRunner:   first attempt:  exited with signal 11\E                                          \n
\QQtQA::App::TestRunner: the test seems to be flaky, please fix this\E                                      \n
\QQtQA::App::TestRunner: this flaky test is being treated as a FAIL\E                                       \n
    }xms,

    verbose_begin => qr{\QQtQA::App::TestRunner: begin \E.*?:\Q [perl]\E[^\n]*},
    verbose_end   => qr{\QQtQA::App::TestRunner: end \E[^:]+\Q: \E[^\n]*},
};

# perl to simulate a test which hangs (for 10 seconds)
Readonly my $PERL_HANGING_FAILURE => <<'END_SCRIPT';
$|++;
print qq{About to hang for a few seconds...\n};
sleep 10;
print qq{Still alive!?!? Most unexpected ...\n};
exit 0;
END_SCRIPT

# stdout from the above
Readonly my $OUTPUT_HANGING_FAILURE => <<'END_MESSAGE';
About to hang for a few seconds...
About to hang for a few seconds...
END_MESSAGE


# error from hanging test
Readonly my $ERROR_HANGING_FAILURE => qr|
    \QQtQA::App::TestRunner: Timed out after \E \d+ \Q seconds\E \n
    $RE->{ exited_with_any_signal }
    \QQtQA::App::TestRunner: test failed, running again to see if it is flaky...\E \n
    \QQtQA::App::TestRunner: Timed out after \E \d+ \Q seconds\E \n
    $RE->{ exited_with_any_signal }
    \QQtQA::App::TestRunner: test failure could be reproduced twice consecutively\E \n
|xms;

# error from the above (when using "flaky" and "core" plugins, in that order)
# note: hardcoded 3328 == (13 << 8)
Readonly my $ERROR_VANISHING_CRASH_WITH_FLAKY_AND_CORE => qr|
\A
    $RE->{ exited_with_signal11 } # testrunner tells us that the test exited with signal 11...
    $RE->{ flaky_first_fail }   # `flaky' says it fails, will try again...
    $RE->{ core_backtrace }     # `core' shows the backtrace from the first fail
    $RE->{ flaky_second_pass }  # `flaky' says it passed on second try
\z
|xms;

# merged stdout/stderr from the above
Readonly my $LOG_VANISHING_CRASH_WITH_FLAKY_AND_CORE => qr|
\A
    \QFirst attempt; crashing...\E \n
    $RE->{ exited_with_signal11 }
    $RE->{ flaky_first_fail }
    $RE->{ core_backtrace }
    \QSecond attempt; causing much vexation by passing!\E \n
    $RE->{ flaky_second_pass }
\z
|xms;

# error from the above (when using "core" and "flaky" plugins, in that order)
# Note the only difference from above is that some output order is switched
Readonly my $ERROR_VANISHING_CRASH_WITH_CORE_AND_FLAKY => qr|
\A
    $RE->{ exited_with_signal11 } # testrunner tells us that the test exited with signal 11
    $RE->{ core_backtrace }     # `core' shows the backtrace from the first fail
    $RE->{ flaky_first_fail }   # `flaky' says it fails, will try again...
    $RE->{ flaky_second_pass }  # `flaky' says it passed on second try
\z
|xms;

# merged stdout/stderr from the above
Readonly my $LOG_VANISHING_CRASH_WITH_CORE_AND_FLAKY => qr|
\A
    \QFirst attempt; crashing...\E \n
    $RE->{ exited_with_signal11 }
    $RE->{ core_backtrace }
    $RE->{ flaky_first_fail }
    \QSecond attempt; causing much vexation by passing!\E \n
    $RE->{ flaky_second_pass }
\z
|xms;

# perl to simulate a test which fails, then fails again in a different way
Readonly my $PERL_DIFFERING_FAILURE => <<'END_SCRIPT';
$|++;
if ($ENV{ QTQA_APP_TESTRUNNER_ATTEMPT } == 1) {
    print qq{First attempt; failing...\n};
    exit 13;
}
print qq{Second attempt; failing again, differently\n};
exit 22;
END_SCRIPT

# stdout from the above
Readonly my $OUTPUT_DIFFERING_FAILURE => <<'END_MESSAGE';
First attempt; failing...
Second attempt; failing again, differently
END_MESSAGE

# error from the above
Readonly my $ERROR_DIFFERING_FAILURE => <<'END_MESSAGE';
QtQA::App::TestRunner: test failed, running again to see if it is flaky...
QtQA::App::TestRunner: test failed on first and second attempts, but with different behavior each time:
QtQA::App::TestRunner:   first attempt:  exited with exit code 13
QtQA::App::TestRunner:   second attempt: exited with exit code 22
QtQA::App::TestRunner: the test seems to be flaky, please fix this
END_MESSAGE

# above, in `pass' flaky mode
Readonly my $ERROR_DIFFERING_FAILURE_MODE_BEST => $ERROR_DIFFERING_FAILURE . <<"END_MESSAGE";
QtQA::App::TestRunner: this flaky test is being treated as a FAIL
END_MESSAGE

# above, in `fail' flaky mode
Readonly my $ERROR_DIFFERING_FAILURE_MODE_WORST => $ERROR_DIFFERING_FAILURE . <<"END_MESSAGE";
QtQA::App::TestRunner: this flaky test is being treated as a FAIL
END_MESSAGE

# above, with --verbose
Readonly my $VERBOSE_ERROR_DIFFERING_FAILURE_MODE_WORST => qr|
\A
$RE->{ verbose_begin }\n
\Q$ERROR_DIFFERING_FAILURE_MODE_WORST\E
$RE->{ verbose_end }\Q, exit code 22\E\n
|xms;

# above, in `ignore' flaky mode
Readonly my $ERROR_DIFFERING_FAILURE_MODE_IGNORE => $ERROR_DIFFERING_FAILURE . <<"END_MESSAGE";
QtQA::App::TestRunner: this flaky test is being ignored
END_MESSAGE

# stdout & stderr mixed from the above
Readonly my $LOG_DIFFERING_FAILURE => <<'END_MESSAGE';
First attempt; failing...
QtQA::App::TestRunner: test failed, running again to see if it is flaky...
Second attempt; failing again, differently
QtQA::App::TestRunner: test failed on first and second attempts, but with different behavior each time:
QtQA::App::TestRunner:   first attempt:  exited with exit code 13
QtQA::App::TestRunner:   second attempt: exited with exit code 22
QtQA::App::TestRunner: the test seems to be flaky, please fix this
END_MESSAGE

# above, in `pass' flaky mode
Readonly my $LOG_DIFFERING_FAILURE_MODE_BEST => $LOG_DIFFERING_FAILURE . <<"END_MESSAGE";
QtQA::App::TestRunner: this flaky test is being treated as a FAIL
END_MESSAGE

# above, in `fail' flaky mode
Readonly my $LOG_DIFFERING_FAILURE_MODE_WORST => $LOG_DIFFERING_FAILURE . <<"END_MESSAGE";
QtQA::App::TestRunner: this flaky test is being treated as a FAIL
END_MESSAGE

# above, in `ignore' flaky mode
Readonly my $LOG_DIFFERING_FAILURE_MODE_IGNORE => $LOG_DIFFERING_FAILURE . <<"END_MESSAGE";
QtQA::App::TestRunner: this flaky test is being ignored
END_MESSAGE

# perl to check if -silent argument is passed (and fail)
Readonly my $PERL_SILENT_CHECK => <<'END_SCRIPT';
if (grep { $_ eq '-silent' } @ARGV) {
    print qq{-silent argument is given; }.scalar(@ARGV).qq{ args\n};
} else {
    print qq{-silent argument is not given; }.scalar(@ARGV).qq{ args\n};
}
exit 16;
END_SCRIPT

# expected output from the above, when run with -silent -foo
Readonly my $OUTPUT_SILENT_CHECK => <<'END_MESSAGE';
-silent argument is given; 2 args
-silent argument is not given; 1 args
END_MESSAGE

# expected stderr from the above
Readonly my $ERROR_SILENT_CHECK => <<'END_MESSAGE';
QtQA::App::TestRunner: test failed, running again to see if it is flaky...
QtQA::App::TestRunner: test failure could be reproduced twice consecutively
END_MESSAGE

sub test_run
{
    my ($params_ref) = @_;

    my @args              = @{$params_ref->{ args }};
    my $expected_stdout   =   $params_ref->{ expected_stdout };
    my $expected_stderr   =   $params_ref->{ expected_stderr };
    my $expected_success  =   $params_ref->{ expected_success };
    my $expected_logfile  =   $params_ref->{ expected_logfile };
    my $expected_logtext  =   $params_ref->{ expected_logtext }  // "";
    my $testname          =   $params_ref->{ testname }          // q{};

    my $status;
    my ($output, $error) = capture {
        $status = system( 'perl', "$FindBin::Bin/../testrunner.pl", @args );
    };

    if ($expected_success) {
        is  ( $status, 0, "$testname exits zero" );
    }
    else {
        isnt( $status, 0, "$testname exits non-zero" );
    }

    is_or_like( $output, $expected_stdout, "$testname output looks correct" );
    is_or_like( $error,  $expected_stderr, "$testname error looks correct" );

    # The rest of the verification steps are only applicable if a log file is expected and created
    return if (!$expected_logfile);
    return if (!ok( -e $expected_logfile, "$testname created $expected_logfile" ));

    my $logtext = read_file( $expected_logfile );   # dies on error
    is_or_like( $logtext, $expected_logtext, "$testname logtext is as expected" );

    return;
}

sub test_testrunner_flaky
{
    # control; check that `--plugin flaky' has no effect if a test doesn't fail
    # flaky-mode should have no effect
    foreach my $mode_args (
        [],
        ['--flaky-mode', 'worst'],
        ['--flaky-mode', 'best'],
        ['--flaky-mode', 'ignore'],
    ) {
        test_run({
            testname         => "plugin loads OK 0 exitcode (@{ $mode_args })",
            args             => [ qw(--plugin flaky), @{ $mode_args }, qw(-- perl -e),
                                  'print STDOUT q{Hi}; print STDERR q{there!}' ],
            expected_success => 1,
            expected_stdout  => q{Hi},
            expected_stderr  => q{there!},
        });
    }

    # stable failure
    # flaky-mode should have no effect
    foreach my $mode_args (
        [],
        ['--flaky-mode', 'worst'],
        ['--flaky-mode', 'best'],
        ['--flaky-mode', 'ignore'],
    ) {
        test_run({
            testname         => "stable failure (@{ $mode_args })",
            args             => [ qw(--plugin flaky), @{ $mode_args }, qw(-- perl -e),
                                  'print qq{Failing...\n}; exit 42' ],
            expected_success => 0,
            expected_stdout  => qq{Failing...\n} x 2,    # x 2 since retried once
            expected_stderr  => $ERROR_STABLE_FAILURE,
        });
    }

    # test which fails once, then passes
    test_run({
        testname         => 'vanishing failure',
        args             => [ qw(--plugin flaky -- perl -e), $PERL_VANISHING_FAILURE ],
        expected_success => 0,
        expected_stdout  => $OUTPUT_VANISHING_FAILURE,
        expected_stderr  => $ERROR_VANISHING_FAILURE_MODE_WORST,
    });
    test_run({
        testname         => 'vanishing failure (flaky-mode worst)',
        args             => [ qw(--plugin flaky --flaky-mode worst -- perl -e), $PERL_VANISHING_FAILURE ],
        expected_success => 0,
        expected_stdout  => $OUTPUT_VANISHING_FAILURE,
        expected_stderr  => $ERROR_VANISHING_FAILURE_MODE_WORST,
    });
    test_run({
        testname         => 'vanishing failure (flaky-mode best)',
        args             => [ qw(--plugin flaky --flaky-mode best -- perl -e), $PERL_VANISHING_FAILURE ],
        expected_success => 1,
        expected_stdout  => $OUTPUT_VANISHING_FAILURE,
        expected_stderr  => $ERROR_VANISHING_FAILURE_MODE_BEST,
    });
    test_run({
        testname         => 'vanishing failure (flaky-mode ignore)',
        args             => [ qw(--plugin flaky --flaky-mode ignore -- perl -e), $PERL_VANISHING_FAILURE ],
        expected_success => 1,
        expected_stdout  => $OUTPUT_VANISHING_FAILURE,
        expected_stderr  => $ERROR_VANISHING_FAILURE_MODE_IGNORE,
    });


    # test which eventually fails once, then eventually passes
    # this also tests timeout warning by setting a smalltimeout value
    test_run({
        testname         => 'vanishing failure; with timeoutwarning test',
        args             => [ qw(--plugin flaky --timeout 5 -- perl -e), $PERL_VANISHING_FAILURE_TIMEOUT_WARNING ],
        expected_success => 0,
        expected_stdout  => $OUTPUT_VANISHING_FAILURE,
        expected_stderr  => $ERROR_VANISHING_FAILURE_MODE_WORST,
    });

    # test which fails once, then again in a different way
    test_run({
        testname         => 'differing failure',
        args             => [ qw(--plugin flaky -- perl -e), $PERL_DIFFERING_FAILURE ],
        expected_success => 0,
        expected_stdout  => $OUTPUT_DIFFERING_FAILURE,
        expected_stderr  => $ERROR_DIFFERING_FAILURE_MODE_WORST,
    });
    test_run({
        testname         => 'differing failure (flaky-mode worst)',
        args             => [ qw(--verbose --plugin flaky --flaky-mode worst -- perl -e), $PERL_DIFFERING_FAILURE ],
        expected_success => 0,
        expected_stdout  => $OUTPUT_DIFFERING_FAILURE,
        expected_stderr  => $VERBOSE_ERROR_DIFFERING_FAILURE_MODE_WORST,
    });
    test_run({
        testname         => 'differing failure (flaky-mode best)',
        args             => [ qw(--plugin flaky --flaky-mode best -- perl -e), $PERL_DIFFERING_FAILURE ],
        expected_success => 0,
        expected_stdout  => $OUTPUT_DIFFERING_FAILURE,
        expected_stderr  => $ERROR_DIFFERING_FAILURE_MODE_BEST,
    });
    test_run({
        testname         => 'differing failure (flaky-mode ignore)',
        args             => [ qw(--plugin flaky --flaky-mode ignore -- perl -e), $PERL_DIFFERING_FAILURE ],
        expected_success => 1,
        expected_stdout  => $OUTPUT_DIFFERING_FAILURE,
        expected_stderr  => $ERROR_DIFFERING_FAILURE_MODE_IGNORE,
    });

    # test -silent argument is omitted on second run
    test_run({
        testname         => 'silent removed',
        args             => [ qw(--plugin flaky -- perl -e), $PERL_SILENT_CHECK, '--', '-silent', '-foo' ],
        expected_success => 0,
        expected_stdout  => $OUTPUT_SILENT_CHECK,
        expected_stderr  => $ERROR_SILENT_CHECK,
    });

    # test which hangs should be retried as usual
    test_run({
        testname         => "hanging failure",
        args             => [ qw(--timeout 2 --plugin flaky -- perl -e), $PERL_HANGING_FAILURE ],
        expected_success => 0,
        expected_stdout  => $OUTPUT_HANGING_FAILURE,
        expected_stderr  => $ERROR_HANGING_FAILURE,
    });

    my $tempdir = tempdir( basename($0).'.XXXXXX', TMPDIR => 1, CLEANUP => 1 );

    # basic check of interaction with logging
    test_run({
        testname         => 'flaky with log',
        args             => [
            '--capture-logs',
            $tempdir,
            '--plugin',
            'flaky',
            '--',
            'perl',
            '-e',
            $PERL_DIFFERING_FAILURE,
        ],
        expected_success => 0,
        expected_stdout  => q{},
        expected_stderr  => q{},
        expected_logfile => "$tempdir/perl-00.txt",
        expected_logtext => $LOG_DIFFERING_FAILURE_MODE_WORST,
    });

    # interaction with core
    # (core only works on linux)
    if ($OSNAME =~ m{linux}i) {
        test_run({
            testname         => 'flaky with tee log and core (flaky, core)',
            args             => [
                '--tee-logs',
                $tempdir,
                '--plugin',
                'flaky',
                '--flaky-mode',     # note we are testing mixing of plugin args
                'worst',            # with global testrunner args.
                '--plugin',
                'core',
                '--',
                'perl',
                '-e',
                $PERL_VANISHING_CRASH,
            ],
            expected_success => 0,
            expected_stdout  => $OUTPUT_VANISHING_CRASH,
            expected_stderr  => $ERROR_VANISHING_CRASH_WITH_FLAKY_AND_CORE,
            expected_logfile => "$tempdir/perl-01.txt",
            expected_logtext => $LOG_VANISHING_CRASH_WITH_FLAKY_AND_CORE,
        });

        # switch the order and verify that this affects the plugin order
        test_run({
            testname         => 'flaky with tee log and core (core, flaky)',
            args             => [
                '--tee-logs',
                $tempdir,
                '--plugin',
                'core',
                '--plugin',
                'flaky',
                '--',
                'perl',
                '-e',
                $PERL_VANISHING_CRASH,
            ],
            expected_success => 0,
            expected_stdout  => $OUTPUT_VANISHING_CRASH,
            expected_stderr  => $ERROR_VANISHING_CRASH_WITH_CORE_AND_FLAKY,
            expected_logfile => "$tempdir/perl-02.txt",
            expected_logtext => $LOG_VANISHING_CRASH_WITH_CORE_AND_FLAKY,
        });
    }

    return;
}

sub run
{
    test_testrunner_flaky;
    done_testing;

    return;
}

run if (!caller);
1;

