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

package QtQA::QMake::Project::LazyValue;
use strict;
use warnings;

our @CARP_NOT = qw( QtQA::QMake::Project );

use overload
    q{""} => \&_resolved,
    q{0+} => \&_resolved,
    q{bool} => \&_resolved,
    q{cmp} => \&_cmp,
    q{<=>} => \&_num_cmp,
;

sub new
{
    my ($class, %args) = @_;

    return bless \%args, $class;
}

sub _resolved
{
    my ($self) = @_;

    my $resolved;
    if (exists $self->{ _resolved }) {
        $resolved = $self->{ _resolved };
    } else {
        $self->{ project }->_resolve( );
        $resolved = $self->{ project }{ _resolved }{ $self->{ type } }{ $self->{ key } };
        $self->{ _resolved } = $resolved;
    }

    # Variables are typically arrayrefs, though they may have only 1 value.
    # Tests are typically plain scalars, no dereferencing required.
    #
    # However, we actually do not rely on the above; we support both cases (arrayref
    # or scalar) without checking what type we expect.
    #
    if (defined($resolved) && ref($resolved) eq 'ARRAY') {
        return wantarray ? @{ $resolved } : $resolved->[0];
    }

    # If there was an error, and we wantarray, make sure we return ()
    # rather than (undef)
    if (wantarray && !defined($resolved)) {
        return ();
    }

    return $resolved;
}

sub _cmp
{
    my ($self, $other) = @_;

    return "$self" cmp "$other";
}

sub _num_cmp
{
    my ($self, $other) = @_;

    return 0+$self <=> 0+$other;
}

1;

=head1 NAME

QtQA::QMake::Project::LazyValue - evaluate qmake values on-demand
                                  (implementation detail)

=head1 DESCRIPTION

This package implements the lazy evaluation of values from a qmake project.
It is an implementation detail; callers do not use this class directly.

=cut
