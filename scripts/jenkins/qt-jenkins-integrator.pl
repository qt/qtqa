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

qt-jenkins-integrator.pl - Qt CI system, Gerrit quality gate using Jenkins

=head1 SYNOPSIS

  $ ./qt-jenkins-integrator.pl --config <configuration_file> [ -o key=val ... ]

Run the Qt CI system over some projects.
A configuration file is mandatory.

=head2 OPTIONS

=over

=item --config <configuration_file>

Path to configuration file.
See L<CONFIGURATION> for more information.

=item -o key=val

Set some option, overriding the value in the configuration file.
See L<CONFIGURATION> for more information.

May be specified multiple times.

=back

=head1 CONFIGURATION

The integrator reads a configuration file using a simple INI-like format:

  [Section1]
  Key1 = Val1
  Key2 = Val2

  [Section2]
  Key1 = Val1
  ...

The configuration file should contain one [Global] section and one section
for each CI project (e.g. [QtBase_master_Integration], [QtDeclarative_master_Integration]).

When set through the -o command-line option, use the syntax "Section.Key=Value"
(example: -o Global.HttpPort=1234).

Supported configuration values are listed below. Most values can be set both in the
[Global] section and for individual projects, in which case the project setting is used.

=over

=item B<JenkinsUrl> [global, project]

Base URL of the Jenkins server (e.g. "http://jenkins.example.com/").

=item B<JenkinsUser> [global, project]

Jenkins user account used for starting/stopping builds.

=item B<JenkinsToken> [global, project]

Password or API token for the configured JenkinsUser. API token is recommended over password.

=item B<JenkinsCancelOnFailure> [global, project]

If true, the integrator will cancel a Jenkins build as soon as any individual configuration
in that build fails. Otherwise, the build will be allowed to complete.

This is a trade-off: aborting if a single configuration fails will improve the CI throughput
but provides less detailed results.

=item B<JenkinsPollInterval> [global, project]

Interval (in seconds) for polling Jenkins builds for updates.

If possible, notifications should be used instead of polling;
see L<JENKINS BUILD NOTIFICATIONS>. If notifications are used, polling occurs
only as a backup in case of problems with the notifications (e.g. notifications
lost due to temporary network issues).

Therefore, if notifications are used, this value can be quite large; otherwise,
it should be small. In fact, the value defaults to something appropriate in both
cases, so it can generally be omitted.

=item B<JenkinsTriggerTimeout> [global, project]

Maximum amount of time (in seconds) Jenkins is expected to take to schedule a
build after being triggered.

Normally, this only takes a few seconds, but certain conditions (such as no available
'master' executor) may cause delays.

Defaults to 15 minutes.

=item B<JenkinsTriggerPollInterval> [global, project]

Poll interval (seconds) to check whether Jenkins has scheduled a build after being
triggered. This is not covered by L<JENKINS BUILD NOTIFICATIONS> and there is no
alternative to polling.

Defaults to 10 seconds.

=item B<MailTo> [global, project]

E-mail recipients for mails sent by the integrator.

The Global MailTo defines recipients for any problems encountered by the integrator,
while the per-project MailTo defines recipients of pass/fail reports for that
project.

If no MailTo option is set, emails are not sent.

=item B<MailFrom> [global, project]

From name and address for emails sent by the integrator.

=item B<MailReplyTo> [global, project]

Reply-To header for emails sent by the integrator.

When MailFrom is an address which does not receive emails, and when sending mails to
a mailing list, it may make sense to set MailReplyTo to the same list, causing
replies to go to the list by default.

=item B<MailSubjectPrefix> [global, project]

A prefix applied to the Subject of each mail sent by the integrator.

For example, setting MailSubjectPrefix=[Qt CI] would result in emails with
subjects of "[Qt CI] pass on <repo>", "[Qt CI] fail on <repo>", etc.

=item B<MailSmtp> [global, project]

SMTP server used when sending mails; defaults to 'localhost'.

=item B<LogBaseSshUrl> [global, project]

Base ssh URL for publishing test logs; if set, build logs from Jenkins will be
copied here by ssh/scp.

Given a base URL of "ssh://user@example.com/www/ci-logs", Jenkins logs would be uploaded to:

  user@example.com:/www/ci-logs/<project>/build_<five_digit_build_number>/<cfg>/log.txt.gz

This naming scheme is currently not configurable.

=item B<LogBaseHttpUrl> [global, project]

Base URL for published test logs, e.g. "http://example.com/ci-logs";
intended to be world-accessible (even if the Jenkins server is not).

This should correspond to the LogBaseSshUrl given above, so that build logs can be
fetched from (e.g.)

  http://example.com/ci-logs/<project>/build_<five_digit_build_number>/<cfg>/log.txt.gz

=item B<HttpPort> [global]

Port number for a Jenkins-style read-only remote API over HTTP.
If omitted, the remote API is not available.

See L<HTTP REMOTE API> for more information.

=item B<TcpPort> [global]

Port number for Jenkins build notification events.
If omitted, notifications are not supported, and polling must be used.

See L<JENKINS BUILD NOTIFICATIONS> for more information.

=item B<AdminTcpPort> [global]

Port number for admin command interface.
If omitted, admin commands are not supported.

See L<ADMINISTRATIVE COMMAND INTERFACE> for more information.

=item B<DebugTcpPort> [global]

Port number opened for debugging connections.

This port may be connected to with telnet and allows arbitrary code to be
executed from within the integrator.
A potential security risk, should only be enabled for debugging purposes.

For more information, connect to the debugger and run the 'help' command,
or see L<Coro::Debug>.

=item B<WorkingDirectory> [global]

Working directory used for this instance of the integrator.

This directory will contain a few small files to maintain the system's state.
If you want to run multiple instances of the integrator, you must use a different
working directory for each.

See L<PERSISTENT STATE> for more information.

=item B<RestartInterval> [global]

Interval, in seconds, after which the integrator will restart itself.
Disabled by default.

Periodic restart may be useful for the following purposes:

=over

=item *

reloading integrator configuration

=item *

loading updated versions of perl modules (for bug fixes)

=item *

as a pre-emptive measure against unexpected bugs (such as long-term resource leaks)

=back

Hint: one day equals ~86400 seconds.

=item B<StagingQuietPeriod> [global, project]

Amount of time, in seconds, for which a staging branch should have no activity before a build
will be triggered.

The staging quiet period serves to ensure that developers have a chance to stage a set of related
changes together; triggering a build instantly after a change is staged is generally undesirable.

=item B<StagingMaximumWait> [global, project]

Maximum amount of time, in seconds, to wait before triggering a build after staging activity has
been detected.

When StagingQuietPeriod is set, this value should also be set to ensure that the CI won't be blocked
if staging activity is occurring continuously (e.g. a malicious person continually staging and un-staging
changes to block the system).

=item B<StagingPollInterval> [global, project]

Interval (in seconds) for polling for staging branch activity.

The integrator normally uses gerrit stream-events to detect staging branch activity; polling
is used only as a backup in case of problems with stream-events (e.g. temporarily dropped connection
to server). Therefore, this should generally be a fairly large value (>15 minutes).

=item B<Enabled> [project]

1 if the project is enabled. Mandatory.

Disabled projects are not used by the integrator in any way.

=item B<GerritUrl> [project]

Full ssh URL to this project's gerrit repository, e.g.

  [QtBase_master_Integration]
  GerritUrl = "ssh://codereview.qt-project.org:29418/qt/qtbase"

=item B<GerritBranch> [project]scripts/jenkins/qt-jenkins-integrator.pl

The branch to be tested and integrated.  Short branch name only
(so "master" rather than "refs/heads/master").

=back

=head3 Example configuration file

Here's a complete example of a configuration file handling a couple of projects.

  [Global]
  JenkinsUrl = "http://jenkins.example.com/"
  JenkinsUser = qt-integration
  #JenkinsToken =  # pass it on the command-line
  MailTo = ci-reports@example.com
  MailReplyTo = ci-reports@example.com
  MailFrom = Qt Continuous Integration System <ci-noreply@example.com>
  LogBaseHttpUrl = "http://testresults.example.com/ci"
  LogBaseSshUrl = "ssh://logs@testresults.example.com/var/www/ci"
  HttpPort = 7181
  TcpPort = 7182
  WorkingDirectory = ~/.qt-ci
  StagingQuietPeriod = 90
  StagingPollInterval = 1800
  StagingMaximumWait = 1800

  [QtBase_master_Integration]
  Enabled = 1
  GerritUrl = "ssh://gerrit.example.com:29418/qt/qtbase"
  GerritBranch = master

  [QtDeclarative_master_Integration]
  Enabled = 1
  GerritUrl = "ssh://gerrit.example.com:29418/qt/qtdeclarative"
  GerritBranch = master

=head1 PERSISTENT STATE

The integrator conceptually runs a state machine for each project covered by CI.

The state of the integrator is stored in a file under the configured WorkingDirectory.
This is a (somewhat) human-readable file, of undefined format.

The state file is written to atomically, and each state machine transition is atomic
(or as close to atomic as can reasonably be expected). Therefore, by design, it is
absolutely fine to kill the integrator script at any time, and it can be expected to
resume from the last known state without errors.

Notably, the state file includes a limited history of states for all projects.
In some cases it may be useful to (I<carefully!>) edit the state file manually, to
'rewind' to an earlier state or otherwise handle some unusual conditions.

The integrator's state can be exported over HTTP in JSON format; see L<HTTP REMOTE API>.

=head1 HTTP REMOTE API

If the HttpPort configuration option is set, the integrator will listen on that port
for connections from HTTP clients.  Upon receiving a request to "/api/json", the
integrator will respond with a dump of the current state in JSON format.

The precise structure of the returned data is currently not documented, and is subject
to change. Roughly, it includes the current state and a history of states for each
project, and recent log messages from the integrator.

Available parameters (passed as an HTTP query string) include:

=over

=item pretty

If "true", whitespace is added to make the output more human-readable; helpful when
attempting to inspect the output manually.

=item since_id

If set to an integer greater than 0, only log messages and project states with an
identifier higher than this will be included.

Each response includes a "last_id" property which is the latest ID of any project state
or log message included in the response.  This value may be passed as the "since_id"
parameter in a subsequent request to receive only the differences between the new
state and old state, which may save a significant amount of network traffic when there
are many projects.

=back


=head1 JENKINS BUILD NOTIFICATIONS

The integrator supports a simple scheme where Jenkins may notify of events by posting
JSON events to the integrator via TCP.

If the TcpPort configuration option is set, the integrator will listen on that port
for connections. It expects each connection to write exactly one JSON object of the
following form:

  {"type":"build-updated","job":"<some_job>"}

Upon receiving such an event, the integrator will check the state of any Jenkins build
it has triggered for the given job. If the integrator hasn't triggered any builds for
the job, the event is ignored.

A Groovy Postbuild script is the recommended method of setting up the Jenkins build
notifications. A simple script like the following is sufficient:

  s = new Socket("integrator.example.com", 7182)
  s << '{"type":"build-updated","job":"Job Name"}'
  s.close()

