#!/usr/bin/env perl
use strict;
use warnings;

use Capture::Tiny qw( capture );
use English qw( -no_match_vars );
use Env::Path;
use File::Temp qw( tempdir );
use Readonly;
use Test::More;
use File::Basename qw( basename );
use File::Spec::Functions;
use FindBin;

use lib catfile( $FindBin::Bin, qw(..) x 3 );
use QtQA::Proc::Reliable;
use QtQA::Proc::Reliable::TESTDATA qw( %TESTDATA );
use QtQA::Test::More qw( :all );

=head1 NAME

20-reliable-strategies.t - system test of various QtQA::Proc::Reliable strategies

=head1 DESCRIPTION

This test runs various commands with simulated error cases and verifies that
QtQA::Proc::Reliable is able to recover from certain errors, while correctly
passing unrecoverable errors through to the caller.

=cut

sub run_one_test
{
    my ($testname, $testdata) = @_;

    my $tempdir = tempdir( basename($0).'.XXXXXX', TMPDIR => 1, CLEANUP => 1 );

    my $command             =   $testdata->{ command };
    my %mock_command        = %{$testdata->{ mock_command }};
    my $reliable            =   $testdata->{ reliable }             // 1;
    my $expected_retries    =   $testdata->{ expected_retries }     // 0;
    my $expected_status     =   $testdata->{ expected_status }      // 0;
    my $expected_stderr     =   $testdata->{ expected_raw_stderr }  // q{};
    my $expected_stdout     =   $testdata->{ expected_raw_stdout }  // q{};

    $mock_command{ directory } = $tempdir;

    if (! exists $mock_command{ name }) {
        $mock_command{ name } = $command->[0];
    }

    create_mock_command( %mock_command );

    my $proc = QtQA::Proc::Reliable->new( { reliable => $reliable }, @{$command} );
    ok( $proc, "$testname proc created OK" );

    # Store all retry info for later inspection
    my @retries;
    $proc->retry_cb( sub { push @retries, \@_; } );

    # Put our mock command first in PATH
    local $ENV{ PATH } = $ENV{ PATH };
    Env::Path->PATH->Prepend( $tempdir );

    my $status;
    my ($stdout, $stderr) = capture {
        $status = $proc->run( );
    };

    is( $status,          $expected_status,  "$testname correct status" );
    is( scalar(@retries), $expected_retries, "$testname correct retry count" );

    is_or_like( $stdout,  $expected_stdout,  "$testname stdout looks correct" );
    is_or_like( $stderr,  $expected_stderr,  "$testname stderr looks correct" );

    return;
}

sub run
{
    while (my ($testname, $testdata) = each %TESTDATA) {
        run_one_test($testname, $testdata);
    }

    done_testing( );

    return;
}

run if (!caller);
1;

