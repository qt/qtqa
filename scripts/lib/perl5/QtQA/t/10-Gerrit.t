#!/usr/bin/env perl
use strict;
use warnings;

=head1 NAME

10-Gerrit.t - test QtQA::Gerrit module

=cut

use FindBin;
use lib "$FindBin::Bin/../..";

use AnyEvent;
use Capture::Tiny qw(capture_merged);
use Const::Fast;
use Data::Dumper;
use English qw( -no_match_vars );
use Env::Path;
use File::Temp;
use File::chdir;
use IO::File;
use Test::More;
use Test::Warn;

use QtQA::Test::More qw(create_mock_command);

BEGIN { use_ok 'QtQA::Gerrit'; }

const my $CHANGE_ID_RE => qr{I[a-f0-9]{40}};

# like system(), but fails the test and shows the command output
# if the command fails
sub system_or_fail
{
    my (@cmd) = @_;
    my $status;
    my $output = capture_merged {
        $status = system(@cmd);
    };
    is( $status, 0 ) || diag "command [@cmd] exited with status $status\noutput:\n$output";
    return;
}

# create a file with the given $filename, or fail
sub touch
{
    my ($filename) = @_;
    ok( IO::File->new($filename, '>>'), "open $filename" )
        || diag "open $filename failed: $!";
    return;
}

sub test_random_change_id
{
    my %seen;
    for my $i (1..10) {
        my $change_id = QtQA::Gerrit::random_change_id();
        ok( !$seen{ $change_id }, "[$i] random_change_id is unique" );
        $seen{ $change_id }++;
        like( $change_id, qr{\A$CHANGE_ID_RE\z}, "[$i] random_change_id looks like a Change-Id" );
    }
    return;
}

sub test_next_change_id
{
    # copy of %ENV with all git-related environment removed
    my %clean_env;
    while (my ($key, $value) = each %ENV) {
        if ($key !~ m{\AGIT_}i) {
            $clean_env{ $key } = $value;
        }
    }

    local %ENV = %clean_env;

    # copy of %ENV for two different git authors
    my %git1_env = QtQA::Gerrit::git_environment( bot_name => 'git bot 1' );
    my %git2_env = QtQA::Gerrit::git_environment( bot_name => 'git bot 2' );

    my $dir = File::Temp->newdir( 'qtqa-gerrit-test.XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    local $CWD = "$dir";

    warnings_are {
        # no history; degrades to random_change_id
        my $id1 = QtQA::Gerrit::next_change_id();
        my $id2 = QtQA::Gerrit::next_change_id();
        isnt( $id1, $id2, 'next_change_id returns two different IDs in random case' );
        like( $id1, qr{\A$CHANGE_ID_RE\z} );
        like( $id2, qr{\A$CHANGE_ID_RE\z} );
    } [('QtQA::Gerrit: git environment is not set, using random Change-Id') x 2];

    {
        local %ENV = %git1_env;
        system_or_fail( qw(git init) );
        touch( 'file1' );
        system_or_fail( qw(git add file1) );
        system_or_fail( qw(git commit -m), 'added file1' );
    }

    {
        # there is a git repository and environment but no commits from the current author;
        # returns a unique but stable Change-Id
        local %ENV = %git2_env;
        my $id1 = QtQA::Gerrit::next_change_id();
        my $id2 = QtQA::Gerrit::next_change_id();
        is( $id1, $id2, 'next_change_id returns same IDs if git environment is set' );
        like( $id1, qr{\A$CHANGE_ID_RE\z} );

        my $git1_id1;
        {
            # creating a new commit as the other author doesn't make any difference
            local %ENV = %git1_env;
            touch( 'file2' );
            system_or_fail( qw(git add file2) );
            system_or_fail( qw(git commit -m), 'added file2' );
            $git1_id1 = QtQA::Gerrit::next_change_id();
            like( $git1_id1, qr{\A$CHANGE_ID_RE\z} );
        }

        my $id3 = QtQA::Gerrit::next_change_id();
        is( $id3, $id1, 'new commits from other authors do not change the result' );

        # creating a commit from this author _does_ change the result...
        touch( 'file3' );
        system_or_fail( qw(git add file3) );
        system_or_fail( qw(git commit -m), 'added file3' );
        my $id4 = QtQA::Gerrit::next_change_id();
        my $id5 = QtQA::Gerrit::next_change_id();
        isnt( $id4, $id1, 'new commits from this author changes the result' );
        is( $id4, $id5, 'new Change-Id is stable' );
        like( $id4, qr{\A$CHANGE_ID_RE\z} );

        {
            # if we switch back to the other author, we still get the same stable
            # change-id for that author
            local %ENV = %git1_env;
            my $git1_id2 = QtQA::Gerrit::next_change_id();
            is( $git1_id1, $git1_id2, 'switching between authors does not change the result' );
        }
    }

    return;
}

sub test_stream_events
{
    local %ENV = %ENV;
    my $dir = File::Temp->newdir( 'qtqa-gerrit-test.XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    Env::Path->PATH->Prepend( "$dir" );

    create_mock_command(
        name => 'ssh',
        directory => $dir,
        sequence => [
            # first simulate an error to check retry behavior
            { exitcode => 1 },

            # then simulate various events from a long-lived connection
            {
                delay => 30,
                exitcode => 0,
                stdout => qq|{"id":1,"key1":"val1"}\n{"id":2,"key2":"val2"}\n{"id":3,"key3":"val3"}\n|,
            }
        ],
    );

    my $cv = AE::cv();

    # make sure we eventually give up if something goes wrong
    my $timeout_timer = AE::timer( 30, 0, sub { $cv->croak( 'timed out!' ) } );
    my $done_timer;

    my @events;
    my $guard;
    $guard = QtQA::Gerrit::stream_events(
        url => 'ssh://gerrit.example.com/',
        on_event => sub {
            my (undef, $event) = @_;
            push @events, $event;
            # we've arranged for 3 events, but test aborting after the 2nd event
            # by undef'ing $guard
            if (@events >= 2) {
                undef $guard;
                # run for a little while longer to give us a chance to wrongly see
                # the third event despite undef $guard
                $done_timer ||= AE::timer( 1, 0, sub { $cv->send() } );
            }
        },
    );

    my @warnings;
    {
        local $SIG{__WARN__} = sub {
            my ($warning) = @_;
            push @warnings, $warning;
        };
        $cv->recv();
    }

    # order of warnings is undefined; sort for testing
    @warnings = sort @warnings;
    is( scalar(@warnings), 2, 'got expected amount of warnings' );
    is( $warnings[0], "QtQA::Gerrit: Broken pipe\n", 'first warning as expected' );
    like( $warnings[1], qr{\AQtQA::Gerrit: ssh exited}, 'second warning as expected' );

    is_deeply( \@events, [{id=>1, key1=>'val1'},{id=>2, key2=>'val2'}], 'got expected events' )
        || diag 'events: '.Dumper( \@events );

    return;
}

sub run_test
{
    test_random_change_id;
    test_next_change_id;

    TODO: {
        if ($OSNAME =~ m{win32}i) {
            todo_skip( "QTQAINFRA-575 - investigate AnyEvent::Util::run_cmd on Windows", 4 );
        }
        test_stream_events;
    }

    return;
}

#==============================================================================

if (!caller) {
    run_test;
    done_testing;
}
1;
