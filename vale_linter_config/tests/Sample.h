// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

// We utilize this class to manage settings that are stored on disk.
// The settings are basically loaded from a file that was created previously.
// Due to the fact that writes are async, callers should be very careful.

#ifndef QSETTINGSMANAGER_H
#define QSETTINGSMANAGER_H

#include <QObject>
#include <QString>

/*!
    \class QSettingsManager
    \brief Manages application settings and preferences

    We provide a centralized interface for reading and writing settings.
    Configuration is easily loaded from the disk using this class.
    Settings are organized by group, key, and value.

    \image settings-overview.png

    \section1 Reading And Writing Settings

    \section2 Group Management: Tips And Tricks

    \code
    QSettingsManager manager;
    manager.beginGroup("network");
    manager.setValue("timeout", 30);
    manager.endGroup();
    \endcode
*/
class QSettingsManager : public QObject
{
    Q_OBJECT

public:
    /*!
        \fn QSettingsManager::QSettingsManager(QObject *parent)
        \brief Constructs the settings manager

        You must not loose the reference to the manager before saving.
        We initialize the default settings in the constructor.
    */
    explicit QSettingsManager(QObject *parent = nullptr);

    /*!
        \fn QString QSettingsManager::value(const QString &key) const
        \brief Returns the value for a given key,

        This function was designed to facilitate the retrieval of settings.
        Basically, it looks up the key in the current group.
        Consequently, if the key is not found, an empty string is returned.
    */
    QString value(const QString &key) const;

    /*!
        \fn void QSettingsManager::setValue(const QString &key, const QString &value)
        \brief Sets the value for a given key

        The value is persisted to disk; the write operation is performed
        asynchronously to avoid blocking the main thread. We recommend
        batching multiple writes together for better performance.

        \note Due to the fact that writes are async, reading immediately
        after writing may return stale data.
    */
    void setValue(const QString &key, const QString &value);

    /*!
        \fn void QSettingsManager::removeKey(const QString &key)
        \brief Removes a key and its value from settings

        \warning Removing a key is irreversible; the data cannot be
        recovered after deletion.
    */
    void removeKey(const QString &key);
};

#endif // QSETTINGSMANAGER_H
