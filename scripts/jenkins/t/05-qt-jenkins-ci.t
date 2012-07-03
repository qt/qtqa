#!/usr/bin/env perl
#############################################################################
##
## Copyright (C) 2012 Nokia Corporation and/or its subsidiary(-ies).
## Contact: http://www.qt-project.org/
##
## This file is part of the Quality Assurance module of the Qt Toolkit.
##
## $QT_BEGIN_LICENSE:LGPL$
## GNU Lesser General Public License Usage
## This file may be used under the terms of the GNU Lesser General Public
## License version 2.1 as published by the Free Software Foundation and
## appearing in the file LICENSE.LGPL included in the packaging of this
## file. Please review the following information to ensure the GNU Lesser
## General Public License version 2.1 requirements will be met:
## http://www.gnu.org/licenses/old-licenses/lgpl-2.1.html.
##
## In addition, as a special exception, Nokia gives you certain additional
## rights. These rights are described in the Nokia Qt LGPL Exception
## version 1.1, included in the file LGPL_EXCEPTION.txt in this package.
##
## GNU General Public License Usage
## Alternatively, this file may be used under the terms of the GNU General
## Public License version 3.0 as published by the Free Software Foundation
## and appearing in the file LICENSE.GPL included in the packaging of this
## file. Please review the following information to ensure the GNU General
## Public License version 3.0 requirements will be met:
## http://www.gnu.org/copyleft/gpl.html.
##
## Other Usage
## Alternatively, this file may be used in accordance with the terms and
## conditions contained in a signed written agreement between you and Nokia.
##
##
##
##
##
##
## $QT_END_LICENSE$
##
#############################################################################

use strict;
use warnings;

=head1 NAME

05-qt-jenkins-ci.t - basic test for qt-jenkins-ci.pl

=cut

use Carp qw( confess );
use Cwd qw( realpath );
use English qw( -no_match_vars );
use File::Spec::Functions qw( :ALL );
use FindBin;
use Readonly;
use Sub::Override;
use Test::More;
use File::Temp qw( tempdir );
use File::Slurp qw( read_file );
use English qw( -no_match_vars );

Readonly my $PACKAGE => 'QtQA::App::JenkinsCI';
Readonly my $SCRIPT => catfile( $FindBin::Bin, '..', 'qt-jenkins-ci.pl' );

Readonly my $SUMMARIZE_JENKINS_BUILD => realpath( catfile( $FindBin::Bin, '..', 'summarize-jenkins-build.pl' ) );

# Mock the fetching of data from Jenkins and the running of external commands.
# Returns an object. When that object is destroyed, the mocking is undone.
sub do_mocks
{
    my (%args) = @_;

    my $fetch_override = Sub::Override->new( "${PACKAGE}::fetch_to_scalar", sub {
        my ($url) = @_;
        if (ok( exists( $args{ url_to_content }{ $url } ), "fetched $url as expected" )) {
            return $args{ url_to_content }{ $url };
        }
        return;
    });

    my $cmd_override = Sub::Override->new( "${PACKAGE}::run_timed_cmd", sub {
        my ($cmd_ref, %options) = @_;

        my @cmd = @{ $cmd_ref };

        local $LIST_SEPARATOR = '] [';
        my $cmd_key = "[@cmd]";

        my $cv = AnyEvent->condvar();

        my $data = $args{ cmd }{ $cmd_key };

        if (ok( $data, "ran $cmd_key as expected" )) {
            # copy output data into output...
            foreach my $fd (grep { />/ } keys %{ $data }) {
                if ($options{ $fd }) {
                    ${$options{ $fd }} = $data->{ $fd };
                }
            }

            # ...and verify input data against expected
            foreach my $fd (grep { /</ } keys %{ $data }) {
                if (ok( exists( $options{ $fd } ), "$fd passed as expected" )) {
                    is( ${$options{ $fd }}, $data->{ $fd }, "$fd content as expected" );
                }
            }

            $cv->send( $data->{ exitcode } || 0 );
        } else {
            my @cmds = keys %{ $args{ cmd } };
            local $LIST_SEPARATOR = "\n  ";
            diag( "expected commands:\n  @cmds" );
            $cv->send( -1 );
        }

        return $cv;
    });

    return {
        fetch_mock => $fetch_override,
        cmd_mock => $cmd_override,
    };
}

