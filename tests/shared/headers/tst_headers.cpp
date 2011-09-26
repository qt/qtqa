/****************************************************************************
**
** Copyright (C) 2011 Nokia Corporation and/or its subsidiary(-ies).
** All rights reserved.
** Contact: Nokia Corporation (qt-info@nokia.com)
**
** This file is part of the test suite of the Qt Toolkit.
**
** $QT_BEGIN_LICENSE:LGPL$
** GNU Lesser General Public License Usage
** This file may be used under the terms of the GNU Lesser General Public
** License version 2.1 as published by the Free Software Foundation and
** appearing in the file LICENSE.LGPL included in the packaging of this
** file. Please review the following information to ensure the GNU Lesser
** General Public License version 2.1 requirements will be met:
** http://www.gnu.org/licenses/old-licenses/lgpl-2.1.html.
**
** In addition, as a special exception, Nokia gives you certain additional
** rights. These rights are described in the Nokia Qt LGPL Exception
** version 1.1, included in the file LGPL_EXCEPTION.txt in this package.
**
** GNU General Public License Usage
** Alternatively, this file may be used under the terms of the GNU General
** Public License version 3.0 as published by the Free Software Foundation
** and appearing in the file LICENSE.GPL included in the packaging of this
** file. Please review the following information to ensure the GNU General
** Public License version 3.0 requirements will be met:
** http://www.gnu.org/copyleft/gpl.html.
**
** Other Usage
** Alternatively, this file may be used in accordance with the terms and
** conditions contained in a signed written agreement between you and Nokia.
**
**
**
**
**
** $QT_END_LICENSE$
**
****************************************************************************/
#include <QtCore/QtCore>
#include <QtTest/QtTest>

class tst_Headers: public QObject
{
    Q_OBJECT
private slots:
    void initTestCase();

    void privateSlots_data() { allHeadersData(); }
    void privateSlots();

    void macros_data() { allHeadersData(); }
    void macros();

private:
    static QStringList getFiles(const QString &path,
                                const QStringList dirFilters,
                                const QRegExp &exclude);
    static QStringList getHeaders(const QString &path);

    void allHeadersData();
    QStringList headers;
    QString qtModuleDir;
};

QStringList tst_Headers::getFiles(const QString &path,
                                  const QStringList dirFilters,
                                  const QRegExp &excludeReg)
{
    const QDir dir(path);
    const QStringList dirs(dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot));
    QStringList result;

    foreach (QString subdir, dirs)
        result += getFiles(path + "/" + subdir, dirFilters, excludeReg);

    QStringList entries = dir.entryList(dirFilters, QDir::Files);
    entries = entries.filter(excludeReg);
    foreach (QString entry, entries)
        result += path + "/" + entry;

    return result;
}

QStringList tst_Headers::getHeaders(const QString &path)
{
    return getFiles(path, QStringList("*.h"), QRegExp("^(?!ui_)"));
}

void tst_Headers::initTestCase()
{
    qtModuleDir = QString::fromLocal8Bit(qgetenv("QT_MODULE_TO_TEST"));
    if (qtModuleDir.isEmpty()) {
        QSKIP("$QT_MODULE_TO_TEST is unset - nothing to test.  Set QT_MODULE_TO_TEST to the path "
              "of a Qt module to test.", SkipAll);
    }

    if (!qtModuleDir.contains("phonon") && !qtModuleDir.contains("qttools")) {
        headers = getHeaders(qtModuleDir + "/src");

        if (headers.isEmpty()) {
            QSKIP("It seems there are no headers in this module; this test is "
                  "not applicable", SkipAll);
        }
    } else {
        QWARN("Some test functions will be skipped, because we ignore them for phonon and qttools.");
    }
}

void tst_Headers::allHeadersData()
{
    QTest::addColumn<QString>("header");

    if (headers.isEmpty())
        QSKIP("can't find any headers in your $QT_MODULE_TO_TEST/src.", SkipAll);

    foreach (QString hdr, headers) {
        if (hdr.contains("/3rdparty/") || hdr.endsWith("/src/tools/uic/qclass_lib_map.h"))
            continue;

        QTest::newRow(qPrintable(hdr)) << hdr;
    }
}

void tst_Headers::privateSlots()
{
    QFETCH(QString, header);

    if (header.endsWith("/qobjectdefs.h"))
        return;

    QFile f(header);
    QVERIFY2(f.open(QIODevice::ReadOnly), qPrintable(f.errorString()));

    QStringList content = QString::fromLocal8Bit(f.readAll()).split("\n");
    foreach (QString line, content) {
        if (line.contains("Q_PRIVATE_SLOT("))
            QVERIFY(line.contains("_q_"));
    }
}

void tst_Headers::macros()
{
    QFETCH(QString, header);

    if (header.endsWith("_p.h") || header.endsWith("_pch.h")
        || header.contains("global/qconfig-") || header.endsWith("/qconfig.h")
        || header.contains("/src/tools/") || header.contains("/src/plugins/")
        || header.contains("/src/imports/")
        || header.contains("/src/uitools/")
        || header.endsWith("/qiconset.h") || header.endsWith("/qfeatures.h")
        || header.endsWith("qt_windows.h"))
        return;

    QFile f(header);
    QVERIFY2(f.open(QIODevice::ReadOnly), qPrintable(f.errorString()));

    QByteArray data = f.readAll();
    QStringList content = QString::fromLocal8Bit(data.replace('\r', "")).split("\n");

    int beginHeader = content.indexOf("QT_BEGIN_HEADER");
    int endHeader = content.lastIndexOf("QT_END_HEADER");

    QVERIFY(beginHeader >= 0);
    QVERIFY(endHeader >= 0);
    QVERIFY(beginHeader < endHeader);

    QVERIFY(content.indexOf(QRegExp("\\bslots\\s*:")) == -1);
    QVERIFY(content.indexOf(QRegExp("\\bsignals\\s*:")) == -1);

    if (header.contains("/sql/drivers/") || header.contains("/arch/qatomic")
        || header.endsWith("qglobal.h")
        || header.endsWith("qwindowdefs_win.h"))
        return;

    int qtmodule = content.indexOf(QRegExp("^QT_MODULE\\(.*\\)$"));
    QVERIFY(qtmodule != -1);
    QVERIFY(qtmodule > beginHeader);
    QVERIFY(qtmodule < endHeader);

    int beginNamespace = content.indexOf("QT_BEGIN_NAMESPACE");
    int endNamespace = content.lastIndexOf("QT_END_NAMESPACE");
    QVERIFY(beginNamespace != -1);
    QVERIFY(endNamespace != -1);
    QVERIFY(beginHeader < beginNamespace);
    QVERIFY(beginNamespace < endNamespace);
    QVERIFY(endNamespace < endHeader);
}

QTEST_MAIN(tst_Headers)
#include "tst_headers.moc"
