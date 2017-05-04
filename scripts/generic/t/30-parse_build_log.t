#!/usr/bin/env perl
#############################################################################
##
## Copyright (C) 2017 The Qt Company Ltd and/or its subsidiary(-ies).
## Contact: https://www.qt.io/licensing/
##
## This file is part of the Quality Assurance module of the Qt Toolkit.
##
## $QT_BEGIN_LICENSE:GPL-EXCEPT$
## Commercial License Usage
## Licensees holding valid commercial Qt licenses may use this file in
## accordance with the commercial license agreement provided with the
## Software or, alternatively, in accordance with the terms contained in
## a written agreement between you and The Qt Company. For licensing terms
## and conditions see https://www.qt.io/terms-conditions. For further
## information use the contact form at https://www.qt.io/contact-us.
##
## GNU General Public License Usage
## Alternatively, this file may be used under the terms of the GNU
## General Public License version 3 as published by the Free Software
## Foundation with exceptions as appearing in the file LICENSE.GPL3-EXCEPT
## included in the packaging of this file. Please review the following
## information to ensure the GNU General Public License requirements will
## be met: https://www.gnu.org/licenses/gpl-3.0.html.
##
## $QT_END_LICENSE$
##
#############################################################################
use 5.010;
use strict;
use warnings;
use utf8;

=head1 NAME

30-parse_build_log.t - various tests for parse_build_log.pl

=head1 SYNOPSIS

  perl ./30-parse_build_log.t [pattern1 [pattern2 ...]]

Runs parse_build_log over all the testdata under the `data' directory.

If any patterns are given, only logs with filenames matching those patterns
(regular expressions) will be tested.

  perl ./30-parse_build_log.t --update

Runs the test as usual, and updates the testdata such that the test
passes.  Use this with care for mass updating of multiple testdata.

=cut

use Getopt::Long qw( GetOptionsFromArray );
use Capture::Tiny qw( capture );
use English qw( -no_match_vars );
use File::Basename;
use File::Slurp;
use File::Spec::Functions;
use FindBin;
use List::MoreUtils qw( none );
use Readonly;
use Test::More;
use Text::Diff;
use autodie;

Readonly my $DATADIR
    => catfile( $FindBin::Bin, 'data' );

Readonly my $PARSE_BUILD_LOG
    => catfile( $FindBin::Bin, '..', 'parse_build_log.pl' );

sub test_from_file
{
    my ($file, $update) = @_;

    my $testname = basename( $file );

    my @expected_lines = read_file( $file );

    # first line is special, it's the arguments to pass to parse_build_log;
    # the rest is the expected output of parse_build_log
    my $args_perl = shift @expected_lines;

    my $args_ref = eval $args_perl; ## no critic
    if ($EVAL_ERROR) {
        die "internal error: while eval'ing first line of $file, `$args_perl': $EVAL_ERROR";
    }
    if (ref($args_ref) ne 'ARRAY') {
        die "internal error: first line of $file, `$args_perl', did not eval to an arrayref";
    }

    my @command = ( $EXECUTABLE_NAME, $PARSE_BUILD_LOG, @{$args_ref} );

    my $status = -1;
    my ($stdout, $stderr) = capture {
        $status = system( @command );
    };

    # Basic checks that the command succeeded and didn't print any warnings

    is( $status, 0, "$testname - exit code 0" )
        || diag("stdout:\n$stdout\nstderr:\n$stderr");

    is( $stderr, q{}, "$testname - no standard error" );


    # Now check if the output was really what we expected.
    # To get the nicest looking failure messages, we use `diff', so the failure message
    # contains exactly the difference between what we wanted and what we got.
    my $diff = diff(
        \@expected_lines,
        \$stdout,
        {
            STYLE       =>  'Unified',
            FILENAME_A  =>  'expected',
            FILENAME_B  =>  'actual',
        },
    );

    # Normal mode: just test.
    if (!$update) {
        ok( !$diff, "$testname - actual matches expected" )
            || diag( $diff );

        return;
    }

    # Update mode: update the testdata if necessary.
    my $message = "$testname - actual matches expected";

    if ($diff) {
        open( my $fh, '>', $file );
        print $fh $args_perl.$stdout;
        close( $fh );
        $message .= " - UPDATED!";
    }

    pass( $message );

    return;
}

sub run
{
    my (@args) = @_;

    my $update;
    GetOptionsFromArray( \@args,
        update  =>  \$update,
    ) || die $!;

    foreach my $file (glob "$DATADIR/parsed-logs/*") {
        # README.txt is not testdata; treat all other files as testdata
        next if ( basename( $file ) eq 'README.txt' );
        next if ( ! -f $file );
        next if (@args && none { $file =~ qr{$_} } @args);

        test_from_file( $file, $update );
    }

    done_testing;

    return;
}

run( @ARGV ) if (!caller);
1;

