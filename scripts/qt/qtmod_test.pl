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

use FindBin;
use lib "$FindBin::Bin/../lib/perl5";

package QtQA::ModuleTest;
use base qw(QtQA::TestScript);

use Carp;
use Cwd qw( abs_path );
use Data::Dumper;
use English qw( -no_match_vars );
use Env::Path;
use File::chdir;
use File::Basename;
use File::Path;
use File::Spec::Functions qw( :ALL );
use List::MoreUtils qw( any apply );
use autodie;
use Readonly;
use Text::Trim;
use Cwd;

#Code coverage tools
Readonly my $TESTCOCOON  => 'testcocoon';

Readonly my %COVERAGE_TOOLS => (
    $TESTCOCOON  =>  1,
);

# Build parts which are useful for testing a module, but not useful for other
# modules built on top of the current module.
# For example, qtdeclarative does not use the examples or tests from qtbase,
# but it may use the libs and tools.
Readonly my @OPTIONAL_BUILD_PARTS => qw(examples tests);

# All properties used by this script.
my @PROPERTIES = (
    q{base.dir}                => q{top-level source directory of module to test},

    q{shadowbuild.dir}         => q{top-level build directory; defaults to $(base.dir). }
                                . q{Setting this to any value other than $(base.dir) implies }
                                . q{a shadow build, in which case the directory will be }
                                . q{recursively deleted if it already exists, and created if }
                                . q{it does not yet exist.},

    q{location}                => q{location hint for git mirrors (`oslo' or `brisbane'); }
                                . q{only useful inside of Nokia LAN},

    q{qt.branch}               => q{git branch of Qt superproject (e.g. `stable'); only used }
                                . q{if qt.gitmodule != "qt5"},

    q{qt.deps_branch}          => q{default git branch for the tested repo's dependencies},

    q{qt.configure.args}       => q{space-separated arguments passed to Qt's configure},

    q{qt.configure.extra_args} => q{more space-separated arguments passed to Qt's configure; }
                                . q{these are appended to qt.configure.args when configure is }
                                . q{invoked},

    q{qt.init-repository.args} => q{space-separated arguments passed to Qt5's init-repository }
                                . q{script},

    q{qt.coverage.tests_output}
                               => q{full path to the file gathering results from coverage tool},

    q{qt.coverage.tool}        => q{coverage tool name; giving a valid coverage tool name here will }
                                . q{enable code coverage using the tool given here. e.g. testcocoon },

    q{qt.dir}                  => q{top-level source directory of Qt superproject; }
                                . q{the script will clone qt.repository into this location if it }
                                . q{does not exist. Testing without the superproject is not }
                                . q{supported},

    q{qt.install.dir}          => q{directory where Qt is expected to be installed (e.g. as set by }
                                . q{-prefix option to configure). Mandatory if qt.make_install is 1. }
                                . q{This directory will be recursively deleted if it already exists. }
                                . q{After installation, basic verification of the install will be }
                                . q{performed},

    q{qt.make_install}         => q{if 1, perform a `make install' step after building Qt. }
                                . q{Generally this should only be done if (1) the `-prefix' }
                                . q{configure option has been used appropriately, and (2) }
                                . q{the `-developer-build' configure argument was not used},

    q{qt.make_html_docs}       => q{if 1, perform a `make html_docs' step after building Qt. },

    q{qt.make_html_docs.insignificant}
                               => q{if 1, ignore all failures from 'make html_docs'},

    q{qt.gitmodule}            => q{(mandatory) git module name of the module under test }
                                . q{(e.g. `qtbase').  Use special value `qt5' for testing of }
                                . q{all modules together in the qt5 superproject},

    q{qt.revdep.gitmodule}     => q{git module name of the reverse dependency module under test }
                                . q{(e.g. `qtdeclarative').  Normally left empty.  Setting this }
                                . q{will switch the script into a mode where it tests the revdep }
                                . q{git module on top of one of its dependencies (e.g. testing }
                                . q{qtdeclarative on top of qtbase)},

    q{qt.revdep.revdep_ref}    => q{git ref for the name of the reverse dependency module under test }
                                . q{(e.g. `refs/heads/stable'); mandatory iff qt.revdep.gitmodule is }
                                . q{set},

    q{qt.revdep.dep_ref}       => q{git ref for the name of the dependency module upon which the }
                                . q{revdep shall be tested (e.g. `refs/heads/stable'); mandatory iff }
                                . q{qt.revdep.gitmodule is set},

    q{qt.repository}           => q{giturl of Qt superproject; only used if }
                                . q{qt.gitmodule != "qt5"},

    q{qt.minimal_deps}         => q{if 1, when building a module other than qt5 or qtbase, only }
                                . q{build the minimum necessary parts of each dependency.  In }
                                . q{particular, do not build the autotests or examples for the }
                                . q{modules we depend on.  This option passes -nomake tests }
                                . q{-nomake examples to configure, and QT_BUILD_PARTS+=tests }
                                . q{QT_BUILD_PARTS+=examples while qmaking the module under }
                                . q{test, and therefore requires these features to be correctly }
                                . q{implemented},

    q{qt.tests.enabled}        => q{if 1, run the autotests (for this module only, or all }
                                . q{modules if qt.gitmodule == "qt5")},

    q{qt.tests.insignificant}  => q{if 1, ignore all failures from autotests},

    q{qt.tests.args}           => q{additional arguments to pass to the tests},

    q{qt.tests.timeout}        => q{default maximum runtime permitted for each autotest, in seconds; }
                                . q{any test which does not completed within this time will be }
                                . q{killed and considered a failure. When using testscheduler, may }
                                . q{be overridden by setting testcase.timeout in a test .pro file},

    q{qt.tests.capture_logs}   => q{if set to a directory name, capture all test logs into this }
                                . q{directory.  For example, setting qt.tests.capture_logs=}
                                . q{$HOME/test-logs will create one file in $HOME/test-logs for }
                                . q{each autotest which is run.  If neither this nor }
                                . q{qt.tests.tee_logs are used, tests print to STDOUT/STDERR }
                                . q{as normal},

    q{qt.tests.tee_logs}       => q{like qt.tests.capture_logs, but also print the test logs to }
                                . q{STDOUT/STDERR as normal while the tests are running},

    q{qt.tests.backtraces}     => q{if 1, attempt to capture backtraces from crashing tests, }
                                . q{using the platform's best available mechanism; currently }
                                . q{uses gdb on Linux, CrashReporter on Mac, and does not work }
                                . q{on Windows},

    q{qt.tests.testscheduler}  => q{if 1, run the autotests via the testscheduler script, rather }
                                . q{than directly by `make check'; this is intended to eventually }
                                . q{become the default},

    q{qt.tests.testscheduler.args}
                               => q{arguments to pass to testscheduler, if any; for example, -j4 }
                                . q{to run autotests in parallel},

    q{qt.tests.flaky.enabled}   => q{enable flaky test plugin },

    q{qt.tests.flaky_mode}     => q{how to handle flaky autotests ("best", "worst" or "ignore")},

    q{qt.tests.dir}            => q{directory where to run the testplanner and execute tests},

    q{qt.mobile.test.enabled}  => q{enabling non-default testrunner},

    q{qt.mobile.testrunner}    => q{external perl script to run tests on mobile target like Android},

    q{qt.mobile.testrunner.args}
                               => q{args for perl script to run tests on mobile target},

    q{qt.qtqa-tests.enabled}   => q{if 1, run the shared autotests in qtqa (over this module }
                                . q{only, or all modules if qt.gitmodule == "qt5").  The qtqa }
                                . q{tests are run after the other autotests.},

    q{qt.qtqa-tests.insignificant}
                               => q{if 1, ignore all failures from shared autotests in qtqa},

    q{make.bin}                => q{`make' command (e.g. `make', `nmake', `jom' ...)},

    q{make.args}               => q{extra arguments passed to `make' command (e.g. `-j25')},

    q{make-check.bin}          => q{`make' command used for running `make check' (e.g. `make', }
                                . q{`nmake', `jom'); defaults to the value of make.bin},

    q{make-check.args}         => q{extra arguments passed to `make check' command when running }
                                . q{tests (e.g. `-j2'); defaults to the value of make.args with }
                                . q{any -jN replaced with -j1, and with -k appended},

    q{qt.sync.profile.dir}     => q{dir prefix, if sync.profile is not stored directly under }
                                . q{$qt.gitmodule/sync.profile. This will append it to }
                                . q{$qt.gitmodule/$qt.sync.profile.dir/sync.profile },


);

# gitmodules for which `make check' is not yet safe.
# These should be removed one-by-one as modules are verified to work correctly.
# See task QTQAINFRA-142
my %MAKE_CHECK_BLACKLIST = map { $_ => 1 } qw(
    qtrepotools
    qtwebkit
);

# Some modules contains nested submodules. Until we get rid of old git
# clients, like in Ubuntu 11.10, we can't run submodule update for some
# of the modules
my %SUBMODULE_UPDATE_BLACKLIST = map { $_ => 1 } qw(
    qtdeclarative
);

# Like abs_path, but dies instead of returning an empty value if dirname($path)
# doesn't exist.
sub safe_abs_path
{
    my ($self, $path) = @_;

    # On Windows, abs_path dies if $path doesn't exist.
    # On Unix, it is OK if $path doesn't exist, as long as dirname($path) exists.
    # Adjust the lookup to get the same behavior on both platforms.
    my $end;
    if (! -e $path) {
        ($end, $path) = fileparse( $path );
    }

    my $abs_path = eval { abs_path( $path ) };
    if ($@ || !$abs_path) {
        $self->fatal_error(
            "path '$path' unexpectedly does not exist (while in directory: $CWD)"
        );
    }

    if ($end) {
        $abs_path = catfile( $abs_path, $end );
    }

    return $abs_path;
}

# Returns 1 if ($path_a, $path_b) refer to the same path.
# Dies if either of dirname($path_a) or dirname($path_b) don't exist.
sub path_eq
{
    my ($self, $path_a, $path_b) = @_;
    return 1 if ($path_a eq $path_b);

    ($path_a, $path_b) = ($self->safe_abs_path( $path_a ), $self->safe_abs_path( $path_b ));
    return 1 if ($path_a eq $path_b);

    return 0;
}

# Returns 1 if $sub is underneath or equal to $base.
# Dies if either of dirname($base) or dirname($sub) don't exist.
sub path_under
{
    my ($self, $base, $sub) = @_;
    return 1 if ($base eq $sub);

    ($base, $sub) = map { canonpath( $self->safe_abs_path( $_ ) ) } ($base, $sub);
    return 1 if ($base eq $sub);

    return 1 if ($sub =~ m{\A\Q$base\E(?:/|\\)});
    return 0;
}

sub run
{
    my ($self) = @_;

    $self->read_and_store_configuration;

    my $qt_gitmodule = $self->{ 'qt.gitmodule' };
    my $doing = $self->doing( "testing $qt_gitmodule" );

    $self->run_clean_directories;
    $self->run_git_checkout;

    my $doing_revdep = $self->maybe_enter_revdep_context;

    $self->run_configure;
    $self->run_qtqa_autotests( 'prebuild' );
    $self->run_compile;
    $self->run_install;
    $self->run_install_check;
    $self->run_make_html_docs;
    $self->run_autotests;
    $self->run_coverage;
    $self->run_qtqa_autotests( 'postbuild' );

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
    my $have_qtgitreadonly;
    if (0 == system(qw(git config --get-regexp ^url\..*\.insteadof$ ^qtgitreadonly:$))) {
        $have_qtgitreadonly = 1;
    }

    return ( $self->{'location'} ) ? 'git://scm.dev.nokia.troll.no/qt/qt5.git'
         : ( $have_qtgitreadonly ) ? 'qtgitreadonly:qt/qt5.git'
         :                           'git://qt.gitorious.org/qt/qt5.git';
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

sub default_qt_revdep_ref
{
    my ($self) = @_;

    # If qt.revdep.gitmodule is set, this is mandatory.
    # Otherwise, it is unused.
    return $self->{ 'qt.revdep.gitmodule' } ? undef : q{};
}

sub default_qt_dir
{
    my ($self) = @_;

    # We don't need to clone qt5 superproject for qt/qt5.git or qt/qt.git
    if (($self->{'qt.gitmodule'} eq 'qt5') or ($self->{'qt.gitmodule'} eq 'qt')) {
        return $self->{ 'base.dir' };
    }

    return catfile( $self->{'base.dir'}, 'qt' );
}

sub default_qt_configure_args
{
    my ($self) = @_;

    return q{-opensource -confirm-license -prefix }.catfile( $self->{ 'qt.dir' }, 'qtbase' );
}

sub default_qt_tests_args
{
    my ($self) = @_;

    my @out = ('-silent');

    # If we're capturing logs, arrange to capture native XML by default
    # for maximum fidelity, and also print to stdout for live feedback.
    if ($self->{ 'qt.tests.capture_logs' } || $self->{ 'qt.tests.tee_logs' }) {
        # Will create files like:
        #
        #   path/to/capturedir/tst_qstring-testresults-00.xml
        #   path/to/capturedir/tst_qwidget-testresults-00.xml
        #
        # ...etc.
        push @out, '-o', 'testresults.xml,xml', '-o', '-,txt';
    }

    return join(' ', @out);
}

sub default_make_check_bin
{
    my ($self) = @_;
    return $self->{ 'make.bin' };
}

sub default_make_check_args
{
    my ($self) = @_;

    my @make_args = split(/ /, $self->{ 'make.args' });

    # Arguments for `make check' are like the arguments for `make',
    # except:
    #
    #  - we want to keep running as many tests as possible, even after failures
    #
    if (! any { m{\A [/\-]k \z }xmsi } @make_args) {
        push @make_args, '-k';
    }

    #  - we want to run the tests one at a time (-j1), as they are not all
    #    parallel-safe; but note that nmake always behavies like -j1 and dies
    #    if explicitly passed -j1.
    #
    @make_args = apply { s{\A -j\d+ \z}{-j1}xms } @make_args;

    return join(' ', @make_args);
}

sub default_qt_minimal_deps
{
    my ($self) = @_;

    my $gitmodule = $self->{ 'qt.revdep.gitmodule' } || $self->{ 'qt.gitmodule' };

    # minimal dependencies makes sense for everything but these three
    return ($gitmodule ne 'qt5' && $gitmodule ne 'qtbase' && $gitmodule ne 'qt');
}

sub default_qt_install_dir
{
    my ($self) = @_;

    # qt.make_install is mandatory to be set if 'make install' is called,
    # otherwise no value is needed.
    if ($self->{ 'qt.make_install' }) {
        return;
    }
    else {
        return q{};
    }
}

sub read_and_store_configuration
{
    my $self = shift;

    my $doing = $self->doing( 'determining test script configuration' );

    $self->read_and_store_properties(
        'base.dir'                => \&QtQA::TestScript::default_common_property ,
        'shadowbuild.dir'         => \&QtQA::TestScript::default_common_property ,
        'location'                => \&QtQA::TestScript::default_common_property ,
        'make.args'               => \&QtQA::TestScript::default_common_property ,
        'make.bin'                => \&QtQA::TestScript::default_common_property ,

        'make-check.args'         => \&default_make_check_args                   ,
        'make-check.bin'          => \&default_make_check_bin                    ,
        'qt.gitmodule'            => undef                                       ,
        'qt.revdep.gitmodule'     => q{}                                         ,
        'qt.revdep.revdep_ref'    => \&default_qt_revdep_ref                     ,
        'qt.revdep.dep_ref'       => \&default_qt_revdep_ref                     ,
        'qt.dir'                  => \&default_qt_dir                            ,
        'qt.repository'           => \&default_qt_repository                     ,
        'qt.branch'               => q{dev}                                      ,
        'qt.deps_branch'          => q{}                                         ,
        'qt.init-repository.args' => q{}                                         ,
        'qt.configure.args'       => \&default_qt_configure_args                 ,
        'qt.configure.extra_args' => q{}                                         ,
        'qt.coverage.tests_output'=> q{}                                         ,
        'qt.coverage.tool'        => q{}                                         ,
        'qt.make_install'         => 0                                           ,
        'qt.make_html_docs'       => 0                                           ,
        'qt.make_html_docs.insignificant' => 0                                   ,
        'qt.minimal_deps'         => \&default_qt_minimal_deps                   ,
        'qt.install.dir'          => \&default_qt_install_dir                    ,
        'qt.tests.enabled'        => \&default_qt_tests_enabled                  ,
        'qt.tests.testscheduler'  => 0                                           ,
        'qt.tests.testscheduler.args' => q{}                                     ,
        'qt.tests.insignificant'  => 0                                           ,
        'qt.tests.timeout'        => 450                                         ,
        'qt.tests.capture_logs'   => q{}                                         ,
        'qt.tests.tee_logs'       => q{}                                         ,
        'qt.tests.dir'            => q{}                                         ,
        'qt.tests.args'           => \&default_qt_tests_args                     ,
        'qt.tests.backtraces'     => \&default_qt_tests_backtraces               ,
        'qt.tests.flaky_mode'     => q{}                                         ,
        'qt.tests.flaky.enabled'  => 1                                           ,
        'qt.mobile.test.enabled'  => 0                                           ,
        'qt.mobile.testrunner'      => q{}                                       ,
        'qt.mobile.testrunner.args' => q{}                                       ,

        'qt.qtqa-tests.enabled'         => 0                                     ,
        'qt.qtqa-tests.insignificant'   => 0                                     ,
        'qt.sync.profile.dir'     => q{}                                         ,

    );

    # for convenience only - this should not be overridden
    $self->{'qt.gitmodule.dir'} = ($self->{'qt.gitmodule'} eq 'qt5')
        ? $self->{'qt.dir'}
        : catfile( $self->{'qt.dir'}, $self->{'qt.gitmodule'} )
    ;

    # Path of the top-level qt5 build:
    $self->{'qt.build.dir'} = ($self->{'base.dir'} eq $self->{'shadowbuild.dir'})
        ? $self->{'qt.dir'}          # no shadow build - same path as qt sources
        : $self->{'shadowbuild.dir'} # shadow build - whatever is requested by the property
    ;

    # Path of this gitmodule's build;
    $self->{'qt.gitmodule.build.dir'} = (($self->{'qt.gitmodule'} eq 'qt5') or ($self->{'qt.gitmodule'} eq 'qt'))
        ? $self->{'qt.build.dir'}
        : catfile( $self->{'qt.build.dir'}, $self->{'qt.gitmodule'} )
    ;

    if ($self->{'qt.tests.capture_logs'} && $self->{'qt.tests.tee_logs'}) {
        delete $self->{'qt.tests.capture_logs'};
        warn 'qt.tests.capture_logs and qt.tests.tee_logs were both specified; '
            .'tee_logs takes precedence';
    }

    if ($self->{'qt.coverage.tool'} && !$COVERAGE_TOOLS{ $self->{'qt.coverage.tool'} }) {
        die "'$self->{'qt.coverage.tool'}' is not a valid Qt coverage tool; try one of ".join(q{,}, keys %COVERAGE_TOOLS);
    }

    if ($self->{'qt.minimal_deps'}
        && !$self->{'qt.revdep.gitmodule'}
        && ($self->{'qt.gitmodule'} eq 'qt5' || $self->{'qt.gitmodule'} eq 'qtbase'))
    {
        warn "qt.minimal_deps is set to 1.  This has no effect on $self->{ 'qt.gitmodule' }.\n";
        $self->{'qt.minimal_deps'} = 0;
    }

    # Make sure revdep settings are sensible:
    #  - revdep test doesn't make sense for modules with no dependencies.
    #  - revdep test on top of qt4 (not modular) doesn't make sense
    #  - revdep test on top of qt5 could make sense, but is not yet supported
    my %no_dependencies = map { $_ => 1 } qw(qt qt5 qtbase);
    my %not_supported_revdep_base = map { $_ => 1 } qw(qt qt5);
    if ($no_dependencies{ $self->{'qt.revdep.gitmodule'} }) {
        $self->fatal_error(
            "'$self->{'qt.revdep.gitmodule'}' does not make sense for a revdep test; "
           ."it has no dependencies"
        );
    } elsif ($self->{'qt.revdep.gitmodule'} && $not_supported_revdep_base{ $self->{'qt.gitmodule'} }) {
        $self->fatal_error(
            "doing a revdep test on top of $self->{'qt.gitmodule'} is currently not supported"
        );
    }

    return;
}

sub read_dependencies
{
    my ($self, $dependency_file) = @_;

    my $doing = $self->doing( "reading dependencies from ".abs2rel( $dependency_file ) );

    our (%dependencies);

    my %default_dependencies = ( 'qtbase' => 'refs/heads/dev' );
    my $default_reason;

    if (! -e $dependency_file ) {
        $default_reason = "$dependency_file doesn't exist";
    }
    else {
        unless ( do $dependency_file ) {
            my ($action, $error);
            if ($@) {
                ($action, $error) = ('parse', $@);
            } elsif ($!) {
                ($action, $error) = ('execute', $!);
            }
            if ($error) {
                $self->fail(
                    "I couldn't $action $dependency_file, which I need to determine dependencies.\n"
                   ."The error was $error\n"
                );
            }
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

sub run_clean_directories
{
    my ($self) = @_;

    my $doing = $self->doing( 'cleaning existing target directories' );

    my $qt_dir = $self->{ 'qt.dir' };
    my $qt_build_dir = $self->{ 'qt.build.dir' };
    my $qt_install_dir = $self->{ 'qt.install.dir' };

    my @to_delete;
    my @to_create;

    if ($qt_dir ne $qt_build_dir) {
        # shadow build?  make sure we start clean.
        if (-e $qt_build_dir) {
            push @to_delete, $qt_build_dir;
        }
        push @to_create, $qt_build_dir;
    }

    if ($qt_install_dir
            && -d dirname( $qt_install_dir )
            && !$self->path_under( $qt_build_dir, $qt_install_dir )
            && -e $qt_install_dir
    ) {
        push @to_delete, $qt_install_dir;
        # note we do not create the install dir, `make install' is expected to do that
    }

    # Job can be configured to outside base.dir.
    # If we are in same dir, it was already deleted
    if ((-e $qt_dir) && ( cwd() ne $qt_dir)) {
        push @to_delete, $qt_dir;
    }
    # it will get created once cloned and checked out

    if (@to_delete) {
        local $LIST_SEPARATOR = qq{\n*** WARNING:    };
        warn(
             ("*" x 80)."\n"
            ."*** WARNING: About to remove:$LIST_SEPARATOR@to_delete\n"
            ."*** WARNING: You have only a few seconds to abort (CTRL+C) !\n"
            .("*" x 80)."\n"
        );
        sleep 15;
        warn "Removing...\n";
        rmtree( \@to_delete );
        warn "Removed.\n";
    }

    mkpath( \@to_create );

    return;
}

# If revdep mode is enabled, set qt.gitmodule=qt.revdep.gitmodule, so the rest of the
# script will test the revdep.  This should be called after the initial git setup.
#
# Warning: this is non-reversible!
#
sub maybe_enter_revdep_context
{
    my ($self) = @_;

    my $qt_revdep_gitmodule = $self->{ 'qt.revdep.gitmodule' };
    my $qt_revdep_revdep_ref = $self->{ 'qt.revdep.revdep_ref' };
    my $qt_gitmodule = $self->{ 'qt.gitmodule' };

    return unless $qt_revdep_gitmodule;

    my $what = "testing reverse dependency $qt_revdep_gitmodule ($qt_revdep_revdep_ref) "
              ."on top of $qt_gitmodule";

    print __PACKAGE__ . ": $what\n";

    $self->{ 'qt.gitmodule' } = $qt_revdep_gitmodule;
    $self->{ 'qt.gitmodule.dir' } = catfile( $self->{'qt.dir'}, $self->{'qt.gitmodule'} );
    $self->{ 'qt.gitmodule.build.dir' } = catfile( $self->{'qt.build.dir'}, $self->{'qt.gitmodule'} );

    return $self->doing( $what );
}

# Run init-repository for the given @modules.
# This may be safely run more than once to incrementally clone additional modules.
# @modules may be omitted to imply _all_ modules.
sub do_init_repository
{
    my ($self, @modules) = @_;

    my $doing = $self->doing( 'running init-repository for '.join(',', @modules) );

    my $qt_dir = $self->{ 'qt.dir' };
    my $qt_init_repository_args = $self->{ 'qt.init-repository.args' };
    my $location = $self->{ 'location' };

    local $CWD = $qt_dir;

    my @init_repository_arguments = split( q{ }, $qt_init_repository_args );

    if (defined( $location ) && ($location eq 'brisbane')) {
        push @init_repository_arguments, '-brisbane-nokia-developer';
    }
    elsif (defined( $location ) && ($location eq 'oslo')) {
        push @init_repository_arguments, '-nokia-developer';
    }

    if (@modules) {
        push @init_repository_arguments, '--module-subset='.join(q{,}, @modules);
    }

    # We use `-force' so that init-repository can be restarted if it hits an error
    # halfway through.  Without this, it would refuse.
    push @init_repository_arguments, '-force';

    $self->exe( { reliable => 'git' },  # recover from transient git errors during init-repository
        'perl', './init-repository', @init_repository_arguments
    );

    return;
}

sub set_module_refs
{
    my ($self, %module_to_ref) = @_;

    my $qt_dir = $self->{ 'qt.dir' };
    my $qt_ref = $self->{ 'qt.deps_branch' };
    $qt_ref = $self->{ 'qt.branch' } if ($qt_ref eq '');
    $qt_ref = "refs/heads/".$qt_ref;

    # Checkout dependencies as specified in the sync.profile, which specifies the sha1s/refs within them
    # Also, this code assumes that init-repository always uses `origin' as the remote.
    while ( my ($module, $ref) = each %module_to_ref ) {
        local $CWD = catfile( $qt_dir, $module );
        $ref = $qt_ref if ($ref eq '');

        # FIXME how do we guarantee we have this SHA1?
        # If it's not reachable from a branch obtained from a default `clone', it could be missing.
        if ( $ref !~ /^[0-9a-f]{40}$/) { # Not a SHA1, fetch origin to ensure using correct SHA-1
            $self->exe( 'git', 'fetch', '--verbose', '--update-head-ok', 'origin', "+$ref:$ref" );
        }
        $self->exe( 'git', 'reset', '--hard', $ref );

        # init-repository is expected to initialize any nested gitmodules where
        # necessary; however, since we are changing the tracked SHA1 here, we
        # need to redo a `submodule update' in case any gitmodule content is
        # affected.  Note that the `submodule update' is a no-op in the usual case
        # of no nested gitmodules.
        if ($SUBMODULE_UPDATE_BLACKLIST{$module}) {
            warn "It is not safe to run submodule update for $module";
        } else {
            $self->exe( 'git', 'submodule', 'update', '--recursive', '--init' );
        }
    }

    return;
}

# Maybe skip (warn and exit with 0 exit code) the revdep test, if:
#  - the revdep module actually does not depend on _this_ module.
#  - the revdep sync.profile refers to a ref other than qt.revdep.dep_ref
#
sub maybe_skip_revdep_test
{
    my ($self, %module_to_ref) = @_;

    my $qt_gitmodule = $self->{ 'qt.gitmodule' };
    my $qt_revdep_gitmodule = $self->{ 'qt.revdep.gitmodule' };
    my $qt_revdep_dep_ref = $self->{ 'qt.revdep.dep_ref' };

    if (! exists $module_to_ref{ $qt_gitmodule }) {
        warn "revdep module [$qt_revdep_gitmodule] does not depend on this module "
            ."[$qt_gitmodule].\nrevdep test skipped.\n";
        exit 0;
    }

    my $wanted_dep_ref = $module_to_ref{ $qt_gitmodule };
    if ($wanted_dep_ref ne $qt_revdep_dep_ref && $wanted_dep_ref ne '') {
        warn "revdep module's sync.profile refers to a ref other than this one:\n"
            ."  [$qt_revdep_gitmodule]: $qt_gitmodule => $wanted_dep_ref\n"
            ."  [$qt_gitmodule]: qt.revdep.dep_ref => $qt_revdep_dep_ref\n"
            ."revdep test skipped.\n";
        exit 0;
    }

    return;
}

sub run_git_checkout
{
    my ($self) = @_;

    my $doing = $self->doing( 'setting up git repositories' );

    my $base_dir      = $self->{ 'base.dir'      };
    my $qt_init_repository_args
                      = $self->{ 'qt.init-repository.args' };
    my $qt_branch     = $self->{ 'qt.branch'     };
    my $qt_repository = $self->{ 'qt.repository' };
    my $qt_dir        = $self->{ 'qt.dir'        };
    my $qt_gitmodule  = $self->{ 'qt.gitmodule'  };
    my $qt_revdep_gitmodule = $self->{ 'qt.revdep.gitmodule' };
    my $qt_revdep_revdep_ref = $self->{ 'qt.revdep.revdep_ref' };
    my $location      = $self->{ 'location'      };
    my $qt_sync_profile_dir = $self->{ 'qt.sync.profile.dir' };


    # We don't need to clone submodules for qt/qt.git
    return if ($qt_gitmodule eq 'qt');

    chdir( $base_dir );

    # Store the SHA1 to be tested into refs/testing before doing anything which might
    # move us to some other revision.
    $self->exe( 'git', 'update-ref', 'refs/testing', 'HEAD' );

    # Clone the Qt superproject
    if ($qt_gitmodule ne 'qt5') {
        $self->exe( 'git', 'clone', '--branch', $qt_branch, $qt_repository, $qt_dir );
    }

    if ($qt_gitmodule eq 'qt5') {
        # We have to set the remote url to be used with older git clients
        $self->exe( 'git', 'config', 'remote.origin.url', $qt_repository );
    }

    local $CWD = $qt_dir;

    # map from gitmodule name to desired ref for testing
    my %module_to_ref;

    # list of modules we need to clone via init-repository
    my @needed_modules;

    if ($qt_revdep_gitmodule) {
        # In revdep mode, the revdep determines the needed modules...
        $self->do_init_repository( $qt_revdep_gitmodule );
        $self->set_module_refs( $qt_revdep_gitmodule => $qt_revdep_revdep_ref );
        %module_to_ref = $self->read_dependencies( catfile($qt_revdep_gitmodule, 'sync.profile') );
        $self->maybe_skip_revdep_test( %module_to_ref );
        # ...but we don't respect the revdep's sync.profile entry for _this_ module, since we're testing
        # an incoming change
        delete $module_to_ref{ $qt_gitmodule };
    } elsif ($qt_gitmodule ne 'qt5' && $qt_gitmodule ne 'qtbase') {
        %module_to_ref = $self->read_dependencies( catfile($base_dir, $qt_sync_profile_dir, 'sync.profile') );
    }

    # clone any remaining modules we haven't got yet.
    push @needed_modules, keys( %module_to_ref );

    # only do init-repository if there's at least one needed module, or if we're
    # testing qt5 (in which case we expect to test _all_ modules).
    # Note that @needed_modules should _not_ contain $qt_gitmodule, that is handled
    # in the next step.
    if (@needed_modules || $qt_gitmodule eq 'qt5') {
        $self->do_init_repository( @needed_modules );
    }

    # Now we need to set the submodule content equal to our tested module's base.dir
    if ($qt_gitmodule ne 'qt5') {
        # Store a flag telling us whether or not this is a module hosted in qt5.git;
        # the build/test procedure can differ slightly depending on this value.
        $self->{ module_in_qt5 } = (-d $qt_gitmodule);

        if ($self->path_eq( $base_dir, $qt_gitmodule )) {
            # If the gitmodule directory in qt5.git is equal to base.dir, then we already
            # have the repo; we just need to set the revision back to what it was before
            # init-repository.
            $module_to_ref{ $qt_gitmodule } = 'refs/testing';
        } else {
            # Otherwise, we don't have the repo (we didn't pass it to init-repository).
            # base.dir's HEAD should still point at what we want to test, so just clone
            # it, and no further work required.

            # The directory should be empty; verify it first.
            # Git will give a fatal error if it isn't empty; by verifying it first,
            # we can give a more detailed and explicit error message.
            my @files;
            if (-d $qt_gitmodule) {
                local $CWD = $qt_gitmodule;
                push @files, glob( '*' );
                push @files, glob( '.*' );
                @files = grep { $_ ne '.' && $_ ne '..' } @files;
            }
            if (@files) {
                $self->fatal_error(
                    "Dirty build directory; '$qt_gitmodule' exists and is not empty.\n"
                   ."Saw files: @files"
                );
            }

            $self->exe( 'git', 'clone', '--shared', $base_dir, $qt_gitmodule );

            if ($SUBMODULE_UPDATE_BLACKLIST{$qt_gitmodule}) {
              warn "It is not safe to run submodule update for $qt_gitmodule";
            } else {
                # run git submodule update for module under test, if there is one for module
                chdir( $qt_gitmodule );
                my $res = $self->exe_qx( 'git', 'submodule', 'status');
                if ($res ne "") {
                    # Check the submodules url and make it to point local mirror if it is relative
                    my $submodule_url = $self->exe_qx('git config -f .gitmodules --get-regexp submodule\..*\.url');
                    for (split /^/, $submodule_url) {
                        my ($submodule, $url) = split / /;
                        if ($url =~ s/^\.\./qtgitreadonly:qt/) {
                            $self->exe('git', 'config', $submodule, $url);
                        }
                    }
                    $self->exe( 'git', 'submodule', 'update', '--recursive', '--init' );
                }
                # return just in case
                chdir( $qt_dir );
            }
        }
    }

    # Set various modules to the SHA1s we want.
    $self->set_module_refs( %module_to_ref );

    return;
}

sub run_configure
{
    my ($self) = @_;

    my $doing = $self->doing( 'configuring Qt' );

    # properties
    my $qt_dir                  = $self->{ 'qt.dir'                  };
    my $qt_build_dir            = $self->{ 'qt.build.dir'            };
    my $qt_configure_args       = $self->{ 'qt.configure.args'       };
    my $qt_configure_extra_args = $self->{ 'qt.configure.extra_args' };
    my $qt_coverage_tool        = $self->{ 'qt.coverage.tool'        };
    my $qt_minimal_deps         = $self->{ 'qt.minimal_deps'         };

    if ($qt_coverage_tool) {
        $qt_configure_extra_args .= " -$qt_coverage_tool";
    }

    if ($qt_minimal_deps) {
        # In minimal deps mode, we turn off the optional build parts globally, then later
        # turn them on explicitly for this particular module under test.
        $qt_configure_extra_args .= join( ' -nomake ', q{}, @OPTIONAL_BUILD_PARTS );
    }

    chdir( $qt_build_dir );

    my $configure = catfile( $qt_dir, 'configure' );
    if ($OSNAME =~ /win32/i) {
        if ($self->{ 'qt.gitmodule' } eq 'qt') {
            # Qt4 does not have a .bat but .exe configure script
            $configure .= '.exe';
        }
        else {
            $configure .= '.bat';
        }
    }

    $self->exe( $configure, split(/\s+/, "$qt_configure_args $qt_configure_extra_args") );

    return;
}


sub run_compile
{
    my ($self) = @_;

    my $doing = $self->doing( 'compiling Qt' );

    # properties
    my $qt_dir                  = $self->{ 'qt.dir'                  };
    my $qt_build_dir            = $self->{ 'qt.build.dir'            };
    my $qt_install_dir          = $self->{ 'qt.install.dir'          };
    my $qt_gitmodule            = $self->{ 'qt.gitmodule'            };
    my $qt_gitmodule_dir        = $self->{ 'qt.gitmodule.dir'        };
    my $qt_gitmodule_build_dir  = $self->{ 'qt.gitmodule.build.dir'  };
    my $make_bin                = $self->{ 'make.bin'                };
    my $make_args               = $self->{ 'make.args'               };
    my $qt_configure_args       = $self->{ 'qt.configure.args'       };
    my $qt_configure_extra_args = $self->{ 'qt.configure.extra_args' };
    my $qt_make_install         = $self->{ 'qt.make_install'         };
    my $qt_minimal_deps         = $self->{ 'qt.minimal_deps'         };

    my $qmake_bin = catfile( $qt_build_dir, 'qtbase', 'bin', 'qmake' );
    my $qmake_install_bin = catfile( $qt_install_dir, 'bin', 'qmake' );

    # true iff the module is hosted in qt5.git (affects build procedure)
    my $module_in_qt5 = $self->{ module_in_qt5 };

    chdir( $qt_build_dir );

    my @make_args = split(/ /, $make_args);
    my @commands;

    my @qmake_args;
    # do not build tools when targeting xplatform
    my $make_tools = ($qt_configure_extra_args =~ m/-xplatform/ or $qt_configure_args =~ m/-xplatform/) ? "" : "tools ";
    if ($qt_minimal_deps) {
        # Qt 5 only:
        # minimal deps mode?  Then we turned off some build parts in configure, and must
        # now explicitly enable them for this module only.
        push @qmake_args, uc($qt_gitmodule)."_BUILD_PARTS = libs $make_tools".join(" ", @OPTIONAL_BUILD_PARTS);
    }

    if (($self->{'qt.gitmodule'} eq 'qt5') or ($self->{'qt.gitmodule'} eq 'qt')) {
        # Building qt5 or qt4; just do a `make' of all default targets in the top-level makefile.
        push @commands, sub { $self->exe( $make_bin, @make_args ) };
    }
    elsif ($module_in_qt5) {
        # Building a module hosted in qt5; `configure' is expected to have generated a
        # makefile with a `module-FOO' target for this module, with correct dependency
        # information. Issuing a `make module-FOO' should automatically build the module
        # and all deps, as parallel as possible.
        my $make_target = "module-$qt_gitmodule";

        push @commands, sub {
            my $global_qmakeflags = $ENV{'QMAKEFLAGS'};
            local $ENV{'QMAKEFLAGS'} = join(" ", map { '"'.$_.'"' } $global_qmakeflags, @qmake_args);
            $self->exe( $make_bin, @make_args, $make_target );
        };
    }
    else {
        # Building a module, hosted outside of qt5.
        # We need to do three steps; first, build all the dependencies, then qmake this
        # module, then make this module.
        # The Makefile generated in qt5 doesn't know anything about this module.

        # First, we build all deps:
        my %dependencies = $self->read_dependencies( "$qt_gitmodule_dir/sync.profile" );
        my @module_targets = map { "module-$_" } keys %dependencies;
        push @commands, sub { $self->exe( $make_bin, @make_args, @module_targets ) };

        if (! -e $qt_gitmodule_build_dir) {
            mkpath( $qt_gitmodule_build_dir );
            # Note, we don't have to worry about emptying the build dir,
            # because it's always under the top-level build dir, and we already
            # cleaned that if it existed.
        }

        push @commands, sub { chdir( $qt_gitmodule_build_dir ) };

        push @commands, sub { $self->exe(
            $qmake_bin,
            $qt_gitmodule_dir,
            @qmake_args
        ) };

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

    my $doing = $self->doing( 'installing Qt' );

    my $make_bin        = $self->{ 'make.bin' };
    my $qt_dir          = $self->{ 'qt.dir' };
    my $qt_build_dir    = $self->{ 'qt.build.dir' };
    my $qt_gitmodule    = $self->{ 'qt.gitmodule' };
    my $qt_gitmodule_dir= $self->{ 'qt.gitmodule.dir' };
    my $qt_make_install = $self->{ 'qt.make_install' };

    return if (!$qt_make_install);

    chdir( $qt_build_dir );

    if (($self->{'qt.gitmodule'} eq 'qt5') or ($self->{'qt.gitmodule'} eq 'qt')) {
        # Testing all of qt5 or qt4? Just do a top-level `make install'
        $self->exe( $make_bin, 'install' );
    }
    elsif ($self->{ module_in_qt5 }) {
        # Testing some module hosted in qt5.git? Top-level `make module-FOO-install_subtargets'
        # to install this module and all its dependencies.
        $self->exe( $make_bin, "module-$qt_gitmodule-install_subtargets" );
    }
    else {
        # Testing some module hosted outside of qt5.git?
        # Then we need to explicitly install all deps first ...
        my %dependencies = $self->read_dependencies( "$qt_gitmodule_dir/sync.profile" );
        my @module_targets = map { "module-$_-install_subtargets" } keys %dependencies;
        $self->exe( $make_bin, @module_targets );

        # ... and then install the module itself
        chdir( $qt_gitmodule );
        $self->exe( $make_bin, 'install' );
    }

    # Note that we are installed, since this changes some behavior elsewhere
    $self->{ installed } = 1;

    return;
}

sub run_install_check
{
    my ($self) = @_;

    my $doing = $self->doing( 'checking the installation' );

    my $qt_install_dir  = $self->{ 'qt.install.dir' };
    my $qt_make_install = $self->{ 'qt.make_install' };

    return if (!$qt_make_install);

    # check whether dirs 'bin' and 'mkspecs' actually exists under qt.install.dir
    my @required_files = map { "$qt_install_dir/$_" } qw(bin mkspecs);
    my @missing_files = grep { ! -e $_ } @required_files;
    if (@missing_files) {
        $self->fail(
            'The make install command exited successfully, but the following expected file(s) '
           .'are missing from the install tree:'.join("\n ", q{}, @missing_files)."\n"
        );
    }

    return;
}

sub run_make_html_docs
{
    my ($self) = @_;

    my $doing = $self->doing( 'making Qt docs' );

    my $make_bin        = $self->{ 'make.bin' };
    my $qt_build_dir    = $self->{ 'qt.build.dir' };
    my $qt_make_html_docs = $self->{ 'qt.make_html_docs' };
    my $doc_insignificant = $self->{ 'qt.make_html_docs.insignificant' };

    return if (!$qt_make_html_docs);

    my $run = sub {
      chdir( $qt_build_dir );
      $self->exe( $make_bin, 'html_docs' );
    };

    if ($doc_insignificant) {
        eval { $run->() };
        if ($EVAL_ERROR) {
            warn "$EVAL_ERROR\n"
                .qq{This is a warning, not an error, because the 'make html_docs' is permitted to fail};
        } else {
            print "Note: 'make html_docs' succeeded. "
                 ."This may indicate it is safe to enforce the 'make html_docs'.\n";
        }
    }
    else {
        $run->();
    }

    return;

}


# Returns a testrunner command
sub get_testrunner_command
{
    my ($self) = @_;

    my $testrunner = catfile( $FindBin::Bin, '..', 'generic', 'testrunner.pl' );
    $testrunner    = canonpath abs_path( $testrunner );

    # sanity check
    $self->fatal_error( "internal error: $testrunner does not exist" ) if (! -e $testrunner);

    my @testrunner_with_args = (
        $EXECUTABLE_NAME,               # perl
        $testrunner,                    # testrunner.pl
        $self->get_testrunner_args( ),
    );

    return join(' ', @testrunner_with_args);
}

# Returns appropriate testrunner arguments (not including trailing --)
sub get_testrunner_args
{
    my ($self) = @_;

    my $qt_tests_timeout         = $self->{ 'qt.tests.timeout' };
    my $qt_tests_capture_logs    = $self->{ 'qt.tests.capture_logs' };
    my $qt_coverage_tool         = $self->{ 'qt.coverage.tool' };
    my $qt_coverage_tests_output = $self->{ 'qt.coverage.tests_output' };
    my $qt_gitmodule             = $self->{ 'qt.gitmodule' };
    my $qt_gitmodule_dir         = $self->{ 'qt.gitmodule.dir' };
    my $qt_tests_tee_logs        = $self->{ 'qt.tests.tee_logs' };
    my $qt_tests_backtraces      = $self->{ 'qt.tests.backtraces' };
    my $qt_tests_flaky_mode      = $self->{ 'qt.tests.flaky_mode' };
    my $qt_tests_flaky_enabled   = $self->{ 'qt.tests.flaky.enabled' };
    my $qt_tests_testscheduler   = $self->{ 'qt.tests.testscheduler' };

    my @testrunner_args = (
        '--timeout',
        $qt_tests_timeout,  # kill any test which takes longer than this ...
    );

    # capture or tee logs to a given directory
    if ($qt_tests_capture_logs) {
        push @testrunner_args, '--capture-logs', canonpath $qt_tests_capture_logs;
    }
    elsif ($qt_tests_tee_logs) {
        push @testrunner_args, '--tee-logs', canonpath $qt_tests_tee_logs;
    }

    if ($qt_tests_backtraces) {
        if ($OSNAME =~ m{linux}i) {
            push @testrunner_args, '--plugin', 'core';
        }
        elsif ($OSNAME =~ m{darwin}i) {
            push @testrunner_args, '--plugin', 'crashreporter';
        }
    }

    # enable flaky test plugin
    if ($qt_tests_flaky_enabled) {
        # give more info about unstable / flaky tests
        push @testrunner_args, '--plugin', 'flaky';
        if ($qt_tests_flaky_mode) {
            push @testrunner_args, '--flaky-mode', $qt_tests_flaky_mode;
        }
    }

    if ($qt_coverage_tool) {
        push @testrunner_args, '--plugin', $qt_coverage_tool;
        push @testrunner_args, "--${qt_coverage_tool}-qt-gitmodule-dir", canonpath $qt_gitmodule_dir;
        push @testrunner_args, "--${qt_coverage_tool}-qt-gitmodule", $qt_gitmodule;
    }

    if ($qt_coverage_tests_output) {
        push @testrunner_args, "--${qt_coverage_tool}-tests-output", $qt_coverage_tests_output;
    }

    # If using testscheduler, there is no predictable beginning/end line for each test
    # (e.g. from `make check') unless we request --verbose mode, so do that
    if ($qt_tests_testscheduler) {
        push @testrunner_args, '--verbose';
    }

    # We cannot handle passing arguments with spaces into `make TESTRUNNER...',
    # so detect and abort right now if that's the case.
    #
    # Handling this properly by quoting the arguments is really quite difficult
    # (it depends on exactly which shell is going to be invoked by make, which may
    # be affected by the value of the PATH environment variable when make is run, etc...),
    # so we will not do it unless it becomes necessary.
    #
    if (any { /\s/ } @testrunner_args) {
        $self->fatal_error(
            "Some arguments to testrunner contain spaces, which is currently not supported.\n"
           ."Try removing spaces from build / log paths, if there are any.\n"
           .'testrunner arguments: '.Dumper(\@testrunner_args)."\n"
        );
    }

    return @testrunner_args;
}

sub run_autotests
{
    my ($self) = @_;

    return if (!$self->{ 'qt.tests.enabled' });

    my $doing = $self->doing( 'running the autotests' );

    my $qt_gitmodule_build_dir = $self->{ 'qt.gitmodule.build.dir' };
    my $qt_tests_dir = $self->{ 'qt.tests.dir' };

    # Add this module's `bin' directory to PATH.
    # FIXME: verify if this is really needed (should each module's tools build directly
    # into the prefix `bin' ?)
    local %ENV = %ENV;
    Env::Path->PATH->Prepend( canonpath catfile( $qt_gitmodule_build_dir, 'bin' ) );

    # In qt4, we need to set QTDIR to run some autotests like 'tst_bic',
    # 'tst_symbols', etc
    if ($self->{ 'qt.gitmodule' } eq 'qt') {
        $ENV{ QTDIR } = $qt_gitmodule_build_dir; ## no critic
    }

    # In qt5, all tests are expected to be correctly set up in top-level .pro files, so they
    # do not need an explicit added compile step.
    # In qt4, this is not the case, so they need to be compiled separately.
    # By using qt.tests.dir one can change the test dir to be tests/auto in qt5 also.
    return $self->_run_autotests_impl(
        tests_dir            =>  ($self->{ 'qt.gitmodule' } ne 'qt')
                                 ? catfile( $qt_gitmodule_build_dir, $qt_tests_dir)  # qt5
                                 : catfile( $qt_gitmodule_build_dir, 'tests/auto' ), # qt4
        insignificant_option =>  'qt.tests.insignificant',
        do_compile           =>  ($self->{ 'qt.gitmodule' } ne 'qt')
                                 ? 0                                                 # qt5
                                 : 1,                                                # qt4
    );
}

# Compile and run some qtqa shared autotests.
#
# The $type parameter decides which tests are run;
# essentially, `qmake && make && make check' are run under
# the qtqa/tests/$type directory.
#
# This function may be called multiple times for different types of tests.
#
sub run_qtqa_autotests
{
    my ($self, $type) = @_;

    return if (!$self->{ 'qt.qtqa-tests.enabled' });

    my $qt_gitmodule           = $self->{ 'qt.gitmodule' };
    my $qt_gitmodule_dir       = $self->{ 'qt.gitmodule.dir' };
    my $qt_gitmodule_build_dir = $self->{ 'qt.gitmodule.build.dir' };

    my $doing = $self->doing( "running the qtqa tests on $qt_gitmodule" );

    # path to the qtqa shared autotests.
    my $qtqa_tests_dir = catfile( $FindBin::Bin, qw(.. .. tests), $type );

    # director(ies) of modules we want to test
    my @module_dirs;

    # module itself is always tested
    push @module_dirs, $qt_gitmodule_dir;

    # if there are submodules, all of those are also tested
    {
        local $CWD = $qt_gitmodule_dir;

        my ($testable_modules) = trim $self->exe_qx(
            'git',
            'submodule',
            '--quiet',
            'foreach',
            'echo $path',
        );
        my @testable_modules = split(/\n/, $testable_modules);

        push @module_dirs, map { catfile( $qt_gitmodule_dir, $_ ) } @testable_modules;
    }

    # message is superfluous if only one tested module
    if (@module_dirs > 1) {
        print __PACKAGE__ . ": qtqa $type autotests will be run over modules: @module_dirs\n";
    }

    my $compiled_qtqa_tests = 0;    # whether or not the tests have been compiled

    foreach my $module_dir (@module_dirs) {
        print __PACKAGE__ . ": now running qtqa $type autotests over $module_dir\n";

        # qtqa autotests use this environment variable to locate the sources of the
        # module under test.
        local $ENV{ QT_MODULE_TO_TEST } = $module_dir;

        $self->_run_autotests_impl(
            tests_dir            =>  $qtqa_tests_dir,
            insignificant_option =>  'qt.qtqa-tests.insignificant',

            # Only need to `qmake', `make' the tests the first time.
            do_compile           =>  !$compiled_qtqa_tests,

            # Testscheduler summary is not useful for qtqa tests
            testscheduler_args   =>  [ '--no-summary' ],
        );

        $compiled_qtqa_tests = 1;
    }

    return;
}

sub _run_autotests_impl
{
    my ($self, %args) = @_;

    # global settings
    my $qt_build_dir   = $self->{ 'qt.build.dir' };
    my $qt_install_dir = $self->{ 'qt.install.dir' };
    my $qt_make_install = $self->{ 'qt.make_install' };
    my $make_bin       = $self->{ 'make.bin' };
    my $make_args      = $self->{ 'make.args' };
    my $make_check_bin = $self->{ 'make-check.bin' };
    my $make_check_args = $self->{ 'make-check.args' };
    my $qt_tests_args  = $self->{ 'qt.tests.args' };
    my $qt_tests_testscheduler = $self->{ 'qt.tests.testscheduler' };
    my $qt_tests_testscheduler_args = $self->{ 'qt.tests.testscheduler.args' };

    my $mobile_test_enabled  = $self->{ 'qt.mobile.test.enabled' };
    my $mobile_testrunner    = $self->{ 'qt.mobile.testrunner' };
    my $qt_testargs          = $self->{ 'qt.mobile.testrunner.args' };
    my @mobile_testargs = split(/ /, $qt_testargs);

    # settings for this autotest run
    my $tests_dir            = $args{ tests_dir };
    my $insignificant_option = $args{ insignificant_option };
    my $do_compile           = $args{ do_compile };
    my $insignificant        = $self->{ $insignificant_option };

    # mobile targets
    if ($mobile_test_enabled) {
        # sanity check
        $self->fatal_error( "internal error: $mobile_testrunner does not exist" ) if (! -e $mobile_testrunner);
        # disable building and desktop scheduler
        $do_compile = 0;
        $qt_tests_testscheduler = 0;
    }

    # Add tools from all the modules to PATH.
    # If shadow-build with install enabled, then we need to add install path
    # rather than build path into the PATH.
    local $ENV{ PATH } = $ENV{ PATH };
    local $ENV{ QMAKEPATH } = $ENV{ QMAKEPATH };
    if ($self->{ installed }) {
        # shadow build and installing? need to add install dir into PATH
        Env::Path->PATH->Prepend( canonpath catfile( $qt_install_dir, 'bin' ) );
    }
    elsif ($self->{ 'qt.gitmodule' } eq 'qt') {
        # qt4 case. this is needed to use the right qmake to compile the tests
        Env::Path->PATH->Prepend( canonpath catfile( $qt_build_dir, 'bin' ) );
    }
    else {
        Env::Path->PATH->Prepend( canonpath catfile( $qt_build_dir, 'qtbase', 'bin' ) );

        # If we are expected to install, but we're not installed yet, then
        # make sure qmake can find its mkspecs.
        if ($qt_make_install) {
            Env::Path->QMAKEPATH->Prepend( canonpath catfile( $qt_build_dir, 'qtbase' ) );
        }
    }

    my $run = sub {
        chdir( $tests_dir );

        my @make_args = split(/ /, $make_args);

        if ($do_compile) {
            $self->exe( 'qmake' );
            $self->exe( $make_bin, '-k', @make_args );
        }

        if ($qt_tests_testscheduler) {
            my @testrunner_args = $self->get_testrunner_args( );

            $self->exe(
                $EXECUTABLE_NAME,
                catfile( "$FindBin::Bin/../generic/testplanner.pl" ),
                '--input',
                '.',
                '--output',
                'testplan.txt',
                '--make',
                $make_check_bin,
                '--',
                split(/ /, $qt_tests_args),
            );

            $self->exe(
                $EXECUTABLE_NAME,
                catfile( "$FindBin::Bin/../generic/testscheduler.pl" ),
                '--plan',
                'testplan.txt',
                @{ $args{ testscheduler_args } || []},
                split( m{ }, $qt_tests_testscheduler_args ),
                @testrunner_args,
            );
        } elsif ($mobile_test_enabled) {
            $self->exe(
                $EXECUTABLE_NAME,       # perl
                $mobile_testrunner,        #/full/path/to/<runner>.pl
                @mobile_testargs,
            );
        } else {
            my $testrunner_command = $self->get_testrunner_command( );

            my @make_check_args = split(/ /, $make_check_args);

            $self->exe( $make_check_bin,
                @make_check_args,                   # include args requested by user
                "TESTRUNNER=$testrunner_command --",# use our testrunner script
                "TESTARGS=$qt_tests_args",          # and our test args (may be empty)
                'check',                            # run the autotests :)
            );
        }
    };

    if ($insignificant) {
        eval { $run->() };
        if ($EVAL_ERROR) {
            warn "$EVAL_ERROR\n"
                .qq{This is a warning, not an error, because the `$insignificant_option' option }
                . q{was used.  This means the tests are currently permitted to fail};
        } else {
            print "Note: $insignificant_option is set, but the tests succeeded. "
                 ."This may indicate it is safe to remove $insignificant_option.\n";
        }
    }
    else {
        $run->();
    }

    return;
}

sub run_coverage
{
    my ($self) = @_;

    return if ((!$self->{ 'qt.tests.enabled' }) or (!$self->{ 'qt.coverage.tool' }));

    my $doing = $self->doing( 'gathering coverage data' );

    my $qt_coverage_tool         = $self->{ 'qt.coverage.tool' };
    my $qt_coverage_tests_output = $self->{ 'qt.coverage.tests_output' };
    my $qt_gitmodule             = $self->{ 'qt.gitmodule' };
    my $qt_gitmodule_dir         = $self->{ 'qt.gitmodule.dir' };

    my $coveragerunner = catfile( $FindBin::Bin, '..', 'generic', "coveragerunner_$qt_coverage_tool.pl" );
    $coveragerunner    = canonpath abs_path( $coveragerunner );

    # sanity check
    $self->fatal_error( "internal error: $coveragerunner does not exist" ) if (! -e $coveragerunner);

    my @coverage_runner_args = (
        '--qt-gitmodule-dir',
        $qt_gitmodule_dir,
        '--qt-gitmodule',
        $qt_gitmodule,
        '--qtcoverage-tests-output',
        $qt_coverage_tests_output
    );

    $self->exe(
        $EXECUTABLE_NAME,       # perl
        $coveragerunner,        # coveragerunner_<foo>.pl
        @coverage_runner_args
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
