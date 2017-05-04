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

package QtQA::Proc::Reliable::Win32;
use strict;
use warnings;

use Capture::Tiny qw( tee );
use Carp;
use Data::Dumper;
use English qw( -no_match_vars );
use IO::Handle;
use MIME::Base64;
use Readonly;
use Storable qw( thaw freeze );

use threads;
use threads::shared;

BEGIN {
    if ($OSNAME =~ m{win32}i) {
        require Win32::Job;
        Win32::Job->import( );
        require Win32::Process;
        Win32::Process->import( );
    }
}

# special key which, if present in $ENV, means we should simply run
# and exit a given command (for win32 support)
Readonly my $ENV_EXEC_KEY => q{__QTQA_PROC_RELIABLE_EXEC};

# a long time, but not forever
Readonly my $LONG_TIME => 60*60*24*7;

# token denoting end of stream (see later comment)
Readonly my $MAGIC_END_TOKEN => qq{__QTQA_PROC_RELIABLE_EOF\n};

sub new
{
    my ($class) = @_;

    return bless {
        # From Proc::Reliable API, and therefore ostensibly "public"...
        status  => -1,
        msg     => q{},
        maxtime => $LONG_TIME,
        # Our own private stuff; shared for child thread access
        _lines => shared_clone([]), # lines of output
        _event => share(my $event), # synchronization flag
        _running => share(my $running), # 1 when job is running
        _reader_ready => share(my $reader_ready), # thread ready count
    }, $class;
}

# Reset state specific to each run()
sub _reset
{
    my ($self) = @_;

    $self->{ status } = -1;
    $self->{ msg } = q{};
    @{$self->{ _lines }} = ();
    ${$self->{ _running }} = 0;
    ${$self->{ _reader_ready }} = 0;

    return;
}

#
# The design for reading from the child process is as follows:
#
#  - parent creates a pipe for stdout and a pipe for stderr.
#
#  - parent creates three threads:
#      - stdout reader thread: reads from stdout pipe
#      - stderr reader thread: reads from stderr pipe
#      - Win32::Job thread: runs the process, connected to stdout/stderr pipes
#    The reader threads are a workaround for the lack of a select() system
#    call to determine when new data is available in the pipe.
#    The Win32::Job thread is a workaround for the fact that the Win32::Job
#    API is synchronous, so we can't run and read output at the same time.
#
#  - the parent runs a mini event loop which is woken up by the
#    threads whenever something interesting happens.
#
#  - as threads read lines, they store them in $self->{ _lines };
#    each line knows whether it is from stdout or stderr, retaining
#    order (approximately); and a reader thread wakes up the parent
#    whenever lines are received.
#
#  - when the Win32::Job thread completes, the parent writes a special
#    token down the pipes to let the reader threads know it is time to stop.
#    This is necessary because, unlike on Unix, the reading end of
#    a pipe on Windows apparently is not notified when the writing
#    end is closed.
#

# Function to be called from within a new thread, to read from pipe.
sub _reader_thread
{
    my ($self, %args) = @_;
    my $pipe = $args{ pipe };   # pipe we'll read
    my $ident = $args{ ident }; # stream identifier (e.g. 'stdout', 'stderr')

    my $running;
    {
        lock( $self->{ _running } );

        # let parent know we are ready (we have the lock on _running)
        {
            lock( $self->{ _reader_ready } );
            ${$self->{ _reader_ready }}++;
            cond_signal( $self->{ _reader_ready } );
        }

        # Wait until the Win32::Job is definitely connected to the other end of the pipe.
        my $until = time() + 30;
        until ($running = ${$self->{ _running }}) {
            last if !cond_timedwait( $self->{ _running }, $until );
        }
    }

    unless ($running) {
        warn __PACKAGE__ . ": $ident reader thread: timeout waiting for wakeup from parent.\n";
        return;
    }

    # Child reads from $pipe and inserts into $self->{ _lines },
    # stops when $MAGIC_END_TOKEN is found.
    while (my $line = <$pipe>) {
        if ($line eq $MAGIC_END_TOKEN) {
            last;
        }
        push @{$self->{ _lines }}, shared_clone([$ident, $line]);

        # notify parent that we have lines (unless we are in the process
        # of shutting down)
        if (${$self->{ _running }}) {
            lock( $self->{ _event } );
            cond_signal( $self->{ _event } );
        }
    }
    return;
}