If build notifications can't be used for some reason (e.g. the Jenkins server can't
open a TCP connection to the machine running this script), polling is used instead,
which introduces some delays and wastes resources.

=head1 ADMINISTRATIVE COMMAND INTERFACE

The integrator supports administrative commands which can be posted as JSON events
via TCP.

If the AdminTcpPort configuration option is set, the integrator will listen on that port
for connections. It expects each connection to write exactly one JSON object of the
following form:

  {"type":"<some-command>","project":"<some_project>","token":"<JenkinsToken>"}

The token is used to authenticate received commands and must match the configured
JenkinsToken. Following commands are supported:

=over

=item remove-state

Remove state and history of project. Can be used when project is disabled or removed
from integrator.

=item reset-state

Reset state of project to 'start'. Can only be used when project is in 'error' state.
Used when project error state is resolved so that previous state cannot be retried.

=back

=head1 ERRORS, SIGNALS, LOGGING

If the integrator experiences some error, it will generally attempt to retry (with some delay).
This helps to automatically recover from temporary network issues or service outages.

If an error occurs repeatedly, it's assumed that some kind of human intervention is needed
to resolve the problem. In this case, the project which experienced the error is suspended.
This means that no further activity takes place until the integrator is requested to resume
suspended projects.

When errors (or warnings) occur, they may be sent via email if a MailTo option is configured.
It is highly recommended to have email logging enabled, as otherwise it will not be clear
when a project has been suspended and needs to be resumed.
Logs will also be sent to the system log on the host running the integrator script.

The integrator script understands the following Unix signals:

=over

=item SIGUSR1

On SIGUSR1, the script will restart itself.  The configuration file will be reloaded;
state will be written to disk and read back again.

=item SIGUSR2

On SIGUSR2, any projects who have been suspended due to error will be resumed.
Currently, it's not possible to select individual projects for resumption.

Note that the suspended state for a project persists over a restart of the integrator,
so it is necessary to resume suspended projects with SIGUSR2 even after a restart.

=back

=cut

package QtQA::GerritJenkinsIntegrator;
use strict;
use warnings;

# should be loaded very early - see docs
if (!caller) {
    require AnyEvent::Watchdog;
}

use AnyEvent::HTTP qw(http_get);
use AnyEvent::HTTPD;
use AnyEvent::Handle;
use AnyEvent::Socket;
use AnyEvent::Util;
use AnyEvent::Watchdog::Util;
use AnyEvent;
use Carp qw( confess croak );
use Config::Tiny;
use Coro::AnyEvent;
use Coro::Util;
use Coro;
use Cwd;
use Data::Alias;
use Data::Dumper;
use Encode::Locale;
use Encode;
use English qw( -no_match_vars );
use Fcntl qw( :flock );
use FindBin;
use File::Basename;
use File::Path qw( mkpath );
use File::Spec::Functions;
use Getopt::Long qw( GetOptionsFromArray );
use HTTP::Headers;
use IO::Compress::Gzip qw( gzip $GzipError );
use IO::Interactive;
use JSON;
use Lingua::EN::Inflect qw( inflect );
use List::MoreUtils qw( all );
use Log::Dispatch;
use Mail::Sender;
use Memoize;
use Pod::Usage;
use Readonly;
use Storable qw( dclone );
use Tie::Persistent;
use Time::Piece;
use Timer::Simple;
use URI;
use YAML::Any;

use autodie;

use feature 'switch';

use lib catfile( $FindBin::Bin, qw(.. lib perl5) );
use QtQA::AnyEvent::Util;
use QtQA::Gerrit;
use QtQA::WWW::Util qw(:all);

our $VERSION = 0.01;

# User-Agent used for HTTP requests/responses
Readonly my $USERAGENT => __PACKAGE__ . "/$VERSION";

Readonly my $SUMMARIZE_JENKINS_BUILD => catfile( $FindBin::Bin, 'summarize-jenkins-build.pl' );

# IDs used in remote API cannot grow larger than this
Readonly my $MAX_ID => 2000000000;

# Max amount of states to hold in state machine history (for remote API)
Readonly my $MAX_HISTORY => 20;

# Max amount of log messages to record (for remote API)
Readonly my $MAX_LOGS => 50;


# ==================================== STATIC ===========================================

# Returns an ISO 8601 timestamp for $time (or the current time) in UTC
sub timestamp
{
    my ($time) = @_;
    $time ||= gmtime();
    return $time->datetime() . 'Z';
}

# Returns base command used for summarizing Jenkins build;
# this is a function so that it may be mocked by tests.
sub summarize_jenkins_build_cmd
{
    return $SUMMARIZE_JENKINS_BUILD;
}

# parse a line of output from gerrit staging-ls
sub parse_staging_ls
{
    my ($line) = @_;

    chomp $line;

    if ($line =~
        m{
            \A
            ([0-9a-f]{40})  # SHA-1
            \s+
            (\d+)           # gerrit change number
            ,
            (\d+)           # gerrit patch set number
            \s+
            (.+)            # one-line changelog
            \z
        }xms
    ) {
        return {
            sha1 => $1,
            change => $2,
            patch_set => $3,
            summary => $4
        };
    }

    return;
}

# Like QtQA::AnyEvent::Util::run_cmd, except:
#  - blocks the current Coro until command completes, and returns a hashref
#    containing status, stdout and stderr (instead of returning a condvar)
#  - enables various useful options by default: retry, croak, cwd
#  - always captures, '>', '2>' hence aren't supported options
#  - includes the stdout/stderr of commands in the croak message, if they fail
#
sub cmd
{
    my ($cmd, %options) = @_;

    $options{ timeout } //= 60*60*30;
    $options{ cwd } //= getcwd();
    $options{ retry } //= 1;
    $options{ 'croak' } //= 1;

    my $stdout;
    my $stderr;
    $options{ '>' } = \$stdout;
    $options{ '2>' } = \$stderr;

    my $cv = QtQA::AnyEvent::Util::run_cmd( $cmd, %options );
    my $status = -1;
    eval {
        $status = $cv->recv();
    };
    if (my $error = $EVAL_ERROR) {
        $error .= "\nstdout:\n$stdout" if $stdout;
        $error .= "\nstderr:\n$stderr" if $stderr;
        die "$error\n";
    }

    return {
        status => $status,
        stdout => $stdout,
        stderr => $stderr,
    };
}

# Returns a new random build request ID (a short hex string)
sub new_build_request_id
{
    return sprintf( '%08x', rand(2**32) );
}

# Given a jenkins $build object, returns the value of the named $parameter;
# dies on error.
sub jenkins_build_parameter
{
    my ($build, $parameter) = @_;

    my @actions = @{ $build->{ actions } || [] };
    die "no 'actions' in build" unless @actions;

    foreach my $action (@actions) {
        foreach my $p (@{ $action->{ parameters } || [] }) {
            if ($p->{ name } eq $parameter) {
                return $p->{ value };
            }
        }
    }

    return;
}

# Like flock() but operates on a filename rather than a handle,
# and dies on error.
# The file is opened for write (and created if necessary).
# Returns the locked handle.
sub flock_filename
{
    my ($filename, $flags) = @_;

    open( my $fh, '>', $filename ) || die "open $filename for write: $!";
    flock( $fh, $flags ) || die "flock $filename: $!";
    return $fh;
}

# ======================================== OBJECT ================================================

sub new
{
    my ($class) = @_;

    return bless {}, $class;
}

# Runs the main event loop until loop_exit is called
sub loop_exec
{
    my ($self) = @_;

    # autorestart on any kind of unexpected errors or hangs which occur during the main
    # loop. $self->loop_exit() is the only normal way to exit.
    AnyEvent::Watchdog::Util::autorestart( 1 );
    AnyEvent::Watchdog::Util::heartbeat( 180 );

    $self->{ exit_cv } = AnyEvent->condvar( );
    my $out = $self->{ exit_cv }->recv( );

    AnyEvent::Watchdog::Util::autorestart( 0 );
    AnyEvent::Watchdog::Util::heartbeat( 0 );

    return $out;
}

# Exits the main event loop with the given exit $code
sub loop_exit
{
    my ($self, $code) = @_;
    $self->{ exit_cv }->send( $code );
    return;
}

# =========================== PERSISTENT STATE ==========================================
#
# This script maintains its state in a hash which is persisted to disk after every
# significant change. The intent is that this script can be terminated at any time, with
# no warning, and will always be able to sensibly resume from its last operation.

# Load state from disk (or create state file if it doesn't yet exist).
# A lock file is used to ensure multiple instances of this script can't be using the
# same state file.
sub lock_and_load_state
{
    my ($self) = @_;

    my $basename = lc __PACKAGE__;
    $basename =~ s{::}{-}g;

    my $state_filename = catfile( $self->{ CWD }, "$basename.state" );
    my $lock_filename = catfile( $self->{ CWD }, "$basename.lock" );

    $self->{ state_lock } = flock_filename( $lock_filename, LOCK_EX );

    my %state;
    tie %state, 'Tie::Persistent', $state_filename, 'rw';
    $self->{ state } = \%state;

    return;
}

# Unload state, save it to disk, release lock file.
# Should be called as the main loop is exiting.
sub unlock_and_unload_state
{
    my ($self) = @_;

    untie %{ $self->{ state } };

    close( $self->{ state_lock } ) || die "close state lock: $!";

    return;
}

# Explicitly synchronize the state to disk.
# Should be called after every significant state change (e.g. after every state machine iteration)
sub sync_state
{
    my ($self) = @_;

    (tied %{ $self->{ state } })->sync( );

    return;
}

# Returns the next unique ID used for identifying elements in certain arrays (e.g. log array
# or project state history)
sub next_id
{
    my ($self) = @_;

    alias my $id = $self->{ state }{ last_id };
    ++$id;

    if ($id > $MAX_ID) {
        $id = 1;
    }

    return $id;
}

# =================================== GERRIT ============================================

# Returns the gerrit project for a given CI project (e.g. 'qt/qtbase' for 'QtBase master Integration')
sub gerrit_project
{
    my ($self, $project_id) = @_;
    my $gerrit_url = $self->project_config( $project_id, 'GerritUrl' );

    my $gerrit_project = $gerrit_url->path( );
    $gerrit_project =~ s{\A/}{};

    return $gerrit_project;
}

sub ssh_base_command_for_gerrit
{
    my ($url) = @_;

    my @ssh_base = (
        'ssh',
        '-oBatchMode=yes',
    );

    if (my $port = $url->port()) {
        push @ssh_base, ('-p', $port);
    }

    if (my $user = $url->user()) {
        push @ssh_base, ($user . '@' . $url->host());
    } else {
        push @ssh_base, $url->host();
    }

    push @ssh_base, 'gerrit';

    return @ssh_base;
}
memoize( 'ssh_base_command_for_gerrit' );

