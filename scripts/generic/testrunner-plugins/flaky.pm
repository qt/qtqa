package QtQA::App::TestRunner::Plugin::flaky;
use strict;
use warnings;

use Carp;

sub new
{
    my ($class, %args) = @_;

    $args{ attempt } = 1;

    return bless \%args, $class;
}

sub run_completed
{
    my ($self) = @_;

    my $testrunner = $self->{ testrunner };
    my $proc       = $testrunner->proc( );

    my $status = $proc->status( );

    if ($self->{ attempt } == 1) {
        # First try, test has failed ...
        if ($status) {
            $testrunner->print_info( "test failed, running again to see if it is flaky...\n" );
            ++$self->{ attempt };
            $self->{ first_attempt_status } = $status;
            return { retry => 1 };
        }

        # First try, test has succeeded ...
        return;
    }

    # Second try, test has succeeded...
    if ($status == 0) {
        $testrunner->print_info(
            "test failed on first attempt and passed on second attempt!\n"
           .'  first attempt:  exited with '.$self->format_status( $self->{ first_attempt_status } )."\n"
           ."the test seems to be flaky, please fix this\n"
        );

        # We need to tell the caller to force a failure, otherwise it will
        # consider that the test has passed.  We will reuse the status from
        # the first failure.
        my $exitcode = ($self->{ first_attempt_status } >> 8) || 1;
        return { force_failure_exitcode => $exitcode };
    }

    # Second try, test failed the same way it failed the first time ...
    if ($status == $self->{ first_attempt_status }) {
        $testrunner->print_info( "test failure seems to be stable\n" );
        return;
    }

    # Second try, test failed a different way than the first time ...
    $testrunner->print_info(
        "test failed on first and second attempts, but with different behavior each time:\n"
       .'  first attempt:  exited with '.$self->format_status( $self->{ first_attempt_status } )."\n"
       .'  second attempt: exited with '.$self->format_status( $status )."\n"
       ."the test seems to be flaky, please fix this\n"
    );

    # Note, we are not forcing any particular exit code, so the status from the
    # first test is what will be used.

    return;
}

# Given an exit status, return a human-readable string for the corresponding
# exit code or signal.  e.g., transform 139 into "signal 11".
sub format_status
{
    my ($self, $status) = @_;

    if ($status == -1) {
        return "status $status";
    }

    my $signal = ($status & 127);
    if ($signal) {
        return "signal $signal"
    }

    return "exit code ".($status >> 8);
}

# Compares two status values and returns 1 if they should be considered equal for the purpose
# of determining test stability.
sub status_eq
{
    my ($self, $a, $b) = @_;

    # We don't care if the process dumped core, since this is done by the OS _after_ the
    # process already crashed.  It has no bearing on the stability of a failure.
    $a |= 128;
    $b |= 128;

    return ($a == $b);
}

=head1 NAME

QtQA::App::TestRunner::Plugin::flaky - try to handle unstable autotests

=head1 SYNOPSIS

  $ testrunner --plugin flaky --capture-logs $HOME/test-logs -- tst_flaky; echo $?
  ********* Start testing of tst_Flaky *********
  Config: Using QTest library 5.0.0, Qt 5.0.0
  PASS   : tst_Flaky::initTestCase()
  FAIL!  : tst_Flaky::some_function() (The quux was not bar)
  PASS   : tst_Flaky::cleanupTestCase()
  Totals: 1 passed, 1 failed, 0 skipped
  ********* Finished testing of tst_Flaky *********
  QtQA::App::TestRunner: test failed, running again to see if it is flaky...
  ********* Start testing of tst_Flaky *********
  Config: Using QTest library 5.0.0, Qt 5.0.0
  PASS   : tst_Flaky::initTestCase()
  PASS   : tst_Flaky::some_function()
  PASS   : tst_Flaky::cleanupTestCase()
  Totals: 3 passed, 0 failed, 0 skipped
  ********* Finished testing of tst_Flaky *********
  QtQA::App::TestRunner: test failed on first attempt and passed on second attempt!
  QtQA::App::TestRunner: the test seems to be flaky, please fix this
  1

=head1 DESCRIPTION

This plugin provides a simple mechanism to help determine if an autotest failure
is stable.  When active, any failing autotest will be re-run at least once to check
if the failure can be reproduced.

An autotest which fails twice in a row, but with a different exit status each time,
is also considered unstable (example: a test which fails "normally" once, but
segfaults at the second run).

The plugin never overrides the pass/fail state of the test.  It only causes
additional information to be added to the test logs in the case of failures.

=head1 CAVEATS

Note that this can only prove when a test is I<unstable>.
Even running a test successfully one trillion times wouldn't prove that it's
stable.

=cut

1;