# Creates a pipe and thread, and returns a (filehandle, thread) pair.
# The filehandle is opened for writing and the thread will read from it.
sub _make_pipe_and_thread
{
    my ($self, $ident) = @_;

    my $fh_r;
    my $fh_w;
    pipe( $fh_r, $fh_w ) || die "make $ident pipe: $!";
    binmode( $fh_r, ':crlf' );
    binmode( $fh_w, ':crlf' );

    $fh_w->autoflush( 1 );

    # Make thread
    my $thread = threads->create(
        sub { $self->_reader_thread( @_ ) },
        pipe => $fh_r,
        ident => $ident,
    );

    return ($fh_w, $thread);
}

# Function to be called from the Win32::Job thread
sub _win32_job_thread
{
    my ($self, @spawn_args) = @_;

    my $job = Win32::Job->new( );
    my $timeout = $self->{ maxtime };
    my $pid;
    my $exited_normally;

    $pid = $job->spawn( @spawn_args );

    # Reader threads can start to read now.
    {
        lock( $self->{ _running } );
        ${$self->{ _running }} = 1;
        cond_broadcast( $self->{ _running } );
    }

    my $until = time() + $timeout;

    # We use `watch' with a watchdog to abort if requested.
    $exited_normally = $job->watch( sub {
        # Return true (abort) if timeout exceeded ...
        return 1 if (time() > $until);
        # Return true (abort) if parent requested us to stop, by setting _running = 0
        return 1 if (!${$self->{ _running }});
        # Neither of the above are true?  Then keep going
        return 0;
    }, 1 );

    ${$self->{ _running }} = 0;

    # Wake up the parent thread
    {
        lock( $self->{ _event } );
        cond_signal( $self->{ _event } );
    }

    # Note!  We CANNOT return $job (created in this thread) to the calling thread.
    # This causes a silent, hard crash.
    return (
        pid => $pid,
        exited_normally => $exited_normally,
        exitcode => $job->status()->{ $pid }{ exitcode },
    );
}

# Since we're using line-based IO and we send a sentinel line
# down the pipe to end the output, we end up with one trailing newline.
# This function removes it.
sub _fixup_trailing_newline
{
    my ($self) = @_;

    my %to_fix = ( stdout => 1, stderr => 1 );
    my $i = @{$self->{ _lines }} - 1;
    while ($i >= 0 && keys(%to_fix)) {
        my $thing = $self->{ _lines }[$i];

        if (exists($to_fix{ $thing->[0] }) ) {
            # found a stream in need of fixing.
            # remove any trailing \n.
            $thing->[1] =~ s{\n\z}{};

            # If it's now empty (which is the usual case), just remove it.
            if ($thing->[1] eq q{}) {
                $thing->[1] = undef;
            }

            delete $to_fix{ $thing->[0] };
        }

        --$i;
    }

    return;
}

sub _stop_reader_threads
{
    my ($self, $fd, $thr) = @_;

    # Finish up the reader threads.
    # We need to send a newline in case the process itself did not end its output
    # with a newline.  We'll strip it later.
    for my $this_fd (@{$fd}) {
        print $this_fd "\n$MAGIC_END_TOKEN";
        close( $this_fd ) || die "close pipe: $!";
    }

    for my $this_thr ( @{$thr} ) {
        $this_thr->join();
    }

    return;
}

sub _stringify_command
{
    my ($self, @command) = @_;
    my @out;
    while (@command) {
        push @out, q{}.shift(@command);
    }
    return @out;
}

