package QtQA::TestScript;
use strict;
use warnings;

use Carp                qw(confess croak);
use Cwd                 qw();
use Getopt::Long        qw(GetOptionsFromArray);
use IO::Socket::INET    qw();
use Pod::Simple::Text   qw();
use Pod::Usage          qw(pod2usage);

#======================== private variables ===================================

# some common properties with subs or scalars to determine their default values
my %DEFAULT_COMMON_PROPERTIES = (
    'base.dir'  =>  \&Cwd::getcwd,
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
        croak q{test script error: `property' was called before `set_permitted_properties'};
    }

    unless (exists($self->{permitted_properties}->{$property_name})) {
        croak "test script error: test script attempted to read property `$property_name', "
            . "but did not declare it as a permitted property";
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

    # We are going to add values to env for all properties which are defined.
    # This ensures that the parent script always has full control over default
    # values of properties.  Otherwise, parent and child scripts could have
    # different defaults and therefore give unexpected behavior.
    my @property_env_keys
        = map { $self->_property_name_to_env_name($_) } keys %{$self->{resolved_property}};

    local @ENV{@property_env_keys} = values %{$self->{resolved_property}};

    # XXX important missing feature compared to Pulse::x - automatic retry.
    #
    # Pulse::x supported parsing of command output and automatically retrying
    # on certain types of errors.  Unfortunately the code for that was very fragile,
    # especially on Windows where quoting issues were common.  So it has not been
    # ported for now.

    $self->print_when_verbose(1, '+ ', join(' ', @command), "\n");
    my $status = system( @command );
    if ($status != 0) {
        croak "@command exited with status $status";
    }

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
# The `PULSE_...' style of naming is used for convenient integration
# with the Pulse CI tool.
sub _property_name_to_env_name
{
    my ($self, $name) = @_;

    $name = uc $name;
    $name =~ s/[^A-Z0-9]/_/g;
    $name = "PULSE_$name";

    return $name;

}

# Get the value of a property from an environment variable
sub _resolve_property_from_env
{
    my ($self, $property_name, $property_default_value) = @_;

    my $value;
    my $env_name = $self->_property_name_to_env_name( $property_name );
    if (exists $ENV{$env_name}) {
        $value = $ENV{$env_name};
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

    croak $message;
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

Environment variables prefixed with C<PULSE_> may be used to set properties.
This facilitates integration with the Pulse CI tool by Zutubi.
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
   my $qt_configure_args = $self->property('qt.configure.args', '-nokia-developer');

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

Run an external program, and die if it fails.  LIST is interpreted the same way as
in the builtin L<system> function.

This method is similar to the builtin L<system> function, with the following
additional features:

=over

=item verbosity

The command is printed before it is run, if the verbosity setting is >= 1.

=item automatic death

If the program does not exit with a 0 exit code, the script will die.
Similar to the L<autodie> module.

=item properties passed to child script

If the script being called is also a QtQA::TestScript, it will automatically
get the same values for all properties which are set in the currently
running script.

=back



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

=cut
