#!/usr/bin/env perl
#############################################################################
##
## Copyright (C) 2011 Nokia Corporation and/or its subsidiary(-ies).
## All rights reserved.
## Contact: Nokia Corporation (qt-info@nokia.com)
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
## $QT_END_LICENSE$
##
#############################################################################

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
use Text::Trim;

# All properties used by this script.
my @PROPERTIES = (
    q{base.dir}                => q{top-level source directory of module to test},

    q{location}                => q{location hint for git mirrors (`oslo' or `brisbane'); }
                                . q{only useful inside of Nokia LAN},

    q{qt.branch}               => q{git branch of Qt superproject (e.g. `master'); only used }
                                . q{if qt.gitmodule != "qt5"},

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
                                . q{(e.g. `qtbase').  Use special value `qt5' for testing of }
                                . q{all modules together in the qt5 superproject},

    q{qt.repository}           => q{giturl of Qt superproject; only used if }
                                . q{qt.gitmodule != "qt5"},

    q{qt.tests.enabled}        => q{if 1, run the autotests (for this module only, or all }
                                . q{modules if qt.gitmodule == "qt5")},

    q{qt.tests.insignificant}  => q{if 1, ignore all failures from autotests},

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

    q{qt.tests.flaky_mode}     => q{how to handle flaky autotests ("best", "worst" or "ignore")},

    q{qt.qtqa-tests.enabled}   => q{if 1, run the shared autotests in qtqa (over this module }
                                . q{only, or all modules if qt.gitmodule == "qt5").  The qtqa }
                                . q{tests are run after the other autotests.  All qt.tests.* }
                                . q{settings are also applied to the qtqa tests},

    q{qt.qtqa-tests.insignificant}
                               => q{overrides the setting of qt.tests.insignificant, for the }
                                . q{shared autotests in qtqa},

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
    $self->run_install;
    $self->run_autotests;
    $self->run_qtqa_autotests;

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
    return ($OSNAME =~ m{linux|darwin}i);
}

sub default_qt_qtqa_tests_insignificant
{
    my ($self) = @_;
    return $self->{ 'qt.tests.insignificant' };
}

sub default_qt_dir
{
    my ($self) = @_;

    if ($self->{ 'qt.gitmodule' } eq 'qt5' ) {
        return $self->{ 'base.dir' };
    }

    return catfile( $self->{'base.dir'}, 'qt' );
}

sub read_and_store_configuration
{
    my $self = shift;

    $self->read_and_store_properties(
        'base.dir'                => \&QtQA::TestScript::default_common_property ,
        'location'                => \&QtQA::TestScript::default_common_property ,
        'make.args'               => \&QtQA::TestScript::default_common_property ,
        'make.bin'                => \&QtQA::TestScript::default_common_property ,

        'qt.gitmodule'            => undef                                       ,
        'qt.dir'                  => \&default_qt_dir                            ,
        'qt.repository'           => \&default_qt_repository                     ,
        'qt.branch'               => q{master}                                   ,
        'qt.configure.args'       => q{-opensource -confirm-license}             ,
        'qt.configure.extra_args' => q{}                                         ,
        'qt.make_install'         => 0                                           ,
        'qt.tests.enabled'        => \&default_qt_tests_enabled                  ,
        'qt.tests.insignificant'  => 0                                           ,
        'qt.tests.timeout'        => 60*15                                       ,
        'qt.tests.capture_logs'   => q{}                                         ,
        'qt.tests.tee_logs'       => q{}                                         ,
        'qt.tests.backtraces'     => \&default_qt_tests_backtraces               ,
        'qt.tests.flaky_mode'     => q{}                                         ,

        'qt.qtqa-tests.enabled'         => 0                                     ,
        'qt.qtqa-tests.insignificant'   => \&default_qt_qtqa_tests_insignificant ,
    );

    # for convenience only - this should not be overridden
    $self->{'qt.gitmodule.dir'} = ($self->{'qt.gitmodule'} eq 'qt5')
        ? $self->{'qt.dir'}
        : catfile( $self->{'qt.dir'}, $self->{'qt.gitmodule'} )
    ;

    if ($self->{'qt.tests.capture_logs'} && $self->{'qt.tests.tee_logs'}) {
        delete $self->{'qt.tests.capture_logs'};
        warn 'qt.tests.capture_logs and qt.tests.tee_logs were both specified; '
            .'tee_logs takes precedence';
    }

    return;
}

sub read_dependencies
{
    my ($self, $dependency_file) = @_;
    our (%dependencies);

    my %default_dependencies = ( 'qtbase' => 'refs/heads/master' );
    my $default_reason;

    if (! -e $dependency_file ) {
        $default_reason = "$dependency_file doesn't exist";
    }
    else {
        unless ( do $dependency_file ) {
            confess "I couldn't parse $dependency_file, which I need to determine dependencies.\nThe error was $@\n" if $@;
            confess "I couldn't execute $dependency_file, which I need to determine dependencies.\nThe error was $!\n" if $!;
        }
        if (! %dependencies) {
            $default_reason = "Although $dependency_file exists, it did not specify any \%dependencies";
        }
    }

    if ($default_reason) {
        %dependencies = %default_dependencies;
        warn __PACKAGE__ . ": $default_reason, so I have assumed this module depends on:\n  "
            .Data::Dumper->new([\%dependencies], ['dependencies'])->Indent(0)->Dump()
            ."\n";
    }

    return %dependencies;
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
    if ($qt_gitmodule ne 'qt5') {
        $self->exe( 'git', 'clone', '--branch', $qt_branch, $qt_repository, $qt_dir );
    }

    chdir( $qt_dir );

    # Load sync.profile for this module.
    # qt5 and qtbase never have dependencies.
    my %dependencies = ();
    if ($qt_gitmodule ne 'qt5' && $qt_gitmodule ne 'qtbase') {
        %dependencies = $self->read_dependencies( "$base_dir/sync.profile" );
    }

    my @init_repository_arguments;
    if (defined( $location ) && ($location eq 'brisbane')) {
        push @init_repository_arguments, '-brisbane-nokia-developer';
    }
    elsif (defined( $location )) {
        push @init_repository_arguments, '-nokia-developer';
    }

    # Tell init-repository to only use the modules specified as dependencies
    # qtbase doesn't depend on anything
    if (%dependencies || $qt_gitmodule eq 'qtbase') {
        my @modules = keys( %dependencies );
        if (-d $qt_gitmodule) {
            push @modules, $qt_gitmodule;
        }
        push @init_repository_arguments, '--module-subset='.join(q{,}, @modules);
    }

    # We use `-force' so that init-repository can be restarted if it hits an error
    # halfway through.  Without this, it would refuse.
    push @init_repository_arguments, '-force';

    $self->exe( { reliable => 'git' },  # recover from transient git errors during init-repository
        'perl', './init-repository', @init_repository_arguments
    );

    # Checkout dependencies as specified in the sync.profile, which specifies the sha1s/refs within them
    # Also, this code assumes that init-repository always uses `origin' as the remote.
    while ( my ($module, $ref) = each %dependencies ) {
        chdir( $module );
        # FIXME how do we guarantee we have this SHA1?
        # If it's not reachable from a branch obtained from a default `clone', it could be missing.
        if ( $ref =~ /^[0-9a-f]{40}$/) { # Is a SHA1, else is a ref and may need to be fetched
            $self->exe( 'git', 'reset', '--hard', $ref );
        }
        else {
            $self->exe( 'git', 'fetch', '--verbose', 'origin', "+$ref:refs/qtmod_test" );
            $self->exe( 'git', 'reset', '--hard', 'refs/qtmod_test' );
        }

        # init-repository is expected to initialize any nested gitmodules where
        # necessary; however, since we are changing the tracked SHA1 here, we
        # need to redo a `submodule update' in case any gitmodule content is
        # affected.  Note that the `submodule update' is a no-op in the usual case
        # of no nested gitmodules.
        $self->exe( 'git', 'submodule', 'update', '--recursive', '--init' );

        chdir( '..' );
    }

    # Now we need to set the submodule content equal to our tested module's base.dir
    if ($qt_gitmodule ne 'qt5') {
        if (-d $qt_gitmodule) {
            # The module is hosted in qt5, so just update it.
            chdir( $qt_gitmodule );
            $self->exe( 'git', 'fetch', $base_dir, '+HEAD:refs/heads/testing' );
            $self->exe( 'git', 'reset', '--hard', 'testing' );

            # Again, since we changed the SHA1, we potentially need to update any submodules.
            $self->exe( 'git', 'submodule', 'update', '--recursive', '--init' );

            $self->{ module_in_qt5 } = 1;
        }
        else {
            # The module is not hosted in qt5, so we have to clone it anew.
            $self->exe( 'git', 'clone', '--shared', $base_dir, $qt_gitmodule );

            # Get submodules (if any)
            chdir( $qt_gitmodule );
            $self->exe( 'git', 'submodule', 'update', '--recursive', '--init' );

            $self->{ module_in_qt5 } = 0;
        }
    }

    return;
}

sub run_compile
{
    my ($self) = @_;

    # properties
    my $qt_dir                  = $self->{ 'qt.dir'                  };
    my $qt_gitmodule            = $self->{ 'qt.gitmodule'            };
    my $qt_configure_args       = $self->{ 'qt.configure.args'       };
    my $qt_configure_extra_args = $self->{ 'qt.configure.extra_args' };
    my $make_bin                = $self->{ 'make.bin'                };
    my $make_args               = $self->{ 'make.args'               };

    # true iff the module is hosted in qt5.git (affects build procedure)
    my $module_in_qt5 = $self->{ module_in_qt5 };

    chdir( $qt_dir );

    my $configure
        = ($OSNAME =~ /win32/i) ? 'configure.bat'
          :                       './configure';

    $self->exe( $configure, split(/\s+/, "$qt_configure_args $qt_configure_extra_args") );

    my @make_args = split(/ /, $make_args);
    my @commands;

    if ($qt_gitmodule eq 'qt5') {
        # Building qt5; just do a `make' of all default targets in the top-level makefile.
        push @commands, sub { $self->exe( $make_bin, @make_args ) };
    }
    elsif ($module_in_qt5) {
        # Building a module hosted in qt5; `configure' is expected to have generated a
        # makefile with a `module-FOO' target for this module, with correct dependency
        # information. Issuing a `make module-FOO' should automatically build the module
        # and all deps, as parallel as possible.
        push @commands, sub { $self->exe( $make_bin, @make_args, "module-$qt_gitmodule" ) };
    }
    else {
        # Building a module, hosted outside of qt5.
        # We need to do three steps; first, build all the dependencies, then qmake this
        # module, then make this module.
        # The Makefile generated in qt5 doesn't know anything about this module.

        # XXX this only works when all the module's dependencies are located in qt5.git.

        # XXX this does not work if Qt is configured such that `make install' needs to be
        # done on the dependencies.  At least the path to `qmake' will be wrong.

        # First, we build all deps:
        my %dependencies = $self->read_dependencies( "$qt_gitmodule/sync.profile" );
        my @module_targets = map { "module-$_" } keys %dependencies;
        push @commands, sub { $self->exe( $make_bin, @make_args, @module_targets ) };

        # Then we qmake, make the module we're actually interested in
        my $qmake_bin = catfile( $qt_dir, 'qtbase', 'bin', 'qmake' );
        push @commands, sub { chdir( $qt_gitmodule ) };
        push @commands, sub { $self->exe( $qmake_bin, '-r' ) };
        push @commands, sub { $self->exe( $make_bin, @make_args ) };
    }

    foreach my $command (@commands) {
        $command->();
    }

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
    my @make_args = ($qt_gitmodule eq 'qt5') ? ('install')
                  :                            ("module-$qt_gitmodule-install_subtargets");

    $self->exe( $make_bin, @make_args );

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
    my $qt_tests_flaky_mode     = $self->{ 'qt.tests.flaky_mode' };

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

    # give more info about unstable / flaky tests
    push @testrunner_with_args, '--plugin', 'flaky';
    if ($qt_tests_flaky_mode) {
        push @testrunner_with_args, '--flaky-mode', $qt_tests_flaky_mode;
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

    my $qt_gitmodule_dir = $self->{ 'qt.gitmodule.dir' };

    # Add this module's `bin' directory to PATH.
    # FIXME: verify if this is really needed (should each module's tools build directly
    # into the prefix `bin' ?)
    local $ENV{ PATH } = $ENV{ PATH };
    Env::Path->PATH->Prepend( catfile( $qt_gitmodule_dir, 'bin' ) );

    return $self->_run_autotests_impl(
        tests_dir            =>  $qt_gitmodule_dir,
        insignificant_option =>  'qt.tests.insignificant',
        do_compile           =>  0,
    );
}

sub run_qtqa_autotests
{
    my ($self) = @_;

    return if (!$self->{ 'qt.qtqa-tests.enabled' });

    my $qt_gitmodule     = $self->{ 'qt.gitmodule' };
    my $qt_gitmodule_dir = $self->{ 'qt.gitmodule.dir' };

    # path to the qtqa autotests.
    my $qtqa_tests_dir = catfile( $FindBin::Bin, qw(.. .. tests auto) );

    # director(ies) of modules we want to test
    my @module_dirs;

    if ($qt_gitmodule ne 'qt5') {
        # testing just one module
        push @module_dirs, $qt_gitmodule_dir;
    }
    else {
        # we're testing all modules;
        # we judge that the qtqa tests are applicable to any module with a tests/global/global.cfg
        chdir $qt_gitmodule_dir;

        my ($testable_modules) = trim $self->exe_qx(
            'git',
            'submodule',
            '--quiet',
            'foreach',
            'if test -f tests/global/global.cfg; then echo $path; fi',
        );
        my @testable_modules = split(/\n/, $testable_modules);

        print __PACKAGE__ . ": qtqa autotests will be run over modules: @testable_modules\n";

        push @module_dirs, map { catfile( $qt_gitmodule_dir, $_ ) } @testable_modules;
    }


    my $compiled_qtqa_tests = 0;    # whether or not the tests have been compiled

    foreach my $module_dir (@module_dirs) {
        print __PACKAGE__ . ": now running qtqa autotests over $module_dir\n";

        # qtqa autotests use this environment variable to locate the sources of the
        # module under test.
        local $ENV{ QT_MODULE_TO_TEST } = $module_dir;

        $self->_run_autotests_impl(
            tests_dir            =>  $qtqa_tests_dir,
            insignificant_option =>  'qt.qtqa-tests.insignificant',

            # Only need to `qmake', `make' the tests the first time.
            do_compile           =>  !$compiled_qtqa_tests,
        );

        $compiled_qtqa_tests = 1;
    }

    return;
}

sub _run_autotests_impl
{
    my ($self, %args) = @_;

    # global settings
    my $qt_dir    = $self->{ 'qt.dir' };
    my $make_bin  = $self->{ 'make.bin' };
    my $make_args = $self->{ 'make.args' };

    # settings for this autotest run
    my $tests_dir            = $args{ tests_dir };
    my $insignificant_option = $args{ insignificant_option };
    my $do_compile           = $args{ do_compile };
    my $insignificant        = $self->{ $insignificant_option };

    my $testrunner_command = $self->get_testrunner_command( );

    # Add qtbase/bin (core tools) to PATH.
    # FIXME: at some point, we should be doing `make install'.  If that is done,
    # the PATH used here should be the install path rather than build path.
    local $ENV{ PATH } = $ENV{ PATH };
    Env::Path->PATH->Prepend( catfile( $qt_dir, 'qtbase', 'bin' ) );

    my $run = sub {
        chdir( $tests_dir );

        if ($do_compile) {
            $self->exe( 'qmake' );
            $self->exe( $make_bin, '-k', split(/ /, $make_args) );
        }

        $self->exe( $make_bin,
            '-j1',                              # in serial (autotests are generally parallel-unsafe)
            '-k',                               # keep going after failure
                                                # (to get as many results as possible)
            "TESTRUNNER=$testrunner_command",   # use our testrunner script
            'check',                            # run the autotests :)
        );
    };

    if ($insignificant) {
        eval { $run->() };
        if ($EVAL_ERROR) {
            warn "$EVAL_ERROR\n"
                .qq{This is a warning, not an error, because the `$insignificant_option' option }
                . q{was used.  This means the tests are currently permitted to fail};
        }
    }
    else {
        $run->();
    }

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
