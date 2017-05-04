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
package QtQA::Log::Dispatch::Email::MailSender;

use strict;
use warnings;

use base 'Log::Dispatch::Email';

use AnyEvent;
use English qw( -no_match_vars );
use Mail::Sender;

sub new
{
    my ($class, %args) = @_;

    my %params = (
        smtp => 'localhost',
        min_timeout => 120,
        max_timeout => 600,
        header => q{},
        prefix => q{},
        replyto => q{},
    );

    foreach my $key (keys %params) {
        my $value = delete $args{ $key };
        if (defined $value) {
            $params{ $key } = $value;
        }
    }

    my $self = $class->SUPER::new( %args );

    foreach my $key (keys %params) {
        $self->{ $key } = $params{ $key };
    }

    $self->setup_callbacks();

    return $self;
}

sub _get_string
{
    my ($self, $key) = @_;

    my $value = $self->{ $key };
    if (my $ref = ref($value)) {
        if ($ref eq 'CODE') {
            return $value->();
        }
    }

    # force stringify
    return "$value";
}

sub setup_callbacks
{
    my ($self) = @_;

    # We don't want to flood with one email per message, but also
    # don't want to wait too long before sending mails, so we buffer
    # for at least $min_timeout seconds up to a maximum of $max_timeout
    # seconds before sending the mails.
    #
    # The mailer also flushes on destruction, so we will send at exit even
    # if these timers are ongoing.
    my $min_timeout = $self->{ min_timeout };
    my $max_timeout = $self->{ max_timeout };

    my $logger_min_timer;
    my $logger_max_timer;

    my $flush = sub {
        # TODO: this is entirely blocking and not Coro/AnyEvent-aware, so
        # coros won't make progress while SMTP negotations are slow
        $self->flush();
        undef $logger_min_timer;
        undef $logger_max_timer;
    };

    $self->add_callback(
        sub {
            my (%data) = @_;

            my $first_message_in_mail = !$logger_max_timer;

            $logger_min_timer = AE::timer( $min_timeout, 0, $flush );
            $logger_max_timer ||= AE::timer( $max_timeout, 0, $flush );

            # email messages are always formatted with two leading spaces (which triggers
            # 'preformatted text' handling in many mail clients) and newlines between
            # messages
            my $prefix = $self->_get_string( 'prefix' );
            $data{ message } = $prefix . $data{ message };
            $data{ message } =~ s{^}{  }mg;
            $data{ message } .= "\n";

            if ($first_message_in_mail) {
                my $header = $self->_get_string( 'header' );
                $data{ message } = "$header\n\n$data{ message }";
            }

            return $data{ message };
        }
    );

    return;
}

sub send_email
{
    my ($self, %args) = @_;

    eval {
        Mail::Sender->new()->MailMsg(
            {
                encoding => 'quoted-printable',
                from => $self->{ from } || 'LogDispatch@foo.bar',
                on_errors => 'die',
                replyto => $self->{ replyto } || q{},
                smtp => $self->{ smtp },
                subject => $self->{ subject },
                to => ( join ',', @{ $self->{ to } } ),
                charset => 'utf-8',
                msg => $args{ message },
            }
        );
    };

    if (my $error = $EVAL_ERROR) {
        warn "Error sending logs by email: $error\n";
    }

    return;
}

=head1 NAME

QtQA::Log::Dispatch::Email::MailSender - send log messages via email

=head1 DESCRIPTION

This is a subclass of L<Log::Dispatch::Email> which sends email message via L<Mail::Sender>.

This class provides functionality equivalent to L<Log::Dispatch::Email::MailSender> with a
few additional features:

=over

=item *

emails are always encoded as UTF-8 quoted-printable.

=item *

timer-based flushing of the message buffer; log messages occurring close together will be
buffered into a single email, up to a maximum timeout.  (The default L<Log::Dispatch::Email>
strategy is to not flush until the logger is destroyed, which is too late in some contexts).

L<AnyEvent> timers are used, so this feature requires the usage of an AnyEvent-aware event loop.

See 'min_timeout', 'max_timeout' parameters.

=item *

a few additional formatting capabilities; ssee 'prefix', 'header' parameters.

=back

=head1 PARAMETERS

The following parameters are accepted, in addition to those supported by L<Log::Dispatch::Email>:

=over

=item smtp

The SMTP host for sending emails.

=item min_timeout, max_timeout

Minimum and maximum timeouts before sending an email after a log message is generated.
Each batch of log messages will be buffered for at least min_timeout seconds and at most
max_timeout seconds.

=item header, prefix

Additional text inserted into the email.

The 'header' is inserted once at the beginning of each email, while the 'prefix' is inserted
once before each individual log message.

May be either a scalar or a callback which returns a scalar.

=back

=cut

1;
