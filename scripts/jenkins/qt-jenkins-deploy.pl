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

qt-jenkins-deploy.pl - deploy Jenkins configuration from templates

=head1 SYNOPSIS

  # jenkins.conf contains template for various Jenkins jobs and nodes...
  $ ./qt-jenkins-deploy.pl --conf jenkins.conf --user admin
  Jenkins API token or password for admin: ******
  job QtBase_master_Integration: no changes required
  job QtDeclarative_master_Integration: updated:
    - this
    - that
    + newthis
    + newthat
  node ubuntu-builder-01: created
  node ubuntu-builder-02: created
  (...)

Quickly deploy or update a set of Jenkins jobs and nodes, based on some
local configuration files.

This script provides a means for maintaining Jenkins configuration as
flat files (e.g. under source control with code review), and deploying
various Jenkins jobs or nodes from a single template (which is otherwise
cumbersome to accomplish).

=head2 OPTIONS

=over

=item --conf <file>

Mandatory. Use the specified configuration <file>.

See L<CONFIGURATION FILE> for details on the configuration format.

=item --user <username>

Use the specified username for authentication with Jenkins.

This may be omitted if the Jenkins instance does not require authentication.

=item --password <password>

Use the specified API token or password for authentication with Jenkins.

If omitted, and --user is specified, the script will prompt.

=item --dry-run

If set, no Jenkins data will be modified; the script will instead print
the changes it would make, then exit.

=back

=head2 TEMPLATE FILES

The Jenkins job and node settings are stored in XML files. This script
loads XML templates using the Template Toolkit.

Here is a complete example of a templated node XML:

  <slave>
    <name>[% name %]</name>
    <description>CI node. Contact: [% contact %] [automatically created]</description>
    <remoteFS>[% root %]</remoteFS>
    <label>[% labels %]</label>
    <numExecutors>1</numExecutors>
    <mode>EXCLUSIVE</mode>
    <retentionStrategy class="hudson.slaves.RetentionStrategy$Always"/>
    <launcher class="hudson.slaves.JNLPLauncher"/>
  </slave>

When the template is processed, directives within '[% ... %]' blocks are replaced
with values calculated from the configuration file.  For more details on template
syntax, see http://template-toolkit.org/ or `perldoc Template::Manual').

=head2 CONFIGURATION FILE

This script uses an INI-style configuration file to declare the jobs and
nodes to be managed.

Unless otherwise stated, each variable mentioned here may also be used from within
a template file.

The following sections are handled:

=over

=item [job.<job_name>]

Manage a job of the given name.

Within a job template, this is accessible as the 'name' variable.

The following attributes may be configured on a job:

=over

=item enabled

If 0, the Jenkins job is disabled. Defaults to 1.

=item pretend

If 1, the Jenkins job should operate in pretend mode.

The semantics of pretend mode depends on the job content, but generally
implies that no destructive/permanent effects result from the job.

Defaults to 0.

=item gerrit_host

Hostname of the Gerrit server.

=item gerrit_port

Port number of the Gerrit server. Defaults to 29418.

=item gerrit_project

Project name on the Gerrit server (e.g. "qt/qtbase").

The default is derived from the first portion of the job name;
for example, a job name of "QtBase_master_Integration" results
in "qt/qtbase".

=item custom_repository

Custom repository if needed.

Defaults to empty.

=item testconfig_project

Project name used for the qtqa/testconfig repository
(e.g. "QtBase master Integration"). Note that underscores and
whitespace are treated as equivalent.

The default is equal to the job name.

=item branch

Short name of the branch to test (e.g. "master").

The default is derived from the second portion of the job name;
for example, a job name of "QtBase_master_Integration" results
in "master".

=item poll_cron

cron-style line for SCM polling (see SCM poll documentation in
Jenkins for syntax details).

If omitted, SCM polling is disabled.

=item trigger_cron

cron-style line for periodic triggering of the job.

If omitted, the job is not triggered periodically.

=item publish_xunit

Parameter to enable xUnit jenkins plugin.

Default is not to publish.

=item publish_build

Parameter to publish build results via another Jenkins dashboar,
like https://builds.qt-project.org/.

Default is not to publish.

=item run_remote_job

Parameter to enable additional build step after default job config.

Default is not to run

=item remote_jenkins

Parameter to configure remote Jenkins' URL, where to run the remote job.

=item remote_jenkins_job

Parameter to configure the remote job to be run.

=item log_days_to_keep
=item log_num_to_keep

Variables to configure how jenkins should store the log items.

