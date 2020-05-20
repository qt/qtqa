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

#include "windowmanager.h"

#include <QtCore/QDir>
#include <QtCore/QThread>
#include <QtCore/QString>
#include <QtTest/QtTest>
#include <QtCore/QProcess>
#include <QtCore/QByteArray>
#include <QtCore/QLibraryInfo>
#include <QtCore/QVariant>
#include <QtCore/QDateTime>
#include <QtCore/QMap>

// AppLaunch: Launch gui applications, keep them running a while
// (grabbing their top level from the window manager) and send
// them a Close event via window manager. Verify that they do not
// not crash nor produces unexpected error output.
// Note: Do not play with the machine while it is running as otherwise
// the top-level find algorithm might get confused (especially on Windows).
// Environment variables are checked to turned off some tests
// It is currently implemented for X11 and Windows, pending an
// implementation of the WindowManager class and deployment on
// the other platforms.

enum  { defaultUpTimeMS = 3000, defaultTopLevelWindowTimeoutMS = 30000,
        defaultTerminationTimeoutMS = 35000 };

// List the examples to test (Gui examples only).
struct Example {
    QByteArray name;
    QByteArray directory;
    QByteArray binary;
    unsigned priority; // 0-highest
    int upTimeMS;
};

QList<Example> examples;

// Data struct used in tests, specifying paths and timeouts
struct AppLaunchData {
    AppLaunchData();
    void clear();

    QString binary;
    QStringList args;    
    QString workingDirectory;
    int upTimeMS;
    int topLevelWindowTimeoutMS;
    int terminationTimeoutMS;
    bool splashScreen;
};

AppLaunchData::AppLaunchData() :
    upTimeMS(defaultUpTimeMS),
    topLevelWindowTimeoutMS(defaultTopLevelWindowTimeoutMS),
    terminationTimeoutMS(defaultTerminationTimeoutMS),
    splashScreen(false)
{
}

void AppLaunchData::clear()
{
    binary.clear();
    args.clear();
    workingDirectory.clear();
    upTimeMS = defaultUpTimeMS;
    topLevelWindowTimeoutMS = defaultTopLevelWindowTimeoutMS;
    terminationTimeoutMS = defaultTerminationTimeoutMS;
    splashScreen = false;
}

Q_DECLARE_METATYPE(AppLaunchData)


class tst_GuiAppLauncher : public QObject
{
    Q_OBJECT

public:
    // Test name (static const char title!) + data
    typedef QPair<const char*, AppLaunchData> TestDataEntry;
    typedef QList<TestDataEntry> TestDataEntries;

    enum { TestTools = 0x1, TestExamples = 0x2, TestAll = TestTools|TestExamples };

    tst_GuiAppLauncher();

private Q_SLOTS:
    void initTestCase();

    void run();
    void run_data();

    void cleanupTestCase();

private:
    QString workingDir() const;

private:
    bool runApp(const AppLaunchData &data, QString *errorMessage) const;
    TestDataEntries testData() const;

    const unsigned m_testMask;
    const unsigned m_examplePriority;
    const QString m_dir;
    const QSharedPointer<WindowManager> m_wm;
};

// Test mask from environment as test lib does not allow options.
static inline unsigned testMask()
{
    unsigned testMask = tst_GuiAppLauncher::TestAll;
    if (!qgetenv("QT_TEST_NOTOOLS").isEmpty())
        testMask &= ~ tst_GuiAppLauncher::TestTools;
    if (!qgetenv("QT_TEST_NOEXAMPLES").isEmpty())
        testMask &= ~tst_GuiAppLauncher::TestExamples;
    return testMask;
}

static inline unsigned testExamplePriority()
{
    const QByteArray priorityD = qgetenv("QT_TEST_EXAMPLE_PRIORITY");
    if (!priorityD.isEmpty()) {
        bool ok;
        const unsigned rc = priorityD.toUInt(&ok);
        if (ok)
            return rc;
    }
    return 5;
}

tst_GuiAppLauncher::tst_GuiAppLauncher() :
    m_testMask(testMask()),
    m_examplePriority(testExamplePriority()),
    m_dir(QLatin1String(SRCDIR)),
    m_wm(WindowManager::create())
{
}

