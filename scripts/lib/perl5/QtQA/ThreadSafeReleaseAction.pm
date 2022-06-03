# Copyright (C) 2017 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only WITH Qt-GPL-exception-1.0

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