=item configurations

A list of space-separated test/build configurations, e.g.
"linux-g++-32_Ubuntu_10.04_x86 win32-msvc2010_Windows_7".

It is possible to set a top-level list of configurations,
then add or subtract from that list for specific jobs by
adding a 'configuration += ...' or 'configuration -= ...' line,
as in the following example:

  # default tests on each major desktop platform...
  configurations = linux mac win

  # ...but this job is not supported on windows
  [job.Some_Unix_Thing]
  configurations -= win

Note that only one 'configurations +=' or 'configurations -=' directive
may appear in each block.

=item jenkins_url

URL of the Jenkins server on which the job should be managed.

=item log_upload_url

URL to which CI logs should be uploaded (e.g. via ssh).

=item log_download_url

URL from which CI logs should be downloaded (e.g. via http, to be
linked to from gerrit).

=item job_template

Path to the template XML file to be POSTed to Jenkins.
If a relative path, it is interpreted relative to the configuration
file.

See L<TEMPLATE FILES> for more information.

=item qt_version

Qt version number, used in packaging.

=item qt_license

Qt license type (commercial/opensource), used in packaging.

=item build_type

Used for assigning build jobs to dedicated label.

=item notarize

Enable (yes) or disable (no) notarization.

=item prod_addr

Production server address

=item prod_srv_repo_base_path

Production server repository base path

=item prod_srv_repo_pending_area_dir

Production server directory for updated repository content

=item repo_staging_server_test_repo_dist_work

Production server temporary directory for online repository update process

=item cores

Number of cores in virtual machine

=item repositories

repository sources to be copied into virtual machine

=item label_with_branch

Information if branch is added into label

=item artifacts_download_url

The url where to download the build artifacts, typically via http.

=item artifacts_upload_host

The host server to be used when uploading build artifacts, should be
accessible with SSH/SCP.

=item artifacts_upload_path

The base path on host server where to upload build artifacts.

=item send_status_mail

Parameter to send status e-mail from jenkins by using extended e-mail plugin.

=item boot_script

File that contains Groovy script for booting the machine down after the build.

=item build_trigger

Contains next build job to start if build succeeds.

=item build_flow

Contains the information about the build flow e.g. 5.4.1

=item qt5sha1

Contains sha1 for qt5

=item use_create_nodes_and_vms

Set to '1' if vm-cloner is to be used instead of default cloner

=item url_trigger

Contains url to be polled to start specific build flow compilation

=item module_name

Contains module name e.g. add-on, tech-preview or some other separate qt module not part of qt5.git

=item module_version

Contains module version

=item module_sha1

Contains module sha1

=item git_module_repo

Contains module repository

=item git_module_repo_branch

Contains module repository branch

=item release_description_file

Contains addons application release description file name

=item do_update_staging_repository

Contains information whether we want to update staging repository

=item do_update_production_repository

Contains information whether we want to update prodcution repository

=item force_version_number_increase

Contains information whether we want to force version number increase for an online repository build

=item create_maintenance_tool_resource_file

Contains information wheater maintenance tool resource file is created or not

=item execute_postbuild_action

If set then execute post build action for the build

=item module_doc_build_qt_dependency_package_uri

Contains information whether module needs libs outside essentials package

=item build_combination

Contains combination Filter for build. Filtering build
targets for different releases.

=item squish_test_suite_path

Path to Squish installation

=item squish_config_path

Path to job specifig configurations, needed by Squish Plugin.

=item squish_test_suites

Space separated list of test suites to run, combined with squish_test_suite_path should form valid path to test suite

=item auth_token

Authorization token to be used when triggering the build from other scripts

=item job_description

Description for the job.

=item test_script

Test script that is run in shell/batch without Squish

=item cores

Number of cores to be requested for a job, defaults to 2.

=item installer_type

Type of Qt installer to use in RTA test. Online/Offline/Monolite/Pyside.

=item irc_channel

IRC channel to notify

=item pip_path

Path to Qt for Python wheels.

=item python_version

Python version to be used. Version 2 used as default.

=item ts_product

Product name when logging test data to Squish Team Server.

=item ts_labels

Labels for the job data sent to Squish Team Server.

=item ts_batch

Batch info string for the data sent to Squish Team Server.

=item ts_enabled

Whether to enable sending logs to Squish Team Server.

=item qt_creator

QtCreator version preview/released.

=back

=item [node.<node_basename>]