void tst_GuiAppLauncher::initTestCase()
{   
    QString message = QString::fromLatin1("### App Launcher test on %1 in %2").
                      arg(QDateTime::currentDateTime().toString(), QDir::currentPath());
    qDebug("%s", qPrintable(message));
    qWarning("### PLEASE LEAVE THE MACHINE UNATTENDED WHILE THIS TEST IS RUNNING\n");

    // Does a window manager exist on the platform?
    if (!m_wm->openDisplay(&message)) {
        QSKIP(message.toLatin1().constData());
    }

    // Paranoia: Do we have our test file?
    const QDir workDir(m_dir);
    if (!workDir.exists()) {
        message = QString::fromLatin1("Invalid working directory %1").arg(m_dir);
        QFAIL(message.toLocal8Bit().constData());
    }
}

void tst_GuiAppLauncher::run()
{
    QString errorMessage;
    QFETCH(AppLaunchData, data);
    const bool rc = runApp(data, &errorMessage);
    if (!rc) // Wait for windows to disappear after kill
        QThread::msleep(500);
    QVERIFY2(rc, qPrintable(errorMessage));
}

// Cross platform galore!
static inline QString guiBinary(QString in)
{
#ifdef Q_OS_MAC
    return in + QLatin1String(".app/Contents/MacOS/") + in;
#endif
    in[0] = in.at(0).toLower();
#ifdef Q_OS_WIN
    in += QLatin1String(".exe");
#endif
    return in;
}

void tst_GuiAppLauncher::run_data()
{
    QTest::addColumn<AppLaunchData>("data");
    foreach(const TestDataEntry &data, testData()) {
        qDebug() << data.first << data.second.binary;
        QTest::newRow(data.first) << data.second;
    }
}

static QList<Example> readDataEntriesFromFile(const QString &fileName)
{
    QList<Example> ret;
    QFile file(fileName);
    if (!file.open(QFile::ReadOnly))
        return ret;

    QRegularExpression lineMatcher("\"([^\"]*)\", *\"([^\"]*)\", *\"([^\"]*)\", *([-0-9]*), *([-0-9]*)");
    for (QByteArray line = file.readLine(); !line.isEmpty(); line = file.readLine()) {
        QRegularExpressionMatch match = lineMatcher.match(QString::fromLatin1(line));
        if (!match.hasMatch())
            break;

        Example example;
        example.name = match.captured(1).toLatin1();
        example.directory = match.captured(2).toLatin1();
        example.binary = match.captured(3).toLatin1();
        example.priority = match.captured(4).toUInt();
        example.upTimeMS = match.captured(5).toInt();
        ret << example;
    }

    return ret;
}

// Read out the examples array structures and convert to test data.
static tst_GuiAppLauncher::TestDataEntries exampleData(unsigned priority,
                                                       const QString &path,
                                                       const QList<Example> exArray,
                                                       unsigned n)
{
    tst_GuiAppLauncher::TestDataEntries rc;
    const QChar slash = QLatin1Char('/');
    AppLaunchData data;
    for (unsigned e = 0; e < n; e++) {
        const Example &example = exArray[e];
        if (example.priority <= priority) {
            data.clear();
            const QString examplePath = path + slash + example.directory;
            data.binary = examplePath + slash;
#ifdef Q_OS_WIN
            // FIXME: support debug version too?
            data.binary += QLatin1String("release/");
#endif
            data.binary += guiBinary(example.binary);
            data.workingDirectory = examplePath;
            if (example.upTimeMS > 0)
                data.upTimeMS = example.upTimeMS;
            rc.append(tst_GuiAppLauncher::TestDataEntry(example.name.constData(), data));
        }
    }
    return rc;
}

tst_GuiAppLauncher::TestDataEntries tst_GuiAppLauncher::testData() const
{
    TestDataEntries rc;
    const QChar slash = QLatin1Char('/');
    const QString binPath = QLibraryInfo::location(QLibraryInfo::BinariesPath) + slash;
    const QString path = qgetenv("QT_MODULE_TO_TEST");

    AppLaunchData data;

    if (m_testMask & TestTools) {
        data.binary = binPath + guiBinary(QLatin1String("Designer"));
        data.args.append(m_dir + QLatin1String("test.ui"));
        rc.append(TestDataEntry("Qt Designer", data));

        data.clear();
        data.binary = binPath + guiBinary(QLatin1String("Linguist"));
        data.splashScreen = true;
        data.upTimeMS = 5000; // Slow loading
        data.args.append(m_dir + QLatin1String("test.ts"));
        rc.append(TestDataEntry("Qt Linguist", data));
    }

    if (m_testMask & TestExamples) {
        if (!path.isEmpty()) {
            examples = readDataEntriesFromFile(path + "/tests/auto/guiapplauncher/examples.txt");
            rc += exampleData(m_examplePriority, path, examples, examples.size());
        }
    }
    qDebug("Running %d tests...", rc.size());
    return rc;
}

