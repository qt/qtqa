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

=head1 NAME

qt-jenkins-ci.pl - perform gerrit CI workflow from within Jenkins

=head1 SYNOPSIS

  ./qt-jenkins-ci.pl <options> <command>

Run underlying (gerrit) commands to support the staging build lifecycle.

=head2 COMMANDS

=over

=item new_build

Start a new build (gerrit staging-new-build) and write various properties
of the build into a set of property files.  The property files should be
loaded by Jenkins slaves.

Options:

=over

=item --properties-dir <path>

Mandatory; the directory where property files shall be created.

The property files should be read on the slaves by the "Envfile" Jenkins
plugin. The correct Envfile path is:

  <path>/qt-ci-${BUILD_TAG}.properties

..., where <path> is the value passed to --properties-dir.

This script will automatically remove old properties files from this directory
when appropriate.

=back

=item complete_build

Inform gerrit that a build has completed (gerrit staging-approve).

The Jenkins build status determines the gerrit build status (pass or fail).

A summary of the build, and links to build logs, will be pasted as gerrit comment(s).

=back

=head2 GLOBAL OPTIONS

These options may be used with any command.

=over

=item --set key=value [, key=value ...]

Set one or more properties, instead of discovering them from Jenkins.

Generally, this script is expected to be run within a Jenkins build. From within
Jenkins, all relevant configuration details (such as the tested repository,
the build results etc) can be automatically discovered.

If problems occur during autodiscovery, or for testing purposes when running
outside of Jenkins, each configuration value may be explicitly set with this
option.

See B<PROPERTIES> for details on each property which may be overridden.

=item --force-jenkins-host <HOSTNAME>

=item --force-jenkins-port <PORTNUMBER>

When fetching any data from Jenkins, disregard the host and port portion
of Jenkins URLs and use these instead.

This is useful for network setups (e.g. port forwarding) where the Jenkins
host cannot access itself using the outward-facing hostname, or simply to
avoid unnecessary round-trips through a reverse proxy setup.

=back

=head2 PROPERTIES

Each "property" represents some configuration value of this script.

Properties are used internally by this script, and also passed to Jenkins slaves
during the build as environment variables (prefixed with 'qt_ci_' to avoid clashes).

The following properties are supported:

=over

=item gerrit_port

ssh port number used for communication with gerrit.

Default: discovered from Jenkins SCM configuration

=item gerrit_host

Gerrit host address.

Default: discovered from Jenkins SCM configuration

=item gerrit_user

Gerrit username. Must have permission for staging-new-build and staging-approve.

Default: discovered from Jenkins SCM configuration

=item gerrit_build_id

The build ID used in Gerrit.  Short name only (i.e. not including 'refs/builds/' prefix).

Default: derived from Jenkins job name and build number, e.g. "jenkins-${JOB_NAME}-${BUILD_NUMBER}"

=item gerrit_project

The short name of the project used in Gerrit, e.g. 'qt/qtbase'.

Default: discovered from Jenkins SCM configuration

=item gerrit_branch

The short name of the branch used in Gerrit, e.g. 'master'.
Note that the destination branch and staging branch must be the same
(e.g. refs/staging/master will be used as the staging branch for refs/heads/master).

Default: discovered from Jenkins SCM configuration

=item gerrit_git_url

The git URL of the Gerrit repository under test, e.g. 'ssh://codereview.qt-project.org:29418/qt/qtbase'

Default: discovered from Jenkins SCM configuration

=item jenkins_job_name

The Jenkins C<master> job name, e.g. 'QtBase_master_Integration'.

Note that this is always equal to the job name from the master, which can differ
from the content of the JOB_NAME environment variable on slaves. For example,
a multi-configuration job may have several child jobs:

=over

=item QtBase_master_Integration

=item QtBase_master_Integration/cfg=linux-g++_Ubuntu_10.04_x86

=item QtBase_master_Integration/cfg=macx-g++_OSX_10.6

=back

The jenkins_job_name property (and hence the qt_ci_jenkins_job_name environment
variable) will be 'QtBase_master_Integration' for all of the above jobs.

Default: JOB_NAME environment variable on master

=item jenkins_build_number

The Jenkins build number, e.g. 123.

Default: BUILD_NUMBER environment variable

