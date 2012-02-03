#!/usr/bin/env perl
use 5.010;
use strict;
use warnings;
use utf8;
use Readonly;

=head1 NAME

01-coveragerunner_testcocoon.t - basic test for coveragerunner_testcocoon.pl

=head1 SYNOPSIS

  perl ./01-coveragerunner_testcocoon.t

This test will run the coveragerunner_testcocoon.pl script with a few different
types of subprocesses and verify that behavior is as expected.

=cut

use Encode;
use English qw( -no_match_vars );
use FindBin;
use Readonly;
use Test::More;
use Capture::Tiny qw( capture );
use Env::Path;
use File::Basename;
use File::Copy;
use File::Find::Rule;
use File::Path qw( mkpath );
use File::Spec::Functions;
use File::Temp qw( tempdir );

use lib "$FindBin::Bin/../../lib/perl5";
use QtQA::Test::More qw( is_or_like create_mock_command );

# Directory separator, quoted for regex
Readonly my $DS => ($OSNAME eq 'MSWin32') ? q{\\\\} : q{/};

# Tempdir testcocoon for tests template
Readonly my $TEMPDIR_TOPLEVEL => File::Spec->tmpdir;

Readonly my $TEMPDIR_TEMPLATE =>
    qr{\Q$TEMPDIR_TOPLEVEL\E${DS}testcocoon_runner\..{6}}sm;

# Preamble always printed out at the beginning
Readonly my $COVERAGERUNNER_PREAMBLE =>
    qr{Gather all library files covered in a global database\sList of all source files in coverage.*};

# Reused paths to csmes for the libraries
# Note for this (and others), the module/.. part is optional,
# because that may be redundant and File::Find may already clean up that
# before returning.
Readonly my $LIST_CSMESLIB =>
    qr{${TEMPDIR_TEMPLATE}${DS}(?:module${DS}\.\.${DS})?qtbase${DS}lib${DS}lib\.csmes.*
${TEMPDIR_TEMPLATE}${DS}(?:module${DS}\.\.${DS})?qtbase${DS}lib${DS}lib2\.csmes.*}sm;

# First merge command
Readonly my $COVERAGERUNNER_CMMERGE_SRC =>
    qr{\+ cmmerge --append --output=${TEMPDIR_TEMPLATE}${DS}module_coverage_src-[0-9]{8}-[0-9]{4}\.csmes ${TEMPDIR_TEMPLATE}${DS}(?:module${DS}\.\.${DS})?qtbase${DS}lib${DS}lib2\.csmes.*};

# Second merge command
Readonly my $COVERAGERUNNER_CMMERGE_GLOBAL =>
    qr{\+ cmmerge --append --output=${TEMPDIR_TEMPLATE}${DS}module_coverage_global-[0-9]{8}-[0-9]{4}\.csmes ${TEMPDIR_TEMPLATE}${DS}module_coverage_unittests-[0-9]{8}-[0-9]{4}\.csmes.*};

# Cmreport command
Readonly my $COVERAGERUNNER_CMREPORT =>
    qr{\+ cmreport --csmes=${TEMPDIR_TEMPLATE}${DS}module_coverage_global-[0-9]{8}-[0-9]{4}\.csmes --xml=${TEMPDIR_TEMPLATE}${DS}module_coverage_report-[0-9]{8}-[0-9]{4}\.xml --select=.* --source=all --source-sort=name --global=all.*};

# gzip command
Readonly my $COVERAGERUNNER_GZIP =>
    qr{\+ gzip ${TEMPDIR_TEMPLATE}${DS}module_coverage_global-[0-9]{8}-[0-9]{4}\.csmes.*};

# xml2html_testcocoon command
Readonly my $COVERAGERUNNER_XML2HTML =>
    qr{\+ xml2html_testcocoon --xml ${TEMPDIR_TEMPLATE}${DS}module_coverage_report-[0-9]{8}-[0-9]{4}\.xml --module module --output ${TEMPDIR_TEMPLATE}.*};

# Standard output up to the first merge (gathering the lib and plugins csmes)
Readonly my $FIRST_CMMERGE =>
    qr{$COVERAGERUNNER_PREAMBLE
$LIST_CSMESLIB
$COVERAGERUNNER_CMMERGE_SRC}sm;

