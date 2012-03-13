#############################################################################
##
## Copyright (C) 2012 Nokia Corporation and/or its subsidiary(-ies).
## Contact: http://www.qt-project.org/
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
##
## $QT_END_LICENSE$
##
#############################################################################

package QtQA::QMake::Project;
use strict;
use warnings;

use Carp;
use English qw(-no_match_vars);
use File::chdir;
use File::Basename;
use File::Temp;
use Getopt::Long qw(GetOptions);
use IO::File;
use Readonly;
use ReleaseAction qw(on_release);
use List::MoreUtils qw(apply);
use Text::ParseWords;

use QtQA::QMake::Project::LazyValue;

Readonly my $WINDOWS => ($OSNAME =~ m{win32}i);

# Magic string denoting we've deliberately exited qmake early
Readonly my $MAGIC_QMAKE_EXIT_STRING => __PACKAGE__.':EXITING';

sub new
{
    my ($class, $makefile) = @_;

    my $self = bless {
        _die_on_error => 1, # whether to die when an error occurs
        _qmake_count => 0,  # number of times qmake has been run (for testing)
    }, $class;

    if ($makefile) {
        $self->set_makefile( $makefile );
    }

    $self->set_make( $self->_default_make( ) );

    return $self;
}

sub set_makefile
{
    my ($self, $makefile) = @_;

    $self->{ _makefile } = $makefile;

    # Makefile changed, so everything needs to be resolved again.
    $self->{ _resolved } = {};

    return;
}

sub makefile
{
    my ($self) = @_;
    return $self->{ _makefile };
}

sub set_make
{
    my ($self, $make) = @_;

    $self->{ _make } = $make;

    return;
}

sub make
{
    my ($self) = @_;

    return $self->{ _make };
}

# Returns a reasonable default make command based on the platform.
sub _default_make
{
    my ($self) = @_;

    if ($WINDOWS) {
        return 'nmake';
    }

    return 'make';
}

sub die_on_error
{
    my ($self) = @_;

    return $self->{ _die_on_error };
}

sub set_die_on_error
{
    my ($self, $value) = @_;

    $self->{ _die_on_error } = $value;
    return;
}

sub _prepare_variable
{
    my ($self, @variable) = @_;

    foreach my $variable (@variable) {
        $self->{ _to_resolve }{ variable }{ $variable } = 1;
    }

    return;
}

sub _prepare_test
{
    my ($self, @test) = @_;

    foreach my $test (@test) {
        $self->{ _to_resolve }{ test }{ $test } = 1;
    }

    return;
}

sub _qx_or_croak
{
    my ($self, $cmd) = @_;

    my $output = qx($cmd);
    if ($? != 0) {
        # If $output contains this magic, we deliberately exited, and the status can
        # be ignored.
        if ($output !~ m/\Q$MAGIC_QMAKE_EXIT_STRING\E/) {
            croak __PACKAGE__.": command `$cmd' exited with status $?, output follows:\n$output\n";
        }
        return $output;
    }

    return $output;
}

# Returns a copy of %ENV with any make-related environment variables removed.
sub _make_cleaned_env
{
    my ($self) = @_;

    my %out = %ENV;

    delete @out{qw(
        MAKEFLAGS
        MAKELEVEL
        MFLAGS
    )};

    return %out;
}

# Returns the qmake command (as a single string) used to generate the given makefile.
# Croaks on error.
sub _discover_qmake_command
{
    my ($self, %args) = @_;

    my $make = $self->make( );
    my $makefile = $args{ makefile };

    # Make sure we do not accidentally inherit any environment from
    # some calling make (e.g. if we are invoked via `make check')
    local %ENV = $self->_make_cleaned_env( );

    my $cmd = qq{"$make" -f "$makefile" -n qmake 2>&1};
    my $output = $self->_qx_or_croak( $cmd );
    my @lines = reverse split( /\n/, $output );

    my $out;
    while (my $line = shift @lines) {
        $line or next;
        # last line should be the qmake command
        if ($line =~ m{qmake}i) {
            $out = $line;
            chomp $out;
            last;
        }
    }

    if (!$out) {
        croak __PACKAGE__.": could not figure out qmake command used to generate $makefile\n"
             ."Output from command ($cmd):\n$output\n";
    }

    return $out;
}

