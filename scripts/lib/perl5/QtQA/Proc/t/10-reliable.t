#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec::Functions;
use FindBin;
use Readonly;
use Test::Exception;
use Test::More;

use lib catfile( $FindBin::Bin, qw(..) x 3 );

=head1 NAME

10-reliable.t - basic QtQA::Proc::Reliable test

=head1 DESCRIPTION

This tests basic construction and error cases for QtQA::Proc::Reliable.
The behavior of reliable strategies is tested elsewhere.

=cut

# This must not exist, or the test will fail
Readonly my $NONEXISTENT_STRATEGY
    => 'something_which_does_not_exist';

# This must exist, or the test will fail
Readonly my $EXISTENT_STRATEGY
    => 'git';

BEGIN { use_ok( 'QtQA::Proc::Reliable' ) }

sub run
{
    ###########################################################################
    # Basic checks: no strategies does nothing
    {
        my $proc = QtQA::Proc::Reliable->new();
        ok( !$proc, 'no args means no proc' );

        $proc = QtQA::Proc::Reliable->new( {} );
        ok( !$proc, 'no strategy or command means no proc' );

        $proc = QtQA::Proc::Reliable->new( { reliable => 0 } );
        ok( !$proc, 'reliable => 0 means no proc' );
    }

    ###########################################################################
    # Basic check: auto does nothing for command with no strategy
    {
        my $proc = QtQA::Proc::Reliable->new({
            reliable => 1,
        }, "/usr/bin/$NONEXISTENT_STRATEGY", '--help' );
        ok( !$proc, 'reliable => 1 does nothing when no applicable strategy' );
    }

    ###########################################################################
    # Basic check: selecting nonexistent strategy raises an error
    throws_ok(
        sub {
            QtQA::Proc::Reliable->new({
                reliable => $NONEXISTENT_STRATEGY,
            }, 'ls', '-l' );
        },
        qr/requested strategy `\Q$NONEXISTENT_STRATEGY\E' does not exist/,
        'reliable => nonexistent throws'
    );
    throws_ok(
        sub {
            QtQA::Proc::Reliable->new({
                reliable => [ $EXISTENT_STRATEGY, $NONEXISTENT_STRATEGY ],
            }, 'ls', '-l' );
        },
        qr/requested strategy `\Q$NONEXISTENT_STRATEGY\E' does not exist/,
        'reliable => [ existent, nonexistent ] throws'
    );

    ###########################################################################
    # we can create an object if the strategy exists
    {
        my $proc = QtQA::Proc::Reliable->new({
            reliable => $EXISTENT_STRATEGY,
        }, 'ls', '-l' );
        ok( $proc, 'can create OK with existent strategy' );
    }

    ###########################################################################
    # same if an arrayref is used
    {
        my $proc = QtQA::Proc::Reliable->new({
            reliable => [ $EXISTENT_STRATEGY ],
        }, 'ls', '-l' );
        ok( $proc, 'can create OK with [existent] strategy' );
    }

    ###########################################################################
    # we can create an object with an automatically selected strategy
    {
        my $proc = QtQA::Proc::Reliable->new({
            reliable => 1,
        }, "/usr/bin/$EXISTENT_STRATEGY" );

        ok( $proc, 'can create OK with auto strategy (full path)' );
    }

    ###########################################################################
    # again, with basename only
    {
        my $proc = QtQA::Proc::Reliable->new({
            reliable => 1,
        }, $EXISTENT_STRATEGY );

        ok( $proc, 'can create OK with auto strategy (basename)' );
    }

    # That's all we can test without getting into the implementation detail
    # of the specific strategies.  Those are tested elsewhere.

    done_testing( );

    return;
}

run if (!caller);
1;

