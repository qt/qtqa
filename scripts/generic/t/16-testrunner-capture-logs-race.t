#!/usr/bin/env perl
use 5.010;
use strict;
use warnings;

=head1 NAME

16-testrunner-capture-logs-race.t - test for one specific race condition

=cut

use English qw( -no_match_vars );
use File::Temp qw( tempdir );
use FindBin;
use Getopt::Long;
use Readonly;
use Test::More;

Readonly my $WINDOWS => ($OSNAME =~ m{mswin32}i);

# Directory containing some helper scripts
# Testrunner script
Readonly my @TESTRUNNER => (
    $EXECUTABLE_NAME,
    "$FindBin::Bin/../testrunner.pl",
);

# Like system(), but returns the pid and runs in the background
sub spawn
{
    my (@cmd) = @_;

    if ($WINDOWS) {
        # avoid fork() on Windows - see 'perldoc perlport'
        return system(1, @cmd);
    }

    my $pid = fork();
    if ($pid == 0) {
        exec( @cmd );
        die "exec: $!";
    } elsif ($pid < 0) {
        die "fork: $!"
    }

    return $pid
}

# main entry point
sub run
{
    my $debug;

    GetOptions(
        'debug' => \$debug,
    ) || die;

    my $tempdir = tempdir( 'qtqa-test-capture-logs.XXXXXX', TMPDIR => 1, CLEANUP => !$debug );
    if ($debug) {
        diag( "Using $tempdir as temporary directory" );
    }

    # check precondition
    my @globbed = glob( "$tempdir/*" );
    ok( @globbed == 0, "$tempdir is empty" )
        || diag "globbed: @globbed";

    # The test is: if we run multiple testrunners in parallel with --capture-logs, do they all
    # get unique output files or do some of them clobber each other?
    # Note: this is also testing concurrent creation of the "logdir" directory.
    my $MAX = 50;
    my @cmd = (@TESTRUNNER, '--capture-logs', "$tempdir/logdir", '--', $EXECUTABLE_NAME, '--version');
    my @pids = map { spawn(@cmd) } (1..$MAX);
    while (my $next = shift @pids) {
        if (waitpid( $next, 0 ) != $next) {
            die "waitpid $next: $!";
        }
    }

    # There should now be exactly $MAX files in the log directory, one per process.
    @globbed = glob( "$tempdir/logdir/*" );
    ok( @globbed == $MAX, 'one log file per process' )
        || diag "globbed: @globbed";

    done_testing( );

    return;
}

run if (!caller);
1;