=item jenkins_build_url

The Jenkins build URL, e.g. 'http://jenkins.example.com/job/MyJob/123'

Default: BUILD_URL environment variable

=item jenkins_build_result

The Jenkins build result string, e.g. 'SUCCESS' or 'FAILURE'.

Note: this is not passed to the Jenkins slaves, since the value does
not make sense until after the build has completed. It is only valid
in a post-build step.

Default: discovered from Jenkins JSON API

=item jenkins_build_summary

The Jenkins build summary, a few paragraphs of text which may be
pasted as a gerrit comment.

Note: this is not passed to the Jenkins slaves, since the value does
not make sense until after the build has completed. It is only valid
in a post-build step.

Default: generated by the summarize-jenkins-build.pl script

=back

=head2 USAGE WITHIN JENKINS

This script is exclusively intended to be used within Jenkins.

It performs the following tasks:

=over

=item *

Informs gerrit when builds have started and completed, and passes
the build results to gerrit.

=item *

Passes some values calculated on the master into each Jenkins slave.

=back

To achieve the above, the following Jenkins setup should be used:

=over

=item Job setup

A "multi-configuration project" should be used, where each configuration
represents a relevant platform for testing Qt.

=item Git setup

The Git SCM plugin should be used in Jenkins.

The repository URL should be an SSH gerrit URL, and the staging
branch should be polled. For example:

  url: ssh://codereview.qt-project.org:29418/qt/qtbase
  refspec: +refs/staging/master:refs/remotes/origin/master-staging
  branches to build: master-staging
  poll SCM: */3 * * * *

Note the 'master-staging' branch does not actually exist on the remote,
but we create it by our refspec, because the Git plugin can only correctly
operate on branches or tags, not arbitrary refs.

=item new_build setup

The pre-scm-buildstep plugin should be used to invoke this script with
the new_build command before each build. (This implies that this script is
installed on the master somewhere.)

Since the new_build command should only be executed on the master, the
conditional build step plugin should be used to ensure the command is
only run when NODE_LABELS is 'master'.

The --properties-dir argument should point to an existing directory on
the master, and should match the Envfile plugin setup (see next point).

  Run buildstep before SCM runs:
    Conditional step (single):
      Strings match: ${NODE_LABELS}, master
      Execute shell: $HOME/qtqa/scripts/jenkins/qt-jenkins-ci.pl new_build --properties-dir /tmp

=item Envfile setup

The Envfile plugin should be used to pass some settings calculated on
the master through to each slave. Currently, this is only needed for
passing the gerrit_build_id property.

  Set environment variables through a file:
    File path: /tmp/qt-ci-${BUILD_TAG}.properties

Note that the ${BUILD_TAG} macro expands to a different value on each slave.
This is the reason why this script will write one property file per configuration.

=item Build setup

The build steps may be set up in any desired manner and they do not need
to use this script. However, they may use any of the properties set by this
script, as environment variables prefixed with 'qt_ci_'.

=item complete_build setup

The PostBuildScript plugin should be used to run this script with the
complete_build command at the end of each build. This will inform Gerrit of
the build result, and post an informative link onto the Gerrit change.

Similarly as the pre-build step, a check must be put in place to ensure the
command is only run on the master.

  [PostBuildScript] - Execute a set of scripts
    Conditional step (single):
      Strings match: ${NODE_LABELS}, master
      Execute shell: $HOME/qtqa/scripts/jenkins/qt-jenkins-ci.pl complete_build

=back

=cut

package QtQA::App::JenkinsCI;

use strict;
use warnings;

use AnyEvent::Util;
use AnyEvent;
use Carp qw( confess );
use Data::Dumper;
use English qw( -no_match_vars );
use File::Basename;
use File::Slurp qw( write_file );
use File::Spec::Functions;
use FindBin;
use Getopt::Long qw( GetOptionsFromArray :config pass_through );
use JSON;
use Pod::Usage;
use Readonly;
use URI;

# Time to live for property files, in seconds
Readonly my $PROPERTY_FILE_TTL => 60*60*24*2;

# summarize-jenkins-build script
Readonly my $SUMMARIZE_JENKINS_BUILD => catfile( $FindBin::Bin, 'summarize-jenkins-build.pl' );

# ======================= static ==============================================

