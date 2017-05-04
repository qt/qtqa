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

package QtQA::App::TestRunner::Plugin::core;
use strict;
use warnings;

use Capture::Tiny qw( capture_merged );
use Carp;
use Data::Dumper;
use English qw( -no_match_vars );
use File::Temp;
use Readonly;

# not available on Windows; allow syntax check to work, at least
BEGIN {
    if ($OSNAME !~ m{win32}i) {
        require BSD::Resource; BSD::Resource->import( );
        require Tie::Sysctl;   Tie::Sysctl->import( );
    }
}

#use Smart::Comments;   # uncomment for debugging

Readonly my $LINUX => ($OSNAME =~ m{linux}i);
Readonly my $MAC   => ($OSNAME =~ m{darwin}i);

# Maximum permitted size of core files.
# On our Linux machines, asking for RLIM_INFINITY doesn't work
# for unknown reasons (even when the hard limit is infinity),
# so an arbitrary large number is used there.
Readonly my $CORE_LIMIT =>
    $LINUX ? 1024*1024*1024 : RLIM_INFINITY();

# Interface to /proc/sys values
tie my %SYSCTL, 'Tie::Sysctl' if $LINUX;

# get mtime of a file, or return -1 on error
sub mtime
{
    my ($file) = @_;
    return -1 if (! -e $file);

    my (@stat) = stat($file);

    return -1 if (! @stat);

    return $stat[9];
}

sub new
{
    my ($class, %args) = @_;

    if (!$LINUX && !$MAC) {
        croak "sorry, core plugin is currently not usable on $OSNAME";
    }

    return bless \%args, $class;
}

sub about_to_run
{
    my ($self) = @_;

    # Attempt to enable core dump for child processes
    if (!setrlimit( 'RLIMIT_CORE', $CORE_LIMIT, $CORE_LIMIT )) {
        $self->{ testrunner }->print_info(
            "enabling core dumps failed: setrlimit: $OS_ERROR\n"
           ."core dump may not be available if the test crashes :(\n"
        );
        return;
    }

    # Save time when the process begins, so we can check if the core dump
    # is new.
    $self->{ start_time } = time();

    return;
}

sub run_completed
{
    my ($self) = @_;

    my $testrunner = $self->{ testrunner };
    my $proc       = $testrunner->proc( );

    my $status = $proc->status( );

    my $signal     = ($status & 127);
    my $coredumped = ($status & 128);

    return if (!$signal);

    if ($signal && !$coredumped) {
        $testrunner->print_info(
            "It looks like the process exited due to a signal, but it didn't dump core :(\n"
           ."Sorry, a core dump will not be available.\n"
        );
        return;
    }

    $self->_find_and_handle_core_files( );

    return;
}

# Given the values of /proc/kernel/core_pattern and /proc/kernel/core_uses_pid,
# returns a pattern suitable for usage with glob() to find the relevant core files.
sub _core_pattern_to_glob_pattern
{
    my ($self, $core_pattern, $core_uses_pid) = @_;

    # There does not appear to be a practical way to feasibly determine who
    # dumped what, without having root permissions to control the core pattern.
    #
    # The core pattern may contain various strings, including the timestamp
    # at the time of the dump (not possible for us to determine), and the pid of
    # the process (possible for us to determine for the parent process, but not
    # for any subprocesses which may have crashed).
    #
    # Therefore, we use a simple hueristics-based approach which hopefully will
    # catch the majority of cases: we read the core pattern up to the first
    # variable portion, then we glob all files matching that pattern, and only
    # keep the ones with a timestamp more recent than when we started the process.
    #
    # For example, if the core pattern is like this:
    #
    #   /tmp/cores/core.%e.%p.%h.%t
    #
    # ...then we will find all files matching /tmp/cores/core.* who were created
    # after the process began.
    #
    # If the core pattern is piping to a program, then we guess that the program
    # will write out a core file "normally", for compatibility.  abrtd from Fedora
    # does this, for example.  We have no feasible way to guess exactly which core
    # pattern the program is going to use, so we just assume default of `core'.
    if ($core_pattern =~ m{ \A \| }xms) {
        $core_pattern = 'core';
    }

    # core_uses_pid is exactly equivalent to an extra .%p on the end of the pattern
    if ($core_uses_pid) {
        $core_pattern .= '.%p';
    }

    my $glob_pattern;

    my @characters = split //, $core_pattern;
    while (@characters) {
        my $c = shift @characters;

        if ($c ne '%') {
            $glob_pattern .= $c;
            next;
        }

        # We got a '%'.  Check the next character...
        $c = shift @characters;

        # silently drop single '%' at end of pattern ...
        last if (!defined($c));

        # retain '%%' -> '%' and continue parsing ...
        if ($c eq '%') {
            $glob_pattern .= $c;
            next;
        }

        # ...for anything else, it's something special.
        # Do not parse any further, we'll just glob the rest.
        $glob_pattern .= '*';
        last;
    }

    ### For core pattern  : $core_pattern
    ### Using glob pattern: $glob_pattern

    return $glob_pattern;
}

