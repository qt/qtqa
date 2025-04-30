// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
// Qt-Security score:critical reason:data-parser

//
//  W A R N I N G
//  -------------
//
// This file is not part of the Qt API.  It exists purely as an
// implementation detail.  This header file may change from version to
// version without notice, or even be removed.
//
// We mean it.
//

#include "networktest.h"
#include <QDnsLookup>
#include <QHostAddress>
#include <QJsonDocument>
#include <iostream>

const QVersionNumber NetworkTest::m_version = QVersionNumber(1, 1);
static constexpr QLatin1StringView normalDomain(".test.qt-project.org");

QString NetworkTest::applicationName()
{
    return "CiNetworkTest";
}

QString NetworkTest::packageName(const QString &extension)
{
    static const QSysInfo info;
    static const QString name = QString("%1-%2-%3-%4-v%5").arg(applicationName(),
                                                           info.productType(),
                                                           info.kernelType(),
                                                           info.buildCpuArchitecture(),
                                                           versionString());
    return extension.isEmpty() ? name : name + "." + extension;
}

QString NetworkTest::versionString()
{
    return version().toString();
}

NetworkTest::NetworkTest(const QString &fileName, bool warnOnly, bool showProgress, int timeout, Verbosity verbosity)
    : m_warnOnly(warnOnly)
    , m_timeout(timeout)
    , m_showProgress(showProgress)
    , m_verbosity(verbosity)
    , m_fileName(fileName)
{
    QFile file(m_fileName);
    if (!file.exists())
        return;

    file.open(QIODevice::ReadOnly);
    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    file.close();
    m_array = doc.array();
}

static constexpr std::array<const char*, NetworkTest::verbosityCount> verbosityText {
    "No output",
    "Summary only",
    "Summary and error messages",
    "Summary, success and error messages"
};

QString NetworkTest::verbosityString(Verbosity verbosity)
{
    static const QMetaEnum me = QMetaEnum::fromType<Verbosity>();
    const int v = static_cast<int>(verbosity);
    const QString key = me.valueToKey(v);
    const QString text = verbosityText[v];
    return QString("%1: %2 (%3)").arg(v).arg(key, text);
}

QStringList NetworkTest::verbosityStrings()
{
    QStringList sl;
    for (int i = 0; i < verbosityCount; ++i)
        sl << verbosityString(static_cast<Verbosity>(i));
    return sl;
}

bool NetworkTest::verbosityCheck(Verbosity verbosity) const
{
    return static_cast<int>(m_verbosity) >= static_cast<int>(verbosity);
}

NetworkTest::Verbosity NetworkTest::toVerbosity(int verbosity, bool *ok)
{
    const bool success = verbosity >= 0 && verbosity < verbosityCount;
    if (ok)
        *ok = success;
    return success ? static_cast<Verbosity>(verbosity) : Verbosity::Summary;
}

QString domainName(const QString &input)
{
    if (input.isEmpty())
        return input;

    if (input.endsWith(QLatin1Char('.'))) {
        QString nodot = input;
        nodot.chop(1);
        return nodot;
    }

    return input + normalDomain;
}

std::unique_ptr<QDnsLookup> lookupCommon(QDnsLookup::Type type, const QString &domain)
{
#if QT_VERSION < QT_VERSION_CHECK(6, 8, 0)
    auto lookup = std::make_unique<QDnsLookup>(type, domainName(domain));
#else
    auto lookup = std::make_unique<QDnsLookup>(type, domainName(domain), QDnsLookup::Protocol::Standard, QHostAddress(), 53);
#endif
    QEventLoop loop;
    QObject::connect(lookup.get(), &QDnsLookup::finished, &loop, &QEventLoop::quit);
    bool timeout = false;
    QTimer::singleShot(2000, &loop, [&]{
        timeout = true;
        loop.quit();
    });
    lookup->lookup();
    loop.exec();
    QDnsLookup::Error error = lookup->error();
#if QT_VERSION >= QT_VERSION_CHECK(6, 8, 0)
    if (timeout)
        error = QDnsLookup::TimeoutError;
#endif

    if (error == QDnsLookup::ServerFailureError
        || error == QDnsLookup::ServerRefusedError
#if QT_VERSION < QT_VERSION_CHECK(6, 8, 0)
        || timeout) {
#else
        || error == QDnsLookup::TimeoutError) {
#endif
            const auto me = QMetaEnum::fromType<QDnsLookup::Type>();
            const QString msg = QString("Server refused or was unable to answer query; %1 type %3: %2")
                        .arg(domain, lookup->errorString(), QString(me.valueToKey(int(type))));
            qCritical() << msg;
        return {};
    }

    return lookup;
}

