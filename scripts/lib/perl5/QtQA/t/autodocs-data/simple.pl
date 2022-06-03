#!/usr/bin/env perl
# Copyright (C) 2017 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only WITH Qt-GPL-exception-1.0


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
