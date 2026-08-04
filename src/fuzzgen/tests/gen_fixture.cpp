// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only
//
// gen_fixture — generates a real fuzz harness for tests/fixtures/fakeclass.h
// via the actual FuzzCppGenerator, for the Tier-3 end-to-end crash-
// attribution autotest. Not a scanner: the method list is hand-built here,
// matching fakeclass.h exactly, since the fixture exists solely to give the
// generator something small and deterministic to work with.
//
// Usage: gen_fixture <output .cpp path>

#include "codegen.h"

#include <iostream>

int main(int argc, char *argv[])
{
    if (argc != 2) {
        std::cerr << "Usage: gen_fixture <output .cpp path>\n";
        return 1;
    }

    using namespace QtFuzz;

    MethodSignature crashy;
    crashy.name = "crashyMethod";
    crashy.params.push_back(MethodParam{ "int", "x", false, false });

    MethodSignature safe;
    safe.name = "safeMethod";

    std::vector<MethodSignature> methods = { crashy, safe };

    FuzzCppGenerator gen("FakeClass", argv[1], AppType::Core, methods,
                         /*hasQObject=*/false, "\"fakeclass.h\"");
    if (!gen.generate()) {
        std::cerr << "gen_fixture: FuzzCppGenerator::generate() failed\n";
        return 1;
    }
    return 0;
}
