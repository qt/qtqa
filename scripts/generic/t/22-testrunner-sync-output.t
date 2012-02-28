#!/usr/bin/env perl
use 5.010;
use strict;
use warnings;

=head1 NAME

22-testrunner-sync-output.t - test testrunner's --sync-output option

=head1 SYNOPSIS

  perl ./22-testrunner-sync-output.t

This test will run the testrunner.pl script with and without sync-output
and verify the order in which subprocess output is printed.

=cut

use File::Spec::Functions;
use FindBin;
use Readonly;
use Test::More;
use Data::Dumper;
use English qw( -no_match_vars );

# Testrunner script
Readonly my $TESTRUNNER => catfile( $FindBin::Bin, '..', 'testrunner.pl' );

# This script
Readonly my $THIS_SCRIPT => catfile( $FindBin::Bin, $FindBin::Script );

# Test output of concurrent processes with no syncing
sub test_concurrent_unsynced
{
    # Run 4 async delayed-output through testrunner with no attempt to sync output
    my $cmd_unsynced = qq{"$EXECUTABLE_NAME" "$THIS_SCRIPT" -run-children};

    # With no --sync-output, verify the output is interleaved
    my $out_unsynced = qx( $cmd_unsynced 2>&1 );
    is( $out_unsynced, <<'END_OUT', 'output is interleaved by default' );
Line 1
Line 1
Line 1
Line 1
Line 2
Line 2
Line 2
Line 2
Line 3
Line 3
Line 3
Line 3
All children done.
END_OUT

    return;
}

# Test output of concurrent processes with syncing
sub test_concurrent_synced
{
    # Run 4 async delayed-output through testrunner and sync output
    my $cmd_synced = qq{"$EXECUTABLE_NAME" "$THIS_SCRIPT" -run-children --sync-output};

    # With --sync-output, verify the output is NOT interleaved
    my $out_synced = qx( $cmd_synced 2>&1 );
    is( $out_synced, <<'END_OUT', 'output with --sync-output is not interleaved' );
Line 1
Line 2
Line 3
Line 1
Line 2
Line 3
Line 1
Line 2
Line 3
Line 1
Line 2
Line 3
All children done.
END_OUT

    return;
}

sub main
{
    test_concurrent_unsynced;
    test_concurrent_synced;

    done_testing;
    return;
}

# Spawn a few concurrent delayed-output processes through testrunner.
# Anything in @ARGV is passed to the testrunner.
sub run_children
{
    my @pids;
    for my $i (1..4) {
        my $pid = fork();
        if (0 == $pid) {
            exec($EXECUTABLE_NAME, $TESTRUNNER, @ARGV, '--',
                 $EXECUTABLE_NAME, $THIS_SCRIPT, '-delayed-output');
            die "exec failed: $!";
        }
        else {
            push @pids, $pid;
        }
    }
    while (@pids) {
        shift @pids;
        waitpid(-1, 0);
    }
    print "All children done.\n";
    return;
}

# Write a few lines with a sleep between them
sub delayed_output
{
    local $| = 1;   # flushed output
    for my $i (1..3) {
        sleep 1;
        if ($i == 2) {
            print STDERR "Line $i\n";
        }
        else {
            print "Line $i\n";
        }
    }
    return;
}

if (my $cmd = shift @ARGV) {
    if ($cmd eq '-run-children') {
        run_children;
    }
    elsif ($cmd eq '-delayed-output') {
        delayed_output;
    }
    else {
        die "Unexpected argument `$cmd'";
    }
}
else {
    main;
}
