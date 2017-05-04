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

package QtQA::ThreadSafeReleaseAction;
use strict;
use warnings;

use ReleaseAction;
use parent 'ReleaseAction';

use Exporter;
our @EXPORT_OK = qw(on_release);

# simply rebless a ReleaseAction as this class
sub new
{
    my ($class, @args) = @_;
    my $out = ReleaseAction->new( @args );
    return bless $out, $class;
}

# on_release { some block } form
sub on_release(&)  ## no critic (ProhibitSubroutinePrototypes) - for compatibility with ReleaseAction
{
    my ($code) = @_;
    return __PACKAGE__->new( $code );
}

# never clone these objects to other threads
sub CLONE_SKIP
{
    return 1;
}

1;

__END__

=head1 NAME

QtQA::ThreadSafeReleaseAction - thread-safe ReleaseAction subclass

=head1 SYNOPSIS

This class is identical to the ReleaseAction class except that release actions
are never cloned to new perl threads.

=cut