sub touch
{
    my (%args) = @_;
    my $filename = $args{ filename } || confess;
    my $mtime = $args{ mtime } || confess;

    # Make sure the file exists
    {
        open( my $fh, '>', $filename ) || die "open $filename: $!";
        close( $fh ) || die "close $filename: $!";
    }

    utime( time(), $mtime, $filename ) || die "utime $filename: $!";

    return;
}

sub test_new_build
{
    {
        my $url_base = 'quux/baz';
        my $tempdir = tempdir( 'qt-jenkins-ci-test.XXXXXX', TMPDIR => 1, CLEANUP => 1 );

        # make some fake property files to test that old ones are cleaned up
        touch(
            filename => catfile( $tempdir, 'qt-ci-old1.properties' ),
            mtime => (time() - 60*60*24*7),
        );
        touch(
            filename => catfile( $tempdir, 'qt-ci-old2.properties' ),
            mtime => (time() - 60*60*24*7),
        );
        touch(
            filename => catfile( $tempdir, 'qt-ci-not-old.properties' ),
            mtime => time(),
        );

        my $mock = do_mocks(
            url_to_content => {

                "$url_base/api/json?tree=activeConfigurations[name],scm[userRemoteConfigs[url,refspec]]"
                =>
                <<'END_JSON'
{
    "scm": {
        "userRemoteConfigs": [
            {
                "url":"ssh://integrator@gerrit.example.com:1234/test/project",
                "refspec":"+refs/staging/somebranch:refs/remotes/origin/somebranch-staging"
            }
        ]
    },
    "activeConfigurations": [
        {"name":"config_1"},
        {"name":"config_2"}
    ]
}
END_JSON

            },

            cmd => {
                '[ssh] [-oBatchMode=yes] [-p] [1234] [integrator@gerrit.example.com] [gerrit] [staging-new-build] '
               .'[--build-id] [jenkins-Some_Job-137] [--project] [test/project] [--staging-branch] [somebranch]'
                =>
                { exitcode => 0 },

                '[git] [ls-remote] [ssh://integrator@gerrit.example.com:1234/test/project] [refs/builds/jenkins-Some_Job-137]'
                =>
                { exitcode => 0, '>' => '74726d1447c09b56341b17e20dded8332c50467e        refs/builds/jenkins-Some_Job-137' },
            }
        );

        local $ENV{ JOB_URL } = 'quux/baz';
        local $ENV{ JOB_NAME } = 'Some_Job';
        local $ENV{ BUILD_NUMBER } = 137;

        my $obj = $PACKAGE->new();
        $obj->run(
            'new_build',
            '--properties-dir', $tempdir
        );

        # Should have deleted old property files ...
        ok( ! -e catfile( $tempdir, 'qt-ci-old1.properties' ), 'old property file deleted [1]' );
        ok( ! -e catfile( $tempdir, 'qt-ci-old2.properties' ), 'old property file deleted [2]' );

        # Should not have deleted newer property file
        ok( -e catfile( $tempdir, 'qt-ci-not-old.properties' ), 'newer property file not deleted' );

        # Should have created a series of property files...
        my $expected_content = <<'END_CONTENT';
qt_ci_gerrit_branch=somebranch
qt_ci_gerrit_build_id=jenkins-Some_Job-137
qt_ci_gerrit_git_url=ssh://integrator@gerrit.example.com:1234/test/project
qt_ci_gerrit_host=gerrit.example.com
qt_ci_gerrit_port=1234
qt_ci_gerrit_project=test/project
qt_ci_gerrit_user=integrator
qt_ci_jenkins_build_number=137
qt_ci_jenkins_job_name=Some_Job
END_CONTENT

        foreach my $cfg (qw(config_1 config_2)) {
            my $filename = "qt-ci-jenkins-$ENV{JOB_NAME}-${cfg}-$ENV{BUILD_NUMBER}.properties";
            my $full_filename = catfile( $tempdir, $filename );
            ok( -e $full_filename, "$filename created" );
            my $content = read_file( $full_filename ) || die;
            is( $content, $expected_content, "$filename content as expected" );
        }
    }

    # TODO: insert testing of error or unusual cases here

    return;
}

