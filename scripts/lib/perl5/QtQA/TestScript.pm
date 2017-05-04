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

package QtQA::TestScript;
use strict;
use warnings;

use feature 'state';

use Capture::Tiny qw(capture capture_merged);
use Carp;
use Config;
use Cwd qw();
use Data::Dumper qw();
use File::chdir;
use Getopt::Long qw(GetOptionsFromArray);
use IO::Socket::INET;
use Lingua::EN::Numbers qw(num2en_ordinal);
use List::MoreUtils qw(zip);
use Params::Validate qw(validate);
use Pod::Simple::Text;
use Pod::Usage qw(pod2usage);
use YAML qw();
use YAML::Node;

use QtQA::Proc::Reliable;
use QtQA::ThreadSafeReleaseAction qw(on_release);

#======================== private variables ===================================

# some common properties with subs or scalars to determine their default values
my %DEFAULT_COMMON_PROPERTIES = (
    'base.dir'  =>  \&Cwd::getcwd,
    'shadowbuild.dir' => sub { shift->_resolved_property('base.dir') },
    'location'  =>  \&_default_location,
    'make.bin'  =>  'make',
    'make.args' =>  '-j5',
);

#======================== public methods ======================================
# These must all be documented at the end of the file


sub new
{
    my $class = shift;

    my %self = (
        resolved_property =>  {},  # resolved property cache starts empty
        verbose           =>   0,
    );

    bless \%self, $class;
    return \%self;
}

sub _croak
{
    my ($self, @rest) = @_;

    local %Carp::Internal = $self->_carp_internal( );
    croak @rest;
}


sub set_permitted_properties
{
    my ($self, %permitted_properties) = @_;

    $self->{permitted_properties} = \%permitted_properties;
    return;
}


