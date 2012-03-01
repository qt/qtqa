#!/usr/bin/env perl
use v5.10;
use strict;
use warnings;

=head1 NAME

20-perl-critic-check.t - use Perl::Critic to check all perl scripts

=head1 DESCRIPTION

This autotest uses Perl::Critic in stern mode to do some static code
checks of all perl scripts and modules within this repo.

=cut

use autodie;
use Cwd                   qw( abs_path        );
use File::Spec::Functions qw( catfile         );
use FindBin               qw();
use Test::Perl::Critic    qw( -severity stern );
use Test::More;

use lib $FindBin::Bin;
use QtQA::PerlChecks;

sub main
{
    my $base = abs_path( catfile( $FindBin::Bin, '..' ) );
    chdir( $base );

    foreach my $file (QtQA::PerlChecks::all_perl_files_in_git( )) {
        critic_ok( $file );
    }
    done_testing( );

    return;
}

main if (!caller);
1;