# Given a qmake $command line (single string containing both command and args),
# parses it and returns a hashref with the following:
#
#   qmake        => path to the qmake binary
#   makefile     => path to the makefile
#   projectfiles => arrayref, paths to the project (.pro) file(s)
#   args         => arrayref, all args not covered by any of the above
#
sub _parse_qmake_command
{
    my ($self, $command) = @_;

    my $qmake;
    my $makefile;
    my @projectfiles;
    my @args;

    # Getopt callbacks to accept a known qmake option onto @args
    my $sub_accept_option_with_value = sub {
        # Getopt already removes the -, we need to put it back
        my ($option, $value) = @_;
        push @args, "-$option", "$value";
    };
    my $sub_accept_option_without_value = sub {
        my ($option) = @_;
        push @args, "-$option";
    };

    # Getopt callback to accept an unknown qmake argument.
    # This includes determining whether the argument should be handled as a
    # .pro file; the logic for this must match qmake's own logic in option.cpp.
    my $sub_accept_nonoption = sub {
        my ($arg) = @_;

        if ($arg =~ m{=}) {
            # Arg containing '=' => it is a user variable assignment.
            # Nothing special to be done.
            push @args, $arg;
        }
        elsif ($arg =~ m{^-}) {
            # Arg starts with '-' => it is probably a qmake argument we haven't
            # handled.  For example, a new qmake argument added after this
            # script was created.  In this case, our code needs to be updated
            # to handle it safely, so we'll warn about it, then keep going.
            warn __PACKAGE__ . ": in ($command), the meaning of $arg is unknown.\n";
            push @args, $arg;
        }
        else {
            # Otherwise, it is a .pro file.
            push @projectfiles, $arg;
        }
    };

    Getopt::Long::Configure( 'permute', 'pass_through' );

    {
        local @ARGV = $self->_split_command_to_words( $command );

        # The first element is the qmake binary itself
        $qmake = shift @ARGV;

        GetOptions(
            # All of these options are directly accepted into @args with no
            # special behavior
            map( { $_ => $sub_accept_option_without_value } qw(
                project
                makefile
                Wnone
                Wall
                Wparser
                Wlogic
                Wdeprecated
                d
                help
                v
                after
                norecursive
                recursive
                nocache
                nodepend
                nomoc
                nopwd
            )),
            map( { $_ => $sub_accept_option_with_value } qw(
                unset=s
                query=s
                cache=s
                spec=s
                t=s
                tp=s
            )),

            # "-o <Makefile>" tells us which makefile to use
            'o=s' => sub { (undef, $makefile) = @_ },

            # anything else should be either a variable assignment or
            # a .pro file, pass it to our function for handling these
            '<>'  => $sub_accept_nonoption,
        ) || croak __PACKAGE__.": command ($command) could not be parsed";
    }

    return {
        qmake => $qmake,
        makefile => $makefile,
        projectfiles => \@projectfiles,
        args => \@args,
    };
}

# Given a single string representing a qmake command, split it into
# a list of arguments as qmake's own main() would receive
sub _split_command_to_words
{
    my ($self, $cmd) = @_;

    if ($WINDOWS) {
        # In theory, we should be using CommandLineToArgvW here.
        # But do we really need to?  It seems quite annoying to use that
        # from within perl (e.g. requires Inline::C or Win32::API).
        #
        # From reading the qmake sources, where the "qmake:" target is
        # written, it appears that the command-line is simple enough that
        # this will never actually matter.  Basically, the only special
        # construct is if a path contains spaces, in which case double
        # quotes are used around that path.
        #
        # Therefore, the Windows command-line handling is compatible
        # with the Unix command-line handling, except that \ does not
        # have a special meaning (so we have to escape it to keep them
        # as-is).
        $cmd =~ s{\\}{\\\\}g;
    }

    return Text::ParseWords::shellwords( $cmd );
}

