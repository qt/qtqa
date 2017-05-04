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

use strict;
use warnings;

=head1 NAME

10-summarize-jenkins-build.t - simple test for summarize-jenkins-build.pl

=head1 SYNOPSIS

  perl 10-summarize-jenkins-build.t

This test invokes summarize-jenkins-build.pl with fake input and verifies
the output. Mocking is used to avoid fetching from any remote servers.

=cut

use File::Spec::Functions;
use FindBin;
use Readonly;
use Sub::Override;
use Test::More;
use Test::Warn;

Readonly my $SCRIPT => catfile( $FindBin::Bin, '..', 'summarize-jenkins-build.pl' );
Readonly my $PACKAGE => 'QtQA::App::SummarizeJenkinsBuild';

# expected string separating multiple failed configurations
Readonly my $CFG_SEPARATOR => "\n\n    ============================================================\n\n";

# Do a single test run.
# Accepts the following arguments:
#
#   name => the human-readable name for this test
#   object => QtQA::App::SummarizeJenkinsBuild object
#   url => url to summarize
#   parsed_url => hashref to customize behavior of parse_build_log mocking;
#       keys are URLs, values are one of 'error' to simulate an error (non-zero
#       exit code) or 'empty' to simulate a log from which nothing of value could
#       be parsed. All other URLs succeed with dummy text.
#   warnings_like => arrayref of expected warning patterns
#   fake_json => ref to a hash containing (key,value) pairs, where keys are
#       URLs and values are the fake JSON text to return for a URL
#   expected_output => expected output of the summarize_jenkins_build function
#
sub do_test
{
    my (%args) = @_;

    my $o = $args{ object };
    my $name = $args{ name };
    my $parsed_url = $args{ parsed_url } || {};
    my $warnings_like = $args{ warnings_like } || [];
    my $warnings_count = @{ $warnings_like };

    my @mock_subs;
    if (my $fake_json = $args{ fake_json }) {
        push @mock_subs, Sub::Override->new(
            "${PACKAGE}::get_json_from_url",
            sub {
                my ($url) = @_;
                my $json = $fake_json->{ $url };
                ok( defined( $json ), "$name: $url fetched as expected" );
                return $json;
            },
        );
    }

    # Give parse_build_log.pl some predictable fake output (YAML)
    push @mock_subs, Sub::Override->new(
        "${PACKAGE}::run_parse_build_log",
        sub {
            my ($url) = @_;

            if (my $type = $parsed_url->{ $url }) {
                if ($type eq 'empty') {
                    print "---\n"
                         ."detail: ''\n"
                         ."summary: ~\n\n";
                    return 0;
                }
                elsif ($type eq 'error') {
                    print STDERR "(parse_build_log.pl error for $url)\n";
                    return 1;
                }
                die "invalid testdata: \$parsed_url->{ '$url' } == '$type', expect 'empty' or 'error'";
            }

            print "---\n"
                 ."summary: (parse_build_log.pl summary for $url)\n"
                 ."detail: (parse_build_log.pl detail for $url)\n\n";
            return 0;
        },
    );

    my $output;
    warnings_like {
        $output = $o->summarize_jenkins_build( $args{ url }, $args{ log_url } );
    } $warnings_like, "$name: $warnings_count warning(s) as expected";

    is( $output, $args{ expected_output }, "$name: summarize_jenkins_build output as expected" );

    return;
}

