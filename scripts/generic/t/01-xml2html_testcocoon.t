#!/usr/bin/env perl
use 5.010;
use strict;
use warnings;
use utf8;
use Readonly;

use File::Basename qw(basename);

=head1 NAME

01-xml2html_testcocoon.t - basic tests for xml2html_testcocoon.pl

=head1 SYNOPSIS

  perl ./01-xml2html_testcocoon.t

This test will run the xml2html_testcocoon.pl script with a few different
inputs and verify that behavior is as expected.

=cut

use Encode;
use English qw( -no_match_vars );
use FindBin;
use Test::More;
use Capture::Tiny qw( capture );
use File::Find::Rule;
use File::Slurp qw( read_file write_file);
use File::Spec::Functions;
use File::Temp qw( tempdir );

use lib "$FindBin::Bin/../../lib/perl5";
use QtQA::Test::More qw( is_or_like );

# Run xml2html_testcocoon
sub test_run
{
    my ($params_ref) = @_;

    my @args                   =   @{$params_ref->{ args }};
    my $expected_stdout        =   $params_ref->{ expected_stdout };
    my $expected_stderr        =   $params_ref->{ expected_stderr };
    my $expected_success       =   $params_ref->{ expected_success };
    my $expected_logfile_list  =   $params_ref->{ expected_logfile };
    my $expected_logtext_list  =   $params_ref->{ expected_logtext }  // [];
    my $testname               =   $params_ref->{ testname }          || q{};

    my $status;
    my ($output, $error) = capture {
        $status = system( 'perl', "$FindBin::Bin/../xml2html_testcocoon.pl", @args );
    };

    if ($expected_success) {
        is  ( $status, 0, "$testname exits zero" );
    } else {
        isnt( $status, 0, "$testname exits non-zero" );
    }

    is_or_like( $output, $expected_stdout, "$testname output looks correct" );
    is_or_like( $error,  $expected_stderr, "$testname error looks correct" );

    # The rest of the verification steps are only applicable if a log file is expected and created
    return if (!$expected_logfile_list);

    my $countLogFiles = @{$expected_logfile_list};
    my $countLogExpectedText = @{$expected_logtext_list};

    for (my $i = 0; $i < $countLogFiles; $i++) {
        my $expected_logfile = $expected_logfile_list->[$i];
        my $expected_logtext = "";
        if ($countLogExpectedText eq $countLogFiles) { # only if the counts match we use the expected texts from the list.
            $expected_logtext = $expected_logtext_list->[$i];
        }
        return if (!ok( -e $expected_logfile, "$testname created $expected_logfile" ));
        my $logtext = read_file( $expected_logfile );   # dies on error
        is_or_like( $logtext, $expected_logtext, "$testname " . basename($expected_logfile) . " is as expected" );
    }

    return;
}

sub test_success
{
    my $tempdir = tempdir( 'testcocoon_xml2html.XXXXXX', TMPDIR => 1, CLEANUP => 1 );

    my $xml_file = init_test_env($tempdir);
    my $created_report = [
        catfile($tempdir, 'module_report.html'),
        catfile($tempdir, 'files', 'folder_folder_module.html'),
        catfile($tempdir, 'files', 'tests_module_failed.html'),
        catfile($tempdir, 'files', 'tests_module_passed.html'),
        catfile($tempdir, 'files', 'tests_module_unknown.html'),
        catfile($tempdir, 'files', 'untested_sources_module.html')
        ];

    my $expected_text = get_html_report_content();

    my $include_path = catfile($FindBin::Bin, 'data', 'parsed-xml-testcocoon', 'module', 'src');

    test_run({
        args                =>  [ '--xml', $xml_file, '--module', 'module', '--output', $tempdir , '--include', $include_path],
        expected_stdout     =>  q{},
        expected_stderr     =>  q{},
        expected_success    =>  1,
        testname            =>  'basic test success',
        expected_logfile    =>  $created_report,
        expected_logtext    =>  $expected_text,
    });

    return;
}

sub test_invalid_xml
{
    my $invalid_xml_file = 'invalid.xml';

    test_run({
    args                =>  [ '--xml', $invalid_xml_file, '--module', 'module', '--output', 'fake', '--include', 'fake'],
        expected_stdout     =>  q{},
        expected_stderr     =>  qr{Missing or invalid required '--xml' option.*},
        expected_success    =>  0,
        testname            =>  'test invalid xml',
    });

    return;
}

