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

=head1 NAME

xml2html_testcocoon - convert a xml coverage report created by testcocoon to structured html reports.

=head1 SYNOPSIS

  # Run command
  $ ./xml2html_testcocoon.pl --xml "path/to/file.xml" --module "modulename" --output "path/to/output" --include "path/to/include" [options]

  # Example
  $ ./xml2html_testcocoon.pl --xml "$HOME/qtbase_coverage_report-20111125-2354.xml" --module qtbase --output "$HOME/coverage/results" --include "$HOME/git/base/qt/qtbase/src" --exclude "$HOME/git/base/qt/qtbase/src/3rdparty"

  # Will generate:
  #
  #   $HOME/coverage/results/qtbase_report.html
  #   $HOME/coverage/results/files/tests_<status>_qtbase.html
  #   $HOME/coverage/results/files/folder_<subfolders>_qtbase.html
  #   $HOME/coverage/results/files/untested_sources_qtbase.html
  #

  It is designed to parse a coverage xml report generated for Qt modules build with testcocoon and create html reports.

=head1 OPTIONS

=over

=item B<--help>

Print this message.

=item B<--xml> <file>

Required. Full path to xml file to analyze.

=item B<--module> <value>

Required. Name of the Qt5 module to analyze.

=item B<--output> <directory>

Required. Path to the output directory (will be created if needed).

=item B<--include> <path>

Required. Set the full path to a folder or a file to include for the code coverage calculus.

=item B<--exclude> <path>

Option. Set the full path to a folder or a file to exclude for the code coverage calculus.
Can have multiple --exclude options. Exclusions are processed after the inclusion.

=back

=cut

use FindBin;
use lib "$FindBin::Bin/../lib/perl5";

package QtQA::App::Xml2HtmlTestCocoon;

use strict;
use warnings;

use autodie;
use Carp;
use File::Basename qw(basename);
use File::Find::Rule;
use File::Path qw( mkpath );
use File::Spec::Functions;
use Getopt::Long qw(GetOptionsFromArray);
use List::Compare;
use Pod::Usage qw( pod2usage );
use XML::Simple;

sub new
{
    my $class = shift;
    my $self = bless {}, $class;
    return $self;
}