sub property
{
    my $self = shift;
    my $property_name = shift;
    my $default_value = shift;

    unless ($self->{permitted_properties}) {
        $self->_croak( q{test script error: `property' was called before `set_permitted_properties'} );
    }

    unless (exists($self->{permitted_properties}->{$property_name})) {
        $self->_croak(
            "test script error: test script attempted to read property `$property_name', "
          . "but did not declare it as a permitted property"
        );
    }

    my $value = $self->_resolved_property($property_name);
    if (defined($value)) {
        return $value;
    }

    # This will die if the value is not set in a `PULSE_...' environment variable.
    $value = $self->_resolve_property_from_env($property_name, $default_value);

    $self->_set_resolved_property($property_name, $value);

    return $value;
}


sub get_options_from_array
{
    my ($self, $arg_values_ref, @arg_specifiers) = @_;

    # Simple args understood by all test scripts ...
    my @standard_arg_specifiers = (
        'help'     => sub { $self->print_usage(1) },
        'verbose+' => \$self->{verbose}            ,
    );

    # Args which may be used to set properties...
    my @permitted_property_arg_specifiers;
    if (exists $self->{permitted_properties}) {
        foreach my $property_name (keys %{$self->{permitted_properties}}) {
            my $option_name = $self->_property_name_to_option_name( $property_name );
            push( @permitted_property_arg_specifiers,
                "$option_name=s" => sub {
                    $self->_set_resolved_property($property_name, $_[1]);
                }
            );
        }
    }

    GetOptionsFromArray( $arg_values_ref,
        @arg_specifiers,
        @standard_arg_specifiers,
        @permitted_property_arg_specifiers,
    ) || $self->print_usage(2);

    # Flag that get_options_from_array has been called; we can use this later
    # for improved warning or debugging messages.
    $self->{called_get_options_from_array} = 1;

    return;
}


sub read_and_store_properties
{
    my ($self, @properties) = @_;

    while (@properties) {
        my $property_name          = shift @properties;
        my $property_default_value = shift @properties;

        # default value may be a sub which we must execute ...
        if (ref($property_default_value) eq 'CODE') {
            $property_default_value = $property_default_value->($self, $property_name);
        }

        $self->{$property_name} = $self->property( $property_name, $property_default_value );
    }

    return;
}


sub default_common_property
{
    my ($self, $property_name) = @_;

    my $property_value = $DEFAULT_COMMON_PROPERTIES{$property_name};
    if (ref($property_value) eq 'CODE') {
        $property_value = $property_value->($self, $property_name);
    }

    return $property_value;
}


sub exe
{
    my ($self, @command) = @_;

    # First element may be an OPTIONS hashref
    my %options = do {
        my @raw_options;
        if (scalar(@command) >= 1 && ref($command[0]) eq 'HASH') {
            @raw_options = (shift @command);
        }
        validate( @raw_options, {
            reliable    =>  { default => 1 },
        });
    };

    # We are going to add values to env for all properties which are defined.
    # This ensures that the parent script always has full control over default
    # values of properties.  Otherwise, parent and child scripts could have
    # different defaults and therefore give unexpected behavior.
    my @property_env_keys
        = map { $self->_property_name_to_env_name($_) } keys %{$self->{resolved_property}};

    local @ENV{@property_env_keys} = values %{$self->{resolved_property}};

    $self->_track_exe_environment( );
    $self->print_when_verbose(0, '+ ', join(' ', @command), "\n");
    $self->_reliable_exe( \%options, @command );

    return;
}

# Immediately prior to running a subprocess, record the CWD and PATH,
# and print the value(s) of these if they are different from last time.
# Should be called once for each exe() invocation.
sub _track_exe_environment
{
    my ($self) = @_;

    my $last_cwd = $self->{ _last_exe_cwd };
    if (!$last_cwd || $last_cwd ne $CWD) {
        $self->print_when_verbose( 0, "+ CWD: $CWD\n" );
        $self->{ _last_exe_cwd } = $CWD;
    }

    my $PATH = $ENV{ PATH };
    my $last_path = $self->{ _last_exe_path };
    if (!$last_path || $last_path ne $PATH) {
        $self->print_when_verbose( 0, "+ PATH: $PATH\n" );
        $self->{ _last_exe_path } = $PATH;
    }

    return;
}

sub _handle_exe_status
{
    my ($self, $status, @command) = @_;

    # $status could be a Math::BigInt (on Windows) but we can't assign that to $?;
    # make it to a plain scalar. Note that this destroys information when the
    # exit code has >24 bits of information, but this is consistent with the way
    # system() itself works on Windows.
    my $status_num = (ref($status) && $status->can('numify'))
        ? $status->numify()
        : $status
    ;
    $? = $status_num; ## no critic (RequireLocalized) - the point is to export it to caller

    if ($status != 0) {
        $self->_croak( "@command exited with status $status" );
    }

    return;
}

sub _simple_exe
{
    my ($self, @command) = @_;

    my $status = system( @command );
    $self->_handle_exe_status( $status, @command );

    return;
}

sub _reliable_exe
{
    my ($self, $options_ref, @command) = @_;

    my $proc = QtQA::Proc::Reliable->new( $options_ref, @command );
    if (!$proc) {
        # No reliable strategy, fall back to simple mechanism
        $self->_simple_exe( @command );
        return;
    }

    # TODO: Hack for Windows 8 "Can't spawn cmd.exe" problem.
    #
    # When command is executed with Qt reliability strategy,
    # OS environment is *sporadically* corrupted. The corrupted environment
    # contains one new environment variable & value with cryptic (illegal) characters.
    #
    # The exact line where environment corruption seems to happen most often is:
    # https://qt.gitorious.org/qt/qtqa/blobs/master/scripts/lib/perl5/QtQA/Proc/Reliable/Win32.pm#line355
    # Initially I thought it is due to encode_base64, which allows  '+', '/' and '=' charachers,
    # but switching to URL safe base64 encoding did not solve the problem.
    # http://search.cpan.org/~kazuho/MIME-Base64-URLSafe-0.01/lib/MIME/Base64/URLSafe.pm
    #
    # The broken OS environment causes perl system() command to fail later on.
    #
    # Because the root cause for environment corruption is not yet known,
    # we backup the environment before the reliable command execution,
    # and revert the environment back to original after command execcution.
    my %ENV_BACKUP = %ENV;

    # Whenever we retry the command, log it
    $proc->retry_cb( sub { $self->_log_exe_retry( @_ ) } );

    # internally, run() may retry many times, but it only returns the last status
    my $status = $proc->run( );
    $self->_handle_exe_status( $status );

    # TODO: Hack for Windows 8 "Can't spawn cmd.exe" problem.
    # Revert environment back to backed-up version.
    %ENV = %ENV_BACKUP; ## no critic

    return;
}

sub _log_exe_retry
{
    my ($self, $arg_ref) = @_;

    my $proc    = $arg_ref->{ proc };
    my $status  = $arg_ref->{ status };
    my $reason  = $arg_ref->{ reason };
    my $attempt = $arg_ref->{ attempt };

    my @command = $proc->command( );

    my $status_string = $self->_format_status( $status );

    my $message
        = 'The '.num2en_ordinal( $attempt )." attempt at running this command:\n"
        . '    '.Data::Dumper->new([\@command], ['command'])->Indent(0)->Dump()."\n"
        . "... failed with $status_string.\n"
        . "It will be retried because $reason\n"
    ;

    $self->_warn( $message );

    return;
}

sub _format_status
{
    my ($self, $status) = @_;

    my $signal   = ($status & 127);
    my $coredump = ($status & 128);
    my $exitcode = ($status >> 8);

    if ($signal) {
        my $out = $self->_format_signal( $signal );
        if ($coredump) {
            $out .= ' (dumped core)';
        }
        return $out;
    }

    return "exit code $exitcode";
}

sub _format_signal
{
    my ($self, $signal) = @_;

    state $signal_number_to_name = (sub {
        #
        # numbers is e.g. '0 1 2 3 4 5 6 7 8 9 10 11 12 13 3 4 ', may contain duplicates.
        # names is e.g.   'ZERO HUP INT QUIT ', no duplicates.
        #
        # We reverse these because we report only one name per number, and we consider the _first_
        # name for a given number to be the most significant name, which means it should be the
        # _last_ name assigned during the hash assignment.
        #
        my @signal_numbers = reverse split(' ', $Config{ sig_num });  # e.g. '1 2 3 4 5 3 4 '
        my @signal_names   = reverse split(' ', $Config{ sig_name }); # e.g. 'HUP SEGV BUS INT '

        my %out = zip @signal_numbers, @signal_names;
        \%out;
    })->();

    my $signal_name = $signal_number_to_name->{ $signal };

    # Examples:
    #
    #   signal 11
    #   signal 11 (SIGSEGV)
    #
    return
        "signal $signal"
       .( $signal_name ? " (SIG$signal_name)" : "")
    ;
}

# Returns a hash suitable for assignment to %Carp::Internal to ensure Carp reports
# backtraces relative to the correct place.
sub _carp_internal
{
    my ($self) = @_;

    my %out = %Carp::Internal;

    foreach my $package (qw(
        QtQA::Proc::Reliable
        QtQA::TestScript
        Capture::Tiny
    )) {
        $out{ $package }++;
    }

    return %out;
}

# Warn with $message, and prefix each line with the package name so that it is obvious where
# this message is coming from.  Also, carp is used so that the message hopefully ends up
# pointing out a relevant line in the actual test script.
sub _warn
{
    my ($self, $message) = @_;

    my $prefix = __PACKAGE__ . ': ';

    $message =~ s{\n}{\n$prefix}g;
    $message = $prefix . $message;

    local %Carp::Internal = $self->_carp_internal( );

    carp $message;

    return;
}

sub exe_qx
{
    my ($self, @command) = @_;

    $self->print_when_verbose(1, "qx @command\n");

    my $stdout;
    my $stderr;
    my $status;

    if (wantarray) {
        ($stdout, $stderr) = capture {
            $status = system( @command );
        };
        $self->print_when_verbose(2, "qx stdout:\n$stdout\n"
                                    ."qx stderr:\n$stderr\n");
    }
    else {
        $stdout = capture_merged {
            $status = system( @command );
        };
        $self->print_when_verbose(2, "qx stdout & stderr:\n$stdout\n" );
    }

    if ($status != 0) {
        $self->_croak(
            Data::Dumper->new( [\@command], ['command'] )->Indent( 0 )->Dump( )
          . qq{ exited with status $status}
        );
    }

    return wantarray ? ($stdout, $stderr) : $stdout;
}

sub fatal_error
{
    my ($self, $text) = @_;

    $self->_croak( $self->_format_yaml_block( 'error', $text ) );

    return;
}

sub fail
{
    my ($self, $text) = @_;

    $self->_croak( $self->_format_yaml_block( 'failure', $text ) );

    return;
}

sub _format_yaml_block
{
    my ($self, $type, $text) = @_;

    # We want to ensure that the 'message' key always comes first.
    # This is why we use YAML::Node.
    my $id = "qtqa.qt-project.org/$type";
    my $ynode = YAML::Node->new({}, $id );
    %{$ynode} = (
        message => $text,
    );
    my @context = @{ $self->{ _context } || [] };

    if (@context) {
        $ynode->{'while'} = [reverse @context];
    }

    local $YAML::UseBlock = 1;
    my $formatted = YAML::Dump( $ynode );

    return "$formatted... # end $id\n";
}

sub doing
{
    my ($self, $thing) = @_;

    if (! defined wantarray) {
        $self->_warn( 'useless call to doing( ) in void context' );
        return;
    }

    $self->_push_context( $thing );
    return on_release { $self->_pop_context( $thing ) };
}

sub _push_context
{
    my ($self, $thing) = @_;

    push @{ $self->{ _context } }, $thing;

    my $time = time();
    push @{ $self->{ _context_start } }, $time;
    print "#=# ". localtime($time) ." #=# >$thing\n";

    return;
}

sub _pop_context
{
    my ($self, $thing) = @_;

    my $actual_thing = pop @{ $self->{ _context } || [] };
    if ($actual_thing ne $thing) {
        $self->_warn( "scope mismatch: leaving context '$actual_thing', expecting to leave '$thing'" );
    }

    my $time = time();
    my $elapsed = $time - pop @{ $self->{ _context_start } || [] };
    print "#=# ". localtime($time) ." #=# <$thing #=# Elapsed $elapsed second(s).\n";

    return;
}

sub print_when_verbose
{
    my ($self, $verbosity, @print_list) = @_;

    my $out = 0;

    if ($self->{verbose} >= $verbosity) {
        print @print_list;
        $out = 1;
    }

    return $out;
}


sub print_usage
{
    my ($self, $exitcode) = @_;

    pod2usage({
        -exitval => 'NOEXIT',
    });

    my $properties_pod = join "\n", (
        '=head2 Standard options:',
        '',
        '=over',
        '',
        '=item --help',
        '',
        'Print this help.',
        '',
        '=item --verbose',
        '',
        'Be more verbose.  Specify multiple times for more verbosity.',
        '',
        '=back',
    );

    if ($self->{permitted_properties}) {
        $properties_pod .= "\n\n=head2 Options specific to this script:\n\n=over\n\n";

        foreach my $property_name (sort keys %{$self->{permitted_properties}}) {
            my $property_doc = $self->{permitted_properties}->{$property_name};

            my $option_name = $self->_property_name_to_option_name( $property_name );

            $properties_pod .= "=item [$property_name] --$option_name <value>\n\n";
            $properties_pod .= "$property_doc\n\n";
        }

        $properties_pod .= "=back\n\n=cut\n";

        Pod::Simple::Text->filter( \$properties_pod );
    }

    exit $exitcode;
}

#====================== internals =============================================

# get the value of a property which has been resolved already.
# `resolved' means it has been read from command-line arguments or from environment.
#
# Parameters:
#   $name - name of the property to get
#
# Returns the value, or undef if the property has not yet been resolved.
#
sub _resolved_property
{
    my ($self, $name) = @_;

    if (exists($self->{resolved_property}->{$name})) {
        return $self->{resolved_property}->{$name};
    }

    return;
}

# set the resolved value of a property.
#
# Parameters:
#   $name  - name of the property, e.g. 'base.dir'
#   $value - value of the property, e.g. '/tmp/foo/bar'
#
sub _set_resolved_property
{
    my ($self, $name, $value) = @_;

    $self->{resolved_property}->{$name} = $value;

    return;
}

# Converts a property name (e.g. qt.configure.args) to an option
# name suitable for getopt (e.g. qt-configure-args)
sub _property_name_to_option_name
{
    my ($self, $name) = @_;

    $name = lc $name;
    $name =~ s/[^a-z0-9\-]/-/g;

    return $name;
}

# Converts a property name (e.g. qt.configure.args) to an option
# name suitable for an environment variable (e.g. PULSE_QT_CONFIGURE_ARGS)
# Several possible names are returned, in order of priority.
# The `QTQA_...' names are preferred, but the `PULSE_...' style of naming
# is used for convenient integration with the Pulse CI tool.
sub _property_name_to_env_names
{
    my ($self, $name) = @_;

    $name = uc $name;
    $name =~ s/[^A-Z0-9]/_/g;

    return ("QTQA_$name", "PULSE_$name");
}

# Like _property_name_to_env_names, but only returns the highest priority name.
sub _property_name_to_env_name
{
    my ($self, $name) = @_;

    my ($out) = $self->_property_name_to_env_names( $name );
    return $out;
}

# Get the value of a property from an environment variable
sub _resolve_property_from_env
{
    my ($self, $property_name, $property_default_value) = @_;

    my $value;
    my @env_names = $self->_property_name_to_env_names( $property_name );
    foreach my $env_name (@env_names) {
        if (exists $ENV{$env_name}) {
            $value = $ENV{$env_name};
            last;
        }
    }
    if (defined $value) {
        # good, nothing to be done
    }
    elsif (defined $property_default_value) {
        $value = $property_default_value;
    }
    else {
        $self->_croak_from_missing_property( $property_name, {
            tried_env => 1,
            tried_argv => $self->{called_get_options_from_array}
        });
    }

    return $value;
}

# Croak with a sensible error message about an undefined property
sub _croak_from_missing_property
{
    my ($self, $property_name, $arg_ref) = @_;

    my $message = "The required property `$property_name' was not defined and there is no "
        ."default value.\n";

    my @set_methods;

    if ($arg_ref->{tried_env}) {
        my $env_name = $self->_property_name_to_env_name( $property_name );
        push @set_methods, "via environment variable $env_name";
    }
    if ($arg_ref->{tried_argv}) {
        my $option_name = $self->_property_name_to_option_name( $property_name );
        push @set_methods, "via --$option_name command-line option";
    }

    if (@set_methods) {
        $message .= "It may be defined by one of the following:\n";
        $message .= join(q{}, map { "  $_\n" } @set_methods);
    }

    $self->_croak( $message );

    return;
}

# Attempt to return this host's most significant IP address
sub _get_primary_ip
{
    my $sock = IO::Socket::INET->new(
        PeerAddr=> "example.com",
        PeerPort=> 80,
        Proto   => "tcp");
    return $sock->sockhost;
}

# Returns default location (e.g. `brisbane', `oslo')
sub _default_location
{
    my ($self) = shift;

    my $ip;
    eval {
        $ip = $self->_get_primary_ip;  # may fail if lacking Internet connectivity
    };

    return '' if (!$ip);

    # Brisbane subnets:
    #   172.30.116.0/24
    #   172.30.136.0/24
    #   172.30.138.0/24
    #   172.30.139.0/24
    if ($ip =~ /^172\.30\.(116|136|138|139)\./) {
        return 'brisbane';
    }

    # Oslo subnets:
    #   172.30.105.0/24
    #   172.24.105.0/24
    #   172.24.90.0/24 europe.nokia.com, consider as oslo
    if ($ip =~ /^172\.30\.105\./ ||
        $ip =~ /^172\.24\.(90|105)\./) {
        return 'oslo';
    }

    return '';
}


1;

__END__


=head1 NAME

QtQA::TestScript - base class for Qt test scripts

=head1 SYNOPSIS

  use base qw(QtQA::TestScript);
  ...

This is the recommended base class for all new test scripts for Qt test
infrastructure.  It encapsulates some functionality which all test scripts
are likely to benefit from, and encourages some uniform coding and
documentation conventions between test scripts.


=head1 METHODS

=over



=item B<new>

Create a new TestScript object, with empty state.



=item B<property>( NAME )

=item B<property>( NAME, DEFAULT )

Returns the value of the specified property.

In the first form, where DEFAULT is not specified, the test script will die
if the property has not been set.

In the second form, DEFAULT will be returned if the property has not been set.

A property is a string value which affects the behavior of the current test
script.  Properties may be sourced from:

=over

=item environment

Environment variables prefixed with C<QTQA_> or C<PULSE_> may be used to set properties.

The C<PULSE_> syntax facilitates integration with the Pulse CI tool by Zutubi.
Read the Pulse documentation for more information about the concepts of Pulse
properties.

=item command line arguments

Arguments passed to the test script may be used to set properties.
For example:

  $ ./testscript.pl --qt-configure-args '-nomake demos -nomake examples'

... will set the C<qt.configure.args> property to `-nomake demos -nomake examples'.

=back

Example:

   my $base_dir          = $self->property('base.dir',          getcwd());
   my $qt_configure_args = $self->property('qt.configure.args', '-developer-build -opensource -confirm-license');

   chdir($base_dir);
   system('./configure', split(/ /, $qt_configure_args));

=cut



=item B<default_common_property>( PROPERTYNAME )

Get the default value for the property with the given PROPERTYNAME, if any
is available.  Returns undef if no default is available.

There are some properties which are used from many test scripts but are
rarely set explicitly.  This method may be used to ensure that all test
scripts using these properties will use the same default values.

Some examples of common properties with default values:

=over

=item base.dir

The top-level directory of the source under test; defaults to the current
working directory.

=item location

Location hint for determining (among other things) which git mirror may be
used, if any.  Default is calculated based on IP address of the current host.

=back



=item B<set_permitted_properties>( NAME1 => DOC1 [, NAME2 => DOC2, ... ] )

Set the properties which this script is permitted to use, along with their
documentation.

This method enforces that all properties used by this script are declared
and documented.  The method must be called prior to any call to L<property>.

After the permitted properties have been set, any call to L<property> which
refers to a property not in this list will cause a fatal error.

The documentation of properties may be used to automatically generate some
documentation or help messages for test scripts.

Example:

  $self->set_permitted_properties(
      q{base.dir}       =>  q{top-level source directory},
      q{configure.args} =>  q{space-separated arguments to be passed to `configure'},
  );

  # later ...
  my @configure_args = split(/ /, $self->property('configure.args'));



=item B<doing>( STRING )

Pushes the given STRING onto an internal context stack, which may then be used for
stack traces produced on error or failure (e.g. by L<fatal_error> or L<fail>).
The STRING should be a human-readable summary of a task (e.g. "compiling the autotests").

Returns a reference.  When that reference is destroyed, the task is popped off
the context stack.  It is invalid to call this function without storing the return
value.

Example:

  sub run {
    my ($self) = @_;
    my $doing = $self->doing( 'testing the frobnitz' );
    $self->configure( );
    $self->compile( );
    $self->compile_autotests( );
    $self->run_autotests( );
  }

  ...

  sub compile {
    my ($self) = @_;
    my $doing = $self->doing( 'compiling the frobnitz' );

    # sanity check
    (-e 'Makefile') || $self->fail(
        'configure succeeded, but no Makefile found!'
    );

    $self->exe( 'make' );
  }

  ...

In the above example, if the sanity check for the Makefile failed, the failure
message would include a trace of the form:

  while:
    - compiling the frobnitz
    - testing the frobnitz

Usage note: the most important consumer of this information is the
C<parse_build_log.pl> script in the qtqa repository.  When this script finds
a failure or error with context information, it uses the topmost part of the context
stack as the failure summary (which is usually pasted into Gerrit).  The failure
from the previous example code may be summarized as:

  Compiling the frobnitz failed :(

    configure succeeded, but no Makefile found!



=item B<fatal_error>( STRING )

Formats the given error STRING into a human and machine-readable value, then dies
with the formatted string.

The output error message is formatted with YAML in a manner intended to be quite
human-readable, but also possible to robustly extract from a plain text log by
a YAML parsing script.

The format of the message is loosely defined as a YAML document of type
C<QtQA::TestScript::Error>, containing a mapping from the scalar 'error' to
an error string. Beyond this, the format is undefined; the message is permitted
to include additional metadata.

This function should be used in place of "die" or "confess" when a useful error
string is known.  If the error message is generic - for example, "process <foo>
exited with status 123" where the process is expected to output its own error
messages - it is generally better not to use this function, as the formatted
error message is unlikely to provide any additional value.

This function should be called only when I<errors> occur, not when I<failures>
occur. In this context, a "failure" is attributable to the software under test,
while an "error" is not. For example, when testing Qt, some .cpp files failing
to compile is most likely a "failure", but some git repositories failing to
clone is most likely an "error".

The primary reason for differentiating between failures and errors is that it
may make sense to retry some actions when errors occur, but it rarely makes
sense to retry when failures occur.

It is highly recommended to make use of this function together with L<doing>.
See the documentation of that function for more information.

=item B<fail>( STRING )

Like L<fatal_error>, but for I<failures> rather than I<errors>; formats the
given failure STRING into a human and machine-readable value, then dies
with the formatted string.

See L<fatal_error> for discussion on the difference between a failure and an
error.

=item B<get_options_from_array>( ARRAYREF [, LIST ] )

Read command-line options from the given ARRAYREF (which would typically be \@ARGV ).
Most test scripts should call this function as one of the first steps.

The following options are processed:

=over

=item --help

Prints a suitable --help message for the current script, by using
pod2usage.

=item --verbose

Increments the verbosity setting of the script.
May be specified more than once.

=item any options passed in LIST

The optional LIST contains Getopt-compatible option specifiers.
See L<Getopt::Long> for details on the format of LIST.

=item options for any properties set via L<set_permitted_properties>

Every permitted property may be set via the command-line.

The option name is equal to the property name with all . replaced with -.
For example, if 'base.dir' is a permitted property, it may be set by
invoking the script with:

  --base-dir /tmp/foo/baz

=back



=item B<exe>( LIST )

=item B<exe>( OPTIONS, LIST )

Run an external program, and die if it fails.  LIST is interpreted the same way as
in the builtin L<system> function.  The exit status is stored in $?.

This method is similar to the builtin L<system> function, with the following
additional features:

=over

=item verbosity

The command is printed before it is run, if the verbosity setting is >= 1.

=item automatic death

If the program does not exit with a 0 exit code, the script will die.
Similar to the L<autodie> module.

=item automatic retry

Many commands may be automatically retried if they fail with errors assumed
to be unrelated to the code under test.  See the L<RELIABLE COMMANDS> section
for discussion of this topic.

=item properties passed to child script

If the script being called is also a QtQA::TestScript, it will automatically
get the same values for all properties which are set in the currently
running script.

=back

The behavior may be customized by passing an OPTIONS hashref with
the following keys:

=over

=item reliable

Controls the reliable heuristics applied to the command.
Set to 0 to completely disable automatic retry.

Please see the L<RELIABLE COMMANDS> section for further discussion.

=back



=item B<exe_qx>( LIST )

Run an external program, die if it fails, and return the standard output
(and maybe standard error).  The exit status is stored in $?.

When called in array context, a list containing (stdout, stderr) will be
returned.  In scalar context, a scalar containing merged stdout and stderr
will be returned.

  # save stdout, discard stderr
  my ($stdout, undef) = $self->exe_qx( qw(find / -name quux.pl) );

  # save stdout and stderr separately
  my ($stdout, $stderr) = $self->exe_qx( qw(find / -name quux.pl) );

  # save merged stdout and stderr
  my $output = $self->exe_qx( qw(find / -name quux.pl) );

This function behaves like the built-in qx() or backticks, with the following
improvements:

=over

=item verbosity

May log both the command, and its output, depending on verbosity settings of the
test script.

=item automatic death

Like B<exe>(), automatically dies if the command exits with a non-zero exit code.

=item no shell quoting issues

Like system(), supports the safe list syntax for the command (backticks/qx only
support a single string, which leads to quoting issues).

=item cleanly get stderr

Can return stdout/stderr separately.

=back

If this function does not meet your needs, consider using L<Capture::Tiny> in
conjunction with B<exe>.



=item B<print_usage>( EXITCODE )

Display a usage message for the current script, then exit with the specified
exit code.

This function uses pod2usage to print a usage message.

If L<set_permitted_properties> has been called, each property will also be
printed, along with its documentation.

If L<get_options_from_array> is used, this method will be called when the
C<--help> option is passed.  Therefore there is often no need to call this
method directly.



=item B<print_when_verbose>( VERBOSITY, LIST )

Print LIST if and only if the current verbosity is greater than or equal
to VERBOSITY.

LIST is interpreted the same way as for the L<print> builtin.

Returns a true value if anything was printed, false otherwise.



=back



=head1 RELIABLE COMMANDS

B<exe> is able to automatically retry failing commands for various
reasons.  This is useful in the case of transient errors which are not related
to the code under test, and hence should not affect the outcome of the test.

A command is considered as failed if it exits with a non-zero exit code,
and it is typically considered as requiring a retry if the stdout or stderr
from the command matches some internally predefined set of patterns.

Whenever a command is retried, a warning is printed with details about the
problem.

The most common usage for this feature is to avoid failures due to temporary
network problems.  Some simple examples include:

=over

=item *

You want to `git clone' a repository hosted on a remote server.  The repository
is very large, and the network connection is occasionally interrupted.  When
this happens, you want the test script to retry a few times until it works,
rather than failing.

=item *

You want to do an aggressively parallelized build by using distributed
compilation software.  The distributed compile tool is unfortunately not robust
in the case that someone trips over the power cord on one of the build
machines.  When this happens, you want to resume compilation rather than
failing the build.

=back

By default, B<exe> will automatically decide the reliable strategy based on
the command which is being run - as determined by the first element of LIST.
For example:

    exe( 'git', 'clone', 'git://example.com/myproject' );

...will enable the reliable handler for `git', automatically retrying the
clone if git fails and outputs messages which appear to be indicative of
network timeouts or similar problems.

This reliability feature is largely based on heuristics, gradually tweaked
over time from experience, and the exact behavior is deliberately undefined.
The intention is to silently do the right thing in most cases and allow the
script writer to focus on the test procedure without having to code for the
dozens of possible bogus error cases from every command.

However, in some cases it will be beneficial to disable or customize this
behavior, in which case the following values can be provided for the `reliable'
option to B<exe>:

=over

=item reliable => 1   (default)

Enable whatever automatic reliable strategies apply to the executed
command.  The command is determined by looking at the first element of
the LIST passed to B<exe>.

=item reliable => 0

Completely disable the reliable special handling.

Use this for pathological situations where the parsing of stdout/stderr is
unacceptable for you (see L<CAVEATS>), or you know that the command can't
be cleanly retried.

=item reliable => ['cmd1', 'cmd2', ...]

Enable all of the named reliable strategies.

These may be arbitrary strings, but they are usually named after the command
to which they should be applied.  For example, 'git', 'wget', 'make'.

Enabling multiple reliable strategies is useful when some complex process
is being initiated which will run several sub-commands, each of which has
its own applicable reliable strategy.

For instance, consider a project where running `make upload-results'
compiles and runs a set of autotests and uploads results to some remote host
using scp:

  $self->exe( {reliable => [
    'gcc',      # attempt to recover from silly compiler segfaults ...
    'scp',      # ...and annoying network problems on scp upload
  ]}, 'make', 'upload-testresults' );


=item reliable => 'cmd'

Shorthand for reliable => ['cmd'].

This is useful when the default command detection will not work due to
indirect execution of a command.  For example, if git is being run via
/bin/sh, the `git' reliable strategy will not be applied by default, so
something like the following may be appropriate:

  $self->exe(
    { reliable => 'git' },
    '/bin/sh',
    '-c',
    'set -e; for i in $(seq 3 5); do git clone git://gitorious.org/qt/qt$i.git; done'
  );

=back


=head1 CAVEATS

When B<exe> is used with a reliable strategy, which is the default for some commands
(see L<RELIABLE COMMANDS>), the script will retain a full copy of the stdout/stderr from
the child process until it completes.  This could be unacceptable if the run command
is expected to generate a lot of output.  In other words, if a command is run via
via B<exe>, and it generates 100MB of output, then the memory usage of Qt::TestScript
will increase by (at least) 100MB during the execution of that command.

=cut
