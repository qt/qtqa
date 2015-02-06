/****************************************************************************
**
** Copyright (C) 2014 Digia Plc and/or its subsidiary(-ies).
** Contact: http://www.qt-project.org/legal
**
** This file is part of the test suite of the Qt Toolkit.
**
** $QT_BEGIN_LICENSE:LGPL21$
** Commercial License Usage
** Licensees holding valid commercial Qt licenses may use this file in
** accordance with the commercial license agreement provided with the
** Software or, alternatively, in accordance with the terms contained in
** a written agreement between you and Digia. For licensing terms and
** conditions see http://qt.digia.com/licensing. For further information
** use the contact form at http://qt.digia.com/contact-us.
**
** GNU Lesser General Public License Usage
** Alternatively, this file may be used under the terms of the GNU Lesser
** General Public License version 2.1 or version 3 as published by the Free
** Software Foundation and appearing in the file LICENSE.LGPLv21 and
** LICENSE.LGPLv3 included in the packaging of this file. Please review the
** following information to ensure the GNU Lesser General Public License
** requirements will be met: https://www.gnu.org/licenses/lgpl.html and
** http://www.gnu.org/licenses/old-licenses/lgpl-2.1.html.
**
** In addition, as a special exception, Digia gives you certain additional
** rights. These rights are described in the Digia Qt LGPL Exception
** version 1.1, included in the file LGPL_EXCEPTION.txt in this package.
**
** $QT_END_LICENSE$
**
****************************************************************************/


#include <QtCore/QtCore>
#include <QtTest/QtTest>
#include "qbic.h"
#include "global.h"
#include <stdlib.h>

class tst_Bic: public QObject
{
    Q_OBJECT

public:
    tst_Bic();
#ifndef QT_NO_PROCESS
    QBic::Info getCurrentInfo(const QString &libName);
#endif

    QHash<QString, QBic::Info> cachedCurrentInfo;

private slots:
    void initTestCase();
    void cleanupTestCase();

    void sizesAndVTables_data();
    void sizesAndVTables();

private:
    QBic bic;
    QString qtModuleDir;
    QHash<QString, QString> modules;
    QStringList incPaths;
};

typedef QPair<QString, QString> QStringPair;