sub run
{
    my ($self, @args) = @_;

    my $xml_file;
    my $module_name;
    my $output_dir;
    my $include_path;
    my @exclude_list;

    GetOptionsFromArray( \@args,
        'help|?'          =>  sub { pod2usage(1) },
        'xml=s'           =>  \$xml_file,
        'module=s'        =>  \$module_name,
        'output=s'        =>  \$output_dir,
        'include=s'       =>  \$include_path,
        'exclude=s'       =>  \@exclude_list,
    ) || pod2usage(2);

    if (!$xml_file || ! -e $xml_file) {
        confess "Missing or invalid required '--xml' option";
    }

    if (!$module_name) {
        confess "Missing required '--module' option";
    }

    if (!$output_dir) {
        confess "Missing required '--output' option";
    }

    my $files_output_subfolder = 'files';
    my $output_files = catfile($output_dir, $files_output_subfolder);

    if (! -d $output_dir && ! mkpath( $output_dir )) {
        confess "mkpath $output_dir: $!";
    }
    if (! -d "$output_files" && ! mkpath( $output_files )) {
        confess "mkpath $output_files: $!";
    }

    if (!$include_path) {
        confess "Missing required '--include' option";
    }

    my $include_path_regex = quotemeta($include_path);

    # get file timestamp
    my $timestamp = "n/a";
    if ( $xml_file =~ m#([0-9]{8}-[0-9]{4})#) {
        $timestamp = $1;
    }

    my $year = substr($timestamp,0,4);
    my $month = substr($timestamp,4,2);
    my $day = substr($timestamp,6,2);
    my $hour = substr($timestamp,9,2);
    my $minute = substr($timestamp,11,2);

    my $separator = '[\\/\\\]';

    my $topFolder_mask = $separator . '.*';
    my $tested_mask = '/.*';
    my $total_mask = '.*/';

    # create object
    my $xml = XML::Simple->new;

    # read XML file
    my $data = $xml->XMLin($xml_file);

    my $sources = $data->{SourcesStatistics}->{Item};
    my $tests = $data->{ExecutionList}->{ExecutionListItem};

    my %hash_folders;

    # Get all the source files under the included directory
    my @files_in_tree_all = File::Find::Rule->file()->name( '*.c', '*.cpp' )->in($include_path);
    my @files_in_tree;
    foreach my $file (@files_in_tree_all) {
        next if ($self->isExcluded($file, @exclude_list));
        next if ($file =~ m/(^|[\/\\])(qrc|moc)_.*\.cpp$/);
        $file = canonpath($file);
        push @files_in_tree, $file;
    }

    my @files_tested;

    foreach my $item (@{$sources}) {
        my $file_name = $item->{ItemSource};
        next unless ($file_name =~ m/$include_path_regex/);
        push @files_tested, $file_name;
        next if ($self->isExcluded($file_name, @exclude_list));

        # Get the relative path of the current file to include under the $include path entered
        my $subfolder_is_file = 0;
        if ( $file_name eq $include_path ) {
            $file_name = basename($include_path);
            $subfolder_is_file = 1;
        } else {
            $file_name =~ s/${include_path_regex}${separator}{0,1}//;
        }

        my $subfolder = $file_name;

        # Figure out the subfolder name under the $include path entered that contains the file.
        # If the file is directly under the $include path, its name is used as a subfolder name.
        # Those subfolder names are used to create the tree structure of the main html report.
        $subfolder =~ s/${topFolder_mask}// if (!$subfolder_is_file);

        my $coverage_ratio = $item->{ItemStatistic}->{ItemStatisticValue};
        my $tested = $coverage_ratio;
        $tested =~ s/${tested_mask}//;
        my $total = $coverage_ratio;
        $total =~ s/${total_mask}//;

        push @{$hash_folders{$subfolder}}, { filename => $file_name, tested => $tested, total => $total };
    }

    my $lc = List::Compare->new(\@files_in_tree, \@files_tested);
    my @untested_sources = $lc->get_unique;
    my $untested_sources_html = $self->write_untested_sources($output_files, $module_name, @untested_sources);
    my $untested_sources_count = scalar(@untested_sources);

    my %passed_tests;
    my %failed_tests;
    my %unknown_tests;
    my %unknown_saved_tests;

    foreach my $test (@{$tests}) {
        my $test_name = lc($test->{ExecutionListName});
        if ( defined $test->{ExecutionListStatusPassed} ) {
            $passed_tests{$test_name} = 1;
        } elsif ( defined $test->{ExecutionListStatusFailed} ) {
            $failed_tests{$test_name} = 1;
        } else { #unknown
            if ( $test_name =~ m/^tc_/ ) {
                $test_name =~ s/^tc_//;
                $unknown_tests{$test_name} = 1;
            } else {
                $unknown_saved_tests{$test_name} = 1;
            }
        }
    }

    # Identify tests with valid unknown status
    foreach my $test (keys %unknown_tests) {
        if (!$passed_tests{$test} && !$failed_tests{$test} && !$unknown_saved_tests{$test}) {
            $unknown_saved_tests{$test} = 1;
        }
    }

    # Sort tests
    my @passed_tests = sort keys %passed_tests;
    my @failed_tests = sort keys %failed_tests;
    my @unknown_saved_tests = sort keys %unknown_saved_tests;

    my $nb_failed_tests = @failed_tests;
    my $nb_passed_tests = @passed_tests;
    my $nb_unknown_saved_tests = @unknown_saved_tests;
    my $nb_total_tests = $nb_failed_tests + $nb_passed_tests + $nb_unknown_saved_tests;

    # Write a html report for each tests status and report tests count in main html
    my $passed_html = '';
    if ($nb_passed_tests > 0) {
        $passed_html = $self->write_tests_html(\@passed_tests, 'passed', $output_files, $module_name);
    }
    my $failed_html = '';
    if ($nb_failed_tests > 0) {
        $failed_html= $self->write_tests_html(\@failed_tests, 'failed', $output_files, $module_name);
    }
    my $unknown_saved_html = '';
    if ($nb_unknown_saved_tests > 0) {
        $unknown_saved_html = $self->write_tests_html(\@unknown_saved_tests, 'unknown', $output_files, $module_name);
    }

    # Create a main html report for a module that reports tests counts and subfolders/global coverage results.
    my $main_html = catfile($output_dir, "${module_name}_report.html");

    open(my $MAIN, '>', $main_html);
    $self->write_start_html_file($MAIN);
    $self->write_title_element($MAIN, "Conditions coverage results for: $module_name");
    $self->write_header2_element($MAIN, "Included directory:<br /><ul><li>$include_path</li></ul>" . $self->create_exclude_elements(@exclude_list) . "<br />Date: $day/$month/$year - $hour:$minute");
    $self->write_header2_element($MAIN, "Source files (.c and .cpp) found under the included directory but not tested by the coverage analysis: " . $self->create_element_with_link($untested_sources_html, $untested_sources_count));
    $self->write_tests_status_global($MAIN, $nb_total_tests, $self->create_element_with_link($passed_html, $nb_passed_tests), $self->create_element_with_link($failed_html, $nb_failed_tests), $self->create_element_with_link($unknown_saved_html, $nb_unknown_saved_tests) );
    $self->write_start_table_folders($MAIN);
    close($MAIN);

    my $global_tested = 0;
    my $global_total = 0;

    # Write a html report for each subfolder
    foreach my $subfolder (sort keys %hash_folders) {
        my $tested = 0;
        my $total = 0;
        my $folder_link = '';
        my @list_files = @{$hash_folders{$subfolder}};
        if (@list_files == 1 ) {
            # If only 1 file is found, no need for a dedicated html report
            $subfolder = $list_files[0]->{filename};
            $tested += $list_files[0]->{tested};
            $total += $list_files[0]->{total};
        } else {
            my $folder_html = catfile($output_files, "/folder_${subfolder}_${module_name}.html");
            open(my $FOLDER, '>', $folder_html);
            my $folder_data = $self->write_folder_html($FOLDER, $hash_folders{$subfolder}, $subfolder, $include_path);
            close($FOLDER);

            $folder_link = $files_output_subfolder . '/' . basename($folder_html);
            $tested = $folder_data->{folder_tested};
            $total = $folder_data->{folder_total};
        }
        open($MAIN, '>>', $main_html);
        $self->write_folder_element($MAIN, $self->create_element_with_link($folder_link, $subfolder), $tested, $total);
        close($MAIN);

        $global_tested += $tested;
        $global_total += $total;
    }

    open($MAIN, '>>', $main_html); ## no critic
    $self->write_folder_element($MAIN, '<p class="global">GLOBAL</p>', $global_tested, $global_total);
    $self->write_end_table($MAIN);
    $self->write_end_html_file($MAIN);
    close($MAIN);
    return;
}

