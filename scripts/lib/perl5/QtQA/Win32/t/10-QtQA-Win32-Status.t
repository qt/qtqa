#!/usr/bin/env perl
use strict;
use warnings;

=head1 NAME

10-QtQA-Win32-Status.t - test for QtQA::Win32::Status

=cut

use FindBin;
use lib "$FindBin::Bin/../../..";

use QtQA::Win32::Status qw( STATUS_ACCESS_VIOLATION STATUS_INVALID_CRUNTIME_PARAMETER );

use Test::More;

sub test_integer_to_symbol
{
    is( $QtQA::Win32::Status::INTEGER_TO_SYMBOL{ 0xC0000005 }, 'STATUS_ACCESS_VIOLATION' );
    is( $QtQA::Win32::Status::INTEGER_TO_SYMBOL{ 0x00000000 }, 'STATUS_SUCCESS' );
    is( $QtQA::Win32::Status::INTEGER_TO_SYMBOL{ 0x00010001 }, 'DBG_EXCEPTION_HANDLED' );
    return;
}

sub test_symbol_to_integer
{
    is( $QtQA::Win32::Status::SYMBOL_TO_INTEGER{ 'STATUS_ACCESS_VIOLATION' }, 0xC0000005 );
    is( $QtQA::Win32::Status::SYMBOL_TO_INTEGER{ 'STATUS_SUCCESS' },          0x00000000 );
    is( $QtQA::Win32::Status::SYMBOL_TO_INTEGER{ 'STATUS_WAIT_0' },           0x00000000 );
    is( $QtQA::Win32::Status::SYMBOL_TO_INTEGER{ 'DBG_EXCEPTION_HANDLED' },   0x00010001 );
    return;
}

sub test_import
{
    is( STATUS_ACCESS_VIOLATION,           0xC0000005 );
    is( STATUS_INVALID_CRUNTIME_PARAMETER, 0xC0000417 );
    return;
}

sub run_test
{
    test_integer_to_symbol;
    test_symbol_to_integer;
    test_import;

    return;
}

#==============================================================================

if (!caller) {
    run_test;
    done_testing;
}
1;
