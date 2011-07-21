package QtQA::Proc::Reliable::Win32;
use strict;
use warnings;

use Capture::Tiny qw( tee );

sub new
{
    my ($class) = @_;

    return bless {
        status => -1,
    }, $class;
}

sub run
{
    my ($self, $command_ref) = @_;

    my ($stdout, $stderr) = tee {
        $self->{ status } = system( @{$command_ref} );
    };

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

sub _activate_callback
{
    my ($self, $cb, $text) = @_;
    while ($text =~ m{
        \G             # beginning of string or end of last match
        (
            [^\n]+     # anything but newline ...
            (?:\n|\z)  # ... up to the next newline (or end of string)
        )
    }gxms) {
        $cb->( $self, $1 );
    }

    return;
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