sub _core_pattern
{
    my ($self) = @_;

    if ($LINUX) {
        return $SYSCTL{ kernel }{ core_pattern };
    }
    elsif ($MAC) {
        # coredump path is always fixed on mac, see "Technical Note TN2124"
        return '/cores/core';
    }

    confess "internal error: unsupported OS $OSNAME";
}

sub _core_uses_pid
{
    my ($self) = @_;

    if ($LINUX) {
        return $SYSCTL{ kernel }{ core_uses_pid };
    }
    elsif ($MAC) {
        # coredump path always uses pid on MAC, see "Technical Note TN2124"
        return 1;
    }

    confess "internal error: unsupported OS $OSNAME";
}

# Attempts to find and return a list of all core files generated by the
# process.  Based on hueristics and may fail.
sub _find_core_files
{
    my ($self) = @_;

    my $glob_pattern = $self->_core_pattern_to_glob_pattern(
        $self->_core_pattern( ),
        $self->_core_uses_pid( ),
    );

    my @all = glob( $glob_pattern );

    return grep { mtime($_) >= $self->{ start_time } } @all;
}

sub _find_and_handle_core_files
{
    my ($self) = @_;

    my @files = $self->_find_core_files( );

    ### found core files: @files

    foreach my $file (@files) {
        $self->_handle_core_file( $file );
    }

    return;
}

sub _get_backtrace
{
    my ($self, $file) = @_;

    # Limit the backtrace lines to 100 in order to
    # prevent huge logfiles and slower builds
    my $MAX_BACKTRACE_FRAMES = '100';
    my $BACKTRACE_COMMANDS = "thread apply all bt $MAX_BACKTRACE_FRAMES";

    # Note, newer versions of gdb support an `--eval-command' option to
    # pass commands through the command line, but we want to support some
    # older gdb (e.g. on mac) which only have `-x'
    my $cmd_file = File::Temp->new( 'qtqa-testrunner-gdb.XXXXXX', TMPDIR => 1 );
    $cmd_file->printflush( $BACKTRACE_COMMANDS );

    my $command = ($self->{ testrunner }->command( ))[0];
    return capture_merged {
        print qq(gdb commands: $BACKTRACE_COMMANDS\n);
        my @cmd = (
            'gdb',
            $command,
            $file,
            '--batch',
            '-x',
            $cmd_file->filename( ),
        );

        my $status = system( @cmd );
        if ($status != 0) {
            print STDERR
                "while getting backtrace, gdb exited with status $status\n"
               ."gdb command: "
               .Data::Dumper->new( [ \@cmd ], [ 'cmd' ] )->Indent( 0 )->Dump( )
            ;
        }
    };
}

sub _handle_core_file
{
    my ($self, $file) = @_;

    my $testrunner = $self->{ testrunner };

    my $backtrace = $self->_get_backtrace( $file );
    if ($backtrace) {
        $testrunner->print_info(
            #
            # create nice chunk of text like:
            #
            #   ================== backtrace follows: ==================
            #   (the backtrace here)
            #   ========================================================
            #
            ('=' x 30). ' backtrace follows: ' . ('=' x 30) . "\n"
           ."$backtrace\n"
           .('=' x 80)."\n"
        );
    }

    if (! unlink( $file )) {
        $testrunner->print_info( "warning: could not remove core dump $file: $OS_ERROR\n" );
    }

    return;
}

=head1 NAME

QtQA::App::TestRunner::Plugin::core - process core files from crashing tests

=head1 SYNOPSIS

  # without this plugin:
  $ testrunner --capture-logs $HOME/test-logs -- tst_crashy
  # $HOME/test-logs/tst_crashy-00.txt says "process exited with signal 11 ..."

  # with this plugin:
  $ testrunner --plugin core --capture-logs $HOME/test-logs -- tst_crashy
  # $HOME/test-logs/tst_crashy-00.txt says "process exited with signal 11 ..."
  # and also contains a full backtrace of all threads

=head1 DESCRIPTION

This plugin will perform the following:

=over

=item *

Prior to the running of the command, testrunner will attempt to enable core dumps
via setrlimit().  This may fail depending on system policy, which will cause a
warning.

=item *

After the command completes, its status is checked.  If it appears to have dumped
core, testrunner will attempt to find the core file (and also the core files of any
subprocesses).

=item *

For each core file, gdb is launched and asked to give a full backtrace of each
thread.  This will be printed to STDERR and/or appended to the test log.

=back

=head1 CAVEATS

Only works on Linux and Mac.

On Mac, core dumps can be very slow to create.  In practice, times of up to
20 minutes to create a single core dump have been observed.  This may make the
usage of this plugin prohibitively slow on Mac.  Consider using the
Mac-specific "crashreporter" plugin instead.

It is not possible for a normal user to control the location where core files
are generated.  Also, it is possible for the system to be configured in such
a way that core files are generated in an unpredictable or inaccessible path.
Therefore, the detection of core files is based on heuristics, which should
cover the majority of use-cases but may fail for more exotic setups.
In particular, this will not work at all on systems where the core_pattern
is set up to pipe to a program.

Currently, the core files are deleted after extracting a backtrace.
There is no mechanism to permanently capture the core files - the size to
value ratio does not seem to warrant it at this time.

=cut

1;
