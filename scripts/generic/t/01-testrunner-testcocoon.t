#!/usr/bin/env perl
use 5.010;
use strict;
use warnings;

=head1 NAME

01-testrunner-testcocoon.t - test testrunner's 'testcocoon' plugin for code coverage analysis.

=head1 SYNOPSIS

  perl ./01-testrunner-testcocoon.t

This test will run the testrunner.pl script with some fake testcocoon processes
and verify that the testcocoon plugin generates the expected output.

=cut

use Capture::Tiny qw( capture );
use Cwd;
use English qw( -no_match_vars );
use Env::Path;
use File::Path qw( mkpath );
use File::Spec::Functions;
use File::Temp qw( tempdir );
use FindBin;
use Readonly;
use Test::More;

use lib "$FindBin::Bin/../../lib/perl5";
use QtQA::Test::More qw( is_or_like create_mock_command );

# Directory separator, quoted for regex
Readonly my $DS => ($OSNAME eq 'MSWin32') ? q{\\\\} : q{/};

# Tempdir testcocoon for tests template
Readonly my $TEMPDIR_TOPLEVEL => catfile(File::Spec->tmpdir);

Readonly my $TEMPDIR_TEMPLATE =>
    qr{\Q$TEMPDIR_TOPLEVEL\E${DS}testcocoon_plugin\..{6}}sm;

# Commands used multiple times

Readonly my $MYTEST_DIR => qr{${TEMPDIR_TEMPLATE}${DS}module${DS}mytest}sm;

Readonly my $GLOBAL_TEST =>
    qr{$MYTEST_DIR${DS}mytest_global\.csmes}sm;

Readonly my $COVERAGERUNNER_CMMERGE_OTHERCSMES =>
    qr{\+ cmmerge --append --output=$GLOBAL_TEST $MYTEST_DIR${DS}mytest\.csmes.*};
Readonly my $COVERAGERUNNER_CMMERGE_PLUGIN_WITH_TEST =>
    qr{\+ cmmerge --append --output=$GLOBAL_TEST ${TEMPDIR_TEMPLATE}${DS}(?:module${DS}\.\.${DS})?qtbase${DS}plugins${DS}plugin1${DS}plugin1\.csmes.*};
Readonly my $COVERAGERUNNER_CMCSEXEIMPORT =>
    qr{\+ cmcsexeimport --csmes=$GLOBAL_TEST --csexe=$MYTEST_DIR${DS}myother\.csexe --title=tc_mytest --policy=merge.*};
Readonly my $COVERAGERUNNER_CMCSEXEIMPORT_OTHER =>
    qr{\+ cmcsexeimport --csmes=$GLOBAL_TEST --csexe=$MYTEST_DIR${DS}mytest\.csexe --title=tc_mytest --policy=merge.*};
Readonly my $COVERAGERUNNER_CMMERGE_TEST_WITH_GLOBAL =>
    qr{\+ cmmerge --append --output=${TEMPDIR_TEMPLATE}${DS}tests\.csmes $GLOBAL_TEST.*};

# Missing --testcocoon-tests-output required option
Readonly my $MISSING_REQUIRED_TESTS_OUTPUT =>
    qr{internal error: .*${DS}testcocoon\.pm loaded OK, but QtQA::App::TestRunner::Plugin::testcocoon could not be instantiated: Missing required '--testcocoon-tests-output' option at .*${DS}testcocoon\.pm line .*};

# Missing --testcocoon-qt-gitmodule-dir required option
Readonly my $MISSING_REQUIRED_GITDIR =>
    qr{internal error: .*${DS}testcocoon\.pm loaded OK, but QtQA::App::TestRunner::Plugin::testcocoon could not be instantiated: Invalid or missing required '--testcocoon-qt-gitmodule-dir' option at .*${DS}testcocoon\.pm line .*};

