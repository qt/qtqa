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

package QtQA::App::TestRunner::Plugin::crashreporter;
use strict;
use warnings;

use Carp;
use English qw( -no_match_vars );
use File::Basename;
use File::Spec::Functions;
use IO::File;
use Readonly;

# uncomment for debugging
#use Smart::Comments;

# 1 if we are on mac
Readonly my $MAC => ($OSNAME =~ m{darwin}i);

# Path to user CrashReporter directory;
# may be overridden with an environment variable, for testing
Readonly my $CRASHREPORTER_DIR => exists( $ENV{ QTQA_CRASHREPORTER_DIR } )
    ? $ENV{ QTQA_CRASHREPORTER_DIR }
    : catfile( $ENV{ HOME }, qw(Library Logs CrashReporter) );

# CrashReporter may take a few seconds to write out the crash report after a test
# crashes.  We'll wait up to this amount in seconds.
Readonly my $CRASHREPORTER_TIMEOUT => 4;

# CrashReporter does not generate a crash log for these signals, so don't
# waste time looking for them.  The set of handled signals doesn't appear to be
# documented or configurable, so this is based on experience/testing.
Readonly my %CRASHREPORTER_IGNORED_SIGNALS => (map { $_ => 1 } qw(
    2
    15
));

sub new
{
    my ($class, %args) = @_;

    if (!$MAC) {
        croak "crashreporter plugin is specific to mac; not usable on $OSNAME";
    }

    return bless \%args, $class;
}

sub about_to_run
{
    my ($self) = @_;

    # Save names of all crash reports prior to the run, so we can check
    # new crash reports only.
    $self->{ old_crash_reports } = [ glob "$CRASHREPORTER_DIR/*" ];

    return;
}

sub run_completed
{
    my ($self) = @_;

    my $testrunner = $self->{ testrunner };
    my $proc = $testrunner->proc( );
    my $status = $proc->status( );
    my $signal = ($status & 127);

    # If no signal or crashreporter ignores this signal, then nothing to do
    return if (!$signal || $CRASHREPORTER_IGNORED_SIGNALS{ $signal });

    my $crashreport = $self->_find_crash_report_robustly(
        # Must not be one of these...
        exclude => $self->{ old_crash_reports },

        # Parent PID should be us
        parent_pid => $PID,
    );

    if (!$crashreport) {
        $testrunner->print_info(
            "Sorry, a crash report could not be found in $CRASHREPORTER_DIR.\n"
        );
        return;
    }

    $self->_print_crashreport( $crashreport );

    return;
}

sub _print_crashreport
{
    my ($self, $filename) = @_;

    my $testrunner = $self->{ testrunner };

    my $fh = IO::File->new( $filename, '<' );
    if (!$fh) {
        $testrunner->print_info(
            "open $filename: $!\n"
           ."The crash report could not be displayed.\n"
        );
        return;
    }

    #
    # create nice chunk of text like:
    #
    #   ================== crash report follows: ===============
    #   (the crash report here)
    #   ========================================================
    #
    $testrunner->print_info(
        ('=' x 29). ' crash report follows: ' . ('=' x 28) . "\n"
    );

    while (my $line = <$fh>) {
        $testrunner->print_info( $line );
    }

    if (!$fh->close( )) {
        $testrunner->print_info(
            "close $filename: $!\n"
           ."The crash report may be incomplete.\n"
        );
    }

    $testrunner->print_info( ('=' x 80)."\n" );

    return;
}

# Returns crash report filename if possible,
# retrying for up to $CRASHREPORTER_TIMEOUT seconds.
sub _find_crash_report_robustly
{
    my ($self, %args) = @_;

    my $time_remaining = $CRASHREPORTER_TIMEOUT;
    my $out;

    while ($time_remaining) {
        if ($out = $self->_find_crash_report( %args )) {
            last;
        }
        sleep 1;
        --$time_remaining;
    }

    return $out;
}

# Returns crash report filename if possible,
# attempting only once to find the crash report according
# to the given information:
#
#  exclude          => arrayref of filenames to exclude from consideration
#  parent_pid       => only consider crash reports whose parent PID matches this
#
# This parses crash reports.
# See Technical Note TN2123 for information on crash report format.
#
# Surprisingly, there is actually no way to get the PID of the child process
# out of Proc::Reliable, so we can't use that for the matching.
#
sub _find_crash_report
{
    my ($self, %args) = @_;

    my %exclude = map { $_ => 1 } @{$args{ exclude }};

    my @found;

    foreach my $candidate (glob "$CRASHREPORTER_DIR/*") {
        ### Checking candidate: $candidate
        if ($exclude{ $candidate }) {
            ### excluded via %exclude
            next;
        }

        if ($self->_looks_like_crash_report( $candidate, %args )) {
            ### Match!
            push @found, $candidate;
        }
    }

    ### Matches: @found
    if (@found == 1) {
        return $found[0];
    }

    # Too few or too many matches.
    return;
}

# Returns 1 if the given $filename looks like a crash
# report according to the criteria in %args
sub _looks_like_crash_report
{
    my ($self, $filename, %args) = @_;

    my $parent_pid = $args{ parent_pid };

    my $fh = IO::File->new( $filename, '<' );
    if (!$fh) {
        ### could not be opened: $!
        return;
    }

    my $match = 0;

    while (my $line = <$fh>) {
        chomp $line;

        # Example:
        # Parent Process:  launchd [241]
        if ($line =~ m{\A Parent \s Process: \s+ .+ \[(\d+)\] \z}xms) {
            my $ppid = $1;
            if ($parent_pid != $ppid) {
                ### Parent PID does not match: $ppid
                return;
            }
            $match = 1;
            last;
        }
    }

    if (!$match) {
        ### Crash report was missing a Parent Process line?
        return;
    }

    return 1;
}

=head1 NAME

QtQA::App::TestRunner::Plugin::crashreporter - show crash reports for crashing tests (on mac)

=head1 SYNOPSIS

  # without this plugin:
  $ testrunner --capture-logs $HOME/test-logs -- tst_crashy
  # $HOME/test-logs/tst_crashy-00.txt says "process exited with signal 11 ..."

  # with this plugin:
  $ testrunner --plugin crashreporter --capture-logs $HOME/test-logs -- tst_crashy
  # $HOME/test-logs/tst_crashy-00.txt says "process exited with signal 11 ..."
  # and also contains all crash information collected by the OSX CrashReporter service

=head1 DESCRIPTION

If a test crashes (exited due to a signal), this plugin will attempt to find and print
any crash log generated by the CrashReporter service.  This is the same information
displayed in native Mac crash dialogs when a GUI application crashes.

The method for finding the application's crash log is simple:
if the crash log was created after the test was begun, and the parent process mentioned
in the crash log is this process (the testrunner), it is determined to be the test's
crash log.

=head1 CAVEATS

Finding the crash log may fail if one of the following occurs:

=over

=item *

the CrashReporter process was very slow, or itself crashed

=item *

some other subprocess of testrunner unexpectedly crashed (for example, a utility
run by some other testrunner plugin crashed)

=item *

the crashing test was not a direct child process of the testrunner (for example,
this testrunner was used in combination with another testrunner script)

=back

If any of the above situations occur, testrunner will warn about the failure.

=cut

1;
