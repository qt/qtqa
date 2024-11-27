// Copyright (C) 2024 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

#ifndef NETWORKTEST_H
#define NETWORKTEST_H

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

#include <QtCore>
#include <QJsonParseError>
#include <QJsonArray>

class QDnsLookup;
class NetworkTest
{
    Q_GADGET
public:
    enum class Verbosity {
        Silent = 0,
        Summary = 1,
        Error = 2,
        All = 3,
    };
    Q_ENUM(Verbosity)
    static constexpr int verbosityCount = 4;

    NetworkTest(const QString &fileName, bool warnOnly, bool showProgress, int timeout, Verbosity verbosity);
    bool test();
    static Verbosity toVerbosity(int verbosity, bool *ok);
    static QString verbosityString(Verbosity verbosity);
    static QStringList verbosityStrings();

private:
    QJsonArray m_array;
    const bool m_warnOnly;
    const bool m_showProgress;
    const int m_timeout;
    const Verbosity m_verbosity;
    const QString m_fileName;
    QStringList formatReply(const QDnsLookup *lookup) const;
    bool verbosityCheck(Verbosity verbosity) const;
};

#endif // NETWORKTEST_H
