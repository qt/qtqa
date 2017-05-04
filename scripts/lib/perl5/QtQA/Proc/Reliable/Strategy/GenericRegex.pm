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

package QtQA::Proc::Reliable::Strategy::GenericRegex;
use strict;
use warnings;

use base qw( QtQA::Proc::Reliable::Strategy );

use Carp;
use List::MoreUtils qw( firstval );
use Readonly;
use Text::Trim;

# Default maximum amount of junk errors before we give up
Readonly my $NUM_TRIES => 10;

sub new
{
    my ($class) = @_;

    my $self = $class->SUPER::new( );

    $self->{ junk_error_count }     = 0;
    $self->{ num_tries }            = $NUM_TRIES;
    $self->{ patterns }             = [];
    $self->{ stderr_patterns }      = [];
    $self->{ stdout_patterns }      = [];

    return bless $self, $class;
}

sub push_stdout_patterns
{
    my ($self, @patterns) = @_;

    push @{$self->{ stdout_patterns }}, @patterns;

    return;
}

sub push_stderr_patterns
{
    my ($self, @patterns) = @_;

    push @{$self->{ stderr_patterns }}, @patterns;

    return;
}

sub push_patterns
{
    my ($self, @patterns) = @_;

    push @{$self->{ patterns }}, @patterns;

    return;
}

sub num_tries
{
    my ($self, $num_tries) = @_;

    if (defined $num_tries) {
        $self->{ num_tries } = $num_tries;
    }

    return $self->{ num_tries };
}

sub _process_text
{
    my ($self, $text, @patterns) = @_;

    # If already found a problem, no need to parse
    return if $self->_junk_error( );

    confess 'internal error: undefined $text' unless defined( $text );

    my $match = firstval { $text =~ $_ } @patterns;
    return if !$match;

    ++$self->{ junk_error_count };

    $self->_set_junk_error({
        text    => $text,
        pattern => $match,
    });

    return;
}

sub process_stdout
{
    my ($self, $text) = @_;

    return $self->_process_text(
        $text,
        @{$self->{ stdout_patterns }},
        @{$self->{ patterns }},
    );
}

sub process_stderr
{
    my ($self, $text) = @_;

    return $self->_process_text(
        $text,
        @{$self->{ stderr_patterns }},
        @{$self->{ patterns }},
    );
}

sub should_retry
{
    my ($self) = @_;

    return if $self->{ junk_error_count } > $self->{ num_tries };

    my $junk_error = $self->_junk_error( );
    return if !$junk_error;

    return "this error:\n   ".trim($junk_error->{ text })."\n"
          ."...was considered possibly junk due to matching $junk_error->{ pattern }";
}

# Basic sanity check to warn if someone didn't set up the object correctly
sub _sanity_check
{
    my ($self) = @_;

    return if ($self->{ done_sanity_check });

    $self->{ done_sanity_check } = 1;

    my @all_patterns = (
        @{$self->{ patterns }},
        @{$self->{ stdout_patterns }},
        @{$self->{ stderr_patterns }},
    );

    if (scalar(@all_patterns) == 0) {
        carp 'useless use of ' . __PACKAGE__ . ' with no patterns';
    }

    return;
}

sub about_to_run
{
    my ($self) = @_;

    $self->_sanity_check( );

    # Starting a new run, so discard current error (if any)
    $self->_set_junk_error( undef );

    return;
}

sub _junk_error
{
    my ($self) = @_;

    return $self->{ junk_error };
}

sub _set_junk_error
{
    my ($self, $error) = @_;

    $self->{ junk_error } = $error;

    return;
}

=head1 NAME

QtQA::Proc::Reliable::Strategy::GenericRegex - generic retry strategy
based on parsing with regexes

=head1 SYNOPSIS

  package QtQA::Proc::Reliable::Strategy::GCC;

  use base qw(QtQA::Proc::Reliable::Strategy::GenericRegex);

  sub new {
      my ($class) = @_;

      my $self = $class->SUPER::new( );

      $self->push_stderr_patterns(
          qr{^internal compiler error: }ms,  # retry on all ICEs
      );

      return bless $self, $class;
  }

Easily implement a reliable strategy based on parsing the output of a command
for a certain set of patterns.

=head1 DESCRIPTION

Most reliable strategies conceptually want to do the same few things:

=over

=item *

As the command runs, parse its stdout and/or stderr.

=item *

If the command output matches some predefined set of patterns, consider it
as a transient error and retry the command.

=item *

If the command has been retried a certain number of times already, give up.

=back

This base class implements the above in an easy-to-use way.

To use this class, subclass it, then call any of the following methods
(usually in your subclass's  constructor):

=over

=item B<push_stdout_patterns>( LIST )

Append to the list of patterns applied to STDOUT of the command
(if any of these match, the command will be retried).

=item B<push_stderr_patterns>( LIST )

Append to the list of patterns applied to STDERR of the command.

=item B<push_patterns>( LIST )

Append to the list of patterns applied to both STDOUT and STDERR of the command.

=item B<num_tries>

=item B<num_tries>( NUMBER )

Get or set the maximum amount of times the command will be allowed to retry
(optional, defaults to 10).

=back

Any mixture of stdout, stderr and combined stdout/stderr patterns may be given,
as long as at least one of them is present.

=cut

1;
