// Copyright (C) 2017 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only WITH Qt-GPL-exception-1.0

#include <stdio.h>

#ifdef _WIN32
# include <windows.h>
# define sleep(x) Sleep(x*1000)
#else
# include <unistd.h>
#endif


int main(int argc, char**)
{
    /*
        This sleep gives predictable timing for a "fail" test vs a "pass" test,
        for testing of parallel_test
    */
    sleep( 2 );
    printf( "passing. %d arg(s)\n", argc );

    return 0;
}
