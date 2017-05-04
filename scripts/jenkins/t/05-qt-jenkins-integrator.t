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

=head1 NAME

05-qt-jenkins-integrator.t - basic test for qt-jenkins-integrator

=head1 DESCRIPTION

This test exercises various CI state functions (do_state_*).
Each state is called individually with a certain set of parameters; behavior from
Jenkins or Gerrit is simulated/mocked, and the test verifies that the system would
transition to the next state as expected, with the expected arguments.

=cut

use strict;
use warnings;

use AnyEvent;
use Carp;
use Coro;
use English qw( -no_match_vars );
use Env::Path;
use File::Spec::Functions;
use File::Temp;
use FindBin;
use JSON;
use Test::Builder;
use Test::Exception;
use Test::More;
use Sub::Override;
use URI;

use lib catfile( $FindBin::Bin, qw(.. .. lib perl5) );

use QtQA::Test::More qw(create_mock_command is_or_like);
use QtQA::WWW::Util qw(www_form_urlencoded);

my $SCRIPT = catfile( $FindBin::Bin, qw(.. qt-jenkins-integrator.pl) );
my $PACKAGE = 'QtQA::GerritJenkinsIntegrator';
my $SOON = .1;  # a small amount of time

if ($OSNAME =~ m{win32}i) {
    plan skip_all => "$PACKAGE is not supported on $OSNAME";
}

# expected query string when looking at the build queue
my $QUEUE_JSON_QUERY_STRING = 'depth=2&tree=builds[number,actions[parameters[name,value]]]';

# expected query string when monitoring a build
my $BUILD_JSON_QUERY_STRING = 'depth=2&tree=building,number,url,result,fullDisplayName,timestamp,duration,runs[building,number,url,result,fullDisplayName,timestamp,duration]';

# base configuration used in tests; override where appropriate
my $GERRIT_BASE = 'ssh://gerrit.example.com';

my %CONFIG = (
    Global => {
        # default is to poll very fast to keep test runtime down;
        # tests which are trying to exercise non-poll code paths should
        # locally increase these values.
        StagingQuietPeriod => $SOON,
        StagingMaximumWait => $SOON*10,
        StagingPollInterval => $SOON,
        JenkinsUrl => 'http://jenkins.example.com',
        JenkinsUser => 'jenkinsuser',
        JenkinsToken => 'jenkinstoken',
        JenkinsPollInterval => $SOON,
        JenkinsTriggerPollInterval => $SOON,
        JenkinsTriggerTimeout => $SOON*10,
    },
    prjA => {
        GerritUrl => URI->new("$GERRIT_BASE/prj/prjA"),
        GerritBranch => 'mybranch',
    }
);


my @logs;

require_ok( $SCRIPT );

sub mock_cmd
{
    my ($cmd, @sequence) = @_;

    my $tmpdir = File::Temp->newdir( 'qt-jenkins-integrator-test.XXXXXX', TMPDIR => 1 );

    create_mock_command(
        name => $cmd,
        directory => $tmpdir,
        sequence => \@sequence,
    );

    return $tmpdir;
}

sub mock_http
{
    my ($label, $mock_ref) = @_;
    return unless $mock_ref;

    my $override = Sub::Override->new();
    my $sub = sub {
        my ($method, $url, %args) = @_;
        my $expected = $mock_ref;
        if (ref($expected) eq 'ARRAY') {
            $expected = shift @{ $mock_ref };
        }

        is( $method, $expected->{ method }, "[$label] http method" ) if $expected->{ method };
        is( $url, $expected->{ url }, "[$label] http url" ) if $expected->{ url };
        is_or_like( $args{ body }, $expected->{ body }, "[$label] http body" ) if $expected->{ body };
        return (
            $expected->{ result_body } || q{},
            $expected->{ result_headers } || { Status => 500, Reason => 'no result specified in mock_http' }
        );
    };

    foreach my $to_mock ("${PACKAGE}::blocking_http_request", "QtQA::WWW::Util::blocking_http_request") {
        $override->replace( $to_mock, $sub );
    }

    return $override;
}

# convenience function to create a gerrit stream-events event for test_state_machine
sub gerrit_updated_soon
{
    my ($uri, $project) = @_;
    $uri ||= $GERRIT_BASE;
    $project ||= 'prj/prjA';
    return [
        $SOON,
        $SOON,
        $uri,
        { type => 'ref-updated', refUpdate => { project => $project } }
    ];
}