# Missing --testcocoon-qt-gitmodule required option
Readonly my $MISSING_REQUIRED_MODULE =>
    qr{internal error: .*${DS}testcocoon\.pm loaded OK, but QtQA::App::TestRunner::Plugin::testcocoon could not be instantiated: Missing required '--testcocoon-qt-gitmodule' option at .*${DS}testcocoon\.pm line .*};

# Cmmerge other csmes
Readonly my $CMMERGE_OTHERCSMES =>
    qr{test success.*
$COVERAGERUNNER_CMMERGE_OTHERCSMES}sm;

# Cmmerge with a plugin
Readonly my $CMMERGE_PLUGIN_WITH_TEST =>
    qr{$CMMERGE_OTHERCSMES
cmmerge success other csmes.*
$COVERAGERUNNER_CMMERGE_PLUGIN_WITH_TEST}sm;

# Cmcsexeimport
Readonly my $CMCSEXEIMPORT =>
    qr{$CMMERGE_PLUGIN_WITH_TEST
cmmerge success plugin with test.*
$COVERAGERUNNER_CMCSEXEIMPORT}sm;

# Cmcsexeimport other
Readonly my $CMCSEXEIMPORT_OTHER =>
    qr{$CMCSEXEIMPORT
cmcsexeimport success.*
$COVERAGERUNNER_CMCSEXEIMPORT_OTHER}sm;

# Cmmerge test into global
Readonly my $CMMERGE_TEST_INTO_GLOBAL =>
    qr{$CMCSEXEIMPORT_OTHER
cmcsexeimport other success.*
$COVERAGERUNNER_CMMERGE_TEST_WITH_GLOBAL}sm;

# Successful run
Readonly my $TESTSCRIPT_SUCCESS =>
    qr{$CMMERGE_TEST_INTO_GLOBAL
cmmerge success test into global.*}sm;

sub test_run
{
    my ($params_ref) = @_;

    my @args              = @{$params_ref->{ args }};
    my $expected_stdout   =   $params_ref->{ expected_stdout };
    my $expected_stderr   =   $params_ref->{ expected_stderr };
    my $expected_success  =   $params_ref->{ expected_success };
    my $testname          =   $params_ref->{ testname }          // q{};

    my $status;
    my ($output, $error) = capture {
        $status = system( 'perl', "$FindBin::Bin/../testrunner.pl", @args );
    };

    if ($expected_success) {
        is  ( $status, 0, "$testname exits zero" );
    }
    else {
        isnt( $status, 0, "$testname exits non-zero" );
    }

    is_or_like( $output, $expected_stdout, "$testname output looks correct" );
    is_or_like( $error,  $expected_stderr, "$testname error looks correct" );

    return;
}