# Returns the gerrit WWW (http or https) URL for a given project
sub gerrit_www_url
{
    my ($self, $project_id) = @_;

    my $gerrit_ssh_url = $self->project_config( $project_id, 'GerritUrl' );

    # NOTE: assumption that server runs http, and redirects to https as appropriate.
    # This is true for codereview.qt-project.org.
    return 'http://' . $gerrit_ssh_url->host();
}
memoize( 'gerrit_www_url' );

sub gerrit_staging_ls
{
    my ($self, $project_id, $from) = @_;

    my $source = $self->project_config( $project_id, 'GerritUrl' );
    my $branch = $self->project_config( $project_id, 'GerritBranch' );

    my @ssh_base = ssh_base_command_for_gerrit( $source );

    my $gerrit_project = $self->gerrit_project( $project_id );

    my @cmd = (
        @ssh_base,
        'staging-ls',
        '--branch', $from // "refs/staging/$branch",
        '--destination', "refs/heads/$branch",
        '--project', $gerrit_project,
    );

    my $out = cmd( \@cmd )->{ stdout };
    chomp( $out );
    return $out;
}

# Returns a true value if and only if the configured staging branch for
# this project exists. The branch generally exists if the project has
# been tested by CI at least once.
sub staging_branch_exists
{
    my ($self, $project_id) = @_;

    my $repository = $self->project_config( $project_id, 'GerritUrl' );
    my $branch = $self->project_config( $project_id, 'GerritBranch' );

    # 'git ls-remote $repo $branch' succeeds if $repo can be contacted
    # and has output only if $branch exists on the repo.
    my @cmd = (
        'git',
        'ls-remote',
        $repository->as_string(),
        "refs/staging/$branch"
    );

    if (cmd( \@cmd )->{ stdout }) {
        return 1;
    }

    return;
}

sub gerrit_staging_new_build
{
    my ($self, $project_id) = @_;

    my $source = $self->project_config( $project_id, 'GerritUrl' );
    my $branch = $self->project_config( $project_id, 'GerritBranch' );

    my @ssh_base = ssh_base_command_for_gerrit( $source );

    my $gerrit_project = $self->gerrit_project( $project_id );

    my $build_ref = "refs/builds/${branch}_".time();

    my @cmd = (
        @ssh_base,
        'staging-new-build',
        '--build-id', $build_ref,
        '--staging-branch', "refs/staging/$branch",
        '--project', $gerrit_project,
    );

    my $log = $self->logger();

    cmd( \@cmd );

    $log->notice( "created build ref $build_ref" );
    return $build_ref;
}

# =================================== HTTP CLIENT =======================================

# Returns a hashref of appropriate HTTP headers.
# If %in_headers are provided, the contents are included in the returned hashref.
sub http_headers
{
    my ($self, %in_headers) = @_;

    return {
        'User-Agent' => $USERAGENT,
        Authorization => $self->http_basic_auth_string(),
        %in_headers,
    };
}

# Calculates and returns an HTTP BASIC authorization string using
# the configured username and password.
sub http_basic_auth_string
{
    my ($self) = @_;

    if (!$self->{ _http_basic_auth }) {
        my $user = $self->config( 'Global', 'JenkinsUser' );
        my $token = $self->config( 'Global', 'JenkinsToken' );
        my $h = HTTP::Headers->new();
        $h->authorization_basic( $user, $token );
        $self->{ _http_basic_auth } = $h->header( 'Authorization' );
    }

    return $self->{ _http_basic_auth };
}

# Issue an HTTP POST.
# Dies on error (any response other than $accept_status, defaulting to 200)
sub http_post
{
    my ($self, %args) = @_;

    my $data = $args{ data } // q{};
    my $headers = $args{ headers } || confess;
    my $label = $args{ label } || confess;
    my $query = $args{ query };
    my $url = URI->new( $args{ url } ) || confess;
    my @accept_status = @{ $args{ accept_status } || [200] };

    if ($query) {
        $url->query_form( %{ $query } );
    }

    my (undef, $response_headers) = blocking_http_request(
        POST => $url,
        body => $data,
        headers => $headers,
    );

    my $status = $response_headers->{ Status };
    if (! grep { $_ == $status } @accept_status) {
        die "$label failed: $status $response_headers->{ Reason }\n";
    }

    return;
}

# =================================== JENKINS ===========================================

sub jenkins_job_url
{
    my ($self, $project_id) = @_;

    my $jenkins_url = $self->project_config( $project_id, 'JenkinsUrl' );
    return "$jenkins_url/job/$project_id";
}

# Calculate and return a Jenkins build summary object; equal to the
# object printed by summarize_jenkins_build.pl in --yaml mode, with
# some additional information added to the 'formatted' text.
sub jenkins_build_summary
{
    my ($self, $project_id, $stash) = @_;

    my $build = $stash->{ build };

    my $gerrit_url = $self->gerrit_www_url( $project_id );
    my @cmd = (summarize_jenkins_build_cmd(), '--yaml', '--url', '-');

    if ($build->{ aborted_by_integrator }) {
        push @cmd, '--ignore-aborted';
    }

    if (my $arg = eval { $self->project_config( $project_id, 'LogBaseHttpUrl' ) }) {
        push @cmd, '--log-base-url', $arg;
    }

    my $stdin = encode_json( $build );
    my $out = cmd( \@cmd, '<' => \$stdin )->{ stdout };

    my $data = YAML::Any::Load( decode_utf8( $out ) );

    # append tested changes part to the formatted summary
    my $formatted = $data->{ formatted };
    chomp( $formatted );

    $formatted .= "\n\n  Tested changes";
    if (my $ref = $stash->{ build_ref }) {
        $formatted .= " ($ref)";
    }
    $formatted .= ':';

    my $staged = $stash->{ staged };
    foreach my $line (split( /\n/, $staged )) {
        my $change = parse_staging_ls( $line );
        if (!$change) {
            $formatted .= "\n    (error parsing change '$line')";
            next;
        }
        my $change_url = "$gerrit_url/$change->{ change }";
        $formatted .= "\n    $change_url [PS$change->{ patch_set }] - $change->{ summary }";
    }

    $data->{ formatted } = $formatted;

    return $data;
}

# Returns true iff it seems a Jenkins build should be retried.
# $parsed_build should be the parsed output of summarize-jenkins-build.pl
sub check_should_retry_jenkins
{
    my ($self, $project_id, $stash) = @_;

    my $parsed_build = $stash->{ parsed_build };

    my @runs = @{ $parsed_build->{ runs } || [] };
    return unless @runs;

    # It only makes sense to retry the build if _all_ failed runs are marked as should_retry...
    # If we had a single run with a genuine failure, we'd expect the same failure on the retry.
    my $should_retry = all { $_->{ should_retry } } @runs;
    return unless $should_retry;

    my $log = $self->logger();
    $log->warning( 'build log indicates we should retry' );

    my $MAX_ATTEMPTS = eval { $self->project_config( $project_id, 'BuildAttempts' ) } || 8;
    alias my $build_attempt = $stash->{ build_attempt };
    $build_attempt ||= 1;
    if ($build_attempt >= $MAX_ATTEMPTS) {
        $log->error( "already tried $MAX_ATTEMPTS times, giving up" );
        return;
    }

    # TODO: should we post a comment back into gerrit mentioning why the testing
    # is taking longer than usual? Or would that just be confusing / noisy?

    # wait a while in the hopes that some transient errors will clear up before we start again
    my $delay = 2**$build_attempt + 30;
    $log->warning( "will retry in $delay seconds" );
    Coro::AnyEvent::sleep( $delay );

    ++$build_attempt;

    return 1;
}


# ================================ LOG SYNCHRONIZATION ==================================

# Upload a single log from an HTTP URL via ssh.
# Expected to be run from within a coro.
#
# Arguments:
#
#   ssh_command => arrayref, the ssh command to run. Should read log data from stdin.
#   url => the log url
#
# The upload will be retried a few times if either the ssh or http connections
# experience an error.
sub upload_http_log_by_ssh
{
    my (%args) = @_;

    my @cmd = @{ $args{ ssh_command } };
    my $url = $args{ url };

    my $retry = 7;
    my $sleep = 1;

    while ($retry) {
        # cv receives nothing on success, error type and details on ssh or http error.
        my $cv = AnyEvent->condvar();

        my ($r, $w);
        pipe( $r, $w) || die "pipe: $!";

        my $ae_w = AnyEvent::Handle->new(
            fh => $w,
            on_error => sub {
                my ($h, $fatal, $msg) = @_;
                if ($fatal) {
                    $cv->send( 'ssh', "fatal error on pipe: $msg" );
                } else {
                    warn "on ssh pipe: $msg\n";
                }
            }
        );

        my $ssh_pid;
        my $ssh_cv = QtQA::AnyEvent::Util::run_cmd(
            \@cmd,
            '<' => $r,
            '$$' => \$ssh_pid,
            timeout => 60*15
        );

        $ssh_cv->cb( sub {
            my $status = $ssh_cv->recv();
            $cv->send( ($status == 0) ? () : ('ssh', $status) );
        });

        # check http headers and fail if anything other than '200 OK'
        my $check_headers = sub {
            my $h = shift;
            if ($h->{ Status } != 200) {
                my $status = $h->{ OrigStatus } || $h->{ Status };
                my $reason = $h->{ OrigReason } || $h->{ Reason };
                $cv->send( 'http', "fetching $url: $status $reason" );
                return 0;
            }
            return 1;
        };

        my $req = http_get(
            $url,
            on_body => sub {
                my ($data, $headers) = @_;
                return unless $check_headers->( $headers );
                # all HTTP data is piped to ssh STDIN
                $ae_w->push_write( $data );
                return 1;
            },
            sub {
                my (undef, $headers) = @_;
                return unless $check_headers->( $headers );
                # close write end of pipe to let ssh know there's no more data
                $ae_w->on_drain(
                    sub {
                        my ($handle) = @_;
                        close( $handle->{ fh } ) || warn "closing internal pipe for $url: $!";
                        $handle->destroy();
                    }
                );
            },
        );

        my (@error) = $cv->recv();
        if (!@error) {
            # all done
            return;
        }

        # something bad happened
        my $type = shift @error;
        my $error_str = "$type error: @error";

        # if we stopped due to an http error, make sure to kill the ssh
        if ($type eq 'http') {
            kill( 15, $ssh_pid ) if $ssh_pid;
        }

        # we will retry on _any_ http error, or on ssh exit code 255 (network error) or status -1 (timeout)
        if ($type eq 'http' || ($type eq 'ssh' && ($error[0] == -1 || ($error[0] >> 8) == 255))) {
            warn "$error_str\n  Trying again in $sleep seconds\n";
            --$retry;
            Coro::AnyEvent::sleep( $sleep );
            $sleep *= 2;
            next;
        }

        # any other kind of error is considered fatal
        die "$error_str\n";
    }

    # if we get here, we never succeeded.
    local $LIST_SEPARATOR = '] [';
    die "HTTP fetch $url to ssh command [@cmd] repeatedly failed, giving up.\n";
}