# Returns a mock Jenkins build object
sub object_for_build
{
    my (%args) = @_;

    my %toplevel;
    my %parameters;

    # each 'run' is itself a build
    my @runs = @{ delete($args{ runs }) || [] };
    @runs = map { object_for_build( %{$_} ) } @runs;

    # permitted toplevel attributes; anything else is a 'parameter'
    foreach my $key (qw(number building result fullDisplayName)) {
        my $value = delete $args{ $key };
        if (defined($value)) {
            $toplevel{ $key } = $value;
        }
    }
    %parameters = %args;

    my $object = \%toplevel;
    while (my ($name, $value) = each %parameters) {
        push @{ $object->{ actions }[0]{ parameters } },
            { name => $name, value => $value };
    }

    if (@runs) {
        $object->{ runs } = \@runs;
    }

    return $object;
}

# Returns a mock Jenkins build object, JSON encoded
sub json_for_build
{
    my (%args) = @_;
    return encode_json object_for_build( %args )
}

# Returns a mock Jenkins object containing multiple builds, JSON encoded
sub json_for_builds
{
    my (@args) = @_;

    my @builds = map { object_for_build( %{ $_ } ) } @args;

    return encode_json( {builds => \@builds} );
}

# Returns a regex for matching the given $pattern as a query string portion
sub qr_query_string
{
    my ($pattern) = @_;
    return qr{
        (?:&|\A)    # beginning of string or of argument
        $pattern
        (?:&|\z)    # end of string or of argument
    }xms;
}

sub query_string_patterns
{
    my (@args) = @_;

    # for the entire string to match exactly this query, every individual pattern must match...
    my @part_patterns = map { qr_query_string($_) } @args;

    # ... and there must be no other query string components
    my $outer_pattern = '\A' . join( '&', map { '[^&]+' } @args ) . '\z';

    return (@part_patterns, qr{$outer_pattern});
}

sub http_responses_for_builds
{
    my ($mock_http_base, @builds) = @_;

    return [
        map {
            +{    # + helps perlcritic parse this as hashref, not block
                %{ $mock_http_base },
                result_headers => {Status => 200},
                result_body => json_for_build( %{$_} ),
            }
        } @builds
    ];
}

# Tests a single state machine function.
#
# 'in' parameters refer to the state input, while 'out' parameters refer
# to the expected state output. Omitted 'out' parameters aren't tested.
#
# The resulting stash is returned in case additional checks are desired.
sub test_state_machine
{
    my (%args) = @_;

    my $object = $args{ object } || croak 'missing object';
    my $project_id = $args{ project_id } || croak 'missing project_id';
    my $in_state = $args{ in_state } || croak 'missing in_state';
    my $in_stash = $args{ in_stash } || {};
    my $out_state = $args{ out_state };
    my $out_stash = $args{ out_stash };
    my $config = $args{ config } || $object->{ config };
    my $label = $args{ label } || 'basic';
    my $mock_git = $args{ mock_git };
    my $mock_ssh = $args{ mock_ssh };
    my $mock_http = $args{ mock_http };
    my $mock_summarize_jenkins_build = $args{ mock_summarize_jenkins_build };
    my $mock_sleep = $args{ mock_sleep };
    my $logs = $args{ logs };
    my $gerrit_events = $args{ gerrit_events };
    my $throws_ok = $args{ throws_ok };

    $label = "$in_state $label";

    # make failures come from caller context
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    local $ENV{ PATH } = $ENV{ PATH };
    local $object->{ config } = $config;

    my @mockdirs;
    my @overrides;
    if ($mock_git) {
        push @mockdirs, mock_cmd( 'git', @{ $mock_git } );
    }
    if ($mock_ssh) {
        push @mockdirs, mock_cmd( 'ssh', @{ $mock_ssh } );
    }
    if ($mock_summarize_jenkins_build) {
        push @mockdirs, mock_cmd( 'fake-summarize-jenkins-build', @{ $mock_summarize_jenkins_build } );
        push @overrides, Sub::Override->new(
            "${PACKAGE}::summarize_jenkins_build_cmd" => sub { 'fake-summarize-jenkins-build' }
        );
    }
    if (@mockdirs) {
        Env::Path->PATH->Prepend( @mockdirs );
    }

    if ($mock_sleep) {
        push @overrides, Sub::Override->new( 'Coro::AnyEvent::sleep' => sub {} );
    }

    push @overrides, mock_http( $label, $mock_http );

    my @gerrit_event_timers = map {
        my ($after, $interval, $uri, $gerrit_event) = @{ $_ };
        if (!ref($uri)) {
            $uri = URI->new( $uri );
        }
        AE::timer( $after, $interval, sub {
            $object->handle_gerrit_stream_event(
                $uri,
                $gerrit_event
            );
        });
    } @{ $gerrit_events || [] };

    my (undef, undef, undef, $caller_name) = caller(1);
    $caller_name =~ s{^.*::}{};

    @logs = ();

    my %stash;

    my $sub_name = "do_state_$in_state";
    $sub_name =~ s{-}{_}g;
    my $sub_ref = $object->can( $sub_name );
    ok( $sub_ref, "[$label] $in_state is a known state" ) || return;

    %stash = %{ $in_stash };
    my $next_state;
    my $run = sub {
        $next_state = $sub_ref->( $object, $project_id, \%stash );
    };
    if ($throws_ok) {
        &throws_ok( $run, $throws_ok, "[$label] throws OK" );
    } else {
        &lives_ok( $run, "[$label] doesn't die" );
    }

    if ($out_state) {
        is( $next_state, $out_state, "[$label] $in_state -> $out_state" );
    }

    if ($out_stash) {
        is_deeply( \%stash, $out_stash, "[$label] stash" );
    }

    if ($logs) {
        is_deeply( \@logs, $logs, "[$label] logs" );
    }

    return \%stash;
}