sub run
{
    my ($self, $command_ref) = @_;

    # Stringify everything in @{$command_ref} (they may be Getopt::Long callback
    # objects, which cannot be serialized by freeze())
    $command_ref = [ $self->_stringify_command( @{$command_ref} ) ];

    $self->_reset( );

    # This convoluted setup aims to solve these problems:
    #
    #  - We want to use exactly the same algorithm for turning a list of
    #    arguments into a single command string as perl uses itself in system()
    #
    #  - We want to be able to timeout and kill the child process, and system()
    #    can't do this.
    #
    # We use Win32::Job to achieve the timeout/kill requirement.
    #
    # To achieve the system() compatibility, we pass the command array
    # through an environment variable into an intermediate perl process.
    #
    # This intermediate process is a new perl instance, which simply loads
    # this file again with $ENV_EXEC_KEY set.

    my $self_pm = $INC{ 'QtQA/Proc/Reliable/Win32.pm' };

    # May happen if the module was included in an odd way
    if (!defined( $self_pm )) {
        confess 'package '.__PACKAGE__." cannot find its own .pm file!\n"
               ."%INC: ".Dumper(\%INC);
    }
    if (! -e $self_pm) {
        confess 'package '.__PACKAGE__." should be located at $self_pm, but "
               .'that file does not exist!';
    }

    local $ENV{ $ENV_EXEC_KEY } = encode_base64( freeze( $command_ref ), undef );
    my $cmd = qq{"$EXECUTABLE_NAME" "$self_pm"};

    my ($stdout_w, $stdout_thr) = $self->_make_pipe_and_thread( 'stdout' );
    my ($stderr_w, $stderr_thr) = $self->_make_pipe_and_thread( 'stderr' );

    # Wait until both readers are ready (which means they are waiting on _running)
    {
        lock( $self->{ _reader_ready } );
        until (${$self->{ _reader_ready }} == 2) {
            cond_wait( $self->{ _reader_ready } );
        }
    }

    my ($job_thr) = threads->create( sub {
        return $self->_win32_job_thread(
            $EXECUTABLE_NAME, $cmd, { stdout => $stdout_w, stderr => $stderr_w }
        )
    });

    my $callback_error;

    # We are now live; all threads running.
    # Try to dequeue all lines to callbacks as soon as we are notified that we
    # have some.
    {
        lock( $self->{ _event } );

        while (!$job_thr->is_joinable( )) {
            # block until an event occurs
            cond_wait( $self->{ _event } );

            # _running == 0 implies job thread has completed.
            last unless (${$self->{ _running }});

            eval {
                $self->_dequeue_lines( );
            };
            if ($@) {
                $callback_error = $@;
                last;
            }
        }
    }

    if ($callback_error) {
        # Aborted early due to "die" in a callback.
        ${$self->{ _running }} = 0;
        $job_thr->join( );
        $self->_stop_reader_threads([ $stdout_w, $stderr_w ], [ $stdout_thr, $stderr_thr ]);
        local $@ = $callback_error;
        die;
    }

    my %results = $job_thr->join();

    my $pid = $results{ pid };
    my $exitcode = $results{ exitcode };
    my $exited_normally = $results{ exited_normally };

    if (!$exited_normally) {
        # The docs for Win32::Job state that a timeout is the only
        # reason that run/watch will return false
        $self->{ msg } .= "Timed out after $self->{ maxtime } seconds\n";
    }

    if ( ! defined $exitcode) {
        # I think that this will never happen ...
        $self->{ msg } .= "Win32::Job did not report an exit code for the process\n";
        $exitcode = 294;
    }

    {
        # status needs to exceed 32 bits in some cases; see CAVEATS
        use bigint;
        $self->{ status } = ($exitcode << 8);
    }

    $self->_stop_reader_threads( [ $stdout_w, $stderr_w ], [ $stdout_thr, $stderr_thr ] );

    # All threads completed.  Fix up the trailing \n due to MAGIC_END_TOKEN,
    # then print out the last lines.
    $self->_fixup_trailing_newline( );
    $self->_dequeue_lines( );

    return;
}

sub status
{
    my ($self) = @_;

    return $self->{ status };
}

sub stdout_cb
{
    my ($self, $cb) = @_;

    $self->{ stdout_cb } = $cb;

    return;
}

sub stderr_cb
{
    my ($self, $cb) = @_;

    $self->{ stderr_cb } = $cb;

    return;
}

sub msg {
    my ($self) = @_;

    return $self->{ msg };
}

sub maxtime {
    my ($self, $maxtime) = @_;

    $self->{ maxtime } = $maxtime;

    return;
}

sub _dequeue_lines
{
    my ($self) = @_;

    while (my $thing = shift @{$self->{ _lines }}) {
        my ($stream, $text) = @{$thing};
        if ($stream eq 'stdout' && $self->{ stdout_cb }) {
            $self->_activate_callback( $self->{ stdout_cb }, *STDOUT, $text );
        }
        elsif ($stream eq 'stderr' && $self->{ stderr_cb }) {
            $self->_activate_callback( $self->{ stderr_cb }, *STDERR, $text );
        }
    }

    return;
}