sub test_missing_module
{
    my $tempdir = tempdir( 'testcocoon_xml2html.XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    my $xml_file = init_test_env($tempdir);

    test_run({
        args                =>  [ '--xml', $xml_file, '--output', 'fake', '--include', 'fake'],
        expected_stdout     =>  q{},
        expected_stderr     =>  qr{Missing required '--module' option.*},
        expected_success    =>  0,
        testname            =>  'test missing module',
    });

    return;
}

sub test_missing_output
{
    my $tempdir = tempdir( 'testcocoon_xml2html.XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    my $xml_file = init_test_env($tempdir);

    test_run({
        args                =>  [ '--xml', $xml_file, '--module', 'module', '--include', 'fake'],
        expected_stdout     =>  q{},
        expected_stderr     =>  qr{Missing required '--output' option.*},
        expected_success    =>  0,
        testname            =>  'test missing output',
    });

    return;
}

sub test_invalid_output
{
    my $tempdir = tempdir( 'testcocoon_xml2html.XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    my $xml_file = init_test_env($tempdir);

    test_run({
        args                =>  [ '--xml', $xml_file, '--module', 'module', '--output', '/\invalid_path' ,'--include', 'fake'],
        expected_stdout     =>  q{},
        expected_stderr     =>  qr{mkdir /\\invalid_path: *},
        expected_success    =>  0,
        testname            =>  'test invalid output',
    });

    return;
}

sub test_missing_include
{
    my $tempdir = tempdir( 'testcocoon_xml2html.XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    my $xml_file = init_test_env($tempdir);

    test_run({
        args                =>  [ '--xml', $xml_file, '--module', 'module', '--module', 'module', '--output', $tempdir],
        expected_stdout     =>  q{},
        expected_stderr     =>  qr{Missing required '--include' option.*},
        expected_success    =>  0,
        testname            =>  'test missing include',
    });

    return;
}

sub init_test_env
{
    my ($tempdir) = @_;

    # Create xml file from template
    my $xml_file_template = catfile($FindBin::Bin, 'data', 'parsed-xml-testcocoon', 'module_test_template.xml');
    my $content = read_file($xml_file_template);

    my $path_files = catfile($FindBin::Bin, 'data', 'parsed-xml-testcocoon', 'module', 'src');
    my $path_3rdparty = catfile($path_files, '3rdparty', '3rdparty.c');
    my $path_source = catfile($path_files, 'folder', 'source.cpp');
    my $path_source2 = catfile($path_files, 'folder', 'source2.cpp');
    my $path2_source2 = catfile($FindBin::Bin, 'data', 'parsed-xml-testcocoon', 'module2', 'src', 'folder2', 'source2.cpp');

    $content =~ s,%path_3rdparty%,$path_3rdparty,g;
    $content =~ s,%path_source%,$path_source,g;
    $content =~ s,%path_source2%,$path_source2,g;
    $content =~ s,%path2_source2%,$path2_source2,g;

    my $xml_file = catfile($tempdir, 'module_test_20120131-1042.xml');
    write_file($xml_file, $content);

    return $xml_file;
}

sub get_html_report_content
{
    # Create html content from templates

    my $list_html_content = [];

    my $path_source = catfile($FindBin::Bin, 'data', 'parsed-xml-testcocoon', 'module', 'src');
    my $thirdrdparty = catfile('3rdparty', '3rdparty.c');

    # Main html report
    my $html_report_template = catfile($FindBin::Bin, 'data', 'parsed-xml-testcocoon', "module_report_template.html");

    my $content = read_file($html_report_template);
    $content =~ s,%path_src%,$path_source,g;
    $content =~ s,%3rdparty%,$thirdrdparty,g;
    push  @{$list_html_content}, $content;

    # Files - folder
    my $html_folder_template = catfile($FindBin::Bin, 'data', 'parsed-xml-testcocoon', 'files', "folder_folder_module_template.html");
    my $content2 = read_file($html_folder_template);
    $content2 =~ s,%path_src%,$path_source,g;
    my $source = catfile('folder', 'source.cpp');
    my $source2 = catfile('folder', 'source2.cpp');
    $content2 =~ s,%source%,$source,g;
    $content2 =~ s,%source2%,$source2,g;
    push  @{$list_html_content}, $content2;

    my $html_failed_tests_template = catfile($FindBin::Bin, 'data', 'parsed-xml-testcocoon', 'files', "tests_module_failed_template.html");
    my $content3 = read_file($html_failed_tests_template);
    push  @{$list_html_content}, $content3;

    my $html_passed_tests_template = catfile($FindBin::Bin, 'data', 'parsed-xml-testcocoon', 'files', "tests_module_passed_template.html");
    my $content4 = read_file($html_passed_tests_template);
    push  @{$list_html_content}, $content4;

    my $html_unknown_tests_template = catfile($FindBin::Bin, 'data', 'parsed-xml-testcocoon', 'files', "tests_module_unknown_template.html");
    my $content5 = read_file($html_unknown_tests_template);
    push  @{$list_html_content}, $content5;

    my $html_untested_template = catfile($FindBin::Bin, 'data', 'parsed-xml-testcocoon', 'files', "untested_sources_module_template.html");
    my $content6 = read_file($html_untested_template);
    my $path_untested = catfile($path_source, 'folder', 'untested.cpp');
    $content6 =~ s,%path_untested%,$path_untested,g;
    push  @{$list_html_content}, $content6;

    return $list_html_content;
}


sub run
{
    test_success;
    test_invalid_xml;
    test_missing_module;
    test_missing_output;
    test_invalid_output;
    test_missing_include;

    done_testing;

    return;
}

run if (!caller);
1;

