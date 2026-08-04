// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only
//
// A synthetic, deliberately-crashing class used only by the Tier-3
// end-to-end crash-attribution autotest (see tests/gen_fixture.cpp). Not a
// real Qt class — this exists purely to give the generated fuzz harness a
// guaranteed, deterministic crash to attribute correctly.
#pragma once

class FakeClass
{
public:
    FakeClass() = default;

    // Always crashes — deterministic, so the autotest doesn't depend on a
    // fuzzed argument value happening to hit some magic number.
    void crashyMethod(int)
    {
        volatile int *p = nullptr;
        *p = 1;
    }

    void safeMethod() { }
};
