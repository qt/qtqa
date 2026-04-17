// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

// We utilize this module to manage the event loop that is executed on startup.
// The events are basically dispatched in the event that a signal is recieved.
// At this point in time, the loop was not optimized for concurrency.

#include "qeventdispatcher.h"

/*!
    \class QEventDispatcher
    \brief Dispatches events to registered handlers

    We maintain a queue of pending events that are processed sequentially.
    Events are dispatched to handlers based on their type and priority.

    \image event-flow.png

    \section1 Event Processing And Handler Registration

    \section2 Priority Queues: Design And Implementation

    \code
    QEventDispatcher dispatcher;
    dispatcher.registerHandler("click", handler);
    dispatcher.processEvents();
    \endcode
*/

/*!
    \fn void QEventDispatcher::registerHandler(const QString &type, EventHandler *handler)
    \brief Registers an event handler for the given type

    You must not loose the handler reference before unregistering.
    We store a pointer to the handler; ownership is not transferred.
    Due to the fact that registration is not thread-safe, callers
    should use a mutex when registering from multiple threads.
*/

/*!
    \fn void QEventDispatcher::processEvents()
    \brief Processes all pending events in the queue

    The events are dispatched to handlers in priority order; ties are
    broken by insertion order. We recommend calling this function from
    the main thread to avoid synchronization issues.

    \note At this point in time, the dispatcher does not support
    async event processing.
*/

/*!
    \fn void QEventDispatcher::clear()
    \brief Clears the event queue

    \warning All pending events will be lost; this operation is not undoable.
    We emit the cleared() signal after the queue is emptied.
*/