Manage a node or set of nodes of the given basename.
In this context, the name of a node contains a trailing number,
while the basename of a node is the part of the name prior
to the trailing '-' and number:

  basename: ubuntu-builder
  name: ubuntu-builder-10

'basename' and 'name' may be used from within template files, with
the above semantics.

The following attributes may be configured on a node:

=over

=item basename

Overrides the default basename of the node (described above).

=item contact

A contact email address for this node, e.g. someone who can
be contacted if the node is unexpectedly offline.

=item node_root

The path to the Jenkins root directory on the node,
e.g. "/work", "c:\work". It is recommended to keep this very
short and with no spaces.

=item labels

The labels to be set on the node (space-separated).
In the Qt CI setup, the labels are primarily used as the test
configurations a node is able to participate in.  Windows nodes
should also have the 'windows' label.

Example:

  labels = win32-msvc2010_Windows_7 win32-msvc2010_developer-build_qtnamespace_Windows_7 windows

=item range

Numeric range of identically configured nodes to manage.
May be a single integer or an (x..y) style range.

The numeric suffix of managed nodes will always be zero-padded to at
least two digits, even if the range only requires a single digit.

For example:

  [node.ubuntu-builder]
  Range = 11..20
  # creates ubuntu-builder-11, ubuntu-builder-12, ..., ubuntu-builder-20

  [node.mac-builder]
  Range = 1
  # creates mac-builder-01 only

=item git_location

The path to the git command to be used on this node.
This is generally required only on Windows nodes, as Jenkins seems unable
to find git.cmd from PATH (and it is undesirable to have git.exe in PATH).

Example:

  git_location = c:\Program Files\Git\cmd\git.cmd

=item node_template

Path to the template XML file to be POSTed to Jenkins.
If a relative path, it is interpreted relative to the configuration
file.

See L<TEMPLATE FILES> for more information.

=back

=item [node.<node_basename>.environment]

Set environment variables on the node.

All keys in this block will be applied as environment variables.
For example, it is appropriate to set Visual Studio environment variables here,
if the node will be used exclusively for Visual Studio builds:

  [node.windows-builder.environment]
  INCLUDE = C:\Program Files\Microsoft Visual Studio 10.0\VC\INCLUDE;c:\openssl\include;...
  LIB = C:\Program Files\Microsoft Visual Studio 10.0\VC\LIB;c:\openssl\lib;
  (...)

The entire contents of this block are available as the 'environment' variable
from within templates.

To append to an environment variable rather than override it, use the key
<VARIABLE>+<SOME_ID>, where VARIABLE is the variable to append to and
SOME_ID is any unique identifier. For example, to append to PATH:

  PATH+MSVC = C:\Program Files\Microsoft Visual Studio 10.0\VSTSDB\Deploy;C:\Program Files\Microsoft SDKs\Windows\v7.0A\bin

Note that this is a virtually undocumented Jenkins feature, and not a feature
implemented by this script, so take care when using it.

=back

Default values for jobs and nodes can be set at the top of the configuration
file, outside of any block. For example, if all jobs use the same gerrit server,
gerrit_host should be specified once near the top of the configuration file,
and omitted from each job block.

=cut

package QtQA::App::JenkinsDeploy;

use strict;
use warnings;

use AnyEvent::HTTP;
use AnyEvent;
use Carp qw(confess croak);
use Config::Tiny;
use Coro;
use Data::Compare;
use English qw( -no_match_vars );
use File::Basename;
use File::Spec::Functions qw( :ALL );
use FindBin;
use Getopt::Long qw( GetOptionsFromArray );
use HTTP::Headers;
use IO::Prompt;
use Pod::Usage qw( pod2usage );
use Readonly;
use Template;
use Text::Diff;
use URI;
use XML::Simple;

use lib catfile( $FindBin::Bin, qw(.. lib perl5) );
use QtQA::WWW::Util qw(:all);

# User-Agent used for HTTP requests/responses
Readonly my $USERAGENT => __PACKAGE__;

#============================== static ========================================

# Returns 1 iff xml1, xml2 are identical after parsing
# (i.e. if they are _semantically_ identical - comments, whitespace ignored).
sub compare_xml
{
    my ($xml1, $xml2) = @_;
    my $d1 = XMLin( $xml1 );
    my $d2 = XMLin( $xml2 );
    return Compare( $d1, $d2 );
}

#=============================== instance =====================================