# Synchronize build logs from Jenkins to another host by ssh.
# All completed runs are synced, incomplete runs are not.
# The $stash keeps track of which logs have been synced.
sub sync_logs
{
    my ($self, $project_id, $stash) = @_;

    my $build_data = $stash->{ build };

    my @runs = @{ $build_data->{ runs } || [] };

    # if the build is still going, only copy completed runs;
    # otherwise, we copy runs in progress as well (may happen if the build is
    # aborted and some runs haven't finished aborting yet)
    if ($build_data->{ building }) {
        @runs = grep { !$_->{ building } } @runs;
    }

    @runs = grep { $_->{ number } == $build_data->{ number } } @runs;
    return unless @runs;

    my $ssh_url = eval { $self->project_config( $project_id, 'LogBaseSshUrl' ) };
    return unless $ssh_url;

    my $log = $self->logger();

    my $parsed_ssh_url = URI->new( $ssh_url );
    if ($parsed_ssh_url->scheme() ne 'ssh') {
        confess "unsupported URL, only ssh URLs are supported: $ssh_url";
    }

    # Figure out the list of target and source URLs
    my $build_number = $build_data->{ number };
    my $build_url = $build_data->{ url };

    my $dest_project_name = $project_id;
    $dest_project_name =~ s{ }{_}g;

    my $dest_project_path = catfile( $parsed_ssh_url->path(), $dest_project_name );
    my $dest_build_number = sprintf( 'build_%05d', $build_number );
    my $dest_build_path = catfile( $dest_project_path, $dest_build_number );

    my %to_upload;

    foreach my $run (@runs) {
        #
        # From a URL like:
        #    http://ci-dev.qt-project.org/job/shadow_QtBase_master_Integration/./cfg=linux-g++_developer-build_qtnamespace_qtlibinfix_Ubuntu_11.10_x64/82/
        # extract the config string:
        #   cfg=linux-g++_developer-build_qtnamespace_qtlibinfix_Ubuntu_11.10_x64
        #
        my $config = $run->{ url };
        $config =~ s{^\Q$build_url\E/}{};
        $config =~ s{^\./}{};
        $config =~ s{/\d+/?$}{};

        # If $config only has one axis (the normal case), just use it directly,
        # to avoid useless 'cfg=' in URLs.
        my $dest_config = $config;
        $dest_config =~ s{\A [^=]+ = ([^=]+) \z}{$1}xms;
        $dest_config =~ s{ }{_}g;

        my $src_url = "$run->{ url }/consoleText";
        my $dest_path = catfile( $dest_build_path, $dest_config, 'log.txt.gz' );

        my $src_url_testlogs = "$run->{ url }"."artifact/_artifacts/test-logs/*zip*/test-logs.zip";
        my $dest_path_testlogs = catfile( $dest_build_path, $dest_config, 'test-logs.zip' );

        if (!$stash->{ logs }{ $src_url }) {
            $to_upload{ $src_url } = $dest_path;

            my $exit_wait = AnyEvent->condvar;

            http_get $src_url_testlogs,
                on_header => sub {
                  if ($_[0]{"content-type"} =~ /^application\/zip$/) {
                    $to_upload{ $src_url_testlogs } = $dest_path_testlogs;
                  }
                  0;
                },
                sub {
                    $exit_wait->send;
                };
            $exit_wait->recv;
        }
    }

    # If the build is completed, also sync the master log
    if (!$build_data->{ building }) {
        $to_upload{ "$build_url/consoleText" } = catfile( $dest_build_path, 'log.txt.gz' );
    }

    my @ssh_base = (
        'ssh',
        '-oBatchMode=yes',
        '-p', $parsed_ssh_url->port( ),
        ($parsed_ssh_url->user( )
            ? ($parsed_ssh_url->user( ) . '@' . $parsed_ssh_url->host( ))
            : $parsed_ssh_url->host( )
        )
    );

    my $parent_coro = $Coro::current;
    my @coro;
    while (my ($src, $dest) = each %to_upload) {
        my $dir = dirname( $dest );
        # don't re-compress zip files
        my $storecmd = ($src =~ m/\.zip$/) ? "cat" : "gzip";
        my $filename = fileparse ($dest);
        my @command = (
            @ssh_base,
            qq{mkdir -p "$dir" && cd "$dir" && }
           .qq{$storecmd > .incoming.$filename && }
           .qq{mv .incoming.$filename $filename}
        );
        push @coro, async {
            local $Coro::current->{ desc } = "$parent_coro->{ desc } uploader";
            my $host = $parsed_ssh_url->host();
            my $thing = "$src -> $dest (on $host)";
            eval {
                upload_http_log_by_ssh(
                    ssh_command => \@command,
                    url => $src,
                );
            };
            if (my $error = $EVAL_ERROR) {
                return "$thing: $error";
            }
            $log->notice( "$thing: OK!" );
            $stash->{ logs }{ $src } = 1;
            return;
        };
    }

    my @errors = map { $_->join() } @coro;
    if (@errors) {
        local $LIST_SEPARATOR = "\n";
        die "@errors";
    }

    # the rest is valid only when the build is completed
    return if $build_data->{ building };

    # Create the 'state.json.gz' dump of the stash, and the
    # 'latest' and possibly 'latest-success' links.
    my %cut_stash = %{ $stash };
    delete $cut_stash{ logs }; # doesn't make sense to show this
    my $stash_json = JSON->new()->pretty(1)->utf8(1)->encode( \%cut_stash );
    my $cmd =
        qq{cd "$dest_project_path" && }
       .qq{gzip > "$dest_build_number/.incoming.state.json.gz" && }
       .qq{mv "$dest_build_number/.incoming.state.json.gz" "$dest_build_number/state.json.gz" && }
       .qq{ln -snf "$dest_build_number" latest};
    if ($build_data->{ result } eq 'SUCCESS') {
        $cmd .= qq{ && ln -snf "$dest_build_number" latest-success};
    }

    cmd( [@ssh_base, $cmd], '<' => \$stash_json );

    # Launch testparser.pl at remote site to scan the sent logs to the SQL database
    my $scriptpath = catdir( $parsed_ssh_url->path(), "/.hooks/post-upload-script" );
    my $scanfolder = catdir( $dest_project_path, $dest_build_number );

    $self->logger()->notice( "Calling '$scriptpath $scanfolder'" );

    eval {
        cmd(
            [@ssh_base, $scriptpath, $scanfolder],
            timeout => 60*5, retry => 0
        );
    };
    $self->logger()->warning( "$@" ) if $@;

    return;
}


# ============================== STATE MACHINE ==========================================
#
# The state machine is the heart of the integrator.
#
# Each project runs its own state machine (in its own Coro).
#
# Each state is implemented by a method named "do_state_${name}".
# The method should return the name of the next state.
# All state methods should be blocking; Coro / Coro::AnyEvent methods should
# be used to yield control to other Coros when appropriate.
#
# Each state method is called with a hashref known as the 'stash', which may be used
# to store named arguments used by subsequent states.
#
# Each state should be as close as possible to atomic. The current state and stash,
# as well as a history of states, is synced to disk between each state transition;
# if state code is written atomically, the state machine can be killed and restarted at
# any time with no resulting problems.
#
# A state is permitted to die; this causes a transition to the "error" state.
# The state which died will be attempted a few times, with some delay.
# If a state repeatedly dies, it will be suspended; SIGUSR2 will resume any suspended
# states.

# State machine main loop for a given project.
#
# This should be called once, from within a Coro.
# It runs an infinite loop.
sub do_project_state_machine
{
    my ($self, $project_id) = @_;

    # this is prepended to log messages
    local $Coro::current->{ desc } = $project_id;

    my $project_ref = $self->{ state }{ project }{ $project_id };
    $project_ref->{ state }{ stash } ||= {};

    my $log = $self->logger( );

    eval {
        $self->do_project_init( $project_id );
    };
    if (my $error = $EVAL_ERROR) {
        $project_ref->{ state } = {
            name => 'error',
            error => "initialization failed: $error",
            when => timestamp(),
        };
    }

    while (1) {
        $self->do_project_state_machine_iter( $project_id );
    }

    return;
}

# Do a single iteration of the project state machine
sub do_project_state_machine_iter
{
    my ($self, $project_id) = @_;

    my $project_ref = $self->{ state }{ project }{ $project_id };
    my $this_state = $project_ref->{ state };

    # Every state is implemented by a method on this object, which returns the next state.
    $this_state->{ name } ||= 'start';
    $this_state->{ stash } ||= {};
    my $state_name = $this_state->{ name };

    my ($next_state_name, $next_stash) = $self->run_state_method( $project_id, $this_state );

    if ($state_name ne $next_state_name) {
        $self->logger()->notice( "state change $state_name -> $next_state_name" );
    }

    $project_ref->{ state } = {
        name => $next_state_name,
        stash => $next_stash,
        when => timestamp(),
        id => $self->next_id(),
    };

    my %history_state = %{ $this_state };
    # historical states get a new ID
    $history_state{ id } = $self->next_id();
    push @{ $project_ref->{ history } }, \%history_state;

    if (@{ $project_ref->{ history } } > $MAX_HISTORY) {
        shift @{ $project_ref->{ history } };
    }

    $self->sync_state( );

    return;
}

# Run the appropriate method for the given state, and return
# the next desired state.
# Handles errors.
sub run_state_method
{
    my ($self, $project_id, $state) = @_;

    my $state_name = $state->{ name };
    my $method = "do_state_$state_name";
    $method =~ s{-}{_}g;
    $method = $self->can( $method );
    if (!$method) {
        # this can only be a programmer's error
        confess "internal error: unexpected state $state_name";
    }

    my $next_state_name;
    my $next_stash = dclone( $state->{ stash } ); # modifiable copy
    eval {
        local $Coro::current->{ desc } = "$project_id $state_name";
        $next_state_name = $method->(
            $self,
            $project_id,
            $next_stash
        );
    };

    if (my $error = $EVAL_ERROR) {
        $next_state_name = 'error';
        $next_stash = { state => $state, error => $error, error_count => ($next_stash->{ error_count }||0) + 1 };
    } elsif ($state_name ne 'error') {
        # reset error count as soon as any state (other than 'error') succeeds
        delete $next_stash->{ error_count };
    }

    return ($next_state_name, $next_stash);
}

# Returns 0 or a random number of seconds used to stagger the initialization
# of each project.
#
# When the integrator is managing many projects, initializing every project
# as fast as possible may cause network congestion or other issues.
#
# For example, if 40 projects were managed and starting from state 'start',
# the integrator would open 40 concurrent network connections to gerrit to
# check staging branch contents, and do the same again after each staging
# poll interval.
#
# At the very least, this results in undesirable periodic spikes in network
# activity; it may also result in dropped connections.
#
# This function calculates a reasonable period over which project initialization
# should be staggered, then returns a random delay so that the initialization
# of projects is uniformly distributed over the stagger period.
sub stagger_delay
{
    my ($self) = @_;

    alias my $stagger_period = $self->{ stagger_period };
    if (!defined($stagger_period)) {
        # initial calculation of whether we need to stagger;
        # the scale is picked more or less arbitrarily
        my $project_count = scalar( @{ $self->{ projects } } );
        given ($project_count) {
            when ($_ > 100) { $stagger_period = 300 }
            when ($_ > 50)  { $stagger_period = 180 }
            when ($_ > 25)  { $stagger_period = 90 }
            when ($_ > 10)  { $stagger_period = 60 }
            default         { $stagger_period = 0 }
        }
        if ($stagger_period) {
            $self->logger()->notice( "Project initialization staggered over $stagger_period seconds" );
        }
    }

    if ($stagger_period) {
        return int(rand($stagger_period));
    }

    return 0;
}