sub isExcluded
{
   my ($self, $file, @list_excluded) = @_;
   foreach my $exclude ( @list_excluded ) {
       return 1 if ($file =~ m/$exclude/);
   }
   return 0;
}

# Function to calculate coverage value
sub calculate_coverage
{
    my ($self, $tested, $total) = @_;
    my $coverage_rounded = 'n/a';
    if ( $total != 0 ) {
        my $coverage_value = $tested / $total * 100;
        $coverage_rounded = sprintf('%.2f', $coverage_value);
    }

    return $coverage_rounded;
}

sub write_start_html_file
{
    my ($self, $FILE) = @_;
    print $FILE <<ENDHTML;
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0//EN" "http://www.w3.org/TR/REC-html40/strict.dtd">
<html><head><meta http-equiv="Content-Type" content="text/html; charset=UTF-8" /><style type="text/css">
p, li { white-space: pre-wrap; } body { color: black; } .global { color: red; }
</style></head><body style=" font-family:'Helvetica'; font-size:12pt; font-weight:400; font-style:normal;">
ENDHTML
    return;
}

sub write_end_html_file
{
    my ($self, $FILE) = @_;
    print $FILE "</body>\n</HTML>\n";
    return;
}

sub write_title_element
{
    my ($self, $FILE, $title) = @_;
    print $FILE <<ENDHTML;
<h1>$title</h1>
ENDHTML
    return;
}