tst_Bic::tst_Bic()
{
    bic.addBlacklistedClass(QLatin1String("std::*"));
    bic.addBlacklistedClass(QLatin1String("qIsNull*"));
    bic.addBlacklistedClass(QLatin1String("_*"));
    bic.addBlacklistedClass(QLatin1String("<anonymous*"));

    /* some system stuff we don't care for */
    bic.addBlacklistedClass(QLatin1String("drand"));
    bic.addBlacklistedClass(QLatin1String("itimerspec"));
    bic.addBlacklistedClass(QLatin1String("lconv"));
    bic.addBlacklistedClass(QLatin1String("pthread_attr_t"));
    bic.addBlacklistedClass(QLatin1String("random"));
    bic.addBlacklistedClass(QLatin1String("sched_param"));
    bic.addBlacklistedClass(QLatin1String("sigcontext"));
    bic.addBlacklistedClass(QLatin1String("sigaltstack"));
    bic.addBlacklistedClass(QLatin1String("timespec"));
    bic.addBlacklistedClass(QLatin1String("timeval"));
    bic.addBlacklistedClass(QLatin1String("timex"));
    bic.addBlacklistedClass(QLatin1String("tm"));
    bic.addBlacklistedClass(QLatin1String("ucontext64"));
    bic.addBlacklistedClass(QLatin1String("ucontext"));
    bic.addBlacklistedClass(QLatin1String("wait"));

    /* QtOpenGL includes qt_windows.h, and some SDKs don't have these structs present */
    bic.addBlacklistedClass(QLatin1String("tagTITLEBARINFO"));
    bic.addBlacklistedClass(QLatin1String("tagMENUITEMINFOA"));
    bic.addBlacklistedClass(QLatin1String("tagMENUITEMINFOW"));
    bic.addBlacklistedClass(QLatin1String("tagENHMETAHEADER"));

    /* some bug in gcc also reported template instanciations */
    bic.addBlacklistedClass(QLatin1String("QTypeInfo<*>"));
    bic.addBlacklistedClass(QLatin1String("QMetaTypeId<*>"));
    bic.addBlacklistedClass(QLatin1String("QVector<QGradientStop>*"));

    /* this guy is never instantiated, just for compile-time checking */
    bic.addBlacklistedClass(QLatin1String("QMap<*>::PayloadNode"));

    /* QFileEngine was removed in 4.1 */
    bic.addBlacklistedClass(QLatin1String("QFileEngine"));
    bic.addBlacklistedClass(QLatin1String("QFileEngineHandler"));
    bic.addBlacklistedClass(QLatin1String("QFlags<QFileEngine::FileFlag>"));

    /* Private classes */
    bic.addBlacklistedClass(QLatin1String("QBrushData"));
    bic.addBlacklistedClass(QLatin1String("QObjectData"));
    bic.addBlacklistedClass(QLatin1String("QAtomic"));
    bic.addBlacklistedClass(QLatin1String("QBasicAtomic"));
    bic.addBlacklistedClass(QLatin1String("QRegion::QRegionData"));
    bic.addBlacklistedClass(QLatin1String("QtConcurrent::ThreadEngineSemaphore"));
    bic.addBlacklistedClass(QLatin1String("QDrawPixmaps::Data"));
    bic.addBlacklistedClass(QLatin1String("QS60Style"));
    bic.addBlacklistedClass(QLatin1String("QPointerBase"));
    bic.addBlacklistedClass(QLatin1String("QOpenGLFunctionsPrivate"));
    bic.addBlacklistedClass(QLatin1String("QGLFunctionsPrivate"));
    bic.addBlacklistedClass(QLatin1String("QDebug::Stream"));

    /* Jambi-related classes in Designer */
    bic.addBlacklistedClass(QLatin1String("QDesignerLanguageExtension"));

    /* Frederik says it's undocumented and private :) */
    bic.addBlacklistedClass(QLatin1String("QAccessible"));
    bic.addBlacklistedClass(QLatin1String("QAccessible::QPrivateSignal"));
    bic.addBlacklistedClass(QLatin1String("QAccessibleWidget"));
    bic.addBlacklistedClass(QLatin1String("QAccessibleTextInterface"));
    bic.addBlacklistedClass(QLatin1String("QAccessibleEditableTextInterface"));
    bic.addBlacklistedClass(QLatin1String("QAccessibleValueInterface"));
    bic.addBlacklistedClass(QLatin1String("QAccessibleTableCellInterface"));
    bic.addBlacklistedClass(QLatin1String("QAccessibleTableInterface"));
    bic.addBlacklistedClass(QLatin1String("QAccessibleActionInterface"));
    bic.addBlacklistedClass(QLatin1String("QAccessibleImageInterface"));

    /* This structure is semi-private and should never shrink */
    bic.addBlacklistedClass(QLatin1String("QVFbHeader"));

    /* This structure has a version field that allows extension */
    bic.addBlacklistedClass(QLatin1String("QDeclarativePrivate::RegisterType"));
}

void tst_Bic::initTestCase()
{
    QWARN("This test needs the correct qmake in PATH, we need it to generate INCPATH for qt modules.");

    qtModuleDir = QString::fromLocal8Bit(qgetenv("QT_MODULE_TO_TEST"));
    if (qtModuleDir.isEmpty()) {
        QSKIP("$QT_MODULE_TO_TEST is unset - nothing to test.  Set QT_MODULE_TO_TEST to the path "
              "of a Qt module to test.");
    }

    if (qgetenv("PATH").contains("teambuilder"))
        QWARN("This test might not work with teambuilder, consider switching it off.");

    QString configFile = qtModuleDir + "/tests/global/global.cfg";

    if (!QFile(configFile).exists()) {
        QSKIP(
            qPrintable(QString(
                "%1 does not exist.  Create it if you want to run this test."
            ).arg(configFile))
        );
    }

    modules = qt_tests_shared_global_get_modules(configFile);

    QVERIFY2(modules.size() > 0, "Something is wrong in the global config file.");

    QString workDir = qtModuleDir + "/tests/global";
    incPaths = qt_tests_shared_global_get_include_paths(workDir, modules);

    QVERIFY2(incPaths.size() > 0, "Parse INCPATH failed.");

    QTest::addColumn<QString>("libName");

    QStringList keys = modules.keys();
    for (int i = 0; i < keys.size(); ++i)
        QTest::newRow(keys.at(i).toLatin1()) << keys.at(i);
}