# Project-specific initialization.
# This is called once for each project before the state machine begins.
sub do_project_init
{
    my ($self, $project_id) = @_;

    if (my $delay = $self->stagger_delay()) {
        Coro::AnyEvent::sleep( $delay );
    }

    # create a stream-events watcher for this gerrit (if we don't already have one)
    my $gerrit_url = $self->project_config( $project_id, 'GerritUrl' )->clone();

    # path has no bearing on stream-events, remove it
    $gerrit_url->path( q{} );

    alias my $watcher = $self->{ gerrit_stream_events }{ $gerrit_url->as_string() };
    if (!$watcher) {
        $watcher = $self->create_gerrit_stream_events_watcher( $gerrit_url );
        $self->logger()->notice( "connected to stream-events for gerrit at $gerrit_url" );
    }

    return;
}

# Initial state for all projects; return to this state after each CI run
sub do_state_start
{
    my ($self, $project_id, $stash) = @_;

    # delete various state built up over the last run
    %{ $stash } = ();

    # The staging branch may not exist (e.g. if the project is newly created)
    if (!$self->staging_branch_exists( $project_id )) {
        return 'wait-until-staging-branch-exists';
    }

    return 'wait-for-staging';
}

# Wait for the staging branch to exist.
sub do_state_wait_until_staging_branch_exists
{
    my ($self, $project_id) = @_;

    my $interval = $self->project_config( $project_id, 'StagingPollInterval' );

    while (!$self->staging_branch_exists( $project_id )) {
        $self->wait_for_gerrit_activity( $project_id, $interval );
    }

    return 'wait-for-staging';
}

# Wait for some changes to be staged.
# Supports notification from 'gerrit stream-events', and polling.
sub do_state_wait_for_staging
{
    my ($self, $project_id, $stash) = @_;

    my $interval = $self->project_config( $project_id, 'StagingPollInterval' );
    my $gerrit_project = $self->gerrit_project( $project_id );

    while (1) {
        $stash->{ staged } = $self->gerrit_staging_ls( $project_id );
        last if $stash->{ staged };

        # Nothing staged yet, try a bit later.
        # We wait until either $interval seconds have passed, or an event occurs
        # to wake us up (from gerrit stream-events)
        $self->wait_for_gerrit_activity( $project_id, $interval );
    }

    # something was staged; wait for the staging branch to settle down
    return 'wait-for-staging-quiet';
}

# Wait for staging branch to stop changing.
#
# Waits either until no more changes have been staged for a while, or some
# maximum timeout has been reached.
sub do_state_wait_for_staging_quiet
{
    my ($self, $project_id, $stash) = @_;

    my $staged = $stash->{ staged };

    my $quiet_period = $self->project_config( $project_id, 'StagingQuietPeriod' );
    my $maximum_wait = $self->project_config( $project_id, 'StagingMaximumWait' );

    my $log = $self->logger();

    my $maximum_timer = Timer::Simple->new( );
    my $quiet_timer = Timer::Simple->new( );
    $maximum_timer->start( );
    $quiet_timer->start();

    while ($maximum_timer->elapsed() < $maximum_wait && $quiet_timer->elapsed() < $quiet_period) {
        my $time_remaining = $maximum_wait - $maximum_timer->elapsed();
        my $wait = $quiet_period;
        if ($wait > $time_remaining) {
            $wait = $time_remaining;
        }
        $self->wait_for_gerrit_activity( $project_id, $wait );

        my $now_staged = $self->gerrit_staging_ls( $project_id );
        if (!$now_staged) {
            $log->notice( 'all changes were unstaged.' );
            delete $stash->{ staged };
            return 'wait-for-staging';
        }

        if ($now_staged ne $staged) {
            $log->notice( 'staging activity occurred.' );
            $staged = $now_staged;
            $quiet_timer->restart( );
        }
    }

    $log->info( 'done waiting for staging' );
    return 'staging-new-build';
}

# Create a new build ref in gerrit, using the current content of the staging branch.
sub do_state_staging_new_build
{
    my ($self, $project_id, $stash) = @_;

    my $build_ref = $self->gerrit_staging_new_build( $project_id );

    $stash->{ build_ref } = $build_ref;

    return 'check-staged-changes';
}

# Check which changes are included in the given build ref, and store them in
# the stash for later reference.
sub do_state_check_staged_changes
{
    my ($self, $project_id, $stash) = @_;

    $stash->{ staged } = $self->gerrit_staging_ls( $project_id, $stash->{ build_ref } );

    return 'trigger-jenkins';
}

# Trigger Jenkins build for the given build ref.
sub do_state_trigger_jenkins
{
    my ($self, $project_id, $stash) = @_;

    my $build_ref = $stash->{ build_ref };

    # To trigger a Jenkins build with parameters.
    # POST to <jenkins>/job/<job>/buildWithParameters,
    # with param1=val1&param2=val2 in the post data.
    #
    # The response to buildWithParameters doesn't give us anything we can use to
    # track our build request, so we generate and include our own request ID.
    my $request_id = new_build_request_id( );
    my $job_url = $self->jenkins_job_url( $project_id );

    $self->http_post(
        label => "new build for $project_id",
        url => "$job_url/buildWithParameters",
        data => www_form_urlencoded(
            qt_ci_request_id => $request_id,
            qt_ci_git_url => $self->project_config( $project_id, 'GerritUrl' ),
            qt_ci_git_ref => $build_ref,
        ),
        headers => $self->http_headers(
            'Content-Type' => 'application/x-www-form-urlencoded',
        ),
        accept_status => [200, 201],
    );

    $stash->{ request_id } = $request_id;

    return 'wait-for-jenkins-build-active';
}

# Wait for the Jenkins build with the given qt_ci_request_id to start.
sub do_state_wait_for_jenkins_build_active
{
    my ($self, $project_id, $stash) = @_;

    my $request_id = delete $stash->{ request_id };

    my $job_json_url =
        $self->jenkins_job_url( $project_id )
       .'/api/json?depth=2&tree=builds[number,actions[parameters[name,value]]]';

    # build should take up to this amount of time to be triggered, max. (seconds)
    my $MAX_WAIT = eval { $self->project_config( $project_id, 'JenkinsTriggerTimeout' ) } || 60*15;

    # poll interval when waiting for build to be triggered (seconds)
    my $INTERVAL = eval { $self->project_config( $project_id, 'JenkinsTriggerPollInterval' ) } || 10;

    my $timer = Timer::Simple->new();

    # loop until a build is found with the correct request ID
    my $build_number;
    while (1) {
        my $job_data = fetch_json_data( $job_json_url );

        eval {
            foreach my $build (@{ $job_data->{ builds } || []}) {
                if (jenkins_build_parameter( $build, 'qt_ci_request_id' ) eq $request_id) {
                    $build_number = $build->{ number };
                    die "no 'number' in build" unless $build_number;
                    last;
                }
            }
        };
        if (my $error = $EVAL_ERROR) {
            die "JSON schema error in $job_json_url: $error\n";
        }

        last if $build_number;

        # If we get here, there's no errors, but we haven't found the build yet.
        if ($timer->elapsed() > $MAX_WAIT) {
            die "Jenkins did not start a build with request ID $request_id within $MAX_WAIT seconds";
        }

        # try again soon...
        Coro::AnyEvent::sleep( $INTERVAL );
    }

    $stash->{ build_number } = $build_number;

    return 'set-jenkins-build-description';
}

# Set a user-visible helpful description on the Jenkins build
sub do_state_set_jenkins_build_description
{
    my ($self, $project_id, $stash) = @_;

    my $build_number = $stash->{ build_number };

    my $build_url = $self->jenkins_job_url( $project_id ) . "/$build_number";
    my $gerrit_url = $self->gerrit_www_url( $project_id );

    # The description is displayed as HTML in Jenkins, we make up a list of changes.
    my $description = 'Tested changes:<ul>';

    my $staged = $stash->{ staged };
    foreach my $line (split( /\n/, $staged )) {
        my $change = parse_staging_ls( $line );
        if (!$change) {
            $self->logger()->warning( "Couldn't parse staging-ls line: $line" );
            $description .= "\n<li>($line)</li>";
            next;
        }
        my $change_url = "$gerrit_url/$change->{ change }";
        $description .= "\n<li><a href=\"$change_url\">$change_url</a> [PS$change->{ patch_set }] - $change->{ summary }</li>";
    }

    $description .= "\n</ul>";

    $self->http_post(
        label => "set description for $project_id $build_number",
        url => "$build_url/submitDescription",
        data => www_form_urlencoded(
            description => $description,
        ),
        headers => $self->http_headers(
            'Content-Type' => 'application/x-www-form-urlencoded',
        ),
    );

    return 'monitor-jenkins-build';
}

# Check the state of a Jenkins build.
# Supports polling and notification from a post-build hook.
sub do_state_monitor_jenkins_build
{
    my ($self, $project_id, $stash) = @_;

    my $build_number = $stash->{ build_number };

    my $interval = eval { $self->project_config( $project_id, 'JenkinsPollInterval' ) };

    # default interval should be small if we expect to receive TCP notifications, large otherwise
    $interval //= (
        eval { $self->config( 'Global', 'TcpPort' ) }
            ? 60*15
            : 30
    );

    my $cancel_on_failure = eval { $self->project_config( $project_id, 'JenkinsCancelOnFailure' ) } // 0;

    my $log = $self->logger( );

    # Jenkins build data contains a lot of stuff we don't need, which can bloat our state file
    # and api/json output; this list is used to limit the data to only the important parts for us.
    # Feel free to expand this whenever you need it.
    my @json_elements = qw(
        building
        number
        url
        result
        fullDisplayName
        timestamp
        duration
    );

    my $json_tree;
    {
        local $LIST_SEPARATOR = ',';
        $json_tree = "@json_elements,runs[@json_elements]";
    }

    my $url = $self->jenkins_job_url( $project_id ) . "/$build_number/api/json?depth=2&tree=$json_tree";

    my $build_data;

    while (1) {
        $build_data = fetch_json_data( $url );
        $stash->{ build } = $build_data;

        # sync logs for any run which recently completed
        $self->sync_logs( $project_id, $stash );

        # if building == false, then we're definitely done...
        last if !$build_data->{ building };

        # otherwise, we might want to cancel, if cancelling is permitted and at least one
        # run (configuration) has failed
        if ($cancel_on_failure) {
            my @runs = @{ $build_data->{ runs } || [] };

            my @failed_runs = grep {
                $_->{ number } == $build_number
                    && !$_->{ building }
                    && $_->{ result } ne 'SUCCESS'
            } @runs;

            if (@failed_runs) {
                my @names = map { $_->{ fullDisplayName } } @failed_runs;
                local $LIST_SEPARATOR = '] [';
                $log->notice( "run(s) failed - [@names]. Cancelling build." );
                return 'cancel-jenkins-build';
            }
        }

        $log->info( "build $build_number - not yet completed" );

        if ($self->wait_for_jenkins_activity( $project_id, $interval )) {
            # if Jenkins notified us, wait a few seconds, since it takes some time
            # between when a Jenkins post-build hook is activated and the build
            # is completed according to remote API.
            Coro::AnyEvent::sleep( 5 );
        }
    }

    # all logs are synced by now, no need to keep this
    delete $stash->{ logs };

    return 'parse-jenkins-build';
}

