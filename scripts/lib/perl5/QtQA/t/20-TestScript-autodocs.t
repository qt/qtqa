#!/usr/bin/env perl
use strict;
use warnings;

=head1 NAME

20-TestScript-autodocs - test QtQA::TestScript module `usage' feature

=head1 SYNOPSIS

This autotest attempts to verify the automatic generation of script
documentation via print_usage, POD, --help.

It uses (.pl, .txt) pairs of files in the autodocs-data directory as
testdata.  Each .pl file is invoked with `--help', and the generated
output is compared against the content of the .txt file.

=cut

use FindBin;
use lib "$FindBin::Bin/../..";

use Test::More;

use File::Basename    qw( basename );
use IO::CaptureOutput qw( qxy      );
use Text::Diff        qw( diff     );

#==============================================================================

sub test_script_against_expected
{
    my ($script_filename, $usage_filename) = @_;

    my $testname = basename($script_filename);

    my ($combined, $success) = qxy('perl', $script_filename, '--help');

    # using `--help' implies non-zero exit
    ok( !$success, "$testname exited with non-zero exit code" );

    my $diff = diff( $usage_filename, \$combined, {
        STYLE       =>  'Unified',
        FILENAME_A  =>  $usage_filename,
        FILENAME_B  =>  "output of `$testname --help'",
    });

    ok( !$diff, "$testname output looks OK" )
        || diag("Output not as expected:\n$diff");

    return;
}

sub run_test
{
    foreach my $script_filename (glob "$FindBin::Bin/autodocs-data/*.pl") {
        my $usage_filename = $script_filename;
        $usage_filename =~ s{\.pl \z}{.txt}xms;

        test_script_against_expected($script_filename, $usage_filename);
    }

    return;
}

#==============================================================================

if (!caller) {
    run_test;
    done_testing;
}
1;
