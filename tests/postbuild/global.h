/****************************************************************************
**
** Copyright (C) 2015 The Qt Company Ltd.
** Contact: http://www.qt.io/licensing/
**
** This file is part of the test suite of the Qt Toolkit.
**
** $QT_BEGIN_LICENSE:LGPL21$
** Commercial License Usage
** Licensees holding valid commercial Qt licenses may use this file in
** accordance with the commercial license agreement provided with the
** Software or, alternatively, in accordance with the terms contained in
** a written agreement between you and The Qt Company. For licensing terms
** and conditions see http://www.qt.io/terms-conditions. For further
** information use the contact form at http://www.qt.io/contact-us.
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
** As a special exception, The Qt Company gives you certain additional
** rights. These rights are described in The Qt Company LGPL Exception
** version 1.1, included in the file LGPL_EXCEPTION.txt in this package.
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
QHash<QString, QString> qt_tests_shared_global_get_modules(const QString &configFile);
QStringList qt_tests_shared_global_get_include_paths();

QHash<QString, QString> qt_tests_shared_global_get_modules(const QString &configFile)
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
        if (xml.tokenType() == QXmlStreamReader::StartElement && xml.name() == "config") {
            xml.readNextStartElement();
            if (xml.name() == "modules") {
                while (!xml.atEnd()) {
                    xml.readNextStartElement();
                    QString modName;
                    QString qtModName;
                    if (xml.name() == "module") {
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

    qDebug() << "modules keys:" << modules.keys();
    qDebug() << "modules values:" << modules.values();

    return modules;
}

QStringList qt_tests_shared_global_get_include_paths(const QString &workDir, QHash<QString, QString> &modules)
{
    QString proFile = workDir + "/global.pro";
    QString makeFile = workDir + "/Makefile";

    QStringList incPaths;

#ifndef QT_NO_PROCESS
    QFile file(proFile);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        QWARN("Can't open the pro file for global.");
        return incPaths;
    }

    QByteArray proLine = "QT += " + QStringList(modules.values()).join(" ").toLatin1() + "\n";
    file.write(proLine);
    file.flush();
    file.close();

    if (!QDir::setCurrent(workDir)) {
        QWARN("Change working dir failed.");
        return incPaths;
    }

    QString qmakeApp = "qmake";

    QStringList qmakeArgs;
    qmakeArgs << "-o"
              << "Makefile";

    QProcess proc;
    proc.start(qmakeApp, qmakeArgs, QIODevice::ReadOnly);
    if (!proc.waitForFinished(6000000)) {
        qWarning() << qmakeApp << qmakeArgs << "in" << workDir << "didn't finish" << proc.errorString();
        return incPaths;
    }
    if (proc.exitCode() != 0) {
        qWarning() << qmakeApp << qmakeArgs << "in" << workDir << "returned with" << proc.exitCode();
        qDebug() << proc.readAllStandardError();
        return incPaths;
    }

    QFile::remove(proFile);

    incPaths = qt_tests_shared_global_get_include_path(makeFile);

    QFile::remove(makeFile);
#else
    Q_UNUSED(modules);
#endif // QT_NO_PROCESS

    return incPaths;
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

#endif // QT_TESTS_SHARED_GLOBAL_H_INCLUDED
