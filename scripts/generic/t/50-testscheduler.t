#!/usr/bin/env perl
use 5.010;
use strict;
use warnings;

=head1 NAME

50-testplanner.t - basic test for testscheduler.pl

=cut

use English qw(-no_match_vars);
use File::Spec::Functions;
use File::Temp;
use File::chdir;
use FindBin;
use Readonly;
use ReleaseAction qw(on_release);
use Test::More;
use Text::Diff;
use Capture::Tiny qw(capture_merged);

use lib "$FindBin::Bin/../../lib/perl5";
use QtQA::Test::More qw(find_qmake);

Readonly my $TESTPLANNER => catfile( $FindBin::Bin, qw(.. testplanner.pl) );

Readonly my $TESTSCHEDULER => catfile( $FindBin::Bin, qw(.. testscheduler.pl) );

Readonly my $TESTDATA_DIR => catfile( $FindBin::Bin, qw(data test-projects) );

Readonly my $QMAKE => find_qmake( );

# Regular expression snippets
Readonly my %RE => make_regexes( );

# Returns various regex parts used in the test, mostly to do with timing.
# We do not generally test that the actual time values are correct.
sub make_regexes
{
    my %out = (

        # a positive time, less than 1 minute
        time_seconds => qr{< 1 second|1 second|\d+ seconds},

        # no time at all
        no_time => qr{\(no time\)},

        # Timing header line
        timing_header => qr{
\Q=== Timing: =================== TEST RUN COMPLETED! ============================\E
        }xms,

    );

    $out{ timing_section_begin } = qr|
$out{ timing_header } \n
[ ]+ Total: [ ]+                                            $out{ time_seconds } \n
[ ]+ \QSerial tests:\E [ ]+                                 $out{ time_seconds } \n
[ ]+ \QParallel tests:\E [ ]+                               $out{ time_seconds } \n
    |xms;

    $out{ timing_section_j1 } = qr|
$out{ timing_section_begin }
[ ]+ \QEstimated time spent on insignificant tests:\E [ ]+  $out{ no_time } \n
[ ]+ \QEstimated time saved by -j1:\E [ ]+                  $out{ time_seconds } \n
    |xms;

    $out{ timing_section_j1_with_insignificant } = qr|
$out{ timing_section_begin }
[ ]+ \QEstimated time spent on insignificant tests:\E [ ]+  $out{ time_seconds } \n
[ ]+ \QEstimated time saved by -j1:\E [ ]+                  $out{ time_seconds } \n
    |xms;

    $out{ timing_section_j4_with_insignificant } = qr|
$out{ timing_section_begin }
[ ]+ \QEstimated time spent on insignificant tests:\E [ ]+  $out{ time_seconds } \n
[ ]+ \QEstimated time saved by -j4:\E [ ]+                  $out{ time_seconds } \n
    |xms;

    return %out;
}

# Given a $directory, returns a filename pointing to a created testplan,
# and a handle for unlinking that filename.
# Any additional @args are passed to testplanner.
sub make_testplan_from_directory
{
    my ($directory, @args) = @_;

    my $testplan = File::Temp->new(
        TEMPLATE => 'qtqa-testplan-XXXXXX',
        TMPDIR => 1,
    );
    $testplan = "$testplan";

    my @cmd = (
        $EXECUTABLE_NAME,
        $TESTPLANNER,
        '--input',
        $directory,
        '--output',
        "$testplan",
        @args,
    );

    my $status = system( @cmd );
    is( $status, 0, 'testplanner exit code OK' );

    my $on_release = on_release { unlink $testplan };

    return ($testplan, $on_release);
}

sub test_mixed
{
    my ($testplan, $unlink) = make_testplan_from_directory $TESTDATA_DIR;

    my $status;
    my $output = capture_merged {
        $status = system(
            $EXECUTABLE_NAME,
            $TESTSCHEDULER,
            '--plan',
            "$testplan",
            '-j4',
            '--sync-output',
        );
    };
    isnt( $status, 0, 'testscheduler fails if some tests fail' );
    like( $output, qr|
\Qfailing. 1 arg(s)
QtQA::App::TestScheduler: failing_significant_test failed
passing. 1 arg(s)
QtQA::App::TestScheduler: ran 2 parallel tests.  Starting 4 serial tests.
Custom failing
QtQA::App::TestScheduler: failing_custom_check_target failed
failing. 1 arg(s)
QtQA::App::TestScheduler: failing_insignificant_test failed, but it is marked with insignificant_test
Custom passing
passing. 1 arg(s)
\E $RE{ timing_section_j4_with_insignificant }
\Q=== Failures: ==================================================================
  failing_significant_test
  failing_custom_check_target
  failing_insignificant_test [insignificant]
=== Totals: 6 tests, 3 passes, 2 fails, 1 insignificant fail ===================
\E|xms, 'testscheduler output as expected' );

    return;
}

