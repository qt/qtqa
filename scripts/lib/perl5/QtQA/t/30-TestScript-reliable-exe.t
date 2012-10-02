#!/usr/bin/env perl
use strict;
use warnings;

package TestReliableExe;

use Capture::Tiny qw( capture );
use English qw( -no_match_vars );
use Env::Path;
use File::Spec::Functions;
use File::Temp qw( tempdir );
use FindBin;
use Readonly;
use Test::Exception;
use Test::More;
use File::Basename qw( basename );

use lib catfile( $FindBin::Bin, qw(..) x 2 );
use QtQA::Proc::Reliable::TESTDATA qw( %TESTDATA );
use QtQA::Test::More qw( :all );

use base 'QtQA::TestScript';

=head1 NAME

30-testscript-reliable-exe.t - system test of exe's `reliable' feature

=head1 DESCRIPTION

This test runs various commands with simulated error cases and verifies that
exe automatically recovers from certain errors.

=cut

sub new
{
    my ($class) = @_;

    my $self = $class->SUPER::new( );
    bless( $self, $class );
    return $self;
}

sub run_one_test
{
    my ($self, $testname, $testdata) = @_;

    my $tempdir = tempdir( basename($0).'.XXXXXX', TMPDIR => 1, CLEANUP => 1 );

    my $command             =   $testdata->{ command };
    my %mock_command        = %{$testdata->{ mock_command }};
    my $reliable            =   $testdata->{ reliable }         // 1;
    my $expected_stderr     =   $testdata->{ expected_exe_stderr }
                            //  $testdata->{ expected_raw_stderr }
                            //  q{};
    my $expected_stdout     =   $testdata->{ expected_exe_stdout }
                            //  $testdata->{ expected_raw_stdout }
                            //  q{};
    my $expected_status     =   $testdata->{ expected_status }  // 0;

    $mock_command{ directory } = $tempdir;

    if (! exists $mock_command{ name }) {
        $mock_command{ name } = $command->[0];
    }

    create_mock_command( %mock_command );

    # Put our mock command first in PATH
    local $ENV{ PATH } = $ENV{ PATH };
    Env::Path->PATH->Prepend( $tempdir );

    # Usually, we just pass our command to exe ...
    my @exe_args = @{$command};

    # ... but, for a non-auto `reliable', we pass options too.
    if (ref($reliable) || $reliable != 1) {
        @exe_args = ( { reliable => $reliable }, @exe_args );
    }

    my ($lives_or_dies_text, $lives_or_dies_ok)
        = ($expected_status == 0) ? ('exits successfully', \&lives_ok)
        :                           ('fails as expected',  \&dies_ok )
    ;

    my ($stdout, $stderr) = capture {
        $lives_or_dies_ok->(
            sub { $self->exe( @exe_args ) },
            "$testname $lives_or_dies_text",
        );
    };

    # exe() should have set $? to the expected value
    is( $?, $expected_status, "$testname \$? set as expected" );

    # Immediately prior to stdout should always be the command;
    # Prior to that may be either CWD or PATH lines.
    my $prefix = quotemeta( '+ '.join(' ', @{$command}) );
    $prefix = qr{
        \A
        (?:\+\ CWD:\ [^\n]+\n)?
        (?:\+\ PATH:\ [^\n]+\n)?
        $prefix \n
    }xms;
    like( $stdout, $prefix, "$testname stdout first line looks correct" );

    # Remove prefix for subsequent comparison
    $stdout =~ s{$prefix}{}xms;

    is_or_like( $stdout,  $expected_stdout,  "$testname stdout looks correct" );
    is_or_like( $stderr,  $expected_stderr,  "$testname stderr looks correct" );

    return;
}

sub run
{
    my ($self) = @_;

    while (my ($testname, $testdata) = each %TESTDATA) {
        $self->run_one_test($testname, $testdata);
    }

    done_testing( );

    return;
}

TestReliableExe->new( )->run( ) if (!caller);
1;

