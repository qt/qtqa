#!/usr/bin/env perl
use 5.010;
use strict;
use warnings;

=head1 NAME

41-print_calling_makefile.t - basic test for print_calling_makefile.pl

=cut

use File::Spec::Functions;
use Capture::Tiny qw(capture_merged);
use English qw(-no_match_vars);
use File::chdir;
use FindBin;
use Readonly;
use Test::More;

Readonly my $TESTDATA_DIR => catfile( $FindBin::Bin, qw(data print-calling-makefile) );

# Tests that the given command (arrayref), when run, outputs $expected_output (chomped).
# Returns 1 iff the exit code of the command is 0.
sub test_cmd
{
    my ($cmd_ref, $expected_output) = @_;

    my $status;
    my $output = capture_merged {
        $status = system( @{$cmd_ref} );
    };

    chomp $output;

    local $LIST_SEPARATOR = '] [';
    is( $output, $expected_output, "output for [@{$cmd_ref}] looks OK" );

    return ($status == 0);
}

sub run
{
    my $should_skip = 1;
    if ($OSNAME =~ m{win32}i) {
        # Skip this test case also on Windows if nmake is not in path
        $should_skip = system( 'where', "/Q", "nmake" );
    }
    plan 'skip_all', "This test is relevant only on Win32 and nmake" if ($should_skip != 0);


    local $CWD = $TESTDATA_DIR;

    for my $makefile ('basic-makefile', 'makefile with spaces') {
        ok( test_cmd( [qw(nmake -C -S -F), $makefile], $makefile ) );
        ok( test_cmd( [qw(nmake -C -S /F), $makefile], $makefile ) );
        ok( test_cmd( [qw(nmake -C -S -f), $makefile], $makefile ) );
        ok( test_cmd( [qw(nmake -C -S /f), $makefile], $makefile ) );
        ok( test_cmd( [qw(nmake -C -S), "-F$makefile"], $makefile ) );
        ok( test_cmd( [qw(nmake -C -S), "/F$makefile"], $makefile ) );
        ok( test_cmd( [qw(nmake -C -S), "-f$makefile"], $makefile ) );
        ok( test_cmd( [qw(nmake -C -S), "/f$makefile"], $makefile ) );
    }

    done_testing;

    return;
}

run if (!caller);
1;

