#!/usr/bin/env perl
#############################################################################
##
## Copyright (C) 2012 Nokia Corporation and/or its subsidiary(-ies).
## All rights reserved.
## Contact: Nokia Corporation (qt-info@nokia.com)
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