sub write_header2_element
{
    my ($self, $FILE, $text) = @_;
    print $FILE <<ENDHTML;
<h2>$text</h2>
ENDHTML
    return;
}

sub write_start_table_folders
{
    my ($self, $FILE) = @_;
    print $FILE <<ENDHTML;
<table border="1" cellspacing="2">
    <TR class="SourceFolderHeader">
        <TD class="SourceFolderFileName">Filename</TD>
        <TD class="SourceFolderTested">Tested Statements</TD>
        <TD class="SourceFolderTotal">Total Statements</TD>
        <TD class="SourceFolderCoverage">Coverage</TD>
    </TR>
ENDHTML
    return;
}

sub write_start_table_tests
{
    my ($self, $FILE) = @_;
    print $FILE <<ENDHTML;
<table border="1" cellspacing="2">
    <TR class="TestsHeader">
        <TD class="TestName">Test Name</TD>
        <TD class="TestStatus">Tested Test Status</TD>
    </TR>
ENDHTML
    return;
}

sub write_end_table
{
    my ($self, $FILE) = @_;

    print $FILE "</table>\n";
    return;
}

# Subroutine to write a html report for all files found in a given subfolder
sub write_folder_html
{
    my ($self, $FILE, $data, $key, $include) = @_;
    $self->write_start_html_file($FILE);
    $self->write_title_element($FILE, "Conditions coverage results for \"$key\" under <br />$include");
    $self->write_start_table_folders($FILE);

    my $folder_tested = 0;
    my $folder_total = 0;
    foreach my $file ( @{$data} ) {
        $self->write_folder_element($FILE, $file->{filename}, $file->{tested}, $file->{total});
        $folder_tested += $file->{tested};
        $folder_total += $file->{total};
    }

    $self->write_folder_element($FILE, '<p class="global">GLOBAL</p>', $folder_tested, $folder_total);
    $self->write_end_table($FILE);
    $self->write_end_html_file($FILE);

    return { folder_tested => $folder_tested, folder_total => $folder_total};
}

sub write_folder_element
{
    my ($self, $FILE, $filename, $tested, $total) = @_;
    my $coverage = $self->calculate_coverage($tested, $total);
    print $FILE <<ENDHTML;
    <TR class="SourceFolderHeader">
        <TD class="SourceFolderFileName">$filename</TD>
        <TD class="SourceFolderTested">$tested</TD>
        <TD class="SourceFolderTotal">$total</TD>
        <TD class="SourceFolderCoverage">$coverage</TD>
    </TR>
ENDHTML
    return;
}

# Subroutine to write a html report for all tests with the same status
sub write_tests_html
{
    my ($self, $tests, $status, $output_dir, $module_name ) = @_;
    my $html = '';
    my $number_of_tests = @{$tests};

    return $html unless $number_of_tests;

    $html = catfile($output_dir, "tests_${module_name}_$status.html");
    open(my $FILE, '>', $html);
    $self->write_start_html_file($FILE);
    $self->write_title_element($FILE, "lists of tests with status $status for module $module_name");
    $self->write_start_table_tests($FILE);
    foreach my $test (@{$tests}) {
         $self->write_tests_element($FILE, $test, $status);
    }
    $self->write_end_table($FILE);
    $self->write_end_html_file($FILE);
    close($FILE);
    $html = basename($output_dir) . '/'. basename($html);

    return $html;
}

