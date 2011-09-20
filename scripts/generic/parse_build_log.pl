#!/usr/bin/env perl
#############################################################################
##
## Copyright (C) 2011 Nokia Corporation and/or its subsidiary(-ies).
## All rights reserved.
## Contact: Nokia Corporation (qt-info@nokia.com)
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
## $QT_END_LICENSE$
##
#############################################################################

package QtQA::App::ParseBuildLog;

use 5.010;
use strict;
use warnings;

=head1 NAME

parse_build_log - extract the interesting parts from a build log

=head1 SYNOPSIS

  ./parse_build_log [options] <logfile>

  # e.g., given a very large build log, just extract the interesting lines:
  $ ./parse_build_log my-log.txt
  compiling qml/qdeclarativebinding.cpp
  qml/qdeclarativebinding.cpp: In static member function 'static QDeclarativeBinding* QDeclarativeBinding::createBinding(int, QObject*, QDeclarativeContext*, const QString&, int, QObject*)':
  qml/qdeclarativebinding.cpp:238: error: cannot convert 'QDeclarativeEngine*' to 'QDeclarativeEnginePrivate*' in initialization
  make[3]: *** [.obj/debug-shared/qdeclarativebinding.o] Error 1
  make[2]: *** [sub-declarative-make_default-ordered] Error 2
  make[1]: *** [module-qtdeclarative-src-make_default] Error 2
  make: *** [module-qtdeclarative] Error 2

  # Or perhaps attempt to summarize the error in human-readable format,
  # and directly load the log over HTTP:
  $ ./parse_build_log --summarize http://example.com/some-ci-system/linux-build-log.txt
  qtdeclarative failed to compile on Linux:

    compiling qml/qdeclarativebinding.cpp
    qml/qdeclarativebinding.cpp: In static member function 'static QDeclarativeBinding* QDeclarativeBinding::createBinding(int, QObject*, QDeclarativeContext*, const QString&, int, QObject*)':
    qml/qdeclarativebinding.cpp:238: error: cannot convert 'QDeclarativeEngine*' to 'QDeclarativeEnginePrivate*' in initialization
    make[3]: *** [.obj/debug-shared/qdeclarativebinding.o] Error 1
    make[2]: *** [sub-declarative-make_default-ordered] Error 2
    make[1]: *** [module-qtdeclarative-src-make_default] Error 2
    make: *** [module-qtdeclarative] Error 2

This script takes a raw plain text build log and attempts to extract the interesting parts,
and possibly provide a nice human-readable summary of the failure.

=head1 OPTIONS

=over

=item B<--help>

Print this message.

=item B<--summarize>

If given, as well as printing out the interesting lines from the log, the script
will attempt to print out a human-readable summary of the error(s).

=item B<--debug>

Enable some debug messages to STDERR.
Use this to troubleshoot when some log is not parsed in the expected manner.

=back

=head1 CAVEATS

This script is entirely based on heuristics.  It may make mistakes.

=cut

use Data::Dumper;
use File::Basename;
use File::Fetch;
use File::Slurp qw();
use Getopt::Long qw(GetOptionsFromArray);
use Lingua::EN::Inflect qw(inflect PL WORDLIST);
use Lingua::EN::Numbers qw(num2en);
use List::MoreUtils qw(any);
use Pod::Usage;
use Readonly;
use Text::Wrap;

# Contact details of some CI admins who can deal with problems.
# Put a public email address here once we have one!
Readonly my $CI_CONTACT
    => q{some CI administrator};

