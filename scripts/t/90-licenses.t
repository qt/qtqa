#!/usr/bin/env perl
use v5.10;
use strict;
use warnings;

=head1 NAME

90-licenses.t - selftest for license checker

=head1 DESCRIPTION

This autotest executes the license checker test (tst_licenses.pl)
against various test files and verifies that good/bad license
headers are correctly detected.

The test uses the testdata under the `license-testdata' directory.

=cut

use Capture::Tiny qw(capture_merged);
use Cwd qw(abs_path);
use English qw(-no_match_vars);
use File::Basename;
use File::Copy;
use File::Copy::Recursive qw(dircopy);
use File::Find;
use File::Path;
use File::Spec::Functions;
use File::Slurp qw(read_file);
use File::Temp;
use FindBin;
use Readonly;
use Test::More;
use Text::Diff;
use autodie qw(:default copy);

Readonly my %RE => (
    # Match any lines in the output consisting of a comment, or empty lines.
    insignificant_line => qr{^#[^\n]*\n|^\n}ms,

    # Match the (irrelevant) test numbers
    test_number => qr{(?<=ok )\d+},
);

sub copy_testdata
{
    my (%args) = @_;
    my $destdir = $args{ destdir };
    my $file = $args{ file };

    return unless (-f $file);

    my $dest = "$destdir/$file";

    # $file might have had a dir portion too, so recalculate destdir
    $destdir = dirname($dest);
    if (! -d $destdir) {
        mkpath( $destdir );
    }

    copy( $file, $dest );
    return;
}

sub main
{
    my $tst_licenses = abs_path(
        catfile( $FindBin::Bin, qw(.. .. tests prebuild license tst_licenses.pl) )
    );
    ok( -f($tst_licenses), 'tst_licenses.pl exists' );

    my $testdata = catfile( $FindBin::Bin, 'license-testdata' );
    ok( -d($testdata), 'license-testdata exists' );

    my $expected_output = read_file( catfile( $testdata, 'expected-output.txt' ) );

    my $tempdir = File::Temp->newdir( basename($0)."-XXXXXX", TMPDIR => 1 );
    diag "testing tst_licenses.pl under $tempdir";

    # The module's own directory is underneath $tempdir, and qtbase is a sibling
    my $moduledir = catfile( $tempdir, 'module' );

    # copy $tempdir/qtbase to the reference header directory (used to find header.*)
    dircopy( "$testdata/reference", "$tempdir/qtbase" ) || die "copy header.*: $!";

    chdir $testdata;

    # copy all our testdata into the tempdir;
    # we have to copy it out of a git repository because, if pointed at a git repo,
    # tst_licenses.pl will check the entire repo.
    my @test_dirs = qw(bad good);
    find({
            no_chdir => 1,
            wanted => sub {
                copy_testdata( destdir => $moduledir, file => $File::Find::name )
            },
        }, @test_dirs
    );

    # Now run the test
    my $actual_output = capture_merged {
        local $ENV{ QT_MODULE_TO_TEST } = $moduledir;
        system( $EXECUTABLE_NAME, $tst_licenses );
    };
    # Remove all comments and test numbers before diff
    $actual_output =~ s/$RE{ insignificant_line }//g;
    $actual_output =~ s/$RE{ test_number }/x/g;
    $expected_output =~ s/$RE{ insignificant_line }//g;
    $expected_output =~ s/$RE{ test_number }/x/g;

    my $diff = diff( \$expected_output, \$actual_output );
    if (!ok( !$diff, "tst_licenses.pl output matches expected" )) {
        diag(
            "--- expected output of tst_licenses.pl\n"
           ."+++ actual output of tst_licenses.pl\n"
           .$diff
        );
    }

    done_testing( );
    return;
}

main if (!caller);
1;
