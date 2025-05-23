#!/usr/bin/env perl
# Copyright (C) 2021 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only WITH Qt-GPL-exception-1.0

use 5.010;
use strict;
use warnings;
use utf8;
use File::Find;
use File::Basename;
use File::Spec::Functions;
use Getopt::Long;
use Cwd qw( abs_path getcwd );
use List::Util qw( first );
use Pod::Usage;
use Test::More;
use JSON;
use Data::Dumper;

=head1 NAME

tst_licenses.pl - verify that source files contain valid license headers
                - verify that the source SBOM does not break license usage rules

=head1 SYNOPSIS

  perl ./tst_licenses.pl [OPTION]

  -f              Force use of find() to create the list of files instead of
                  git ls-files
  -h|?            Display this help
  -m [MODULENAME] Use the module name given instead of the base name of the
                  path specified by QT_MODULE_TO_TEST. This is useful if the
                  repository is checked out under a different directory.
  -t              Run the test despite the module being listed in
                  @excludedModules.
  -sbom [PATH]    path for the source SBOM to be tested
  -sbomonly       only check the provided source SBOM. Cannot be used without sbom option.

This test expects the environment variable QT_MODULE_TO_TEST to contain
the path to the Qt module to be tested.

=head1 DESCRIPTION

This test inspects all source files that are expected to have a valid Qt
license header and complains about any files that do not match the reference
headers. It can also check a source SBOM, making sure the licensing follows the
rules provided in licenseRule.json.

=cut

# These variables will contain regular expressions read from module
# specific configuration files.
my @moduleOptionalFiles;
my @moduleExcludedFiles;
my $optForceFind = 0;
my $optForceTest = 0;
my $optHelp = 0;
my $optModuleName;

# To trigger only source SBOM check.
my $optSourceSbomOnly = 0;

# These modules are not expected to contain any files that need
# Qt license headers.  They are entirely excluded from license checking.
my %excludedModules = (
    'qtrepotools' => [],
    'qttools' => ['6.2', '6.3'],
    'qtwebkit' => [],
    'test262' => [],
    '3rdparty' => [],
    'qtqa' => [],
    'pyside-setup' => ['5.6']
);

# These modules are excluded if the repository License Type is not SPDX
my @SPDXonlyModules = ( "qtwebengine" );

# If you add to the following lists of regexes, please
# make the patterns as specific as possible to avoid excluding more files
# than intended -- for directories, add the leading and trailing /, and
# for files, add the trailing $ and don't forget to escape the '.'.
# It is also helpful to document why files are excluded.

# The following regex patterns designate directories and files for which
# license headers are not checked at all.  Valid uses of this should be
# very rare - use %optionalFiles where possible.
my %excludedFiles = (
    "all"            => [
                          # Do not scan the header templates themselves
                          qr{^header\.[\w-]*$},
                          # Third-party license headers are handled upstream
                          qr{/3rdparty/},
                          qr{^3rdparty/},
                        ],
    "qtbase"         => [
                          # XML file from Khronos taken as-is, no control over the
                          # license and copyright syntax in this one. The checker
                          # gets confused with newer upstream versions, so skip.
                          qr{^src/gui/vulkan/vk\.xml$},
                          # File is generated and license info is in qt_attribution.json
                          qr{^src/gui/text/qfontsubset_agl.cpp$},
                        ],
    "qtwayland"      => [
                          # XML files for protocol (the license checker fails to
                          # recognize the copyright headers in these)
                          qr{^src/extensions/.+\.xml$},
                          qr{^config\.tests/wayland_scanner/scanner-test\.xml$},
                          qr{^examples/wayland/server-buffer/share-buffer\.xml$},
                          qr{^examples/wayland/custom-extension/protocol/custom\.xml$},
                          qr{^examples/wayland/custom-shell/protocol/example-shell\.xml$},
                        ],
    'pyside-setup'   => [ qr{^doc/changelogs/changes.*$},
                          qr{^examples/.*/ui_[a-zA-Z0-9_]+\.py$},
                          qr{^examples/.*/[a-zA-Z0-9_]+_rc\.py$},
                          qr{^examples/.*/rc_[a-zA-Z0-9_]+\.py$},
                          qr{^tools/.*/rc_[a-zA-Z0-9_]+\.py$},
                          qr{^sources/shiboken2/wizard/rc_[a-zA-Z0-9_]+\.py$},
                          qr{^sources/shiboken\d/.*\.1}, # Man pages (removed in 5.13)
                          qr{^sources/pyside2-tools/.*$},
                          qr{^sources/pyside\d/doc/.*\.py$} # Sphinx
                        ],
    'qtscxml'        => [
                          # Don't expect license headers in patch files
                          qr{^tools/qscxmlc/moc_patches/.*\.patch$},
                        ],
    'qttools'        => [
                          # Exclude QDoc test data and third party dependencies
                          qr{^src/qdoc/qdoc/tests/generatedoutput/expected_output/},
                          qr{^src/qdoc/qdoc/tests/validateqdocoutputfiles/testdata/},
                          qr{^src/qdoc/qdoc/src/qdoc/clang/AST/QualTypeNames.h},
                        ],
);