sub _resolve
{
    my ($self) = @_;

    eval {
        $self->_resolve_impl( );
    };
    if ($@) {
        my $error = $@;
        # Make sure the error visibly comes from us
        my $pkg = __PACKAGE__;
        if ($error !~ m{^\Q$pkg\E: }) {
            $error = "$pkg: $error";
        }

        if ($self->{ _die_on_error }) {
            croak $error;
        }
        carp $error;
    }

    return;
}

sub _resolve_impl
{
    my ($self) = @_;

    my $makefile = $self->makefile( ) || croak __PACKAGE__.': no makefile set';
    local $CWD = dirname( $makefile );
    $makefile = basename( $makefile );

    my $to_resolve = delete $self->{ _to_resolve };
    if (!$to_resolve) {
        return $self->{ _resolved };
    }

    my $original_qmake_command = $self->_discover_qmake_command( makefile => $makefile );
    my $parsed_qmake_command = $self->_parse_qmake_command( $original_qmake_command );

    # We must have exactly one makefile and one .pro file to proceed
    my $croak_command_error = sub {
        croak __PACKAGE__.": in ($original_qmake_command), @_";
    };

    my $parsed_makefile = $parsed_qmake_command->{ makefile }
        || $croak_command_error->( 'the output makefile could not be determined' );
    my @projectfiles = @{$parsed_qmake_command->{ projectfiles }};
    if (@projectfiles == 0) {
        $croak_command_error->( 'the input .pro file could not be determined' );
    }
    if (@projectfiles > 1) {
        $croak_command_error->( 'this is an unusual, unsupported qmake command' );
    }
    my ($projectfile) = @projectfiles;

    # We're ready to run our qmake.
    #
    # We need to rewrite the input, and we don't care about the output, so we use
    # temporary files for both of these.
    #
    # Note that the temporary files must be in the same directory as the real input/output
    # files, because this significantly affects the behavior of qmake (e.g. values of $$PWD,
    # $$_PRO_FILE_PWD_)
    my $pkg_safe = __PACKAGE__;
    $pkg_safe =~ s{[^a-zA-Z0-9]}{_}g;

    my $temp_makefile = File::Temp->new(
        TEMPLATE => "${pkg_safe}_Makefile.XXXXXX",
        DIR => dirname( $parsed_makefile ),
        UNLINK => 1,
    );
    # qmake may silently create various other makefiles behind our back (e.g. Debug, Release
    # makefiles), so we have to arrange to delete those too.
    my $delete_other_makefiles = $self->_delete_files_on_destroy( "$temp_makefile.*" );

    my $temp_projectfile = File::Temp->new(
        TEMPLATE => "${pkg_safe}_XXXXXX",
        SUFFIX => '.pro',
        DIR => dirname( $projectfile ),
        UNLINK => 1,
    );

    my $temp_qmakefeatures_dir = File::Temp->newdir(
        "${pkg_safe}_XXXXXX",
        TMPDIR => 1,
        CLEANUP => 1,
    );

    local $ENV{ QMAKEFEATURES } = "$temp_qmakefeatures_dir"
        . ($ENV{ QMAKEFEATURES }
          ? ':'.$ENV{ QMAKEFEATURES }
          : '')
    ;

    $self->_write_modified_pro_prf(
        input_filename => $projectfile,
        output_pro => $temp_projectfile,
        output_qmakefeatures => $temp_qmakefeatures_dir,
        to_resolve => $to_resolve,
    );

    # Special case: default value of TARGET is defined by the .pro file name.
    # We changed the .pro file name, but we can keep the old target by
    # passing it on the command-line.
    my $initial_target = fileparse( $projectfile, qr{\..+\z} );

    # If it has a space, it needs to be double-quoted (i.e. quoted in shell,
    # and also quoted in qmake)
    if ($initial_target =~ m{ }) {
        $initial_target = qq{"$initial_target"};
    }

    my $qmake_command = $self->_shquote(
        $parsed_qmake_command->{ qmake },
        '-o',
        $temp_makefile,
        "TARGET=$initial_target",
        $temp_projectfile,
        @{$parsed_qmake_command->{ args }},
    );
    my $qmake_output = $self->_qx_or_croak( "$qmake_command 2>&1" );

    # _parse_qmake_output merges with current _resolved
    $self->_parse_qmake_output( $qmake_output );

    ++$self->{ _qmake_count };

    return $self->{ _resolved };
}

