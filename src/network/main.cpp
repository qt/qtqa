// Copyright (C) 2024 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

//
//  W A R N I N G
//  -------------
//
// This file is not part of the Qt API.  It exists purely as an
// implementation detail.  This header file may change from version to
// version without notice, or even be removed.
//
// We mean it.
//

#include "networktest.h"
#include <QCoreApplication>
#include <QCommandLineParser>

int main(int argc, char *argv[])
{
    QCoreApplication a(argc, argv);
    QCoreApplication::setApplicationName("NetworkTest");
    QCoreApplication::setApplicationVersion("1.0");

    QCommandLineParser parser;
    parser.addVersionOption();
    parser.addHelpOption();
    const QCommandLineOption inputOption({"input-file", "i"},
                                         "JSON input file to parse", "jsonFile");
    const QCommandLineOption timeoutOption({"timeout", "to", "t"}, "Overall timeout in milliseconds", "timeout");
    const QCommandLineOption warnOnlyOption({"warn-only", "wo"}, "Just warn, exit 0 on error.");
    const QCommandLineOption verbosityOption({"verbosity", "d"}, NetworkTest::verbosityStrings().join("\n"), "verbosity");
    const QCommandLineOption copyOption({"copy-default-file", "o"},
                                        "Write a copy of the default file to the given path",
                                        "file");
    const QCommandLineOption showProgressOption({"show-progress", "p"}, "Show progress");

    parser.addOption(inputOption);
    parser.addOption(timeoutOption);
    parser.addOption(warnOnlyOption);
    parser.addOption(verbosityOption);
    parser.addOption(copyOption);
    parser.addOption(showProgressOption);
    parser.process(a);

    constexpr QLatin1StringView defaultFile(":/tests/DNSLookup.json");
    const QString input = parser.isSet(inputOption) ? parser.value(inputOption) : defaultFile;
    const int timeout = parser.value(timeoutOption).toInt();
    const bool warnOnly = parser.isSet(timeoutOption);
    const bool showProgress = parser.isSet(showProgressOption);

    NetworkTest::Verbosity verbosity = NetworkTest::Verbosity::Summary;
    if (parser.isSet(verbosityOption)) {
        bool ok;
        const QString vString = parser.value(verbosityOption);
        const int v = vString.toInt(&ok);
        if (ok)
            verbosity = NetworkTest::toVerbosity(v, &ok);
        if (!ok)
            qWarning() << "Illegal verbosity value:" << vString << ". Falling back to" << verbosity;
    }

    if (parser.isSet(copyOption)) {
        const QString oFile = parser.value(copyOption);
        if (!QFile::copy(defaultFile, oFile))
            qWarning() << "Could not create" << oFile;
    }

    NetworkTest test(input, warnOnly, showProgress, timeout, verbosity);
    const bool success = test.test();
    return success ? 0 : 1;
}