# The following regex patterns designate directories and files for which
# license headers are optional.  These files are permitted, but not required,
# to have a license header.  This script will check the correctness of any
# found license headers.
my %optionalFiles = (
    "all"            => [
                          # Test data can be exempted on a case-by-case basis by reviewers
                          # Automated testing should not block on any test files
                          qr{^tests/},
                          # change logs
                          qr{^dist/},
                          # Don't look at git's metadata
                          qr{^\.git/},
                          # These are qt5 third-party files.
                          qr{^gnuwin32/bin/data/glr\.c$},
                          qr{^gnuwin32/bin/data/yacc\.c$},
                          qr{^gnuwin32/share/bison/glr\.c$},
                          qr{^gnuwin32/share/bison/yacc\.c$},
                        ],
    "qtbase"         => [
                          # These are two-line wrappers around perl programs.
                          qr{^bin/elf2e32_qtwrapper\.bat$},
                          qr{^bin/patch_capabilities\.bat$},
                          # This is a 3rdparty file
                          qr{^src/network/kernel/qurltlds_p\.h$},
                          # These are generated files
                          qr{^src/corelib/global/qsimd_x86\.cpp$},
                          qr{^src/corelib/global/qsimd_x86_p\.h$},
                          # This is a 3rdparty file
                          qr{^src/gui/text/qharfbuzz_copy_p\.h$},
                          # These are 3rdparty files (copy of Khronos GL headers)
                          qr{^src/gui/opengl/qopenglext\.h$},
                          qr{^src/gui/opengl/qopengles2ext\.h$},
                          # these files are generated by the qdbusxml2cpp utility
                          qr{^src/plugins/platforminputcontexts/ibus/qibusinputcontextproxy\.cpp$},
                          qr{^src/plugins/platforminputcontexts/ibus/qibusinputcontextproxy\.h$},
                          qr{^src/plugins/platforminputcontexts/ibus/qibusproxy\.cpp$},
                          qr{^src/plugins/platforminputcontexts/ibus/qibusproxy\.h$},
                          qr{^src/plugins/platforminputcontexts/ibus/qibusproxyportal\.cpp$},
                          qr{^src/plugins/platforminputcontexts/ibus/qibusproxyportal\.h$},
                          # This is a list of classes generated by a script
                          qr{^src/tools/uic/qclass_lib_map\.h$},
                          # This is a copy of a Google Android tool with a fix.
                          qr{^mkspecs/features/data/android/dx\.bat$},
                          # This is a short source that is preprocessed only
                          qr{^mkspecs/features/data/macros\.cpp$},
                        ],
    "qtconnectivity" => [
                          # These directories contain generated files
                          qr{^src/bluetooth/bluez/},
                          qr{^src/nfc/neard/},
                        ],
    "qtdeclarative"  => [
                          # This is a single line forwarding header
                          qr{^src/qml/qml/v8/qv8debug_p\.h$},
                          # The following can be removed when the paths become obsolete:
                          qr{^src/declarative/qml/v8/qv8debug_p\.h$},
                        ],
    "qtdoc"          => [
                          # This is a 3rdparty file from KDE
                          qr{^doc/src/classes/phonon-api\.qdoc$},
                        ],
    "qttools"        => [
                          # This directory contain 3rdparty code
                          qr{^src/assistant/clucene/},
                          # This directory is a copy of a 3rdparty library
                          qr{^src/assistant/lib/fulltextsearch/},
                        ],
    'pyside-setup'   => [
                          qr{docs/conf.py},
                          qr{docs/make.bat},
                          qr{checklibs.py},
                          qr{ez_setup.py},
                          qr{popenasync.py},
                          qr{qtinfo.py},
                          qr{sources/patchelf/elf.h},
                          qr{utils.py}
                        ]
);

# Unless specifically excluded, all files matching these patterns are
# required to contain a license header.
my @mandatoryFiles=(
    qr{^configure$},
    qr{^bin/findtr$},
    qr{^bin/qtmodule-configtests$},
    qr{^bin/syncqt$},
    qr{\.h$},
    qr{\.cpp$},
    qr{\.c$},
    qr{\.mm$},
    qr{\.qml$},
    qr{\.qtt$},
    qr{\.fsh$},
    qr{\.vsh$},
    qr{\.qdoc$},
    qr{\.g$},
    qr{\.l$},
    qr{\.s$},
    qr{\.1$},
    qr{\.pl$},
    qr{\.pm$},
    qr{\.bat$},
    qr{\.py$},
    qr{\.sh$},
);

my $QT_MODULE_TO_TEST;
my $sourceSbomFileName;
my $moduleName;
my $repositoryLicenseType = 'legacy';

#
# These regexes define the expected patterns for the various parts of a
# license header.
#

