#############################################################################
##
## Copyright (C) 2012 Nokia Corporation and/or its subsidiary(-ies).
## Contact: http://www.qt-project.org/
##
## This file is part of the Quality Assurance module of the Qt Toolkit.
##
## $QT_BEGIN_LICENSE:LGPL$
## GNU Lesser General Public License Usage
## This file may be used under the terms of the GNU Lesser General Public
## License version 2.1 as published by the Free Software Foundation and
## appearing in the file LICENSE.LGPL included in the packaging of this
## file. Please review the following information to ensure the GNU Lesser
## General Public License version 2.1 requirements will be met:
## http://www.gnu.org/licenses/old-licenses/lgpl-2.1.html.
##
## In addition, as a special exception, Nokia gives you certain additional
## rights. These rights are described in the Nokia Qt LGPL Exception
## version 1.1, included in the file LGPL_EXCEPTION.txt in this package.
##
## GNU General Public License Usage
## Alternatively, this file may be used under the terms of the GNU General
## Public License version 3.0 as published by the Free Software Foundation
## and appearing in the file LICENSE.GPL included in the packaging of this
## file. Please review the following information to ensure the GNU General
## Public License version 3.0 requirements will be met:
## http://www.gnu.org/copyleft/gpl.html.
##
## Other Usage
## Alternatively, this file may be used in accordance with the terms and
## conditions contained in a signed written agreement between you and Nokia.
##
##
##
##
##
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
use MIME::Base64;
use Readonly;
use Storable qw( thaw freeze );

BEGIN {
    if ($OSNAME =~ m{win32}i) {
        require Win32::Job;
        Win32::Job->import( );
    }
}

# special key which, if present in $ENV, means we should simply run
# and exit a given command (for win32 support)
Readonly my $ENV_EXEC_KEY => q{__QTQA_PROC_RELIABLE_EXEC};

# a long time, but not forever
Readonly my $LONG_TIME => 60*60*24*7;

sub new
{
    my ($class) = @_;

    return bless {
        status  => -1,
        msg     => q{},
        maxtime => $LONG_TIME,
    }, $class;
}

sub run
{
    my ($self, $command_ref) = @_;

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

    my $job = Win32::Job->new( );
    my $timeout = $self->{ maxtime };
    my $pid;
    my $exited_normally;

    my ($stdout, $stderr) = tee {
        $pid = $job->spawn( $EXECUTABLE_NAME, $cmd );
        $exited_normally = $job->run( $timeout );
    };

    if (!$exited_normally) {
        # The docs for Win32::Job state that a timeout is the only
        # reason that run() will return false
        $self->{ msg } .= "Timed out after $timeout seconds\n";
    }

    my $exitcode = $job->status()->{ $pid }{ exitcode };

    if ( ! defined $exitcode) {
        # I think that this will never happen ...
        $self->{ msg } .= "Win32::Job did not report an exit code for the process\n";
        $exitcode = 294;
    }

    $self->{ status } = ($exitcode << 8);

    if ($self->{ stdout_cb }) {
        $self->_activate_callback( $self->{ stdout_cb }, $stdout );
    }
    if ($self->{ stderr_cb }) {
        $self->_activate_callback( $self->{ stderr_cb }, $stderr );
    }

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

sub _activate_callback
{
    my ($self, $cb, $text) = @_;
    while ($text =~ m{
        \G             # beginning of string or end of last match
        (
            [^\n]*     # anything but newline (or maybe nothing)...
            (?:\n|\z)  # ... up to the next newline (or end of string)
        )
    }gxms) {
        $cb->( $self, $1 );
    }

    return;
}

# Helper for win32 support; if signalled by the presence of this environment
# variable, just run a command and exit.
if (!caller && exists( $ENV{ $ENV_EXEC_KEY } )) {
    my $command = delete $ENV{ $ENV_EXEC_KEY };
    $command = thaw decode_base64 $command;
    exit( system( @{$command} ) >> 8);
}

=head1 NAME

QtQA::Proc::Reliable::Win32 - win32 backend for reliable processes

=head1 DESCRIPTION

This is a helper class used by QtQA::Proc::Reliable, on Windows only.
It is not intended to be used directly by anything else.

The primary motivation of this class is to avoid usage of perl's fork()
emulation on Windows, which is considered too buggy for general usage.

This class implements a very limited subset of the Proc::Reliable API,
with two known significant differences:

=over

=item *

When stdout_cb/stderr_cb are activated, the stdout/stderr from the
child process has already been printed.  This means there is no way
to hide or rewrite the output.  It also means the callbacks should
not print out the output, otherwise it will be printed twice.

=item *

stdout_cb/stderr_cb are only activated once the process has run to
completion.  This means that, compared to other operating systems,
the ordering of stdout_cb/stderr_cb is almost always lost (although
the order is never guaranteed on other platforms either); and there
is no way for a strategy to abort a process in the middle of a run
on Windows.

=back

=cut

1;
