#!/usr/bin/env perl
use v5.10;
use strict;
use warnings;

=head1 NAME

10-perl-syntax-check.t - syntax check all perl scripts

=head1 DESCRIPTION

This autotest uses `perl -c' to do a simple syntax check of all perl
scripts and modules within this repo.

=cut

use Cwd                 qw( abs_path       );
use File::Spec          qw();
use FindBin             qw();
use IO::CaptureOutput   qw( qxy            );
use Test::More;

use lib $FindBin::Bin;
use QtQA::PerlChecks;

# Returns a true-ish value if a particular syntax error should be permitted.
#
# The value returned is suitable for use as a skip reason to the `skip' method
# from Test::More .
#
# Parameters:
#
#   $filename   name of the perl file which failed a syntax check
#   $output     combined stdout/stderr from `perl -c' on $filename
#
sub should_skip
{
    my ($filename, $output) = @_;

    # Some scripts need VMware VIX.  This is unfortunately not in CPAN and
    # not easily installable everywhere, so we will permit syntax checks
    # to fail in this case.
    if ($output =~ m{^Can't locate VMware/Vix/}) {
        return "$filename: VMware VIX module not available";
    }

    if ($^O eq "MSWin32") {
        if ($output =~ m{^Can't locate AnyEvent/HTTPD}) {
            return "$filename: AnyEvent/HTTPD module not available on Windows";
        } elsif ($output =~ m{^Base class package "Log::Dispatch::Email" is empty}) {
            return "$filename: Log::Dispatch::Email module not available on Windows";
        }
    }

    # Win32-specific scripts will fail syntax check when not on Win32.
    if ($^O ne "MSWin32" && $output =~ m{^Can't locate Win32}) {
        return "$filename: script looks Win32-specific and this is not Win32";
    }

    return 0;
}

# Performs syntax check on one file
#
# Parameters:
#
#   $filename   the filename to check.
#
sub syntax_check_one_perl
{
    my $filename = shift;

    # This is a set of directories which are put into the includepath
    # when doing the syntax check.
    #
    # Try not to add too much to this list - the usual case is that a
    # script should do `use lib' to add to its own includepath, when
    # necessary.
    my @qtqa_inc = (
        # all of the modules under lib/perl5 expect that this directory
        # is already in @INC at the time they are included (which seems
        # reasonable)
        'lib/perl5',
    );

    my @cmd = (
        'perl',
        map( { '-I'.$_ } @qtqa_inc),
        '-c',
        $filename
    );
    my ($output, $success) = qxy(@cmd);

    SKIP: {
        # There are certain types of errors which are not really practical
        # to avoid.  In these cases we'll print out a "skip" instead of a "fail".
        my $should_skip = should_skip($filename, $output);
        skip($should_skip, 1) if $should_skip;
        ok($success, $filename) || diag("Output of @cmd:\n$output");
    }

    return;
}

sub main
{
    my $base = abs_path(File::Spec->catfile($FindBin::Bin, '..'));
    chdir($base);

    foreach my $file (QtQA::PerlChecks::all_perl_files_in_git( )) {
        syntax_check_one_perl( $file );
    }

    done_testing;

    return;
}

main if (!caller);
1;
