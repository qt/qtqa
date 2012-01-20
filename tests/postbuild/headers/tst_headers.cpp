/****************************************************************************
**
** Copyright (C) 2012 Nokia Corporation and/or its subsidiary(-ies).
** All rights reserved.
** Contact: http://www.qt-project.org/
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
    static QStringList getHeaders(const QString &path);
    static QString explainPrivateSlot(const QString &line);

    void allHeadersData();
    QStringList headers;
    QString qtModuleDir;
};

QStringList tst_Headers::getHeaders(const QString &path)
{
    QStringList result;

    QProcess git;
    git.setWorkingDirectory(path);
    git.start("git", QStringList() << "ls-files");

    // Wait for git to start
    if (!git.waitForStarted())
        qFatal("Error running 'git': %s", qPrintable(git.errorString()));

    // Continue reading the data until EOF reached
    QByteArray data;
    while (git.waitForReadyRead(-1))
        data.append(git.readAll());

    // wait until the process has finished
    if ((git.state() != QProcess::NotRunning) && !git.waitForFinished(30000))
        qFatal("'git ls-files' did not complete within 30 seconds: %s", qPrintable(git.errorString()));

    // Check for the git's exit code
    if (0 != git.exitCode())
        qFatal("Error running 'git ls-files': %s", qPrintable(git.readAllStandardError()));

    // Create a QStringList of files out of the standard output
    QString string(data);
    QStringList entries = string.split( "\n" );

    // We just want to check header files
    entries = entries.filter(QRegExp("\\.h$"));
    entries = entries.filter(QRegExp("^(?!ui_)"));

    // Recreate the whole file path so we can open the file from disk
    foreach (QString entry, entries)
        result += path + "/" + entry;

    return result;
}

void tst_Headers::initTestCase()
{
    qtModuleDir = QString::fromLocal8Bit(qgetenv("QT_MODULE_TO_TEST"));
    if (qtModuleDir.isEmpty()) {
        QSKIP("$QT_MODULE_TO_TEST is unset - nothing to test.  Set QT_MODULE_TO_TEST to the path "
              "of a Qt module to test.");
    }

    QDir dir(qtModuleDir);
    QString module = dir.dirName(); // git module name, e.g. qtbase, qtdeclarative

    if (module != "phonon" && module != "qttools") {
        if (dir.exists("src")) {

            /*
                Let all paths be relative to the directory containing the module.
                For example, if the full path is:

                    /home/qt/build/qt5/qtbase/src/corelib/tools/qstring.h

                ... the first part of the path is useless noise, and causes the
                test log to look different on different machines.
                Cut it down to only the important part:

                    qtbase/src/corelib/tools/qstring.h

            */

            QVERIFY(QDir::setCurrent(dir.absolutePath() + "/.."));

            headers = getHeaders(module + "/src");
        }
        if (headers.isEmpty()) {
            QSKIP("It seems there are no headers in this module; this test is "
                  "not applicable");
        }
    } else {
        QWARN("Some test functions will be skipped, because we ignore them for phonon and qttools.");
    }
}

void tst_Headers::allHeadersData()
{
    QTest::addColumn<QString>("header");

    if (headers.isEmpty())
        QSKIP("can't find any headers in your $QT_MODULE_TO_TEST/src.");

    foreach (QString hdr, headers) {
        if (hdr.contains("/3rdparty/") || hdr.endsWith("/src/tools/uic/qclass_lib_map.h"))
            continue;

        QTest::newRow(qPrintable(hdr)) << hdr;
    }
}

QString tst_Headers::explainPrivateSlot(const QString& line)
{
    // Extract private slot from a line like:
    //  Q_PRIVATE_SLOT(d_func(), void fooBar(...))
    QRegExp re("^\\s+Q_PRIVATE_SLOT\\([^,]+,\\s*(.+)\\)\\s*$");
    QString slot = line;
    if (re.indexIn(slot) != -1) {
        slot = re.cap(1).simplified();
    }

    return QString(
        "Private slot `%1' should be named starting with _q_, to reduce the risk of collisions "
        "with signals/slots in user classes"
    ).arg(slot);
}

void tst_Headers::privateSlots()
{
    QFETCH(QString, header);

    if (header.endsWith("_p.h"))
        return;

    QFile f(header);
    QVERIFY2(f.open(QIODevice::ReadOnly), qPrintable(f.errorString()));

    QStringList content = QString::fromLocal8Bit(f.readAll()).split("\n");
    foreach (QString line, content) {
        if (line.contains("Q_PRIVATE_SLOT(") && !line.contains("define Q_PRIVATE_SLOT"))
            QVERIFY2(line.contains("_q_"), qPrintable(explainPrivateSlot(line)));
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

    // "signals" and "slots" should be banned in public headers
    // headers which use signals/slots wouldn't compile if Qt is configured with QT_NO_KEYWORDS
    QVERIFY2(content.indexOf(QRegExp("\\bslots\\s*:")) == -1, "Header contains `slots' - use `Q_SLOTS' instead!");
    QVERIFY2(content.indexOf(QRegExp("\\bsignals\\s*:")) == -1, "Header contains `signals' - use `Q_SIGNALS' instead!");

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
