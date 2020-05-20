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
    QString waitForTopLevelWindow(unsigned count, Q_PID pid, int timeOutMS, QString *errorMessage);
    bool sendCloseEvent(const QString &winId, Q_PID pid, QString *errorMessage);

protected:
    WindowManager();

    virtual bool openDisplayImpl(QString *errorMessage);
    virtual bool isDisplayOpenImpl() const;
    virtual QString waitForTopLevelWindowImpl(unsigned count, Q_PID pid, int timeOutMS, QString *errorMessage);
    virtual bool sendCloseEventImpl(const QString &winId, Q_PID pid, QString *errorMessage);
};

#endif // WINDOWMANAGER_H
