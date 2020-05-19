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
    static QString explainPrivateSlot(const QString &line);

    void allHeadersData();
    QStringList headers;
    QString qtModuleDir;
};

static QByteArray captureOutput(const QString &program, const QStringList &arguments, const QString &workingDirectory = QString())
{
    QProcess process;
    process.setWorkingDirectory(workingDirectory);
    process.start(program, arguments);

    if (!process.waitForFinished(30000))
        qFatal("'%s' did not complete within 30 seconds: %s", qPrintable(program), qPrintable(process.errorString()));

    if (0 != process.exitCode())
        qFatal("Error running '%s': %s", qPrintable(program), process.readAllStandardError().constData());

    return process.readAll();
}

static QStringList getHeaders(const QString &path)
{
    // Create a QStringList of files out of the standard output
    QString string(captureOutput("git", QStringList() << "ls-files", path));
    QStringList entries = string.split( "\n" );

    // We just want to check header files
    entries = entries.filter(QRegularExpression("\\.h$"));
    entries = entries.filter(QRegularExpression("^(?!ui_)"));

    // Recreate the whole file path so we can open the file from disk
    QStringList result;
    foreach (QString entry, entries)
        result += path + "/" + entry;

    return result;
}

static QStringList getModuleHeaders(const QString &moduleRoot)
{
    // Read the sync.profile file of the module and test headers that syncqt will consider deploying.
    const QLatin1String perlReadSyncProfileExpr(
        "use File::Spec; use Cwd 'abs_path';"
        "$basedir = $ARGV[0];"
        "do File::Spec->catfile($basedir, 'sync.profile');"
        "foreach my $lib (keys(%modules)) {"
            "my $module = $modules{$lib};"
            "my $moduleheader = $moduleheaders{$lib};"
            "my $is_qt = !($module =~ s/^!//);"
            "my $joined = abs_path(File::Spec->catdir($module, $moduleheader));"
            "push @searchPaths, $joined if ($is_qt);"
        "}"
        "print join(\"\\n\", @searchPaths);");

    QString string(captureOutput("perl", QStringList() << "-e" << perlReadSyncProfileExpr << moduleRoot));
    QStringList entries = string.split("\n");
    QStringList headers;
    foreach (const QString &headersPath, entries)
        headers += getHeaders(headersPath);
    return headers;
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

            headers = getModuleHeaders(module);
        }
        if (headers.isEmpty()) {
            QVERIFY2(module != "qtbase",
                "qtbase not containing any header? Something might be wrong with this test.");
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
    QRegularExpression re("^\\s+Q_PRIVATE_SLOT\\([^,]+,\\s*(.+)\\)\\s*$");
    QString slot = line;
    QRegularExpressionMatch match = re.match(slot);
    if (match.hasMatch())
        slot = match.captured(1).simplified();

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
        || header.endsWith("src/corelib/global/qcompilerdetection.h")
        || header.endsWith("src/corelib/global/qprocessordetection.h")
        || header.endsWith("src/corelib/global/qsystemdetection.h")
        || header.endsWith("src/gui/opengl/qopengles2ext.h")
        || header.endsWith("src/gui/opengl/qopenglext.h")
        || header.contains("/snippets/")
        || header.contains("/src/tools/") || header.contains("/src/plugins/")
        || header.contains("/src/imports/")
        || header.contains("/src/uitools/")
        || header.contains("/src/daemon")
        || header.endsWith("/qiconset.h") || header.endsWith("/qfeatures.h")
        || header.endsWith("qt_windows.h")
        // qtsvg.git files
        || header.endsWith("src/svg/qsvgfunctions_wince.h"))
        return;

    QFile f(header);
    QVERIFY2(f.open(QIODevice::ReadOnly), qPrintable(f.errorString()));

    QByteArray data = f.readAll();
    QStringList content = QString::fromLocal8Bit(data.replace('\r', "")).split("\n");

    // "signals" and "slots" should be banned in public headers
    // headers which use signals/slots wouldn't compile if Qt is configured with QT_NO_KEYWORDS
    QVERIFY2(content.indexOf(QRegularExpression("\\bslots\\s*:")) == -1, "Header contains `slots' - use `Q_SLOTS' instead!");
    QVERIFY2(content.indexOf(QRegularExpression("\\bsignals\\s*:")) == -1, "Header contains `signals' - use `Q_SIGNALS' instead!");

    if (header.contains("/sql/drivers/") || header.contains("/arch/qatomic")
        || header.contains(QRegularExpression("q.*global\\.h$"))
        || header.endsWith("qwindowdefs_win.h"))
        return;

    int beginNamespace = content.indexOf(QRegularExpression("QT_BEGIN_NAMESPACE(_[A-Z_]+)?"));
    int endNamespace = content.lastIndexOf(QRegularExpression("QT_END_NAMESPACE(_[A-Z_]+)?"));
    QVERIFY(beginNamespace != -1);
    QVERIFY(endNamespace != -1);
    QVERIFY(beginNamespace < endNamespace);
}

QTEST_MAIN(tst_Headers)
#include "tst_headers.moc"