# Calculates and returns an HTTP BASIC authorization string using
# the configured username and password.
#
# If a username is known, but no password is known, prompts for password on
# first use.
sub http_basic_auth_string
{
    my ($self) = @_;

    if ($self->{ auth }) {
        return $self->{ auth };
    }

    my $user = $self->{ user } || confess 'internal error: called with no username';

    # prompt for password on first use, and don't store unnecessarily
    my $password = $self->{ password } || prompt( "Jenkins API token or password for $user: ", '-echo', '*' );

    my $h = HTTP::Headers->new();
    $h->authorization_basic( $user, $password );
    return $self->{ auth } = $h->header( 'Authorization' );
}

# Returns a hashref of appropriate HTTP headers.
# If $headers are provided, the contents are included in the returned hashref.
sub http_headers
{
    my ($self, %in_headers) = @_;

    return {
        'User-Agent' => $USERAGENT,
        ($self->{ user } ? (Authorization => $self->http_basic_auth_string()) : ()),
        %in_headers,
    };
}

# Returns the config value for the specified $key.
#
# If the value is set under $block, it is returned from there;
# otherwise, if it is set under the default block, it is returned from there;
# otherwise, a fatal error occurs.
sub cfg
{
    my ($self, $block, $key) = @_;

    my $cfg = $self->{ cfg };

    if (exists($cfg->{ $block }) && exists($cfg->{ $block }{ $key })) {
        return $cfg->{ $block }{ $key };
    }
    if (exists($cfg->{ _ }{ $key })) {
        return $cfg->{ _ }{ $key };
    }

    croak "configuration error: $key is not set in $block block or in default block\n";
}

