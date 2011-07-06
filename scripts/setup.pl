#!/usr/bin/env perl
use strict;
use warnings;

=head1 NAME

setup.pl - set up environment for Qt QA scripts

=head1 SYNOPSIS

setup.pl [--install] [--prefix <prefix>]

Attempt to ensure all prerequisites for this repo are installed.

If run with no arguments, this script will check if you have all necessary
perl and python modules.

The behavior can be customized with the following options:

=over

=item --install

Attempt to automatically install the missing perl and python modules.

For perl, this will attempt to use cpanminus to install into $HOME/perl5
(or the prefix given with the `--prefix' option).

For python, this requires that your `pip' command with no further
options is able to successfully install modules into the current python
module path.  The recommended way to accomplish this is to have a
python virtualenv set up and activated in the current environment.

=item  --prefix <prefix>

Customize the prefix used for perl installation.
Defaults to $HOME/perl5 .

Only makes sense combined with `--install'.

This does not affect the python installation, which will always use
the settings of the first `pip' in $PATH.  To customize the python
prefix, activate a virtualenv before calling this script.

=back

=head1 EXAMPLE

The recommend way to run the script is:

C<./setup.pl --install>

This will attempt to automatically install all needed perl and python
modules.

For python, it will automatically install all needed modules into
whatever environment is used by the first `pip' in PATH (which ideally
is a virtualenv you have set up and activated at, for example,
`$HOME/python26').

For perl, it will automatically install cpanminus (a tool for installing
modules from CPAN) and all required perl modules into `$HOME/perl5'.

If you do it this way, you should ensure your environment is set up to use
the perl modules under `$HOME/perl5'.  The recommended way to do this is to
have this shell fragment

C<eval $(perl -Mlocal::lib)>

...in some script which is sourced in your environment at login time.
See `perldoc L<local::lib>' for more details.

=cut

#==============================================================================

package QtQASetup;

use English               qw( -no_match_vars      );
use File::Spec::Functions qw( catfile             );
use File::Temp            qw( tempfile            );
use Getopt::Long          qw( GetOptionsFromArray );
use LWP::UserAgent        qw(                     );
use Pod::Usage            qw( pod2usage           );

# URL from which cpanminus can be downloaded.
# Note that http://cpanmin.us, as recommended by the docs, is not a good idea;
# it redirects to an https:// site and this requires more modules to be
# installed to handle the SSL.
my $HTTP_CPANMINUS =
    'http://cpansearch.perl.org/src/MIYAGAWA/App-cpanminus-1.4005/bin/cpanm';

# Null device understood by system shell redirection
my $DEVNULL = ($OSNAME =~ m{win32}i) ? 'NUL'
            :                          '/dev/null';

#====================== perl stuff ============================================

# Returns a list of all CPAN modules needed (including those which
# are already installed).
#
# The returned values are suitable for use both as module names within
# a perl script (e.g. use Some::Module), and as module names for use with
# the cpan command (e.g. cpan -D Some::Module).
#
sub all_required_cpan_modules
{
    return qw(
        BSD::Resource
        Capture::Tiny
        Env::Path
        File::Slurp
        IO::CaptureOutput
        List::MoreUtils
        Perl::Critic
        Proc::Reliable
        Readonly
        Test::Exception
        Test::Exit
        Test::More
        Test::Perl::Critic
        Text::Diff
        Text::Trim
        Tie::Sysctl
        autodie
    );
}

# Returns the subset of modules from `all_required_cpan_modules'
# which are not currently installed.
#
# This function invokes perl once per module, and attempts to use each
# module to determine if it is available in the current environment.
# Therefore it is crucial that modules must not have significant side effects
# merely from being used.
#
# Parameters:
#  an optional hashref to be passed to run_module_test
#
sub missing_required_cpan_modules
{
    my ($self, $arg_ref) = @_;

    my @all = $self->all_required_cpan_modules;

    my @need_install = ();

    # We're deliberately running a new `perl' for each module instead of
    # just doing the `require' ourselves.
    #
    # The reason is that attempting to `require' a module may have undesireable
    # side effects. In particular, some modules will refuse to be `require'd
    # more than once, which breaks our case where we want to do:
    #
    #  - attempt to load a module
    #  - if it fails:
    #    - install the module
    #    - attempt to load it again
    #

    foreach my $module (@all) {
        print "$module - ";
        my $cmd = "perl -m$module -e1";

        if (!$self->run_module_test( $cmd, $arg_ref )) {
            push @need_install, $module;
        }
    }

    return @need_install;
}

# Install cpanminus to the given $prefix, or die.
#
# This will result in a cpanm command being made available at $prefix/bin/cpanm.
#
# This function fetches cpanminus from the Internet and hence needs an
# Internet connection.
#
# Parameters:
#
#  $prefix  -   the prefix under which cpanminus should be installed
#               (e.g. `$HOME/perl5')
#
sub install_cpanminus
{
    my ($self, $prefix) = @_;

    # We want a simple way to download files from http, which will work on both
    # win and unix, without needing any non-core perl modules.  There seems to
    # be no such thing.
    # However, LWP seems fairly safe to use - although technically not a core module,
    # it is installed by default for ActivePerl and probably most Linux distros.

    my ($tempfh, $tempfilename) = tempfile( 'qtqa-cpanminus.XXXXXX', TMPDIR => 1 );

    my $response = LWP::UserAgent->new( )->get( $HTTP_CPANMINUS );

    die "get $HTTP_CPANMINUS: ".$response->as_string if (!$response->is_success);

    $tempfh->print( $response->decoded_content );
    close( $tempfh ) || die "close $tempfilename: $OS_ERROR";

    my @cmd = (
        'perl',
        $tempfilename,    # contains a copy of the cpanm bootstrap script
        '--local-lib',    # options from this line onwards are cpanm options, not perl options;
        $prefix,          # install to the given prefix
        'App::cpanminus', # name of the module to install is App::cpanminus
    );

    print "+ @cmd\n";
    if (0 != system(@cmd)) {
        die "Could not install cpanminus; install command exited with status $?";
    }
}

# Ask cpan to install the given @modules.
#
# This function will run the cpan command only once.  It does not attempt to
# be robust in case of failure.
#
# Parameters:
#
#  @modules -   list of modules to install (e.g. qw(Date::Calc SOAP::Lite))
#
# Returns the exit status of the cpan command.
#
sub run_cpan
{
    my ($self, @modules) = @_;

    my $prefix = $self->{locallib};
    my @cpan = (
        "$prefix/bin/cpanm",

        # Install into the local prefix
        "--local-lib", $prefix,

        # Skip autotests.
        # If autotests fail, there's not really any practical way for
        # us to resolve the issue, so there is little point to running
        # the tests.  We merely hope that the quality is not so bad as
        # to cause our scripts to break.  This could be revisited with
        # a more complex solution in the future, e.g. trying to install
        # older versions of modules which fail tests.
        "--notest",
    );

    unless (-e $cpan[0]) {
        print "I need cpanminus and it's not installed yet; installing it myself :)\n";
        $self->install_cpanminus($prefix);
    }

    print "+ @cpan @modules\n";
    return system(@cpan, @modules);
}

# Import the local::lib module into the current process or exit.
#
# Importing local::lib ensure the selected prefix exists and is
# available for use by the current process and all subprocesses.
#
# This is equivalent to `use local::lib', except that it will give
# a helpful failure message if local::lib is not available.
#
sub do_local_lib
{
    my ($self) = @_;

    my $prefix = $self->{locallib};
    eval { require local::lib; local::lib->import($prefix) };
    if (!$EVAL_ERROR) {
        return;
    }

    print STDERR
        "$EVAL_ERROR\n\nI need you to manually install the local::lib module "
       ."before I can proceed.  This module allows me to easily set up a perl "
       ."prefix under $prefix.\n";

    # This hint may be helpful to some :)
    if (-e "/etc/debian_version") {
        print STDERR
            "\nOn Debian and Ubuntu, this module is available from the "
           ."`liblocal-lib-perl' package.\n";
    }

    exit 1;
}

# Try hard to ensure all CPAN modules returned from all_required_cpan_modules
# are installed.  The cpan command may be run several times.
#
# Returns 1 on success, 0 on failure.
#
sub ensure_complete_cpan
{
    my $self = shift;

    # We expect everything under a local::lib
    $self->do_local_lib;

    return $self->try_hard_to_install(
        name        =>  "CPAN",
        need_sub    =>  \&missing_required_cpan_modules,
        install_sub =>  \&run_cpan,
    );
}

#====================== python stuff ==========================================

# Returns a list of all python modules needed (including those which
# are already installed).
#
# The returned values are suitable for use both as module names within
# a python script (e.g. import some_module), and as module names for use
# with the cpan command (e.g. pip install some_module).
#
sub all_required_python_modules
{
    # Note that there is currently nothing within the repo which actually requires these
    # modules.  They are kept here in anticipation of using python within our scripts,
    # so that the python module installation code is not allowed to bitrot.
    return qw(
        minimock
        nose
    );
}

# Returns the subset of modules from `all_required_python_modules'
# which are not currently installed.
#
# This function invokes python once per module, and attempts to import each
# module to determine if it is available in the current environment.
# Therefore it is crucial that modules must not have significant side effects
# merely from being imported.
#
# Parameters:
#  an optional hashref to be passed to run_module_test
#
sub missing_required_python_modules
{
    my ($self, $arg_ref) = @_;

    my @all = $self->all_required_python_modules;

    my @need_install = ();

    foreach my $module (@all) {
        print "$module - ";
        my $cmd = "python -c \"import $module\"";

        if (!$self->run_module_test( $cmd, $arg_ref )) {
            push @need_install, $module;
        }
    }

    return @need_install;
}

# Ask pip to install the given @modules.
#
# Unlike for cpan, this function's behavior can't be customized.
# The first pip in PATH is always used.
# This is intentional, as the recommended way to use this script is to
# first activate a virtualenv, which should place an appropriate pip in PATH.
#
# This function will run the pip command only once.  It does not attempt to
# be robust in case of failure.
#
# Parameters:
#
#  @modules -   list of modules to install (e.g. qw(minimock nose))
#
# Returns the exit status of the pip command.
#
sub run_pip
{
    my ($self, @modules) = @_;

    my @cmd = ('pip', 'install', @modules);
    print "+ @cmd\n";

    return system(@cmd);
}

# Try hard to ensure all python modules returned from all_required_python_modules
# are installed.  The pip command may be run several times.
#
# Returns 1 on success, 0 on failure.
#
sub ensure_complete_python
{
    my $self = shift;

    return $self->try_hard_to_install(
        name        =>  "python",
        need_sub    =>  \&missing_required_python_modules,
        install_sub =>  \&run_pip,
    );
}

#====================== generic stuff =========================================

# Create a QtQASetup object.
#
# Parameters:
#
#   @args   -   command-line parameters, e.g. from $ARGV
#               (see perldoc for documentation)
#
sub new
{
    my ($class, @args) = @_;

    my $home = ($OSNAME =~ m{win32}i) ? catfile($ENV{HOMEDRIVE}, $ENV{HOMEPATH})
             :                          $ENV{HOME};

    my %self = (
        install     =>  0,
        locallib    =>  catfile($home, 'perl5'),
    );

    GetOptionsFromArray(\@args,
        "install"     =>  \$self{install},
        "prefix=s"    =>  \$self{locallib},
        "help"        =>  sub { pod2usage(2) },
    ) || pod2usage(1);

    bless \%self, $class;
    return \%self;
}

# Run the setup procedure, installing all needed python/perl modules.
#
# Returns on success, and exits with a non-zero exit code on failure.
#
sub run
{
    my $self = shift;

    # Close STDIN to ensure that all modules and subprocesses do not try to do interactive
    # prompts, etc.
    #
    # Without this, it is possible that certain modules will attempt to read from STDIN
    # and block indefinitely (even though we have not asked pip, cpan to run in interactive
    # mode).
    close( STDIN ) || die "close STDIN: $OS_ERROR";

    my $ok = 1;

    print "\nChecking python modules ...\n";
    $ok = $self->ensure_complete_python && $ok;

    print "\nChecking perl modules ...\n";
    $ok = $self->ensure_complete_cpan && $ok;

    if (!$ok) {
        exit 1;
    }
}

# Try really hard to install some python or perl modules.
#
# Takes one hash, with these named parameters:
#
#  name:        user-friendly name of the type of modules we're
#               installing, e.g. "perl", "python"
#
#  need_sub:    reference to a sub returning a list of all modules
#               which still need to be installed
#
#  install_sub: reference to a sub which takes as input a list of
#               modules, and attempts to install them
#
# Example:
#
#    # Install all python modules, via pip
#    $self->try_hard_to_install(
#        name        =>  "python",
#        need_sub    =>  \&missing_required_python_modules,
#        install_sub =>  \&run_pip,
#    );
#
# This function will repeatedly call need_sub and install_sub to
# calculate what needs to be installed, and to install them.
# It will stop when need_sub returns an empty list or when no
# progress can be made.
#
# This function is necessary because perl and python modules may,
# on occasion, be missing some vital dependency information which
# prevents them from installing correctly on the first attempt.
# As a desireable side effect, it also helps this script to be
# robust in the face of transient network failures.
#
# Returns 1 on success, 0 on failure.
#
sub try_hard_to_install
{
    my ($self, %args) = @_;

    my $name = $args{name};

    my @need = $args{need_sub}($self, { quiet => 1 });

    unless (@need) {
        print "\nIt looks like your $name setup is complete :)\n";
        return 1;
    }

    print "\nYou are missing some needed $name modules.\n";

    unless ($self->{install}) {
        print "I can install them if you use the `--install' option.\n";
        return 0;
    }

    while (1) {
        my $exitcode = $args{install_sub}($self, @need);
        if ($exitcode == 0) {
            last;
        }

        print "\n\nInstallation failed :(\n";
        print "Checking if any progress was made...\n\n";

        my %newneed = map { $_ => 1 } $args{need_sub}($self, { quiet => 1 });
        my @installed = grep { !$newneed{$_} } @need;

        if (@installed) {
            print "\nAlthough installation failed, it looks like some "
                ."progress was made; successfully installed these:\n\n  "
                .join(" ", @installed)."\n\n";

            @need = keys %newneed;

            if (@need) {
                print "I'll try again to see if I can get further.\n";
            }
            else {
                print "Actually, there's nothing left to install!\n"
                    ."You might want to check why installation claimed "
                    ."to fail. Regardless, I'm continuing.\n";
                last;
            }
        }
        else {
            print "\nNope, looks like no progress was made.  See errors:\n";
            $args{need_sub}($self, { quiet => 0 });
            print "\nGiving up :(\n";
            return 0;
        }
    }

    @need = $args{need_sub}($self, { quiet => 0 });
    if (@need) {
        print "Installation completed successfully, but you still seem to "
             ."be missing some $name modules: @need\n";
        return 0;
    }

    return 1;
}

# Run a module test command, and return true if it succeeds.
#
# Parameters:
#   $cmd     -  the command to run; will be run via shell, so be careful with quotes
#   $arg_ref -  hashref with the following keys:
#     quiet  => if true, hide stderr from the command
#
sub run_module_test
{
    my ($self, $cmd, $arg_ref) = @_;

    my $quiet = $arg_ref->{ quiet };

    if ($quiet) {
        $cmd .= " 2>$DEVNULL";
    }

    if (0 == system($cmd)) {
        print "OK\n";
        return 1;
    }

    # if we hid errors, then we'll print a summary;
    # otherwise, we expect that the module test command printed something.
    if ($quiet) {
        print "NOT OK\n";
    }

    return 0;
}

#==============================================================================

QtQASetup->new(@ARGV)->run if (!caller);
1;
