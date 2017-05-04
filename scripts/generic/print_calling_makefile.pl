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

package QtQA::App::PrintCallingMakefile;

use strict;
use warnings;

=head1 NAME

print_calling_makefile - print the name of the currently executing makefile

=head1 SYNOPSIS

  # Within "some-makefile":
  first:
          perl print_calling_makefile.pl

  # then, at command prompt:
  $ nmake -f some-makefile
  some-makefile

When called as a child process of nmake or jom, prints the name of the
currently processed makefile to standard output, and exits. The name of
the makefile is printed as passed on the command-line, so it may be an
absolute or relative path.

This script is a workaround for nmake's lack of any equivalent to GNU make's
$(MAKEFILE_LIST) variable.  For example, in a GNU makefile, where one would
write something like:

  echo Current makefile is $(firstword $(MAKEFILE_LIST))

In a makefile for nmake, one may write:

  for /f "usebackq tokens=*" %%a in (`perl print_calling_makefile.pl`) do echo Current makefile is %%a

This script only works on Windows.

=cut

use Data::Dumper;
use English qw( -no_match_vars );
use Text::ParseWords qw(shellwords);
use Win32::Process::Info qw(WMI);
use Win32;

# Returns 1 if the given $process looks like it refers to jom/nmake.
sub looks_like_make
{
    my ($process) = @_;
    return ($process->{ ExecutablePath } =~ m{\b(?:jom|nmake)\.exe}i);
}

# From the given process $info (arrayref), find and return the process
# with the given $pid, or die.
sub extract_process
{
    my ($info, $pid) = @_;

    my (@process) = grep { $_->{ ProcessId } == $pid } @{ $info };
    if (@process > 1) {
        die "error: multiple processes with ProcessId $pid";
    }
    if (@process == 0) {
        die "error: cannot find process with ProcessId $pid";
    }

    return $process[0];
}

# Given an nmake/jom $command line, extracts and returns the Makefile
# argument, or dies.
sub extract_makefile_from_command
{
    my ($command) = @_;

    my $makefile;

    # We use shellwords() to parse the command-line; this is following
    # Bourne-style rules, which may be incompatible with the way nmake
    # parses its own command line in some respects.  In practice, for
    # the relatively basic command lines we expect to see, this should
    # be acceptable.
    my @words = shellwords( $command );
    my @argv = @words;

    while (my $arg = shift @argv) {
        # All known forms are:
        #
        #   [-f] [Makefile]
        #   [/f] [Makefile]
        #   [-F] [Makefile]
        #   [/F] [Makefile]
        #   [-fMakefile]
        #   [/fMakefile]
        #   [-FMakefile]
        #   [/FMakefile]
        #
        if ($arg =~ m{\A [-/][fF] (.*) \z}xms) {
            if ($1) {
                # makefile is in this argument
                $makefile = $1;
            } else {
                # makefile is in next argument
                # (or, if this is the last argument, we'll die later)
                $makefile = shift @argv;
            }
            last;
        }
    }

    if (!$makefile) {
        local $LIST_SEPARATOR = '] [';
        die "Can't extract makefile from command line $command\n"
           ."Parsed as: [@words]\n";
    }

    return $makefile;
}

# Main function.
sub run
{
    my $pid = Win32::GetCurrentProcessId();

    # $info will contain info for _all_ processes (at least those we have permission to view).
    # It would also be possible to do a new query per process; a basic benchmark showed no
    # significant difference between the two.
    my $info = Win32::Process::Info->new()->GetProcInfo();
    $info || die;

    # $process_tree holds the known process tree, used purely for debugging when something
    # goes wrong.
    my ($process_tree, $process);

    eval {
        $process = extract_process( $info, $pid );

        while ($process) {
            last if looks_like_make( $process );
            $process_tree = { %{$process}, _child => $process_tree };
            $pid = $process->{ ParentProcessId } || die Dumper( $process ).' ... has no ParentProcessId';
            $process = extract_process( $info, $pid );
        }

        if (!$process) {
            die 'error: could not find any calling nmake/jom';
        }
    };

    if (my $error = $@) {
        die "$error\nProcess tree: ".Dumper( $process_tree )."\n";
    }

    my $command = $process->{ CommandLine } || die Dumper( $process ).' ... has no CommandLine';
    my $makefile = extract_makefile_from_command( $command );
    print "$makefile\n";

    return;
}

run unless caller;
1;