# Returns a handle which, when it goes out of scope, will delete
# all the files matching $glob.
sub _delete_files_on_destroy
{
    my ($self, $glob) = @_;

    return on_release {
        my @files = glob( $glob );
        return unless @files;

        if (unlink( @files ) != @files) {
            warn __PACKAGE__.': failed to remove some of ('
                .join(', ', @files)
                ."): $!";
        }
    };
}

sub _write_modified_pro_prf
{
    my ($self, %args) = @_;

    my $input_filename = $args{ input_filename };
    my $output_pro = $args{ output_pro };
    my $output_qmakefeatures = $args{ output_qmakefeatures };
    my $to_resolve = $args{ to_resolve };
    my $pkg = __PACKAGE__;

    my $prf_basename = '_qtqa_qmake_project_magic';
    my $prf_name = "$output_qmakefeatures/$prf_basename.prf";

    my $input_fh = IO::File->new( $input_filename, '<' )
        || croak "$pkg: open $input_filename for read: $!";
    my $prf_fh = IO::File->new( $prf_name, '>' )
        || croak "$pkg: open $prf_name for write: $!";

    # Copy the input .pro file unmodified ...
    while (my $line = <$input_fh>) {
        $output_pro->print( $line );
    }

    # Then arrange our .prf to be loaded.
    # CONFIG are loaded from right-to-left, so we put ourself at
    # the beginning to be loaded last.
    $output_pro->printflush( qq|\n\nCONFIG=$prf_basename \$\$CONFIG\n| );

    # And write all code to resolve the desired values to our prf.
    # Set PWD back to the value from the .pro file, to hide that we're
    # in a temporary .prf
    $prf_fh->print( qq|PWD="\$\$_PRO_FILE_PWD_"\n| );
    $prf_fh->print( qq|message("${pkg}::BEGIN")\n| );

    # The name of a qmake variable which we can safely use without fear of colliding
    # with any real qmake variables.
    my $x = $pkg;
    $x =~ s{[^a-zA-Z0-9]}{_}g;

    # For each variable we've been asked to resolve, make qmake output lines like:
    #
    #   QtQA::QMake::Project::variable:CONFIG:val1
    #   QtQA::QMake::Project::variable:CONFIG:val2
    #   ...etc
    #
    # Most qmake variables are lists; in fact, all "normal" qmake variables
    # are lists, but a few special substitutions (e.g. _PRO_FILE_PWD_) use
    # special code.  We always try with "for" first to get proper lists,
    # then fall back to a plain message otherwise.
    #
    foreach my $v (keys %{ $to_resolve->{ variable } || {} }) {
        $prf_fh->print( <<"END_QMAKE" );

unset(found_$x)
for($x,$v) {
    message("${pkg}::variable:$v:\$\$$x")               # normal variable (list)
    found_$x=1
}
isEmpty(found_$x):message("${pkg}::variable:$v:\$\$$v") # special variable

END_QMAKE

    }

    # For each test we've been asked to resolve, make qmake output lines like:
    #
    #   QtQA::QMake::Project::test:EXPR1:1
    #   QtQA::QMake::Project::test:EXPR2:0
    #   ...etc
    #
    foreach my $test (keys %{ $to_resolve->{ test } || {} }) {
        $prf_fh->print(
            qq|$x=0\n$test:$x=1\nmessage("${pkg}::test:$test:\$\$$x")\n|
        );
    }

    $prf_fh->printflush( qq|\nunset($x)\nmessage("${pkg}::END")\n| );

    # We've output everything we need.
    # Kill qmake, to avoid wasting time creating the Makefile.
    # In a basic benchmark (on Linux), this seems to save ~10-15% of runtime.
    $prf_fh->printflush( qq|error($MAGIC_QMAKE_EXIT_STRING)\n| );

    return;
}

