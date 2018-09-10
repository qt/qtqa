#!/bin/sh
#############################################################################
##
## Copyright (C) 2017 The Qt Company Ltd.
## Contact: https://www.qt.io/licensing/
##
## This file is the build configuration utility of the Qt Toolkit.
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

if [ "$#" -lt 2 ]; then
    echo "$0 - Generates reference files for b/c autotest"
    echo "Usage: $0 [module|-all] [platform]"
    echo "Examples: $0 -all 5.1.0.macx-gcc-ppc32"
    echo "          $0 QtGui 5.0.0.linux-gcc-ia32"
    exit 1
fi

if [ "$1" = "-all" ]; then
    modules="QtConcurrent QtCore QtDBus QtDeclarative QtDesigner QtGui QtHelp QtMultimedia QtMultimediaWidgets QtNetwork QtOpenGL QtPositioning QtPrintSupport QtQml QtQuickParticles QtQuick QtQuickTest QtScript QtScriptTools QtSql QtSvg QtTest QtWebKit QtWebKitWidgets QtWidgets QtXmlPatterns QtXml"
else
    modules="$1"
fi

GCC_MAJOR=`echo '__GNUC__' | gcc -E - | tail -1`

if [ $GCC_MAJOR -ge 8 ]; then
    DUMP_CMDLINE=-fdump-lang-class
else
    DUMP_CMDLINE=-fdump-class-hierarchy
fi

for module in $modules; do
    echo "#include <$module/$module>" >test.cpp
    g++ -c -std=c++11 -I$QTDIR/include -DQT_NO_STL $DUMP_CMDLINE -fPIC test.cpp
    mv test.cpp*.class $module.$2.txt
    # Remove template classes from the output
    perl -pi -e '$skip = 1 if (/^(Class|Vtable).*</);
        if ($skip) {
            $skip = 0 if (/^$/);
            $_ = "";
        }' $module.$2.txt
done

