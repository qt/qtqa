#!/bin/sh
# Copyright (C) 2022 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only WITH Qt-GPL-exception-1.0

if [ "$#" -lt 2 ]; then
    echo "$0 - Generates reference files for b/c autotest"
    echo "Usage: $0 [module|qt=mod1,mod2,...|-all] [platform]"
    echo "Examples: $0 -all 5.1.0.macx-gcc-ppc32"
    echo "          $0 QtGui 5.0.0.linux-gcc-ia32"
    echo "          $0 qt=QtGui,QtQuick 5.0.0.linux-gcc-amd64"
    exit 1
fi

if [ "$1" = "-all" ]; then
    modules="QtConcurrent QtCore QtDBus QtDeclarative QtDesigner QtGui QtHelp QtMultimedia QtMultimediaWidgets QtNetwork QtOpenGL QtPositioning QtPrintSupport QtQml QtQuickParticles QtQuick QtQuickTest QtScript QtScriptTools QtSql QtSvg QtTest QtWebKit QtWebKitWidgets QtWidgets QtXmlPatterns QtXml"
else
    modules="$1"
fi

use_qt=""

case "$1" in
    qt=*) use_qt="yes"
    # split qt=foo,bar,baz into ["qt", "foo,bar,baz"]
    IFS="=" read -r -a split_qt <<-_EOF_
$1
_EOF_
    # split "foo,bar,baz" into ["foo", "bar", "baz"]
    IFS="," read -r -a qt_modules <<-_EOF_
${split_qt[1]}
_EOF_
;;
esac

GCC_MAJOR=`echo '__GNUC__' | gcc -E - | tail -1`

if [ $GCC_MAJOR -ge 8 ]; then
    DUMP_CMDLINE=-fdump-lang-class
else
    DUMP_CMDLINE=-fdump-class-hierarchy
fi

function remove_templates {
    # Remove template classes from the output
    perl -pi -e '$skip = 1 if (/^(Class|Vtable).*</);
        if ($skip) {
            $skip = 0 if (/^$/);
            $_ = "";
        }' $1
}

if [ "$use_qt" == "yes" ]; then
    for qt_module in "${qt_modules[@]}"; do
        echo -e "#include <$qt_module/$qt_module>\n" >> test.cpp
    done
    g++ -c -std=c++17 -I$QTDIR/include -DQT_NO_STL $DUMP_CMDLINE -fPIC test.cpp
    mv test.cpp*.class qt.$2.txt
    remove_templates qt.$2.txt
else
    for module in $modules; do
        echo "#include <$module/$module>" >test.cpp
        g++ -c -std=c++17 -I$QTDIR/include -DQT_NO_STL $DUMP_CMDLINE -fPIC test.cpp
        mv test.cpp*.class $module.$2.txt
        remove_templates "$module.$2.txt"
    done
fi