# Cancel the current Jenkins build (because we know it is going to fail).
sub do_state_cancel_jenkins_build
{
    my ($self, $project_id, $stash) = @_;

    my $build = $stash->{ build };

    $self->http_post(
        label => "cancel $project_id build $build->{ number }",
        url => "$build->{ url }/stop",
        headers => $self->http_headers(),
        # as a slight oddity, Jenkins may respond to this with HTTP 302
        accept_status => [200, 302],
    );

    # Don't bother with another round-trip to fetch the build's state again,
    # we already have all the info we need; also note that it was aborted by
    # us, since it affects how the failure is represented.
    $build->{ building } = undef;
    $build->{ result } = 'ABORTED';
    $build->{ aborted_by_integrator } = 1;

    $self->sync_logs( $project_id, $stash );
    delete $stash->{ logs };

    return 'parse-jenkins-build';
}

sub do_state_parse_jenkins_build
{
    my ($self, $project_id, $stash) = @_;

    my $build = $stash->{ build };
    if ($build->{ building }) {
        die 'internal error: arrived in parse-jenkins-build state with build still in progress';
    }

    $stash->{ parsed_build } = $self->jenkins_build_summary( $project_id, $stash );
    $stash->{ parsed_build }{ result } = $build->{ result };

    # parsed_build replaces build
    delete $stash->{ build };

    if ($self->check_should_retry_jenkins( $project_id, $stash )) {
        $stash->{ parsed_build }{ should_retry } = 1;
    }

    return 'handle-jenkins-build-result';
}

# Do some appropriate action with the parsed result of a Jenkins build
sub do_state_handle_jenkins_build_result
{
    my ($self, $project_id, $stash) = @_;

    my $parsed_build = $stash->{ parsed_build };
    if ($parsed_build->{ should_retry }) {
        delete $stash->{ parsed_build };
        return 'trigger-jenkins';
    }

    my $gerrit_url = $self->project_config( $project_id, 'GerritUrl' );
    my @ssh_base = ssh_base_command_for_gerrit( $gerrit_url );

    my @cmd = (
        @ssh_base,
        'staging-approve',
        '--branch', $self->project_config( $project_id, 'GerritBranch' ),
        '--build-id', $stash->{ build_ref },
        '--project', $self->gerrit_project( $project_id ),
        '--result', (($parsed_build->{ result } eq 'SUCCESS') ? 'pass' : 'fail'),
        '--message', '-'
    );

    my $stdin = encode_utf8( $parsed_build->{ formatted } );
    cmd( \@cmd, '<' => \$stdin );

    return 'send-mail';
}

# Send email about a build result.
sub do_state_send_mail
{
    my ($self, $project_id, $stash) = @_;

    if (! eval { $self->project_config( $project_id, 'MailTo' ) }) {
        return 'start';
    }

    my $parsed_build = delete $stash->{ parsed_build };
    my $build_ref = delete $stash->{ build_ref };

    my $gerrit_url = $self->project_config( $project_id, 'GerritUrl' );
    my $gerrit_branch = $self->project_config( $project_id, 'GerritBranch' );
    my $ident = "$project_id #$stash->{ build_number }";
    my $result = ($parsed_build->{ result } eq 'SUCCESS') ? 'pass' : 'fail';

    my $sender = Mail::Sender->new();

    my %args = (
        subject => "$result on $ident",
        headers => {
            'X-Qt-CI-Status' => $result,
            'X-Qt-CI-Repository' => $gerrit_url,
            'X-Qt-CI-Branch' => $gerrit_branch,
            'X-Qt-CI-Build' => $build_ref,
        },
        msg => $parsed_build->{ formatted },
        on_errors => 'die',
        encoding => 'quoted-printable',
        charset => 'utf-8'
    );

    $self->fill_mail_args( \%args, $project_id );

    $sender->MailMsg( \%args );

    # all done!
    %{ $stash } = ();

    return 'start';
}

# Generic error handler state.
# This will attempt to resume the last executed state, with some delay;
# if errors occur repeatedly, this will eventually suspend the state machine
# until SIGUSR2 is received.
sub do_state_error
{
    my ($self, $project_id, $stash) = @_;

    my $from_state = $stash->{ state };
    my $error_count = $stash->{ error_count };
    my $error = $stash->{ error };

    my $MAX_ERROR_COUNT = 8;
    chomp $error;

    my $log = $self->logger();

    if ($error_count > $MAX_ERROR_COUNT) {
        $log->critical( "$error, occurred repeatedly." );
        $log->critical( "Suspending for investigation; to resume: kill -USR2 $PID" );
        $self->wait_for_resume_from_error_signal();
        # SIGUSR2 resets error count
        $error_count = 0;
    } else {
        my $delay = 2**$error_count;
        $log->error( "$error, retry in $delay seconds" );
        Coro::AnyEvent::sleep( $delay );
    }

    my $state_name = $from_state->{ name };
    %{ $stash } = %{ $from_state->{ stash } };
    $stash->{ error_count } = $error_count;

    # check if state was reset
    if ( $self->{ state }{ project }{ $project_id }{ state }{ reset } ) {
        $state_name = 'start';
    }

    $log->notice( "resuming from error into state $state_name" );

    return $state_name;
}

# =========================== CONFIGURATION FILE ========================================

# Loads configuration from disk, combined with $command_line_options hashref, into
# $self->{ config }, which is subsequently made a strict hash to help catch coding errors.
sub load_config
{
    my ($self, $command_line_options) = @_;

    if (!$self->{ config_file }) {
        die "No configuration file set. Try --config <somefile>\n";
    }

    my $config_ref = Config::Tiny->read( $self->{ config_file } );
    if (!$config_ref) {
        die "Reading configuration file $self->{ config_file } failed: ".Config::Tiny->errstr();
    }

    my %config = %{ $config_ref };

    # options from command-line override any from configuration file
    while (my ($key, $val) = each %{ $command_line_options }) {
        my ($section, $subkey) = split( /\./, $key, 2 );
        $config{ $section }{ $subkey } = $val;
    }

    my @projects;

    foreach my $section (keys %config) {
        my $section_ref = $config{ $section };
        foreach my $key (keys %{ $section_ref }) {
            # Replace some URI strings with parsed objects
            if ($key =~ m{Url\z}) {
                my $value = $section_ref->{ $key };
                # Omit useless .git from URL end
                if ($value) {
                    $value =~ s{\.git\z}{};
                }
                $section_ref->{ $key } = URI->new( $value );
            }

            # Construct a list of all enabled projects
            if ($section ne 'Global' && $key eq 'Enabled' && $section_ref->{ $key } eq '1') {
                push @projects, $section;
            }
        }
    }

    # Check for some mandatory global options.
    my @mandatory = qw(
        WorkingDirectory
    );
    my @missing = grep { !exists( $config{ Global }{ $_ } ) } @mandatory;
    if (my $count = @missing) {
        local $LIST_SEPARATOR = ', ';
        die inflect("Error: mandatory PL(option,$count) PL(is,$count) not set: @missing\n");
    }

    # Allow Global.WorkingDirectory to be globbed (use ~/ etc)
    $config{ Global }{ WorkingDirectory } = glob $config{ Global }{ WorkingDirectory };

    # Nothing to do if there are no projects.
    if (!@projects) {
        die "Error: no projects configured.\n";
    }

    $self->{ config } = \%config;
    $self->{ projects } = \@projects;

    return;
}

# Returns project-specific config if available (and $project_id is defined), or global
# config otherwise, or dies if neither is available.
# If called in list context, comma or space separated values will be split into a list.
sub project_config
{
    my ($self, $project_id, $key) = @_;

    my $out;
    eval {
        $project_id // die 'no project_id given';
        $out = $self->config( $project_id, $key );
    };
    if ($EVAL_ERROR) {
        $out = $self->config( 'Global', $key );
    }

    if (wantarray && $out && $out =~ m{,}) {
        return split( /[ ,]+/, $out );
    }

    return $out;
}

# Returns config for the given key and section, or dies if it is unavailable.
# If called in list context, comma or space separated values will be split into a list.
sub config
{
    my ($self, $section, $key) = @_;

    my $out = $self->{ config }{ $section }{ $key };
    if (!defined($out)) {
        croak "missing configuration key '$key' in section [$section]";
    }

    if (wantarray && $out && $out =~ m{,}) {
        return split( /[ ,]+/, $out );
    }

    return $out;
}

# ================================ TCP SERVER =======================================

# Create and return a simple TCP server listening for connections. Configured with
# port and event handler subroutine.
sub create_tcp_server
{
    my ($self, $port_config, $event_handler) = @_;

    my $log = $self->logger();

    my $port = eval { $self->config( 'Global', $port_config ) };
    if (!$port) {
        $log->warning( "TCP interface not available. Set '$port_config' in configuration file to enable it." );
        return;
    }

    my $out = tcp_server(
        undef,
        $port,
        sub {
            $self->handle_tcp_connection( @_, $event_handler );
        }
    );

    $log->notice( "TCP listening on port $port ($port_config)" );

    return $out;
}

# Handle an incoming TCP connection
sub handle_tcp_connection
{
    my ($self, $fh, $host, $port, $event_handler) = @_;

    my $desc = "TCP handler $host:$port";
    local $Coro::current->{ desc } = $desc;

    my $log = $self->logger();

    my $handle = AnyEvent::Handle->new(
        fh => $fh,
        autocork => 0,
        on_error => sub {
            my ($h, undef, $message) = @_;
            local $Coro::current->{ desc } = $desc;
            $log->warning( $message );
            $h->destroy();
            return;
        }
    );

    my $timeout;

    my $finish = sub {
        $handle->destroy();
        undef $handle;
        undef $timeout;
    };

    # We expect to receive exactly one JSON object
    $handle->push_read(
        json => sub {
            my (undef, $data) = @_;
            local $Coro::current->{ desc } = $desc;
            $event_handler->( $self, $data );
            $finish->();
        }
    );

    # basic guard against connections being held open; drop anything which doesn't
    # send us valid input within a few seconds
    $timeout = AE::timer( 5, 0, sub {
        local $Coro::current->{ desc } = $desc;
        $log->warning( 'connection dropped, JSON not received' );
        $handle->push_write( "timed out waiting for you to send me some data!\n" );
        $finish->();
    });

    return;
}