static inline void ensureTerminated(QProcess *p)
{
    if (p->state() != QProcess::Running)
        return;
    p->terminate();
    if (p->waitForFinished(300))
        return;
    p->kill();
    if (!p->waitForFinished(500))
        qWarning("Unable to terminate process");
}

static const QStringList &stderrWhiteList()
{
    static QStringList rc;
    if (rc.empty()) {
        rc << QLatin1String("QPainter::begin: Paint device returned engine == 0, type: 2")
           << QLatin1String("QPainter::setRenderHint: Painter must be active to set rendering hints")
           << QLatin1String("QPainter::setPen: Painter not active")
           << QLatin1String("QPainter::setBrush: Painter not active")
           << QLatin1String("QPainter::end: Painter not active, aborted");
    }
    return rc;
}

bool tst_GuiAppLauncher::runApp(const AppLaunchData &data, QString *errorMessage) const
{
    qDebug("Launching: %s\n", qPrintable(data.binary));
    QProcess process;
    process.setProcessChannelMode(QProcess::MergedChannels);
    if (!data.workingDirectory.isEmpty())
        process.setWorkingDirectory(data.workingDirectory);
    process.start(data.binary, data.args);
    process.closeWriteChannel();
    if (!process.waitForStarted()) {
        *errorMessage = QString::fromLatin1("Unable to execute %1: %2").arg(data.binary, process.errorString());
        return false;
    }
    // Get window id.
    const QString winId = m_wm->waitForTopLevelWindow(data.splashScreen ? 2 : 1, process.pid(), data.topLevelWindowTimeoutMS, errorMessage);
    if (winId.isEmpty()) {
        ensureTerminated(&process);
        return false;
    }
    qDebug("Window: %s\n", qPrintable(winId));
    // Wait a bit, then send close
    QThread::msleep(data.upTimeMS);
    if (m_wm->sendCloseEvent(winId, process.pid(), errorMessage)) {
        qDebug("Sent close to window: %s\n", qPrintable(winId));
    } else {
        ensureTerminated(&process);
        return false;
    }
    // Terminate
    if (!process.waitForFinished(data.terminationTimeoutMS)) {
        *errorMessage = QString::fromLatin1("%1: Timeout %2ms").arg(data.binary).arg(data.terminationTimeoutMS);
        ensureTerminated(&process);
        return false;
    }
    if (process.exitStatus() != QProcess::NormalExit) {
        *errorMessage = QString::fromLatin1("%1: Startup crash").arg(data.binary);
        return false;
    }

    const int exitCode = process.exitCode();
    // check stderr
    const QStringList stderrOutput = QString::fromLocal8Bit(process.readAllStandardOutput()).split(QLatin1Char('\n'));
    foreach(const QString &stderrLine, stderrOutput) {
        // Skip expected QPainter warnings from oxygen.
        if (stderrWhiteList().contains(stderrLine)) {
            qWarning("%s: stderr: %s\n", qPrintable(data.binary), qPrintable(stderrLine));
        } else {
            if (!stderrLine.isEmpty()) { // Split oddity gives empty messages
                *errorMessage = QString::fromLatin1("%1: Unexpected output (ex=%2): '%3'").arg(data.binary).arg(exitCode).arg(stderrLine);
                return false;
            }
        }
    }

    if (exitCode != 0) {
        *errorMessage = QString::fromLatin1("%1: Exit code %2").arg(data.binary).arg(exitCode);
        return false;
    }
    return true;
}

void tst_GuiAppLauncher::cleanupTestCase()
{
}

QTEST_APPLESS_MAIN(tst_GuiAppLauncher)
#include "tst_guiapplauncher.moc"
