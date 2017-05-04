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

package QtQA::App::TestRunner::Plugin::testcocoon;
use strict;
use warnings;

use Carp;
use Cwd;
use English qw( -no_match_vars );
use File::Basename;
use File::Copy;
use File::Find::Rule;
use File::Path qw( mkpath );
use File::Spec::Functions;
use Getopt::Long qw(GetOptionsFromArray);
use Readonly;

sub new
{
    my ($class, %args) = @_;

    my $testcocoon_tests_output;
    my $qt_gitmodule_dir;
    my $qt_gitmodule;

    GetOptionsFromArray( $args{ argv },
        'testcocoon-tests-output=s'     =>  \$testcocoon_tests_output,
        'testcocoon-qt-gitmodule-dir=s' =>  \$qt_gitmodule_dir,
        'testcocoon-qt-gitmodule=s'     =>  \$qt_gitmodule,
    ) || pod2usage(1);

    if (!$testcocoon_tests_output) {
        confess "Missing required '--testcocoon-tests-output' option";
    } else {
        my $output_dir = dirname( $testcocoon_tests_output );
        if (! -d $output_dir && ! mkpath( $output_dir )) {
            confess "mkpath $output_dir: $!";
        }
        $args{ testcocoon_tests_output } = $testcocoon_tests_output;
    }

    if ((!$qt_gitmodule_dir) or (! -d $qt_gitmodule_dir)) {
        confess "Invalid or missing required '--testcocoon-qt-gitmodule-dir' option";
    } else {
        $args{ testcocoon_qt_gitmodule_dir } = $qt_gitmodule_dir;
    }

    if (!$qt_gitmodule) {
        confess "Missing required '--testcocoon-qt-gitmodule' option";
    } else {
        $args{ testcocoon_qt_gitmodule } = $qt_gitmodule;
    }

    return bless \%args, $class;
}

sub run_completed
{
    my ($self) = @_;

    my $tests_target  = $self->{ testcocoon_tests_output };
    my $testrunner = $self->{ testrunner };
    my $qt_gitmodule_dir = $self->{ testcocoon_qt_gitmodule_dir };
    my $qt_gitmodule = $self->{ testcocoon_qt_gitmodule };

    my $test_basename = basename(($testrunner->command( ))[0]);
    my $test_dir = getcwd;

    # Get all csmes found under test folder
    my @all_test_csmes = File::Find::Rule->file()->name( '*.csmes' )->in($test_dir);
    @all_test_csmes = map { canonpath($_) } sort(@all_test_csmes);

    # merge all csmes found under the test folder and merge them in a global csmes
    my $test_global_csmes = catfile($test_dir, "${test_basename}_global.csmes");
    foreach my $sub_csmes (@all_test_csmes) {
        if (-e $test_global_csmes) {
            $self->system_call('cmmerge', '--append', "--output=$test_global_csmes", $sub_csmes);
        } else {
           copy($sub_csmes, $test_global_csmes) or confess "copy $sub_csmes: $!";
        }
    }

    my $qt_git_qtbase_dir =
        ($qt_gitmodule eq 'qtbase') ? $qt_gitmodule_dir
        : ($qt_gitmodule eq 'qt5')  ? catfile($qt_gitmodule_dir, 'qtbase')
        :                             catfile($qt_gitmodule_dir, '..', 'qtbase');

    # Get plugins and imports dir
    my $qt_git_qtbase_pluginsdir = catfile($qt_git_qtbase_dir, 'plugins');
    my $qt_git_qtbase_importsdir = catfile($qt_git_qtbase_dir, 'imports');

    if (-e $test_global_csmes) {
        # Merge each plugins and import code database (csmes) in one global database with all plugins/imports
        my @all_pluginsandimport_csmes = File::Find::Rule->file()->name( '*.csmes' )->in($qt_git_qtbase_pluginsdir);
        push @all_pluginsandimport_csmes, File::Find::Rule->file()->name( '*.csmes' )->in($qt_git_qtbase_importsdir);
        @all_pluginsandimport_csmes = map { canonpath($_) } sort(@all_pluginsandimport_csmes);

        foreach my $csmes (@all_pluginsandimport_csmes) {
            $self->system_call('cmmerge', '--append', "--output=$test_global_csmes", $csmes);
        }

        # Get all csexe files found under the test folder (except tools csexe: moc, uic and rcc) and import them
        # FIXME Getting code coverage data for/from the tools. We don't export the tools csexe because tools are using a
        # separately compiled version of some QtBase sources. This means they are incompatible with the tests csmes used here.
        my @all_test_csexe = File::Find::Rule->file()->name( '*.csexe' )->in($test_dir);
        @all_test_csexe = map { canonpath($_) } sort(@all_test_csexe);

        foreach my $sub_csexe (@all_test_csexe) {
            my $csexe_basename;
            $csexe_basename = basename($sub_csexe);
            if (!($csexe_basename =~ m/^(moc|uic|rcc)\.csexe$/)) {
                $self->system_call('cmcsexeimport', "--csmes=$test_global_csmes", "--csexe=$sub_csexe", "--title=tc_$test_basename", '--policy=merge');
                # Delete the csexe to save space.
                unlink($sub_csexe) or confess "unlink $sub_csexe: $!";
            }
        }

        if (-e $tests_target) {
            $self->system_call('cmmerge', '--append', "--output=$tests_target", $test_global_csmes);
        } else {
            copy($test_global_csmes, $tests_target) or confess "copy $test_global_csmes: $!";
        }

        # Delete the global csmes to save space
        unlink($test_global_csmes) or confess "unlink $test_global_csmes: $!";

    } else {
        $testrunner->print_info( "warning: $test_basename csmes file is missing\n" );
    }

    return;
}

sub system_call
{
    my ($self, @command) = @_;
    print "+ @command\n";
    (!system(@command)) or (confess "@command exited with error $?");

    return;
}

=head1 NAME

QtQA::App::TestRunner::Plugin::testcocoon - gather code coverage information of all tests in a single database.

=head1 SYNOPSIS

  # With this plugin
  # $ ./testrunner --plugin testcocoon --testcocoon-tests-output "$HOME/all_tests.cmses" --testcocoon-qt-gitmodule-dir "$HOME/git/qt5/qtbase" --testcocoon-qt-gitmodule qtbase -- ./tst_mytest
  # $HOME/all-tests.csmes will be created and will gather all code coverage information collected from
  # the tests after they have been executed. All the plugins csmes are merge with each test csmes.

=head1 DESCRIPTION

This plugin provides a simple mechanism to import each test execution report (csexe) into
its source database (csmes). This plugin purpose is to create a global database (csmes)
gathering all those tests source databases.

=head1 OPTIONS

=over

=item B<--testcocoon-tests-output> <fullpath>

Required. Full path to the global tests database to create. Must contain a full path to a csmes file.
(First time, the file should not exist to avoid data corruption)

=item B<--testcocoon-qt-gitmodule-dir> <directory>

Required. the git dir is used to retrieve the plugins csmes and then collect the plugin execution data.

=item B<--testcocoon-qt-gitmodule> <directory>

Required. Name of the git module (e.g. 'qtbase')

=back

=head1 CAVEATS

Requires tests and tested code to be built with testcocoon configure option enabled.

=cut

1;

