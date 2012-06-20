#############################################################################
##
## Copyright (C) 2012 Digia Plc and/or its subsidiary(-ies).
## Contact: http://www.qt-project.org/legal
##
## This file is part of the Quality Assurance module of the Qt Toolkit.
##
## $QT_BEGIN_LICENSE:LGPL$
## Commercial License Usage
## Licensees holding valid commercial Qt licenses may use this file in
## accordance with the commercial license agreement provided with the
## Software or, alternatively, in accordance with the terms contained in
## a written agreement between you and Digia.  For licensing terms and
## conditions see http://qt.digia.com/licensing.  For further information
## use the contact form at http://qt.digia.com/contact-us.
##
## GNU Lesser General Public License Usage
## Alternatively, this file may be used under the terms of the GNU Lesser
## General Public License version 2.1 as published by the Free Software
## Foundation and appearing in the file LICENSE.LGPL included in the
## packaging of this file.  Please review the following information to
## ensure the GNU Lesser General Public License version 2.1 requirements
## will be met: http://www.gnu.org/licenses/old-licenses/lgpl-2.1.html.
##
## In addition, as a special exception, Digia gives you certain additional
## rights.  These rights are described in the Digia Qt LGPL Exception
## version 1.1, included in the file LGPL_EXCEPTION.txt in this package.
##
## GNU General Public License Usage
## Alternatively, this file may be used under the terms of the GNU
## General Public License version 3.0 as published by the Free Software
## Foundation and appearing in the file LICENSE.GPL included in the
## packaging of this file.  Please review the following information to
## ensure the GNU General Public License version 3.0 requirements will be
## met: http://www.gnu.org/copyleft/gpl.html.
##
##
## $QT_END_LICENSE$
##
#############################################################################
package QtQA::Gerrit;
use strict;
use warnings;

use AnyEvent::Handle;
use AnyEvent::Util;
use AnyEvent;
use Carp;
use URI;

use base 'Exporter';
our @EXPORT_OK = qw(stream_events);

sub stream_events
{
    my (%args) = @_;

    my $url = $args{ url } || croak 'missing url argument';
    my $on_event = $args{ on_event } || croak 'missing on_event argument';
    my $on_error = $args{ on_error } || sub {
        my ($handle, $error) = @_;
        warn __PACKAGE__ . ": $error\n";
        return 1;
    };

    my $INIT_SLEEP = 2;
    my $MAX_SLEEP = 60*10;
    my $sleep = $INIT_SLEEP;

    my $gerrit = URI->new( $url );

    if ($gerrit->scheme() ne 'ssh') {
        croak "gerrit URL $url is not supported; only ssh URLs are supported\n";
    }

    my @ssh = (
        'ssh',
        '-oBatchMode=yes',          # never do interactive prompts
        '-oServerAliveInterval=30', # try to avoid the server silently dropping connection
        ($gerrit->port() ? ('-p', $gerrit->port()) : ()),
        ($gerrit->user() ? ($gerrit->user() . '@') : q{}) . $gerrit->host(),
        'gerrit',
        'stream-events',
    );

    my $out = {};

    my $cleanup = sub {
        my ($handle) = @_;
        delete $handle->{ timer };
        if (my $r_h = delete $handle->{ r_h }) {
            $r_h->destroy();
        }
        if (my $cv = delete $handle->{ cv }) {
            $cv->cb( sub {} );
            if (my $pid = $handle->{ pid }) {
                kill( 15, $pid );
            }
        }
    };

    my $restart;

    my $handle_error = sub {
        my ($handle, $error) = @_;
        my $retry;
        eval {
            $retry = $on_error->( $handle, $error );
        };
        if ($retry) {
            # retry after $sleep seconds only
            $handle->{ timer } = AnyEvent->timer( after => $sleep, cb => sub { $restart->( $handle ) } );
            $sleep *= 2;
            if ($sleep > $MAX_SLEEP) {
                $sleep = $MAX_SLEEP;
            }
        } else {
            $cleanup->( $handle );
        }
    };

    $restart = sub {
        my ($handle) = @_;
        $cleanup->( $handle );

        $sleep = $INIT_SLEEP;

        my ($r, $w) = portable_pipe();

        $handle->{ r_h } = AnyEvent::Handle->new(
            fh => $r,
        );
        $handle->{ r_h }->on_error(
            sub {
                my (undef, undef, $error) = @_;
                $handle_error->( $handle, $error );
            }
        );

        # run stream-events with stdout connected to pipe ...
        $handle->{ cv } = run_cmd(
            \@ssh,
            '>' => $w,
            '$$' => \$handle->{ pid },
        );
        $handle->{ cv }->cb(
            sub {
                my ($status) = shift->recv();
                $handle_error->( $handle, "ssh exited with status $status" );
            }
        );

        my %read_req;
        %read_req = (
            # read one json item at a time
            json => sub {
                my ($h, $data) = @_;

                # every successful read resets sleep period
                $sleep = $INIT_SLEEP;

                $on_event->( $handle, $data );
                $h->push_read( %read_req );
            }
        );
        $handle->{ r_h }->push_read( %read_req );
    };

    my $stash = {};
    $restart->( $stash );
    return guard {
        $cleanup->( $stash );
    };
}

=head1 NAME

QtQA::Gerrit - interact with Gerrit code review tool

=head1 SYNOPSIS

  use AnyEvent;
  use QtQA::Gerrit qw(stream_events);

  # alert me when new patch sets arrive in ssh://codereview.qt-project.org:29418/qt/myproject
  my $stream = stream_events(
    url => 'ssh://codereview.qt-project.org:29418/',
    on_event => sub {
      my (undef, $event) = @_;
      if ($event->{type} eq 'patchset-added' && $event->{change}{project} eq 'qt/myproject') {
        system("xmessage", "New patch set arrived!");
      }
    }
  );

  AE::cv()->recv(); # must run an event loop for callbacks to be activated

This module provides some utility functions for interacting with the Gerrit code review tool.

This module is an L<AnyEvent> user and may be used with any event loop supported by AnyEvent.

=head1 METHODS

=over

=item B<stream_events> url => $gerrit_url

Connect to "gerrit stream-events" on the given gerrit host and register one or more callbacks
for events. Returns an opaque handle to the stream-events connection; the connection will be
aborted if the handle is destroyed.

$gerrit_url should be a URL with ssh schema referring to a valid Gerrit installation
(e.g. "ssh://user@gerrit.example.com:29418/").

Supported callbacks are documented below. All callbacks receive the stream-events
handle as their first argument.

=over

=item on_event => $cb->($handle, $data)

Called when an event has been received.
$data is a reference to a hash representing the event.

See the Gerrit documentation for information on the possible events:
L<http://gerrit.googlecode.com/svn/documentation/2.2.1/cmd-stream-events.html>

=item on_error => $cb->($handle, $error)

Called when an error occurs in the connection.
$error is a human-readable string.

Examples of errors include network disruptions between your host and the Gerrit server,
or the ssh process being killed unexpectedly. Receiving any kind of error means that
some Gerrit events may be lost.

If this callback returns a true value, stream_events will attempt to reconnect
to Gerrit and resume processing; otherwise, the connection is terminated and no more
events will occur.

The default error callback will warn and return 1, retrying on all errors.

=back


=back

=cut

1;