QStringList NetworkTest::formatReply(const QDnsLookup *lookup) const
{
    QStringList result;
    QString domain = lookup->name();

    auto shorter = [this](QString value) {
        const QString &ending = normalDomain;
        if (value.endsWith(ending))
            value.chop(ending.size());
        else
            value += u'.';
        return value;
    };

    for (const QDnsMailExchangeRecord &rr : lookup->mailExchangeRecords()) {
        QString entry = QString("MX %1 %2").arg(rr.preference(), 5).arg(shorter(rr.exchange()));
        if (rr.name() != domain)
            entry = "MX unexpected label to " + rr.name();
        result.append(std::move(entry));
    }

    for (const QDnsServiceRecord &rr : lookup->serviceRecords()) {
        QString entry = QString("SRV %1 %2 %3 %4").arg(rr.priority(), 5).arg(rr.weight())
                .arg(rr.port()).arg(shorter(rr.target()));
        if (rr.name() != domain)
            entry = "SRV unexpected label to " + rr.name();
        result.append(std::move(entry));
    }

    auto addNameRecords = [&](QLatin1StringView rrtype, const QList<QDnsDomainNameRecord> &rrset) {
        for (const QDnsDomainNameRecord &rr : rrset) {
            QString entry = QString("%1 %2").arg(rrtype, shorter(rr.value()));
            if (rr.name() != domain)
                entry = rrtype + " unexpected label to " + rr.name();
            result.append(std::move(entry));
        }
    };
    addNameRecords(QLatin1StringView("NS"), lookup->nameServerRecords());
    addNameRecords(QLatin1StringView("PTR"), lookup->pointerRecords());
    addNameRecords(QLatin1StringView("CNAME"), lookup->canonicalNameRecords());

    for (const QDnsHostAddressRecord &rr : lookup->hostAddressRecords()) {
        if (rr.name() != domain)
            continue;   // A and AAAA may appear as extra records in the answer section
        QHostAddress addr = rr.value();
        result.append(QString("%1 %2")
                      .arg(addr.protocol() == QHostAddress::IPv6Protocol ? "AAAA" : "A",
                           addr.toString()));
    }

    for (const QDnsTextRecord &rr : lookup->textRecords()) {
        QString entry = "TXT";
        for (const QByteArray &data : rr.values()) {
            entry += u' ';
            entry += QDebug::toString(data);
        }
        result.append(std::move(entry));
    }

#if QT_VERSION >= QT_VERSION_CHECK(6, 8, 0)
    for (const QDnsTlsAssociationRecord &rr : lookup->tlsAssociationRecords()) {
        QString entry = QString("TLSA %1 %2 %3 %4").arg(int(rr.usage())).arg(int(rr.selector()))
                .arg(int(rr.matchType())).arg(rr.value().toHex().toUpper());
        if (rr.name() != domain)
            entry = "TLSA unexpected label to " + rr.name();
        result.append(std::move(entry));
    }
#endif

    result.sort();
    return result;
}

int lastPercentage = -1;

void writeProgress(int count, int max)
{
    static constexpr int barWidth = 70;
    const float countF = count;
    const float maxF = max;
    const float progress = (count == max - 1) ? 1.0 : countF / maxF;
    const int percentage = progress * 100;
    if (percentage == lastPercentage)
        return;

    lastPercentage = percentage;
    std::cout << "[";
    const int pos = barWidth * progress;
    for (int i = 0; i < barWidth; ++i) {
        if (i < pos)
            std::cout << "=";
        else if (i == pos)
            std::cout << ">";
        else
            std::cout << " ";
    }

    std::cout << "] " << percentage << " %\r";
    std::cout.flush();

    if (progress == 1.0) {
        lastPercentage = -1;
        std::cout << "\n";
    }
}

