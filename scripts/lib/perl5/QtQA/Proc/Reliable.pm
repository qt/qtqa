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

package QtQA::Proc::Reliable;
use strict;
use warnings;

use feature 'state';

use English qw( -no_match_vars );
use Carp;
use File::Basename;
use QtQA::Proc::Reliable::Strategy;
use Readonly;

BEGIN {
    # On Windows, Proc::Reliable is unreliable.
    # Instead we use a stub that we've written,
    # which avoids any emulated fork().
    if ($OSNAME =~ m{win32}i) {
        require QtQA::Proc::Reliable::Win32;
        QtQA::Proc::Reliable::Win32->import( );
    }
    else {
        require AutoLoader;
        require Proc::Reliable;
        Proc::Reliable->import( );
    }
}

Readonly my $WINDOWS => ($OSNAME =~ m{win32}i);

Readonly my $TIMEOUT
    => 60*60*24*30; # a long time, but not forever (because Proc::Reliable doesn't support that)

sub new
{
    my ($class, $arg_ref, @command) = @_;

    my $reliable = $arg_ref->{ reliable };

    # If reliable mode is not requested, nothing to do ...
    if (!$reliable) {
        return;
    }

    # Likewise, if there is no command, there is nothing to do...
    if (!@command) {
        return;
    }

    my $strat_possible = __PACKAGE__->_available_strategies( );
    my @strat_selected;

    # A reliable mode of 1 means `auto', so we try to find a strategy for
    # the command being run, which is guessed as the basename of $command[0]
    if (1 eq $reliable) {
        $reliable = basename( $command[0] );
        if (! exists $strat_possible->{ $reliable }) {
            # No auto-strategy for this command, nothing to do...
            return;
        }
    }

    # $reliable may be:
    #
    #   [ 'cmd1', 'cmd2', ... ]
    #
    # or just:
    #
    #   'cmd1'
    #
    if (ref($reliable) eq 'ARRAY') {
        @strat_selected = @{ $reliable };
    }
    else {
        @strat_selected = ( $reliable );
    }

    # Check that all the selected strategies really exist, and create them.
    my @strat_objects;
    foreach my $strat (@strat_selected) {
        croak(
            __PACKAGE__ . ": requested strategy `$strat' does not exist! Available strategies: "
          . join( ',', keys( %{ $strat_possible } ) )
        ) if (! exists $strat_possible->{ $strat });

        my $strat_object = $strat_possible->{ $strat }->new( );
        __PACKAGE__->_check_strategy({ name => $strat, object => $strat_object });

        push @strat_objects, $strat_object;
    }

    # OK, all strategies were valid, we're ready to go!
    return bless({
        strategies => \@strat_objects,
        command    => \@command,
    }, $class);
}

sub run
{
    my ($self) = @_;

    $self->_reset( );

    my $attempt = 1;
    my $proc    = $self->_create_proc( );

    $self->_run_proc( $proc );

    while ($proc->status() && (my $why = $self->_should_retry( $proc ))) {

        $self->_activate_retry_cb({
            proc    => $self,   # caller sees QtQA::Reliable::Proc (not Reliable::Proc) as $proc
            status  => $proc->status( ),
            reason  => $why,
            attempt => $attempt++,
        });

        $self->_run_proc( $proc );
    }

    return $proc->status( );
}

sub retry_cb
{
    my ($self, $callback) = @_;

    my $out = $self->{ retry_cb };

    if ($callback) {
        $self->{ retry_cb } = $callback;
    }

    return $out;
}

sub command
{
    my ($self) = @_;

    return @{$self->{ command }};
}

#==================================== internals ===================================================

sub _create_proc
{
    my ($self) = @_;

    my $proc;
    if ($WINDOWS) {
        $proc = $self->_create_proc_win32( );
    }
    else {
        $proc = Proc::Reliable->new( );

        $proc->stdin_error_ok( 1 );                 # OK if child does not read all stdin
        $proc->num_tries( 1 );                      # don't automatically retry on error
        $proc->child_exit_time( 0 );                # don't consider it an error if the test
                                                    # doesn't quit soon after closing stdout
        $proc->time_per_try( $TIMEOUT );            # don't run for longer than this
        $proc->maxtime( $TIMEOUT );                 # ...and again (need to set both)
        $proc->want_single_list( 0 );               # force stdout/stderr handled separately
    }

    $proc->stdout_cb( sub { $self->_handle_stdout( @_ ) } );
    $proc->stderr_cb( sub { $self->_handle_stderr( @_ ) } );

    return $proc;
}

sub _create_proc_win32
{
    my ($self) = @_;

    return QtQA::Proc::Reliable::Win32->new( );
}

sub _run_proc
{
    my ($self, $proc) = @_;

    # Inform all strategies that we are about to run.
    # In most cases, this will do nothing, but it may be used e.g. to reset some internal
    # context to a clean state
    $self->_foreach_strategy( sub { shift->about_to_run( ) } );

    $proc->run( $self->{ command } );

    return;
}

sub _foreach_strategy
{
    my ($self, $sub) = @_;

    my @out;

    foreach my $strategy (@{$self->{ strategies }}) {
        push @out, $sub->( $strategy );
    }

    return @out;
}

sub _reset
{
    my ($self) = @_;

    # not yet implemented

    return;
}

