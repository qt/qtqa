#!/usr/bin/perl -w
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


use strict;
use warnings;
use Cwd;
use Cwd qw(abs_path);
use JSON::PP;
use LWP::UserAgent;
use Pod::Usage;
use Getopt::Long;
use Time::Out qw(timeout) ;
use LWP::UserAgent;

# call
# perl jenkins_job_trigger.pl -forcesuccess -u http://qt-dev-ci.ci.local -j Remotely_triggered -a 'token=REMOTE_TOKEN&MY_BRANCH=simo'

# Params
my $jenkins = "http://qt-dev-ci.ci.local";
my $job = "Remotely_triggered";
my $job_params = "";
$job_params = "$ENV{'PUBLISHER_PARAMS'}" if (defined $ENV{'PUBLISHER_PARAMS'});
$jenkins = "$ENV{'PUBLISHER_JENKINS'}" if (defined $ENV{'PUBLISHER_JENKINS'});
$job = "$ENV{'PUBLISHER_JOB'}" if (defined $ENV{'PUBLISHER_JOB'});
my $verbose = 0;
my $fire_and_forget = 0;
my $forcesuccess = 0;
my $max_runtime = 60; # hour by default
my $credentials = "";
my $jenkins_with_token = "";

GetOptions('h|help' => sub { pod2usage(1) }
            , 'v|verbose' => sub { $verbose = 1 }
            , 'forcesuccess'  => sub { $forcesuccess = 1 }
            , 'u|url=s' => \$jenkins
            , 'j|job=s' => \$job
            , 'a|job_args=s' => \$job_params # Argments when trigering jenkins job
            , 'runtime=i' => \$max_runtime   # in minutes
            , 't|token=s' => \$credentials
            , 'fireandforget|faf' => sub{ $fire_and_forget = 1 }
            ) or pod2usage(1);

# If we are triggerin job which requires authetication, we need
# to keep the token private
if ($credentials ne "") {
    open (my $FILE, "<", $credentials) or die "Can't open $credentials \n";
    my @lines = <$FILE>;
    my $user = $lines[0];
    $user =~ s/\R//g;
    my $token = $lines[1];
    $token =~ s/\R//g;
    close $FILE;
    die "Invalid user credentials in $credentials file\n" if ($user eq"" || $token eq "");

    my $cmd = "echo ${jenkins} | cut -d/ -f 3";
    my $base_url = qx(${cmd});
    $jenkins_with_token = "http://".$user.":".$token."\@".$base_url;
    $jenkins_with_token =~ s/\R//g;
    $jenkins = $jenkins_with_token;
}
# print params
# TODO make printable url, one without user:token, we don't want to share all secrets
my $public_url = "http://hidden.jenkins.server";
print "  --> JENKINS : $public_url \n" if ($verbose);
print "  --> PARAMS : $job_params \n" if ($verbose);
print "  --> JOB : $job \n" if ($verbose);

## Start selected build
sub start_build {
    my $job_url = $jenkins."/job/".$job."/buildWithParameters\?".$job_params;
    $job_url =~ s/"//g;
    my $ua = LWP::UserAgent->new;
    $ua->agent("RemoteTrigger/0.1 ");
    my $req = HTTP::Request->new(GET => $job_url);
    my $ret = $ua->request($req);
    if (!$ret->is_success) {
        print "Triggering $job failed\n";
        exit -1;
    }
    print "Job URL was $public_url/job/$job/buildWithParameters?$job_params\n" if ($verbose);
    print "Jenkins url params was $jenkins\n" if ($verbose);
    print "Job params were $job_params\n" if ($verbose);
    print "Job was $job\n" if ($verbose);
    print "GET return was $ret\n" if ($verbose);
    return;
}

## Read from json api, where are we and what is going on
sub wait_for_me {
    my $json_url = shift; #$jenkins."/job/".$job."/api/json";
    my $state = shift;
    my $ua = LWP::UserAgent->new;
    my $req = HTTP::Request->new(GET => $json_url);
    my $json = JSON::PP->new;
    my $still_doing = 1;
    my $data = "";
    my $sleeptime = 2;
    $sleeptime = 2 if ($state eq 'building'); # building takes longest

    print "Start state \"$state\"\n";
    while ($still_doing) {
        sleep($sleeptime) if ($state ne 'result'); # no need to sleep if just checking result
        my $resp = $ua->request($req);
        if ($resp->is_success) {
            my $message = $resp->decoded_content;
        } else {
           print "HTTP GET error code: ", $resp->code, "\n";
           # Most likely we will fail die to this
           return -1;
        }
        $data = $json->decode($resp->decoded_content);
        print "    Still \"$state\" \n" if ($state ne 'result');
        $still_doing = $data->{$state};
        $still_doing = 0 if ($state eq 'result');
    }

    if ($state eq 'result') {
        print "Done state \"$state\" and result was $data->{$state}\n";
        if ($data->{$state} ne "SUCCESS") {
            return -1;
        }
    } else {
        print "Done state \"$state\"\n";
    }
    return 1;
}

## running
sub run {
    start_build();
    exit 0 if ($fire_and_forget); # no need to wait for exit nor build status
    my $next = 1;
    my $runtime = $max_runtime*60;
    #make sure we will exit eventually, not to break whole job
    timeout $runtime => sub {
        $next = wait_for_me($jenkins."/job/".$job."/api/json","inQueue");
        $next = wait_for_me($jenkins."/job/".$job."/lastBuild/api/json","building") if ($next == 1);
        $next = wait_for_me($jenkins."/job/".$job."/lastBuild/api/json","result") if ($next == 1);
    };
    # timeout
    if ($@) {
        print "$public_url/job/$job. timed out \n";
        $next = -1;
    }
    if ($next == -1) {
        #make it possible to force to succeed
        if ($forcesuccess == 1) {
            print "Normally I would now fail, but I was forced to succeed\n";
            exit 0;
        } else {
            print "Failure\n";
            exit -1;
        }
    }
    exit 0;
}

run() unless caller;


__END__

=head1 NAME

Script to execute job and wait for its result in remote jenkins.
 If run without options, it will try to trigger dummy project on dev-ci.

=head1 SYNOPSIS

jenkins_job_trigger.pl [options]

=head1 OPTIONS

=item B<-u Remote_jenkins' URL>

URL to remote jenkins, default is Qt-project's dev-ci. Same as PUBLISHER_JENKINS
env variable. If -u option is givesn, env variable is not used.

=item B<-t Path to token file >

Path to file which contains jenkins' user name and its
secret token. The file should contain two lines:
user
token

=item B<-j job_name>

Name of the remote job. Same PUBLISHER_JOB env variable.
If -j is given env varible is not used.

=item B<-a Parameters for the job>

Parameters for the jenkins job. Same as PUBLISHER_PARAMS env variable.
If -a is given PUBLISHER_PARAMS env varible is not used.

=item B<-runtime Time in minutes>

Maximum runtime of remote job.

=item B<-forcesuccess>

Force successful exit in if the remotely triggered job fails.

=item B<-fireandforget|-faf>

Exit right after launching the remote job.

=item B<-v>

Print more logs.

=back

=head1 DESCRIPTION

Script to execute job and wait for its result in remote jenkins.

=cut
