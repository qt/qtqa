# Copyright (C) 2017 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only WITH Qt-GPL-exception-1.0

package QtQA::Proc::Reliable::Strategy::Git;
use strict;
use warnings;

use base qw( QtQA::Proc::Reliable::Strategy::SSH );

use Readonly;

Readonly my @JUNK_STDERR_PATTERNS => (

    # This error message can be caused by a wide range of errors on both the
    # client and server side.  It is not _always_ a junk error, but usually
    # is if the test script is written correctly.
    #
    # An example client-side error: trying to push to a read-only URL
    # (e.g. using git:// instead of git@)
    #
    # An example server-side error: server-side process is killed by OOM killer,
    # or someone manually restarting it, or similar issues during the git operation.
    #
    qr{^fatal: The remote end hung up unexpectedly$}msi,

    # Unknown host, could be temporary DNS outage:
    #
    #   $ git clone git://foo.bar.baz/quux >/dev/null
    #   fatal: Unable to look up foo.bar.baz (port 9418) (Name or service not known)
    #
    qr{^fatal: Unable to look up .*\(Name or service not known\)$}msi,

    # `unable to connect a socket' could be various kinds of temporary outage:
    #
    #   $ git clone git://128.0.0.1/quux >/dev/null
    #   128.0.0.1[0: 128.0.0.1]: errno=No route to host
    #   fatal: unable to connect a socket (No route to host)
    #
    #   $ git clone git://example.com/quux >/dev/null
    #   example.com[0: 192.0.32.10]: errno=Connection timed out
    #   example.com[0: 2620:0:2d0:200::10]: errno=Network is unreachable
    #   fatal: unable to connect a socket (Network is unreachable)
    #
    qr{^fatal: unable to connect a socket }msi,

    # all of the above class of error are also possible for HTTP and SSH clones:
    #
    #   HTTP - not yet handled (because we do not use this in practice)
    #   SSH  - handled by subclassing the SSH strategy
    #
);

sub new
{
    my ($class) = @_;

    my $self = $class->SUPER::new( );
    $self->push_stderr_patterns( @JUNK_STDERR_PATTERNS );

    return bless $self, $class;
}

=head1 NAME

QtQA::Proc::Reliable::Strategy::Git - reliable strategy for git command

=head1 DESCRIPTION

Attempts to recover from various forms of network issues when performing
git commands which access a remote host.

=head1 SEE ALSO

L<QtQA::Proc::Reliable::Strategy>

=cut

1;