## no critic Subroutines::RequireArgUnpacking - allows for convenient syntax when overriding %test

sub test_state_wait_until_staging_branch_exists
{
    my (%test) = (
        @_,
        in_state => 'wait-until-staging-branch-exists',
        out_stash => {},
        out_state => 'wait-for-staging',
        logs => [],
    );

    {
        # staging branch eventually exists, discovered by polling
        test_state_machine(
            %test,
            label => 'poll',
            mock_git => [
                {},
                {},
                { stdout => '98921005a7df200cac9e488db4df4bf38ba85478      refs/staging/mybranch' },
            ],
        );
    }

    {
        # branch is discovered by gerrit event, not polling
        # make poll interval large so gerrit events arrive first
        local $CONFIG{ Global }{ StagingPollInterval } = 10;

        test_state_machine(
            %test,
            label => 'non-poll',
            gerrit_events => [
                gerrit_updated_soon(),
            ],
            mock_git => [
                {},
                { stdout => '98921005a7df200cac9e488db4df4bf38ba85478      refs/staging/mybranch' },
            ],
            logs => [ 'woke up by event from gerrit' ],
        );
    }

    return;
}

sub test_state_start
{
    my (%test) = (
        @_,
        in_state => 'start',
        in_stash => {hi => 'there'},
        out_stash => {},    # 'start' always empties the stash
        logs => [],
    );

    {
        test_state_machine(
            %test,
            label => 'no staging branch',
            mock_git => [
                # simulate staging branch doesn't exist (ls-remote has no output)
                {}
            ],
            out_state => 'wait-until-staging-branch-exists'
        );
    }

    {
        test_state_machine(
            %test,
            label => 'staging branch',
            mock_git => [
                # simulate staging branch exists
                { stdout => '98921005a7df200cac9e488db4df4bf38ba85478      refs/staging/mybranch' },
            ],
            out_state => 'wait-for-staging',
        );
    }

    return;
}

sub test_state_wait_for_staging
{
    my (%test) = (
        @_,
        in_state => 'wait-for-staging',
        in_stash => {},
        logs => [],
    );

    {
        # staged changes discovered by polling
        test_state_machine(
            %test,
            label => 'poll',
            mock_ssh => [
                # simulate nothing staged for first couple of staging-ls; then eventually some activity appears
                {},
                {},
                {stdout => qq{some change\n}},
            ],
            out_state => 'wait-for-staging-quiet',
            out_stash => {
                staged => 'some change',
            },
            logs => [],
        );
    }

    {
        # staged changes discovered by gerrit events;
        # put poll interval large so the events arrive first
        local $CONFIG{ Global }{ StagingPollInterval } = 10;

        test_state_machine(
            %test,
            label => 'non-poll',
            mock_ssh => [
                {},
                {stdout => qq{another change\n}},
            ],
            gerrit_events => [
                gerrit_updated_soon(),
            ],
            out_state => 'wait-for-staging-quiet',
            out_stash => {
                staged => 'another change',
            },
            logs => [ 'woke up by event from gerrit' ],
        );
    }


    return;
}

