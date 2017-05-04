#!/usr/bin/env perl
#############################################################################
##
## Copyright (C) 2017 The Qt Company Ltd.
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

=head1 NAME

coveragerunner_testcocoon - helper script to run coverage analysis after build (tool used is TestCocoon)

=head1 SYNOPSIS

  # Run code coverage analysis
  $ ./coveragerunner_testcocoon --qtmodule-dir path/to/module --qtmodule-name modulename --qtcoverage-tests_output path/to/output/folder/tests_database.csmes"

  # Example launch script for a qt module (ie qtbase)
  # ./coveragerunner_testcocoon --qtmodule-dir path/to/qtbase --qtmodule-name qtbase --qtcoverage-tests_output "$HOME/qtbase/alltests.csmes"

  # Will generate:
  #
  #   $HOME/qtbase/qtbase-coverage_report-<currentdatetime>.xml
  #   $HOME/qtbase/qtbase-coverage_global-<currentdatetime>.csmes
  #

This script depends on auto tests run with testrunner script. It is designed to integrate with Qt configured
with -testcocoon option and testrunner run with the testcocoon plugin loaded.

Required qtcoverage-tests_output
generated from testrunner. This file is renamed with unique name to avoid overwriting it.

=head1 OPTIONS

=over

=item B<--help>

Print this message.

=item B<--qtmodule-dir> <directory>

Required. Path to Qt5 module to analyze.

=item B<--qtmodule-name> <value>

Required. Name of Qt5 module to analyze.

=item B<--qtcoverage-tests-output> <directory>

Required. Full path to the csmes database gathering tests results.

=back

=cut

use FindBin;
use lib "$FindBin::Bin/../lib/perl5";

package QtQA::App::CoverageRunnerTestCocoon;
use base qw(QtQA::TestScript);

use Carp;
use Getopt::Long qw(GetOptionsFromArray);
use English qw( -no_match_vars );
use File::Basename;
use File::Spec::Functions;
use Pod::Usage qw( pod2usage );
use autodie;

use POSIX qw/strftime/;
use File::Copy;
use File::Find::Rule;

sub new
{
    my ($class) = @_;

    my $self = $class->SUPER::new;
    bless $self, $class;
    return $self;
}

sub run
{
    my ($self, @args) = @_;

    my $qt_gitmodule_dir;
    my $qt_gitmodule;
    my $testcocoon_tests_output;

    GetOptionsFromArray( \@args,
        'help|?'                    =>  sub { pod2usage(1) },
        'qt-gitmodule-dir=s'        =>  \$qt_gitmodule_dir,
        'qt-gitmodule=s'            =>  \$qt_gitmodule,
        'qtcoverage-tests-output=s' =>  \$testcocoon_tests_output,
    ) || pod2usage(2);

    my $currentdatetime = strftime('%Y%m%d-%H%M', localtime);

    if (! -f $testcocoon_tests_output) {
        confess "$testcocoon_tests_output does not exist. Either the tests have not been run or coverage was not enabled at build time";
    }

    my $coverage_dir = dirname($testcocoon_tests_output);

    # Named unique output files
    my $xml_report = $qt_gitmodule . "_coverage_report-" . $currentdatetime . ".xml";
    my $csmes_source = $qt_gitmodule . "_coverage_src-" . $currentdatetime . ".csmes";
    my $csmes_tests = $qt_gitmodule . "_coverage_unittests-" . $currentdatetime . ".csmes";
    my $csmes_global = $qt_gitmodule . "_coverage_global-" . $currentdatetime . ".csmes";

    $xml_report = catfile( $coverage_dir, $xml_report );
    $csmes_source = catfile( $coverage_dir, $csmes_source );
    $csmes_tests = catfile( $coverage_dir, $csmes_tests );
    $csmes_global = catfile( $coverage_dir, $csmes_global );

    # Rename global tests csmes file with unique name
    move($testcocoon_tests_output, $csmes_tests) or confess "move $testcocoon_tests_output: $!";

   my $qt_git_qtbase_dir =
        ($qt_gitmodule eq 'qtbase') ? $qt_gitmodule_dir
        : ($qt_gitmodule eq 'qt5')  ? catfile($qt_gitmodule_dir, 'qtbase')
        :                             catfile($qt_gitmodule_dir, '..', 'qtbase');

    # Get all sources files csmes gathered in a global database (from lib and plugins folder)
    my $qt_git_qtbase_libdir = catfile($qt_git_qtbase_dir, 'lib');
    print "Gather all library files covered in a global database\n";

    my $qt_git_qtbase_pluginsdir = catfile($qt_git_qtbase_dir, 'plugins');
    my $qt_git_qtbase_importsdir = catfile($qt_git_qtbase_dir, 'imports');

    my @allcsmes = File::Find::Rule->file()->name( '*.csmes' )->in($qt_git_qtbase_libdir);
    push @allcsmes, File::Find::Rule->file()->name( '*.csmes' )->in($qt_git_qtbase_pluginsdir);
    push @allcsmes, File::Find::Rule->file()->name( '*.csmes' )->in($qt_git_qtbase_importsdir);
    @allcsmes = map { canonpath($_) } sort(@allcsmes);

    print "List of all source files in coverage\n";

    foreach my $csmes (@allcsmes) {
        print "$csmes\n";
        if (-e $csmes_source) {
            $self->exe('cmmerge',
                       '--append',
                       "--output=$csmes_source",
                       $csmes
            );
        } else {
            copy($csmes, $csmes_source) or confess "copy $csmes: $!";
        }
    }

    print "End of list\n";

    # Create global database
    move($csmes_source, $csmes_global) or confess "move $csmes_source: $!";

    # Merge tests into global
    $self->exe('cmmerge',
               '--append',
               "--output=$csmes_global",
               $csmes_tests
    );

    # Delete the tests csmes to save space.
    unlink($csmes_tests) or confess "unlink $csmes_tests: $!";

    # Generate report
    $self->exe('cmreport',
        "--csmes=$csmes_global",
        "--xml=$xml_report",
        '--select=.*',
        '--source=all',
        '--source-sort=name',
        '--global=all'
    );

    # Compress global csmes to save space
    $self->exe('gzip',
        $csmes_global);

    # Create hmtl reports
    my $xml2html = catfile( $FindBin::Bin, 'xml2html_testcocoon.pl' );
    $xml2html = 'xml2html_testcocoon' if (defined $ENV{ TESTING_COVERAGERUNNER });
    $self->exe($xml2html,
        '--xml',
        $xml_report,
        '--module',
        $qt_gitmodule,
        '--output',
        $coverage_dir,
        '--include',
        catfile($qt_gitmodule_dir, 'src'),
        '--exclude',
        catfile($qt_gitmodule_dir, 'src', '3rdparty')
    );

    return;
}

QtQA::App::CoverageRunnerTestCocoon->new( )->run( @ARGV ) if (!caller);
1;