# Returns environment variable for $key, or dies if unset.
#
# The error message will hint to the user that they may try to override
# the value with '--set', if $property_key is set.
#
sub env_or_die
{
    my ($key, $property_key) = @_;
    my $out = $ENV{ $key };
    if (!$out) {
        my $error = "Error: $key environment variable is not set\n";
        if ($property_key) {
            $error .= "  If running outside of Jenkins, try: --set $property_key=<value>\n";
        }
        confess $error;
    }
    return $out;
}

# Fetch a $url and return its content, or die on error.
sub fetch_to_scalar
{
    my ($url) = @_;
    my $req = http_request( GET => $url, Coro::rouse_cb() );
    my ($data, $headers) = Coro::rouse_wait();
    if ($headers->{ Status } != 200) {
        confess "fetch $url: $headers->{ Status } $headers->{ Reason }";
    }
    return $data;
}

# Fetch a $url, which must contain JSON, and return the corresponding perl representation.
# Dies on error.
sub fetch_json_data
{
    my ($url) = @_;

    my $json = fetch_to_scalar( $url );

    return decode_json( $json );
}

# Run a command.
#
# The API of this function is equal to AnyEvent::Util::run_cmd with
# the following differences:
#
#   - the command will be automatically killed if it does not complete
#     within a certain amount of time (overridable by 'timeout' option,
#     in seconds). When this occurs, the exit status is -1
#
#   - the $$ option may not be passed into this function, since it
#     is already used internally.
#
sub run_timed_cmd
{
    my ($cmd, %options) = @_;

    my $timeout = delete $options{ timeout } || 60*15;

    my $pid;

    # command may exit normally or via timeout
    my $cv = run_cmd( $cmd, %options, '$$' => \$pid );
    my $timer = AnyEvent->timer( after => $timeout, cb => sub {
        local $LIST_SEPARATOR = '] [';
        warn "command [@{ $cmd }] timed out after $timeout seconds\n";

        kill( 15, $pid );
        $cv->send( -1 );
    });

    return $cv;
}

# Run a command, robustly.
#
# The command may be retried several times, depending on the exit code.
#
# Dies if the command doesn't eventually succeed.
#
# Named parameter include:
#
#   stdin => some data to send to the stdin of the process (e.g. for staging-approve)
#   cmd => arrayref specifying the command to run
#   retry_exitcodes => arrayref specifying exit codes on which to retry
#
sub do_robust_cmd
{
    my (%args) = @_;

    my @cmd = @{ $args{ cmd } };

    my @run_cmd_options = (
        \@cmd,
    );
    if ($args{ stdin }) {
        push @run_cmd_options, (
            '<' => \$args{ stdin }
        );
    }

    print "+ @cmd\n";

    my $attempts = 8;
    my $sleep = 1;
    my @retry_exitcodes = @{ $args{ retry_exitcodes } || []};

    while (my $status = run_timed_cmd( @run_cmd_options )->recv()) {
        my $exitcode = $status >> 8;

        my $retry = grep { $_ == $exitcode } @retry_exitcodes;

        local $LIST_SEPARATOR = '] [';
        if (!$retry) {
            confess "[@cmd] exited with status $status";
        }

        if (!$attempts) {
            confess "[@cmd] repeatedly failed after several attempts, giving up.";
        }

        warn "[@cmd] had an error (exit code $exitcode), trying again in $sleep seconds ...\n";
        --$attempts;
        sleep( $sleep );
        $sleep *= 2;
    }

    return;
}

# Like qx(), but dies on non-zero exit code.
sub safe_qx
{
    my (@cmd) = @_;

    my $stdout;
    my $stderr;
    my $status = run_timed_cmd(
        \@cmd,
        '>' => \$stdout,
        '2>' => \$stderr,
    )->recv();

    if ($status != 0) {
        local $LIST_SEPARATOR = '] [';
        confess
            "[@cmd] exited with status $status"
           .($stdout ? "\noutput: $stdout" : q{})
           .($stderr ? "\nerror: $stderr" : q{});
    }

    return $stdout;
}

# ======================= instance ============================================