sub _handle_stdout
{
    my ($self, $handle, $text) = @_;

    $handle->printflush( $text );
    $self->_foreach_strategy( sub { shift->process_stdout( $text ) } );

    return;
}

sub _handle_stderr
{
    my ($self, $handle, $text) = @_;

    $handle->printflush( $text );
    $self->_foreach_strategy( sub { shift->process_stderr( $text ) } );

    return;
}

sub _should_retry
{
    my ($self, $proc) = @_;

    my @why = $self->_foreach_strategy( sub { shift->should_retry() } );

    # For now, we just return the "first" reason why we should retry.
    # It's unclear if there is any benefit in attempting to combine the reasons
    # (e.g. in the case where multiple strategies flag an error as transient).
    return shift @why;
}

sub _activate_retry_cb
{
    my ($self, $why_ref) = @_;

    if ($self->{ retry_cb }) {
        $self->{ retry_cb }->( $why_ref );
    }

    return;
}

#==================================== static functions ============================================

# Returns a hashref of all available strategies.
# Keys are strategy names, values are strategy classes.
# The return value is calculated only once, and cached for subsequent calls.
sub _available_strategies
{
    state $strategies = __PACKAGE__->_find_available_strategies( );
    return $strategies;
}

# Returns a hashref of all available strategies,
# exactly as _available_strategies, but not cached.
sub _find_available_strategies
{
    my $out = {};

    # foreach subclass, which is the last part of the name, e.g. `Git', `Network' ...
    foreach my $subclass (QtQA::Proc::Reliable::Strategy->subclasses( )) {

        # full class is the full class name, e.g. 'QtQA::Proc::Reliable::Strategy::Git'
        my $fullclass = "QtQA::Proc::Reliable::Strategy::$subclass";

        # strategy name is the short class name in lowercase, e.g. 'git'
        my $strategy = lc $subclass;

        # Make sure it can be loaded
        eval "use $fullclass";  ## no critic - unavoidable (block form won't work)
        confess( __PACKAGE__ . ": internal error: while loading $fullclass: $@" ) if ($@);

        $out->{ $strategy } = $fullclass;
    }

    return $out;
}

# Dies if the given strategy does not appear to implement the correct strategy interface
sub _check_strategy
{
    my ($class, $arg_ref) = @_;

    my $name   = $arg_ref->{ name };
    my $object = $arg_ref->{ object };

    confess( "$class: internal error: strategy `$name' could not be created; "
            ."did someone forget to implement the `new' sub?" )
        if (! defined $object);

    my @required_subs = qw(
        process_stdout
        process_stderr
        should_retry
        about_to_run
    );

    foreach my $sub (@required_subs) {
        next if $object->can( $sub );

        confess( "$class: internal error: strategy `$name' is missing required sub `$sub'" );
    }

    return;
}

=head1 NAME

QtQA::Proc::Reliable - reliably execute processes

=head1 SYNOPSIS

  use QtQA::Proc::Reliable;

  my @cmd  = qw(git clone git://example.com/repo.git);
  my $proc = QtQA::Proc::Reliable->new({ reliable => 1 }, @cmd);

  my $status;
  if (!$proc) {
      # no `reliable' strategy available, fall back to plain ol' system
      $status = system(@cmd);
  }
  else {
      # $proc may automatically retry for certain errors
      $proc->retry_cb( sub { warn "Retrying @cmd ..." } );
      $status = $proc->run();
  }

  confess "@cmd exited with status $status" if ($status != 0);

This example will attempt to find a "reliable strategy" for the git command.
If it does, the command may be run via the B<run>() function, which will
automatically retry the command several times in the case of e.g. temporary
network timeouts.

=head1 DESCRIPTION

This class is a logical extension of the highly useful L<Proc::Reliable> module.
That module provides a generic toolkit with many options for running external
processes reliably; this module further wraps L<Proc::Reliable> with appropriate
settings for a variety of commands, with heuristics based on experience running
these commands in Qt's automated test infrastructure.

This class is primarily considered an implementation detail of the
L<QtQA::TestScript> B<exe> function, and generally won't be used directly.

=head1 METHODS

=over

=item B<new>( OPTIONS, COMMAND )

Create a new object with the given OPTIONS and COMMAND.

If a strategy cannot be found, returns undef.  Otherwise, returns an object.

These parameters are interpreted exactly as for the L<QtQA::TestScript> B<exe>
function.  Please read the documentation for that function for more details.

=item B<command>

Returns the command encapsulated by this object, as a list.

=item B<retry_cb>( SUBREF )

=item B<retry_cb>

Set or get a callback which is executed each time the process is retried.

If set, the callback will be called between each try of the command,
with a single hashref containing the following:

=over

=item proc

Reference to the QtQA::Reliable::Proc object.

=item status

Exit status of the process (e.g. as returned by B<system>).

=item reason

A human-readable string explaining the reason why the command is about to be
retried.  This is suitable to print to a log, for example.

=item attempt

The number of the attempt which has failed.  Counting starts from 1 for the
first attempt.

=back

=back

=head1 SEE ALSO

L<Proc::Reliable>, L<QtQA::Proc::Reliable::Strategy>, B<exe> function in L<QtQA::TestScript>

=cut

1;