void tst_Bic::cleanupTestCase()
{
}

void tst_Bic::sizesAndVTables_data()
{
#if !defined(Q_CC_GNU) || defined(Q_CC_INTEL)
    QSKIP("Test not implemented for this compiler/platform");
#else

#if defined Q_OS_LINUX
# if defined(__powerpc__) && !defined(__powerpc64__)
#  define FILESUFFIX "linux-gcc-ppc32"
# elif defined(__amd64__)
#  define FILESUFFIX "linux-gcc-amd64"
# elif defined(__i386__)
#  define FILESUFFIX "linux-gcc-ia32"
# elif defined(__arm__)
#  define FILESUFFIX "linux-gcc-arm"
# endif
#elif defined Q_OS_MAC && defined(__powerpc__)
#  define FILESUFFIX "macx-gcc-ppc32"
#elif defined Q_OS_MAC && defined(__i386__)
#  define FILESUFFIX "macx-gcc-ia32"
#elif defined Q_OS_MAC && defined(__amd64__)
#  define FILESUFFIX "macx-gcc-amd64"
#elif defined Q_OS_WIN && defined Q_CC_GNU
#  define FILESUFFIX "win32-gcc-ia32"
#else
#  define FILESUFFIX "nonsuch"
    QSKIP("No reference files found for this platform");
#endif

    QTest::addColumn<QString>("oldLib");
    QTest::addColumn<bool>("isPatchRelease");

    int minor = (QT_VERSION >> 8) & 0xFF;
    int patch = QT_VERSION & 0xFF;
    for (int i = 0; i <= minor; ++i) {
        if (i != minor || patch)
            QTest::newRow("5." + QByteArray::number(i))
                << (QString(qtModuleDir + "/tests/auto/bic/data/%1.5.")
                    + QString::number(i)
                    + QString(".0." FILESUFFIX ".txt"))
                << (i == minor && patch);
    }
#endif
}

#ifndef QT_NO_PROCESS
QBic::Info tst_Bic::getCurrentInfo(const QString &libName)
{
    QBic::Info &inf = cachedCurrentInfo[libName];
    if (!inf.classSizes.isEmpty())
        return inf;

    QTemporaryFile tmpQFile;
    tmpQFile.open();
    QString tmpFileName = tmpQFile.fileName();

    QByteArray tmpFileContents = "#include<" + libName.toLatin1() + "/" + libName.toLatin1() + ">\n";
    tmpQFile.write(tmpFileContents);
    tmpQFile.flush();

    QString compilerName = "g++";

    QStringList args;
    args << "-c"
         << incPaths
#ifdef Q_OS_MAC
        << "-arch" << "i386" // Always use 32-bit data on Mac.
#endif
#ifndef Q_OS_WIN
         << "-I/usr/X11R6/include/"
#endif
         << "-DQT_NO_STL"
         << "-xc++"
#if !defined(Q_OS_AIX) && !defined(Q_OS_WIN)
         << "-o" << "/dev/null"
#endif
         << "-fdump-class-hierarchy"
         << "-fPIE"
         << tmpFileName;

    QProcess proc;
    proc.start(compilerName, args, QIODevice::ReadOnly);
    if (!proc.waitForFinished(6000000)) {
        qWarning() << "gcc didn't finish" << proc.errorString();
        return QBic::Info();
    }
    if (proc.exitCode() != 0) {
        qWarning() << "gcc returned with" << proc.exitCode();
        qDebug() << proc.readAllStandardError();
        return QBic::Info();
    }

    QString errs = QString::fromLocal8Bit(proc.readAllStandardError().constData());
    if (!errs.isEmpty()) {
        qDebug() << "Arguments:" << args << "Warnings:" << errs;
        return QBic::Info();
    }

    // See if we find the gcc output file, which seems to change
    // from release to release
    QStringList files = QDir().entryList(QStringList() << "*.class");
    if (files.isEmpty()) {
        qFatal("Could not locate the GCC output file, update this test");
        return QBic::Info();
    } else if (files.size() > 1) {
        qDebug() << files;
        qFatal("Located more than one output file, please clean up before running this test");
        return QBic::Info();
    }

    QString resultFileName = files.first();
    inf = bic.parseFile(resultFileName);

    QFile::remove(resultFileName);
    tmpQFile.close();

    return inf;
}
#endif

