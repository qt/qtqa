#!/usr/bin/env perl
use strict;
use warnings;
use utf8;

=head1 NAME

10-test-more-create_mock_command.t - basic test of create_mock_command

=head1 DESCRIPTION

This test performs checking of simple error cases for create_mock_command,
and does a simple check of a successful usage.

More extensive testing of create_mock_command is performed indirectly by
its usage in QtQA::Proc::Reliable tests.

=cut

use Capture::Tiny qw( capture );
use Encode;
use English qw( -no_match_vars );
use File::Spec::Functions;
use File::Temp qw( tempdir );
use FindBin;
use IO::File;
use Readonly;
use Test::Exception;
use Test::More tests => 24;
use Test::NoWarnings;

use lib catfile( $FindBin::Bin, qw(..) x 3 );
use QtQA::Test::More qw( :all );

# Separator for PATH-like variables
Readonly my $PATHSEP => ($OSNAME =~ m{win32}i) ? q(;)
                     :                           q(:);

sub test_errors
{
    dies_ok( sub { create_mock_command( ) }, 'dies on missing args' );

    dies_ok( sub { create_mock_command(
        nam         => 'foo',  # intentionally misspelled
        directory   => 'bar',
        sequence    => [],
    ) }, 'dies on misspelled arg' );

    dies_ok( sub { create_mock_command(
        name        => '',
        directory   => 'bar',
        sequence    => [],
    ) }, 'dies on bad name' );

    dies_ok( sub { create_mock_command(
        name        => 'quux1',
        directory   => '/some_directory_which_does_not_exist',
        sequence    => [],
    ) }, 'dies on nonexistent directory' );

    my $tempdir = tempdir( 'qtqa-create-mock-command.XXXXXX', TMPDIR => 1, CLEANUP => 1 );

    dies_ok( sub { create_mock_command(
        name        => 'quux2',
        directory   => $tempdir,
        sequence    => [
            { stdout => 'hi', stderr => 'there', exitcode => 3 },
            { stdout => 'hi', stder  => 'again', exitcode => 0 },  # intentionally misspelled
        ],
    ) }, 'dies on bad sequence' );

    # Create an empty script file
    { IO::File->new( "$tempdir/quux3", '>' ) || die $!; }

    dies_ok( sub { create_mock_command(
        name        => 'quux3',
        directory   => $tempdir,
        sequence    => [
            { stdout => 'hi', stderr => 'there', exitcode => 3 },
        ],
    ) }, 'dies if script already exists' );

    # Create an empty step file
    { IO::File->new( "$tempdir/quux4.step-13", '>' ) || die $!; }

    dies_ok( sub { create_mock_command(
        name        => 'quux4',
        directory   => $tempdir,
        sequence    => [
            { stdout => 'hi', stderr => 'there', exitcode => 3 },
        ],
    ) }, 'dies if a step file exists' );

    # Create a sequence which is way too large
    my @sequence = map { { stdout => 'hi', stderr => 'there', exitcode => 0 } } (0..500);
    dies_ok( sub { create_mock_command(
        name        => 'quux5',
        directory   => $tempdir,
        sequence    => \@sequence,
    ) }, 'dies if sequence is too large' );

    return;
}

sub test_basic_success
{
    my $tempdir = tempdir( 'qtqa-create-mock-command.XXXXXX', TMPDIR => 1, CLEANUP => 1 );

    my @sequence = (
        # stdout only
        { stdout => "Hello\nthere :)\n",     exitcode => 0, delay => 1 },

        # stderr only
        { stderr => "I hope you are well\n", exitcode => 2, delay => 2 },

        # mixed (and with nonascii)
        { stdout => "早上好\n你好马？\n",    stderr => "我很好\n你呢？\n", exitcode => 58 },
    );

    create_mock_command(
        name        =>  'git',
        directory   =>  $tempdir,
        sequence    =>  \@sequence,
    );

    ok( -e( "$tempdir/git" ),         'script was created' );

    # OK, mock git is created, run it.
    local $ENV{PATH} = $tempdir . $PATHSEP . $ENV{PATH};
    my $i = 0;
    foreach my $step (@sequence) {
        my $status;
        my $then = time();
        my ($stdout, $stderr) = capture {
            $status = system( 'git', '--foo', 'bar', 'baz' );
        };
        my $runtime = time() - $then;

        is( ($status >> 8), $step->{ exitcode },                     "step $i exitcode is OK" );
        is( $stdout,        encode_utf8( $step->{ stdout } // q{} ), "step $i stdout is OK" );
        is( $stderr,        encode_utf8( $step->{ stderr } // q{} ), "step $i stderr is OK" );
        if ($step->{ delay }) {
            ok( $runtime >= $step->{ delay }, "step $i delay is OK" )
                || diag "command only took $runtime seconds to run, expected at least $step->{ delay }";
        }

        ++$i;
    }

    # Test sequence should now be entirely consumed.
    # Run one more time and verify that it dies.
    my $status;
    my ($stdout, $stderr) = capture {
        $status = system( 'git' );
    };

    ok( ($status >> 8), 'exitcode is non-zero when all steps are consumed' );
    ok( !$stdout,       'no stdout when all steps are consumed' );

    like( $stderr, qr{no more test steps}, 'stderr when all steps are consumed' );

    return;
}

sub run
{
    test_errors( );

    test_basic_success( );

    return;
}

run( ) if (!caller);
1;
