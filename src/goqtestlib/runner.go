// Copyright (C) 2016 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
package goqtestlib

import (
	"errors"
	"fmt"
	"io/ioutil"
	"os"
	"os/exec"
	"path/filepath"
)

const (
	// NoRepetitionsOnFailure is a convenience value for indicating that even a single failing test function is considered an overall failure.
	NoRepetitionsOnFailure int = 0
)

// RunFunction is used by GenerateTestResult to run unit tests in the current environment. In
// the agent this usually means running "make check".
type RunFunction func(extraArgs []string) error

// GenerateTestResult sets up the environment for QTestLib style testing and calls the runner function for
// to produce the test results. The repetitionsOnFailure allows for a failing test function to fail once
// and have that failure to be ignored under the condition that consequent repeated running of the same
// test function does not produce any failures.
func GenerateTestResult(name string, resultsDirectory string, repetitionsOnFailure int, runner RunFunction) (*TestResult, error) {
	resultsDir := filepath.Join(resultsDirectory, filepath.Dir(name))
	os.MkdirAll(resultsDir, 0755)
	resultsFile, err := ioutil.TempFile(resultsDirectory, name)
	if err != nil {
		return nil, fmt.Errorf("Error creating temporary file to collected test output: %s", err)
	}
	testResult := &TestResult{
		TestCaseName:     name,
		PathToResultsXML: resultsFile.Name(),
	}
	resultsFile.Close()

	os.Setenv("QT_CI_RESULTS_PATH", testResult.PathToResultsXML)

	err = runner([]string{"-o", testResult.PathToResultsXML + ",xml", "-o", "-,txt"})

	os.Setenv("QT_CI_RESULTS_PATH", "")

	_, ok := err.(*exec.ExitError)
	if err != nil && !ok {
		return nil, err
	}

	fileInfo, statErr := os.Stat(testResult.PathToResultsXML)
	if os.IsNotExist(statErr) || fileInfo.Size() == 0 {
		return nil, err
	}

	if err != nil {
		parsedResult, err := testResult.Parse()
		if err != nil {
			return nil, err
		}

		failingFunctions := parsedResult.FailingFunctions()
		if len(failingFunctions) > 0 {
			if repetitionsOnFailure == 0 {
				return nil, errors.New("Tests failed")
			}

			for _, testFunction := range failingFunctions {
				for i := 0; i < repetitionsOnFailure; i++ {
					if err = runner([]string{testFunction}); err != nil {
						return nil, err
					}
				}
			}
		}
	}

	return testResult, nil
}
