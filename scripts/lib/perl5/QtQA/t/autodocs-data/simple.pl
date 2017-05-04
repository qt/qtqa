#!/usr/bin/env perl
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


use strict;
use warnings;

# This file is run via the `autodocs' test and has its generated `--help'
# message compared against an expected value.

=head1 NAME

simple.pl - test script used by `autodocs' test

=head1 SYNOPSIS

  $ ./simple.pl [options]

Frobnitz the quux via usage of blargle.

Crungy factor may be taken into consideration if the operand density
is sufficiently cromulent.

=cut

use FindBin;
use lib "$FindBin::Bin/../../..";

package SimpleScript;
use base qw(QtQA::TestScript);

my @PROPERTIES = (
    q{quux.style}        =>  q{Style of the quux to be frobnitzed (e.g. `cheesy', `purple')},
    q{quux.inplace}      =>  q{If 1, do the frobnitz in-place, instead of copying the quux }
                            .q{first (use with care!)},
    q{fast}              =>  q{If 1, sacrifice accuracy for speed},
);

sub new
{
    my ($class, @args) = @_;

    my $self = $class->SUPER::new;
    bless $self, $class;

    $self->set_permitted_properties(@PROPERTIES);
    $self->get_options_from_array(\@args);

    return $self;
}

sub run
{
    my ($self) = @_;

    # If this were a real script, the implementation would go here ...

    print "Frobnitz successfully completed!\n";

    return;
}

SimpleScript->new(@ARGV)->run if (!caller);
1;
