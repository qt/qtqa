#!/usr/bin/env perl
# Copyright (C) 2017 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only WITH Qt-GPL-exception-1.0

use strict;
use warnings;

package QtQA::App::Crash;

# This script deliberately crashes by dereferencing an invalid pointer.
use Inline 'C';

sub main
{
    dereference_bad_pointer();
    die 'unexpectedly still alive after bad memory access!';
}

main unless caller;
1;

__DATA__
__C__

#include <stdio.h>

void dereference_bad_pointer()
{
    int* i = 0;
    /* fprintf ensures compiler can't optimize this out */
    fprintf(stderr, "i[1]: %d\n", i[1]);
}