# Returns the desired XML for a job, based on the configured job_template.
sub desired_job_xml
{
    my ($self, $name) = @_;

    my $job_template = $self->cfg( "job.$name", 'job_template' );

    my $template_file = $job_template;
    if (!file_name_is_absolute( $template_file )) {
        $template_file = rel2abs( $template_file, dirname( $self->{ ini } ) );
    }

    my $tt = Template->new(
        ABSOLUTE => 1
    );

    # Automatically deteremined gerrit project and branch, used if
    # the job name matches a common pattern and if not otherwise configured.
    my ($auto_gerrit_project, $auto_branch);
    if (
        $name =~ m{
            \A
            ([^_]+)
            _
            (.+)
            _Integration
            \z
        }xms
    ) {
        $auto_gerrit_project = 'qt/'.lc($1);
        $auto_branch = $2;
    }

    my $gerrit_project
        = eval { $self->cfg( "job.$name", 'gerrit_project' ) }
       || $auto_gerrit_project
       || confess "job $name: can't determine gerrit project";

    my $branch
        = eval { $self->cfg( "job.$name", 'branch' ) }
       || $auto_branch
       || confess "job $name: can't determine branch";

    # configurations start from the 'configuration' key, but may be added or subtracted by
    # configurations += or configurations -=, which are simply parsed as 'configuration +' and
    # 'configuration -' keys
    my %configurations = map { $_ => 1 } split( /[ ,]+/, $self->cfg( "job.$name", 'configurations' ) );
    foreach my $add_cfg (eval { split( /[ ,]+/, $self->cfg( "job.$name", 'configurations +' ) ) } ) {
        $configurations{ $add_cfg } = 1;
    }
    foreach my $remove_cfg (eval { split( /[ ,]+/, $self->cfg( "job.$name", 'configurations -' ) ) } ) {
        delete $configurations{ $remove_cfg };
    }
    my @configurations = sort keys %configurations;

    # get squish test suites
    my @squish_test_suites;
    @squish_test_suites = eval { split( /[ ,]+/, $self->cfg( "job.$name", 'squish_test_suites' )) };

    # get boot_script from ini
    my $boot_script_file = eval { $self->cfg( "job.$name", 'boot_script' ) } || q{};
    my $file_contents = '';

    # if file is found read contents to $file_contents variable
    if ($boot_script_file) {
        if (!file_name_is_absolute( $boot_script_file )) {
            $boot_script_file = rel2abs( $boot_script_file, dirname( $self->{ ini } ) );
        }
        open my $file, "<", $boot_script_file or die "Can't read file $boot_script_file\n";
        $file_contents = do { local $/; <$file> };
        close ($file);
    }

    my $data;
    $tt->process(
        $template_file,
        {
            name => $name,
            gerrit_host => eval { $self->cfg( "job.$name", 'gerrit_host' ) } || q{},
            gerrit_port => eval { $self->cfg( "job.$name", 'gerrit_port' ) } // 29418,
            build_trigger => eval { $self->cfg( "job.$name", 'build_trigger' ) } || q{},
            build_flow => eval { $self->cfg( "job.$name", 'build_flow' ) } || q{},
            qt5sha1 => eval { $self->cfg( "job.$name", 'qt5sha1' ) } || q{},
            url_trigger => eval { $self->cfg( "job.$name", 'url_trigger' ) } || q{},
            module_name => eval { $self->cfg( "job.$name", 'module_name' ) } || q{},
            module_version => eval { $self->cfg( "job.$name", 'module_version' ) } || q{},
            module_sha1 => eval { $self->cfg( "job.$name", 'module_sha1' ) } || q{},
            git_module_repo => eval { $self->cfg( "job.$name", 'git_module_repo' ) } || q{},
            git_module_repo_branch => eval { $self->cfg( "job.$name", 'git_module_repo_branch' ) } || q{},
            release_description_file => eval { $self->cfg( "job.$name", 'release_description_file' ) } || q{},
            do_update_staging_repository => eval { $self->cfg( "job.$name", 'do_update_staging_repository' ) } || q{},
            do_update_production_repository => eval { $self->cfg( "job.$name", 'do_update_production_repository' ) } || q{},
            force_version_number_increase => eval { $self->cfg( "job.$name", 'force_version_number_increase' ) } || q{},
            create_maintenance_tool_resource_file => eval { $self->cfg( "job.$name", 'create_maintenance_tool_resource_file' ) } || q{},
            execute_postbuild_action => eval { $self->cfg( "job.$name", 'execute_postbuild_action' ) } || q{},
            module_doc_build_qt_dependency_package_uri => eval { $self->cfg( "job.$name", 'module_doc_build_qt_dependency_package_uri' ) } || q{},
            build_combination => eval { $self->cfg( "job.$name", 'build_combination' ) } || q{},
            gerrit_project => $gerrit_project,
            testconfig_project => eval { $self->cfg( "job.$name", 'testconfig_project' ) } // $name,
            job_template => $job_template,
            branch => $branch,
            log_upload_url => eval { $self->cfg( "job.$name", 'log_upload_url' ) } || q{},
            log_download_url => eval { $self->cfg( "job.$name", 'log_download_url' ) } || q{},
            log_days_to_keep => eval {$self->cfg( "job.$name", 'log_days_to_keep' )} || q{1},
            log_num_to_keep =>  eval {$self->cfg( "job.$name", 'log_num_to_keep' )} || q{4},
            enabled => eval { $self->cfg( "job.$name", 'enabled' ) } // 1,
            pretend => eval { $self->cfg( "job.$name", 'pretend' ) } // 0,
            poll_cron => eval { $self->cfg( "job.$name", 'poll_cron' ) } || q{},
            on_demand => eval { $self->cfg( "job.$name", 'on_demand' ) } // 0,
            use_create_nodes_and_vms => eval { $self->cfg( "job.$name", 'use_create_nodes_and_vms' ) } // 0,
            template_ini_prefix => eval { $self->cfg( "job.$name", 'template_ini_prefix' ) } // $branch,
            trigger_cron => eval { $self->cfg( "job.$name", 'trigger_cron' ) } || q{},
            publish_xunit => eval { $self->cfg( "job.$name", 'publish_xunit' ) } || q{0},
            publish_build => eval { $self->cfg( "job.$name", 'publish_build' ) } || q{0},
            run_remote_job => eval { $self->cfg( "job.$name", 'run_remote_job' ) } || q{0},
            remote_jenkins => eval { $self->cfg( "job.$name", 'remote_jenkins' ) } || q{},
            remote_jenkins_job => eval { $self->cfg( "job.$name", 'remote_jenkins_job' ) } || q{},
            configurations => \@configurations,
            qt_version => eval { $self->cfg( "job.$name", 'qt_version' ) } || q{},
            qt_license => eval { $self->cfg( "job.$name", 'qt_license' ) } || q{},
            build_type => eval { $self->cfg( "job.$name", 'build_type' ) } || q{},
            notarize => eval { $self->cfg( "job.$name", 'notarize' ) } || q{},
            prod_addr => eval { $self->cfg( "job.$name", 'prod_addr' ) } || q{},
            prod_srv_repo_base_path => eval { $self->cfg( "job.$name", 'prod_srv_repo_base_path' ) } || q{},
            prod_srv_repo_pending_area_dir => eval { $self->cfg( "job.$name", 'prod_srv_repo_pending_area_dir' ) } || q{},
            repo_staging_server_test_repo_dist_work => eval { $self->cfg( "job.$name", 'repo_staging_server_test_repo_dist_work' ) } || q{},
            cores => eval { $self->cfg( "job.$name", 'cores' ) } || q{},
            repositories => eval { $self->cfg( "job.$name", 'repositories' ) } || q{},
            label_with_branch => eval { $self->cfg( "job.$name", 'label_with_branch' ) } || q{},
            artifacts_download_url => eval { $self->cfg( "job.$name", 'artifacts_download_url' ) } || q{},
            artifacts_upload_host => eval { $self->cfg( "job.$name", 'artifacts_upload_host' ) } || q{},
            artifacts_upload_path => eval { $self->cfg( "job.$name", 'artifacts_upload_path' ) } || q{},
            send_status_mail => eval { $self->cfg( "job.$name", 'send_status_mail' ) } || q{},
            boot_script => $file_contents,
            squish_test_suite_path => eval { $self->cfg( "job.$name", 'squish_test_suite_path' ) } || q{},
            squish_config_path => eval { $self->cfg( "job.$name", 'squish_config_path' ) } || q{},
            squish_test_suites => \@squish_test_suites,
            auth_token => eval { $self->cfg( "job.$name", 'auth_token' ) } || q{},
            job_description => eval { $self->cfg( "job.$name", 'job_description' ) } || q{},
            suffix_labels => eval { $self->cfg( "job.$name", 'suffix_labels' ) } || q{0},
            test_script => eval { $self->cfg( "job.$name", 'test_script' ) } || q{},
            custom_repository => eval { $self->cfg( "job.$name", 'custom_repository' ) } // 0,
            cores => eval { $self->cfg( "job.$name", 'cores' ) } || q{2},
            irc_channel => eval { $self->cfg( "job.$name", 'irc_channel' ) } || q{},
            installer_type => eval { $self->cfg( "job.$name", 'installer_type' ) } || q{},
            pip_path => eval { $self->cfg( "job.$name", 'pip_path' ) } || q{},
            python_version => eval { $self->cfg( "job.$name", 'python_version' ) } || q{2},
            ts_product => eval { $self->cfg( "job.$name", 'ts_product' ) } || q{},
            ts_labels => eval { $self->cfg( "job.$name", 'ts_labels' ) } || q{},
            ts_batch => eval { $self->cfg( "job.$name", 'ts_batch' ) } || q{},
            ts_enabled => eval { $self->cfg( "job.$name", 'ts_enabled' ) } || q{},
            qt_creator => eval { $self->cfg( "job.$name", 'qt_creator' ) } || q{},
        },
        \$data
    ) || die "job $name: while parsing template: ".$tt->error();

    my $suffix_labels = eval { $self->cfg( "job.$name", 'suffix_labels' ) } || q{0};
    if ($suffix_labels) {
        # Add the configurations to the combination filter and after that replace all
        # instances of the configuration with the suffix of $ini_branch
        my $ini_branch = eval { $self->cfg( "job.$name", 'template_ini_prefix' ) } // $branch;
        foreach my $cfg (@configurations) {
            $data =~ s/<\/combinationFilter>/(cfg == \"$cfg-$ini_branch\") || <\/combinationFilter>/;
            $data =~ s/\<string\>\Q$cfg\E\<\/string\>/<string>$cfg-$ini_branch<\/string>/g;
        }
        # Remove the excess " || " from the end of the combinationFilter string
        $data =~ s/ \|\| <\/combinationFilter/<\/combinationFilter/;
    }

    chomp $data;
    return $data;
}

# Returns the desired XML for a node, based on the configured node_template.
sub desired_node_xml
{
    my ($self, %args) = @_;

    my $cfg_basename = $args{ cfg_basename } || confess;
    my $template_basename = $args{ template_basename } || confess;
    my $name = $args{ name } || confess;

    my $cfg_item = sub {
        my ($key) = @_;
        return $self->cfg( "node.$cfg_basename", $key );
    };

    my $node_template = $cfg_item->( 'node_template' );

    my $template_file = $node_template;
    if (!file_name_is_absolute( $template_file )) {
        $template_file = rel2abs( $template_file, dirname( $self->{ ini } ) );
    }

    my $tt = Template->new(
        ABSOLUTE => 1
    );

    my $data;
    $tt->process(
        $template_file,
        {
            name => $name,
            node_template => $node_template,
            basename => $template_basename,
            contact => $cfg_item->( 'contact' ),
            labels => $cfg_item->( 'labels' ),
            root => $cfg_item->( 'node_root' ),
            environment => $self->{ cfg }{ "node.$cfg_basename.environment" } || {},
            git_location => (eval { $cfg_item->( 'git_location' ) } || q{}),
        },
        \$data
    ) || die "node $name: while parsing template: ".$tt->error();

    chomp $data;
    return $data;
}

# Returns dummy data used to create a new Jenkins slave with the given $name.
#
# The primary method of remotely updating objects in Jenkins is to POST an updated config.xml.
# When creating jobs, Jenkins allows the same config.xml to be sent.
# However, the node API does not support this for some reason. Instead, a form
# must be posted with embedded JSON.
#
# To simplify the creation of nodes, we create a dummy node using the data returned from
# this function, then POST an update afterwards.
sub dummy_node_postdata
{
    my ($name) = @_;
    my $pkg = __PACKAGE__;
    my $json = <<"END_JSON";
            {
                "name": "$name",
                "nodeDescription": "temporary node from $pkg",
                "numExecutors": "1",
                "remoteFS": "/",
                "labelString": "",
                "mode": "EXCLUSIVE",
                "": ["hudson.slaves.JNLPLauncher", "hudson.slaves.RetentionStrategy\$Always"],
                "launcher": {"stapler-class": "hudson.slaves.JNLPLauncher", "tunnel": "", "vmargs": ""},
                "retentionStrategy": {"stapler-class": "hudson.slaves.RetentionStrategy\$Always"},
                "nodeProperties": {"stapler-class-bag": "true"},
                "type": "hudson.slaves.DumbSlave"
            }
END_JSON

    $json =~ s{(?:^|\n) *}{}msg;

    return www_form_urlencoded(
        name => $name,
        type => 'hudson.slaves.DumbSlave',
        json => $json,
    );
}

# Issue an HTTP POST.
# Dies on error (any response other than 200 OK)
sub post
{
    my ($self, %args) = @_;

    my $data = $args{ data } || confess;
    my $headers = $args{ headers } || confess;
    my $label = $args{ label } || confess;
    my $query = $args{ query };
    my $url = URI->new( $args{ url } ) || confess;

    if ($query) {
        $url->query_form( %{ $query } );
    }

    if ($self->{ dry_run }) {
        print "$label: if not in dry run mode, would POST to $url:\n$data\n\n";
        return;
    }

    my (undef, $response_headers) = blocking_http_request(
        POST => $url,
        body => $data,
        headers => $headers,
    );

    my $status = $response_headers->{ Status };
    if ($status != 200) {
        die "$label: failed to update: $status $response_headers->{ Reason }\n";
    }

    return;
}

# Ensure the specified jenkins object exists and has the given content.
sub ensure_jenkins_object
{
    my ($self, %args) = @_;

    my $update_url = $args{ update_url } || confess;
    my $create_url = $args{ create_url } || confess;
    my $update_data = $args{ update_data } || confess;
    my $create_data = $args{ create_data } || $update_data;
    my $update_type = $args{ update_type } || 'text/xml';
    my $create_type = $args{ create_type } || $update_type;

    my $name = $args{ name } || confess;
    my $type = $args{ type } || confess;
    my $create_then_update = $args{ create_then_update };

    my $request_headers = $self->http_headers( );

    my ($data, $headers) = blocking_http_request( GET => $update_url, headers => $request_headers );

    my $status = $headers->{ Status };

    if ($status == 404) {
        print "$type $name: $update_url -> $status $headers->{ Reason }\n";

        $self->post(
            label => "$type $name",
            url => $create_url,
            query => { name => $name },
            data => $create_data,
            headers => $self->http_headers(
                'Content-Type' => $create_type
            ),
        );

        if (!$create_then_update) {
            # that's it, no more to do
            return;
        }

        # in 'create then update' mode, we've created an object; now fetch and
        # update it
        print "$type $name: created a dummy object for updating\n";

        ($data, $headers) = blocking_http_request( GET => $update_url, headers => $request_headers );
        $status = $headers->{ Status };
    }

    if ($status == 200) {
        # object exists, see if it matches expected.
        if (compare_xml( $data, $update_data )) {
            print "$type $name: no changes required\n";
            return;
        }

        $self->post(
            label => "$type $name",
            url => $update_url,
            data => $update_data,
            headers => $self->http_headers(
                'Content-Type' => $update_type
            ),
        );

        my $diff = diff( \$data, \$update_data );
        chomp $diff;
        $diff =~ s{\n}{\n  }msg;

        print "$type $name: updated:\n  $diff\n\n";
        return;
    }

    die "$type $name: unexpected response when fetching $update_url: $status $headers->{ Reason }\n";
}

# Set up a job.
sub do_job
{
    my ($self, $name) = @_;

    local $Coro::current->{ desc } = "job $name";

    my $expected_xml = $self->desired_job_xml( $name );

    my $jenkins = $self->cfg( "job.$name", 'jenkins_url' );

    $self->die_if_insecure( $jenkins );

    # Remove any trailing /
    $jenkins =~ s{/\z}{};

    $self->ensure_jenkins_object(
        name => $name,
        type => 'job',
        update_url => "$jenkins/job/$name/config.xml",
        update_data => $expected_xml,
        create_url => "$jenkins/createItem",
    );

    return;
}

sub die_if_insecure
{
    my ($self, $url) = @_;

    return if $self->{ allow_insecure };

    return if !$self->{ user }; # no security in use

    my $scheme = URI->new( $url )->scheme();
    if ($scheme ne 'https') {
        die "ERROR: authentication was requested, but Jenkins server ($url) is using an "
           ."unsecured connection.\n"
           ."  Your username and password could be intercepted.\n"
           ."  This check may be disabled with the '--allow-insecure' option.\n";
    }

    return;
}

# Set up a single node.
sub do_single_node
{
    my ($self, %args) = @_;

    my $cfg_basename = $args{ cfg_basename };
    my $template_basename = $args{ template_basename };
    my $name = $args{ name };

    local $Coro::current->{ desc } = "node $name";

    my $expected_xml = $self->desired_node_xml( %args );

    my $jenkins = $self->cfg( "node.$cfg_basename", 'jenkins_url' );

    $self->die_if_insecure( $jenkins );

    # Remove any trailing /
    $jenkins =~ s{/\z}{};

    $self->ensure_jenkins_object(
        name => $name,
        type => 'node',
        update_url => "$jenkins/computer/$name/config.xml",
        update_data => $expected_xml,
        create_url => "$jenkins/computer/doCreateItem",
        create_data => dummy_node_postdata( $name ),
        create_type => 'application/x-www-form-urlencoded',
        create_then_update => 1,
    );

    return;
}

# Set up a node range.
sub do_node_range
{
    my ($self, $name) = @_;

    local $Coro::current->{ desc } = "node $name";

    my $range = $self->cfg( "node.$name", 'range' );
    my $basename = eval { $self->cfg( "node.$name", 'basename' ) } || $name;

    # $range should be a number range understood by perl
    # e.g. "1", "1, 2", "1..10"
    if ($range !~ m{\A[0-9 ,.]+\z}) {
        die "node $name: invalid range '$range'\n";
    }

    my @range = eval $range;  ## no critic - $range already checked for correctness
    if (my $error = $EVAL_ERROR) {
        die "node $name: error evaluating range '$range': $error\n";
    }

    my @coro;
    foreach my $i (@range) {
        my $fullname = sprintf( "%s-%02d", $basename, $i );
        push @coro, async {
            $self->do_single_node(
                name => $fullname,
                cfg_basename => $name,
                template_basename => $basename,
            );
        };
    }

    # wait for all nodes to finish
    map { $_->join() } @coro;

    my $count = @range;
    print "node $name: all done ($count node(s))\n";

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

    GetOptions(
        'conf=s' => \$self->{ ini },
        'dry-run' => \$self->{ dry_run },
        'user=s' => \$self->{ user },
        'password=s' => \$self->{ password },
        'allow-insecure' => \$self->{ allow_insecure },
        'help|h' => sub { pod2usage( 2 ) },
    );

    $self->{ ini } || die "Missing mandatory --conf=<file> option.\n";

    $self->{ cfg } = Config::Tiny->new()->read( $self->{ ini } )
        || die "read $self->{ ini }: ".Config::Tiny->errstr();

    local $OUTPUT_AUTOFLUSH = 1;

    my @coro;

    foreach my $block (keys %{ $self->{ cfg } }) {
        if ($block =~ qr{\Ajob\.(.+)\z}) {
            my $job = $1;
            push @coro, async {
                $self->do_job( $job );
            };
        } elsif ($block =~ qr{\Anode\.([^.]+)\z} ) {
            my $node = $1;
            push @coro, async {
                $self->do_node_range( $node );
            };
        }
    }

    if (!@coro) {
        die "no configured jobs or nodes.\n";
    }

    # wait for everything to finish
    map { $_->join() } @coro;

    return;
}

__PACKAGE__->new( )->run( @ARGV ) unless caller;
1;
