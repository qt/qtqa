// Copyright (C) 2017 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only WITH Qt-GPL-exception-1.0

#ifndef WINDOWMANAGER_H
#define WINDOWMANAGER_H

#include <QtCore/QSharedPointer>
#include <QtCore/QString>
#include <QtCore/QProcess>

/* WindowManager: Provides functions to retrieve the top level window of
 * an application and send it a close event. */

class WindowManager
{
    Q_DISABLE_COPY(WindowManager)
public:
    static QSharedPointer<WindowManager> create();

    virtual ~WindowManager();

    bool openDisplay(QString *errorMessage);
    bool isDisplayOpen() const;

    // Count: Number of toplevels, 1 for normal apps, 2 for apps with a splash screen
    QString waitForTopLevelWindow(unsigned count, qint64 pid, int timeOutMS, QString *errorMessage);
    bool sendCloseEvent(const QString &winId, qint64 pid, QString *errorMessage);

protected:
    WindowManager();

    virtual bool openDisplayImpl(QString *errorMessage);
    virtual bool isDisplayOpenImpl() const;
    virtual QString waitForTopLevelWindowImpl(unsigned count, qint64 pid, int timeOutMS, QString *errorMessage);
    virtual bool sendCloseEventImpl(const QString &winId, qint64 pid, QString *errorMessage);
};

#endif // WINDOWMANAGER_H
