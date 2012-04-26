#!/usr/bin/env perl
use 5.010;
use strict;
use warnings;

=head1 NAME

23-testrunner-crashreporter.t - test testrunner's crashreporter plugin

=head1 SYNOPSIS

  perl ./23-testrunner-crashreporter.t

This test will run the testrunner.pl script with some crashing processes
and do a basic verification that the CrashReporter crash logs are
correctly printed.

=cut

use Capture::Tiny qw( capture );
use English qw( -no_match_vars );
use FindBin;
use File::Basename;
use File::Slurp qw( read_file );
use File::Temp qw( tempdir );
use File::Spec::Functions;
use FindBin;
use Readonly;
use Test::More;

use lib "$FindBin::Bin/../../lib/perl5";
use QtQA::Test::More qw( is_or_like );

Readonly my $HELPER_DIR => catfile( $FindBin::Bin, 'helpers' );

# regex snippet when process exits due to segfault
Readonly my $PROCESS_EXITED_DUE_TO_SIGNAL => qr{
    \QQtQA::App::TestRunner: Process exited due to signal 11\E
        (?:\Q; dumped core\E)?  # we don't care if it dumped core
        \n
}xms;

# Matches text expected when a segfault occurs
Readonly my $SIGSEGV_CRASHLOG => qr{

    \A

    $PROCESS_EXITED_DUE_TO_SIGNAL

    \QQtQA::App::TestRunner: ============================= crash report follows: ============================\E\n

    # We are doing a basic check that some crash log appears to have been printed.
    # The actual content is only verified very loosely.

    .*
    \QQtQA::App::TestRunner: OS Version:      Mac OS X \E
    .*
    \QQtQA::App::TestRunner: Exception Type:  EXC_BAD_ACCESS (SIGSEGV)\E\n
    .*
    \QQtQA::App::TestRunner: ================================================================================\E\n

    \z

}xms;

sub test_run
{
    my ($params_ref) = @_;

    my @args              = @{$params_ref->{ args }};
    my $expected_stdout   =   $params_ref->{ expected_stdout };
    my $expected_stderr   =   $params_ref->{ expected_stderr };
    my $expected_success  =   $params_ref->{ expected_success };
    my $expected_logfile  =   $params_ref->{ expected_logfile };
    my $expected_logtext  =   $params_ref->{ expected_logtext }  // "";
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

    # The rest of the verification steps are only applicable if a log file is expected and created
    return if (!$expected_logfile);
    return if (!ok( -e $expected_logfile, "$testname created $expected_logfile" ));

    my $logtext = read_file( $expected_logfile );   # dies on error
    is_or_like( $logtext, $expected_logtext, "$testname logtext is as expected" );

    return;
}

sub test_testrunner
{
    # control; check that `--plugin crashreporter' can load OK
    test_run({
        testname         => 'plugin loads OK 0 exitcode',
        args             => [ '--plugin', 'crashreporter', '--', 'true' ],
        expected_success => 1,
        expected_stdout  => q{},
        expected_stderr  => q{},
    });

    # another control; check that it doesn't break non-zero exit code
    test_run({
        testname         => 'plugin loads OK !0 exitcode',
        args             => [ '--plugin', 'crashreporter', '--', 'false' ],
        expected_success => 0,
        expected_stdout  => q{},
        expected_stderr  => q{},
    });

    my @crash_command = ( 'perl', catfile( $HELPER_DIR, 'dereference_bad_pointer.pl' ) );

    # check that a crash log is captured if process crashes
    test_run({
        testname         => 'simple backtrace',
        args             => [ '--plugin', 'crashreporter', '--', @crash_command ],
        expected_success => 0,
        expected_stdout  => q{},
        expected_stderr  => $SIGSEGV_CRASHLOG,
    });

    # check that the crashlog is captured via --capture-logs OK
    my $tempdir = tempdir( basename($0).'.XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    test_run({
        testname         => 'crash to log [capture]',
        args             => [
            '--capture-logs',
            $tempdir,
            '--plugin',
            'crashreporter',
            '--sync-output',
            '--',
            @crash_command,
        ],
        expected_success => 0,
        expected_stdout  => q{},
        expected_stderr  => q{},
        expected_logfile => "$tempdir/perl-00.txt",
        expected_logtext => $SIGSEGV_CRASHLOG,
    });

    # And again, with --tee
    test_run({
        testname         => 'crash to log [tee]',
        args             => [
            '--tee-logs',
            $tempdir,
            '--plugin',
            'crashreporter',
            '--',
            @crash_command,
        ],
        expected_success => 0,
        expected_stdout  => q{},
        expected_stderr  => $SIGSEGV_CRASHLOG,
        expected_logfile => "$tempdir/perl-01.txt",
        expected_logtext => $SIGSEGV_CRASHLOG,
    });

    # check what happens if a crash log can't be found
    {
        local $ENV{ QTQA_CRASHREPORTER_DIR } = '/bogus/crashreport/dir';
        test_run({
            testname         => 'no crash report',
            args             => [ '--plugin', 'crashreporter', '--', @crash_command ],
            expected_success => 0,
            expected_stdout  => q{},
            expected_stderr  => qr{
                \A
                $PROCESS_EXITED_DUE_TO_SIGNAL
                \QQtQA::App::TestRunner: Sorry, a crash report could not be found in /bogus/crashreport/dir.\E\n
                \z
            }xms
        });
    }

    return;
}

sub run
{
    if ($OSNAME !~ m{darwin}i) {
        plan 'skip_all', "test is not relevant on $OSNAME";
    }

    TODO: {
        local $TODO = 'QTQAINFRA-488, mac crash report collection is unstable';
        test_testrunner;
    }

    done_testing;

    return;
}

run if (!caller);
1;