sub test_success
{
    my $tempdir = tempdir( 'testcocoon_plugin.XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    init_test_env($tempdir);

    # Put our mock command first in PATH
    local $ENV{ PATH } = $ENV{ PATH };
    Env::Path->PATH->Prepend( $tempdir );

    create_mock_command(
        name        =>  'mytest',
        directory   =>  $tempdir,
        sequence    =>  [
           { exitcode => 0, stdout => "test success\n"},
        ],
    );

    create_mock_command(
        name        =>  'cmmerge',
        directory   =>  $tempdir,
        sequence    =>  [
            { exitcode => 0, stdout => "cmmerge success other csmes\n"},
            { exitcode => 0, stdout => "cmmerge success plugin with test\n"},
            { exitcode => 0, stdout => "cmmerge success test into global\n"},
        ],
    );

    create_mock_command(
        name        =>  'cmcsexeimport',
        directory   =>  $tempdir,
        sequence    =>  [
            { exitcode => 0, stdout => "cmcsexeimport success\n"},
            { exitcode => 0, stdout => "cmcsexeimport other success\n"},
        ],
    );

    my $initdir = getcwd;
    my $testdir = catfile( $tempdir, 'module', 'mytest');
    chdir($testdir);

    my $module_gitdir = catfile( $tempdir, 'module');
    my $tests_csmes = catfile( $tempdir, 'tests.csmes' );

    test_run({
        testname         => 'test success',
        args             => [ '--plugin', 'testcocoon', '--testcocoon-tests-output', $tests_csmes, '--testcocoon-qt-gitmodule-dir', $module_gitdir, '--testcocoon-qt-gitmodule', 'module', '--', "$tempdir/mytest",'testname' ],
        expected_success => 1,
        expected_stdout  => $TESTSCRIPT_SUCCESS,
        expected_stderr  => q{},
    });

    chdir($initdir);

    return;
}

sub test_invalid_tests_output_arg
{
    my $tempdir = tempdir( 'testcocoon_plugin.XXXXXX', TMPDIR => 1, CLEANUP => 1 );

    test_run({
        testname         => 'missing test output',
        args             => [ '--plugin', 'testcocoon', '--testcocoon-qt-gitmodule-dir', 'fake_gitmodule_dir', '--', "$tempdir/mytest",'testname' ],
        expected_success => 0,
        expected_stdout  => q{},
        expected_stderr  => $MISSING_REQUIRED_TESTS_OUTPUT,
    });

    return;
}

sub test_invalid_qt_gitmodule_dir
{
    my $tempdir = tempdir( 'testcocoon_plugin.XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    my $tests_csmes = catfile( $tempdir, 'tests.csmes' );

    test_run({
        testname         => 'missing git module dir',
        args             => [ '--plugin', 'testcocoon', '--testcocoon-tests-output', $tests_csmes, '--', "$tempdir/mytest",'testname' ],
        expected_success => 0,
        expected_stdout  => q{},
        expected_stderr  => $MISSING_REQUIRED_GITDIR,
    });

    return;
}

sub test_missing_qt_gitmodule
{
    my $tempdir = tempdir( 'testcocoon_plugin.XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    init_test_env($tempdir);

    my $module_gitdir = catfile( $tempdir, 'module');
    my $tests_csmes = catfile( $tempdir, 'tests.csmes' );

    test_run({
        testname         => 'missing git module name',
        args             => [ '--plugin', 'testcocoon', '--testcocoon-qt-gitmodule-dir', $module_gitdir, '--testcocoon-tests-output', $tests_csmes, '--', "$tempdir/mytest",'testname' ],
        expected_success => 0,
        expected_stdout  => q{},
        expected_stderr  => $MISSING_REQUIRED_MODULE,
    });

    return;
}

sub test_merge_other_csmes_failure
{
    my $tempdir = tempdir( 'testcocoon_plugin.XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    init_test_env($tempdir);

    # Put our mock command first in PATH
    local $ENV{ PATH } = $ENV{ PATH };
    Env::Path->PATH->Prepend( $tempdir );

    create_mock_command(
        name        =>  'mytest',
        directory   =>  $tempdir,
        sequence    =>  [
           { exitcode => 0, stdout => "test success\n"},
        ],
    );

    create_mock_command(
        name        =>  'cmmerge',
        directory   =>  $tempdir,
        sequence    =>  [
            { exitcode => 1, stderr => "cmmerge failure other csmes\n"},
        ],
    );

    my $initdir = getcwd;
    my $testdir = catfile( $tempdir, 'module', 'mytest');
    chdir($testdir);

    my $module_gitdir = catfile( $tempdir, 'module');
    my $tests_csmes = catfile( $tempdir, 'tests.csmes' );

    test_run({
        testname         => 'cmmerge other csmes failure',
        args             => [ '--plugin', 'testcocoon', '--testcocoon-tests-output', $tests_csmes, '--testcocoon-qt-gitmodule-dir', $module_gitdir, '--testcocoon-qt-gitmodule', 'module', '--', "$tempdir/mytest",'testname' ],
        expected_success => 0,
        expected_stdout  => $CMMERGE_OTHERCSMES,
        expected_stderr  => qr{cmmerge failure other csmes\n},
    });

    chdir($initdir);

    return;
}

sub test_cmmerge_plugin_with_test_failure
{
    my $tempdir = tempdir( 'testcocoon_plugin.XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    init_test_env($tempdir);

    # Put our mock command first in PATH
    local $ENV{ PATH } = $ENV{ PATH };
    Env::Path->PATH->Prepend( $tempdir );

    create_mock_command(
        name        =>  'mytest',
        directory   =>  $tempdir,
        sequence    =>  [
           { exitcode => 0, stdout => "test success\n"},
        ],
    );

    create_mock_command(
        name        =>  'cmmerge',
        directory   =>  $tempdir,
        sequence    =>  [
            { exitcode => 0, stdout => "cmmerge success other csmes\n"},
            { exitcode => 1, stderr => "cmmerge failure plugin\n"},
        ],
    );

    my $initdir = getcwd;
    my $testdir = catfile( $tempdir, 'module', 'mytest');
    chdir($testdir);

    my $module_gitdir = catfile( $tempdir, 'module');
    my $tests_csmes = catfile( $tempdir, 'tests.csmes' );

    test_run({
        testname         => 'cmmerge into global plugins failure',
        args             => [ '--plugin', 'testcocoon', '--testcocoon-tests-output', $tests_csmes, '--testcocoon-qt-gitmodule-dir', $module_gitdir, '--testcocoon-qt-gitmodule', 'module', '--', "$tempdir/mytest",'testname' ],
        expected_success => 0,
        expected_stdout  => $CMMERGE_PLUGIN_WITH_TEST,
        expected_stderr  => qr{cmmerge failure plugin\n},
    });

    chdir($initdir);

    return;
}

sub test_cmcsexeimport_failure
{
    my $tempdir = tempdir( 'testcocoon_plugin.XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    init_test_env($tempdir);

    # Put our mock command first in PATH
    local $ENV{ PATH } = $ENV{ PATH };
    Env::Path->PATH->Prepend( $tempdir );

    create_mock_command(
        name        =>  'mytest',
        directory   =>  $tempdir,
        sequence    =>  [
           { exitcode => 0, stdout => "test success\n"},
        ],
    );

    create_mock_command(
        name        =>  'cmmerge',
        directory   =>  $tempdir,
        sequence    =>  [
            { exitcode => 0, stdout => "cmmerge success other csmes\n"},
            { exitcode => 0, stdout => "cmmerge success plugin with test\n"},
        ],
    );

    create_mock_command(
        name        =>  'cmcsexeimport',
        directory   =>  $tempdir,
        sequence    =>  [
            { exitcode => 3, stderr => "cmcsexeimport failure\n"},
        ],
    );

    my $initdir = getcwd;
    my $testdir = catfile( $tempdir, 'module', 'mytest');
    chdir($testdir);

    my $module_gitdir = catfile( $tempdir, 'module');
    my $tests_csmes = catfile( $tempdir, 'tests.csmes' );

    test_run({
        testname         => 'cmcsexeimport failure',
        args             => [ '--plugin', 'testcocoon', '--testcocoon-tests-output', $tests_csmes, '--testcocoon-qt-gitmodule-dir', $module_gitdir, '--testcocoon-qt-gitmodule', 'module', '--', "$tempdir/mytest",'testname' ],
        expected_success => 0,
        expected_stdout  => $CMCSEXEIMPORT,
        expected_stderr  => qr{cmcsexeimport failure\n},
    });

    chdir($initdir);

    return;
}

sub test_cmmerge_test_into_global_failure
{
    my $tempdir = tempdir( 'testcocoon_plugin.XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    init_test_env($tempdir);

    # Put our mock command first in PATH
    local $ENV{ PATH } = $ENV{ PATH };
    Env::Path->PATH->Prepend( $tempdir );

    create_mock_command(
        name        =>  'mytest',
        directory   =>  $tempdir,
        sequence    =>  [
           { exitcode => 0, stdout => "test success\n"},
        ],
    );

    create_mock_command(
        name        =>  'cmmerge',
        directory   =>  $tempdir,
        sequence    =>  [
            { exitcode => 0, stdout => "cmmerge success other csmes\n"},
            { exitcode => 0, stdout => "cmmerge success plugin with test\n"},
            { exitcode => 4, stderr => "cmmerge failure test into global\n"},
        ],
    );

    create_mock_command(
        name        =>  'cmcsexeimport',
        directory   =>  $tempdir,
        sequence    =>  [
            { exitcode => 0, stdout => "cmcsexeimport success\n"},
            { exitcode => 0, stdout => "cmcsexeimport other success\n"},
        ],
    );

    my $initdir = getcwd;
    my $testdir = catfile( $tempdir, 'module', 'mytest');
    chdir($testdir);

    my $module_gitdir = catfile( $tempdir, 'module');
    my $tests_csmes = catfile( $tempdir, 'tests.csmes' );

    test_run({
        testname         => 'cmmerge test into global failure',
        args             => [ '--plugin', 'testcocoon', '--testcocoon-tests-output', $tests_csmes, '--testcocoon-qt-gitmodule-dir', $module_gitdir, '--testcocoon-qt-gitmodule', 'module', '--', "$tempdir/mytest",'testname' ],
        expected_success => 0,
        expected_stdout  => $CMMERGE_TEST_INTO_GLOBAL,
        expected_stderr  => qr{cmmerge failure test into global\n},
    });

    chdir($initdir);

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

    # Create "module" path
    my $gitmodule_path = catfile($tempdir, 'module');
    if (! -d $gitmodule_path && ! mkpath( $gitmodule_path )) {
        die "mkpath $gitmodule_path: $!";
    }

    # Create "mytest" path
    my $mytest_path = catfile($gitmodule_path, 'mytest');
    if (! -d $mytest_path && ! mkpath( $mytest_path )) {
        die "mkpath $mytest_path: $!";
    }

    # Create qtbase plugins path
    my $plugins_path = catfile($qtbase_path, 'plugins');
    if (! -d $plugins_path && ! mkpath( $plugins_path )) {
        die "mkpath $plugins_path: $!";
    }

    my $plugin1_path = catfile($plugins_path, 'plugin1');
    if (! -d $plugin1_path && ! mkpath( $plugin1_path )) {
        die "mkpath $plugin1_path: $!";
    }

    # Create csmes for 1 plugin
    open(my $plugin1, ">", "$plugin1_path/plugin1.csmes") or die $!;
    close($plugin1);

    #  Create current test csexe and csmes
    open(my $mytestcsmes, ">", "$mytest_path/mytest.csmes") or die $!;
    close($mytestcsmes);
    open(my $mytestcsexe, ">", "$mytest_path/mytest.csexe") or die $!;
    close($mytestcsexe);
    open(my $myothercsmes, ">", "$mytest_path/myother.csmes") or die $!;
    close($myothercsmes);
    open(my $myothercsexe, ">", "$mytest_path/myother.csexe") or die $!;
    close($myothercsexe);
    open(my $moccsexe, ">", "$mytest_path/moc.csexe") or die $!;
    close($moccsexe);

    # Create a tests result database csmes
    open(my $test, ">", "$tempdir/tests.csmes") or die $!;
    close($test);

    return;
}

sub run
{
    test_success;
    test_invalid_tests_output_arg;
    test_invalid_qt_gitmodule_dir;
    test_merge_other_csmes_failure;
    test_cmmerge_plugin_with_test_failure;
    test_cmcsexeimport_failure;
    test_cmmerge_test_into_global_failure;
    test_missing_qt_gitmodule;

    done_testing;

    return;
}

run if (!caller);
1;

