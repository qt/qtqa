#############################################################################
##
## Copyright (C) 2015 The Qt Company Ltd.
## Contact: http://www.qt.io/licensing/
##
## This file is part of the Quality Assurance module of the Qt Toolkit.
##
## $QT_BEGIN_LICENSE:LGPL21$
## Commercial License Usage
## Licensees holding valid commercial Qt licenses may use this file in
## accordance with the commercial license agreement provided with the
## Software or, alternatively, in accordance with the terms contained in
## a written agreement between you and The Qt Company. For licensing terms
## and conditions see http://www.qt.io/terms-conditions. For further
## information use the contact form at http://www.qt.io/contact-us.
##
## GNU Lesser General Public License Usage
## Alternatively, this file may be used under the terms of the GNU Lesser
## General Public License version 2.1 or version 3 as published by the Free
## Software Foundation and appearing in the file LICENSE.LGPLv21 and
## LICENSE.LGPLv3 included in the packaging of this file. Please review the
## following information to ensure the GNU Lesser General Public License
## requirements will be met: https://www.gnu.org/licenses/lgpl.html and
## http://www.gnu.org/licenses/old-licenses/lgpl-2.1.html.
##
## As a special exception, The Qt Company gives you certain additional
## rights. These rights are described in The Qt Company LGPL Exception
## version 1.1, included in the file LGPL_EXCEPTION.txt in this package.
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
