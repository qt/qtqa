#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib/perl5";

package QtQA::ModuleTest;
use base qw(QtQA::TestScript);

use Carp;
use Cwd qw( abs_path );
use Data::Dumper;
use English qw( -no_match_vars );
use Env::Path;
use File::Spec::Functions;
use FindBin;
use List::MoreUtils qw( any );
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

    q{qt.make_install}         => q{if 1, perform a `make install' step after building Qt. }
                                . q{Generally this should only be done if (1) the `-prefix' }
                                . q{configure option has been used appropriately, and (2) }
                                . q{neither `-nokia-developer' nor `-developer-build' configure }
                                . q{arguments were used},

    q{qt.gitmodule}            => q{(mandatory) git module name of the module under test }
                                . q{(e.g. `qtbase')},

    q{qt.repository}           => q{giturl of Qt superproject},

    q{qt.tests.enabled}        => q{if 1, run the autotests (for this module only)},

    q{qt.tests.timeout}        => q{maximum runtime permitted for each autotest, in seconds; any }
                                . q{test which does not completed within this time will be }
                                . q{killed and considered a failure},

    q{qt.tests.capture_logs}   => q{if set to a directory name, capture all test logs into this }
                                . q{directory.  For example, setting qt.tests.capture_logs=}
                                . q{$HOME/test-logs will create one file in $HOME/test-logs for }
                                . q{each autotest which is run.  If neither this nor }
                                . q{qt.tests.tee_logs are used, tests print to STDOUT/STDERR }
                                . q{as normal},

    q{qt.tests.tee_logs}       => q{like qt.tests.capture_logs, but also print the test logs to }
                                . q{STDOUT/STDERR as normal while the tests are running},

    q{qt.tests.backtraces}     => q{if 1, attempt to capture backtraces from crashing tests; }
                                . q{currently, this requires gdb, and is likely to work only on }
                                . q{Linux},

    q{make.bin}                => q{`make' command (e.g. `make', `nmake', `jom' ...)},

    q{make.args}               => q{extra arguments passed to `make' command (e.g. `-j25')},
);

# gitmodules for which `make check' is not yet safe.
# These should be removed one-by-one as modules are verified to work correctly.
# See task QTQAINFRA-142
my %MAKE_CHECK_BLACKLIST = map { $_ => 1 } qw(
    qtrepotools
    qtwebkit
);

sub run
{
    my ($self) = @_;

    $self->read_and_store_configuration;
    $self->run_git_checkout;
    $self->run_compile;
    $self->run_autotests;
    $self->run_install;

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

sub default_qt_tests_enabled
{
    my ($self) = @_;

    my $qt_gitmodule = $self->{ 'qt.gitmodule' };

    # By default, avoid the modules known to be bad.
    # See task QTQAINFRA-142
    if ($MAKE_CHECK_BLACKLIST{$qt_gitmodule}) {
        warn "Autotests are not yet runnable for $qt_gitmodule";
        return 0;
    }

    return 1;
}

sub default_qt_tests_backtraces
{
    my ($self) = @_;
    return ($OSNAME =~ m{linux}i);
}

sub read_and_store_configuration
{
    my $self = shift;

    $self->read_and_store_properties(
        'base.dir'                => \&QtQA::TestScript::default_common_property ,
        'location'                => \&QtQA::TestScript::default_common_property ,
        'make.args'               => \&QtQA::TestScript::default_common_property ,
        'make.bin'                => \&QtQA::TestScript::default_common_property ,

        'qt.dir'                  => sub { catfile( $self->{'base.dir'}, 'qt' ) },
        'qt.repository'           => \&default_qt_repository                     ,
        'qt.branch'               => q{master}                                   ,
        'qt.gitmodule'            => undef                                       ,
        'qt.configure.args'       => q{-opensource -confirm-license}             ,
        'qt.configure.extra_args' => q{}                                         ,
        'qt.make_install'         => 0                                           ,
        'qt.tests.enabled'        => \&default_qt_tests_enabled                  ,
        'qt.tests.timeout'        => 60*15                                       ,
        'qt.tests.capture_logs'   => q{}                                         ,
        'qt.tests.tee_logs'       => q{}                                         ,
        'qt.tests.backtraces'     => \&default_qt_tests_backtraces               ,
    );

    # for convenience only - this should not be overridden
    $self->{'qt.gitmodule.dir'}   =  catfile( $self->{'qt.dir'}, $self->{'qt.gitmodule'} );

    if ($self->{'qt.tests.capture_logs'} && $self->{'qt.tests.tee_logs'}) {
        delete $self->{'qt.tests.capture_logs'};
        warn 'qt.tests.capture_logs and qt.tests.tee_logs were both specified; '
            .'tee_logs takes precedence';
    }

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

    # FIXME: currently we support testing a module only against some tracking branch
    # (usually `master') of all other modules.
    # Later, this should also support parsing of sync.profile.
    # Also, this code assumes that init-repository always uses `origin' as the remote.
    $self->exe(
        'git',
        'submodule',
        'foreach',

        # init-repository is expected to initialize any nested gitmodules where
        # necessary; however, since we are changing the tracked SHA1 here, we
        # need to redo a `submodule update' in case any gitmodule content is
        # affected.  Note that the `submodule update' is a no-op in the usual case
        # of no nested gitmodules.
        q{
            branch=master;
            if test $name = qtwebkit; then
                branch=qt-modularization-base;
            fi;
            git reset --hard origin/$branch;
            git submodule update --recursive --init;
        },
    );

    # Now we need to set the submodule content equal to our tested module's base.dir
    chdir( $qt_gitmodule );
    $self->exe( 'git', 'fetch', $base_dir, '+HEAD:refs/heads/testing' );
    $self->exe( 'git', 'reset', '--hard', 'testing' );

    # Again, since we changed the SHA1, we potentially need to update any submodules.
    $self->exe( 'git', 'submodule', 'update', '--recursive', '--init' );

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

sub run_install
{
    my ($self) = @_;

    my $make_bin        = $self->{ 'make.bin' };
    my $qt_dir          = $self->{ 'qt.dir' };
    my $qt_gitmodule    = $self->{ 'qt.gitmodule' };
    my $qt_make_install = $self->{ 'qt.make_install' };

    return if (!$qt_make_install);

    chdir( $qt_dir );

    # XXX: this will not work for modules which aren't hosted in qt/qt5.git
    $self->exe( $make_bin, "module-$qt_gitmodule-install_subtargets" );

    return;
}

# Returns a testrunner command
sub get_testrunner_command
{
    my ($self) = @_;

    my $qt_tests_timeout        = $self->{ 'qt.tests.timeout' };
    my $qt_tests_capture_logs   = $self->{ 'qt.tests.capture_logs' };
    my $qt_tests_tee_logs       = $self->{ 'qt.tests.tee_logs' };
    my $qt_tests_backtraces     = $self->{ 'qt.tests.backtraces' };

    my $testrunner = catfile( $FindBin::Bin, '..', '..', 'bin', 'testrunner' );
    $testrunner    = abs_path( $testrunner );

    # sanity check
    confess( "internal error: $testrunner does not exist" ) if (! -e $testrunner);

    my @testrunner_with_args = (
        $testrunner,        # run the tests through our testrunner script ...
        '--timeout',
        $qt_tests_timeout,  # kill any test which takes longer than this ...
    );

    # capture or tee logs to a given directory
    if ($qt_tests_capture_logs) {
        push @testrunner_with_args, '--capture-logs', $qt_tests_capture_logs;
    }
    elsif ($qt_tests_tee_logs) {
        push @testrunner_with_args, '--tee-logs', $qt_tests_tee_logs;
    }

    if ($qt_tests_backtraces) {
        push @testrunner_with_args, '--plugin', 'core';
    }

    push @testrunner_with_args, '--'; # no more args

    # We cannot handle passing arguments with spaces into `make TESTRUNNER...',
    # so detect and abort right now if that's the case.
    #
    # Handling this properly by quoting the arguments is really quite difficult
    # (it depends on exactly which shell is going to be invoked by make, which may
    # be affected by the value of the PATH environment variable when make is run, etc...),
    # so we will not do it unless it becomes necessary.
    #
    if (any { /\s/ } @testrunner_with_args) {
        confess( "Some arguments to testrunner contain spaces, which is currently not supported.\n"
                ."Try removing spaces from build / log paths, if there are any.\n"
                .'testrunner and arguments: '.Dumper(\@testrunner_with_args)."\n" );
    }

    return join(' ', @testrunner_with_args);
}

sub run_autotests
{
    my ($self) = @_;

    return if (!$self->{ 'qt.tests.enabled' });

    my $qt_dir                  = $self->{ 'qt.dir'           };
    my $qt_gitmodule            = $self->{ 'qt.gitmodule'     };
    my $qt_gitmodule_dir        = $self->{ 'qt.gitmodule.dir' };
    my $make_bin                = $self->{ 'make.bin'         };

    my $testrunner_command = $self->get_testrunner_command( );

    # Add both qtbase/bin (core tools) and this qtmodule's bin to PATH.
    # FIXME: at some point, we should be doing `make install'.  If that is done,
    # the PATH used here should be the install path rather than build path.
    local $ENV{ PATH } = $ENV{ PATH };
    Env::Path->PATH->Prepend(
        catfile( $qt_dir, 'qtbase', 'bin' ),
        catfile( $qt_gitmodule_dir, 'bin' ),
    );

    $self->exe( $make_bin,
        '-C',                               # in the gitmodule's directory ...
        $qt_gitmodule_dir,
        '-j1',                              # in serial (autotests are generally parallel-unsafe)
        '-k',                               # keep going after failure
                                            # (to get as many results as possible)
        "TESTRUNNER=$testrunner_command",   # use our testrunner script
        'check',                            # run the autotests :)
    );

    return;
}

sub main
{
    my $test = QtQA::ModuleTest->new(@ARGV);
    $test->run;

    return;
}

QtQA::ModuleTest->main unless caller;
1;

__END__

=head1 NAME

qtmod_test.pl - test a specific Qt module

=head1 SYNOPSIS

  ./qtmod_test.pl [options]

Test the Qt module checked out into base.dir.

=cut
