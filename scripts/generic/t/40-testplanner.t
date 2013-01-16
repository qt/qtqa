#!/usr/bin/env perl
use 5.010;
use strict;
use warnings;

=head1 NAME

40-testplanner.t - basic test for testplanner.pl

=cut

use English qw(-no_match_vars);
use File::Spec::Functions;
use File::Temp;
use File::chdir;
use FindBin;
use Readonly;
use ReleaseAction qw(on_release);
use Test::More;
use Text::Diff;

use lib "$FindBin::Bin/../../lib/perl5";
use QtQA::Test::More qw(find_qmake);

Readonly my $TESTPLANNER => catfile( $FindBin::Bin, qw(.. testplanner.pl) );

Readonly my $TESTDATA_DIR => catfile( $FindBin::Bin, qw(data test-projects) );

Readonly my $QMAKE => find_qmake( );

sub test_testplanner_on_testdata
{
    my $testplan = File::Temp->new(
        TEMPLATE => 'qtqa-testplan-XXXXXX',
        TMPDIR => 1,
    );
    $testplan = "$testplan";
    my $cleanup = on_release { unlink $testplan };

    # Put some garbage in environment variables relating to "make check", to ensure
    # that this does _not_ affect the behavior
    local $ENV{ TESTRUNNER } = 'some testrunner';
    local $ENV{ TESTARGS } = 'some testargs';

    my @cmd = (
        $EXECUTABLE_NAME,
        $TESTPLANNER,
        '--input',
        $TESTDATA_DIR,
        '--output',
        "$testplan",
    );

    if ($OSNAME =~ m{win32}i) {
        if (!system( 'where', "/Q", "nmake" )) {
            push @cmd, (
                '--make',
                'nmake',
            );
        } elsif (!system( 'where', "/Q", "mingw32-make" )) {
            push @cmd, (
                '--make',
                'mingw32-make',
            );
        } # else - use default
    } # else - use default

    my $status = system( @cmd );
    is( $status, 0, 'testplanner exit code OK' );

    # Note we must open a new fh to the testplan file, since the testplanner
    # script overwrote it.
    my @lines;
    my $fh = IO::File->new( "$testplan", '<' ) || die "open $testplan for read: $!";

    # We need to replace the testdata dir with a %TESTDATA_DIR% macro, to avoid having
    # untestable full paths in the testdata.
    # We allow both unix style and platform native style paths.
    my $canon_testdata_dir = canonpath $TESTDATA_DIR;
    # Paths will be quoted with qq in the testplan, so \ becomes \\
    $canon_testdata_dir =~ s{\\}{\\\\}g;
    while (my $line = <$fh>) {
        $line =~ s{\Q$TESTDATA_DIR\E}{%TESTDATA_DIR%}g;
        $line =~ s{\Q$canon_testdata_dir\E}{%TESTDATA_DIR%}g;
        push @lines, $line;
    }

    # The order of output from testplanner is undefined.
    # We sort the lines for a stable comparison.
    @lines = sort @lines;

    my $expected = "$TESTDATA_DIR/expected_testplan";
    if ($OSNAME =~ m{win32}i) {
        $expected .= '_win32';
    }
    $expected .= '.txt';

    my $diff = diff( \@lines, $expected );
    ok( !$diff, 'testplanner output as expected' )
        || diag( "diff between actual and expected:\n$diff" );

    return;
}

sub run
{
    if (!$QMAKE) {
        plan skip_all => 'no qmake available for testing';
    }

    # qmake the testdata before doing anything else.
    {
        local $CWD = $TESTDATA_DIR;
        my $status = system( $QMAKE );
        is( $status, 0, 'qmake ran OK' );
    }

    test_testplanner_on_testdata;
    done_testing;

    return;
}

run if (!caller);
1;

