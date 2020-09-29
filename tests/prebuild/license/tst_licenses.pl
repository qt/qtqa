#!/usr/bin/env perl
#############################################################################
##
## Copyright (C) 2017 The Qt Company Ltd.
## Contact: https://www.qt.io/licensing/
##
## This file is part of the test suite of the Qt Toolkit.
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

=head1 NAME

tst_licenses.pl - verify that source files contain valid license headers

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

This test expects the environment variable QT_MODULE_TO_TEST to contain
the path to the Qt module to be tested.

This test inspects all source files that are expected to have a valid Qt
license header and complains about any files that do not match the reference
headers.

=cut

# These variables will contain regular expressions read from module
# specific configuration files.
my @moduleOptionalFiles;
my @moduleExcludedFiles;
my $optForceFind = 0;
my $optForceTest = 0;
my $optHelp = 0;
my $optModuleName;

# These modules are not expected to contain any files that need
# Qt license headers.  They are entirely excluded from license checking.
my %excludedModules = (
    'qtrepotools' => [],
    'qtwebkit' => [],
    'test262' => [],
    'qtwebengine' => [],
    '3rdparty' => [],
    'qtqa' => [],
    'pyside-setup' => ['5.6']
);

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
                        ],
    "qtwayland"      => [
                          # XML files for protocol
                          qr{^src/extensions/.+\.xml$},
                          qr{^config\.tests/wayland_scanner/scanner-test\.xml$},
                          qr{^examples/wayland/server-buffer/share-buffer\.xml$},
                          qr{^examples/wayland/custom-extension/protocol/custom\.xml$},
                        ],
    'pyside-setup'   => [ qr{^examples/.*/ui_[a-zA-Z0-9_]+\.py$},
                          qr{^examples/.*/[a-zA-Z0-9_]+_rc\.py$},
                          qr{^examples/.*/rc_[a-zA-Z0-9_]+\.py$},
                          qr{^sources/shiboken2/.*\.1}, # Man pages (removed in 5.13)
                          qr{^sources/pyside2-tools/.*$},
                          qr{^sources/pyside2/doc/.*\.py$} # Sphinx
                        ]
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
                          # Third-party files are not expected to have a Qt license
                          qr{/3rdparty/},
                          qr{^3rdparty/},
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
                          qr{^src/corelib/io/qurltlds_p\.h$},
                          # This is a 3rdparty file
                          qr{^src/network/kernel/qurltlds_p\.h$},
                          # These are generated files
                          qr{^src/corelib/tools/qsimd_x86\.cpp$},
                          qr{^src/corelib/tools/qsimd_x86_p\.h$},
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
my $moduleName;

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

sub loadLicense {
    my $licenseFile = shift;

    # Read the sample license
    my $fileHandle;
    if (!open($fileHandle, '<', $licenseFile)) {
        fail("Cannot open license file: $licenseFile");
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
        fail("$licenseFile has no QT_BEGIN_LICENSE marker");
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
        fail("$licenseFile has no QT_END_LICENSE marker");
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
    return "Mismatch in license text in\n" . $filename . "\n"
        . "    Actual: '" . $actual . "'\n"
        . "  Expected: '" . $reference . "'\n"
        . '   License: ' . $licenseType . ' (' . $licenseFiles{$licenseType} . ':'
        . ($line + 1) . ')';
}

#
# Check whether the nominated file has a valid license header with legal text
# that matches one of the reference licenses.
#
sub checkLicense
{
    my $filename = shift;

    # Use short filename for reporting purposes (remove useless noise from failure message)
    my $shortfilename = $filename;
    $shortfilename =~ s/^\Q$QT_MODULE_TO_TEST\E\///;

    # Read in the whole file
    my $fileHandle;
    if (!open($fileHandle, '<', $filename)) {
        fail("Cannot open $filename");
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
                    fail("No reference text for license type $licenseType in $shortfilename, line $currentLine");
                    return 0;
                }
                $inLicenseText = 1;
            } elsif (/^\Q$beginDelimiter\E/) {
                fail("QT_BEGIN_LICENSE does not follow Copyright block in $shortfilename, line $currentLine");
                return 0;
            } else {
                fail("$shortfilename has license header with inconsistent comment delimiters, line $currentLine");
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
                    my $message = 'License text (' . $#text . ') and reference text ('
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
                            print('License text does not match ' . $licenseType . ' due to: '
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
        fail("$shortfilename does not appear to contain a license header");
        return 0;
    }

    # If we get here and matched at least one license then the file is OK.
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

    # Skip the test (and return success) if we don't want to scan this module

    if ($optForceTest == 0) {
        my $excludedBranches = $excludedModules{$moduleName};
        if (defined($excludedBranches)) {
            if (scalar(@$excludedBranches) > 0) {
                my $branch = gitBranch();
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
    my $current_dir = dirname(__FILE__);
    foreach (glob "$current_dir/templates/header.*") {
        loadLicense($_) || return;
    }

    # Also load all header.* files in the module's root, in case the module has special requirements
    foreach (glob "$QT_MODULE_TO_TEST/header.*") {
        loadLicense($_) || return;
    }

    my $numLicenses = keys %licenseTexts;
    if ($numLicenses == 0) {
        fail("No reference licenses were found.");
        return;
    }

    #
    # Phase 3: Decide which files we are going to scan.
    #
    @moduleOptionalFiles = readRegularExpressionsFromFile(catfile($QT_MODULE_TO_TEST, ".qt-license-check.optional"));
    @moduleExcludedFiles = readRegularExpressionsFromFile(catfile($QT_MODULE_TO_TEST, ".qt-license-check.exclude"));

    my @filesToScan;
    if (!$optForceFind && -d "$QT_MODULE_TO_TEST/.git") {
        # We're scanning a git repo, only examine files that git knows
        my $oldpwd = getcwd();
        if (!chdir $QT_MODULE_TO_TEST) {
            fail("Cannot change directory to $QT_MODULE_TO_TEST: $!");
            return;
        }

        my @allFiles = grep(!/\/3rdparty\//,`git ls-files`);

        if ($? != 0) {
            fail("There was a problem running 'git ls-files' on the repository");
            return;
        }

        foreach (@allFiles) {
            chomp;
            shouldScan("$QT_MODULE_TO_TEST/$_") && push @filesToScan, "$QT_MODULE_TO_TEST/$_";
        }
        chdir $oldpwd;
    } else {
        # We're scanning something other than a git repo, examine all files
        find( sub{
            shouldScan($File::Find::name) && push @filesToScan, $File::Find::name;
        }, $QT_MODULE_TO_TEST);
    }

    # sort the files so we get predictable (and testable) output
    @filesToScan = sort @filesToScan;

    #
    # Phase 4: Scan the files
    #
    my $numTests = $#filesToScan + 1;
    if ($numTests <= 0) {
        plan skip_all => "Module $moduleName appears to have no files that must be scanned";
    } else {
        plan tests => $#filesToScan + 1;
        foreach ( @filesToScan ) {
            checkLicense($_);
        }
    }
}

GetOptions('f' => \$optForceFind, "help|?" => \$optHelp, 'm:s' => \$optModuleName,
           't' => \$optForceTest) or pod2usage(2);
pod2usage(0) if $optHelp;

run();
done_testing();
