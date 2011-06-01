#!/usr/bin/env perl
use 5.010;
use strict;
use warnings;

package Qt::App::TestRunner;

=head1 NAME

testrunner - helper script to safely run autotests

=head1 SYNOPSIS

  # Run one autotest safely...
  $ path/to/testrunner [options] -- some/tst_test1

  # Run many autotests safely... (from within a Qt project)
  # A maximum runtime of 2 minutes each...
  $ make check "TESTRUNNER=path/to/testrunner --timeout 120 --"
  # Will run:
  #   path/to/testrunner --timeout 120 -- some/tst_test1
  #   path/to/testrunner --timeout 120 -- some/tst_test2
  # etc...

This script is a wrapper for running autotests safely and ensuring that
uniform results are generated.  It is designed to integrate with Qt's
`make check' feature.

=head1 OPTIONS

=over

=item B<--help>

Print this message.

=item B<--timeout> <value>

If the test takes longer than <value> seconds, it will be killed, and
the testrunner will exit with a non-zero exit code to indicate failure.

=back

=head1 CAVEATS

Note that, if a test is killed (e.g. due to a timeout), no attempt is made
to terminate the entire process tree spawned by that test (if any), as this
appears to be impractical.  In practice, that means any helper programs run
by a test may be left running if the test is killed.

It is possible that the usage of this script may alter the apparent ordering
of stdout/stderr lines from the test, though this is expected to be rare
enough to be negligible.

As an implementation detail, this script may retain the entire stdout/stderr
of the test in memory until the script exits.  This will make it inappropriate
for certain uses; for example, if your test is expected to run for one day
and print 100MB of text to stdout, testrunner will use (at least) 100MB of
memory, which is possibly unacceptable.

=cut

use Getopt::Long qw(
    GetOptionsFromArray
    :config pass_through require_order
);
use English      qw( -no_match_vars );
use Pod::Usage   qw( pod2usage );
use Proc::Reliable;
use Readonly;

Readonly my %DEFAULTS => (
    timeout =>  60*60*24*7, # a long time, but not forever
);

# exit code for strange process issues, such as a failure to fork
# or failure to waitpid; this is expected to be extremely rare,
# so the exit code is unusual
Readonly my $EXIT_PROCESS_ERROR => 96;

# exit code if subprocess dies due to signal; not all that rare
# (tests crash or hang frequently), so the exit code is not too unusual
Readonly my $EXIT_PROCESS_SIGNALED => 3;

sub new
{
    my ($class) = @_;

    my $self = bless {}, $class;
    return $self;
}

sub run
{
    my ($self, @args) = @_;

    %{$self} = ( %DEFAULTS, %{$self} );

    GetOptionsFromArray( \@args,
        'help|?'    =>  sub { pod2usage(1) },
        'timeout=i' =>  \$self->{timeout},
    ) || pod2usage(2);

    $self->do_subprocess( @args );

    return;
}

sub do_subprocess
{
    my ($self, @command_and_args) = @_;

    @command_and_args || die 'not enough arguments';

    $self->{command_and_args} = \@command_and_args;

    my $proc = Proc::Reliable->new( );

    $proc->stdin_error_ok( 1 );                 # OK if child does not read all stdin
    $proc->num_tries( 1 );                      # don't automatically retry on error
    $proc->child_exit_time( 0 );                # don't consider it an error if the test
                                                # doesn't quit soon after closing stdout
    $proc->time_per_try( $self->{timeout} );    # don't run for longer than this
    $proc->maxtime( $self->{timeout} );         # ...and again (need to set both)
    $proc->want_single_list( 0 );               # force stdout/stderr handled separately

    # Print all output as we receive it;
    # The first parameter to the callback is the correct IO handle (STDOUT or STDERR)
    my $print_sub = sub {
        my $io_handle = shift;
        $io_handle->print(@_);
    };
    $proc->stdout_cb( $print_sub );
    $proc->stderr_cb( $print_sub );

    $proc->run( \@command_and_args );

    $self->exit_appropriately( $proc );

    return;
}

sub print_info
{
    my ($self, $msg) = @_;

    return if (!$msg);

    # Prefix every line with __PACKAGE__ so it is clear where this message comes from
    my $prefix = __PACKAGE__ . ': ';
    $msg =~ s{ \n (?! \z ) }{\n$prefix}xms;   # replace all newlines except the trailing one
    $msg = $prefix.$msg;

    print STDERR $msg;

    return;
}

sub exit_appropriately
{
    my ($self, $proc) = @_;

    my $status = $proc->status( );

    # Print out any messages from the Proc::Reliable; this will include information
    # such as "process timed out", etc.
    my $msg = $proc->msg( );

    if ($msg) {
        # Don't mention the `Exceeded retry limit'; we never retry, so it would only be
        # confusing.  Note that this can (and often will) reduce $msg to nothing.
        $msg =~ s{ ^ Exceeded \s retry \s limit \s* }{}xms;
    }

    $self->print_info( $msg );

    if ($status == -1) {
        if (!$msg) {
            # we should have a msg, but avoid being entirely silent if we don't
            $self->print_info( 'Proc::Reliable failed to run process for unknown reasons' );
        }
        exit( $EXIT_PROCESS_ERROR );
    }

    my $signal = ($status & 127);
    if ($signal) {
        my $coredumped = ($status & 128);
        $self->print_info(
            "Process exited due to signal $signal"
           .($coredumped ? '; dumped core' : q{})
           ."\n"
        );
        exit( $EXIT_PROCESS_SIGNALED );
    }

    my $exitcode = ($status >> 8);

    # Proc::Reliable gives an exit code of 255 if the binary doesn't exist.
    # Try to give a helpful hint about this case.
    # This is racy and not guaranteed to be correct.
    if ($exitcode == 255) {
        my $command = $self->{command_and_args}[0];
        if (! -e $command) {
            $self->print_info( "$command: No such file or directory\n" );
        }
    }

    # testrunner exits with same exit code as the child
    exit( $exitcode );
}

Qt::App::TestRunner->new( )->run( @ARGV ) if (!caller);
1;

