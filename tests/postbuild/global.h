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
// Helper functions for global test cases.

#ifndef QT_TESTS_SHARED_GLOBAL_H_INCLUDED
#define QT_TESTS_SHARED_GLOBAL_H_INCLUDED

#include <QtCore/QtCore>
#include <QtTest/QtTest>

QStringList qt_tests_shared_global_get_include_path(const QString &makeFile);
QHash<QString, QString> qt_tests_shared_global_get_modules(const QString &workDir,
                                                           const QString &configFile);
QStringList qt_tests_shared_global_get_include_paths();

QStringList qt_tests_shared_run_qmake(const QString &workDir,
                                      const QByteArray &proFileConent,
                                      QStringList(*makeFileParser)(const QString&));
QStringList qt_tests_shared_global_get_export_modules(const QString &makeFile);
void qt_tests_shared_filter_module_list(const QString &workDir, QHash<QString, QString> &modules);

QHash<QString, QString> qt_tests_shared_global_get_modules(const QString &workDir, const QString &configFile)
{
    QHash<QString, QString> modules;

    QFile file(configFile);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QWARN("Can't open the config file for global.cfg.");
        return modules;
    }

    QXmlStreamReader xml;
    xml.setDevice(&file);

    while (!xml.atEnd()) {
        xml.readNext();
        if (xml.tokenType() == QXmlStreamReader::StartElement && xml.name() == QLatin1String("config")) {
            xml.readNextStartElement();
            if (xml.name() == QLatin1String("modules")) {
                while (!xml.atEnd()) {
                    xml.readNextStartElement();
                    QString modName;
                    QString qtModName;
                    if (xml.name() == QLatin1String("module")) {
                        modName = xml.attributes().value("name").toString().simplified();
                        qtModName = xml.attributes().value("qtname").toString().simplified();
                        if (!modName.isEmpty() && !qtModName.isEmpty())
                            modules[modName] = qtModName;
                    }
                }
            }
        }
    }

    file.close();

    qt_tests_shared_filter_module_list(workDir, modules);

    qDebug() << "modules keys:" << modules.keys();
    qDebug() << "modules values:" << modules.values();

    return modules;
}

QByteArray qt_tests_shared_global_get_modules_pro_lines(const QHash<QString, QString> &modules)
{
    QByteArray result;
    foreach (QString moduleName, modules.values()) {
        QByteArray module = moduleName.toLatin1();
        result += "qtHaveModule(" + module + ") {\n" +
                  "    QT += " + module + "\n" +
                  "    MODULES += " + module + "\n" +
                  "}\n";
    }
    result += "QMAKE_EXTRA_VARIABLES += MODULES\n";
    return result;
}

QStringList qt_tests_shared_global_get_include_paths(const QString &workDir,
                                                     QHash<QString, QString> &modules)
{
    return qt_tests_shared_run_qmake(workDir,
                                     qt_tests_shared_global_get_modules_pro_lines(modules),
                                     &qt_tests_shared_global_get_include_path);
}

void qt_tests_shared_filter_module_list(const QString &workDir, QHash<QString, QString> &modules)
{
    const QStringList result = qt_tests_shared_run_qmake(workDir,
                                                         qt_tests_shared_global_get_modules_pro_lines(modules),
                                                         &qt_tests_shared_global_get_export_modules);
    const QStringList keys = modules.keys();
    for (int i = 0; i < keys.size(); ++i) {
        const QString key = keys.at(i);
        if (!result.contains(modules[key]))
            modules.remove(key);
    }
}

QStringList qt_tests_shared_run_qmake(const QString &workDir,
                                      const QByteArray &proFileContent,
                                      QStringList(*makeFileParser)(const QString&))
{
    QString proFile = workDir + "/global.pro";
    QString makeFile = workDir + "/Makefile";

    QStringList result;

#ifndef QT_NO_PROCESS
    QFile file(proFile);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        QWARN("Can't open the pro file for global.");
        return result;
    }

    file.write(proFileContent);
    file.flush();
    file.close();

    if (!QDir::setCurrent(workDir)) {
        QWARN("Change working dir failed.");
        return result;
    }

    QString qmakeApp = "qmake";

    QStringList qmakeArgs;
    qmakeArgs << "-o"
              << "Makefile";

    QProcess proc;
    proc.start(qmakeApp, qmakeArgs, QIODevice::ReadOnly);
    if (!proc.waitForFinished(6000000)) {
        qWarning() << qmakeApp << qmakeArgs << "in" << workDir << "didn't finish" << proc.errorString();
        return result;
    }
    if (proc.exitCode() != 0) {
        qWarning() << qmakeApp << qmakeArgs << "in" << workDir << "returned with" << proc.exitCode();
        qDebug() << proc.readAllStandardError();
        return result;
    }

    QFile::remove(proFile);

    result = makeFileParser(makeFile);
#ifdef Q_OS_WIN
    if (result.isEmpty())
        result = makeFileParser(makeFile + QLatin1String(".Release"));
#endif

    QFile::remove(makeFile);
#else
    Q_UNUSED(modules);
#endif // QT_NO_PROCESS

    return result;
}

QStringList qt_tests_shared_global_get_include_path(const QString &makeFile)
{
    QFile file(makeFile);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return QStringList();

    QTextStream in(&file);
    while (!in.atEnd()) {
        QString line = in.readLine();
        if (line.contains("=") && line.contains("INCPATH")) {
            QString relatives = line.mid(line.indexOf("=")+1);
            QStringList list1 = relatives.split(" ");
            QStringList list2;
            for (int i = 0; i < list1.size(); ++i) {
                if (!list1.at(i).startsWith("-I"))
                    continue;
                QString rpath = list1.at(i).mid(2);
                QString apath = "-I" + QDir(rpath).absolutePath();
#ifdef Q_OS_WIN
                apath.replace('\\', '/');
#endif
                list2 << apath;
            }
            return list2;
        }
    }

    return QStringList();
}

QStringList qt_tests_shared_global_get_export_modules(const QString &makeFile)
{
    QFile file(makeFile);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return QStringList();
    QTextStream in(&file);
    while (!in.atEnd()) {
        QString line = in.readLine();
        int index = line.indexOf('=');
        if (index > 13 && line.startsWith(QLatin1String("EXPORT_MODULES"))) {
            QString relatives = line.mid(index + 1);
#if QT_VERSION >= QT_VERSION_CHECK(5, 14, 0)
            return relatives.split(QChar(' '), Qt::SkipEmptyParts);
#else
            return relatives.split(QChar(' '), QString::SkipEmptyParts);
#endif
        }
    }
    return QStringList();
}

#endif // QT_TESTS_SHARED_GLOBAL_H_INCLUDED
