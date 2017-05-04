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

package QtQA::AnyEvent::Util;
use strict;
use warnings;

use AnyEvent;
use AnyEvent::Util qw();
use English qw( -no_match_vars );

use base 'Exporter';
our @EXPORT_OK = qw(run_cmd);

# extension of AnyEvent::Util::run_cmd
sub run_cmd
{
    my ($cmd, %options) = @_;

    my $timeout = delete $options{ timeout };
    my $cwd = delete $options{ cwd };
    my $on_prepare = delete $options{ on_prepare };
    my $retry = delete $options{ retry };
    my $croak = delete $options{ 'croak' };

    if ($cwd) {
        my $orig_on_prepare = $on_prepare;
        $on_prepare = sub {
            chdir( $cwd ) || warn __PACKAGE__ . "::run_cmd: chdir to $cwd: $!";
            if ($orig_on_prepare) {
                $orig_on_prepare->( @_ )
            };
        };
    }

    if ($on_prepare) {
        $options{ on_prepare } = $on_prepare;
    }

    # We need to know the pid, but note the caller might have asked for it too.
    my $pid;
    my $pid_ref = delete( $options{ '$$' } ) || \$pid;
    $options{ '$$' } = $pid_ref;

    my $inner_cv;
    my $timer;
    my $outer_cv = AE::cv();

    my $run;
    my $end = sub {
        my ($status) = @_;
        undef $timer;   # cancel any timer in progress
        undef $run;     # $run refers to itself recursively creating a cycle, break it
        if ($status && $croak) {
            local $LIST_SEPARATOR = '] [';
            $outer_cv->croak( "command [@{ $cmd }] exited with status $status" );
        } else {
            $outer_cv->send( $status );
        }
    };

    my $attempt = 0;
    $run = sub {
        $inner_cv = AnyEvent::Util::run_cmd( $cmd, %options );
        if ($timeout) {
            my $timeout_cv = $inner_cv;
            $timer = AE::timer( $timeout, 0, sub {
                if (!$timeout_cv->ready()) {
                    # timer expired and process is not yet finished
                    local $LIST_SEPARATOR = '] [';
                    warn "command [@{ $cmd }] timed out after $timeout seconds\n";

                    kill( 15, $$pid_ref );
                    $inner_cv->send( -1 );
                }

                undef $timer;
            });
        }

        $inner_cv->cb(
            sub {
                my $status = shift->recv();
                if ($status == 0) {
                    $end->( $status );
                } elsif (!$retry || ++$attempt > 5) {
                    $end->( $status );
                } else {
                    my $sleep = 2**$attempt;
                    local $LIST_SEPARATOR = '] [';
                    warn "command [@{ $cmd }] exited with status $status [retry in $sleep]\n";
                    my $retry_timer;
                    $retry_timer = AE::timer( $sleep, 0, sub {
                        undef $retry_timer;
                        $run->();
                    });
                }
            }
        );
    };

    $run->();

    return $outer_cv;
}

=head1 NAME

QtQA::AnyEvent::Util - extensions of AnyEvent::Util methods

=head1 METHODS

Methods are not exported by default.

=over

=item $cv = run_cmd $cmd, key => value...

Extended version of L<AnyEvent::Util>::run_cmd, supporting the following additional options:

=over

=item timeout => $seconds

Maximum permitted runtime of the command; if the command has not completed within this time,
it is killed (signal 15) and $cv receives a value of -1.

=item cwd => $path

Working directory used for the subprocess.

=item retry => $boolean

If true, the command will be repeated a few times (with delays) if it exits with a non-zero
exit code. Suitable for commands which may be subject to intermittent errors (e.g. ssh over
a flaky network connection).

=item croak => $boolean

If true, $cv will croak when the command fails.

=back

=back

=cut


1;
