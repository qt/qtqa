#############################################################################
##
## Copyright (C) 2013 Digia Plc and/or its subsidiary(-ies).
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
package QtQA::WWW::Util;
use strict;
use warnings;

use AnyEvent::HTTP;
use Carp;
use Coro;
use JSON;
use URI;

use base 'Exporter';
our @EXPORT_OK = qw(
    blocking_http_request
    fetch_json_data
    fetch_to_scalar
    www_form_urlencoded
);
our %EXPORT_TAGS = (all => \@EXPORT_OK);

sub www_form_urlencoded
{
    my (%args) = @_;

    my $uri = URI->new( );
    $uri->query_form( %args );
    return $uri->query( );
}

sub blocking_http_request
{
    my ($method, $url, @args) = @_;
    http_request( $method, $url, @args, Coro::rouse_cb() );
    return Coro::rouse_wait();
}

sub fetch_to_scalar
{
    my ($url) = @_;
    my ($data, $headers) = blocking_http_request( GET => $url );
    if ($headers->{ Status } != 200) {
        croak "fetch $url: $headers->{ Status } $headers->{ Reason }";
    }
    return $data;
}

sub fetch_json_data
{
    my ($url) = @_;

    my $json = fetch_to_scalar( $url );

    return decode_json( $json );
}

=head1 NAME

QtQA::WWW::Util - utility methods for dealing with web services

=head1 METHODS

Methods are not exported by default; they may be exported individually,
or all together by using the ':all' tag.

=over

=item www_form_urlencoded( key1 => $val1, key2 => $val2 ... )

Given a hash, returns a string representation in application/x-www-form-urlencoded format.
Useful for constructing the body of an HTTP POST normally filled by a web form.

  my $postdata = www_form_urlencoded(id => 1234, request => 'do this; do that' );
  # $postdata eq 'request=do+this%3B+do+that&id=1234'

=item blocking_http_request( $method => $url, key => value... )

Like http_request from L<AnyEvent::HTTP>, but blocks until the request is complete and returns
the result rather than invoking a callback.

Blocking is achieved by the usage of L<Coro>, so use this only if your application is Coro-aware.

=item fetch_to_scalar( $url )

Do an HTTP GET on the given URL and return the fetched content. Croaks on error.

Note: uses L<Coro>.

=item fetch_json_data( $url )

Do an HTTP GET on the given URL, parse the fetched content as JSON and return the parsed object.
Croaks on error.

Note: uses L<Coro>.

=back

=cut

1;
