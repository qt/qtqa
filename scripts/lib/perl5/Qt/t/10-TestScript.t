#!/usr/bin/env perl
use strict;
use warnings;

=head1 NAME

10-TestScript.t - test Qt::TestScript module

=cut

use FindBin;
use lib "$FindBin::Bin/../..";

use Data::Dumper      qw( Dumper  );
use IO::CaptureOutput qw( capture );
use Test::Exception;
use Test::Exit;
use Test::More;

BEGIN { use_ok 'Qt::TestScript'; }

#==============================================================================

my %TEST_PERMITTED_PROPERTIES = (
    'dog.color' => 'The color of the dog.',
    'cat.color' => 'The color of the cat.',
);

my @TEST_EXE_ARGS1 = (
    q{arg1},
    q{arg two},
    q{arg the third},
    q{arg 'with quotes'},
    q{arg "with dquotes"},
    q{arg with $shell ^meta %characters%},
);

my $TEST_EXE_ARGS1_DUMP = Dumper(\@TEST_EXE_ARGS1);

# Test that `property' will die in various ways
sub test_property_death
{
    my $script = Qt::TestScript->new;

    # Should die if called before set_permitted_properties
    throws_ok { $script->property('foo.bar'       ) } qr/set_permitted_properties/;
    throws_ok { $script->property('foo.bar', 'def') } qr/set_permitted_properties/;

    $script->set_permitted_properties(%TEST_PERMITTED_PROPERTIES);

    # Should die if property is not permitted
    throws_ok { $script->property('bird.color'       ) } qr/did not declare it as a permitted property/;
    throws_ok { $script->property('bird.color', 'def') } qr/did not declare it as a permitted property/;

    # Should die if property is permitted, but is not defined and has no default
    throws_ok { $script->property('dog.color'        ) } qr/default/;

    return;
}

# Test that `property' will use the `default' parameter appropriately
sub test_property_get_defaults
{
    my $script = Qt::TestScript->new;
    $script->set_permitted_properties(%TEST_PERMITTED_PROPERTIES);

    # Should be able to get defaults
    my $value;
    lives_ok { $value = $script->property('dog.color', 'black') };
    is($value, 'black');
    lives_ok { $value = $script->property('cat.color', 'white') };
    is($value, 'white');

    # A repeated call should return the same value (cached)
    lives_ok { $value = $script->property('dog.color', 'red')   };
    is($value, 'black');
    lives_ok { $value = $script->property('dog.color')          };
    is($value, 'black');

    return;
}

# Test that `property' will get the property values from `PULSE_...' environment variables
sub test_property_get_from_env
{
    my $script = Qt::TestScript->new;
    $script->set_permitted_properties(%TEST_PERMITTED_PROPERTIES);

    my $value;

    {
        local $ENV{PULSE_DOG_COLOR} = 'grey';
        local $ENV{PULSE_CAT_COLOR} = 'light blue';

        lives_ok { $value = $script->property('dog.color', 'black') }; # default is ignored
        is($value, 'grey');
        lives_ok { $value = $script->property('cat.color')          };
        is($value, 'light blue');
    }

    # A repeated call should return the same value (cached),
    # even though the ENV vars are no longer set
    lives_ok { $value = $script->property('dog.color', 'red')   }; # default is ignored
    is($value, 'grey');
    lives_ok { $value = $script->property('cat.color')          };
    is($value, 'light blue');

    return;
}

# Test that `property' will get the properties from command-line arguments
sub test_property_get_from_args
{
    my $script = Qt::TestScript->new;
    $script->set_permitted_properties(%TEST_PERMITTED_PROPERTIES);

    my @args = ('--dog-color', 'green', '--cat-color', 'dark red');
    $script->get_options_from_array(\@args);

    my $value;
    lives_ok { $value = $script->property('dog.color', 'black') }; # default is ignored
    is($value, 'green');
    lives_ok { $value = $script->property('cat.color')          };
    is($value, 'dark red');

    return;
}