# Remove any old qt-ci-.*.properties file from $dir.
sub clean_properties_dir
{
    my ($self, $dir) = @_;

    my $now = time();

    foreach my $file (glob "$dir/qt-ci-*.properties") {
        my (@stat) = stat( $file );
        next unless @stat;

        my $mtime = $stat[ 9 ] || next;
        my $age = $now - $mtime;
        next unless ($age > $PROPERTY_FILE_TTL);

        # File is old.  Remove it...
        if (!unlink( $file )) {
            # Maybe somebody else removed it?
            my $error = $!;
            if (-e $file) {
                warn "Warning: could not remove $file: $error\n";
            }
            next;
        }

        print "Removed stale $file\n";
    }

    return;
}

# Write all properties to files in $dir.
#
# One file is created for each configuration, so that the files may
# be loaded by the pattern:
#
#   <dir>/qt-ci-${BUILD_TAG}.properties
#
sub write_properties
{
    my ($self, $dir) = @_;

    my $job_name = $self->jenkins_job_name( );
    my $build_number = $self->jenkins_build_number( );
    my $build_ref = $self->gerrit_build_ref( );

    my $content = q{};
    foreach my $key (sort keys %{ $self->{ cfg } }) {
        $content .= "qt_ci_$key=$self->{ cfg }{ $key }\n";
    }

    foreach my $config ($self->jenkins_configurations( )) {
        # Example:
        # /tmp/qt-ci-jenkins-QtBase_master_Integration-cfg=win32-msvc2010_Windows_7-170.properties
        my $file = catfile( $dir, "qt-ci-jenkins-${job_name}-${config}-${build_number}.properties" );
        write_file(
            $file,
            { err_mode => 'carp' },
            $content,
        );
        print "Wrote $file\n";
    }

    return;
}

# Returns a version of $url possibly with the host and port replaced, according
# to the --force-jenkins-host and --force-jenkins-port command-line arguments.
sub maybe_rewrite_url
{
    my ($self, $url) = @_;

    if (!$self->{ force_jenkins_host } && !$self->{ force_jenkins_port }) {
        return $url;
    }

    my $parsed = URI->new( $url );
    if ($self->{ force_jenkins_host }) {
        $parsed->host( $self->{ force_jenkins_host } );
    }
    if ($self->{ force_jenkins_port }) {
        $parsed->port( $self->{ force_jenkins_port } );
    }

    return $parsed->as_string();
}

# Returns the configuration data for the Jenkins job (fetched on first use).
sub jenkins_job_config
{
    my ($self) = @_;

    if (!$self->{ jenkins_job_config }) {
        my $job_url = $self->maybe_rewrite_url( env_or_die( 'JOB_URL' ) );
        # Add any other required data to the 'tree' parameter, as needed
        $self->{ jenkins_job_config } = fetch_json_data( "$job_url/api/json?tree=activeConfigurations[name],scm[userRemoteConfigs[url,refspec]]" );
    }

    return $self->{ jenkins_job_config };
}

# Returns the data for the current Jenkins build (fetched on first use).
sub jenkins_build_data
{
    my ($self) = @_;

    if (!$self->{ jenkins_build_data }) {
        my $build_url = $self->jenkins_build_url( );
        # Add any other required data to the 'tree' parameter, as needed
        $self->{ jenkins_build_data } = fetch_json_data( "$build_url/api/json?tree=result" );
    }

    return $self->{ jenkins_build_data };
}

# Returns a list of all active Jenkins configurations in the current job.
sub jenkins_configurations
{
    my ($self) = @_;

    if (!$self->{ jenkins_configurations }) {
        my @cfgs = @{ $self->jenkins_job_config()->{ activeConfigurations } || []};
        if (!@cfgs) {
            confess 'No activeConfigurations found in Jenkins job config';
        }
        $self->{ jenkins_configurations } = [ map { $_->{ name } } @cfgs ];
    }

    return @{ $self->{ jenkins_configurations } };
}

# Returns the git configuration in the Jenkins job.
sub jenkins_git_config
{
    my ($self) = @_;

    if (!$self->{ jenkins_git_config }) {
        my $cfg = $self->jenkins_job_config()->{ scm };
        if (!$cfg || !$cfg->{ userRemoteConfigs }) {
            confess 'Error: scm data is missing from jenkins configuration';
        }
        my $count = scalar( @{ $cfg->{ userRemoteConfigs } || []} );
        if ($count != 1) {
            confess "Error: in scm data, expected one userRemoteConfig, got $count\n";
        }
        $self->{ jenkins_git_config } = $cfg->{ userRemoteConfigs }[0];
    }

    return $self->{ jenkins_git_config };
}