sub test_complete_build
{
    {
        my $url_base = "http://jenkins.example.com/job/Some_Job";
        my $job_json = <<'END_JSON';
{
    "scm": {
        "userRemoteConfigs": [
            {
                "url":"ssh://codereview.example.com:29418/other/project",
                "refspec":"+refs/staging/branch:refs/remotes/origin/branch-staging"
            }
        ]
    },
    "activeConfigurations": [
        {"name":"config_X"},
        {"name":"config_Y"},
        {"name":"config_Z"}
    ]
}
END_JSON

        my $mock = do_mocks(
            url_to_content => {

                "$url_base/api/json?tree=activeConfigurations[name],scm[userRemoteConfigs[url,refspec]]"
                =>
                $job_json

                ,

                "$url_base/5/api/json?tree=result"
                =>
                '{"result":"SUCCESS"}',

            },

            cmd => {
                "[$SUMMARIZE_JENKINS_BUILD] [--url] [http://jenkins.example.com/job/Some_Job/5]"
                =>
                { exitcode => 0, '>' => '(fake summary)' }

                ,

                '[ssh] [-oBatchMode=yes] [-p] [29418] [codereview.example.com] [gerrit] '
               .'[staging-approve] [--branch] [branch] [--build-id] [jenkins-Some_Job-5] '
               .'[--project] [other/project] [--result] [pass] [--message] [-]'
                =>
                { exitcode => 0, '<' => '(fake summary)' }
            }

        );

        local $ENV{ JOB_URL } = $url_base;
        local $ENV{ JOB_NAME } = 'Some_Job';
        local $ENV{ BUILD_NUMBER } = 5;
        local $ENV{ BUILD_URL } = $ENV{ JOB_URL } . '/' . $ENV{ BUILD_NUMBER };

        {
            my $obj = $PACKAGE->new();
            $obj->run(
                'complete_build',
            );
        }

        # OK, now try again with a failing build
        undef $mock;
        $mock = do_mocks(
            url_to_content => {

                "$url_base/api/json?tree=activeConfigurations[name],scm[userRemoteConfigs[url,refspec]]"
                =>
                $job_json

                ,

                "$url_base/5/api/json?tree=result"
                =>
                '{"result":"FAILURE"}',

            },

            cmd => {
                "[$SUMMARIZE_JENKINS_BUILD] [--url] [http://jenkins.example.com/job/Some_Job/5]"
                =>
                { exitcode => 0, '>' => '(fake summary)' }

                ,

                '[ssh] [-oBatchMode=yes] [-p] [29418] [codereview.example.com] [gerrit] '
               .'[staging-approve] [--branch] [branch] [--build-id] [jenkins-Some_Job-5] '
               .'[--project] [other/project] [--result] [fail] [--message] [-]'
                =>
                { exitcode => 0, '<' => '(fake summary)' }
            }

        );

        {
            my $obj = $PACKAGE->new();
            $obj->run(
                'complete_build',
            );
        }
    }

    # TODO: insert testing of error or unusual cases here

    return;
}

# main entry point
sub run
{
    plan( skip_all => "qt-jenkins-ci.pl is not supported on $OSNAME" ) if ($OSNAME =~ m{win32}i);

    {
        # while loading $SCRIPT, put FindBin::Bin to the directory of the script (not the test)
        local $FindBin::Bin = realpath catfile( $FindBin::Bin, '..' );
        ok( do $SCRIPT, "$PACKAGE loads OK" ) || diag("\$@ - $@, \$! - $!");
    }

    test_new_build();
    test_complete_build();
    done_testing();

    return;
}

run() unless caller;
1;
