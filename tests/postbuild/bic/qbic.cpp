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


#include "qbic.h"

#include "QtCore/qfile.h"
#include "QtCore/qdebug.h"

void QBic::addBlacklistedClass(const QString &wildcard)
{
    blackList.append(QRegularExpression(QRegularExpression::anchoredPattern(QRegularExpression::wildcardToRegularExpression(wildcard))));
}

void QBic::addBlacklistedClass(const QRegularExpression &expression)
{
    blackList.append(expression);
}

void QBic::removeBlacklistedClass(const QString &wildcard)
{
    blackList.removeAll(QRegularExpression(QRegularExpression::anchoredPattern(QRegularExpression::wildcardToRegularExpression(wildcard))));
}

bool QBic::isBlacklisted(const QString &className) const
{
    // all templates are blacklisted
    if (className.contains('<'))
        return true;

    for (int i = 0; i < blackList.count(); ++i)
        if (blackList[i].match(className).hasMatch())
            return true;
    return false;
}

static bool qualifiedTailMatch(const QString &expectedTail, const QString &symbol)
{
    if (symbol == expectedTail)
        return true;
    const QString tail = symbol.right(expectedTail.length() - 2);
    if (!tail.startsWith(QLatin1String("::")))
        return false;
    return tail.endsWith(expectedTail);
}

static QString innerClassVTableSymbol(const QString &outerClass, const QString &innerClass)
{
    return (QLatin1String("_ZTVN") + QString::number(outerClass.length()) + outerClass
            + QString::number(innerClass.length()) + innerClass + QLatin1Char('E'));
}

static QStringList nonVirtualThunkToDestructorSymbols(const QString &className)
{

    const QString symbolTemplate = QString::fromLatin1("%1::_ZThn%2_N%3%4");
    QStringList candidates;
    candidates << symbolTemplate.arg(className).arg(16).arg(className.length()).arg(className)
               << symbolTemplate.arg(className).arg(32).arg(className.length()).arg(className)
               << symbolTemplate.arg(className).arg(40).arg(className.length()).arg(className)
               ;

    QStringList result;
    for (int i = 0; i <= 1; ++i) {
        const QString suffix = QString::fromLatin1("D%1Ev").arg(i);
        foreach (const QString &candidate, candidates)
            result << candidate + suffix;
    }

    return result;
}

static void parseClassName(const QString &mangledClassName, QString *className, QString *qualifiedClassName)
{
    const QString outerClassCandidate = mangledClassName.section(QLatin1String("::"), 0, 0);
    const QString innerClassCandidate = mangledClassName.section(QLatin1String("::"), 1, 1);
    const QString innerClassVTableSymbolCandidate = innerClassVTableSymbol(outerClassCandidate, innerClassCandidate);
    const QString qualifiedInnerClassVTableSymbolCandidate = outerClassCandidate
                                                             + QLatin1String("::")
                                                             + innerClassCandidate
                                                             + QLatin1String("::")
                                                             + innerClassVTableSymbolCandidate;

    if (mangledClassName == qualifiedInnerClassVTableSymbolCandidate) {
        *qualifiedClassName = outerClassCandidate + QLatin1String("::") + innerClassCandidate;
        *className = innerClassCandidate;
    } else {
        *qualifiedClassName = *className = outerClassCandidate;
    }
}

static bool matchDestructor(const QString &mangledClassName, const QString &symbol)
{
    QString className;
    QString qualifiedClassName;
    parseClassName(mangledClassName, &className, &qualifiedClassName);

    const QString destructor = qualifiedClassName + QLatin1String("::~") + className;
    QStringList nonVirtualThunkToDestructorSymbolCandidates = nonVirtualThunkToDestructorSymbols(className);

    if (qualifiedTailMatch(destructor, symbol))
        return true;
    foreach (const QString &candidate, nonVirtualThunkToDestructorSymbolCandidates) {
        if (qualifiedTailMatch(candidate, symbol))
            return true;
    }

    return false;
}

static QStringList normalizedVTable(const QStringList &entry)
{
    QStringList normalized;

    // Extract the class name from lines like these:
    //     QObject::_ZTV7QObject: 14u entries
    QString className = entry.at(1).section(QLatin1Char(' '), 0, 0);
    className.chop(1);

    for (int i = 2; i < entry.count(); ++i) {
        const QString line = entry.at(i).simplified();
        bool isOk = false;
        int num = line.left(line.indexOf(QLatin1Char(' '))).toInt(&isOk);
        if (!isOk) {
            qWarning("unrecognized line: %s", qPrintable(line));
            continue;
        }

        QString sym = line.mid(line.indexOf(QLatin1Char(' ')) + 1);
        if (sym.startsWith(QLatin1Char('('))) {
            if (sym.endsWith(QLatin1Char(')'))) {
                sym = sym.mid(sym.lastIndexOf('(') + 1);
                sym.chop(1);
            } else {
                sym = sym.mid(sym.lastIndexOf(QLatin1Char(')')) + 1);
            }
        } else {
            sym = sym.left(sym.indexOf(QLatin1Char('(')));
        }

        if (sym.startsWith(QLatin1String("& ")))
            sym.remove(1, 1);

        // Clear the entry for destructors, as starting with 4.9, gcc intentionally stores null
        // pointers in the vtable for the destructors of abstract classes.
        if (matchDestructor(className, sym))
            sym = QLatin1String("0");

        if (sym.startsWith(QLatin1String("-0")) || sym.startsWith(QLatin1String("0"))) {
            if (sym.endsWith('u'))
                sym.chop(1);

            bool isOk = false;
            qint64 num = sym.toLongLong(&isOk, 16);
            if (!isOk) {
                qWarning("unrecognized token: %s", qPrintable(sym));
                continue;
            }
            if (sizeof(void*) == 4)
                sym = QString::number(int(num));
            else
                sym = QString::number(num);
        }

        normalized << QString::number(num) + QLatin1Char(' ') + sym;
    }

    return normalized;
}