sub gerrit_port
{
    my ($self) = @_;

    return $self->{ cfg }{ gerrit_port } //= $self->gerrit_parsed_url( )->port( );
}

# Returns a user@host string, suitable for e.g. ssh.
# If user is unknown, just returns the host.
sub gerrit_user_at_host
{
    my ($self) = @_;

    my $host = $self->gerrit_host( );
    if (my $user = $self->gerrit_user( )) {
        return $user . '@' . $host;
    }
    return $host;
}

sub gerrit_host
{
    my ($self) = @_;

    return $self->{ cfg }{ gerrit_host } //= $self->gerrit_parsed_url()->host( );
}

sub gerrit_user
{
    my ($self) = @_;

    return $self->{ cfg }{ gerrit_user } //= ($self->gerrit_parsed_url()->user( ) || q{});
}

sub gerrit_build_id
{
    my ($self) = @_;

    return $self->{ cfg }{ gerrit_build_id } //= 'jenkins-'.$self->jenkins_job_name( ).'-'.$self->jenkins_build_number( );
}

sub gerrit_project
{
    my ($self) = @_;

    if (!$self->{ cfg }{ gerrit_project }) {
        my $project = $self->gerrit_parsed_url()->path( );
        # Remove leading / and trailing .git (if any)
        $project =~ s{^/}{};
        $project =~ s{\.git$}{};
        $self->{ cfg }{ gerrit_project } = $project;
    }

    return $self->{ cfg }{ gerrit_project };
}

sub gerrit_branch
{
    my ($self) = @_;

    if (!$self->{ cfg }{ gerrit_branch }) {
        eval {
            my $refspec = $self->jenkins_git_config()->{ refspec };

            if (!$refspec) {
                die 'refspec is missing from scm data';
            }

            if ($refspec !~ m{\A\+refs/staging/([^:]+):}) {
                die "refspec of '$refspec' is not understood. Expected '+refs/staging/<somebranch>:...'";
            }

            $self->{ cfg }{ gerrit_branch } = $1;
        };
        if (my $error = $EVAL_ERROR) {
            confess "Error: can't automatically detect staging branch: $error\n"
                   ."Try --set gerrit_branch=<something>\n";
        }
    }

    return $self->{ cfg }{ gerrit_branch };
}

sub gerrit_build_ref
{
    my ($self) = @_;

    return 'refs/builds/' . $self->gerrit_build_id( );
}

sub gerrit_git_url
{
    my ($self) = @_;

    return $self->{ cfg }{ gerrit_git_url } //= $self->jenkins_git_config()->{ url };
}

sub gerrit_parsed_url
{
    my ($self) = @_;

    # Note: not in 'cfg' because not directly exported or overridable.
    return $self->{ gerrit_parsed_url } //= URI->new( $self->gerrit_git_url( ) );
}

sub jenkins_job_name
{
    my ($self) = @_;

    return $self->{ cfg }{ jenkins_job_name } //= env_or_die( 'JOB_NAME', 'jenkins_job_name' );
}

sub jenkins_build_number
{
    my ($self) = @_;

    return $self->{ cfg }{ jenkins_build_number } //= env_or_die( 'BUILD_NUMBER', 'jenkins_build_number' );
}

sub jenkins_build_url
{
    my ($self) = @_;

    return $self->{ cfg }{ jenkins_build_url }
        //= $self->maybe_rewrite_url( env_or_die( 'BUILD_URL', 'jenkins_build_url' ) );
}

sub jenkins_build_result
{
    my ($self) = @_;

    if (!$self->{ cfg }{ jenkins_build_result }) {
        my $data = $self->jenkins_build_data( );
        if (!$data->{ result }) {
            confess "jenkins build data does not contain a 'result' key: ".Dumper( $data );
        }
        $self->{ cfg }{ jenkins_build_result } = $data->{ result };
    }

    return $self->{ cfg }{ jenkins_build_result };
}