sub _parse_qmake_output
{
    my ($self, $output) = @_;

    my $pkg = quotemeta( __PACKAGE__ );
    my $resolved = {
        variable => {},
        test => {},
    };

    my @lines = split( /\n/, $output );
    my $parsing = 0;
    foreach my $line (@lines) {
        # We only parse between our BEGIN and END blocks, just in case something
        # somewhere else is outputting lines which could confuse us.
        if ($line =~ m/\b${pkg}::BEGIN/) {
            $parsing = 1;
        }
        elsif ($line =~ m/\b${pkg}::END/) {
            $parsing = 0;
            last;
        }
        next unless $parsing;

        if ($line =~ m/\b${pkg}::variable:([^:]+):(.+)\z/) {
            push @{ $resolved->{ variable }{ $1 } }, $2;
        }
        elsif ($line =~ m/\b${pkg}::test:([^:]+):(.+)\z/) {
            $resolved->{ test }{ $1 } = $2;
        }
    }

    # Now merge what we resolved this time with what we resolved previously
    my %resolved_variable = %{ $resolved->{ variable } };
    my %resolved_test = %{ $resolved->{ test } };
    $self->{ _resolved }{ variable } = {(
        %{ $self->{ _resolved }{ variable } || {} },
        %resolved_variable,
    )};
    $self->{ _resolved }{ test } = {(
        %{ $self->{ _resolved }{ test } || {} },
        %resolved_test,
    )};

    return;
}

# Given an arguments list, returns a single string representing that command in a shell.
# This is far from complete, it only needs to work for all the qmake commands we're likely
# to run, in sh and cmd.
sub _shquote
{
    my ($self, @command) = @_;

    # [ q{"Hello", world!}, q{nice day today} ] => q{"\"Hello\", world!" "nice day today"}

    @command = apply { s{"}{\\"}g } @command;
    @command = map { qq{"$_"} } @command;

    return join(' ', @command);
}

sub values  ## no critic (Subroutines::ProhibitBuiltinHomonyms)
            #  Yes, there is a builtin values(), but we are trying to follow the
            #  API of the QMakeProject class in qmake/project.cpp, and this should
            #  be harmless if always invoked using $object-> syntax.
{
    my ($self, $key) = @_;

    $self->_prepare_variable( $key );

    return $self->_lazy_value( project => $self, key => $key, type => 'variable' );
}

sub test
{
    my ($self, $key) = @_;

    $self->_prepare_test( $key );

    return $self->_lazy_value( project => $self, key => $key, type => 'test' );
}

sub _lazy_value
{
    my ($self, %args) = @_;

    my $lazy = QtQA::QMake::Project::LazyValue->new( %args );

    # FIXME: some way of also delaying on `wantarray' would be nice, but it
    # currently doesn't seem feasible.  Note that returning a tied array
    # doesn't work as expected (the entire tied array is expanded out into
    # the caller when the function returns).
    return wantarray ? $lazy->_resolved( ) : $lazy;
}

1;

=head1 NAME

