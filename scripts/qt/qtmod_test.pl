#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib/perl5";

package Qt::ModuleTest;
use base qw(Qt::TestScript);

use Cwd;
use English qw( -no_match_vars );
use File::Spec::Functions;
use autodie;

# All properties used by this script.
my @PROPERTIES = (
    q{base.dir}                => q{top-level source directory of module to test},

    q{location}                => q{location hint for git mirrors (`oslo' or `brisbane'); }
                                . q{only useful inside of Nokia LAN},

    q{qt.branch}               => q{git branch of Qt superproject (e.g. `master')},

    q{qt.configure.args}       => q{space-separated arguments passed to Qt's configure},

    q{qt.configure.extra_args} => q{more space-separated arguments passed to Qt's configure; }
                                . q{these are appended to qt.configure.args when configure is }
                                . q{invoked},

    q{qt.dir}                  => q{top-level source directory of Qt superproject; }
                                . q{the script will clone qt.repository into this location},

    q{qt.gitmodule}            => q{(mandatory) git module name of the module under test }
                                . q{(e.g. `qtbase')},

    q{qt.repository}           => q{giturl of Qt superproject},

    q{make.bin}                => q{`make' command (e.g. `make', `nmake', `jom' ...)},

    q{make.args}               => q{extra arguments passed to `make' command (e.g. `-j25')},
);

sub run
{
    my ($self) = @_;

    $self->read_and_store_configuration;
    $self->run_git_checkout;
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

sub default_qt_repository
{
    my ($self) = @_;
    return defined( $self->{'location'} ) ? 'git://scm.dev.nokia.troll.no/qt/qt5.git'
         :                                  'git://qt.gitorious.org/qt/qt5.git';
}

sub read_and_store_configuration
{
    my $self = shift;

    $self->read_and_store_properties(
        'base.dir'                => \&Qt::TestScript::default_common_property   ,
        'location'                => \&Qt::TestScript::default_common_property   ,
        'make.args'               => \&Qt::TestScript::default_common_property   ,
        'make.bin'                => \&Qt::TestScript::default_common_property   ,

        'qt.dir'                  => sub { catfile( $self->{'base.dir'}, 'qt' ) },
        'qt.repository'           => \&default_qt_repository                     ,
        'qt.branch'               => q{master}                                   ,
        'qt.gitmodule'            => undef                                       ,
        'qt.configure.args'       => q{-opensource -confirm-license}             ,
        'qt.configure.extra_args' => q{}                                         ,
    );

    # for convenience only - this should not be overridden
    $self->{'qt.gitmodule.dir'}   =  catfile( $self->{'qt.dir'}, $self->{'qt.gitmodule'} );

    return;
}

sub run_git_checkout
{
    my ($self) = @_;

    my $base_dir      = $self->{ 'base.dir'      };
    my $qt_branch     = $self->{ 'qt.branch'     };
    my $qt_repository = $self->{ 'qt.repository' };
    my $qt_dir        = $self->{ 'qt.dir'        };
    my $qt_gitmodule  = $self->{ 'qt.gitmodule'  };
    my $location      = $self->{ 'location'      };

    chdir( $base_dir );

    # Clone the Qt superproject
    $self->exe( 'git', 'clone', '--branch', $qt_branch, $qt_repository, $qt_dir );
    chdir( $qt_dir );

    my @init_repository_arguments;
    if (defined( $location ) && ($location eq 'brisbane')) {
        push @init_repository_arguments, '-brisbane-nokia-developer';
    }
    elsif (defined( $location )) {
        push @init_repository_arguments, '-nokia-developer';
    }

    # FIXME: this implementation clones all the modules, even those we don't need.
    # It should be improved to get only those modules we need (if at all possible ...)
    $self->exe( 'perl', './init-repository', @init_repository_arguments );

    # FIXME: currently we support testing a module only against the `master' of all
    # other modules.  Later, this should also support parsing of sync.profile.
    # Also, this code assumes that init-repository always uses `origin' as the remote.
    $self->exe(
        'git',
        'submodule',
        'foreach',
        'if test $name != qtwebkit; then git reset --hard origin/master; fi'
    );

    # Now we need to set the submodule content equal to our tested module's base.dir
    chdir( $qt_gitmodule );
    $self->exe( 'git', 'fetch', $base_dir, '+HEAD:refs/heads/testing' );
    $self->exe( 'git', 'reset', '--hard', 'testing' );

    return;
}

sub run_compile
{
    my ($self) = @_;

    my $qt_dir                  = $self->{ 'qt.dir'                  };
    my $qt_gitmodule            = $self->{ 'qt.gitmodule'            };
    my $qt_configure_args       = $self->{ 'qt.configure.args'       };
    my $qt_configure_extra_args = $self->{ 'qt.configure.extra_args' };
    my $make_bin                = $self->{ 'make.bin'                };
    my $make_args               = $self->{ 'make.args'               };

    chdir( $qt_dir );

    my $configure
        = ($OSNAME =~ /win32/i) ? './configure.bat'
          :                       './configure';

    $self->exe( $configure, split(/\s+/, "$qt_configure_args $qt_configure_extra_args") );

    # `configure' is expected to generate a makefile with a `module-FOO'
    # target for every module.  That target should have correct module
    # dependency information, so now issuing a `make module-FOO' should
    # automatically build the module and all deps, as parallel as possible.
    # XXX: this will not work for modules which aren't hosted in qt/qt5.git
    $self->exe( $make_bin, split(/ /, $make_args), "module-$qt_gitmodule" );

    return;
}

sub main
{
    my $test = Qt::ModuleTest->new(@ARGV);
    $test->run;

    return;
}

Qt::ModuleTest->main unless caller;
1;

__END__

=head1 NAME

qtmod_test.pl - test a specific Qt module

=head1 SYNOPSIS

  ./qtmod_test.pl [options]

Test the Qt module checked out into base.dir.

=cut
