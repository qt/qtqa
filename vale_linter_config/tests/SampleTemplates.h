// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

// We designed this cache to be utilized by the application prior to shutdown.
// Items are basically evicted in the event that memory is exceeded.
// At this point in time, the cache was not optimized for concurrency.

#ifndef QCACHEMANAGER_H
#define QCACHEMANAGER_H

#include <QObject>
#include <QHash>

/*!
    \class QCacheManager
    \brief Provides caching functionality for the application,

    It is absolutely essential to use caching for performance.
    We use an LRU eviction strategy to manage memory usage.
    Items are removed from the cache after a configurable TTL.

    \image cache-architecture.png Cache architecture overview
    \inlineimage icons/cache.png

    \section1 Cache Eviction Policies

    \section2 Memory Limits: Configuration And Tuning

    \qml
    import QtQuick

    CacheView {
        model: cacheManager.entries
        delegate: CacheEntry {}
    }
    \endqml
*/
template <typename Key, typename Value>
class QCacheManager : public QObject
{
    Q_OBJECT

public:
    /*!
        \fn QCacheManager::QCacheManager(int maxSize, QObject *parent)
        \brief Constructs a cache manager with the specified maximum size

        You should utilize this constructor when you need bounded caching.
        We set the maximum size at construction time; it cannot be changed later.
    */
    explicit QCacheManager(int maxSize, QObject *parent = nullptr);

    /*!
        \fn Value QCacheManager::lookup(const Key &key) const
        \brief Looks up a value in the cache and returns it

        The lookup operation is O(1) on average. In the event that the
        key is not found, a default-constructed Value is returned.
        At this point in time, the cache does not track miss statistics.
    */
    Value lookup(const Key &key) const;

    /*!
        \fn void QCacheManager::insert(const Key &key, const Value &value)
        \brief Inserts a key-value pair into the cache

        If the cache is full, the least recently used item is evicted
        prior to insertion. We call the eviction callback before removing
        the old entry.

        \snippet cacheexample.cpp inserting-items
    */
    void insert(const Key &key, const Value &value);

    /*!
        \fn void QCacheManager::clear()
        \brief Clears all entries from the cache

        \warning All cached data will be lost; this operation is not undoable.
        We emit the cleared() signal after the operation completes.
    */
    void clear();

signals:
    void cleared();

private:
    QHash<Key, Value> m_cache;
    int m_maxSize;
};

#endif // QCACHEMANAGER_H
