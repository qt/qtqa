#!/usr/bin/env perl
use strict;
use warnings;
use utf8;

use threads;    # important - must come before Test::More.  See Test::More docs.

use Encode;
use English qw(-no_match_vars);
use File::Spec::Functions;
use FindBin;
use Test::More;

use lib catfile( $FindBin::Bin, qw(..) x 4 );
use QtQA::Proc::Reliable::Win32;

# Perl scriptlet which will output some stdout/stderr lines in a predictable order
my $OUTPUT_SCRIPT =
    # Remove newlines (windows shell does not like passing newlines in arguments)
    join( q{ }, split(/\s*\n\s*/, <<'EOF') );
        use Time::HiRes qw(usleep);
        $|++;
        my $i = 0;
        while (++$i <= 3) {
            print qq{Hi there on stdout $i\n};
            usleep( 200000 );
            warn qq{Hi there on stderr $i\n};
            usleep( 200000 );
        }
EOF

# Test of a somewhat realistic process outputting on both stdout and stderr
# for a few seconds.
sub test_output_ordering
{
    my ($proc) = @_;

    # Arrange for all lines to be saved, in order.
    my @lines;
    my $handle_line = sub {
        my ($expected_handle, $expected_handle_name, $handle, $text) = @_;
        my $linecount = @lines+1;
        is( $handle, $expected_handle, "line $linecount goes to $expected_handle_name" );
        push @lines, "$expected_handle_name: $text";
    };
    $proc->stdout_cb( sub { $handle_line->( *STDOUT, 'STDOUT', @_ ) } );
    $proc->stderr_cb( sub { $handle_line->( *STDERR, 'STDERR', @_ ) } );

    $proc->run( [ $EXECUTABLE_NAME, "-e", $OUTPUT_SCRIPT ] );

    is( $proc->status(), 0, 'process exited successfully' );

    my @expected_lines = (
        "STDOUT: Hi there on stdout 1\n",
        "STDERR: Hi there on stderr 1\n",
        "STDOUT: Hi there on stdout 2\n",
        "STDERR: Hi there on stderr 2\n",
        "STDOUT: Hi there on stdout 3\n",
        "STDERR: Hi there on stderr 3\n",
    );
    is_deeply( \@lines, \@expected_lines, 'callbacks called as expected' )
        || diag( "actual output:\n@lines" );

    return;
}

# Test of a process which executes fast and has no output.
# Executing fast could flush out race conditions in thread startup / teardown.
sub test_fast_no_output
{
    my ($proc) = @_;

    $proc->stdout_cb( sub { die "unexpectedly received something on stdout!\n@_\n" } );
    $proc->stderr_cb( sub { die "unexpectedly received something on stderr!\n@_\n" } );

    $proc->run( [ $EXECUTABLE_NAME, '-e', '1' ] );

    is( $proc->status(), 0, 'proc exited successfully' );

    return;
}

# Test of a process which executes fast and has output on one stream.
# Executing fast could flush out race conditions in thread startup / teardown.
sub test_fast_with_output
{
    my ($proc) = @_;

    my @lines;
    $proc->stdout_cb( sub { die "unexpectedly received something on stdout!\n@_\n" } );
    $proc->stderr_cb( sub {
        my ($handle, $text) = @_;
        is( $handle, *STDERR, 'line arrived on stderr' );
        push @lines, $text;
    });

    $proc->run( [ $EXECUTABLE_NAME, '-e', 'print STDERR q{Hello}; exit 12' ] );

    is( ($proc->status()>>8), 12, 'proc exited with expected exit code' )
        || diag( 'proc status: '.$proc->status() );

    is_deeply( \@lines, [ 'Hello' ], 'output is as expected' );

    return;
}

# Basic check that non-latin1 text can be passed through without munging
sub test_nonlatin1
{
    my ($proc) = @_;

    my @lines;
    $proc->stderr_cb( sub { die "unexpectedly received something on stderr!\n@_\n" } );
    $proc->stdout_cb( sub {
        my ($handle, $text) = @_;
        is( $handle, *STDOUT, 'line arrived on stdout' );
        push @lines, $text;
    });

    $proc->run( [ $EXECUTABLE_NAME, $0, '-print-nonlatin1' ] );

    is( $proc->status(), 0, 'proc exited successfully' );

    is_deeply( \@lines, [ encode_utf8( "我可以有汉堡吗\n" ) ], 'output is as expected' );

    return;
}

sub test_hang
{
    my ($proc) = @_;

    my @lines;
    $proc->stderr_cb( sub { die "unexpectedly received something on stderr!\n@_\n" } );
    $proc->stdout_cb( sub {
        my ($handle, $text) = @_;
        is( $handle, *STDOUT, 'line arrived on stdout' );
        push @lines, $text;
    });

    $proc->maxtime( 2 );
    $proc->run( [ $EXECUTABLE_NAME, '-e', '$|++; print qq{About to hang\n}; sleep 5; print STDERR qq{Still alive??\n};' ] );

    is( $proc->msg(), qq{Timed out after 2 seconds\n}, 'proc msg mentions hang' );
    ok( $proc->status(), 'proc did not exit successfully' );

    is_deeply( \@lines, [ "About to hang\n" ], 'output is as expected' );

    return;
}

# Test what happens when a callback does "die".
# This is important due to the usage of threads; if we aren't careful, we could
# leak threads when the stack is unwound.
sub test_die_in_cb
{
    my ($proc) = @_;

    $proc->stdout_cb( sub { die 'deliberately dying in stdout_cb' } );
    $proc->stderr_cb( sub {} );
    $proc->maxtime( 30 );

    my $thread_count_before = threads->list( );

    eval {
        $proc->run( [ $EXECUTABLE_NAME, '-e', '$|++; print qq{Hello\n}; sleep 20; print qq{World\n};' ] );
    };
    my $error = $@;

    my $thread_count_after = threads->list( );

    is( $thread_count_after, $thread_count_before, 'no leaking threads' );
    like( $error, qr{deliberately dying in stdout_cb}, '$@ is passed through callback as normal' );
    ok( $proc->status(), 'proc did not exit successfully' );

    return;
}

sub main
{
    SKIP: {
        skip( q{This test is only valid on Windows}, 1 ) unless ($OSNAME =~ m{win32}i);
        my $proc = QtQA::Proc::Reliable::Win32->new();

        # We redo tests using the same $proc object to try to flush out any issues
        # with state incorrectly not being cleared between runs.
        # Note: it would be nice to use subtest, but we avoid it due to
        # https://github.com/schwern/test-more/issues/145 "threads and subtests"
        for my $i (1, 2, 3) {
            diag("test_output_ordering $i");
            test_output_ordering( $proc );

            diag("test_fast_no_output $i");
            test_fast_no_output( $proc );

            diag("test_fast_with_output $i");
            test_fast_with_output( $proc );

            diag("test_nonlatin1 $i");
            test_nonlatin1( $proc );

            diag("test_hang $i");
            test_hang( $proc );

            diag("test_die_in_cb $i");
            test_die_in_cb( $proc );
        }
    }

    done_testing;
    return;
}

# Print a non-latin1 string.
# This is called if this script is invoked with -print-nonlatin1.
sub print_nonlatin1
{
    print encode_utf8( qq{我可以有汉堡吗\n} );
    return;
}

unless (caller) {
    if (@ARGV && $ARGV[0] eq '-print-nonlatin1') {
        print_nonlatin1;
    }
    else {
        main;
    }
}
1;
