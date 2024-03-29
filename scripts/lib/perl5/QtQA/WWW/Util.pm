# Copyright (C) 2017 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only WITH Qt-GPL-exception-1.0
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