QtQA::QMake::Project - perl interface to qmake .pro file(s)

=head1 SYNOPSIS

  use QtQA::QMake::Project;

  # Load a project from a qmake-generated Makefile
  my $prj = QtQA::QMake::Project->new( 'Makefile' );

  # Perform arbitrary tests; may be anything usable from a qmake scope
  my $testcase = $prj->test( 'testcase' );
  my $insignificant = $prj->test( 'insignificant_test' );

  # Retrieve arbitrary values (scalars or lists)
  my $target = $prj->values( 'TARGET' );

  return unless $testcase;

  my $status = system( $target, '-silent' );
  return unless $status;
  if ($insignificant) {
      warn "Test $target failed; ignoring, since it is insignificant";
      return;
  }
  die "Test $target failed with exit status $status";

Given a qmake-generated Makefile, provides an API for accessing any
qmake variables or tests (scopes).

=head1 DESCRIPTION

For projects using qmake, .pro files are a convenient place to include
all sorts of metadata.  However, making that metadata robustly readable
by tools other than qmake has been rather challenging.  Typically the data
is only able to flow in one direction: if some tool outside of the build
system wants to access build system metadata, then qmake or some .prf
files must be modified to explicitly export that data.  General programmatic
access has not been possible.

This module aims to solve this problem, allowing robust and correct reading
of metadata from qmake project files without requiring any changes to qmake.

=head2 HOW IT WORKS

The qmake language is undefined, and there is no library form of qmake.
This means that only qmake (the binary) can parse qmake (the language).
Therefore, this module does not actually parse any qmake .pro files itself.
qmake does all the parsing.

Values are resolved roughly using a process like the following:

=over

=item *

The given makefile is used to determine the correct qmake command,
arguments and .pro file for this test.

=item *

A temporary .pro file is created containing the content of the real .pro
file, as well as some additional code which outputs all of the requested
variables / tests.

=item *

qmake is run over the temporary .pro file.  The Makefile generated by
this qmake run is discarded.  The standard output of qmake is parsed to
determine the values of the evaluated variables/tests.

=back

At a glance, it may seem odd that this package operates on Makefiles
(qmake's output) rather than .pro files (qmake's input).  In fact, there
is a good reason for this.

Various context affects the behavior of qmake, including the directory
containing the .pro file, the directory containing the Makefile, the
arguments passed by the user, the presence of a .qmake.cache file, etc.
The Makefile encapsulates all of this context.

=head2 DELAYED EVALUATION

Running qmake can be relatively slow (e.g. a few seconds for a cold
run), and therefore the amount of qmake runs should be minimized.
This is accomplished by delayed evaluation.

Essentially, repeated calls to the B<test> or B<values> functions
may not result in any qmake runs, until one of the values returned
by these functions is actually used.  This is accomplished by
returning blessed values with overloaded conversions.

For example, consider this code:

  my $project = QtQA::QMake::Project->new( 'Makefile' );
  my $target = $project->values( 'TARGET' );
  my $target_path = $project->values( 'target.path' );

  say "$target will be installed to $target_path";  # QMAKE EXECUTED HERE!

There is a single qmake execution, occurring only when the values
are used by the caller.

This means that writing the code a bit differently potentially would
have much worse performance:

  #### BAD EXAMPLE ####
  my $project = QtQA::QMake::Project->new( 'Makefile' );

  my $target = $project->values( 'TARGET' );
  say "Processing $target";                            # QMAKE EXECUTED HERE!

  my $target_path = $project->values( 'target.path' );
  say "  -> will be installed to $target_path";        # QMAKE EXECUTED HERE!

Therefore it is good to keep the delayed evaluation in mind, to avoid writing
poorly performing code.

