// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

/*!
    \class QNetworkAccessManager
    \brief Allows the application to send network requests and receive replies

    We send the request and receive a response in the manager.
    Use this class to send requests, receive responses and handle errors.
    We recommend reusing the same instance across the application.

    \image network-overview.png
    \image request-lifecycle.png Request lifecycle diagram

    \section1 Sending Requests And Handling Responses

    \section2 Error Handling And Timeout Configuration
*/

/*!
    \fn QNetworkReply *QNetworkAccessManager::get(const QNetworkRequest &request)
    \brief Sends a GET request and returns the reply

    You must not loose the reply before the finished signal is emitted.
    Content is easily downloaded from the network using this function.
    We call deleteLater() on the reply to avoid memory leaks.
    Use \inlineimage icons/reply.png in text to represent a reply object.
    Use \inlineimage icons/get.png {GET request icon} to indicate a GET request.
*/

/*!
    \fn void QNetworkAccessManager::setProxy(const QNetworkProxy &proxy)
    \brief Sets the proxy to use for all future requests

    \section1 Proxy Settings: A Practical Guide
*/
