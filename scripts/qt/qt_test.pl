#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib/perl5";

package Qt::Qt5Test;
use base qw(Qt::TestScript);

use Cwd;
use English qw( -no_match_vars );
use File::Spec::Functions;
use autodie;

# All properties used by this script.
my @PROPERTIES = (
    q{base.dir}                => q{top-level source directory of Qt5},

    q{location}                => q{location hint for git mirrors (`oslo' or `brisbane'); }
                                . q{only useful inside of Nokia LAN},

    q{qt.configure.args}       => q{space-separated arguments passed to Qt's configure},

    q{qt.configure.extra_args} => q{more space-separated arguments passed to Qt's configure; }
                                . q{these are appended to qt.configure.args when configure is }
                                . q{invoked},

    q{make.bin}                => q{`make' command (e.g. `make', `nmake', `jom' ...)},

    q{make.args}               => q{extra arguments passed to `make' command (e.g. `-j25')},
);

sub run
{
    my ($self) = @_;

    $self->read_and_store_configuration;
    $self->run_init_repository;
    $self->run_compile;

    return;
}

sub new
{
    my ($class, @args) = @_;

    my $self = $class->SUPER::new;

    $self->set_permitted_properties( @PROPERTIES );
    $self->get_options_from_array( \@args );

    bless $self, $class;
    return $self;
}

sub read_and_store_configuration
{
    my $self = shift;

    $self->read_and_store_properties(
        'base.dir'                => \&Qt::TestScript::default_common_property   ,
        'location'                => \&Qt::TestScript::default_common_property   ,
        'make.args'               => \&Qt::TestScript::default_common_property   ,
        'make.bin'                => \&Qt::TestScript::default_common_property   ,

        'qt.configure.args'       => q{-opensource -confirm-license}             ,
        'qt.configure.extra_args' => q{}                                         ,
    );

    return;
}

sub run_init_repository
{
    my ($self) = @_;

    my $base_dir      = $self->{ 'base.dir' };
    my $location      = $self->{ 'location' };

    chdir( $base_dir );

    my @init_repository_arguments;
    if (defined( $location ) && ($location eq 'brisbane')) {
        push @init_repository_arguments, '-brisbane-nokia-developer';
    }
    elsif (defined( $location )) {
        push @init_repository_arguments, '-nokia-developer';
    }

    $self->exe( 'perl', './init-repository', @init_repository_arguments );

    return;
}

sub run_compile
{
    my ($self) = @_;

    my $base_dir                = $self->{ 'base.dir'                };
    my $qt_configure_args       = $self->{ 'qt.configure.args'       };
    my $qt_configure_extra_args = $self->{ 'qt.configure.extra_args' };
    my $make_bin                = $self->{ 'make.bin'                };
    my $make_args               = $self->{ 'make.args'               };

    chdir( $base_dir );

    my $configure
        = ($OSNAME =~ /win32/i) ? './configure.bat'
          :                       './configure';

    $self->exe( $configure, split(' ', "$qt_configure_args $qt_configure_extra_args") );

    $self->exe( $make_bin,  split(' ', $make_args) );

    return;
}

sub main
{
    my $test = Qt::Qt5Test->new(@ARGV);
    $test->run;

    return;
}

Qt::Qt5Test->main unless caller;
1;

__END__

=head1 NAME

qt_test.pl - test all of Qt5

=head1 SYNOPSIS

  ./qt_test.pl [options]

Test the Qt5 checked out into base.dir.

This script currently supports compilation of all Qt modules.
It does not yet support running autotests.

=cut