void tst_Bic::sizesAndVTables()
{
#if !defined(Q_CC_GNU) || defined(Q_CC_INTEL)
    QSKIP("Test not implemented for this compiler/platform");
#elif defined(QT_NO_PROCESS)
    QSKIP("This Qt build does not have QProcess support");
#else

    QFETCH_GLOBAL(QString, libName);
    QFETCH(QString, oldLib);
    QFETCH(bool, isPatchRelease);

    bool isFailed = false;

    //qDebug() << oldLib.arg(libName);
    if (oldLib.isEmpty() || !QFile::exists(oldLib.arg(libName)))
        QSKIP("No platform spec found for this platform/version.");

    const QBic::Info oldLibInfo = bic.parseFile(oldLib.arg(libName));
    QVERIFY(!oldLibInfo.classVTables.isEmpty());

    const QBic::Info currentLibInfo = getCurrentInfo(libName);
    QVERIFY(!currentLibInfo.classVTables.isEmpty());

    QBic::VTableDiff diff = bic.diffVTables(oldLibInfo, currentLibInfo);

    if (!diff.removedVTables.isEmpty()) {
        qWarning() << "VTables for the following classes were removed" << diff.removedVTables;
        isFailed = true;
    }

    if (!diff.modifiedVTables.isEmpty()) {
        if (diff.modifiedVTables.size() != 1 ||
            strcmp(QTest::currentDataTag(), "4.4") != 0 ||
            diff.modifiedVTables.at(0).first != "QGraphicsProxyWidget") {
            foreach(QStringPair entry, diff.modifiedVTables)
                qWarning() << "modified VTable:\n    Old: " << entry.first
                           << "\n    New: " << entry.second;
            isFailed = true;
        }
    }

    if (isPatchRelease && !diff.addedVTables.isEmpty()) {
        qWarning() << "VTables for the following classes were added in a patch release:"
                   << diff.addedVTables;
        isFailed = true;
    }

    if (isPatchRelease && !diff.reimpMethods.isEmpty()) {
        foreach(QStringPair entry, diff.reimpMethods)
            qWarning() << "reimplemented virtual in patch release:\n    Old: " << entry.first
                       << "\n    New: " << entry.second;
        isFailed = true;
    }

    QBic::SizeDiff sizeDiff = bic.diffSizes(oldLibInfo, currentLibInfo);
    if (!sizeDiff.mismatch.isEmpty()) {
        foreach (QString className, sizeDiff.mismatch)
            qWarning() << "size mismatch for" << className
                       << "old" << oldLibInfo.classSizes.value(className)
                       << "new" << currentLibInfo.classSizes.value(className);
        isFailed = true;
    }

#ifdef Q_CC_MINGW
    /**
     * These symbols are from Windows' imm.h header, and is available
     * conditionally depending on the value of the WINVER define. We pull
     * them out since they're not relevant to the testing done.
     */
    sizeDiff.removed.removeAll(QLatin1String("tagIMECHARPOSITION"));
    sizeDiff.removed.removeAll(QLatin1String("tagRECONVERTSTRING"));
#endif

    if (!sizeDiff.removed.isEmpty()) {
        qWarning() << "the following classes were removed:" << sizeDiff.removed;
        isFailed = true;
    }

    if (isPatchRelease && !sizeDiff.added.isEmpty()) {
        qWarning() << "the following classes were added in a patch release:" << sizeDiff.added;
        isFailed = true;
    }

    if (isFailed)
        QFAIL("Test failed, read warnings above.");
#endif
}

QTEST_APPLESS_MAIN(tst_Bic)

#include "tst_bic.moc"