# Standard output up to the second merge (gathering the lib and plugins csmes)
Readonly my $SECOND_CMMERGE =>
    qr{$FIRST_CMMERGE
cmmerge success lib.*
End of list.*
$COVERAGERUNNER_CMMERGE_GLOBAL}sm;

# Standard output until cmreport command
Readonly my $CMREPORT =>
    qr{$SECOND_CMMERGE
cmmerge success tests.*
$COVERAGERUNNER_CMREPORT}sm;

# Standard output until gzip
Readonly my $GZIP =>
    qr{$CMREPORT
cmreport success.*
$COVERAGERUNNER_GZIP}sm;

# Standard output until xml2html_testcocoon
Readonly my $XML2HTML =>
    qr{$GZIP
gzip success.*
$COVERAGERUNNER_XML2HTML}sm;

# Successful run
Readonly my $TESTSCRIPT_SUCCESS =>
    qr{$XML2HTML
xml2html_testcocoon success.*}sm;

# Invalid --qtcoverage-test-ouput required argument
Readonly my $INVALID_TESTS_OUTPUT =>
    qr{${TEMPDIR_TEMPLATE}${DS}tests_invalid\.csmes does not exist. Either the tests have not been run or coverage was not enabled at build time};

# Run coveragerunner_testcocoon
sub test_run
{
    my ($params_ref) = @_;

    my @args              = @{$params_ref->{ args }};
    my $expected_stdout   =   $params_ref->{ expected_stdout };
    my $expected_stderr   =   $params_ref->{ expected_stderr };
    my $expected_success  =   $params_ref->{ expected_success };
    my $testname          =   $params_ref->{ testname }          || q{};

    my $status;
    my ($output, $error) = capture {
        $status = system( 'perl', "$FindBin::Bin/../coveragerunner_testcocoon.pl", @args );
    };

    if ($expected_success) {
        is  ( $status, 0, "$testname exits zero" );
    } else {
        isnt( $status, 0, "$testname exits non-zero" );
    }

    is_or_like( $output, $expected_stdout, "$testname output looks correct" );
    is_or_like( $error,  $expected_stderr, "$testname error looks correct" );

    return;
}

