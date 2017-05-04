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

package QtQA::App::TestRunner::Plugin::flaky;
use strict;
use warnings;

use Carp;
use Getopt::Long qw(GetOptionsFromArray);
use List::Util qw(max);
use Readonly;

# different flaky modes.

# WORST: always take the worst result
# (i.e. fail if an autotest fails at least once)
Readonly my $WORST  => 'worst';

# BEST: always take the best result
# (i.e. pass if an autotest passes at least once)
Readonly my $BEST   => 'best';

# IGNORE: ignore result
# (i.e. pass if the autotest is unstable, regardless of
# the pass/fail result of the autotest)
Readonly my $IGNORE => 'ignore';

Readonly my %FLAKY_MODES => (
    $WORST  =>  1,
    $BEST   =>  1,
    $IGNORE =>  1,
);

sub new
{
    my ($class, %args) = @_;

    $args{ attempt } = 1;

    # `WORST' is essentially equal to operating only in an advisory mode,
    # so it is the safest default.
    my $mode = $WORST;

    GetOptionsFromArray( $args{ argv },
        'flaky-mode=s'  =>  \$mode,
    ) || pod2usage(1);

    if (!$FLAKY_MODES{ $mode }) {
        die "`$mode' is not a valid --flaky-mode; try one of ".join(q{,}, keys %FLAKY_MODES);
    }

    $args{ mode } = $mode;

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
            ++$self->{ attempt };
            $self->{ first_attempt_status } = $status;
            $testrunner->print_info( "test failed, running again to see if it is flaky...\n" );
            return { retry => 1 };
        }

        # First try, test has succeeded ...
        return;
    }

    # Second try, test gave same results both times...
    if ($status == $self->{ first_attempt_status }) {
        $testrunner->print_info( "test failure could be reproduced twice consecutively\n" );
        return;
    }

    # Second try, test gave different results each time.
    return $self->handle_flaky_test( $self->{ first_attempt_status }, $status );
}

sub about_to_run
{
    my ($self, $args_ref) = @_;

    # on attempt other than the first, omit '-silent' argument, so we get all
    # details about the failure.
    if ($self->{ attempt } > 1) {
        @{ $args_ref } = grep { $_ ne '-silent' } @{ $args_ref };
    }

    return;
}

# Once a test has been determined as definitely being flaky,
# this function will do something based on the current flaky mode.
sub handle_flaky_test
{
    my ($self, $first_status, $second_status) = @_;

    if ($first_status == 0) {
        confess 'internal error: should not be called if test passed on first attempt';
    }

    my $testrunner = $self->{ testrunner };

    if ($second_status == 0) {
        $testrunner->print_info(
            "test failed on first attempt and passed on second attempt!\n"
           .'  first attempt:  exited with '.$self->format_status( $first_status )."\n"
        );
    }
    else {
        $testrunner->print_info(
            "test failed on first and second attempts, but with different behavior each time:\n"
           .'  first attempt:  exited with '.$self->format_status( $first_status )."\n"
           .'  second attempt: exited with '.$self->format_status( $second_status )."\n"
        );
    }

    $testrunner->print_info( "the test seems to be flaky, please fix this\n" );

    if ($self->{ mode } eq $IGNORE) {
        $testrunner->print_info( "this flaky test is being ignored\n" );
        $testrunner->proc( )->{ status } = 0;
    }
    elsif ($self->{ mode } eq $BEST && $second_status == 0) {
        $testrunner->print_info( "this flaky test is being treated as a PASS\n" );
    }
    else {
        $testrunner->print_info( "this flaky test is being treated as a FAIL\n" );
        # We need to tell the caller to force a failure, otherwise it will
        # consider that the test has passed.  Take the "worst" exit code
        # (well, a higher exit code doesn't necessarily imply worse results,
        # but testlib uses the number of failures as an exitcode, and also high
        # exitcodes stand out more easily in test logs).
        my $exitcode = max( $first_status >> 8, $second_status >> 8 ) || 1;
        return { force_failure_exitcode => $exitcode };
    }

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

  # default: advisory mode only
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
  QtQA::App::TestRunner: this flaky test is being treated as a FAIL
  1

  # can also permit or ignore flaky tests ...
  $ testrunner --plugin flaky --flaky-mode best -- tst_flaky; echo $?
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
  QtQA::App::TestRunner: this flaky test is being treated as a PASS
  0

=head1 DESCRIPTION

This plugin provides a simple mechanism to help determine if an autotest failure
is stable.  When active, any failing autotest will be re-run at least once to check
if the failure can be reproduced.

If the failing autotest was initially run with the '-silent' argument, this argument
will be omitted on the second run.

An autotest which fails twice in a row, but with a different exit status each time,
is also considered unstable (example: a test which fails "normally" once, but
segfaults at the second run).

By default, the plugin does not override the pass/fail state of the test.
This can be configured by the B<--flaky-mode> argument, which accepts the values:

=over

=item B<worst>

Always take the worst result of an autotest as the canonical result (default).

=item B<best>

Always take the best result of an autotest as the canonical result.

=item B<ignore>

Ignore any autotest which gives unstable results.

=back

To aid in the understanding of the difference between these values,
the following table is provided which enumerates all possible cases:

  +======================================================================================+
  | flaky-mode |  pass  | stable fail  |  fail then pass  |   fail then fail differently |
  +============+========+==============+==================+==============================+
  |  worst     |  PASS  |    FAIL      |      FAIL        |           FAIL               |
  |  best      |  PASS  |    FAIL      |      PASS        |           FAIL               |
  |  ignore    |  PASS  |    FAIL      |      PASS        |           PASS               |
  +======================================================================================+

=head1 CAVEATS

Note that this can only prove when a test is I<unstable>.
Even running a test successfully one trillion times wouldn't prove that it's
stable.

Use of any flaky-mode other than B<worst> may lead to genuine issues being hidden
indefinitely.

=cut

1;