sub test_state_wait_for_staging_quiet
{
    my (%test) = (
        @_,
        in_state => 'wait-for-staging-quiet',
    );

    {
        # polling determines staging branch is stable; start a build
        test_state_machine(
            %test,
            label => 'quiet, poll',
            mock_ssh => [
                # stable staging branch
                ({stdout => 'c'}) x 2
            ],
            in_stash => { staged => 'c' },
            out_stash => { staged => 'c' },
            out_state => 'staging-new-build',
            logs => ['done waiting for staging'],
        );
    }

    {
        # polling, changes keep appearing and disappearing in staging branch;
        # eventually timeout and start a build
        test_state_machine(
            %test,
            label => 'timeout, poll',
            mock_ssh => [
                # content oscillates as things are staged, unstaged
                ({stdout => 'a'}, {stdout => 'ab'}) x 10
            ],
            in_stash => { staged => 'c' },
            out_stash => { staged => 'c' },
            out_state => 'staging-new-build',
        );

        # we don't know exactly how many times 'staging activity occurred' should be logged,
        # it depends on timing; should be a couple at least
        is_deeply( [ @logs[0..2] ], [ ('staging activity occurred.') x 3 ] );
    }

    {
        # non-polling, eventually all changes are unstaged, so return to waiting for staging
        local $CONFIG{ Global }{ StagingPollInterval } = 10;
        local $CONFIG{ Global }{ StagingQuietPeriod } = 20;
        local $CONFIG{ Global }{ StagingMaximumWait } = 60;

        test_state_machine(
            %test,
            label => 'unstaged, non-poll',
            mock_ssh => [
                # content oscillates as things are staged, unstaged, then eventually everything
                # is unstaged
                ({stdout => 'a'}, {stdout => 'ab'}) x 2,
                {},
            ],
            in_stash => { staged => 'c' },
            out_stash => { },
            out_state => 'wait-for-staging',
            gerrit_events => [
                gerrit_updated_soon(),
            ],
        );

        is_deeply( [ @logs[0..3] ], [ ('woke up by event from gerrit', 'staging activity occurred.') x 2 ] );
    }


    return;
}

