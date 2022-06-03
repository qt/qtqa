# Copyright (C) 2017 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only WITH Qt-GPL-exception-1.0

package QtQA::Proc::Reliable::Strategy::SSH;
use strict;
use warnings;

use base qw( QtQA::Proc::Reliable::Strategy::GenericRegex );

use Readonly;

# Pattern matching all formatted errno strings (in English) which
# may be considered possibly junk
Readonly my $JUNK_ERRNO_STRING => qr{

      \QNo route to host\E          # network outage
    | \QNetwork is unreachable\E    # network outage
    | \QConnection timed out\E      # network outage
    | \QConnection refused\E        # ssh service outage (e.g. host is rebooting)

}xmsi;

Readonly my @JUNK_STDERR_PATTERNS => (

    # Unknown host, could be temporary DNS outage:
    #
    #   $ ssh ignore_me@foo.bar.quux
    #   ssh: Could not resolve hostname foo.bar.quux: Name or service not known
    #
    qr{^ssh: Could not resolve hostname}msi,

    # Various types of possibly temporary outages:
    #
    #   $ ssh ignore_me@128.0.0.1
    #   ssh: connect to host 128.0.0.1 port 22: No route to host
    #
    #   $ ssh -p 9999 ignore_me@127.0.0.1
    #   ssh: connect to host 127.0.0.1 port 9999: Connection refused
    #
    #   $ ssh ignore_me@example.com
    #   ssh: connect to host example.com port 22: Network is unreachable
    #
    #   $ ssh ignore_me@nokia.com
    #   ssh: connect to host nokia.com port 22: Connection timed out
    #
    qr{^ssh: connect to host.*: $JUNK_ERRNO_STRING$}msi,

);

sub new
{
    my ($class) = @_;

    my $self = $class->SUPER::new( );
    $self->push_stderr_patterns( @JUNK_STDERR_PATTERNS );

    return bless $self, $class;
}

=head1 NAME

QtQA::Proc::Reliable::Strategy::SSH - reliable strategy for ssh command

=head1 DESCRIPTION

Attempts to recover from various forms of network issues when performing
ssh commands.

=head1 SEE ALSO

L<QtQA::Proc::Reliable::Strategy>

=cut

1;
