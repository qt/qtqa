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
        qWarning() << "qmake didn't finish" << proc.errorString();
        return incPaths;
    }
    if (proc.exitCode() != 0) {
        qWarning() << "gcc returned with" << proc.exitCode();
        qDebug() << proc.readAllStandardError();
        return incPaths;
    }

    QFile::remove(proFile);

    incPaths = qt_tests_shared_global_get_include_path(makeFile);

    QFile::remove(makeFile);

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