sub test_state_staging_new_build
{
    my (%test) = (
        @_,
        in_state => 'staging-new-build',
    );

    {
        # succeeds (after an initial error) and moves to check-staged-changes
        my $stash = test_state_machine(
            %test,
            label => 'success',
            mock_ssh => [
                # fake an error to ensure we can recover
                {stderr => q{some error}, exitcode => 2},
                {}
            ],
            in_stash => {},
            out_state => 'check-staged-changes',
        );

        # build ref should be exported to stash
        my $build_ref = $stash->{ build_ref };
        ok( $build_ref, 'build ref is set' );
        like( $build_ref, qr{^refs/builds/mybranch_\d+$}, 'build ref looks OK' );

        my $warning = shift @logs;
        like( $warning, qr{command \[ssh\].*\[staging-new-build\].*exited with status \d+ \[retry}, 'retried ssh OK' );

        is_deeply( \@logs, ["created build ref $build_ref"], 'logs' );
    }

    return;
}

sub test_state_check_staged_changes
{
    my (%test) = (
        @_,
        in_state => 'check-staged-changes',
    );

    {
        # check staged changes always proceeds to trigger jenkins
        test_state_machine(
            %test,
            mock_ssh => [
                {stdout => qq{some stuff\nmore stuff\n}},
            ],
            in_stash => {build_ref => 'refs/builds/mybranch_1234'},
            out_state => 'trigger-jenkins',
            stash => {staged => qq{some stuff\nmore stuff}},
            logs => [],
        );
    }

    return;
}

sub test_state_trigger_jenkins
{
    my (%test) = (
        @_,
        in_state => 'trigger-jenkins',
        in_stash => {build_ref => 'refs/builds/somebuild'},
    );

    # we expect the following HTTP request to be sent out
    # TODO: verify the postdata
    my %mock_http_base = (
        method => 'POST',
        url => 'http://jenkins.example.com/job/prjA/buildWithParameters',
        body => [query_string_patterns(
            qr/qt_ci_request_id=[0-9a-f]{8}/,
            quotemeta(www_form_urlencoded(qt_ci_git_url => 'ssh://gerrit.example.com/prj/prjA')),
            www_form_urlencoded(qt_ci_git_ref => 'refs/builds/somebuild'),
        )]
    );

    {
        test_state_machine(
            %test,
            label => 'error',
            mock_http => { %mock_http_base, result_headers => { Status => 404, Reason => 'frobnitz' } },
            throws_ok => qr{new build for prjA failed: 404 frobnitz},
        );
    }

    {
        my $stash = test_state_machine(
            %test,
            label => 'success',
            mock_http => { %mock_http_base, result_headers => { Status => 200 } },
            out_state => 'wait-for-jenkins-build-active',
        );
        like( $stash->{ request_id }, qr{\A[0-9a-f]{8}\z}, 'request_id is set' );
    }
}

sub test_state_wait_for_jenkins_build_active
{
    my (%test) = (
        @_,
        in_state => 'wait-for-jenkins-build-active',
        in_stash => { request_id => 'a1b2c3d4' },
    );

    # we expect the following HTTP request to be sent out
    my %mock_http_base = (
        method => 'GET',
        url => "http://jenkins.example.com/job/prjA/api/json?$QUEUE_JSON_QUERY_STRING"
    );

    {
        test_state_machine(
            %test,
            label => 'http error',
            mock_http => { %mock_http_base, result_headers => { Status => 503, Reason => 'server down' } },
            throws_ok => qr{server down},
        );
    }

    {
        test_state_machine(
            %test,
            label => 'not json error',
            mock_http => {
                %mock_http_base,
                result_headers => { Status => 200 },
                result_body => "this ain't json",
            },
            throws_ok => qr{.},
        );
    }

    {
        test_state_machine(
            %test,
            label => 'missing data error',
            mock_http => {
                %mock_http_base,
                result_headers => { Status => 200 },
                result_body => '{"builds":{"incorrect":"data"}}',
            },
            throws_ok => qr{JSON schema error},
        );
    }

    {
        test_state_machine(
            %test,
            label => 'timeout',
            mock_http => {
                %mock_http_base,
                result_headers => { Status => 200 },
                result_body => json_for_builds(
                    # some builds, but not the right ones
                    {number => 41, qt_ci_request_id => 'aabbccdd'},
                    {number => 42, qt_ci_request_id => 'eeff0011'},
                ),
            },
            throws_ok => qr{Jenkins did not start a build with request ID a1b2c3d4},
        );
    }

    {
        test_state_machine(
            %test,
            label => 'success',
            mock_http => {
                %mock_http_base,
                result_headers => { Status => 200 },
                result_body => json_for_builds(
                    # a couple of unrelated builds, plus the real one
                    {number => 41, qt_ci_request_id => 'aabbccdd'},
                    {number => 42, qt_ci_request_id => 'a1b2c3d4'},
                    {number => 43}
                ),
            },
            out_stash => {build_number => 42},
            out_state => 'set-jenkins-build-description',
        );
    }

    return;
}

sub test_state_set_jenkins_build_description
{
    my (%test) = (
        @_,
        in_state => 'set-jenkins-build-description',
        in_stash => {
            build_number => 1234,
            staged => qq{2b63d8d760c80ebf5fc939a35fd133a62bfb3fc2 123,45 do this\n}
                     .qq{63d8d760c80ebf5fc939a35fd133a62bfb3fc22b 67,89 do that\n}
        },
    );

    # we expect the following HTTP request to be sent out
    # TODO: verify the postdata
    my %mock_http_base = (
        method => 'POST',
        url => 'http://jenkins.example.com/job/prjA/1234/submitDescription',
        body => [query_string_patterns(
            quotemeta(www_form_urlencoded(
                description =>
                    qq{Tested changes:<ul>\n}
                   .qq{<li><a href="http://gerrit.example.com/123">http://gerrit.example.com/123</a> [PS45] - do this</li>\n}
                   .qq{<li><a href="http://gerrit.example.com/67">http://gerrit.example.com/67</a> [PS89] - do that</li>\n}
                   .qq{</ul>}
            ))
        )]
    );

    {
        test_state_machine(
            %test,
            label => 'http request fails',
            mock_http => {
                %mock_http_base,
                result_headers => {Status => 503, Reason => 'quux'},
            },
            throws_ok => qr{set description for prjA 1234 failed: 503 quux},
        );
    }

    {
        test_state_machine(
            %test,
            label => 'success',
            out_state => 'monitor-jenkins-build',
            mock_http => {
                %mock_http_base,
                result_headers => {Status => 200},
            }
        );
    }

    return;
}

sub test_state_monitor_jenkins_build
{
    my (%test) = (
        @_,
        in_state => 'monitor-jenkins-build',
        in_stash => {build_number => 1234},
    );

    my %mock_http_base = (
        method => 'GET',
        url => "http://jenkins.example.com/job/prjA/1234/api/json?$BUILD_JSON_QUERY_STRING"
    );

    {
        test_state_machine(
            %test,
            label => 'http error',
            mock_http => {
                %mock_http_base,
                result_headers => {Status => 503, Reason => 'error37'},
            },
            throws_ok => qr{fetch.*: 503 error37},
        );
    }

    {
        test_state_machine(
            %test,
            label => 'json error',
            mock_http => {
                %mock_http_base,
                result_headers => {Status => 200},
                result_body => q{not valid json},
            },
            throws_ok => qr{.*},
        );
    }

    {
        test_state_machine(
            %test,
            label => 'poll, eventually completed build',
            mock_http => http_responses_for_builds(
                \%mock_http_base,
                {number => 1234, building => 1},
                {number => 1234, building => 1, runs => [
                    {
                        number => 1234,
                        building => 0,
                        result => 'FAILED',
                        fullDisplayName => 'some cfg'
                    }
                ]},
                {number => 1234, building => 0},
            ),
            out_state => 'parse-jenkins-build',
        );
    }

    {
        local $CONFIG{ Global }{ JenkinsCancelOnFailure } = 1;
        test_state_machine(
            %test,
            label => 'poll, cancel build',
            mock_http => http_responses_for_builds(
                \%mock_http_base,
                {number => 1234, building => 1},
                {number => 1234, building => 1, runs => [
                    {
                        number => 1234,
                        building => 0,
                        result => 'FAILED',
                        fullDisplayName => 'some cfg'
                    }
                ]},
            ),
            out_state => 'cancel-jenkins-build',
        );
    }

    return;
}

sub test_state_cancel_jenkins_build
{
    my (%test) = (
        @_,
        in_state => 'cancel-jenkins-build',
        in_stash => {
            build => {
                number => 1234,
                url => 'http://jenkinsZ.example.com/job/prjAZ/1234Z',
                building => 1,
            }
        },
    );

    my %mock_http_base = (
        method => 'POST',
        url => $test{ in_stash }{ build }{ url } . '/stop',
    );

    {
        test_state_machine(
            %test,
            label => 'http error',
            mock_http => {
                %mock_http_base,
                result_headers => {Status => 503, Reason => 'error37'},
            },
            throws_ok => qr{cancel prjA build 1234 failed: 503 error37},
        );
    }

    foreach my $code (qw(200 302)) {
        test_state_machine(
            %test,
            label => "success, http $code",
            mock_http => {
                %mock_http_base,
                result_headers => {Status => $code},
            },
            out_state => 'parse-jenkins-build',
            out_stash => {
                build => {
                    %{ $test{ in_stash }{ build } },
                    building => undef,
                    result => 'ABORTED',
                    aborted_by_integrator => 1
                }
            }
        );
    }

    return;
}

sub test_state_parse_jenkins_build
{
    my (%test) = (
        @_,
        in_state => 'parse-jenkins-build',
        in_stash => {
            build_ref => 'refs/builds/testbuild',
            staged => qq{2b63d8d760c80ebf5fc939a35fd133a62bfb3fc2 111,1 do this\n}
                     .qq{63d8d760c80ebf5fc939a35fd133a62bfb3fc22b 22,3 do that\n},
            build => {
                number => 1234,
                url => 'http://jenkinsZ.example.com/job/prjAZ/1234Z',
                result => 'some_result',
            }
        },
    );

    # "Tested changes" text block, for the above stash
    my $tested_changes =
        qq{  Tested changes (refs/builds/testbuild):\n}
       .qq{    http://gerrit.example.com/111 [PS1] - do this\n}
       .qq{    http://gerrit.example.com/22 [PS3] - do that};

    # Portion of in_stash expected to appear unmodified in the out_stash
    my %common_stash = map { $_ => $test{ in_stash }{ $_ } } qw(
        build_ref
        staged
    );

    {
        test_state_machine(
            %test,
            label => 'yaml error',
            mock_summarize_jenkins_build => [
                {stdout => 'hi there'},
            ],
            throws_ok => qr{YAML error:}i,
        );
    }

    {
        test_state_machine(
            %test,
            label => 'success',
            mock_summarize_jenkins_build => [
                {stdout => qq{formatted: build succeeded!\n}},
            ],
            out_state => 'handle-jenkins-build-result',
            out_stash => {
                %common_stash,
                parsed_build => {
                    result => $test{ in_stash }{ build }{ result },
                    formatted =>
                        qq{build succeeded!\n\n$tested_changes}
                }
            },
        );
    }

    {
        test_state_machine(
            %test,
            label => "don't retry on partial set of should_retry",
            mock_summarize_jenkins_build => [{
                stdout =>
                    qq{formatted: build failed!\n}
                   .qq{runs:\n - should_retry: 1\n - should_retry: 0\n}
            }],
            out_state => 'handle-jenkins-build-result',
            out_stash => {
                %common_stash,
                parsed_build => {
                    result => $test{ in_stash }{ build }{ result },
                    formatted =>
                        qq{build failed!\n\n}
                       .qq{  Tested changes (refs/builds/testbuild):\n}
                       .qq{    http://gerrit.example.com/111 [PS1] - do this\n}
                       .qq{    http://gerrit.example.com/22 [PS3] - do that},
                    runs => [{should_retry => 1}, {should_retry => 0}],
                }
            },
        );
    }

    {
        test_state_machine(
            %test,
            label => 'retry when all runs should_retry',
            mock_summarize_jenkins_build => [{
                stdout =>
                    qq{formatted: build failed!\n}
                   .qq{runs:\n - should_retry: 1\n - should_retry: 1\n}
            }],
            out_state => 'handle-jenkins-build-result',
            out_stash => {
                %common_stash,
                parsed_build => {
                    should_retry => 1,
                    result => $test{ in_stash }{ build }{ result },
                    formatted =>
                        qq{build failed!\n\n$tested_changes},
                    runs => [{should_retry => 1}, {should_retry => 1}],
                },
                build_attempt => 2
            },
            mock_sleep => 1,
            logs => [ 'build log indicates we should retry', 'will retry in 32 seconds' ],
        );
    }

    {
        local $CONFIG{ Global }{ BuildAttempts } = 1;
        test_state_machine(
            %test,
            label => 'eventually give up retrying',
            mock_summarize_jenkins_build => [{
                stdout =>
                    qq{formatted: build failed!\n}
                   .qq{runs:\n - should_retry: 1\n - should_retry: 1\n}
            }],
            out_state => 'handle-jenkins-build-result',
            out_stash => {
                %common_stash,
                parsed_build => {
                    result => $test{ in_stash }{ build }{ result },
                    formatted =>
                        qq{build failed!\n\n$tested_changes},
                    runs => [{should_retry => 1}, {should_retry => 1}],
                },
                build_attempt => 1,
            },
            logs => [ 'build log indicates we should retry', 'already tried 1 times, giving up' ],
        );
    }

    return;
}

sub test_state_handle_jenkins_build_result
{
    my (%test) = (
        @_,
        in_state => 'handle-jenkins-build-result',
        in_stash => {
            build_ref => 'refs/builds/testbuild',
            parsed_build => {result => 'SUCCESS'},
        },
    );

    {
        my %out_stash = %{ $test{ in_stash } };
        delete $out_stash{ parsed_build };
        test_state_machine(
            %test,
            label => 'should_retry',
            in_stash => {
                %{ $test{ in_stash } },
                parsed_build => { should_retry => 1 }
            },
            out_state => 'trigger-jenkins',
            out_stash => \%out_stash,
        );
    }

    {
        # TODO: verify the arguments and stdin of staging-approve
        # with a few different builds
        test_state_machine(
            %test,
            label => 'OK',
            mock_ssh => [
                # simulate an error, then recover from it
                {stderr => 'some error!', exitcode => 2},
                {exitcode => 0},
            ],
            out_state => 'send-mail',
        );
    }

    return;
}

sub test_state_send_mail
{
    my (%test) = (
        @_,
        in_state => 'send-mail',
        out_state => 'start',
        in_stash => {
            build_ref => 'refs/builds/testbuild',
            parsed_build => {
                result => 'SUCCESS',
                formatted => 'build succeeded!',
            },
        },
    );

    my $mailmsg_count = 0;
    my $override = Sub::Override->new(
        'Mail::Sender::MailMsg' => sub {
            # TODO: actually verify the content of the mails.
            ++$mailmsg_count;
        }
    );

    {
        local $CONFIG{ Global }{ MailTo } = undef;
        test_state_machine(
            %test,
            label => 'do nothing if mail disabled',
            out_state => 'start',
        );
        is( $mailmsg_count, 0, 'no mail sent' );
    }

    {
        local $CONFIG{ Global }{ MailTo } = ['addr1@example.com','addr2@example.com'],
        test_state_machine(
            %test,
            label => 'send a mail if enabled',
            out_state => 'start',
        );
        is( $mailmsg_count, 1, 'one mail sent' );
    }

    return;
}

sub test_state_error
{
    my (%test) = (
        @_,
        in_state => 'error',
        in_stash => {
            state => {
                name => 'some-state',
                stash => { foo => 'bar' },
            }
        },
        mock_sleep => 1,
    );

    {
        test_state_machine(
            %test,
            label => 'retry',
            in_stash => {
                %{ $test{ in_stash } },
                error => 'some error!',
                error_count => 3,
            },
            out_state => 'some-state',
            out_stash => {
                %{ $test{ in_stash }{ state }{ stash }},
                error_count => 3,
            },
            logs => ['some error!, retry in 8 seconds', 'resuming from error into state some-state'],
        );
    }

    {
        # This test will suspend the calling coro, so we need to run it from its own coro
        # (otherwise we'll deadlock).
        my $coro = async {
            local $Coro::current->{ desc } = 'test coro';
            test_state_machine(
                %test,
                label => 'suspend',
                in_stash => {
                    %{ $test{ in_stash } },
                    error => 'some error!',
                    error_count => 1000,
                },
                out_state => 'some-state',
                out_stash => {
                    %{ $test{ in_stash }{ state }{ stash }},
                    error_count => 0,
                },
                logs => [
                    'some error!, occurred repeatedly.',
                    "Suspending for investigation; to resume: kill -USR2 $$",
                    'resuming from error into state some-state',
                ],
            );
        };

        # keep sending the 'wake up' signal until it wakes up
        my $timer = AE::timer( $SOON, $SOON, sub {
            $test{ object }->resume_from_error_signal()->broadcast()
        } );

        $coro->join();
    }

    return;
}

sub test_states
{
    my $object = $PACKAGE->new();
    ok( $object );

    # Set up a logger which injects all messages back to us
    local $object->{ logger } = Log::Dispatch->new(
        outputs => [ ['Null', min_level => 'debug'] ],
        callbacks => sub {
            my (%data) = @_;
            push @logs, $data{ message };
            return $data{ message };
        }
    );

    # pass warnings through logger, as done in $PACKAGE::run()
    local $Coro::State::WARNHOOK = sub {
        $object->logger()->warning( @_ );
    };

    # base parameters for test_state_machine, to be overridden where appropriate.
    my %base_test = (
        object => $object,
        config => \%CONFIG,
        project_id => 'prjA',
    );

    test_state_start( %base_test );
    test_state_wait_until_staging_branch_exists( %base_test );
    test_state_wait_for_staging( %base_test );
    test_state_wait_for_staging_quiet( %base_test );
    test_state_staging_new_build( %base_test );
    test_state_check_staged_changes( %base_test );
    test_state_trigger_jenkins( %base_test );
    test_state_wait_for_jenkins_build_active( %base_test );
    test_state_set_jenkins_build_description( %base_test );
    test_state_monitor_jenkins_build( %base_test );
    test_state_cancel_jenkins_build( %base_test );
    test_state_parse_jenkins_build( %base_test );
    test_state_handle_jenkins_build_result( %base_test );
    test_state_send_mail( %base_test );
    test_state_error( %base_test );

    return;
}

sub run
{
    test_states();
    return;
}

run();
done_testing();

