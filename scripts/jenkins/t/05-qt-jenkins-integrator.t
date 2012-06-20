#!/usr/bin/env perl
#############################################################################
##
## Copyright (C) 2012 Digia Plc and/or its subsidiary(-ies).
## Contact: http://www.qt-project.org/legal
##
## This file is part of the Quality Assurance module of the Qt Toolkit.
##
## $QT_BEGIN_LICENSE:LGPL$
## Commercial License Usage
## Licensees holding valid commercial Qt licenses may use this file in
## accordance with the commercial license agreement provided with the
## Software or, alternatively, in accordance with the terms contained in
## a written agreement between you and Digia.  For licensing terms and
## conditions see http://qt.digia.com/licensing.  For further information
## use the contact form at http://qt.digia.com/contact-us.
##
## GNU Lesser General Public License Usage
## Alternatively, this file may be used under the terms of the GNU Lesser
## General Public License version 2.1 as published by the Free Software
## Foundation and appearing in the file LICENSE.LGPL included in the
## packaging of this file.  Please review the following information to
## ensure the GNU Lesser General Public License version 2.1 requirements
## will be met: http://www.gnu.org/licenses/old-licenses/lgpl-2.1.html.
##
## In addition, as a special exception, Digia gives you certain additional
## rights.  These rights are described in the Digia Qt LGPL Exception
## version 1.1, included in the file LGPL_EXCEPTION.txt in this package.
##
## GNU General Public License Usage
## Alternatively, this file may be used under the terms of the GNU
## General Public License version 3.0 as published by the Free Software
## Foundation and appearing in the file LICENSE.GPL included in the
## packaging of this file.  Please review the following information to
## ensure the GNU General Public License version 3.0 requirements will be
## met: http://www.gnu.org/copyleft/gpl.html.
##
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
use Test::More;
use URI;

use lib catfile( $FindBin::Bin, qw(.. .. lib perl5) );

use QtQA::Test::More qw(create_mock_command);

my $SCRIPT = catfile( $FindBin::Bin, qw(.. qt-jenkins-integrator.pl) );
my $PACKAGE = 'QtQA::GerritJenkinsIntegrator';
my $SOON = .1;  # a small amount of time

if ($OSNAME =~ m{win32}i) {
    plan skip_all => "$PACKAGE is not supported on $OSNAME";
}

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
    my $out_state = $args{ out_state } || croak 'missing out_state';
    my $out_stash = $args{ out_stash };
    my $config = $args{ config } || $object->{ config };
    my $label = $args{ label } || 'basic';
    my $mock_git = $args{ mock_git };
    my $mock_ssh = $args{ mock_ssh };
    my $logs = $args{ logs };
    my $gerrit_events = $args{ gerrit_events };

    local $ENV{ PATH } = $ENV{ PATH };
    local $object->{ config } = $config;

    my @mockdirs;
    if ($mock_git) {
        push @mockdirs, mock_cmd( 'git', @{ $mock_git } );
    }
    if ($mock_ssh) {
        push @mockdirs, mock_cmd( 'ssh', @{ $mock_ssh } );
    }
    if (@mockdirs) {
        Env::Path->PATH->Prepend( @mockdirs );
    }

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

    subtest "$caller_name [$label]" => sub {
        my $sub_name = "do_state_$in_state";
        $sub_name =~ s{-}{_}g;
        my $sub_ref = $object->can( $sub_name );
        ok( $sub_ref, "$in_state is a known state" ) || return;

        %stash = %{ $in_stash };
        my $next_state = $sub_ref->( $object, $project_id, \%stash );

        is( $next_state, $out_state, "$in_state -> $out_state [$label]" );

        if ($out_stash) {
            is_deeply( \%stash, $out_stash, "stash [$label]" );
        }

        if ($logs) {
            is_deeply( \@logs, $logs, "logs [$label]" );
        }
    };

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

    return;
}

sub run
{
    test_states();
    return;
}

run();
done_testing();