# Trivial test of default_common_property function
sub test_default_common_property
{
    my $script = Qt::TestScript->new;

    # Here, we basically test that default common properties returns
    # anything at all for a known property, and nothing for an unknown property.
    # We don't attempt to test the actual value returned (since the whole point
    # of this function is that the value may be unpredictable).
    ok( $script->default_common_property('base.dir'),             'base.dir has a default'       );
    is( $script->default_common_property('fake.property'), undef, 'fake.property has no default' );

    return;
}

# Test interaction between `print_verbose' and `--verbose' command-line option
sub test_verbosity
{
    my $script = Qt::TestScript->new;

    my $stdout;
    my $stderr;

    capture { $script->print_when_verbose(0, "hello", "world") } \$stdout, \$stderr;
    is( $stdout, "helloworld" );
    is( $stderr, ""           );

    capture { $script->print_when_verbose(-10, "negative") } \$stdout, \$stderr;
    is( $stdout, "negative" );
    is( $stderr, ""         );

    capture { $script->print_when_verbose(1, "should not print") } \$stdout, \$stderr;
    is( $stdout, "" );
    is( $stderr, "" );

    # Should set verbosity to 2
    $script->get_options_from_array(['--verbose', '--verbose']);

    capture { $script->print_when_verbose(1, "should print") } \$stdout, \$stderr;
    is( $stdout, "should print" );
    is( $stderr, ""             );

    capture { $script->print_when_verbose(2, "again print") } \$stdout, \$stderr;
    is( $stdout, "again print" );
    is( $stderr, ""            );

    capture { $script->print_when_verbose(3, "silent") } \$stdout, \$stderr;
    is( $stdout, "" );
    is( $stderr, "" );

    return;
}

# Basic test of command-line parsing
sub test_get_options_from_array
{
    my $script = Qt::TestScript->new;

    # `--help' is tested by 20-TestScript-autodocs.t
    # `--verbose' is tested by test_verbosity
    # passing arguments for properties is tested by test_property_get_from_args

    # Here, we're just testing that our arguments are passed to getopt unmolested.
    my $value1;
    my $value2;
    my @args = (
        '--option-one', 'A string',
        '--option-two',
        'something else',
    );
    $script->get_options_from_array(\@args,
        'option-one=s'  =>  \$value1,
        'option-two'    =>  \$value2,
    );

    is( $value1,        'A string'       );
    is( $value2,        1                );
    is( scalar(@args),  1                ); # non-parsed option is left behind
    is( $args[0],       'something else' );

    return;
}

# Test that exe logs, dies and passes arguments correctly
sub test_exe
{
    my $script = Qt::TestScript->new;

    # Any non-zero exit code should make the script die
    dies_ok( sub { $script->exe('/bin/false') }, 'non-zero exit code implies death' );

    my $stdout;
    my $stderr;

    my @good_cmd = (
        'perl',
        '-e',
        'use Data::Dumper; print Dumper(\@ARGV);',
        @TEST_EXE_ARGS1,
    );

    # We invoke a subprocess which uses Data::Dumper to print out all
    # arguments.  This is a simple way to check unambiguously what args
    # were received.
    lives_ok( sub { capture { $script->exe(@good_cmd) } \$stdout, \$stderr },
        'successful command lives');

    is( $stdout, $TEST_EXE_ARGS1_DUMP, 'exe passes arguments correctly'   );
    is( $stderr, q{},                  'no unexpected warnings or stderr' );

    # If verbose, should print out the command being run
    $script->get_options_from_array(['--verbose']);
    lives_ok( sub { capture { $script->exe(@good_cmd) } \$stdout, \$stderr },
        'successful command lives (verbose)');

    # exe should print out one line before running the command, like this:
    #   + cmd with each arg separated by space
    # Note it currently does not attempt to print args with whitespace unambiguously
    my $expected_log = "+ @good_cmd\n$TEST_EXE_ARGS1_DUMP";
    is( $stdout, $expected_log, 'exe logs correctly'               );
    is( $stderr, q{},           'no unexpected warnings or stderr' );

    return;
}

# Run all the tests
sub run_test
{
    test_property_death;
    test_property_get_defaults;
    test_property_get_from_env;
    test_property_get_from_args;

    test_default_common_property;

    test_verbosity;

    test_get_options_from_array;

    test_exe;

    return;
}

#==============================================================================

if (!caller) {
    run_test;
    done_testing;
}
1;
