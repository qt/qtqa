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

use strict;
use warnings;

package QtQaTest;

=head1 NAME

test.pl - run autotests for the Qt QA scripts

=head1 SYNOPSIS

  ./test.pl [ --clean ]

Run the automated test suite in this repository.

=head2 Options:

=over

=item --clean

Instead of running against the perl environment set up
in the caller's environment, create a new perl environment
in a temporary directory, and delete it after the test completes.

This is the most accurate way to test that all prerequisites are
correctly specified in setup.pl.  However, it significantly increases
the test time.

=back

On a typical clean Linux workstation, this script shouldn't require any
additional prerequisites other than the perl B<local::lib> dependency
needed by L<setup.pl>.

=cut

use English               qw( -no_match_vars      );
use File::Path            qw( rmtree              );
use File::Spec::Functions qw( catfile             );
use File::Temp            qw( tempdir             );
use FindBin               qw(                     );
use Getopt::Long          qw( GetOptionsFromArray );
use Pod::Usage            qw( pod2usage           );

sub new
{
    my ($class, @args) = @_;

    my %self = (
        'clean'       =>  0,
    );

    GetOptionsFromArray(\@args,
        "clean"         =>  \$self{ 'clean'       },
        "help"          =>  sub { pod2usage(1) },
    ) || pod2usage(2);

    bless \%self, $class;
    return \%self;
}

sub system_or_die
{
    my ($self, @command_with_args) = @_;

    my $command = join(" ", @command_with_args);
    print "+ $command\n";
    system(@command_with_args);
    if ($? == -1) {
        die "$command failed to execute: $!\n";
    }
    elsif ($? & 127) {
        die(sprintf "$command died with signal %d\n", ($? & 127));
    }
    elsif ($?) {
        die(sprintf "$command exited with value %d\n", $? >> 8);
    }

    return;
}

# Use setup.pl to install prereqs
sub run_setup_pl
{
    my $self = shift;

    my $setup = catfile($FindBin::Bin, 'setup.pl');
    my @cmd = ('perl', $setup, '--install');
    if ($self->{perldir}) {
        push @cmd, '--prefix', $self->{perldir};
    }

    $self->system_or_die(@cmd);

    return;
}

# Run all of the autotests, using prove.
sub run_prove
{
    my $self = shift;

    # While running the tests, it is good to use a
    # "temporary temporary directory", because a few things expect to use /tmp
    # as semi-persistent storage.  Ideally nothing would do this, but some third
    # party modules may do so.
    #
    # We clean up the directory before the test if it exists, but we make no
    # attempt to clean up this directory after the test:
    #
    #  - if running in CI system, the CI system will clean it
    #  - if running locally, and a test fails, the user might like to look at
    #    some of the data left behind
    #
    my $tmpdir = catfile($FindBin::Bin, 'test_pl_tmp');
    if (-e $tmpdir) {
        rmtree($tmpdir, 0, 0) || die "rmtree $tmpdir: $OS_ERROR";
    }
    mkdir($tmpdir) || die "mkdir $tmpdir: $OS_ERROR";
    local $ENV{TMPDIR} = $tmpdir;

    # options always passed to `prove'
    my @prove_options = (
        # Let tests freely use modules under lib/perl5
        '-I',
        "$FindBin::Bin/lib/perl5",
    );

    my @prove = (
        'prove',

        @prove_options,

        # Use `--merge' because we have some tests which are expected to output a
        # lot of stderr which look like errors (e.g. test for the Pulse::x handling
        # of transient errors).  Having these visible by default is rather
        # confusing to e.g. the CI system, which will extract these "errors" into
        # report emails.
        #
        # If there is a failure, we will re-run the tests later without `--merge',
        # so failing tests will still have all the details available.
        '--merge',

        # Use `--state=save' so, if running manually, the user can easily
        # re-run only the failed tests if desired; and to support the rerun-tests
        # option.
        #
        '--state=save',

        # Let tests freely use modules under lib/perl5
        '-I',
        "$FindBin::Bin/lib/perl5",

        # Run all tests under the directory in which test.pl is located
        '--recurse',
        $FindBin::Bin
    );

    eval { $self->system_or_die(@prove) };
    my $error = $@;
    if ($error) {
        print "\n\nI'm going to run only the failed tests again:\n";
        $self->system_or_die(
            'prove',

            @prove_options,

            # This will run only the tests which were marked as failing ...
            '--state=failed,save',

            # ...and this will be quite verbose, to aid in
            # figuring out the problem.
            '--verbose',
        );

        # The second attempt may have passed, in the case of unstable
        # tests, but we still should consider this a fatal error.
        die $error;
    }

    return;
}

sub make_clean_prefix
{
    my ($self) = @_;

    my $cleandir = tempdir( 'qt-qa-test-pl.XXXXXX', CLEANUP => 1, TMPDIR => 1 );

    print "Using $cleandir as perl prefix.\n";

    # perl: local::lib creates the dirs and sets environment in the current process.
    # Unsetting PERL5LIB first ensures that this is the only local::lib in the
    # environment.
    $ENV{PERL5LIB} = q{};   ## no critic - localized by caller
    my $perl_dir = "$cleandir/perl";
    require local::lib;
    local::lib->import($perl_dir);

    $self->{perldir} = $perl_dir;

    return;
}

sub run
{
    my ($self) = @_;

    # localize in case we modify this in the below block.
    local $ENV{PERL5LIB} = $ENV{PERL5LIB};

    if ($self->{clean}) {
        $self->make_clean_prefix;
    }

    $self->run_setup_pl;
    $self->run_prove;

    return;
}

#==============================================================================

QtQaTest->new(@ARGV)->run if (!caller);
1;
