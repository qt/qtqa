#!/usr/bin/env perl
use strict;
use warnings;

=head1 NAME

10-TestScript.t - test QtQA::TestScript module

=cut

use FindBin;
use lib "$FindBin::Bin/../..";

use English           qw( -no_match_vars );
use Data::Dumper      qw( Dumper  );
use IO::CaptureOutput qw( capture );
use Test::Exception;
use Test::Exit;
use Test::More;
use Readonly;

Readonly my $WINDOWS => ($OSNAME =~ m{win32}i);

BEGIN { use_ok 'QtQA::TestScript'; }

#==============================================================================

my %TEST_PERMITTED_PROPERTIES = (
    'dog.color' => 'The color of the dog.',
    'cat.color' => 'The color of the cat.',
    'fish.color'=> 'The color of the fish.',
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
    my $script = QtQA::TestScript->new;

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
    my $script = QtQA::TestScript->new;
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

# Test that `property' will get the property values from environment variables
sub test_property_get_from_env
{
    my $script = QtQA::TestScript->new;
    $script->set_permitted_properties(%TEST_PERMITTED_PROPERTIES);

    my $value;

    {
        local $ENV{PULSE_DOG_COLOR} = 'grey';       # old style, PULSE
        local $ENV{QTQA_CAT_COLOR}  = 'light blue'; # new style, QTQA

        lives_ok { $value = $script->property('dog.color', 'black') }; # default is ignored
        is($value, 'grey');
        lives_ok { $value = $script->property('cat.color')          };
        is($value, 'light blue');

        # And verify that QTQA takes precedence over PULSE
        local $ENV{QTQA_FISH_COLOR}  = 'silver';
        local $ENV{PULSE_FISH_COLOR} = 'gold';

        lives_ok { $value = $script->property('fish.color') };
        is($value, 'silver');
    }

    # A repeated call should return the same value (cached),
    # even though the ENV vars are no longer set
    lives_ok { $value = $script->property('dog.color', 'red')   }; # default is ignored
    is($value, 'grey');
    lives_ok { $value = $script->property('cat.color')          };
    is($value, 'light blue');
    lives_ok { $value = $script->property('fish.color')         };
    is($value, 'silver');

    return;
}

# Test that `property' will get the properties from command-line arguments
sub test_property_get_from_args
{
    my $script = QtQA::TestScript->new;
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
    my $script = QtQA::TestScript->new;

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
    my $script = QtQA::TestScript->new;

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
    my $script = QtQA::TestScript->new;

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
    my $script = QtQA::TestScript->new;

    # Any non-zero exit code should make the script die
    local $? = 0;
    dies_ok( sub { $script->exe('/bin/false') }, 'non-zero exit code implies death' );
    isnt( $?, 0, 'non-zero exit code is passed through $?' );

    my $stdout;
    my $stderr;

    my @good_cmd = (
        'perl',
        '-e',
        'use Data::Dumper; print Dumper(\@ARGV);',
        @TEST_EXE_ARGS1,
    );
    my $expected_log = "+ @good_cmd\n$TEST_EXE_ARGS1_DUMP";

    # We invoke a subprocess which uses Data::Dumper to print out all
    # arguments.  This is a simple way to check unambiguously what args
    # were received.
    local $? = 1;
    lives_ok( sub { capture { $script->exe(@good_cmd) } \$stdout, \$stderr },
        'successful command lives');
    is( $?, 0, 'zero exit code is passed through $?' );

    TODO: {
        local $TODO = 'fix or document argument passing on Windows' if $WINDOWS;
        is( $stdout, $expected_log, 'exe passes arguments correctly'   );
    }
    is( $stderr, q{},                  'no unexpected warnings or stderr' );

    # If verbose, should print out the command being run
    $script->get_options_from_array(['--verbose']);
    lives_ok( sub { capture { $script->exe(@good_cmd) } \$stdout, \$stderr },
        'successful command lives (verbose)');

    # exe should print out one line before running the command, like this:
    #   + cmd with each arg separated by space
    # Note it currently does not attempt to print args with whitespace unambiguously
    TODO: {
        local $TODO = 'fix or document argument passing on Windows' if $WINDOWS;
        is( $stdout, $expected_log, 'exe logs correctly' );
    }
    is( $stderr, q{},           'no unexpected warnings or stderr' );

    # verify that an exit status is passed into $? correctly
    my @exit12_cmd = (
        'perl',
        '-e',
        'exit(12)',
    );
    local $? = 0;
    dies_ok( sub { $script->exe(@exit12_cmd) }, 'exit(12) implies death' );
    is( $?, (12 << 8), 'correct exit code is passed through $?' );

    return;
}

# Test that exe_qx works like exe and also captures output.
sub test_exe_qx
{
    my $script = QtQA::TestScript->new;

    # Any non-zero exit code should make the script die
    local $? = 0;
    dies_ok( sub { $script->exe_qx('/bin/false') }, 'non-zero exit code implies death' );
    isnt( $?, 0, 'non-zero exit code is passed through $?' );

    # Note that there are two sets of output: the output from the child process
    # (which we expect to be returned), and the output from this process
    # (which is empty in the non-verbose case, and should never be returned).

    # From child process:
    my $stdout;
    my $stderr;
    my $merged;

    # From this process:
    my $log_stdout;
    my $log_stderr;

    my $test_stdout = $TEST_EXE_ARGS1_DUMP;
    my $test_stderr = "Some stderr\n";
    my $test_merged = $test_stdout.$test_stderr;

    my @good_cmd = (
        'perl',
        '-e',
        '$|++; use Data::Dumper; print Dumper(\@ARGV); print STDERR qq{Some stderr\n};',
        @TEST_EXE_ARGS1,
    );

    local $? = 1;
    lives_ok(
        sub {
            capture { ($stdout, $stderr) = $script->exe_qx(@good_cmd) } \$log_stdout, \$log_stderr;
            capture { $merged = $script->exe_qx(@good_cmd) };           # discard any log output
        },
        'successful command lives'
    );
    is( $?, 0, 'zero exit code is passed through $?' );

    TODO: {
        local $TODO = 'fix or document argument passing on Windows' if $WINDOWS;
        is( $stdout, $test_stdout, 'exe_qx passes arguments correctly' );
        is( $merged, $test_merged, 'merged output OK'                  );
    }
    is( $stderr, $test_stderr, 'stderr OK' );

    ok( !$log_stdout, 'no log output (verbose1)' );
    ok( !$log_stderr, 'no log error (verbose1)'  );



    # If verbose 1, command will be logged before it is run.
    $script->get_options_from_array(['--verbose']);

    lives_ok(
        sub {
            capture { ($stdout, $stderr) = $script->exe_qx(@good_cmd) } \$log_stdout, \$log_stderr;
            capture { $merged = $script->exe_qx(@good_cmd) };           # discard any log output
        },
        'successful command lives (verbose1)'
    );

    is( $stderr, $test_stderr, 'stderr OK (verbose1)' );
    TODO: {
        local $TODO = 'fix or document argument passing on Windows' if $WINDOWS;
        is( $stdout, $test_stdout, 'exe_qx passes arguments correctly (verbose1)' );
        is( $merged, $test_merged, 'merged output OK (verbose1)'                  );
    }

    is( $log_stdout, "qx @good_cmd\n", 'log output OK (verbose1)' );
    ok( !$log_stderr,                  'no log error (verbose1)'  );



    # If verbose 2, command will be logged before it is run, and stdout/stderr is logged
    # after it is run.  We need to test the log for merged vs non-merged independently here.
    $script->get_options_from_array(['--verbose']);

    my $log_stdout_merged;
    my $log_stderr_merged;

    my $expected_log_stdout = "qx @good_cmd\n" . <<'EOF';
qx stdout:
$VAR1 = [
          'arg1',
          'arg two',
          'arg the third',
          'arg \'with quotes\'',
          'arg "with dquotes"',
          'arg with $shell ^meta %characters%'
        ];

qx stderr:
Some stderr

EOF

    my $expected_log_stdout_merged = "qx @good_cmd\n" . <<'EOF';
qx stdout & stderr:
$VAR1 = [
          'arg1',
          'arg two',
          'arg the third',
          'arg \'with quotes\'',
          'arg "with dquotes"',
          'arg with $shell ^meta %characters%'
        ];
Some stderr

EOF

    lives_ok(
        sub {
            capture { ($stdout, $stderr) = $script->exe_qx(@good_cmd) }
                \$log_stdout,        \$log_stderr;

            capture { $merged = $script->exe_qx(@good_cmd) }
                \$log_stdout_merged, \$log_stderr_merged;
        },
        'successful command lives (verbose2)'
    );

    is( $stderr, $test_stderr, 'stderr OK (verbose2)' );
    ok( !$log_stderr,        'no log error (verbose2)'  );
    ok( !$log_stderr_merged, 'no log error (verbose2, merged)'  );
    TODO: {
        local $TODO = 'fix or document argument passing on Windows' if $WINDOWS;
        is( $stdout, $test_stdout, 'exe_qx passes arguments correctly (verbose2)' );
        is( $merged, $test_merged, 'merged output OK (verbose2)'                  );
        is( $log_stdout, $expected_log_stdout, 'log output OK (verbose2)' );
        is( $log_stdout_merged, $expected_log_stdout_merged, 'log output OK (verbose2, merged)' );
    }

    # verify that an exit status is passed into $? correctly
    my @exit12_cmd = (
        'perl',
        '-e',
        'exit(12)',
    );
    local $? = 0;
    dies_ok( sub { $script->exe_qx(@exit12_cmd) }, 'exit(12) implies death' );
    is( $?, (12 << 8), 'correct exit code is passed through $?' );

    return;
}

sub test_fatal_error
{
    my $script = QtQA::TestScript->new;

    throws_ok {
        $script->fatal_error(
            "Error occurred while making sandwich:\n"
           ."Somebody left the fridge door open all weekend\n"
        );
    } qr{

    # Note it is OK to have some stuff before and after the YAML.
    # However, the header must always be on its own line and the
    # footer must always be followed by a newline.

(?:\n|\A)
\Q--- !qtqa.qt-project.org/error
message: |
  Error occurred while making sandwich:
  Somebody left the fridge door open all weekend
... \E\#\Q end qtqa.qt-project.org/error\E
(?:\n|\z)

    }xms, 'fatal_error output looks OK';

    return;
}

sub test_fail
{
    my $script = QtQA::TestScript->new;

    throws_ok {
        $script->fail(
            "Error occurred while making sandwich:\n"
           ."Somebody left the fridge door open all weekend\n"
        );
    } qr{

(?:\n|\A)
\Q--- !qtqa.qt-project.org/failure
message: |
  Error occurred while making sandwich:
  Somebody left the fridge door open all weekend
... \E\#\Q end qtqa.qt-project.org/failure\E
(?:\n|\z)

    }xms, 'fail output looks OK';

    return;
}

sub test_doing
{
    my $script = QtQA::TestScript->new;

    my $make_expected = sub {
        my ($type, $message, @scopes) = @_;
        @scopes = reverse @scopes;
        return
            "--- !qtqa.qt-project.org/$type\nmessage: $message\n"
           .(@scopes
                ? "while:\n  - "
                 .join("\n  - ", @scopes)
                 ."\n"
                : q{}
            )
           ."... # end qtqa.qt-project.org/$type\n";
    };

    my $expected_error_for_scopes = sub { return $make_expected->( 'error', @_ ) };
    my $expected_failure_for_scopes = sub { return $make_expected->( 'failure', @_ ) };

    {
        my $outer = $script->doing( 'outer1' );

        {
            my $inner1 = $script->doing( 'inner1' );
            my $expected = $expected_error_for_scopes->( 'quux', 'outer1', 'inner1' );
            throws_ok { $script->fatal_error( 'quux' ) } qr{\A\Q$expected\E}, 'two scopes';
        }

        my $expected = $expected_failure_for_scopes->( 'bar', 'outer1' );
        throws_ok { $script->fail( 'bar' ) } qr{\A\Q$expected\E}, 'one scope';
    }

    my $expected = $expected_error_for_scopes->( 'baz' );
    throws_ok { $script->fatal_error( 'baz' ) } qr{\A\Q$expected\E}, 'no scope';

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
    test_exe_qx;

    test_fatal_error;
    test_fail;
    test_doing;

    return;
}

#==============================================================================

if (!caller) {
    run_test;
    done_testing;
}
1;