# ================================ TCP REMOTE API =======================================
#
# To avoid polling Jenkins for build updates, this script supports a simple protocol for
# Jenkins to report build completions via TCP.
#
# If enabled, it expects to receive JSON objects (one object per connection) of the form:
#
#   {"type":"build-updated","job":"some job"}
#
# When these events are received, any coros waiting on the specified job may be woken up.

# Called whenever an event is received from Jenkins
sub handle_jenkins_event
{
    my ($self, $event) = @_;

    my $log = $self->logger();
    if (!$event->{ type }) {
        $log->warning( 'received jenkins event with no type, ignored' );
        return;
    }

    # this is the only supported event for now
    if ($event->{ type } ne 'build-updated') {
        $log->warning( "received jenkins event with unknown type '$event->{ type }', ignored" );
        return;
    }

    my $job = $event->{ job };

    if (!$job) {
        $log->warning( "build-updated event is missing 'job', ignored" );
        return;
    }

    $log->info( "received build-updated event for $job" );

    # wake up anyone waiting for this.
    if (my $signal = $self->{ jenkins_job_signal }{ $job }) {
        $signal->broadcast();
    }

    return;
}

# ================================ TCP ADMIN API =======================================
#
# Admin interface for receiving remote commands to modify state machine
#
# If enabled, it expects to receive JSON objects (one object per connection) of the form:
#
#  {"type":"<some-command>","project":"<some_project>","token":"<JenkinsToken>"}

# Called whenever an admin command is received
sub handle_admin_cmd
{
    my ($self, $event) = @_;

    my $log = $self->logger();
    if (!$event->{ type }) {
        $log->warning( 'received admin command with no type, ignored' );
        return;
    }

    # Basic authentication using JenkinsToken
    if (!$event->{ token } || $event->{ token } ne $self->config( 'Global', 'JenkinsToken' )) {
        $log->warning( "received admin command with missing or wrong token" );
        return;
    }

    if ($event->{ type } eq 'remove-state') {
        $self->handle_admin_cmd_remove_state($event);
    } elsif ($event->{ type } eq 'reset-state') {
        $self->handle_admin_cmd_reset_state($event);
    } else {
        $log->warning( "received admin command with unknown type '$event->{ type }', ignored" );
    }
    return;
}

# Handle administrative command reset-state
sub handle_admin_cmd_reset_state
{
    my ($self, $event) = @_;

    my $log = $self->logger();
    my $project = $event->{ project };

    if (!$project) {
        $log->warning( "reset-state command is missing 'project', ignored" );
        return;
    }

    my $project_ref = $self->{ state }{ project }{ $project };
    if ( $project_ref->{ state }{ name } ne 'error' ) {
        $log->info( "Project '$project' not in error state, ignoring reset-state" );
        return;
    }

    $log->notice( "Resetting state for project '$project'" );
    $project_ref->{ state }{ reset } = 1;
    $project_ref->{ state }{ name } = 'start';

    $self->sync_state( );

    return;
}

# Handle administrative command remove-state
sub handle_admin_cmd_remove_state
{
    my ($self, $event) = @_;

    my $log = $self->logger();
    my $project = $event->{ project };

    if (!$project) {
        $log->warning( "remove-state command is missing 'project', ignored" );
        return;
    }

    $log->notice( "Removing state for project '$project'" );
    delete $self->{ state }{ project }{ $project };

    $self->sync_state( );

    return;
}
# ================================ HTTP REMOTE API ======================================

# Create and return an HTTP server object, if enabled.
sub create_httpd
{
    my ($self) = @_;

    my $log = $self->logger();

    my $port = eval { $self->config( 'Global', 'HttpPort' ) };
    if (!$port) {
        $log->warning( "HTTP interface not available. Set HttpPort in configuration file to enable it." );
        return;
    }

    my $httpd = AnyEvent::HTTPD->new(
        host => '0.0.0.0',
        port => $port,
        allowed_methods => ['GET']
    );

    $httpd->reg_cb(
        '/api/json' => sub {
            $self->http_api_json( @_ );
        },
        '' => sub {
            # TODO: add a helpful top-level page?
            $self->http_fallback( @_ );
        },
    );

    $log->notice( "HTTP listening on port $port" );

    return $httpd;
}

# Handler for any HTTP request not handled elsewhere
sub http_fallback
{
    my ($self, $httpd, $req) = @_;

    return if $req->responded();

    $req->respond([
        404,
        'not found',
        {'Content-Type' => 'text/plain'},
        "The resource you requested does not exist.\n\n($USERAGENT)",
    ]);

    return;
}

# Handle a request to /api/json (Jenkins-style read-only remote API).
#
# The same persistent state saved to disk is exported over the remote API.
# The JSON is cached and recalculated a maximum of once every few seconds.
sub http_api_json
{
    my ($self, $httpd, $req) = @_;

    my $gzip = 0;
    if (my $accept_encoding = $req->headers()->{ 'accept-encoding' }) {
        if ($accept_encoding =~ m{(?:^|,)gzip(?:$|,)}) {
            $gzip = 1;
        }
    }
    my $pretty = $req->parm( 'pretty' ) ? 1 : 0;
    my $since_id = $req->parm( 'since_id' ) || 0;
    if ($since_id > $MAX_ID) {
        $since_id = 0;
    }

    my $content = $self->api_json_content( pretty => $pretty, gzip => $gzip, since_id => $since_id );

    $req->respond([
        200,
        'ok',
        {
            'Content-Type' => 'application/json; charset=utf-8',
            'Access-Control-Allow-Origin' => '*',
            ($gzip ? ('Content-Encoding' => 'gzip') : ()),
        },
        $content
    ]);

    return;
}

# Given a $state hashref, removes all history and log messages with an ID
# less than $id, to cut down on JSON size
sub cut_state_by_id
{
    my ($self, $state, $id) = @_;

    foreach my $project (keys %{ $state->{ project } || {} } ) {
        if ($state->{ project }{ $project }{ state }{ id } < $id) {
            delete $state->{ project }{ $project };
            next;
        }
        my @history = @{ $state->{ project }{ $project }{ history } || []};
        @history = grep { $_->{ id } >= $id } @history;
        $state->{ project }{ $project }{ history } = \@history;
    }

    my @logs = @{ $state->{ logs } };
    @logs = grep { $_->{ id } >= $id } @logs;
    $state->{ logs } = \@logs;

    return;
}

# Returns utf-8 encoded JSON representation of state, for remote API.
#
# Arguments:
#   pretty => if true, use whitespace to make the JSON more human-readable
#   gzip => if true, return gzip-compressed output
#   since_id => if an integer greater than 0, only show messages and states with
#               an ID greater than this (to cut down on traffic)
#
# The returned content may be cached for a few seconds.
sub api_json_content
{
    my ($self, %args) = @_;

    my $pretty = $args{ pretty } ? 1 : 0;
    my $gzip = $args{ gzip } ? 1 : 0;
    my $since_id = $args{ since_id } || 0;

    # cache items live this long, maximum
    my $TTL = 10;

    my $key = "pretty=$pretty,gzip=$gzip,since_id=$since_id";
    alias my $cache = $self->{ cached_json }{ $key };

    # invalidate cache item older than $TTL
    if ($cache && (AE::now() - $cache->{ when } > $TTL)) {
        $cache = undef;
    }

    if (!$cache) {
        my %state = %{ $self->{ state } };
        $state{ when } = timestamp();
        if ($since_id) {
            %state = %{ dclone( \%state ) };
            $self->cut_state_by_id( \%state, $since_id );
        }
        my $encoder = JSON->new();
        $encoder->pretty( $pretty );
        $encoder->utf8( 1 );

        my $json = $encoder->encode( \%state );
        my $content;
        if ($gzip) {
            if (!gzip( \$json => \$content )) {
                die "gzipping JSON for HTTP: $GzipError";
            }
        } else {
            $content = $json;
        }

        $cache = {
            when => AE::now(),
            content => $content,
        };

        # periodically destroy the entire cache (simplest way to evict the since_id entries
        # which would otherwise grow unbounded)
        $self->{ cached_json_timer } ||= AE::timer( 60*15, 0, sub {
            delete $self->{ cached_json };
            delete $self->{ cached_json_timer };
        });
    }

    return $cache->{ content };
}

# ============================== EVENT SOURCES ==========================================
# Events from Jenkins, Gerrit or Unix signals may cause some coros to be woken up.

# Waits and returns once gerrit activity occurs on the given project,
# or $timeout seconds have elapsed.
# Returns true iff activity occurred.
sub wait_for_gerrit_activity
{
    my ($self, $project_id, $timeout) = @_;

    my $gerrit_url = $self->project_config( $project_id, 'GerritUrl' );
    my $gerrit_host_port = $gerrit_url->host_port();
    my $gerrit_project = $self->gerrit_project( $project_id );

    alias my $signal = $self->{ gerrit_project_signal }{ $gerrit_host_port }{ $gerrit_project };
    $signal ||= Coro::Signal->new();

    my $out;

    if ($self->wait_for_signal( $signal, $timeout )) {
        $out = 1;
        $self->logger( )->info( 'woke up by event from gerrit' );
    }

    $signal = undef;

    return $out;
}

# Creates and returns a handle to a gerrit stream-events object for the given $gerrit URL
sub create_gerrit_stream_events_watcher
{
    my ($self, $gerrit) = @_;

    return QtQA::Gerrit::stream_events(
        url => $gerrit,
        on_event => sub {
            my (undef, $data) = @_;
            $self->handle_gerrit_stream_event( $gerrit, $data );
        }
    );
}

# Handler for incoming events from gerrit, may wake up coros in wait_for_gerrit_activity()
sub handle_gerrit_stream_event
{
    my ($self, $gerrit, $event) = @_;

    # ref-updated is the only relevant type for us
    if ($event->{ type } ne 'ref-updated') {
        return;
    }

    my $project = $event->{ refUpdate }{ project };
    my $gerrit_host_port = $gerrit->host_port();
    if (my $signal = $self->{ gerrit_project_signal }{ $gerrit_host_port }{ $project }) {
        $signal->broadcast();
    }

    return;
}

# Waits and returns once activity occurs on the given Jenkins project
# or $timeout seconds have elapsed.
# Returns true iff activity occurred.
sub wait_for_jenkins_activity
{
    my ($self, $project_id, $timeout) = @_;

    alias my $signal = $self->{ jenkins_job_signal }{ $project_id };
    $signal ||= Coro::Signal->new();

    my $out;

    if ($self->wait_for_signal( $signal, $timeout )) {
        $self->logger( )->info( 'woke up by event from jenkins' );
        $out = 1;
    }

    $signal = undef;

    return $out;
}

