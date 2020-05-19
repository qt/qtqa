/****************************************************************************
**
** Copyright (C) 2017 The Qt Company Ltd.
** Contact: https://www.qt.io/licensing/
**
** This file is part of the test suite of the Qt Toolkit.
**
** $QT_BEGIN_LICENSE:GPL-EXCEPT$
** Commercial License Usage
** Licensees holding valid commercial Qt licenses may use this file in
** accordance with the commercial license agreement provided with the
** Software or, alternatively, in accordance with the terms contained in
** a written agreement between you and The Qt Company. For licensing terms
** and conditions see https://www.qt.io/terms-conditions. For further
** information use the contact form at https://www.qt.io/contact-us.
**
** GNU General Public License Usage
** Alternatively, this file may be used under the terms of the GNU
** General Public License version 3 as published by the Free Software
** Foundation with exceptions as appearing in the file LICENSE.GPL3-EXCEPT
** included in the packaging of this file. Please review the following
** information to ensure the GNU General Public License requirements will
** be met: https://www.gnu.org/licenses/gpl-3.0.html.
**
** $QT_END_LICENSE$
**
****************************************************************************/
#ifndef QBIC_H
#define QBIC_H

#include "QtCore/qhash.h"
#include "QtCore/qlist.h"
#include "QtCore/qpair.h"
#include "QtCore/qregularexpression.h"
#include "QtCore/qstring.h"
#include "QtCore/qstringlist.h"

QT_FORWARD_DECLARE_CLASS(QByteArray)

class QBic
{
public:
    struct Info
    {
        QHash<QString, int> classSizes;
        QHash<QString, QStringList> classVTables;
    };

    struct VTableDiff
    {
        QList<QPair<QString, QString> > reimpMethods;
        QList<QPair<QString, QString> > modifiedVTables;
        QStringList addedVTables;
        QStringList removedVTables;
    };

    struct SizeDiff
    {
        QStringList mismatch;
        QStringList added;
        QStringList removed;
    };

    void addBlacklistedClass(const QString &wildcard);
    void addBlacklistedClass(const QRegularExpression &expression);
    void removeBlacklistedClass(const QString &wildcard);
    bool isBlacklisted(const QString &className) const;

    Info parseOutput(const QByteArray &ba) const;
    Info parseFile(const QString &fileName) const;

    VTableDiff diffVTables(const Info &oldLib, const Info &newLib) const;
    SizeDiff diffSizes(const Info &oldLib, const Info &newLib) const;

private:
    mutable QList<QRegularExpression> blackList;
};

#endif