#define ERROR if (verbosityCheck(Verbosity::Error)) qCritical()
#define WARNING if (verbosityCheck(Verbosity::Error)) qWarning()
#define SUCCESS if (verbosityCheck(Verbosity::All)) qInfo()

bool NetworkTest::test()
{
    int errors = 0;
    int ignoredRecords = 0;
    const QTime started = QTime::currentTime();
    if (verbosityCheck(Verbosity::Summary)) {
        qInfo() << "Starting network test at" << started.toString()
                << "QT_VERSION:" << QT_VERSION_STR;
        qInfo() << "WarnOnly:" << m_warnOnly;
        if (m_timeout > 0)
            qInfo() << "Timeout after" << m_timeout << "milliseconds";
        else
            qInfo() << "Never time out";

        qInfo().noquote() << "Verbosity:" << verbosityString(m_verbosity);
        QString progress = QString("Show progress: %1").arg(m_showProgress ? "true" : "false");
        if (m_verbosity != Verbosity::Summary && m_showProgress)
            progress += QString("(ignored due to verbosity != 1)");
        qInfo().noquote() << progress;
    }

    if (m_array.isEmpty()) {
        if (verbosityCheck(Verbosity::Error))
            qCritical().noquote() << "Nothing to test! Check" << m_fileName;
        ++errors;
    }

    const auto me = QMetaEnum::fromType<QDnsLookup::Type>();
    const int count = m_array.count();
    const bool showProgress = m_verbosity == Verbosity::Summary && m_showProgress;

    for (int i = 0; i < count; ++i) {
        if (showProgress)
            writeProgress(i, count);

        if (!m_array.at(i).isObject()) {
            ERROR << "JSON format error in input file, array position" << i;
            ++errors;
            continue;
        }

        const QJsonObject obj = m_array.at(i).toObject();
        const QByteArray typeBa = obj.value("Type").toString().toLatin1();
        bool typeOk;
        const int typeInt = me.keyToValue(typeBa, &typeOk);
        if (!typeOk) {
            WARNING.noquote() << "Ignoring record with type" << typeBa;
            ++ignoredRecords;
            continue;
        }

        const auto type = static_cast<QDnsLookup::Type>(typeInt);
        const QString domain = obj.value("Domain").toString();
        const QString expected = obj.value("Expected").toString();

        std::unique_ptr<QDnsLookup> lookup = lookupCommon(type, domain);
        if (!lookup) {
            ERROR << "Failed to create QDnsLookup object. Aborting.";
            ++errors;
            break;
        }

        if (lookup->error() != QDnsLookup::NoError) {
            ERROR << "DNS Lookup error" << lookup->error() << lookup->errorString();
            ++errors;
        }

        QString result = formatReply(lookup.get()).join(u';');
        if (result == expected) {
            SUCCESS << "Succeeded:" << domain << "-->" << result;
        } else {
            ERROR << "Expected" << expected << "and got" << result << "for" << domain;
            ++errors;
        }
    }
    const QTime finished = QTime::currentTime();
    const int duration = started.msecsTo(finished);
    if (m_timeout > 0 && m_timeout < duration) {
        ERROR << "Duration of" << duration << "exceeded timeout limit of" << m_timeout;
        ++errors;
    }

    if (verbosityCheck(Verbosity::Summary)) {
        qInfo() << "Network test finished at" << finished.toString()
                << "Total milliseconds consumed:" << started.msecsTo(finished);
        qInfo() << "Processed" << count << "records," << ignoredRecords << "ignored.";
        qInfo() << errors << "error(s) occurred";
    }
    return (errors == 0) || m_warnOnly ;
}

#undef ERROR
#undef WARNING
#undef SUCCESS
