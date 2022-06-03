# Copyright (C) 2021 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

param (
    [Parameter(Mandatory = $true)][string]$QtVersion = "dev",
    [Parameter(Mandatory = $true)][string]$MachineName = "UNKNOWN",
    [int]$BuildCores = 2,
    [switch]$Annotate,
    [string]$QtDeclarativeVersion = "",
    [string]$FlexBisonDir = "$PWD\flex_bison\"
)

Invoke-WebRequest -Uri http://download.qt.io/official_releases/jom/jom.zip -OutFile ./JOM.zip
Expand-Archive .\JOM.zip -DestinationPath ./JOM

$qmake = "$PSScriptRoot/../qtbase/bin/qmake.exe"
$vsLoc = $env:VS_DEV_TOOLS_PATH
$buildCommand = "$PSScriptRoot/JOM/jom.exe"
# Fallback to nmake if JOM doesn't exist or can't be execusted.
if (!(Test-Path $buildCommand) -or !(Get-Command $buildCommand -ErrorAction SilentlyContinue)) {
    $buildCommand = "nmake"
    echo "Falling back to system nmake"
} else {
    echo "Using JOM for compilation."
}

function make([string]$module) {
    $stopwatch = [system.diagnostics.stopwatch]::StartNew()
    # Use Incredibuild if possible.
    if (Get-Command "BuildConsole.exe" -ErrorAction SilentlyContinue) {
        BuildConsole /COMMAND="$buildCommand"
    } else {
        if ($buildCommand -eq "nmake"){
            set CL=/MP
            & $buildCommand
        } else {
            & $buildCommand -j $BuildCores
        }
    }
    echo "Build of $module took $([math]::Round($stopwatch.Elapsed.TotalSeconds,0)) seconds"
    $stopwatch.Stop()
    return
}

function checkoutQtModule([string]$module, [string]$version) {
    git clone https://code.qt.io/qt/$module
    cd $module
    git checkout $version
    git rev-parse HEAD > ([string]::Format("../{0}_{1}_sha1.txt", $module, $version))
    echo "Checked out $module at $(git rev-parse HEAD)"
    cd ..
}

function buildQtModule([string]$module, [string]$version, [int]$BuildCores) {
    checkoutQtModule $module $version
    cd $module
    if ($module -eq "qttools") {
        & $qmake
        cd src/windeployqt
        & $qmake
        make $module
        cd ../..
    }
    else {
        & $qmake
        make $module
    }
    cd ..
}

function compareSha1sAndAnnotate([string]$module, [string]$version) {
    if ((Get-Content ([string]::Format("../{0}_{1}_sha1.txt", $module, $version))) -eq (Get-Content ([string]::Format("{0}_{1}_sha1.txt", $module, $version)))) {
        Set-Variable -Name "new_sha1" -Value (Get-Content ([string]::Format("{0}_{1}_sha1.txt", $module, $version)))
        Set-Variable -Name "old_sha1" -Value (Get-Content ([string]::Format("../{0}_{1}_sha1.txt", $module, $version)))

        if ($new_sha1 -ne $old_sha1) {
            python qmlbenchrunner/annotate.py --title="$module update" --tag="$moduleUpdate" --text="Updated $module to $new_sha1 (previous was $old_sha1)" --branch="$version"
        }
    }

    if ((Get-Content ([string]::Format("{0}_{1}_sha1.txt", $module, $version)))) {
        cp ([string]::Format("{0}_{1}_sha1.txt", $module, $version)) ([string]::Format("../{0}_{1}_sha1.txt", $module, $version))
    }
}

Set-Variable -Name "branch_label" -Value ([string]::Format("{0}+{1}", $QtVersion, $QtDeclarativeVersion))
Set-Variable -Name "qtdeclarative_branch" -Value $QtDeclarativeVersion
if ($qtdeclarative_branch.length -le 0) {
    $qtdeclarative_branch = $QtVersion
    $branch_label = $QtVersion
}

echo "Using $QtVersion as base and $qtdeclarative_branch for qtdeclarative. Using $branch_label as label in database."

#Configure Windows environment for building. Default to VS2017
if (!($vsLoc) -or !(Test-Path $vsLoc)) {
    echo "Using default VS installation location"
    $vsLoc = "C:\Program Files (x86)\Microsoft Visual Studio\2017\BuildTools\Common7\Tools\"
    if (Get-Command "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\Common7\Tools\VsDevCmd.bat" -ErrorAction SilentlyContinue) {
        $vsLoc = "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\Common7\Tools\"
    }
}
[regex]$re = [regex]"\\([0-9]+)\\"
echo "Found VS $($re.Matches($vsLoc).Groups[1].Value) at $vsLoc"
pushd $vsLoc
cmd /c "VsDevCmd.bat&set" |
foreach {
    if ($_ -match "=") {
        $v = $_.split("="); set-item -force -path "ENV:\$($v[0])"  -value "$($v[1])"
    }
}

$env:Path += ";$FlexBisonDir"

popd
Write-Host "`nVisual Studio Command Prompt variables set." -ForegroundColor Yellow

# checkout and configure Qt Base
checkoutQtModule qtbase $QtVersion
cd qtbase

./configure -developer-build -nomake tests -nomake examples -release -opensource -confirm-license -no-warnings-are-errors -opengl desktop (&{If($env:EXTRA_CONFIGURE_ARGS) {$env:EXTRA_CONFIGURE_ARGS.split()}})
make "qtbase"
cd ..

# other modules
buildQtModule qtdeclarative $qtdeclarative_branch $BuildCores
buildQtModule qtquickcontrols $QtVersion $BuildCores
buildQtModule qtquickcontrols2 $QtVersion $BuildCores
buildQtModule qtgraphicaleffects $QtVersion $BuildCores
buildQtModule qttools $QtVersion $BuildCores

# qmlbench
git clone --progress https://code.qt.io/qt-labs/qmlbench.git
cd qmlbench

$qmlbenchBranch = "dev"

if ($QtVersion | Select-String -Pattern '^(v?6\.|dev)' -NotMatch) {
    # Qt6 introduces many breaking changes to qmlbench.
    # For qt 5.x, checkout branch 5.15
    $qmlbenchBranch = "5.15"
}

git checkout $qmlbenchBranch
git rev-parse HEAD > ../qmlbench_${qmlbenchBranch}_sha1.txt

& $qmake
make "qmlbench"
cd ../qtbase/bin
./windeployqt.exe --qmldir ..\..\qmlbench\benchmarks ..\..\qmlbench\src\release\qmlbench.exe
cd ../..

cd qmlbench

if ($env:BADTESTS) {
    $env:BADTESTS.split() | ForEach-Object {
        if (Test-Path $_) {
            echo "Deleting $_"
            Remove-Item $_ -Recurse -Force
        }
    }
}

src/release/qmlbench.exe --json --shell frame-count benchmarks/auto/creation/ benchmarks/auto/changes/ benchmarks/auto/js benchmarks/auto/animations benchmarks/auto/bindings > ../results.json
cd ..
echo Label: $branch_label
python qmlbenchrunner/run.py results.json $branch_label $MachineName

if ($Annotate) {
    compareSha1sAndAnnotate qtbase $QtVersion
    compareSha1sAndAnnotate qtdeclarative $QtVersion
    compareSha1sAndAnnotate qtquickcontrols $QtVersion
    compareSha1sAndAnnotate qtquickcontrols2 $QtVersion
    compareSha1sAndAnnotate qtgraphicaleffects $QtVersion
    compareSha1sAndAnnotate qmlbench $qmlbenchBranch
}