# Waits and returns once activity occurs on the given Coro::Signal
# or $timeout seconds have elapsed.
# Returns true iff activity occurred.
sub wait_for_signal
{
    my ($self, $signal, $timeout) = @_;

    my $cb = Coro::rouse_cb();
    $signal->wait(
        sub {
            $cb->( 1 );
        }
    );

    my $w = AE::timer(
        $timeout,
        0,
        sub {
            $signal = undef;
            $cb->();
        },
    );

    return Coro::rouse_wait( $cb );
}

# Returns a Coro::Signal which may be used to wait for a 'resume from error' event,
# creating it if necessary.
sub resume_from_error_signal
{
    my ($self) = @_;

    alias my $signal = $self->{ coro_resume_from_error_signal };
    if (!$signal) {
        $signal = Coro::Signal->new( );

        # destroy the signal after a single event
        $signal->wait(
            sub {
                $signal = undef;
            }
        );
    }

    return $signal;
}

# Waits until we are requested to resume from errors (e.g. by SIGUSR2)
sub wait_for_resume_from_error_signal
{
    my ($self) = @_;

    local $Coro::current->{ desc } = "$Coro::current->{ desc } - suspended due to error";

    $self->resume_from_error_signal( )->wait();

    return;
}

# Creates and returns a handle to some watchers for various Unix signals.
sub create_unix_signal_watcher
{
    my ($self) = @_;

    my %out;

    my $log = $self->logger( );

    # Exit normally on these
    foreach my $sig (qw(INT TERM)) {
        $out{ $sig } = AnyEvent->signal(
            signal => $sig,
            cb => sub {
                $log->notice( 'Exiting due to signal.' );
                $self->loop_exit( 0 );
            }
        );
    }

    # Don't crash on HUP
    $out{ HUP } = AnyEvent->signal( signal => 'HUP', cb => sub {} );

    # USR1 will reload code and config
    $out{ USR1 } = AnyEvent->signal(
        signal => 'USR1',
        cb => sub {
            $log->notice( 'USR1 received; reloading' );
            AnyEvent::Watchdog::Util::restart_in( 5 );
            $self->loop_exit( 0 );
        }
    );

    # USR2 can be sent to resume from errors
    $out{ USR2 } = AnyEvent->signal(
        signal => 'USR2',
        cb => sub {
            $log->notice( 'USR2 received; resuming any suspended tasks' );
            $self->resume_from_error_signal()->broadcast();
        }
    );

    return \%out;
}

# Creates and returns a debugger object, if enabled in config
sub create_debugger
{
    my ($self) = @_;

    my $debugger_port = eval { $self->config( 'Global', 'DebugTcpPort' ) };
    return unless $debugger_port;

    my $log = $self->logger();

    require Coro::Debug;
    my $out = Coro::Debug->new_tcp_server( $debugger_port );

    $log->warning( "POSSIBLE SECURITY RISK: debugger enabled on port $debugger_port" );

    return $out;
}

# Creates and returns an object to restart self, if RestartInterval is set
sub create_restarter
{
    my ($self) = @_;

    my $interval = eval { $self->config( 'Global', 'RestartInterval' ) };
    return unless $interval;

    my $log = $self->logger();

    my $timer = AE::timer($interval, 0, sub {
        $log->notice( 'RestartInterval elapsed, restarting.' );
        AnyEvent::Watchdog::Util::restart_in( 5 );
        $self->loop_exit( 0 );
    });

    $log->notice( 'Restart scheduled for ' . timestamp( gmtime() + $interval ) );

    return $timer;
}

# Creates all top-level event sources
sub create_event_watchers
{
    my ($self) = @_;

    $self->{ httpd } = $self->create_httpd( );
    $self->{ jenkins_tcpd } = $self->create_tcp_server( 'TcpPort', \&handle_jenkins_event );
    $self->{ admin_tcpd } = $self->create_tcp_server( 'AdminTcpPort', \&handle_admin_cmd );
    $self->{ unix_signal_watcher } = $self->create_unix_signal_watcher( );
    $self->{ debugger } = $self->create_debugger( );
    $self->{ restarter } = $self->create_restarter( );

    return;
}

# ============================================= LOGGING =================================

# Returns the logger object (Log::Dispatch).
# Example usage:
#
#   $self->logger()->warning( 'something bad happened!' );
#
sub logger
{
    my ($self) = @_;

    return $self->{ logger };
}

# Returns a human-readable list of log output destinations,
# and a Log::Dispatch output specifier list, as two arrayrefs.
sub logger_outputs
{
    my ($self) = @_;

    my @logging_to = ('syslog');

    my @outputs = (
        [
            'Syslog',
            name => 'syslog',
            min_level => 'notice',
            facility => 'daemon',
            ident => 'qt-jenkins-integrator',
            callbacks => sub { $self->encode_locale_log_message( @_ ) },
        ]
    );

    # output to stdout only if we're connected to a terminal
    if (IO::Interactive::is_interactive()) {
        push @logging_to, 'terminal';
        push @outputs, [
            'Screen',
            name => 'screen',
            min_level => 'debug',
            newline => 1,
            callbacks => sub { $self->encode_locale_log_message( @_ ) },
        ];
    }

    if (my @mailto = eval { $self->config( 'Global', 'MailTo' ) }) {
        push @logging_to, @mailto;

        my %mail_args = (
            subject => 'Problems...',
        );
        $self->fill_mail_args( \%mail_args );

        push @outputs, [
            '+QtQA::Log::Dispatch::Email::MailSender',
            min_level => 'error',
            prefix => sub { timestamp() . ': ' },
            header => q{Some problems occurred recently...},
            %mail_args
        ];
    }

    return (\@logging_to, \@outputs);
}

# Log::Dispatch callback to format a log message for printing
sub format_log_message
{
    my ($self, %data) = @_;

    my $message = $data{ message };

    # strip useless trailing whitespace
    $message =~ s{\s+\z}{};

    # add coro desc, conceptually the currently executing task, to each log message
    if (my $desc = $Coro::current->{ desc }) {
        $message = "[$desc] $message";
    }

    return $message;
}

# Log::Dispatch callback to save a log message into state, exposing it
# via remote API
sub record_log_message
{
    my ($self, %data) = @_;

    my $message = $data{ message };

    alias my $logs = $self->{ state }{ logs };

    push @{ $logs }, {
        when => timestamp(),
        message => $message,
        id => $self->next_id(),
    };
    while (@{ $logs } > $MAX_LOGS) {
        shift @{ $logs };
    }
    return $message;
}

# encodes a Log::Dispatch message according to the current locale
# (e.g. for console or syslog)
sub encode_locale_log_message
{
    my ($self, %data) = @_;

    return encode( 'locale', $data{ message }, Encode::FB_PERLQQ );
}

# Create and return a Log::Dispatch object with appropriate config.
sub create_logger
{
    my ($self) = @_;

    my ($logging_to, $outputs) = $self->logger_outputs();

    my $logger = Log::Dispatch->new(
        outputs => $outputs,
    );

    $logger->add_callback( sub { $self->format_log_message( @_ ) } );
    $logger->add_callback( sub { $self->record_log_message( @_ ) } );

    $self->{ logger } = $logger;

    # this single line always goes to stdout to avoid the script appearing entirely silent
    local $LIST_SEPARATOR = ', ';
    print "Logging to @{ $logging_to }\n";

    return;
}

# Insert/update Mail::Sender arguments into $args, according to the configuration
# of the given $project_id (which may be undefined for global configuration only).
sub fill_mail_args
{
    my ($self, $args, $project_id) = @_;

    my %config_mandatory = (
        MailTo => 'to',
    );
    my %config = (
        %config_mandatory,
        MailFrom => 'from',
        MailReplyTo => 'replyto',
        MailSmtp => 'smtp',
    );

    my %defaults = (
        smtp => 'localhost',
    );

    while (my ($config, $arg) = each %config) {
        my @value = eval { $self->project_config( $project_id, $config ) };
        next unless @value;
        $args->{ $arg } = (@value > 1) ? \@value : $value[0];
    }

    while (my ($config, $arg) = each %config_mandatory) {
        next if defined $args->{ $arg };
        croak "can't send mail: missing mandatory configuration value '$config'";
    }

    while (my ($arg, $value) = each %defaults) {
        $args->{ $arg } //= $value;
    }

    # this one is a bit special, it prepends to (rather than overwrites) the input argument
    if (my $subject_prefix = eval { $self->project_config( $project_id, 'MailSubjectPrefix' ) }) {
        $args->{ subject } = "$subject_prefix ".$args->{ subject };
    }

    return;
}


# ========================================= INITIALIZATION ==============================

# Create the top-level Coro for each enabled project.
sub create_project_coros
{
    my ($self) = @_;

    my @projects = @{ $self->{ projects }};
    my $state = $self->{ state };

    my $log = $self->logger();

    foreach my $project (@projects) {
        alias my $project_state = $state->{ project }{ $project }{ state };
        if ($project_state) {
            $log->notice( "$project resuming from state '$project_state->{ name }'" );
        } else {
            $log->notice( "$project is a new project, starting at state 'start'" );
            $project_state = {
                name => 'start',
                id => $self->next_id(),
                when => timestamp()
            };
        }

        async {
            $self->do_project_state_machine( $project );
        };
    }

    # Find any projects for which we have some state, but they are not configured.
    # These would generally be disabled projects.
    foreach my $known_project (keys %{ $self->{ state }{ project } }) {
        if (! grep { $known_project eq $_ } @projects) {
            $log->error( "Project $known_project has some state, but is not configured. Ignoring." );
        }
    }

    return;
}

# Returns the path to the desired working directory, creating it if necessary.
sub ensure_working_directory
{
    my ($self) = @_;

    my $dir = $self->config( 'Global', 'WorkingDirectory' );

    if (! -d $dir) {
        mkpath( $dir );
        $self->logger()->notice( "Created working directory $dir" );
    }

    return $dir;
}

# main entry point
sub run
{
    my ($self, @args) = @_;

    local $Tie::Persistent::Readable = 1;
    local $OUTPUT_AUTOFLUSH = 1;

    my %options;
    GetOptionsFromArray( \@args,
        'config=s' => \$self->{ config_file },
        'o=s' => \%options,
        'h|help|?' => sub { pod2usage(1) },
    ) || die;

    # Load our configuration from file (in addition to command-line options)
    $self->load_config( \%options );

    # create logger and force all warnings through it
    $self->create_logger( );
    local $Coro::State::WARNHOOK = sub {
        $self->logger()->warning( @_ );
    };

    # chdir into the directory we'll be working from
    $self->{ CWD } = $self->ensure_working_directory( );
    chdir( $self->{ CWD } );

    # Load state from our last run, if any.
    # The state file is flocked, ensuring that no other instance is running.
    $self->lock_and_load_state( );

    # Construct handlers for any events (incoming http requests, etc.)
    $self->create_event_watchers( );

    # Construct the main coros for each project.
    $self->create_project_coros( );

    my $out = $self->loop_exec( );

    $self->unlock_and_unload_state( );

    return $out;
}

exit( __PACKAGE__->new( )->run( @ARGV ) ) unless caller;
1;