sub _activate_callback
{
    my ($self, $cb, $handle, $text) = @_;
    return unless $text;
    while ($text =~ m{
        \G             # beginning of string or end of last match
        (
            [^\n]*     # anything but newline (or maybe nothing)...
            (?:\n|\z)  # ... up to the next newline (or end of string)
        )
    }gxms) {
        $cb->( $handle, $1 ) if $1;
    }

    return;
}

# Helper for win32 support; if signalled by the presence of this environment
# variable, just run a command and exit.
if (!caller && exists( $ENV{ $ENV_EXEC_KEY } )) {
    my $command = delete $ENV{ $ENV_EXEC_KEY };
    $command = thaw decode_base64 $command;

    # If we use plain system/waitpid, perl already converts all exit codes
    # to POSIX-compatible semantics.  In the usual case that is fine, but
    # in the crashing case and a few others, it destroys information:
    #
    #   - POSIX uses 8 bits as various "status" info and 8 bits as the exit code
    #   - Windows has no concept of "status" and uses a full 32 bits as exit code
    #
    # Therefore Windows exit codes can easily overflow and lose information
    # when converted to POSIX-style exit codes.
    #
    # Luckily, perl does provide a workaround: as documented in "perlport",
    # the special system( 1, @args ) syntax returns the pid of the process
    # (without waiting for it to complete), and we can use native Win32 API
    # to get the _real_ exit status.

    my ($pid, $child_process, $this_process, $exitcode);
    $pid = system( 1, @{$command} );

    Win32::Process::Open( $child_process, $pid, 0 ) || die __PACKAGE__.": OpenProcess child: $!";
    $child_process->Wait( Win32::Process::INFINITE() );
    $child_process->GetExitCode( $exitcode );

    # A plain exit() will discard all but the lower 16 bits of the exit code.
    # Use Win32-native API to retain all information.
    Win32::Process::Open( $this_process, $$, 0 ) || die __PACKAGE__.": OpenProcess self: $!";
    $this_process->Kill( $exitcode );

    # should not happen
    die __PACKAGE__.": internal error: still alive after Kill( $exitcode ) on self";
}

=head1 NAME

QtQA::Proc::Reliable::Win32 - win32 backend for reliable processes

=head1 DESCRIPTION

This is a helper class used by QtQA::Proc::Reliable, on Windows only.
It is not intended to be used directly by anything else.

The primary motivation of this class is to avoid usage of perl's fork()
emulation on Windows, which is considered too buggy for general usage.

This class implements a very limited subset of the Proc::Reliable API.
Notably, the stdout_cb/stderr_cb callbacks are supported, with some
caveats.

=head1 CAVEATS

=over

=item Threads

Perl interpreter threads are used for reading output from the process.
This won't usually matter, but may have an impact on certain code.
For example, Test::More will only work correctly if C<use threads>
appears prior to C<use Test::More>.

=item Exceptions in callbacks

If an exception is generated within stdout_cb or stderr_cb, there may
be a small delay (~1 second) before the exception is propagated upwards.
This delay occurs because the interpreter threads must be safely
destroyed before returning control to the caller, and the threads cannot
be interrupted instantly (due to limitations in the Win32::Job API).

=item CRLF

The C<:crlf> layer is enabled on the stdout/stderr streams (see "PerlIO").
This means that a CRLF output by the child process will be converted to
a plain LF by the time it arrives in stdout_cb/stderr_cb.
This is intentional, but may cause problems if the subprocess outputs
binary data.  So, don't do that.  A workaround could be added if there
is a valid use-case.

=item status() returns a big integer

On Unix-like platforms, the exit code of a process is a mere 8 bits;
Windows, on the other hand, uses a full 32 bits for the exit code.
Rather than truncating that exit code, this module retains the full
32 bits.

However, on Unix, it's necessary to shift the process exit B<status>
right by 8 bits in order to get the exit B<code>.  The status() function
here follows those semantics (as it would be error-prone and inconvenient
otherwise), but this means status() needs to return (up to) a 40-bit
integer on Windows.

=back

=cut

1;
