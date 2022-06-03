// Copyright (C) 2016 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
package goqtestlib

import (
	"os"
	"testing"
)

func TestEnvironmentSet(t *testing.T) {
	testVariable := "myVariable"
	os.Setenv(testVariable, "initialValue")

	if os.Getenv(testVariable) != "initialValue" {
		t.Fatal("Invalid initial environment variable value")
	}

	func() {
		defer SetEnvironmentVariableAndRestoreOnExit(testVariable, "tempValue")()
		if os.Getenv(testVariable) != "tempValue" {
			t.Fatal("Environment variable should be set to the temporary value here")
		}
	}()

	if os.Getenv(testVariable) != "initialValue" {
		t.Fatal("Environment variable not restored")
	}
}
