// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only
//
// scanner_diff_selftest — exercises classesDeclaredIn()/classesDefinedIn()
// (the real scanner functions qtdiff uses, not a reimplementation) against
// hand-written header/source text fixtures. No filesystem, no Qt
// dependency — runs identically and quickly on macOS, Windows, and Linux.

#include "scanner.h"

#include <iostream>
#include <string>

using namespace QtFuzz;

namespace {

int g_failures = 0;

void check(bool cond, const std::string &what)
{
    if (!cond) {
        std::cerr << "FAIL: " << what << "\n";
        ++g_failures;
    } else {
        std::cout << "ok: " << what << "\n";
    }
}

bool contains(const std::vector<std::string> &v, const std::string &name)
{
    for (const auto &n : v) {
        if (n == name)
            return true;
    }
    return false;
}

} // namespace

int main()
{
    // ── classesDeclaredIn: multiple classes in one header ────────────────────
    {
        const std::string header = R"(
            class Q_CORE_EXPORT QFoo {
            public:
                QFoo();
                void bar();
            };

            class QBar : public QFoo {
            public:
                QBar();
            };
        )";
        auto names = classesDeclaredIn(header);
        check(contains(names, "QFoo"), "classesDeclaredIn finds exported class QFoo");
        check(contains(names, "QBar"), "classesDeclaredIn finds unexported class QBar");
        check(names.size() == 2, "classesDeclaredIn finds exactly 2 classes");
    }

    // ── classesDeclaredIn: Private/Impl/_p suffixes are excluded ─────────────
    {
        const std::string header = R"(
            class QFooPrivate {
            public:
                int state;
            };
            class QFoo {
            public:
                QFoo();
            };
        )";
        auto names = classesDeclaredIn(header);
        check(!contains(names, "QFooPrivate"), "classesDeclaredIn excludes *Private classes");
        check(contains(names, "QFoo"), "classesDeclaredIn still finds QFoo alongside excluded Private");
    }

    // ── classesDeclaredIn: no Q-prefixed class in the file ────────────────────
    {
        const std::string header = R"(
            class NetworkTest {
            public:
                NetworkTest();
            };
        )";
        auto names = classesDeclaredIn(header);
        check(names.empty(), "classesDeclaredIn returns nothing for a non-Q-prefixed class");
    }

    // ── classesDefinedIn: out-of-line definitions at depth 0 ─────────────────
    {
        const std::string source = R"(
            #include "qfoo.h"

            QFoo::QFoo()
            {
                doSomethingUnrelated();
            }

            void QFoo::bar()
            {
                QOther::helper(); // nested call inside a method body — must not count
            }

            void QBar::baz()
            {
            }
        )";
        auto names = classesDefinedIn(source);
        check(contains(names, "QFoo"), "classesDefinedIn finds QFoo from QFoo::bar() definition");
        check(contains(names, "QBar"), "classesDefinedIn finds QBar from QBar::baz() definition");
        check(!contains(names, "QOther"),
              "classesDefinedIn ignores QOther::helper() call inside a method body (depth > 0)");
        check(names.size() == 2, "classesDefinedIn finds exactly 2 classes");
    }

    // ── classesDefinedIn: no qualified definitions ────────────────────────────
    {
        const std::string source = R"(
            int main() { return 0; }
        )";
        auto names = classesDefinedIn(source);
        check(names.empty(), "classesDefinedIn returns nothing when no Class::member(...) exists");
    }

    // ── classesDefinedIn: a string literal ending in an escaped backslash
    // ("C:\\", i.e. quote C : backslash backslash quote) must not be
    // mistaken for an escaped closing quote. A single preceding backslash
    // escapes a quote, but a *pair* of backslashes is itself one escaped
    // backslash — the quote right after it is unescaped and really does
    // close the string. Getting this wrong leaves the parser stuck
    // believing it's still inside the string for the rest of the file,
    // which would make it miss every later definition (QBar::baz() here).
    {
        const std::string source = R"(
            void QFoo::setPath()
            {
                const char *p = "C:\\";
            }

            void QBar::baz()
            {
            }
        )";
        auto names = classesDefinedIn(source);
        check(contains(names, "QFoo"),
              "classesDefinedIn finds QFoo despite the C:\\\\ string literal");
        check(contains(names, "QBar"),
              "classesDefinedIn still finds QBar::baz() after the escaped-backslash string");
    }

    if (g_failures > 0) {
        std::cerr << g_failures << " check(s) failed.\n";
        return 1;
    }
    std::cout << "All checks passed.\n";
    return 0;
}