# All important regular expressions used to extract errors
#Readonly my %RE => (  <- too slow :( Adds seconds to runtime, according to NYTProf.
my %RE = (

    # never matches anything
    never_match => qr{a\A}ms,


    # the kind of timestamp prefix used by Pulse.
    # example:
    #
    #  8/29/11 7:03:33 PM EST: Hi there
    #
    # matches up to and including the `: '
    #
    # Captures:
    #   date    -   the date string
    #   time    -   the time string (incl. AM/PM, and timezone)
    #
    pulse_timestamp => qr{
            \A

            (?<date>
                # d/m/y
                \d{1,2}/\d{1,2}/\d{1,2}
            )

            \s+

            (?<time>
                # h:m:s
                \d{1,2}:\d{1,2}:\d{1,2}

                \s+

                # AM or PM
                [AP]M

                \s+

                # some timezone (e.g. EST)
                [A-Z]{2,4}
            )

            # and the `: ' at the end
            :[ ]
    }xms,

    # Any kind of error in the Pulse configuration.
    #
    # Example:
    #   Recipe terminated with an error: Recipe request timed out waiting for a capable agent to become available.
    #
    # These kinds of errors are always the fault of the CI infrastructure
    # and not the code under test.
    #
    pulse_config_error => qr{
        (?:
            \A
            \QNo online agents satisfy the request requirements.\E
        )

        # add more as discovered
    }xms,

    # Any kind of glitch which can be identified as the reason for the build failure,
    # but the underlying cause is unknown.
    #
    # This is a catch-all for any kind of errors where:
    #
    #  - we can recognize the error message, but don't know the cause, or:
    #
    #  - we roughly know the cause, but it's considered unfeasible to really fix the
    #    problem or confidently present more information about the problem.
    #
    glitch => qr{
        (?:
            # note, deliberately not anchored at \A - this can occur in the middle of a line!
            \QRecipe terminated with an error: Agent status changed to 'invalid master' while recipe in progress\E
        )

        |

        (?:
            \QRecipe terminated with an error: Unable to dispatch recipe:\E
            [^\n]+
            \Qcom.caucho.hessian.io.HessianProtocolException: expected boolean at end of file\E
        )

        # add more as discovered
    }xms,

    # line output when the top-level qtqa script fails.
    #
    # Example:
    #   `perl _qtqa_latest/scripts/setup.pl --install && perl _qtqa_latest/scripts/qt/qtmod_test.pl' exited with code 3 at _pulseconfig/test.pl line 1025.
    #
    # Captures:
    #   qtqa_script -   path of the qtqa script which failed, relative to qtqa
    #                   (e.g. "scripts/qt/qtmod_test.pl")
    #
    qtqa_script_fail => qr{
        perl \s _qtqa_latest/

        (?<qtqa_script>
            [^']+
        )

        ' \s \Qexited with code \E\d
    }xms,

    # make failed.
    #
    # Examples:
    #   make[1]: *** [module-qtdeclarative-src-make_default] Error 2
    #   make: *** [module-qtdeclarative] Error 2
    #
    # Captures:
    #   make        -   the make tool (e.g. "make", "gmake"). ".exe" is omitted on windows
    #   sublevel    -   level of submake (e.g. "make[1]: *** Error 2" gives "1");
    #                   never matches for top-level make
    #   target      -   make target which failed (not always available)
    #   errorlevel  -   the error number, e.g. "Error 2" gives "2"
    #
    # Caveats:
    #   nmake probably doesn't work right.
    #
    #   jom support is missing (it probably can't be added without modifying jom,
    #   as jom simply doesn't output enough info - tested with jom 0.9.3)
    #
    #   According to NYTProf, this regex is unusually slow ... why??
    #
    make_fail => qr{
        \A

        (?<make>
            make
            |
            [gn]make        # GNU make, nmake
            |
            mingw32-make
        )

        (?: \.exe )?    # maybe has .exe on the end on Windows

        (?:
            \[
            (?<sublevel>
                \d+
            )
            \]
        )?              # "[2]" etc only present for submakes

        :
        \s

        # *** is the thing indicating an error
        \*{3}
        \s

        # now the target, in square brackets
        (?:
            \[
            (?<target>
                [^\]]+
            )
            \]
        )

        \s

        # "Error <num>"
        (?:
            Error \s
            (?<errorlevel>
                \d+
            )
        )

        \z
    }xms,

    # compile failed.
    #
    # Examples:
    #   quicktestresult.cpp:453: error: no matching function for call to 'QTestResult::addSkip(const char*, QTest::SkipMode, const char*, int&)'
    #   c:\test\recipes\129373577\base\qt\qtsvg\src\svg\qsvgstyle_p.h(65) : fatal error C1083: Cannot open include file: 'qdebug.h': No such file or directory
    #   /bin/sh: line 1: 52873 Killed: 9               g++ -c -pipe (...) graphicsview/qgraphicstransform.cpp
    #   mapsgl/frustum_p.h:60:27: error: Qt3D/qplane3d.h: No such file or directory
    #   qmetaobject/main.cpp:219: undefined reference to `QTreeView::staticMetaObject'
    #
    # Captures:
    #   file        -   name of the file in which error occurred (exactly as output by the
    #                   compiler - could be relative, absolute, or totally bogus)
    #   line        -   line number at which the error occurred (if available)
    #   error       -   text of the error message
    #
    # Caveats:
    #   Only matches a single line of the error (so e.g. for an ambiguous overload, "error"
    #   will not contain any of the alternatives)
    #
    #   These can probably be screwed up by source files whose path contains characters
    #   used as message separators by the compiler (e.g. `:' or `(' ) ... so please do not
    #   name source files like this :)
    #
    compile_fail => qr{

        # gcc or similar
        (?:
            \A

            # foobar.cpp:123: error: quiznux
            (?<file>
                [^:]+
            )

            :

            (?<line>
                \d+
            )

            (?:         # It is possible to have more than one line number in the error, e.g:
                :\d+    #   mapsgl/frustum_p.h:60:27: (...)
            )*          # We do not capture them at the moment.

            : \s

            (?<error>
                (?:
                    error: .+
                )
                |
                (?:
                    # note that `undefined reference' may produce either a compiler-style
                    # error message (caught here), or a linker-style error message (caught
                    # in linker_fail), depending on exactly when the error occurs
                    \Qundefined reference to \E.+
                )
            )

            \z
        )

        |

        # gcc killed for some reason
        (?:
            \A

            # note, assumes `make' is using `/bin/sh' (probably safe assumption)
            # /bin/sh: line 123: 456 Killed: 9
            /bin/sh:
            \s+

            line \s \d+:
            \s+

            \d+             # pid
            \s+

            (?<error>
                [^:]+       # description of the signal.  e.g. Killed, Aborted
                :
                \s+
                \d+         # signal number
            )

            \s+

            (?: gcc|g\+\+ ) # only catch gcc issues
            .+?             # rest of command and arguments ...

            (?<file>        # ...and assume file is the last argument (qmake-specific assumption)
                [^\s]+
            )

            \z
        )

        |

        # msvc or similar
        (?:
            \A

            #foobar.cpp(65) : fatal error C123: quiznux
            (?<file>
                [^\(]+
            )

            \(
            (?<line>
                \d+
            )
            \)

            \s*
            :
            \s*

            (?<error>
                # some errors include the word `fatal' and others don't,
                # though they all seem to be equally fatal.
                (?:fatal\s)?
                \Qerror C\E
                \d+
                .+
            )

            \z
        )

        # add more compilers here as needed

    }xms,

    # Continued lines from a compile failure.
    #
    # This matches the lines leading or following an initial compile fail message which
    # provide additional info about the failure.
    #
    # Examples:
    #   src/testlib/qtestresult_p.h:96: note: candidates are: static void QTestResult::addSkip(const char*, const char*, int)
    #
    #   In file included from mapsgl/map_p.h:59,
    #                    from mapsgl/map2d/map2d_p.h:55,
    #                    from mapsgl/map2d/map2d_p.cpp:41:
    #
    # Captures: nothing
    #
    # Caveats:
    #   Has false positives.
    #   This is considered acceptable because this pattern is only intended
    #   to be used in a very narrow scope (it should be applied only to lines
    #   surrounding something which matches compile_fail).
    #
    compile_fail_continuation => qr{
        (?:
            \Q: note: \E
        )

        |

        (?:
            \A
            \s*
            (?:
                \QIn file included \E
                |
                \s+
            )
            from
            \s
            [^\s]+:\d+  # some/file.cpp:123
            [,:]        # , or : depending on whether it's the last line
            \s*
            \z
        )
    }xms,

    # Failure to link.
    #
    # Example:
    #   ld: library not found for -lQtMultimediaKit
    #
    # Captures:
    #   linker  -   the linker command (e.g. "ld") (if any)
    #   error   -   text of the error message ("library not found for -lQtMultimediaKit")
    #   lib     -   the relevant library or object (if any)
    #
    linker_fail => qr{
        (?:

            \A

            (?<linker>
                ld              # basename only
                |
                /[^\s]+/ld      # full path
            )

            :
            \s

            (?<error>
                (?:
                    (?:
                        \Qlibrary not found for \E
                        |
                        \Qcannot find \E
                    )
                    (?<lib>
                        [\-\w]+
                    )
                )

                |

                \Qsymbol(s) not found\E

                # add others as discovered
            )

            \z
        )

        |

        (?:
            # `Undefined symbols' error message doesn't contain the linker name
            # in the error message.  Therefore, there is a risk of false positives
            # here (considered acceptable).
            #
            # Whole block of text looks like this, the lines after "Undefined symbols"
            # can be caught by linker_fail_continuation:
            #
            #  Undefined symbols:
            #   "v8::internal::NativesCollection<(v8::internal::NativeType)0>::GetScriptSource(int)", referenced from:
            #       v8::internal::Bootstrapper::NativesSourceLookup(int)  in bootstrapper.o
            #       v8::internal::Bootstrapper::NativesSourceLookup(int)  in bootstrapper.o
            #       v8::internal::Deserializer::ReadChunk(v8::internal::Object**, v8::internal::Object**, int, unsigned char*)in serialize.o
            #
            \A
            \s*
            (?<error>
                \QUndefined symbols:\E
            )
            \s*
            \z
        )
    }xms,

    # Line continuing a linker error message previously extracted.
    #
    # For example, in this whole block of text:
    #  Undefined symbols:
    #   "v8::internal::NativesCollection<(v8::internal::NativeType)0>::GetScriptSource(int)", referenced from:
    #       v8::internal::Bootstrapper::NativesSourceLookup(int)  in bootstrapper.o
    #       v8::internal::Bootstrapper::NativesSourceLookup(int)  in bootstrapper.o
    #       v8::internal::Deserializer::ReadChunk(v8::internal::Object**, v8::internal::Object**, int, unsigned char*)in serialize.o
    #
    # ... the lines following `Undefined symbols' can be extracted by this pattern.
    #
    # Captures: nothing
    #
    # Caveats:
    #   Like the similar compile_fail_continuation, has false positives,
    #   so it should only be used in a narrow context (if you already "know" the
    #   line has a high chance of being related to linker errors).
    #
    linker_fail_continuation => qr{
        (?:
            \Q, referenced from:\E
        )

        |

        (?:
            in [ ] [^ ]+\.o\b   # referring to a particular foo.o file
        )

        # add others as discovered
    }xms,

    # Line indicating a library is being linked.
    # This is used to keep track of which libraries have been built, to
    # give extra information in the case of errors relating to libraries.
    #
    # Examples:
    #   g++ (...) -o libQtMultimediaKit.so.5.0.0
    #   linking ../../lib/libQtCore.so.5.0.0
    #
    # Captures:
    #   lib     -   the library name (exactly as printed - i.e. may or may
    #               not be absolute, relative, basename ...)
    #
    # Caveats:
    #   This pattern is fairly narrow in scope and won't match all cases.
    #   This is considered acceptable as long as the info is only used
    #   to provide additional hints.  In other words, if this pattern
    #   matches, you can be fairly sure that a library was built; if it
    #   doesn't match, you shouldn't assume the library wasn't built.
    #
    linked_lib  =>  qr{
        \A

        (?:
            # non-silent mode, with gcc
            (?: gcc | g\+\+ )
            .+

            -o
            \s

            (?<lib>
                lib [^\.]+ \. # name always starts with libSomething.

                (?:
                    so        # linux: libQtCore.so.5.0.0
                    |
                    \d        # mac:   libQtCore.5.0.0.dylib
                )

                [^\s]+
            )
        )

        |

        (?:
            # silent mode, linking path/to/libWhatever.so
            linking

            \s

            (?<lib>
                [^\s]+

                (?:
                    \.so
                    |
                    \.dylib     # must contain at least one .so or .dylib to be a library
                )

                [^\s]+
            )

            \z
        )
    }xms,

    # Info about some pulse property.
    #
    # Note that these lines come from our pulseconfig/test.pl script,
    # and not from Pulse itself.  Pulse itself does not put the values
    # of properties directly into the build logs.
    #
    # Example:
    #
    #  PULSE_STAGE='linux-g++-32 Ubuntu 10.04 x86'
    #
    # Captures:
    #   property    -   the property name (all in uppercase and _ instead of .,
    #                   e.g. QT_TESTS_ENABLED rather than qt.tests.enabled)
    #   value       -   the value of the property
    #
    pulse_property => qr{
        \A

        # Windows-only starts with cmd-style `set '
        (?: set \s )?

        PULSE_

        (?<property>
            [^=]+
        )

        =

        # value may or may not be quoted
        (?:
            '
            (?<value>
                [^']+
            )
            '

            |

            (?<value>
                [^'].+
            )
        )

        \z
    }xms,

    # If matched, indicates that the top-level test script is running in `forcesuccess' mode,
    # meaning that all failures should be discarded.
    #
    # Example:
    #  Normally I would now fail.  However, `forcesuccess' was set in C:/test/recipes/129373577/base/_pulseconfig/projects/Qt_Modules_Continuous_Integration/stages/win32-msvc2010_Windows_7/forcesuccess.
    #
    # Captures: nothing
    #
    forcesuccess => qr{
        \A
        \QNormally I would now fail.  However, `forcesuccess' was set\E
    }xms,

    # The line where execution of an autotest begins.
    #
    # Example:
    #   make[3]: Entering directory `/home/qt/.pulse2-agent/data/recipes/129375783/base/qt/qtsystems/tests/auto/common'
    #   /home/qt/.pulse2-agent/data/recipes/129371992/base/_qtqa_latest/scripts/generic/testrunner.pl --timeout 900 --tee-logs /home/qt/.pulse2-agent/data/recipes/129371992/base/_artifacts/test-logs --plugin core --plugin flaky -- ./tst_qhostinfo
    #
    # Captures:
    #   name    -   basename of autotest (e.g. tst_foobar, sys_quux)
    #
    # Caveats:
    #   Depends on usage of testrunner.pl or special output from make.
    #   So, a little prone to error.
    #
    autotest_begin => qr{
        \A

        (?:

            .*? scripts[/\\]generic[/\\]testrunner\.pl

            .*?         # all the arguments to testrunner.pl
            [ ]--[ ]    # end of the arguments to testrunner.pl
            [^\s]+?     # path up to the last directory separator
            [/\\]       # the last directory separator
            (?<name>
                [^\s]+  # basename of the test
            )
        )

        |

        (?:
            # if testrunner is not used, the best we can do is to see when `make'
            # says it is entering a directory

            [gn]?make
            \[ \d+ \]
            :
            \s
            Entering[ ]directory[ ]

            `
            [^']+?                  # path up to the last /
            /                       # last /
            (?<name>
                [^/']+              # name of directory containing test
            )
            '
        )
    }xms,

    # Indicator that an autotest was flaky.
    #
    autotest_flaky => qr{
        \A
        \QQtQA::App::TestRunner: the test seems to be flaky\E
    }xms,
);

sub new
{
    my ($class) = @_;

    my $self = bless {}, $class;
    return $self;
}

sub run
{
    my ($self, @args) = @_;

    $self->set_options_from_args( @args );

    my @log_lines = $self->read_file( );

    # We pass through the log twice.
    # The first pass determines what caused the build to fail (if anything) ...
    my $fail = $self->identify_failures(
        lines   =>  \@log_lines,
    );

    if ($self->{ debug }) {
        print STDERR Data::Dumper->Dump([ $fail ], [ 'fail' ]);
    }

    # The second pass extracts and prints the messages which relate to the failure reason.
    $self->extract_and_output(
        lines   =>  \@log_lines,
        fail    =>  $fail,
    );

    return;
}

# Set various parts of $self based on command-line @args.
# Dies if there is a problem.
sub set_options_from_args
{
    my ($self, @args) = @_;

    GetOptionsFromArray( \@args,
        'help'          =>  sub { pod2usage(0) },
        'debug'         =>  \$self->{ debug },
        'summarize'     =>  \$self->{ summarize },
    ) || pod2usage(1);

    # Should be exactly one argument left - the filename.
    if (@args > 1) {
        print STDERR "Too many arguments: @args\n";
        pod2usage(2);
    }
    if (@args < 1) {
        print STDERR "Not enough arguments!  I need the filename of the log to parse.\n";
        pod2usage(2);
    }

    $self->{ file } = shift @args;

    return;
}

# Given a raw log line, returns a normalized form of that line; for example:
#  - strips Pulse-format timestamps
#  - trims trailing whitespace
#
# The purpose of this is to format lines in such a way that regular expressions
# do not need to be written to explicitly handle things which may or may not
# be in the logs; e.g. the Pulse timestamps.
sub normalize_line
{
    my ($self, $line) = @_;

    $line =~ s/$RE{ pulse_timestamp }//;

    # Note: don't use Text::Trim here, it's surprisingly slow.
    $line =~ s/\s+\z//;

    return $line;
}

sub read_file
{
    my ($self) = @_;

    my $file = $self->{ file };

    my @lines;

    if ($file =~ m{://} && ! -e $file) {
        # We've guessed that the user passed a URL
        # (note it is technically possible to have a file named e.g.
        # http://example.com/foo.html on local disk).
        #
        # Work around a silly File::Fetch behavior.
        # File::Fetch breaks if the URL ends with a `/'.
        # It croaks with: No 'file' specified
        # ...because it requires the URL to have a "file" component for
        # some reason.
        #
        # Note that we can't 100% guarantee that silently removing this
        # doesn't change the result :(
        $file =~ s{/$}{};
        my $ff = File::Fetch->new( uri => $file );

        local $File::Fetch::WARN = 0;   # do not warn about insignificant things

        my $text;
        $ff->fetch( to => \$text ) || die "fetch $file: ".$ff->error( );

        @lines = split( qr{\n}, $text );
    }
    else {
        # normal read from disk
        @lines = File::Slurp::read_file( $file );
    }

    # normalize before returning
    @lines = map { $self->normalize_line($_) } @lines;

    return @lines;
}

sub identify_failures
{
    my ($self, %args) = @_;

    my $out = {};

    # While we are reading the log relating to a `make check' fail,
    # this holds info about the failure.
    my $make_check_fail;
    # The max amount of line's we're willing to read before giving up
    # (quite large, since autotests can have large logs ...)
    Readonly my $MAKE_CHECK_FAIL_MAX_LINES => 5000;

    # We are trying to identify the reasons why this build failed.
    # We start from the end of the log and move backwards, since we're interested in what caused
    # the build to terminate.
    foreach my $line (reverse @{$args{ lines }}) {

        # reading a test log?
        if ($make_check_fail) {
            # are we done?
            if ($line =~ $RE{ autotest_begin }) {
                push @{$out->{ autotest_fail }}, {
                    name    =>  $+{ name },
                    details =>  $make_check_fail->{ details },
                    flaky   =>  $make_check_fail->{ flaky },
                };
                undef $make_check_fail;
                next;
            }

            # no, we're not done.
            # shall we give up?
            if (++$make_check_fail->{ lines } > $MAKE_CHECK_FAIL_MAX_LINES) {
                if ($self->{ debug }) {
                    print STDERR "giving up on reading `make check' details, too many lines.\n";
                }
                undef $make_check_fail;
            }

            # no, we're not giving up.
            else {
                $make_check_fail->{ details } = "$line\n" . $make_check_fail->{ details };

                if ($line =~ $RE{ autotest_flaky }) {
                    $make_check_fail->{ flaky } = $line;
                }

                next;
            }
        }

        # qtqa script failed?
        #
        # It's useful to save the name of the script which we were running,
        # to customize the output in some cases.
        #
        if ($line =~ $RE{ qtqa_script_fail }) {
            $out->{ qtqa_script }      = $+{ qtqa_script };
            $out->{ qtqa_script_fail } = $line;
        }

        # make tool failed?
        #
        if ($line =~ $RE{ make_fail }) {
            $out->{ make_fail } = $line;

            my $target = $+{ target };

            # If we're running qtmod_test.pl, try to determine specifically which module
            # failed to compile
            if ($out->{ qtqa_script } =~ m{qtmod_test\.pl}i) {
                if ($target =~ m{\A module-(q[^\-]+)}xms) {
                    $out->{ qtmodule } = $1;
                }
            }

            if ($target eq 'check') {
                $out->{ make_check_fail } = $line;

                # start reading the details of the failure.
                $make_check_fail = {
                    details => q{},
                };
            }

            $out->{ significant_lines }{ $line } = 1;
        }

        # compiler failed?
        #
        elsif ($line =~ $RE{ compile_fail }) {
            $out->{ compile_fail }                       = $line;
            $out->{ compile_fail_sources }{ $+{ file } } = $line;

            if ($out->{ qtmodule }) {
                $out->{ compile_fail_qtmodule } = $out->{ qtmodule };
            }

            $out->{ significant_lines }{ $line } = 1;
        }

        # linking failed?
        #
        elsif ($line =~ $RE{ linker_fail }) {
            my $lib = $+{ lib };

            $out->{ linker_fail } = $line;

            if ($out->{ qtmodule }) {
                $out->{ linker_fail_qtmodule } = $out->{ qtmodule };
            }

            if ($lib) {
                $out->{ linker_fail_lib }{ $lib } = $line;

                # Did the linker refer to a library which was created _later_ in the build?
                # (remember that we're parsing the log backwards)
                $lib =~ s{\A-l}{lib};  # -lQtCore -> libQtCore

                my $linked_lib = $out->{ linked_libs }{ $lib };
                if ($linked_lib) {
                    $out->{ linker_attempted_to_link_too_early }{ $lib } = 1;

                    # Also mark the line doing the linking as "significant" to show that
                    # the lib was linked in the wrong order
                    $out->{ significant_lines }{ $linked_lib } = 1;
                }
            }

            $out->{ significant_lines }{ $line } = 1;
        }

        # linking succeeded?  If so, store the built lib name for future reference
        #
        elsif ($line =~ $RE{ linked_lib }) {
            my ($lib, undef, undef) = fileparse( $+{ lib }, qr{\..+$} );

            $out->{ linked_libs }{ $lib } = $line;
        }

        # Pulse config problem?
        elsif ($line =~ $RE{ pulse_config_error }) {
            $out->{ pulse_config_error } = $line;
            $out->{ significant_lines }{ $line } = 1;
        }

        # Badly understood glitchy behavior?
        elsif ($line =~ $RE{ glitch }) {
            $out->{ glitch } = $line;
            $out->{ significant_lines }{ $line } = 1;
        }

        # Extract some possibly useful info about the pulse properties
        #
        elsif ($line =~ $RE{ pulse_property })
        {
            $out->{ pulse_property }{ $+{ property } } = $+{ value };
        }

        # Were we operating in `forcesuccess' mode?
        # If so, (almost) nothing else should be able to cause a failure ...
        #
        elsif ($line =~ $RE{ forcesuccess })
        {
            $out->{ forcesuccess } = 1;
        }
    }

    return $out;
}

sub output_autotest_fail
{
    my ($self, %args) = @_;

    my $fail   = $args{ fail };
    my $indent = $args{ indent };

    foreach my $autotest (@{ $fail->{ autotest_fail }} ) {
        my @lines = split( /\n/, $autotest->{ details } );
        print $indent . join( "\n$indent", @lines ) . "\n\n";
    }

    return;
}

sub extract_and_output
{
    my ($self, %args) = @_;

    my $fail  = $args{ fail };
    my @lines = @{$args{ lines }};

    if (!$fail || ref($fail) ne 'HASH' || !%{$fail}) {
        # No idea about the failure ...
        return;
    }

    if ($fail->{ forcesuccess }) {
        # We may have "failed", but we were operating in forcesuccess mode,
        # so the failure was (or should have been) discarded
        return;
    }

    # Buffer of recent lines, in case we need to look backwards.
    # Only keeps unprinted lines, and is cleared whenever something is printed.
    #
    # The value selected for $RECENT_MAX has some effects other than memory usage;
    # for example, if a file main.cpp fails to compile, then any previous
    # messages relating to main.cpp will be printed, up to a maximum distance
    # of $RECENT_MAX from the line where the error occurred.
    #
    # This means that increasing $RECENT_MAX increases the chance of false positives,
    # and decreasing it increases the chance of losing some valuable info.
    # The correct value to use is linked somewhat to the `-j' option used in builds
    # (consider: if we compile up to 30 source files simultaneously, then there
    # may be ~30 simultaneously interleaved streams at any one time).
    #
    my @recent = ();
    Readonly my $RECENT_MAX => 60;

    my $indent = q{};
    my @continuation_patterns = ();

    if ($self->{ summarize }) {
        $self->output_summary( $fail );
        $indent = "  ";
    }

    # Output any autotest failures first.
    # FIXME: outputting these first can mean that an autotest failure is printed
    # earlier than some other extracted message, even if in reality they appeared
    # in the opposite order.  Should we care about this?  Or is this a better
    # way to do it?
    if ($fail->{ autotest_fail }) {
        $self->output_autotest_fail(
            fail    =>  $fail,
            indent  =>  $indent,
        );
    }

    # Mark a line as significant and print it.
    #
    # Parameters:
    #  $line           -   the line to consider significant (and print)
    #  @continuations  -   zero or more regular expressions which, if matched,
    #                      will be considered a continuation of this significant
    #                      message (e.g. for compile failures spanning multiple
    #                      lines)
    #
    my $line_is_significant = sub {
        my ($line, @continuations) = @_;
        push @continuation_patterns, @continuations;

        # Before we print this significant line, see if any of the previous lines
        # are significant, according to @continuations.
        foreach my $recent_line (@recent) {
            if ( any { $recent_line =~ $_ } @continuation_patterns ) {
                print "$indent$recent_line\n";
            }
        }

        print "$indent$line\n";
        @recent = ();
    };


    while (@lines) {

        # keep no more than $RECENT_MAX lines in memory.
        while (scalar(@recent) > $RECENT_MAX) {
            shift @recent;
        }

        my $line = shift @lines;

        # Compilation failure?
        if ($fail->{ compile_fail } && $line =~ $RE{ compile_fail }) {
            # When extracting any further messages relating to this error, we look for
            # the "generic" continuation patterns ...
            my @continuation_patterns = ($RE{ compile_fail_continuation });

            # ... and, if we could identify the file at fault, we look for messages relating
            # to this specific file.
            if (my $file = $+{ file }) {
                push @continuation_patterns, qr{(?:\b|\A) \Q$file\E (?:\b|\z)}xms;
            }

            $line_is_significant->( $line, @continuation_patterns );

            next;
        }

        # Linker failure?
        if ($fail->{ linker_fail } && $line =~ $RE{ linker_fail }) {
            $line_is_significant->( $line, $RE{ linker_fail_continuation } );
            next;
        }

        # Have we explicitly stored this as a significant line already?
        # Note, this must come after the more specific checks, since those may add
        # specific continuations.
        if ($fail->{ significant_lines }{ $line }) {
            $line_is_significant->( $line );
            next;
        }

        #=============== KEEP THIS AT THE END OF THE LOOP =========================================
        #
        # Any continuations of multiple-line error messages?
        #
        if ( any { $line =~ $_ } @continuation_patterns ) {
            $line_is_significant->( $line );
            next;
        }

        # Nope, no error messages in progress.
        @continuation_patterns = ();
        push @recent, $line;
    }

    return;
}

sub output_summary
{
    my ($self, $fail) = @_;

    my $summary;

    # These failure conditions need to be listed in order from lowest
    # to highest precedence.  e.g. if we know that:
    #
    #  - qtmod_test.pl failed, because:
    #    - make failed, because:
    #      - gcc failed on qxyz.cpp
    #
    # ...then we only want to report the gcc failure - the rest is just noise.

    # test script failed and there are no further details;
    # we omit this message, because it will probably only cause confusion.
    # If people see this message, they'll probably conclude that the test
    # script is buggy - actually, we just couldn't extract any interesting
    # information, so we may as well remain silent.
    #
    if (0 && $fail->{ qtqa_script_fail }) {
        $summary = 'The test script '.$fail->{ qtqa_script }.' failed :(';
    }

    if ($fail->{ make_fail }) {
        $summary = q{`make' failed :(};
    }

    if ($fail->{ make_check_fail }) {
        $summary = q{autotests failed :(};
    }

    if ($fail->{ autotest_fail }) {
        my @autotest_fail = @{ $fail->{ autotest_fail } };
        my @flaky         = grep { $_->{ flaky } } @autotest_fail;

        if (@autotest_fail == 1) {
            $summary = q{Autotest `} . $autotest_fail[0]->{ name } . q{' failed};
        }

        elsif (@autotest_fail <= 5) {
            my @fail_names = map { q{`}.$_->{ name }.q{'} } @autotest_fail;
            @fail_names = sort @fail_names;

            my $fail_names_str = WORDLIST( @fail_names );

            # Example: autotests tst_qstring, tst_qwidget and tst_qfiledialog failed
            $summary = "Autotests $fail_names_str failed";
        }

        else {
            # too many to list (the details will still be given in the body)
            $summary = num2en( scalar(@autotest_fail) ) . q{ autotests failed};
        }

        # do we know the stage name?  (i.e. the test configuration)
        if ($fail->{ pulse_property }{ STAGE }) {
            $summary .= " for $fail->{ pulse_property }{ STAGE }";
        }

        $summary .= q{ :(};

        # any flaky tests?
        if (@flaky) {

            $summary .= qq{\n\n};

            my $tests_were;
            if (@autotest_fail == 1) {
                $tests_were = q{The test was};
            }
            elsif (@flaky == @autotest_fail) {
                $tests_were = q{The tests were};
            }
            else {
                $tests_were = q{Some (not all) of the tests were};
            }

            $summary .= qq{$tests_were determined to be flaky, meaning results were not }
                       . q{consistent across multiple runs.  This might make the problem }
                       . q{difficult to reproduce.  Also, flaky failures might or might not be }
                       . q{related to any recent changes in the source code.};
        }
    }

    # In the vernacular, "compile" is generally understood to also include linking.
    # We will treat compilation and linking the same for the purpose of summarizing.
    my $compile_fail
        = $fail->{ compile_fail }
       // $fail->{ linker_fail };
    my $compile_fail_qtmodule
        = $fail->{ compile_fail_qtmodule }
       // $fail->{ linker_fail_qtmodule };

    if ($compile_fail) {
        $summary = q{Compilation failed};

        # do we know the qtmodule in which compilation failed?
        if ($compile_fail_qtmodule) {
            $summary = "$compile_fail_qtmodule failed to compile";
        }

        # do we know the stage name?  (i.e. the test configuration)
        if ($fail->{ pulse_property }{ STAGE }) {
            $summary .= " for $fail->{ pulse_property }{ STAGE }";
        }

        $summary .= ' :(';

        # if this seems to be a dependency of the tested module, and not the module
        # we intended to test, give a hint about it
        if ($compile_fail_qtmodule) {
            my $tested_qtmodule = $fail->{ pulse_property }{ QT_GITMODULE };
            if ($tested_qtmodule && $compile_fail_qtmodule ne $tested_qtmodule) {
                $summary .= "\n\nWe were trying to test $tested_qtmodule.  "
                           ."One of the dependencies, $compile_fail_qtmodule, "
                           ."failed to compile.";
            }
        }

        # Check for the specific case where someone has attempted to link against
        # some library before it has been compiled.
        my $linked_too_early = $fail->{ linker_attempted_to_link_too_early };
        if ($linked_too_early) {
            my @libs = keys %{ $linked_too_early };

            Lingua::EN::Inflect::NUM( scalar(@libs) );

            my $project      = (@libs > 1) ? 'project(s)'   : 'project';
            my $that_lib_was = inflect 'PL(that) PL(library) PL(was)';
            my $lib          = WORDLIST( @libs, { conj => q{and/or} } );

            $summary .= "\n\nIt seems that some $project tried to link against $lib "
                       ."before $that_lib_was built."
                       ."\n\nThis could be caused by some missing dependencies in .pro file(s). "
                       ."If this is indeed the case, the error may be unstable, and will be "
                       ."easier to reproduce with a highly parallelized build.";
        }
    }

    # Pulse config problem?
    if ($fail->{ pulse_config_error }) {
        $summary = "It seems that there has been some misconfiguration of the Pulse CI tool, "
                  ."or some related CI infrastructure error. "
                  ."This is NOT the fault of the code under test!"
                  ."\n\nPlease contact $CI_CONTACT to resolve this problem.  Meanwhile, it may "
                  ."be worthwhile to attempt the build again.";
    }

    # Badly understood glitchy behavior?
    if ($fail->{ glitch }) {
        $summary = "An unexpected error occurred, most likely due to no fault in the tested "
                  ."code itself :("
                  ."\n\nPlease point $CI_CONTACT towards this problem.  Meanwhile, it may "
                  ."be worthwhile to attempt the build again.";
    }

    if ($summary) {
        # The summary is supposed to be human-readable text (not preformatted).
        # It's nice to wrap it.
        local $Text::Wrap::columns = 72;
        print wrap(q{}, q{}, $summary);

        # Blank lines after summary begin the (indented) body of the raw text
        print "\n\n";
    }

    return;
}

QtQA::App::ParseBuildLog->new( )->run( @ARGV ) if (!caller);

1;
