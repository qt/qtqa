// Copyright (C) 2016 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
package goqtestlib

import (
	"os"
)

// SetEnvironmentVariableAndRestoreOnExit immediately sets the specified environment variable to the given value. However
// as opposed to os.Setenv it returns a closure that will restore the old value. This is useful in conjunction with deferred
// calls, like so: defer SetEnvironmentVariableAndRestoreOnExit("someVar", "someValue")()
func SetEnvironmentVariableAndRestoreOnExit(variable string, value string) func() {
	oldValue := os.Getenv(variable)
	os.Setenv(variable, value)
	return func() {
		os.Setenv(variable, oldValue)
	}
}