sub jenkins_build_summary
{
    my ($self) = @_;

    if (!$self->{ cfg }{ jenkins_build_summary }) {
        my @cmd = ($SUMMARIZE_JENKINS_BUILD, '--url', $self->jenkins_build_url( ));

        my $summary;
        my $status = run_timed_cmd(
            \@cmd,
            '>' => \$summary,
        )->recv();

        if ($status) {
            local $LIST_SEPARATOR = '] [';
            confess "build summarize script [@cmd] exited with status $status";
        }

        $self->{ cfg }{ jenkins_build_summary } = $summary;
    }

    return $self->{ cfg }{ jenkins_build_summary };
}

# Perform the gerrit staging-new-build command, with appropriate arguments.
#
# This function also checks that the build ref was really created with git ls-remote,
# as the staging-new-build command's exit code can't be entirely trusted.
#
sub do_staging_new_build
{
    my ($self) = @_;

    do_robust_cmd(
        retry_exitcodes => [255], # ssh gives 255 on possibly temporary network error,
        cmd => [
            'ssh',
            '-oBatchMode=yes',
            '-p',
            $self->gerrit_port( ),
            $self->gerrit_user_at_host( ),
            'gerrit',
            'staging-new-build',
            '--build-id',
            $self->gerrit_build_id( ),
            '--project',
            $self->gerrit_project( ),
            '--staging-branch',
            $self->gerrit_branch( ),
        ],
    );

    # Now verify the build ref really exists.
    my $build_ref = $self->gerrit_build_ref( );
    my $output = safe_qx(
        'git',
        'ls-remote',
        $self->gerrit_git_url( ),
        $build_ref,
    );
    if (!$output) {
        confess "gerrit staging-new-build exited with a 0 exit code, but build ref $build_ref does not exist\n";
    }

    return;
}

# Perform the gerrit staging-approve command, with appropriate arguments.
sub do_staging_approve
{
    my ($self) = @_;

    do_robust_cmd(
        stdin => $self->jenkins_build_summary(),
        retry_exitcodes => [255],
        cmd => [
            'ssh',
            '-oBatchMode=yes',
            '-p',
            $self->gerrit_port( ),
            $self->gerrit_user_at_host( ),
            'gerrit',
            'staging-approve',
            '--branch',
            $self->gerrit_branch( ),
            '--build-id',
            $self->gerrit_build_id( ),
            '--project',
            $self->gerrit_project( ),
            '--result',
            (($self->jenkins_build_result( ) eq 'SUCCESS') ? 'pass' : 'fail'),
            '--message',
            '-'
        ],
    );

    return;
}

# Entry point of 'new_build'
sub command_new_build
{
    my ($self, @args) = @_;

    my $properties_dir;
    GetOptionsFromArray(
        \@args,
        'properties-dir=s' => \$properties_dir,
    ) || die;

    $properties_dir || die "Missing mandatory --properties-dir\n";

    $self->do_staging_new_build();

    $self->clean_properties_dir( $properties_dir );
    $self->write_properties( $properties_dir );

    return;
}

# Entry point of 'complete_build'
sub command_complete_build
{
    my ($self) = @_;

    $self->do_staging_approve();

    return;
}

# Sets all properties passed through the command-line,
# which should be stored by Getopt::Long in %set.
sub set_cfg_from_command_line
{
    my ($self, %set) = @_;

    while (my ($key, $value) = each %set) {
        $self->{ cfg }{ $key } = $value;
    }

    return;
}

sub new
{
    my ($class) = @_;
    return bless {}, $class;
}

sub run
{
    my ($self, @args) = @_;

    my %set;

    GetOptionsFromArray(
        \@args,
        'help|h' => sub { pod2usage(2) },
        'set=s%{,}' => \%set,
        'force-jenkins-host=s' => \$self->{ force_jenkins_host },
        'force-jenkins-port=i' => \$self->{ force_jenkins_port },
    ) || die;

    my $command = shift @args;
    $command || die "Error: no command specified.\n";

    $self->set_cfg_from_command_line( %set );

    my $sub_ref = $self->can( "command_$command" );
    if (!$sub_ref) {
        die "Error: '$command' is not a valid command. Try --help.\n";
    }

    $sub_ref->( $self, @args );

    return;
}

#==============================================================================

QtQA::App::JenkinsCI->new( )->run( @ARGV ) if (!caller);
1;