# Test what happens with a directory containing no tests
sub test_none
{
    my ($testplan, $unlink) = make_testplan_from_directory "$TESTDATA_DIR/not_tests";

    my $status;
    my $output = capture_merged {
        $status = system(
            $EXECUTABLE_NAME,
            $TESTSCHEDULER,
            '--plan',
            "$testplan",
        );
    };
    is( $status, 0, 'testscheduler with no tests is a pass' );
    like( $output, qr|
$RE{ timing_section_j1 }
\Q=== Totals: no tests, no passes ================================================\E \n
        |xms, 'testscheduler output as expected' );

    return;
}

sub test_single_fail
{
    my ($testplan, $unlink) = make_testplan_from_directory "$TESTDATA_DIR/tests/failing_significant_test";

    my $status;
    my $output = capture_merged {
        $status = system(
            $EXECUTABLE_NAME,
            $TESTSCHEDULER,
            '--plan',
            "$testplan",
            '--',   # test trailing -- is harmless
        );
    };
    isnt( $status, 0, 'testscheduler with single fail is a fail' );
    like( $output, qr|
\Qfailing. 1 arg(s)
QtQA::App::TestScheduler: failing_significant_test failed
\E $RE{ timing_section_j1 }
\Q=== Failures: ==================================================================
  failing_significant_test
=== Totals: 1 test, no passes, 1 fail ==========================================
\E|xms, 'testscheduler output as expected' );

    return;
}

sub test_single_insignificant_fail
{
    # Testing with some additional args
    my ($testplan, $unlink) = make_testplan_from_directory(
        "$TESTDATA_DIR/tests/failing_insignificant_test",
        '--',
        'arg1',
        'arg2',
    );

    my $status;
    my $output = capture_merged {
        $status = system(
            $EXECUTABLE_NAME,
            $TESTSCHEDULER,
            '--plan',
            "$testplan",
        );
    };
    is( $status, 0, 'testscheduler with single insignificant fail is a pass' );
    like( $output, qr|
\Qfailing. 3 arg(s)
QtQA::App::TestScheduler: failing_insignificant_test failed, but it is marked with insignificant_test
\E $RE{ timing_section_j1_with_insignificant }
\Q=== Failures: ==================================================================
  failing_insignificant_test [insignificant]
=== Totals: 1 test, no passes, 1 insignificant fail ============================
\E|xms, 'testscheduler output as expected' );

    return;
}

sub test_single_pass
{
    my ($testplan, $unlink) = make_testplan_from_directory "$TESTDATA_DIR/tests/passing_significant_test";

    my $status;
    my $output = capture_merged {
        $status = system(
            $EXECUTABLE_NAME,
            $TESTSCHEDULER,
            '--plan',
            "$testplan",
        );
    };
    is( $status, 0, 'testscheduler with single pass is a pass' );
    like( $output, qr|
\Qpassing. 1 arg(s)
\E $RE{ timing_section_j1 }
\Q=== Totals: 1 test, 1 pass =====================================================
\E|xms, 'testscheduler output as expected' );

    return;
}

sub run
{
    # qmake the testdata before doing anything else.
    ok( $QMAKE, 'found some qmake' );

    {
        local $CWD = $TESTDATA_DIR;
        # we use qmake -r so we can access the makefiles at any level,
        # and we disable debug and release for predictable results
        my $status = system( $QMAKE, '-r' );
        is( $status, 0, 'qmake ran OK' );
    }

    test_none;
    test_single_fail;
    test_single_insignificant_fail;
    test_single_pass;
    test_mixed;
    done_testing;

    return;
}

run if (!caller);
1;