QBic::Info QBic::parseOutput(const QByteArray &ba) const
{
    Info info;
    const QStringList source = QString::fromLatin1(ba).split("\n\n");

    foreach(QString str, source) {
        QStringList entry = str.split('\n');
        if (entry.count() < 2)
            continue;
        if (entry.at(0).startsWith("Class ")) {
            const QString className = entry.at(0).mid(6);
            if (isBlacklisted(className))
                continue;
            QRegularExpression rx("size=(\\d+)");
            QRegularExpressionMatch match = rx.match(entry.at(1));
            if (!match.hasMatch()) {
                qWarning("Could not parse class information for className %s", className.toLatin1().constData());
                continue;
            }
            info.classSizes[className] = match.captured(1).toInt();
        } else if (entry.at(0).startsWith("Vtable for ")) {
            const QString className = entry.at(0).mid(11);
            if (isBlacklisted(className))
                continue;
            info.classVTables[className] = normalizedVTable(entry);
        }
    }

    return info;
}

QBic::Info QBic::parseFile(const QString &fileName) const
{
    QFile f(fileName);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return Info();

    QByteArray ba = f.readAll();
    f.close();

    return parseOutput(ba);
}

enum VTableDiffResult { Match, Mismatch, Reimp };
static VTableDiffResult diffVTableEntry(const QString &v1, const QString &v2)
{
    if (v1 == v2)
        return Match;
    if (v2.endsWith(QLatin1String("__cxa_pure_virtual")))
        return Reimp;
    if (!v1.contains(QLatin1String("::")) || !v2.contains(QLatin1String("::")))
        return Mismatch;

    const QString sym1 = v1.mid(v1.lastIndexOf(QLatin1String("::")) + 2);
    const QString sym2 = v2.mid(v2.lastIndexOf(QLatin1String("::")) + 2);

    if (sym1 == sym2)
        return Reimp;

    return Mismatch;
}

QBic::VTableDiff QBic::diffVTables(const Info &oldLib, const Info &newLib) const
{
    VTableDiff result;

    for (QHash<QString, QStringList>::const_iterator it = newLib.classVTables.constBegin();
            it != newLib.classVTables.constEnd(); ++it) {
        if (!oldLib.classVTables.contains(it.key())) {
            result.addedVTables.append(it.key());
            continue;
        }
        const QStringList oldVTable = oldLib.classVTables.value(it.key());
        const QStringList vTable = it.value();
        if (vTable.count() != oldVTable.count()) {
            result.modifiedVTables.append(QPair<QString, QString>(it.key(),
                        QLatin1String("size mismatch")));
            continue;
        }

        for (int i = 0; i < vTable.count(); ++i) {
            VTableDiffResult diffResult = diffVTableEntry(vTable.at(i), oldVTable.at(i));
            switch (diffResult) {
            case Match:
                // do nothing
                break;
            case Mismatch:
                result.modifiedVTables.append(QPair<QString, QString>(oldVTable.at(i),
                            vTable.at(i)));
                break;
            case Reimp:
                result.reimpMethods.append(QPair<QString, QString>(oldVTable.at(i), vTable.at(i)));
                break;
            }
        }
    }

    for (QHash<QString, QStringList>::const_iterator it = oldLib.classVTables.constBegin();
            it != oldLib.classVTables.constEnd(); ++it) {
        if (!newLib.classVTables.contains(it.key()))
            result.removedVTables.append(it.key());
    }

    return result;
}

QBic::SizeDiff QBic::diffSizes(const Info &oldLib, const Info &newLib) const
{
    QBic::SizeDiff result;

    for (QHash<QString, int>::const_iterator it = newLib.classSizes.constBegin();
            it != newLib.classSizes.constEnd(); ++it) {
        if (!oldLib.classSizes.contains(it.key())) {
            result.added.append(it.key());
            continue;
        }
        int oldSize = oldLib.classSizes.value(it.key());
        int newSize = it.value();

        if (oldSize != newSize)
            result.mismatch.append(it.key());
    }

    for (QHash<QString, int>::const_iterator it = oldLib.classSizes.constBegin();
            it != oldLib.classSizes.constEnd(); ++it) {
        if (!newLib.classSizes.contains(it.key()))
            result.removed.append(it.key());
    }

    return result;
}