sub test_success
{
    my $tempdir = tempdir( 'testcocoon_runner.XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    init_test_env($tempdir);

    # Put our mock command first in PATH
    local $ENV{ PATH } = $ENV{ PATH };
    Env::Path->PATH->Prepend( $tempdir );

    create_mock_command(
        name        =>  'cmmerge',
        directory   =>  $tempdir,
        sequence    =>  [
            { exitcode => 0, stdout => "cmmerge success lib\n"},
            { exitcode => 0, stdout => "cmmerge success tests\n"},
        ],
    );

    create_mock_command(
        name        =>  'cmreport',
        directory   =>  $tempdir,
        sequence    =>  [
            { exitcode => 0, stdout => "cmreport success\n"},
        ],
    );

    create_mock_command(
        name        =>  'gzip',
        directory   =>  $tempdir,
        sequence    =>  [
            { exitcode => 0, stdout => "gzip success\n"},
        ],
    );

    local $ENV{ TESTING_COVERAGERUNNER } = 1;
    create_mock_command(
        name        =>  'xml2html_testcocoon',
        directory   =>  $tempdir,
        sequence    =>  [
            { exitcode => 0, stdout => "xml2html_testcocoon success\n"},
        ],
    );

    my $module_gitdir = catfile( $tempdir, 'module');
    my $test_csmes = catfile( $tempdir, 'tests.csmes' );

    test_run({
        args                =>  [ '--qt-gitmodule-dir', $module_gitdir, '--qt-gitmodule', 'module', '--qtcoverage-tests-output', $test_csmes, 'testname'],
        expected_stdout     =>  $TESTSCRIPT_SUCCESS,
        expected_stderr     =>  q{},
        expected_success    =>  1,
        testname            =>  'basic test success',
    });

    return;
}

sub test_first_merge_failure
{
    my $tempdir = tempdir( 'testcocoon_runner.XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    init_test_env($tempdir);

    # Put our mock command first in PATH
    local $ENV{ PATH } = $ENV{ PATH };
    Env::Path->PATH->Prepend( $tempdir );

    create_mock_command(
        name        =>  'cmmerge',
        directory   =>  $tempdir,
        sequence    =>  [
            { exitcode => 1, stderr => "first cmmerge failure\n", stdout => ""},
        ],
    );

    my $module_gitdir = catfile( $tempdir, 'module');
    my $test_csmes = catfile( $tempdir, 'tests.csmes' );

    test_run({
        args                =>  [ '--qt-gitmodule-dir', $module_gitdir, '--qt-gitmodule', 'module', '--qtcoverage-tests-output', $test_csmes, 'testname'],
        expected_stdout     =>  $FIRST_CMMERGE,
        expected_stderr     =>  qr{first cmmerge failure\n}sm,
        expected_success    =>  0,
        testname            =>  'test first merge failed',
    });

    return;
}

sub test_second_merge_failure
{
    my $tempdir = tempdir( 'testcocoon_runner.XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    init_test_env($tempdir);

    # Put our mock command first in PATH
    local $ENV{ PATH } = $ENV{ PATH };
    Env::Path->PATH->Prepend( $tempdir );

    create_mock_command(
        name        =>  'cmmerge',
        directory   =>  $tempdir,
        sequence    =>  [
            { exitcode => 0, stdout => "cmmerge success lib\n"},
            { exitcode => 2, stderr => "second cmmerge failure\n", stdout => ""},
        ],
    );

    my $module_gitdir = catfile( $tempdir, 'module');
    my $test_csmes = catfile( $tempdir, 'tests.csmes' );

    test_run({
        args                =>  [ '--qt-gitmodule-dir', $module_gitdir, '--qt-gitmodule', 'module', '--qtcoverage-tests-output', $test_csmes, 'testname'],
        expected_stdout     =>  $SECOND_CMMERGE,
        expected_stderr     =>  qr{second cmmerge failure\n}sm,
        expected_success    =>  0,
        testname            =>  'test second merge failed',
    });

    return;
}

sub test_cmreport_failure
{
    my $tempdir = tempdir( 'testcocoon_runner.XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    init_test_env($tempdir);

    # Put our mock command first in PATH
    local $ENV{ PATH } = $ENV{ PATH };
    Env::Path->PATH->Prepend( $tempdir );

    create_mock_command(
        name        =>  'cmmerge',
        directory   =>  $tempdir,
        sequence    =>  [
            { exitcode => 0, stdout => "cmmerge success lib\n"},
            { exitcode => 0, stdout => "cmmerge success tests\n"},
        ],
    );

    create_mock_command(
        name        =>  'cmreport',
        directory   =>  $tempdir,
        sequence    =>  [
            { exitcode => 3, stderr => "cmreport failure\n", stdout => ""},
        ],
    );

    my $module_gitdir = catfile( $tempdir, 'module');
    my $test_csmes = catfile( $tempdir, 'tests.csmes' );

    test_run({
        args                =>  [ '--qt-gitmodule-dir', $module_gitdir, '--qt-gitmodule', 'module', '--qtcoverage-tests-output', $test_csmes, 'testname'],
        expected_stdout     =>  $CMREPORT,
        expected_stderr     =>  qr{cmreport failure\n}sm,
        expected_success    =>  0,
        testname            =>  'test cmreport failure',
    });

    return;
}

sub test_gzip_failure
{
    my $tempdir = tempdir( 'testcocoon_runner.XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    init_test_env($tempdir);

    # Put our mock command first in PATH
    local $ENV{ PATH } = $ENV{ PATH };
    Env::Path->PATH->Prepend( $tempdir );

    create_mock_command(
        name        =>  'cmmerge',
        directory   =>  $tempdir,
        sequence    =>  [
            { exitcode => 0, stdout => "cmmerge success lib\n"},
            { exitcode => 0, stdout => "cmmerge success tests\n"},
        ],
    );

    create_mock_command(
        name        =>  'cmreport',
        directory   =>  $tempdir,
        sequence    =>  [
            { exitcode => 0, stdout => "cmreport success\n"},
        ],
    );

    create_mock_command(
        name        =>  'gzip',
        directory   =>  $tempdir,
        sequence    =>  [
            { exitcode => 4, stderr => "gzip failure\n", stdout => ""},
        ],
    );

    my $module_gitdir = catfile( $tempdir, 'module');
    my $test_csmes = catfile( $tempdir, 'tests.csmes' );

    test_run({
        args                =>  [ '--qt-gitmodule-dir', $module_gitdir, '--qt-gitmodule', 'module', '--qtcoverage-tests-output', $test_csmes, 'testname'],
        expected_stdout     =>  $GZIP,
        expected_stderr     =>  qr{gzip failure\n}sm,
        expected_success    =>  0,
        testname            =>  'test gzip failure',
    });

    return;
}

sub test_xml2html_failure
{
    my $tempdir = tempdir( 'testcocoon_runner.XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    init_test_env($tempdir);

    # Put our mock command first in PATH
    local $ENV{ PATH } = $ENV{ PATH };
    Env::Path->PATH->Prepend( $tempdir );

    create_mock_command(
        name        =>  'cmmerge',
        directory   =>  $tempdir,
        sequence    =>  [
            { exitcode => 0, stdout => "cmmerge success lib\n"},
            { exitcode => 0, stdout => "cmmerge success tests\n"},
        ],
    );

    create_mock_command(
        name        =>  'cmreport',
        directory   =>  $tempdir,
        sequence    =>  [
            { exitcode => 0, stdout => "cmreport success\n"},
        ],
    );

    create_mock_command(
        name        =>  'gzip',
        directory   =>  $tempdir,
        sequence    =>  [
            { exitcode => 0, stdout => "gzip success\n"},
        ],
    );

    local $ENV{ TESTING_COVERAGERUNNER } = 1;
    create_mock_command(
        name        =>  'xml2html_testcocoon',
        directory   =>  $tempdir,
        sequence    =>  [
            { exitcode => 5, stderr => "xml2html_testcocoon failure\n"},
        ],
    );

    my $module_gitdir = catfile( $tempdir, 'module');
    my $test_csmes = catfile( $tempdir, 'tests.csmes' );

    test_run({
        args                =>  [ '--qt-gitmodule-dir', $module_gitdir, '--qt-gitmodule', 'module', '--qtcoverage-tests-output', $test_csmes, 'testname'],
        expected_stdout     =>  $XML2HTML,
        expected_stderr     =>  qr{xml2html_testcocoon failure\n}sm,
        expected_success    =>  0,
        testname            =>  'test xml2html failure',
    });

    return;
}

sub test_invalid_qtcoverage_tests_output
{
    my $tempdir = tempdir( 'testcocoon_runner.XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    init_test_env($tempdir);

    my $test_invalid_csmes = catfile( $tempdir, 'tests_invalid.csmes' );

    test_run({
        args                =>  [ '--qt-gitmodule-dir', $tempdir, '--qt-gitmodule', 'module', '--qtcoverage-tests-output', $test_invalid_csmes, 'testname'],
        expected_stdout     =>  q{},
        expected_stderr     =>  $INVALID_TESTS_OUTPUT,
        expected_success    =>  0,
        testname            =>  'invalid csmes output file',
    });

    return;
}

sub init_test_env
{
    my ($tempdir) = @_;

    # Create qtbase path
    my $qtbase_path = catfile($tempdir, 'qtbase');
    if (! -d $qtbase_path && ! mkpath( $qtbase_path )) {
        die "mkpath $qtbase_path: $!";
    }

    # Create plugins path
    my $plugins_path = catfile($qtbase_path, 'plugins');
    if (! -d $plugins_path && ! mkpath( $plugins_path )) {
        die "mkpath $plugins_path: $!";
    }

    # Create "module" path
    my $module_gitdir = catfile( $tempdir, 'module');
    if (! -d $module_gitdir && ! mkpath( $module_gitdir )) {
        die "mkpath $module_gitdir: $!";
    }

    # Create lib path
    my $lib_path = catfile($qtbase_path, 'lib');
    if (! -d $lib_path && ! mkpath( $lib_path )) {
        die "mkpath $lib_path: $!";
    }
    # Create a csmes in lib folder
    open(my $lib, ">", "$lib_path/lib.csmes") or die $!;
    close($lib);
    open(my $lib2, ">", "$lib_path/lib2.csmes") or die $!;
    close($lib2);
    # Create a tests result database csmes
    open(my $test, ">", "$tempdir/tests.csmes") or die $!;
    close($test);

    return;
}

sub run
{
    test_success;
    test_first_merge_failure;
    test_second_merge_failure;
    test_cmreport_failure;
    test_gzip_failure;
    test_invalid_qtcoverage_tests_output;
    test_xml2html_failure;

    done_testing;

    return;
}

run if (!caller);
1;

