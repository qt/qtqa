#!/usr/bin/env perl
# Copyright (C) 2017 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only WITH Qt-GPL-exception-1.0

use strict;
use warnings;

package QtQA::App::DivideByZero;

# This script deliberately performs an integer division by zero.
use Inline 'C';

sub main
{
    divide_by_zero();
    die 'unexpectedly still alive after dividing by zero!';
}

main unless caller;
1;

__DATA__
__C__

#include <stdio.h>

void divide_by_zero()
{
    int i = 0;
    /* fprintf ensures compiler can't optimize this out */
    fprintf(stderr, "1/i %d\n", (1/i));
}