# Subroutine to write one test status in the test html report
sub write_tests_status_global
{
    my ($self, $FILE, $total, $passed, $failed, $unknown ) = @_;
    print $FILE <<ENDHTML;
<table border="1" cellspacing="2">
    <TR class="TestsHeader">
        <TD class="TotalTests">Numbers of tests run</TD>
        <TD class="PassedTests">Passed</TD>
        <TD class="FailedTests">Failed</TD>
ENDHTML
    if ( defined $unknown ) {
        print $FILE "<TD class=\"UnknownTests\">Unknown</TD>\n";
    }
    print $FILE <<ENDHTML;
    </TR>
    <TR class="Tests">
        <TD class="TotalTests">$total</TD>
        <TD class="PassedTests">$passed</TD>
        <TD class="FailedTests">$failed</TD>
ENDHTML
    if ( defined $unknown ) {
        print $FILE "<TD class=\"UnknownTests\">$unknown</TD>\n";
    }
    print $FILE "</TR>\n</table>\n";

    return;
}

sub write_tests_element
{
    my ($self, $FILE, $testname, $status) = @_;
    print $FILE <<ENDHTML;
    <TR class="TestsHeader">
        <TD class="TestName">$testname</TD>
        <TD class="TestStatus">$status</TD>
    </TR>
ENDHTML
    return;
}

sub create_element_with_link
{
    my ($self, $link, $text) = @_;
    return $text unless ($link);
    my $pre_link = '';
    my $post_link = '';
    if ($link) {
        $pre_link = "<a href=\"$link\">";
        $post_link = '</a>';
    }
    return $pre_link . $text . $post_link;
}

sub create_exclude_elements
{
    my ($self, @exclude_list) = @_;
    my $elements = '';
    return $elements unless (@exclude_list);
    $elements = "\nExcluding: <ul>";
    foreach my $exclude (@exclude_list) {
        $elements .= "<li>$exclude</li>";
    }
    $elements .= '</ul>';
    return $elements;
}

sub write_start_table_untested_sources
{
    my ($self, $FILE) = @_;
    print $FILE <<ENDHTML;
<table border="1" cellspacing="2">
    <TR class="UntestedSourceHeader">
        <TD class="UntestedSourceFileName">Filename</TD>
    </TR>
ENDHTML
    return;
}

sub write_untested_sources_element
{
    my ($self, $FILE, $filename) = @_;
    print $FILE <<ENDHTML;
    <TR class="UntestedSourceHeader">
        <TD class="UntestedSourceFileName">$filename</TD>
    </TR>
ENDHTML
    return;
}

sub write_untested_sources
{
    my ($self, $output_dir, $module_name, @untested_sources) = @_;
    my $html = '';
    return $html unless @untested_sources;


    $html = catfile($output_dir, "untested_sources_${module_name}.html");
    open(my $UNTESTED, '>', $html);
    $self->write_start_html_file($UNTESTED);
    $self->write_title_element($UNTESTED, 'Source files not covered by the coverage analysis<br />Generated files (moc_*.cpp and qrc_*.cpp) and files found under the exclude paths don\'t appear in this report');
    $self->write_start_table_untested_sources($UNTESTED);
    foreach my $filename ( @untested_sources ) {
        $self->write_untested_sources_element($UNTESTED, $filename);
    }
    $self->write_end_table($UNTESTED);
    $self->write_end_html_file($UNTESTED);
    close($UNTESTED);
    $html = basename($output_dir) . '/' . basename($html);
    return $html;
}

QtQA::App::Xml2HtmlTestCocoon->new()->run( @ARGV ) if (!caller);
1;