# Run all defined tests, on the given object $o
sub run_object_tests
{
    my ($o) = @_;

    my $url = 'some-url';

    do_test(
        name => 'simple success',
        object => $o,
        url => $url,
        fake_json => {
            $url => '{"number":1,"result":"SUCCESS","fullDisplayName":"quux"}',
        },
        expected_output => 'quux: SUCCESS',
    );

    $url = 'http://example.com/jenkins/123';
    do_test(
        name => 'simple failure',
        object => $o,
        url => $url,
        fake_json => {
            $url => '{"number":2,"result":"FAILURE","fullDisplayName":"bar build 2"}',
        },
        expected_output => 'bar build 2: FAILURE',
    );

    do_test(
        name => 'simple failure with master log',
        object => $o,
        url => $url,
        fake_json => {
            $url => '{"number":3,"result":"FAILURE","fullDisplayName":"bar build 3","url":"fake-url"}',
        },
        expected_output =>
            "(parse_build_log.pl summary for fake-url/consoleText)\n\n"
           ."  (parse_build_log.pl detail for fake-url/consoleText)\n\n"
           ."  Build log: fake-url/consoleText",
    );

    do_test(
        name => 'failure with rebased master log',
        object => $o,
        url => $url,
        log_url => 'http://testresults.example.com/ci',
        fake_json => {
            $url => '{"number":3,"result":"FAILURE","fullDisplayName":"bar build 3","url":"http://example.com/jenkins/job/Some_Job/123"}',
        },
        expected_output =>
            "(parse_build_log.pl summary for http://testresults.example.com/ci/Some_Job/build_00123/log.txt.gz)\n\n"
           ."  (parse_build_log.pl detail for http://testresults.example.com/ci/Some_Job/build_00123/log.txt.gz)\n\n"
           ."  Build log: http://testresults.example.com/ci/Some_Job/build_00123/log.txt.gz",
    );

    do_test(
        name => 'failure with master and configuration logs',
        object => $o,
        url => $url,
        fake_json => {
            $url => <<'END'
{
    "number":4,
    "result":"FAILURE",
    "fullDisplayName":"bar build 4",
    "url":"master-url",
    "runs":[
        {"number":4,"result":"FAILURE","fullDisplayName":"cfg1","url":"cfg1-url"},
        {"number":4,"result":"SUCCESS","fullDisplayName":"cfg2","url":"cfg2-url"},
        {"number":4,"result":"FAILURE","fullDisplayName":"cfg3","url":"cfg3-url"},
        {"number":5,"result":"FAILURE","fullDisplayName":"not-this","url":"not-this-url"}
    ]
}
END
        },
        expected_output =>
            "(parse_build_log.pl summary for cfg1-url/consoleText)\n\n"
           ."  (parse_build_log.pl detail for cfg1-url/consoleText)\n\n"
           ."  Build log: cfg1-url/consoleText"
           .$CFG_SEPARATOR
           ."(parse_build_log.pl summary for cfg3-url/consoleText)\n\n"
           ."  (parse_build_log.pl detail for cfg3-url/consoleText)\n\n"
           ."  Build log: cfg3-url/consoleText"
    );

    do_test(
        name => 'failure with no parseable details',
        object => $o,
        url => $url,
        fake_json => {
            $url => <<'END'
{
    "number":4,
    "result":"FAILURE",
    "fullDisplayName":"bar build 4",
    "url":"master-url",
    "runs":[
        {"number":4,"result":"FAILURE","fullDisplayName":"cfg1","url":"cfg1-url"},
        {"number":4,"result":"SUCCESS","fullDisplayName":"cfg2","url":"cfg2-url"},
        {"number":4,"result":"FAILURE","fullDisplayName":"cfg3","url":"cfg3-url"},
        {"number":5,"result":"FAILURE","fullDisplayName":"not-this","url":"not-this-url"}
    ]
}
END
        },
        parsed_url => { map { +"$_-url/consoleText" => 'empty' } qw(cfg1 cfg2 cfg3) },
        expected_output =>
            # when no details are available, the summary should just contain the jenkins build
            # status and a link to the log
            "cfg1: FAILURE\n"
           ."  Build log: cfg1-url/consoleText"
           .$CFG_SEPARATOR
           ."cfg3: FAILURE\n"
           ."  Build log: cfg3-url/consoleText"
    );

    do_test(
        name => 'failure with rebased master and configuration logs',
        object => $o,
        url => $url,
        log_url => 'http://testresults.example.com/ci',
        fake_json => {
            $url => <<'END'
{
    "number":4,
    "result":"FAILURE",
    "fullDisplayName":"bar build 4",
    "url":"master-url",
    "runs":[
        {"number":4,"result":"FAILURE","fullDisplayName":"cfg1","url":"http://example.com/jenkins/job/bar/key1=val1,cfg=cfg1/4/"},
        {"number":4,"result":"SUCCESS","fullDisplayName":"cfg2","url":"cfg2-url"},
        {"number":4,"result":"FAILURE","fullDisplayName":"cfg3","url":"http://example.com/jenkins/job/bar/./cfg=cfg3/4"},
        {"number":5,"result":"FAILURE","fullDisplayName":"not-this","url":"not-this-url"}
    ]
}
END
        },
        expected_output =>
            # note multi-axis config name is left as-is...
            "(parse_build_log.pl summary for http://testresults.example.com/ci/bar/build_00004/key1=val1,cfg=cfg1/log.txt.gz)\n\n"
           ."  (parse_build_log.pl detail for http://testresults.example.com/ci/bar/build_00004/key1=val1,cfg=cfg1/log.txt.gz)\n\n"
           ."  Build log: http://testresults.example.com/ci/bar/build_00004/key1=val1,cfg=cfg1/log.txt.gz"
           .$CFG_SEPARATOR
            # ... while a config with a single axis is collapsed, useless cfg= prefix removed
           ."(parse_build_log.pl summary for http://testresults.example.com/ci/bar/build_00004/cfg3/log.txt.gz)\n\n"
           ."  (parse_build_log.pl detail for http://testresults.example.com/ci/bar/build_00004/cfg3/log.txt.gz)\n\n"
           ."  Build log: http://testresults.example.com/ci/bar/build_00004/cfg3/log.txt.gz"
    );

    {
        # try --force-jenkins-host and --force-jenkins-port
        local $o->{ force_jenkins_host } = 'forced-host';
        local $o->{ force_jenkins_port } = 999;
        # --ignore-aborted should have no effect here
        local $o->{ ignore_aborted } = 1;
        do_test(
            name => 'failure with rebased master and configuration logs, log force and fallback',
            object => $o,
            url => $url,
            log_url => 'http://testresults.example.com/ci',
            warnings_like => [
                qr{
                    \Qhttp://testresults.example.com/ci/bar/build_00004/key1=val1,cfg=cfg1/log.txt.gz\E
                    .*
                    \Qparse_build_log exited with status 1\E
                }xms
            ],
            parsed_url => { 'http://testresults.example.com/ci/bar/build_00004/key1=val1,cfg=cfg1/log.txt.gz' => 'error' },
            fake_json => {
                'http://forced-host:999/jenkins/123' => <<'END'
{
    "number":4,
    "result":"FAILURE",
    "fullDisplayName":"bar build 4",
    "url":"master-url",
    "runs":[
        {"number":4,"result":"FAILURE","fullDisplayName":"cfg1","url":"http://example.com/jenkins/job/bar/key1=val1,cfg=cfg1/4/"},
        {"number":4,"result":"SUCCESS","fullDisplayName":"cfg2","url":"cfg2-url"},
        {"number":4,"result":"FAILURE","fullDisplayName":"cfg3","url":"http://example.com/jenkins/job/bar/cfg=cfg3/4"},
        {"number":5,"result":"FAILURE","fullDisplayName":"not-this","url":"not-this-url"}
    ]
}
END
            },
            expected_output =>
                # we simulated an error on the testresults host here, so parse_build_log was run directly on jenkins,
                # but the link passed to gerrit is still the testresults link.
                "(parse_build_log.pl summary for http://forced-host:999/jenkins/job/bar/key1=val1,cfg=cfg1/4/consoleText)\n\n"
               ."  (parse_build_log.pl detail for http://forced-host:999/jenkins/job/bar/key1=val1,cfg=cfg1/4/consoleText)\n\n"
               ."  Build log: http://testresults.example.com/ci/bar/build_00004/key1=val1,cfg=cfg1/log.txt.gz"
               .$CFG_SEPARATOR
               ."(parse_build_log.pl summary for http://testresults.example.com/ci/bar/build_00004/cfg3/log.txt.gz)\n\n"
               ."  (parse_build_log.pl detail for http://testresults.example.com/ci/bar/build_00004/cfg3/log.txt.gz)\n\n"
               ."  Build log: http://testresults.example.com/ci/bar/build_00004/cfg3/log.txt.gz"
        );
    }

    do_test(
        name => 'aborted ignores failure logs',
        object => $o,
        url => $url,
        fake_json => {
            $url => <<'END'
{
    "number":5,
    "result":"ABORTED",
    "fullDisplayName":"bar build 5",
    "url":"master-url",
    "runs":[
        {"number":5,"result":"FAILURE","fullDisplayName":"cfg1","url":"cfg1-url"},
        {"number":5,"result":"SUCCESS","fullDisplayName":"cfg2","url":"cfg2-url"},
        {"number":5,"result":"FAILURE","fullDisplayName":"cfg3","url":"cfg3-url"},
        {"number":6,"result":"FAILURE","fullDisplayName":"not-this","url":"not-this-url"}
    ]
}
END
        },
        expected_output => 'bar build 5: ABORTED',
    );

    {
        local $o->{ ignore_aborted } = 1;
        do_test(
            name => '--ignore-aborted extracts failures from ABORTED build',
            object => $o,
            url => $url,
            fake_json => {
                $url => <<'END'
{
    "number":5,
    "result":"ABORTED",
    "fullDisplayName":"bar build 5",
    "url":"master-url",
    "runs":[
        {"number":5,"result":"FAILURE","fullDisplayName":"cfg1","url":"cfg1-url"},
        {"number":5,"result":"SUCCESS","fullDisplayName":"cfg2","url":"cfg2-url"},
        {"number":5,"result":"FAILURE","fullDisplayName":"cfg3","url":"cfg3-url"},
        {"number":6,"result":"FAILURE","fullDisplayName":"not-this","url":"not-this-url"}
    ]
}
END
            },
            expected_output =>
                "(parse_build_log.pl summary for cfg1-url/consoleText)\n\n"
               ."  (parse_build_log.pl detail for cfg1-url/consoleText)\n\n"
               ."  Build log: cfg1-url/consoleText"
               .$CFG_SEPARATOR
               ."(parse_build_log.pl summary for cfg3-url/consoleText)\n\n"
               ."  (parse_build_log.pl detail for cfg3-url/consoleText)\n\n"
               ."  Build log: cfg3-url/consoleText"
        );
    }

    {
        local $o->{ yaml } = 1;
        my $formatted =
            "(parse_build_log.pl summary for fake-url/consoleText)\n\n"
           ."  (parse_build_log.pl detail for fake-url/consoleText)\n\n"
           ."  Build log: fake-url/consoleText";
        my $yaml_formatted = $formatted;
        $yaml_formatted =~ s{^}{  }mg;

        do_test(
            name => 'simple failure with master log [yaml]',
            object => $o,
            url => $url,
            fake_json => {
                $url => '{"number":3,"result":"FAILURE","fullDisplayName":"bar build 3","url":"fake-url"}',
            },
            expected_output =>
                "---\n"
               ."formatted: |-\n$yaml_formatted\n"
               ."runs:\n"
               ."  - detail: (parse_build_log.pl detail for fake-url/consoleText)\n"
               ."    summary: (parse_build_log.pl summary for fake-url/consoleText)\n"
        );

        $formatted =
            "(parse_build_log.pl summary for cfg1-url/consoleText)\n\n"
           ."  (parse_build_log.pl detail for cfg1-url/consoleText)\n\n"
           ."  Build log: cfg1-url/consoleText"
           .$CFG_SEPARATOR
           ."(parse_build_log.pl summary for cfg3-url/consoleText)\n\n"
           ."  (parse_build_log.pl detail for cfg3-url/consoleText)\n\n"
           ."  Build log: cfg3-url/consoleText";
        $yaml_formatted = $formatted;
        $yaml_formatted =~ s{^}{  }mg;

        do_test(
            name => 'failure with master and configuration logs [yaml]',
            object => $o,
            url => $url,
            fake_json => {
                $url => <<'END'
{
    "number":4,
    "result":"FAILURE",
    "fullDisplayName":"bar build 4",
    "url":"master-url",
    "runs":[
        {"number":4,"result":"FAILURE","fullDisplayName":"cfg1","url":"cfg1-url"},
        {"number":4,"result":"SUCCESS","fullDisplayName":"cfg2","url":"cfg2-url"},
        {"number":4,"result":"FAILURE","fullDisplayName":"cfg3","url":"cfg3-url"},
        {"number":5,"result":"FAILURE","fullDisplayName":"not-this","url":"not-this-url"}
    ]
}
END
            },
            expected_output =>
                "---\n"
               ."formatted: |-\n$yaml_formatted\n"
               ."runs:\n"
               ."  - detail: (parse_build_log.pl detail for cfg1-url/consoleText)\n"
               ."    summary: (parse_build_log.pl summary for cfg1-url/consoleText)\n"
               ."  - detail: (parse_build_log.pl detail for cfg3-url/consoleText)\n"
               ."    summary: (parse_build_log.pl summary for cfg3-url/consoleText)\n"
        );

        $formatted =
            "cfg1: FAILURE\n"
           ."  Build log: cfg1-url/consoleText"
           .$CFG_SEPARATOR
           ."cfg3: FAILURE\n"
           ."  Build log: cfg3-url/consoleText";
        $yaml_formatted = $formatted;
        $yaml_formatted =~ s{^}{  }mg;

        do_test(
            name => 'failure with no parseable details [yaml]',
            object => $o,
            url => $url,
            fake_json => {
                $url => <<'END'
{
    "number":4,
    "result":"FAILURE",
    "fullDisplayName":"bar build 4",
    "url":"master-url",
    "runs":[
        {"number":4,"result":"FAILURE","fullDisplayName":"cfg1","url":"cfg1-url"},
        {"number":4,"result":"SUCCESS","fullDisplayName":"cfg2","url":"cfg2-url"},
        {"number":4,"result":"FAILURE","fullDisplayName":"cfg3","url":"cfg3-url"},
        {"number":5,"result":"FAILURE","fullDisplayName":"not-this","url":"not-this-url"}
    ]
}
END
            },
            parsed_url => { map { +"$_-url/consoleText" => 'empty' } qw(cfg1 cfg2 cfg3) },
            expected_output =>
                "---\n"
               ."formatted: |-\n$yaml_formatted\n"
               ."runs:\n"
               ."  - detail: ''\n"
               ."    summary: 'cfg1: FAILURE'\n"
               ."  - detail: ''\n"
               ."    summary: 'cfg3: FAILURE'\n"
        );

        do_test(
            name => 'aborted [yaml]',
            object => $o,
            url => $url,
            fake_json => {
                $url => <<'END'
{
    "number":5,
    "result":"ABORTED",
    "fullDisplayName":"bar build 5",
    "url":"master-url",
    "runs":[
        {"number":5,"result":"FAILURE","fullDisplayName":"cfg1","url":"cfg1-url"},
        {"number":5,"result":"SUCCESS","fullDisplayName":"cfg2","url":"cfg2-url"},
        {"number":5,"result":"FAILURE","fullDisplayName":"cfg3","url":"cfg3-url"},
        {"number":6,"result":"FAILURE","fullDisplayName":"not-this","url":"not-this-url"}
    ]
}
END
            },
            expected_output =>
                "---\n"
               ."formatted: 'bar build 5: ABORTED'\n"
               ."runs: []\n"
        );
    }

    return;
}

# main entry point
sub run
{
    ok( do $SCRIPT, "$PACKAGE loads OK" )
        || diag $@;

    my $object = $PACKAGE->new( );
    ok( $object, "$PACKAGE created OK" );
    run_object_tests( $object );

    done_testing( );

    return;
}

run() unless caller;
1;