# Each line of the license header will have a comment delimiter or literal
# string delimiter at the beginning of the line.
# Delimiters we're likely to see in Qt are '*' (C/C++/qdoc), ';' (assembly),
# '!' (SPARC assembly), ':' (batch files), '#' (shell/perl scripts),
# '--' (flex/bison), '.\"' (man page source), '\'' (visual basic script)
my $leadingDelimiter = qr/^(\s*[\*!;:#\-\.\\\"']+)/;

# These lines appear before the legal text in each license header.
# Where these are embedded in literals in a perl script, the @ in the
# contact email address will be escaped.
my @copyrightBlock = (
    qr/\s\bCopyright \(C\) 2[0-9][0-9][0-9].*/,
    qr/\s\bContact: http(s?):\/\/www\.(qt-project\.org|qt\.io)\/.*/,
    qr//,
    qr/\s\bThis file is (the|part of)\s*\b(\w*)\b.*/,
    qr//,
);

# These patterns represent the markers at the beginning and end of the
# license text. Where these are embedded in literals in scripts, the dollar
# signs may be escaped by one literal backslash (perl scripts) or two
# literal backslashes (for shell scripts).
my $licenseBeginMarker = qr/\s\\{0,2}\$QT_BEGIN_LICENSE:([A-Z0-9\-]*)\\{0,2}\$(.*)$/;
my $licenseEndMarker   = qr/\s\\{0,2}\$QT_END_LICENSE\\{0,2}\$/;

#
# The following subroutine loads the legal text from a reference header
# into the %licenseTexts map.
#
my %licenseTexts;   # Map from license name to the associated legal text
my %licenseFiles;   # Map from license name to the file defining it for reporting errors

sub gitBranch
{
    my $cmd = 'git "--git-dir=' . $QT_MODULE_TO_TEST . '/.git" branch';
    for my $line (split(/\n/, `$cmd`)) {
        chomp($line);
        return $1 if $line =~ /^\*\s+(.*)$/;
    }
    return '';
}

sub moduleBranch
{
    my $branch = $ENV{TESTED_MODULE_BRANCH_COIN};
    if (!defined($branch)) {
        $branch = gitBranch();
    }
    return $branch;
}

sub loadLicense {
    my $licenseFile = shift;

    # Read the sample license
    my $fileHandle;
    if (!open($fileHandle, '<', $licenseFile)) {
        fail("error: Cannot open license file: $licenseFile");
        return 0;
    }

    # Skip lines up to the QT_BEGIN_LICENSE marker.
    my $foundBeginMarker = 0;
    my $licenseType;
    my $beginDelimiter;
    my $endDelimiter;
    while (!$foundBeginMarker and $_ = <$fileHandle>) {
        chomp;
        if (/$leadingDelimiter$licenseBeginMarker/) {
            ($beginDelimiter,$licenseType,$endDelimiter) = ($1, $2, $3);
            $foundBeginMarker = 1;
        }
    }
    if (!$foundBeginMarker) {
        fail("error: $licenseFile has no QT_BEGIN_LICENSE marker");
        close $fileHandle;
        return 0;
    }

    # Strip the delimiters from lines up to the QT_END_LICENSE marker
    my $foundEndMarker = 0;
    my @licenseText;
    while (!$foundEndMarker and $_ = <$fileHandle>) {
        chomp;
        if (/$licenseEndMarker/) {
            $foundEndMarker = 1;
        } else {
            # Strip delimiters -- wrapping \Q and \E stops perl trying to treat the contents as a regex
            s/^\Q$beginDelimiter\E\s?//;
            s/\s*\Q$endDelimiter\E$//;
            push @licenseText, $_;
        }
    }
    close $fileHandle;
    if (!$foundEndMarker) {
        fail("error: $licenseFile has no QT_END_LICENSE marker");
        return 0;
    }

    $licenseTexts{$licenseType} = \@licenseText;
    $licenseFiles{$licenseType} = $licenseFile;
    return 1;
}

#
# Format error message about line mismatch
#

sub msgMismatch
{
    my ($filename, $actual, $reference, $licenseType, $line) = @_;
    return "error: Mismatch in license text in\n" . $filename . "\n"
        . "    Actual: '" . $actual . "'\n"
        . "  Expected: '" . $reference . "'\n"
        . '   License: ' . $licenseType . ' (' . $licenseFiles{$licenseType} . ':'
        . ($line + 1) . ')';
}

#
# Check whether the nominated file has a valid license header with legal text
# that matches one of the reference licenses.
#
sub checkLicense_legacy
{
    my $filename = shift;

    # Use short filename for reporting purposes (remove useless noise from failure message)
    my $shortfilename = $filename;
    $shortfilename =~ s/^\Q$QT_MODULE_TO_TEST\E\///;

    # Read in the whole file
    my $fileHandle;
    if (!open($fileHandle, '<', $filename)) {
        fail("error: Cannot open $filename");
        return 0;
    }
    my @lines = <$fileHandle>;
    close $fileHandle;

    # Convert from Mac OS9 format if needed (an OS9 file will look like
    # it's all on a single line due to lack of newlines).
    if ($#lines == 0) {
        @lines = split /\r/, $lines[0];
    }

    # Process the entire file, because it is possible that more than one
    # license header may be present, e.g. one at the top of the file and
    # one embedded in a printf for a utility that generates other files.
    my $matchedLicenses = 0;
    my $inLicenseText = 0;
    my $linesMatched = 0;
    my $currentLine = 0;
    my $beginDelimiter;
    my $endDelimiter;
    my $licenseType;
    my @text;

    while ($currentLine <= $#lines) {
        $_ = $lines[$currentLine];
        $currentLine++;

        chomp;
        s/\r$//;    # Strip DOS carriage return if present

        if ($linesMatched == 0) {
            # Can we match the first line of the copyright block?
            if (/$leadingDelimiter$copyrightBlock[0]/) {
                # Found first line of copyright block
                $beginDelimiter = $1;
                $linesMatched = 1;
            }
            # ...else this is not the beginning of copyright block -- do nothing
        } elsif ($linesMatched == 1 and /$leadingDelimiter$copyrightBlock[0]/ ) {
            # more copyright lines, do nothing
        } elsif ($linesMatched >= 1 and $linesMatched <= $#copyrightBlock) {
            if (/^\Q$beginDelimiter\E$copyrightBlock[$linesMatched]/) {
                # We matched the next line of the copyright block
                ++$linesMatched;
            } elsif ($copyrightBlock[$linesMatched] =~ m{\Q(?#optional)\E}) {
                # We didn't match, but it's OK - this part of the block is optional anyway.
                # We need to move on to the next pattern and rescan this line.
                ++$linesMatched;
                --$currentLine;
            }
            else {
                # If the line doesn't match the delimiter or the expected pattern,
                # don't error out (because other copyright messages are allowed),
                # just go back to looking for the beginning of a license block.
                $linesMatched = 0;
            }
        } elsif ($linesMatched == $#copyrightBlock + 1) {
            # The next line should contain the QT_BEGIN_LICENSE marker
            if (/^\Q$beginDelimiter\E$licenseBeginMarker/) {
                ($licenseType,$endDelimiter) = ($1, $2);
                # Verify that we have reference text for the license type
                if (!@{$licenseTexts{$licenseType} // []}) {
                    fail("error: No reference text for license type $licenseType in $shortfilename, line $currentLine");
                    return 0;
                }
                $inLicenseText = 1;
            } elsif (/^\Q$beginDelimiter\E/) {
                fail("error: QT_BEGIN_LICENSE does not follow Copyright block in $shortfilename, line $currentLine");
                return 0;
            } else {
                fail("error: $shortfilename has license header with inconsistent comment delimiters, line $currentLine");
                return 0;
            }
            $linesMatched++;
        } else {
            # The next line should contain either license text or the
            # QT_END_LICENSE marker.
            if (/^\Q$beginDelimiter\E$licenseEndMarker\Q$endDelimiter\E/) {
                # We've got all the license text, does it match the reference?
                my @referenceText = @{$licenseTexts{$licenseType}};
                my $oldLicenseType = $licenseType . '-OLD';
                my $hasOldText = exists($licenseTexts{$oldLicenseType});
                my @oldReferenceText;
                if ($hasOldText) {
                    @oldReferenceText = @{$licenseTexts{$oldLicenseType}};
                }
                my $useOldText = 0;
                if ($#text != $#referenceText) {
                    my $message = 'error: License text (' . $#text . ') and reference text ('
                        . $licenseType . ', ' . $#referenceText . ') have different number of lines in '
                        . $shortfilename;
                    if ($#oldReferenceText == 0) {
                        fail($message);
                        return 0;
                    } elsif ($#text != $#oldReferenceText) {
                        fail($message . ' and it does not match ' . $oldLicenseType . ', either (' . $#oldReferenceText . ')');
                        return 0;
                    } else {
                        print($message . '. Comparing to old license ' . $oldLicenseType . "\n");
                        $useOldText = 1;
                        @referenceText = @oldReferenceText;
                    }
                }

                my $n = 0;
                while ($n <= $#text) {
                    if ($text[$n] ne $referenceText[$n]) {
                        if (!$useOldText && $hasOldText) {
                            print('error: License text does not match ' . $licenseType . ' due to: '
                                  . msgMismatch($shortfilename, $text[$n], $referenceText[$n],
                                                $licenseType, $n) . "\n");
                            $useOldText = 1;
                            $n = -1; # restart comparing from the first line
                            @referenceText = @oldReferenceText;
                        } else {
                            fail(msgMismatch($shortfilename, $text[$n], $referenceText[$n],
                                 $useOldText ? $oldLicenseType : $licenseType, $n));
                            return 0;
                        }
                    }
                    $n++;
                }
                $matchedLicenses++;

                if ($useOldText) {
                    print('Old license ' . $oldLicenseType . ' being used for ' . $shortfilename . ".\n");
                }

                # Reset to begin searching for another license header
                $inLicenseText = 0;
                $linesMatched = 0;
                @text = ();
            } elsif (/^\Q$beginDelimiter\E\s?(.*)\Q$endDelimiter\E/) {
                # We've got a line of license text
                push @text, $1;
            } else {
                # We didn't recognize the line -- it mustn't be wrapped in the
                # same delimiters as the QT_BEGIN_LICENSE line.
                fail("$shortfilename has license header with inconsistent comment delimiters, line $currentLine");
                return 0;
            }
        }
    }

    # Were we in the middle of a license when we reached EOF?
    if ($inLicenseText) {
        fail("$shortfilename has QT_BEGIN_LICENSE, but no QT_END_LICENSE");
        return 0;
    }

    # Did we find any valid licenses?
    if ($matchedLicenses == 0 && $#lines > 2) {
        fail("error: $shortfilename does not appear to contain a license header");
        return 0;
    }

    # If we get here and matched at least one license then the file is OK.
    pass($shortfilename);
    return 1;
}


##########################################################################################
my $licenseRuleFileName = "licenseRule.json";
# Format of the license rule json file
# It's an array
# Each entry in the array corresponds to a set of rules
# There are sets of rules for files with certain endings.
# A file ending cannot be present in two "file_pattern_ending".
# A more constraining ending (like "special.txt") needs to appear in a "file_pattern_ending"
# located before the "file_pattern_ending" of a less constraining ending (like ".txt").
# [
# {
#   "file_pattern_ending" : [ "special.txt", ".end1"],
#   "location" : {
#       "src/" : {# the location (the directory or file) for which the spdx rule applies
#           "comment" : "blabla",   # this is optional
#           "file type" : "module", #corresponding file type in terms of quip18
#           "spdx"      : ["BDS3"]  # the authorized license expression(s)
#       },
#       "src/tools" : {             # the location is checked from the base of $QT_MODULE_TO_TEST.
#           "file type" : "tools",
#           "spdx"      : ["first_possibility", "second_possibility"]
#       }
#   }
# },
# {
#   "file_pattern_ending" : [ ".txt", "end2"],
#   "location" : {
#       "src/a_special_file.txt" : {
#           "comment" : "Exception",
#           "file type" : "module",
#           "spdx"      : ["BDS3"]
#       }
#   }
# },
# {
#   "location" : {
#       "src" : {
#           "comment" : "blabla",
#           "file type" : "module",
#           "spdx"      : ["BDS3"]
#       },
#       "src/tools" : {
#           "file type" : "tools",
#           "spdx"      : ["first_possibility", "second_possibility"]
#       }
#   }
# }
#]
# The last entry does NOT have a "file_pattern_ending"
# It's the set of rules for the files whose ending does not define the license rule.
# For those files the license rule only depends on the location of the file in
# the Qt module repository.

my $keyLocation = "location";
my $keyFileType = "file type";
my $keySpdxEpr = "spdx";
my $keyEnding = "file_pattern_ending";

my $licenseRules;
my @caseLocationList; # for each case, the list of dir and/or files is ordered

my $licenseRuleValid;
sub readLicenseRules
{
    my $filename = "$QT_MODULE_TO_TEST/$licenseRuleFileName";
    my $message = "";
    if (open (my $json_str, $filename)) {
      local $/ = undef;
      $licenseRules = decode_json <$json_str>;
      close($json_str);
    } else {
        $message = "$QT_MODULE_TO_TEST/$licenseRuleFileName does not exist.";
        $message .= " The license usage is not tested.\n";
        return $message;
    }

    #for debug
    #print Data::Dumper->Dump([$licenseRules], [qw(licenseRules)]);

    # this is to check that a given ending appears in only one list of endings
    my @arrayOfEndings = ();

    my @allCases = @$licenseRules;
    for (my $index = 0; $index < @allCases; $index++) {
        my $case = $allCases[$index];
        # ordering the location, to review the deeper one first in checkLicenseUsage
        @{$caseLocationList[$index]} = (sort { length $b <=> length $a }
                                        keys %{%$case{$keyLocation}});
        if (exists $case->{$keyEnding}) {
            push(@{$arrayOfEndings[$index]} , @{%$case{$keyEnding}});
        }

        if (!exists $case->{$keyEnding} and $#allCases > $index) {
            $message .= "warning: the default case with NO ". $keyEnding
                       ." needs to appear last.\n";
        }
    }

    #print Dumper @arrayOfEndings;
    # Make sure a file ending appears only once
    # and that the file endings are logically ordered
    foreach my $arrayIndex (0 .. ($#arrayOfEndings-1)) {
        foreach my $compArrayIndex ($arrayIndex+1 .. $#arrayOfEndings) {
            foreach my $end (@{$arrayOfEndings[$arrayIndex]}) {
                # If a file_pattern_ending entry matches a subsequent file_pattern_ending entry
                # the file is considered invalid
                # in other words, the more restrictive ending should appear in a
                # file_pattern_ending
                # that is first in the file
                # The following is invalid
                # {
                #   "file_pattern_ending" : ["doc"]
                #   ...
                # },
                # { "file_pattern_ending" : [".doc"]
                #  ...
                # }
                # two equivalent ending cannot appear in two different file_pattern_ending
                # The following is invalid
                # {
                #   "file_pattern_ending" : [".doc"]
                #   ...
                # },
                # { "file_pattern_ending" : [".doc"]
                #  ...
                # }
                # The following is valid
                # {
                #   "file_pattern_ending" : [".doc"]
                #   ...
                # },
                # { "file_pattern_ending" : ["doc"]
                #  ...
                # }
                foreach my $compEnd (@{$arrayOfEndings[$compArrayIndex]}) {
                    if ($compEnd eq $end) {
                       $message .= "warning: " . $compEnd
                                  . " appears in more than one rule set.\n";
                       last;
                    }
                    if ($compEnd =~ qr{\Q$end\E$}) {
                       $message .= "warning: " . $compEnd
                                  . " is more restrictive than " . $end . ".\n";
                       $message .= "The rule set for "
                                  . $compEnd . " needs to appear first.\n";
                    }
                }
            }
        }
    }

    if (length($message)) {
        $message .= "Please review " . $filename
                   . "\nwarning: The license usage is not tested.\n";
    }
    return $message;
}

# Map, one entry per file. Each file is associated to a string of licenses
my %filesLicensingInSourceSbom;
sub readReuseSourceSbom
{
    my $file;

    if (open(my $fh, '<:encoding(UTF-8)', $sourceSbomFileName)) {
      while (my $row = <$fh>) {
        chomp $row;

        if ( $row =~ s,^FileName:\s+./,,) {
            #skipping 3rdparty directories for the moment
            if ( $row =~ m,/3rdparty/, or $row =~ m,\\3rdparty\\,) {
                $file = "";
            } else {
               $file = $row;
            }
        }
        if ( $file and $row =~ s,^LicenseInfoInFile:\s+,,) {
            $filesLicensingInSourceSbom{$file} .= "$row ";
        }
      }
    } else {
        return 0;
    }
    print("$sourceSbomFileName successfully read.\n");
    return 1;
}

my $sbomErrorMessage;
sub checkLicenseUsageInSourceSbom
{
    # Logical information between licenses is lost in the source SBOM
    my $checkingWithoutLogic = "indeed";

    my $numErrorSbom = 0;
    $sbomErrorMessage = "wrong licensing in $sourceSbomFileName\n";
    foreach (sort keys %filesLicensingInSourceSbom) {
        my $shortfilename = $_;
        my $expression = $filesLicensingInSourceSbom{$shortfilename};
        $shortfilename =~ s,\\,/,g;
        if (!checkLicenseUsage($expression, $shortfilename, $checkingWithoutLogic)) {
            $numErrorSbom +=1;
        }
    }

    if ($numErrorSbom) {
        my $totalNumFileSourceSbom = keys %filesLicensingInSourceSbom;
        $sbomErrorMessage .= "Licensing does not follow the rules\n"
                           . "If the licensing is as should be, please add a rule exception "
                           . "in ".$licenseRuleFileName.",\n"
                           . "if not, please check the rules for the file type "
                           . "and correct the licensing in file or in the REUSE.toml\n";

        $sbomErrorMessage .= "$numErrorSbom/$totalNumFileSourceSbom files failing the license test in $sourceSbomFileName\n";
        fail($sbomErrorMessage);
        return 0;
    }

    pass($sourceSbomFileName);
    return 1;
}

sub checkLicenseUsage
{
    my $expression = shift;
    my $shortfilename = shift;
    my $checkingWithoutLogic = shift;
    my $index = 0;
    foreach my $case (@$licenseRules) {
        # Entering the default case, were no $keyEnding exists.
        # or
        # Entering a case if the file ending corresponds to one of the ending
        # in @{%$case{$keyEnding}}.
        # $keyEnding entries should be string so the regular expression is built using \Q and \E
        if (!exists $case->{$keyEnding} or
            first {$shortfilename =~ qr{\Q$_\E$}} @{%$case{$keyEnding}}) {
            # using the ordered list of location, to check deeper first
            foreach my $location (@{$caseLocationList[$index]}) {
                # location can be expressed as regular expression, for this reason no \Q \E here
                if ($shortfilename =~ qr{^$location}) {
                    # the SPDX expression should be entered in the json file as string,
                    # using \Q \E to convert to regexpr
                    # get the license rule spdx expression corresponding to the file name
                    my @license_expressions_in_rules = @{%$case{$keyLocation}->{$location}->{$keySpdxEpr}};
                    if ($checkingWithoutLogic) {
                        my @tagsInExpression = split(/\s+/, $expression);
                        foreach my $rule_expression (@license_expressions_in_rules) {
                            # in licenseRule.json, the license tag are always separated with a logic.
                            my @tagsInRuleExpression = split(/\s*OR\s*|\s*AND\s*|\s*WITH\s*/, $rule_expression);
                            my %sbom;
                            my %rule;
                            @sbom{ @tagsInExpression} = @tagsInExpression;
                            @rule{ @tagsInRuleExpression} = @tagsInRuleExpression;
                            delete @sbom{ @tagsInRuleExpression };
                            delete @rule{ @tagsInExpression};

                            my $extra_tag_in_sbom = keys %sbom;
                            my $missing_tag_in_sbom = keys %rule;
                            if (!$extra_tag_in_sbom and !$missing_tag_in_sbom) {
                                return 1;
                            }
                        }
                        my $type = %$case{$keyLocation}->{$location}->{$keyFileType};
                        $sbomErrorMessage .= "$shortfilename is under: $expression /  type: $type\n";
                        return 0;
                    } else {
                        if (!first {$expression eq $_} @license_expressions_in_rules) {
                            my $type = %$case{$keyLocation}->{$location}->{$keyFileType};
                            fail("error: $shortfilename is using wrong license SPDX expression \n"
                            . $expression . ". \n" . "Please check the rule for " . $type
                            . " in ".$licenseRuleFileName.".\n");
                            return 0;
                        }
                        return 1;
                    }
                }
            }
        }
        $index++;
    }

    fail("error: No license rule could be found for $shortfilename Please check "
         .$licenseRuleFileName.".\n");
    return 0;

}

sub checkSPDXLicenseIdentifier
{
    my $expression = shift;
    my $shortfilename = shift;
    $expression =~ s/[^:]+:\s*//;    # remove the "SPDX-License-Identifier: " prefix
    foreach (split(/\s+/, $expression)) {
        # Skip operators in the expression.
        if (/OR|AND|WITH|\(|\)/) {
            next;
        }

        # Check whether we know this license.
        if (!exists($licenseFiles{$_})) {
            fail("error: $shortfilename uses unknown license " . $_ . "\n");
            return 0;
        }
    }

    # only checking the license usage if a $licenseRuleFileName has been found
    # in $QT_MODULE_TO_TEST
    if (!$licenseRuleValid) {
        return 1;
    } else {
        return checkLicenseUsage($expression, $shortfilename);
    }
}

#
# Check whether the nominated file has a valid license header with legal text
# that matches one of the reference licenses.
#
sub checkLicense_SPDX
{
    my $filename = shift;

    # Use short filename for reporting purposes (remove useless noise from failure message)
    my $shortfilename = $filename;
    $shortfilename =~ s/^\Q$QT_MODULE_TO_TEST\E\///;

    # Read in the whole file
    my $fileHandle;
    if (!open($fileHandle, '<', $filename)) {
        fail("error: Cannot open $filename");
        return 0;
    }
    my @lines = <$fileHandle>;
    close $fileHandle;

    my $currentLine = 0;
    my $yearRegEx = qr/2[0-9][0-9][0-9]/;
    my $copyrightRegEx = qr/\b((?:Copyright \([cC]\) $yearRegEx.*)|(?:SPDX-FileCopyrightText: $yearRegEx.*))/;
    my $licenseIdRegEx = qr/\b((?:SPDX-License-Identifier:\s*[\(\)a-zA-Z0-9.\- ]+))/;

    my @copyrightTags = ();
    my @licenseIdentifiers = ();

    while ($currentLine <= $#lines) {
        $_ = $lines[$currentLine];
        $currentLine++;

        chomp;
        s/\r$//;    # Strip DOS carriage return if present

        if (/$copyrightRegEx/) {
            push @copyrightTags, $1;
        } elsif (/$licenseIdRegEx/) {
            push @licenseIdentifiers, $1;
        }
    }

    # Be more lenient towards empty or very small files.
    if ($#lines > 2) {
        # Did we find any copyright tags?
        if (!@copyrightTags) {
            fail("error: $shortfilename lacks an SPDX copyright tag");
            return;
        }

        # Did we find any licenses?
        if (!@licenseIdentifiers) {
            fail("error: $shortfilename does not appear to contain a license header");
            return;
        }

        # Checking only the first SPDX tag found
        if (!checkSPDXLicenseIdentifier($licenseIdentifiers[0], $shortfilename)) {
            return 0;
        }
    }

    pass($shortfilename);
    return 1;
}


#
# Decide whether the nominated file needs to be scanned for a license header.
# We will scan the file if it is obliged to have a license header (i.e. it is
# in one of the mandatory categories and isn't specifically excluded) or if
# it isn't mandatory, but we can see that it contains a QT_BEGIN_LICENSE marker.
#
sub shouldScan
{
    my $fullPath = shift;
    my $repositoryLicenseType = shift;

    # Is this an existing file?
    return 0 unless (-f $fullPath);

    # Strip the module path from the filename
    my $file = $fullPath;
    $file =~ s/^\Q$QT_MODULE_TO_TEST\E\///;

    # Does the filename match a mandatory pattern?
    my $isMandatory = first { $file =~ qr{$_} } @mandatoryFiles;

    # Is the file excluded or optional?
    my $isExcluded = first { $file =~ qr{$_} } @{$excludedFiles{"all"}}, @{$excludedFiles{$moduleName} || []}, @moduleExcludedFiles;
    my $isOptional = first { $file =~ qr{$_} } @{$optionalFiles{"all"}}, @{$optionalFiles{$moduleName} || []}, @moduleOptionalFiles;

    return 0 if ($isExcluded);

    # Skip opening the file if we already know we'll have to scan it later
    return 1 if ($isMandatory and !$isOptional);

    # The file is neither excluded nor mandatory - we only check it if it has a license marker
    my $fileHandle;
    if (!open ($fileHandle, '<', $fullPath)) {
        fail("Cannot open $fullPath");
        return 0;
    }
    my @lines = <$fileHandle>;
    close $fileHandle;

    if ($repositoryLicenseType eq "SPDX") {
        return grep(/SPDX-License-Identifier:/, @lines);
    }
    return grep(/QT_BEGIN_LICENSE/, @lines);
}

# This function reads line based regular expressions into a list.
# Comments are ignored.
sub readRegularExpressionsFromFile
{
    my $handle;
    my @regExList;

    if (open($handle, '<:encoding(UTF-8)', $_[0])) {
        while (my $row = <$handle>) {
            chomp $row;
            # Ignore comments
            if ($row !~ /^\s*#/ ) {
                push @regExList, qr{$row};
            }
        }
        close $handle;
    }

    return @regExList;
}

sub run
{
    #
    # Phase 1: Check prerequisites
    #

    # The QT_MODULE_TO_TEST environment variable must be set and must point to
    # a path that exists
    $QT_MODULE_TO_TEST=$ENV{QT_MODULE_TO_TEST};
    if (!$QT_MODULE_TO_TEST) {
        fail("Environment variable QT_MODULE_TO_TEST has not been set");
        return;
    }
    if (!-d $QT_MODULE_TO_TEST) {
        fail("Environment variable QT_MODULE_TO_TEST is set to \"$QT_MODULE_TO_TEST\", which does not exist");
        return;
    }
    $QT_MODULE_TO_TEST = abs_path($QT_MODULE_TO_TEST);

    # Get module name without the preceding path
    $moduleName = defined($optModuleName) ? $optModuleName : basename($QT_MODULE_TO_TEST);

    # Remove possible 'tqtc-' prefix from the module name
    substr($moduleName, 0, 5, "") if (index($moduleName,"tqtc-") == 0);

    # Check if we're dealing with a repository that has been ported to use SPDX.
    if (-d "$QT_MODULE_TO_TEST/LICENSES") {
        print "SPDX compliant repository detected.\n";
        $repositoryLicenseType = 'SPDX';
        # Store what's in the LICENSES directory.
        foreach (glob "$QT_MODULE_TO_TEST/LICENSES/*.txt") {
            my $id = basename($_);
            $id =~ s/\.txt$//;
            $licenseFiles{$id} = $_;
        }
    }

    if (grep(/$moduleName/, @SPDXonlyModules) && $repositoryLicenseType ne "SPDX") {
        plan skip_all => $moduleName .
        ' is excluded from license checks (because it is not SPDX compliant)';
        return;
    }

    # Skip the test (and return success) if we don't want to scan this module
    if ($optForceTest == 0) {
        my $excludedBranches = $excludedModules{$moduleName};
        if (defined($excludedBranches)) {
            if (scalar(@$excludedBranches) > 0) {
                my $branch = moduleBranch();
                my $quotedBranch = quotemeta($branch);
                if ($branch ne '' && grep(/$quotedBranch/, @$excludedBranches)) {
                    plan skip_all => 'Branch ' . $branch . ' of ' . $moduleName
                                     . ' is excluded from license checks';
                    return;
                }
            } else {
                plan skip_all => $moduleName . ' is excluded from license checks';
                return;
            }
        }
    }


    #
    # Phase 2: Read the reference license texts
    #
    # Load reference license headers from qtqa/tests/prebuild/license/templates/
    if ($repositoryLicenseType eq 'legacy') {
        my $current_dir = dirname(__FILE__);
        foreach (glob "$current_dir/templates/header.*") {
            loadLicense($_) || return;
        }

        # Also load all header.* files in the module's root, in case the module has special
        # requirements
        foreach (glob "$QT_MODULE_TO_TEST/header.*") {
            loadLicense($_) || return;
        }

        my $numLicenses = keys %licenseTexts;
        if ($numLicenses == 0) {
            fail("No reference licenses were found.");
            return;
        }
    } elsif ($repositoryLicenseType eq 'SPDX') {
        # Make sure that the repo does not contain extra license header files.
        my @repoLicenseHeaders = glob "$QT_MODULE_TO_TEST/header.*";
        if (@repoLicenseHeaders) {
            my $message = sprintf("A Qt repository ported to SPDX should not contain license header"
                                  . " templates:\n  %s", join("\n  ", @repoLicenseHeaders));
            fail($message);
            return;
        }
    }



    #
    # Phase 3: Decide which files we are going to scan.
    #
    @moduleOptionalFiles = readRegularExpressionsFromFile(catfile($QT_MODULE_TO_TEST, ".qt-license-check.optional"));
    @moduleExcludedFiles = readRegularExpressionsFromFile(catfile($QT_MODULE_TO_TEST, ".qt-license-check.exclude"));

    my @filesToScan;
    if (!$optSourceSbomOnly) {
        if (!$optForceFind && -d "$QT_MODULE_TO_TEST/.git") {
            # We're scanning a git repo, only examine files that git knows
            my $oldpwd = getcwd();
            if (!chdir $QT_MODULE_TO_TEST) {
                fail("Cannot change directory to $QT_MODULE_TO_TEST: $!");
                return;
            }
            my $currentpwd = getcwd();

            my @allFiles = `git ls-files`;

            if ($? != 0) {
                fail("There was a problem running 'git ls-files' on the repository: $currentpwd");
                return;
            }

            foreach (@allFiles) {
                chomp;
                shouldScan("$QT_MODULE_TO_TEST/$_", $repositoryLicenseType)
                        && push @filesToScan, "$QT_MODULE_TO_TEST/$_";
            }
            chdir $oldpwd;
        } else {
            # We're scanning something other than a git repo, examine all files
            find( sub{
                shouldScan($File::Find::name, $repositoryLicenseType)
                        && push @filesToScan, $File::Find::name;
            }, $QT_MODULE_TO_TEST);
        }

        # sort the files so we get predictable (and testable) output
        @filesToScan = sort @filesToScan;
    }
    #
    # Phase 4: Scan the files and Scan the source SBOM produced with reuse if present
    #
    my $readLicenseRulesMessage = readLicenseRules;
    $licenseRuleValid = !length($readLicenseRulesMessage);

    my $sourceSbom = 0;
    if ($sourceSbomFileName){
        if (!-e $sourceSbomFileName) {
            fail("Source SBOM is expected to be \"$sourceSbomFileName\", which does not exist");
            return;
        }

        $sourceSbomFileName = abs_path($sourceSbomFileName);
        if (!readReuseSourceSbom) {
            fail("error: source SBOM $sourceSbomFileName could not be read\n");
            return 0;
        }
        $sourceSbom = 1;
    }

    my $numFilesInSourceSbom = keys %filesLicensingInSourceSbom;
    # Checking the source SBOM is one single test.
    # because we don't want an 'ok' line for each source file properly licensed in the source SBOM
    my $numTests = $#filesToScan + $sourceSbom + 1;

    if ($numTests <= 0) {
        plan skip_all => "Module $moduleName appears to have no files that must be scanned";
    } else {
        plan tests => $numTests;#$#filesToScan + 1;
        my $checkLicense = \&checkLicense_legacy;
        if ($repositoryLicenseType eq 'SPDX') {
            $checkLicense = \&checkLicense_SPDX;
        }
        foreach ( @filesToScan ) {
            &$checkLicense($_);
        }
        if ($sourceSbom) {
            checkLicenseUsageInSourceSbom();
        }
        if (!$licenseRuleValid) {
            print("$readLicenseRulesMessage");
        }
    }
}

GetOptions('f' => \$optForceFind, "help|?" => \$optHelp, 'm:s' => \$optModuleName,
           't' => \$optForceTest,'sbom=s' => \$sourceSbomFileName, 'sbomonly' => \$optSourceSbomOnly) or pod2usage(2);
pod2usage("Error: -sbomonly must be used in association with -sbom") if ($optSourceSbomOnly and !$sourceSbomFileName);
pod2usage(0) if $optHelp;

run();
done_testing();
