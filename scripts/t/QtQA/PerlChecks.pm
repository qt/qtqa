# Copyright (C) 2017 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only WITH Qt-GPL-exception-1.0

package QtQA::PerlChecks;
use strict;
use warnings;

use Exporter;
our @ISA = qw( Exporter );
our @EXPORT_OK = qw( all_files_in_git all_perl_files_in_git );

use File::chdir;
use File::Spec::Functions;
use File::Find;
use List::MoreUtils qw( apply );
use Perl::Critic::Utils qw( all_perl_files );
use Test::More;

# Helper for tests in this directory to find perl files for testing.

# Returns a list of all files known to git under the given $path (or '.' if unset)
# It is considered a failure if there are no files known to git.
sub all_files_in_git
{
    my ($path) = @_;

    if (!$path) {
        $path = '.';
    }

    # Do everything from $path, so we get filenames relative to that
    local $CWD = $path;

    my $QT_MODULE_TO_TEST=$ENV{QT_MODULE_TO_TEST};

    # Find all the files known to git
    my @out;
    if (-d $QT_MODULE_TO_TEST . '/.git') {
        @out =
            apply { $_ = canonpath($_) } # make paths canonical ...
            apply { chomp }     # strip all newlines ...
                qx( git ls-files );
    } else {
        find(sub{ push @out, canonpath($File::Find::name); }, ".");
    }
    foreach (@out) {
        print "$_\n";
    }

    # Get files in a reliable order
    @out = sort @out;

    is( $?, 0, 'git ls-files ran ok' );
    ok( @out,  'git ls-files found some files' );

    return @out;
}

# Returns a list of all perl files known to git under the given $path.
# See Perl::Critic::Utils all_perl_files for documentation on what
# "perl files" means.
# May return an empty list if there are no perl files.
sub all_perl_files_in_git
{
    my ($path) = @_;

    if (!$path) {
        $path = '.';
    }

    # Do everything from $path, so we get filenames relative to that
    local $CWD = $path;

    # Find all the git files ...
    my %all_git_files = map { $_ => 1 } all_files_in_git( '.' );

    # Then return only those perl files which are also in git
    my @out = grep { $all_git_files{ $_ } } all_perl_files( '.' );

    # Get files in a reliable order
    @out = sort @out;

    return @out;
}

1;