As a caveat to all of the above, a list evaluation is never delayed. This is
because the size of the list must always be known when a list is returned.

  my $project = QtQA::QMake::Project->new( 'Makefile' );
  my $target = $project->values( 'TARGET' );
  my @config = $project->values( 'CONFIG' ); # QMAKE EXECUTED HERE!

  say "configuration of $target: ".join(' ', @CONFIG);

=head2 ERROR HANDLING

By default, all errors are considered fatal, and raised as exceptions.
This includes errors encountered during delayed evaluation.

Errors can be made into non-fatal warnings by calling C<set_die_on_error( 0 )>.

All exceptions and warnings match the pattern C<qr/^QtQA::QMake::Project:/>.

=head2 FUNCTIONS

The following functions are provided:

=over

=item B<new>()

=item B<new>( MAKEFILE )

Returns a new B<QtQA::QMake::Project> representing the qmake project for
the given MAKEFILE.  If MAKEFILE is not provided, a makefile must be set
via B<set_makefile> before attempting to retrieve any values from the project.

=item B<test>( EXPRESSION )

Returns a true value if the given qmake EXPRESSION evaluated to true,
a false value otherwise.

EXPRESSION must be a valid qmake "test" expression, as in the following
construct:

  EXPRESSION:message("The expression is true!")

Compound expressions are fine.  For example:

  if ($project->test( 'testcase:CONFIG(debug, debug|release)' )) {
    say "Found testcase in debug mode.  Running test in debugger.";
    ...
  }

The actual evaluation of the expression might be delayed until the returned
value is used in a boolean context.  See L<DELAYED EVALUATION> for more
details.

=item B<values>( VARIABLE )

Returns the value(s) of the given qmake VARIABLE.

VARIABLE may be any valid qmake variable name, without any leading $$.

Note that (almost) all qmake variables are inherently lists.  A variable
with a single value, such as TARGET, is a list with one element.  A variable
such as CONFIG contains many elements.

In scalar context, this function will return only the variable's first value.
In list context, it will return all values.

Example:

  my $target = $project->values( 'TARGET' );
  my @testdata = $project->values( 'TESTDATA' );

  if (@testdata) {
    say "Deploying testdata for $target";
    ...
  }

In scalar context, the actual evaluation of the variable might be delayed
until the returned value is used in a string, integer or boolean context.
See L<DELAYED EVALUATION> for more details.  In list context, evaluation is
never delayed, due to implementation difficulties.

=item B<makefile>()

=item B<set_makefile>( MAKEFILE )

Get or set the makefile referred to by this project.
Note that changing the makefile invalidates any values resolved via the
old makefile.

=item B<make>()

=item B<set_make>( MAKE )

Get or set the "make" binary (with no arguments) to be used for parsing
the makefile.  It should rarely be required to use these functions, as
there is a reasonable default.

=item B<die_on_error>()

=item B<set_die_on_error>( BOOL )

Get or set whether to raise exceptions when an error occurs.
By default, exceptions are raised.

Calling C<set_die_on_error( 0 )> will cause errors to be reported as
warnings only.  When errors occur, undefined values will be returned
by C<test> and C<values>.

=back

=head1 CAVEATS

Write permissions are required to both the directory containing the .pro
file and the directory containing the Makefile.

The module tries to ensure that all evaluations are performed after
qmake has processed default_post.prf and CONFIG - so, for example, if a
.pro file contains CONFIG+=debug, QMAKE_CXXFLAGS would contain (e.g.) -g,
as expected.  However, certain strange code could break this (such as
some .prf files loaded via CONFIG themselves re-ordering the CONFIG
variable).

It is possible to use this module to run arbitrary qmake code.  It goes
without saying that users are discouraged from abusing this :)

Various exotic constructs may cause this code to fail; for example, .pro
files with side effects.  The rule of thumb is: if C<make qmake> works for
your project, then this package should also work.

This module is (somewhat obviously) using qmake in a way it was not
designed to be used.  Although it appears to work well in practice, it's
fair to call this module one a big hack.

=cut
