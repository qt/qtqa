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

package QtQA::App::SummarizeJenkinsBuild;
use strict;
use warnings;

=head1 NAME

summarize-jenkins-build.pl - generate human-readable summary of a result from jenkins

=head1 SYNOPSIS

  # Explain why this build failed...
  $ summarize-jenkins-build.pl --url http://jenkins.example.com/job/QtBase_master_Integration/10018/
  QtBase master Integration #10017: FAILURE

    Autotest `license' failed for linux-g++-32_Ubuntu_10.04_x86 :(

  # Or, from within a Jenkins post-build step:
  $ summarize-jenkins-build.pl --url "$JOB_URL"

Parse a Jenkins build and extract a short summary of the failure reason(s), suitable
for pasting into a gerrit comment.

=head2 OPTIONS

=over

=item --help

Print this help.

=item --url B<URL>

URL of the Jenkins build.

For a multi-configuration build, the URL of the top-level build should be used.
The script will parse the logs from each configuration.

=item --debug

Print an internal representation of the build to standard error, for debugging
purposes.

=back

=cut

use AnyEvent::HTTP;
use Capture::Tiny qw(capture);
use Data::Dumper;
use File::Spec::Functions;
use FindBin;
use Getopt::Long qw(GetOptionsFromArray);
use JSON;
use Pod::Usage;
use Readonly;

# Jenkins status constants
Readonly my $SUCCESS => 'SUCCESS';
Readonly my $FAILURE => 'FAILURE';
Readonly my $ABORTED => 'ABORTED';

# Build log parser script
Readonly my $PARSE_BUILD_LOG => catfile( $FindBin::Bin, qw(.. generic parse_build_log.pl) );

# Given a Jenkins $url, returns JSON of depth 1 for the object at that URL,
# or dies on error.
sub get_json_from_url
{
    my ($url) = @_;

    $url =~ s{/$}{};
    $url .= '/api/json?depth=1';

    my $cv = AE::cv();
    my $req = http_request( GET => $url, sub { $cv->send( @_ ) } );
    my ($data, $headers) = $cv->recv();

    if ($headers->{ Status } != '200') {
        die "fetch $url: $headers->{ Status } $headers->{ Reason }\n";
    }

    return $data;
}

# Returns a hashref containing all (relevant) build data from the build at $url,
# or dies on error.
sub get_build_data_from_url
{
    my ($url) = @_;

    return from_json( get_json_from_url( $url ) );
}

# Runs parse_build_log.pl through system() for the given $url
sub run_parse_build_log
{
    my ($url) = @_;

    return system( $PARSE_BUILD_LOG, '--summarize', $url );
}

# Returns the output of "parse_build_log.pl --summarize $url",
# or warns and returns nothing on error.
sub get_build_summary_from_log_url
{
    my ($url) = @_;

    return unless $url;

    my $status;
    my ($stdout, $stderr) = capture {
        $status = run_parse_build_log( $url );
    };

    chomp $stdout;

    if ($status != 0) {
        warn "parse_build_log exited with status $status"
            .($stderr ? ":\n$stderr" : q{})
            ."\n";

        # Output is not trusted if script didn't succeed
        undef $stdout;
    }

    return $stdout;
}

# Given a Jenkins build object, returns a "permanent" link
# to the build log (which may itself not be in jenkins).
sub get_permanent_url_for_build_log
{
    my ($cfg) = @_;

    # FIXME: support testresults.qt-project.org logs
    my $url = $cfg->{ url };
    return unless $url;

    if ($url !~ m{/\z}) {
        $url .= '/';
    }

    return $url . 'consoleText';
}

# Given a jenkins build $url, returns a human-readable summary of
# the build result.
sub summarize_jenkins_build
{
    my ($self, $url) = @_;

    my $build = get_build_data_from_url( $url );

    if ($self->{ debug }) {
        warn "debug: build information:\n" . Dumper( $build );
    }

    my $result = $build->{ result };
    my $number = $build->{ number };

    my $out = "$build->{ fullDisplayName }: $result";

    if ($result eq $SUCCESS || $result eq $ABORTED) {
        # no more info required
        return $out;
    }

    my @configurations = @{$build->{ runs } || []};

    # Only care about runs for this build...
    @configurations = grep { $_->{ number } == $number } @configurations;

    # ...and only care about failed runs.
    # If the top-level build is aborted, the results of individual configurations
    # are not trustworthy.
    @configurations = grep { $_->{ result } eq $FAILURE } @configurations;

    # Configurations are sorted by display name (for predictable output order)
    @configurations = sort { $a->{ fullDisplayName } cmp $b->{ fullDisplayName } } @configurations;

    # If there are no failing sub-configurations, the failure must come from the
    # master configuration (for example, git checkout failed and no builds could
    # be spawned), so we'll summarize that one.
    if (!@configurations) {
        push @configurations, $build;
    }

    my @summaries;

    foreach my $cfg (@configurations) {
        my $log_url = get_permanent_url_for_build_log( $cfg );

        my $this_out;

        if (my $summary = get_build_summary_from_log_url( $log_url )) {
            # If we can get a sensible summary, just do that.
            # The summary should already mention the tested configuration.
            $this_out = $summary;
        } else {
            # Otherwise, we don't know what happened, so just mention the
            # jenkins result string.
            $this_out = "$cfg->{ fullDisplayName }: $cfg->{ result }";
        }

        if ($log_url) {
            if ($this_out !~ m{\n\z}ms) {
                $this_out .= "\n";
            }
            $this_out .= "  Build log: $log_url";
        }

        push @summaries, $this_out;
    }

    return join( "\n\n--\n\n", @summaries );
}

sub new
{
    my ($class) = @_;
    return bless {}, $class;
}

sub run
{
    my ($self, @args) = @_;

    my $url;

    GetOptionsFromArray(
        \@args,
        'url=s' => \$url,
        'h|help' => sub { pod2usage( 2 ) },
        'debug' => \$self->{ debug },
    );

    $url || die 'Missing mandatory --url option';

    print $self->summarize_jenkins_build( $url ) . "\n";

    return;
}

__PACKAGE__->new( )->run( @ARGV ) unless caller;
1;
