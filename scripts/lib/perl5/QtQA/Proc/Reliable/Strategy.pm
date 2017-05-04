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

package QtQA::Proc::Reliable::Strategy;
use strict;
use warnings;

use Class::Factory::Util;

sub new
{
    my ($class) = @_;

    return bless {}, $class;
}

# Strategies are expected to override these as appropriate.

sub about_to_run   {}
sub process_stdout {}
sub process_stderr {}

# should_retry omitted - no suitable default implementation,
# the strategy is 100% pointless if it does not implement this

=head1 NAME

QtQA::Proc::Reliable::Strategy - base class for QtQA::Proc::Reliable retry logic

=head1 SYNOPSIS

  package QtQA::Proc::Reliable::Strategy::GCC;
  use base qw(QtQA::Proc::Reliable::Strategy);

  # retry on any internal compiler errors, a maximum of 5 times

  sub new {
      my ($class) = @_;
      my $self = $class->SUPER::new();
      $self->{ internal_compiler_error } = 0;  # whether or not we've seen an ICE
      $self->{ run_count }               = 0;  # how many times we've run
      return bless $self, $class;
  }

  sub about_to_run {
      my ($self) = @_;
      $self->{ run_count }++;
      $self->{ internal_compiler_error } = 0;
  }

  sub process_stderr {
      my ($self, $text) = @_;
      $self->{ internal_compiler_error }++ if ($text =~ m{^internal compiler error: }ms);
  }

  sub should_retry {
      my ($self) = @_;
      return ($self->{ run_count } < 5 && $self->{ internal_compiler_error });
  }

Implement a reliable strategy for any command run via L<QtQA::Proc::Reliable>.

=head1 DESCRIPTION

Reliable strategies for use with L<QtQA::Proc::Reliable> are implemented by subclassing
this module.

=head2 STRATEGY LOOKUP

L<QtQA::Proc::Reliable> decides which strategies are used based on the options passed
during construction.  In the default case (automatic strategy selection), the strategy
class follows the name of the command being invoked.

Below are a few examples to clarify.

  EXAMPLE:                                          STRATEGIES:

  'git', 'fetch'                          =>        QtQA::Proc::Reliable::Strategy::Git

  {reliable=>1}, 'git', 'fetch'           =>        QtQA::Proc::Reliable::Strategy::Git

  {reliable=>['foo', 'bar' ]}, 'git'      =>        QtQA::Proc::Reliable::Strategy::Foo,
                                                    QtQA::Proc::Reliable::Strategy::Bar

  {reliable=>0}, 'git', 'fetch'           =>        (none)


=head1 METHODS

=over

=item B<new>()

Create and return the object as a reference to a blessed hash.

=item B<process_stdout>(TEXT)

This method is called once per line of standard output (TEXT).

=item B<process_stderr>(TEXT)

This method is called once per line of standard error (TEXT).

=item B<should_retry>()

If a command fails, QtQA::Proc::Reliable will call this function on the strategy
to decide if the command should be retried.

If the command should not be retried, this function should return a false value.

If the command should be retried, this function should return a human-readable
string describing the reason for retrying the command.

=item B<about_to_run>()

This function is called prior to each time QtQA::Proc::Reliable runs the command.
It may be called several times.

This will typically be used to increment an "attempt" counter or to reset some state
relating to the parsing of the command's output.

=back

=head1 SEE ALSO

L<QtQA::Proc::Reliable>, B<exe> function in L<QtQA::TestScript>

=cut

1;
