// Copyright (C) 2016 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
package goqtestlib

import (
	"encoding/xml"
	"flag"
	"fmt"
	"io/ioutil"
	"os"
	"os/exec"
	"strings"
	"testing"
)

type Output struct {
	file   string
	format string
}

type outputOption struct {
	outputs []Output
}

func (o *outputOption) Set(value string) error {
	s := strings.Split(value, ",")
	o.outputs = append(o.outputs, Output{file: s[0], format: s[1]})
	return nil
}

func (o *outputOption) String() string {
	return fmt.Sprintf("%v", o.outputs)
}

func (o *outputOption) XMLOutputFileName() string {
	for _, o := range o.outputs {
		if o.file != "-" && o.format == "xml" {
			return o.file
		}
	}
	return ""
}

func testResultsEqual(left *ParsedTestResult, right *ParsedTestResult) bool {
	leftBytes, _ := xml.Marshal(left)
	rightBytes, _ := xml.Marshal(right)
	return string(leftBytes) == string(rightBytes)
}

func makeTestRunner(t *testing.T, outputToProduce ...*ParsedTestResult) RunFunction {
	return func(extraArgs []string) error {
		option := outputOption{}
		flagSet := flag.NewFlagSet("testlibflagset", flag.PanicOnError)
		flagSet.Var(&option, "o", "output specifier")
		if err := flagSet.Parse(extraArgs); err != nil {
			return err
		}

		output := outputToProduce[0]
		outputToProduce = outputToProduce[1:]

		if outputFile := option.XMLOutputFileName(); outputFile != "" {
			bytes, err := xml.MarshalIndent(output, "    ", "    ")
			if err != nil {
				return err
			}
			if err := ioutil.WriteFile(outputFile, bytes, 0644); err != nil {
				return err
			}
		}

		if len(output.FailingFunctions()) > 0 {
			return &exec.ExitError{}
		}

		return nil
	}
}

const (
	initialXMLOutputToProduce = `<?xml version="1.0" encoding="UTF-8"?>
<TestCase name="tst_QIODevice">
<Environment>
    <QtVersion>5.6.0</QtVersion>
    <QtBuild>Qt 5.6.0 (x86_64&#x002D;little_endian&#x002D;lp64 shared (dynamic) debug build; by GCC 4.9.2)</QtBuild>
    <QTestVersion>5.6.0</QTestVersion>
</Environment>
<TestFunction name="initTestCase">
<Incident type="pass" file="" line="0" />
    <Duration msecs="0.274962"/>
</TestFunction>
</TestCase>
`
)

func TestGenerateTestResult(t *testing.T) {
	passingOutput := &ParsedTestResult{}
	xml.Unmarshal([]byte(initialXMLOutputToProduce), passingOutput)

	testRunner := makeTestRunner(t, passingOutput)

	result, err := GenerateTestResult("testname", os.TempDir(), NoRepetitionsOnFailure, testRunner)
	if err != nil {
		t.Errorf("Error generating test result: %s", err)
		t.FailNow()
	}

	if result == nil {
		t.Errorf("Unexpected missing test result")
		t.FailNow()
	}

	if result.TestCaseName != "testname" {
		t.Errorf("Unexpected test case name. Got %s", result.TestCaseName)
	}

	actualParsedResult, err := result.Parse()
	if err != nil {
		t.Errorf("Could not read/parse results xml file at %s: %s", result.PathToResultsXML, err)
		t.FailNow()
	}

	if !testResultsEqual(actualParsedResult, passingOutput) {
		t.Errorf("Unexpected actual output. Got %v", actualParsedResult)
		t.FailNow()
	}
}

func TestFailingOnceTestResult(t *testing.T) {
	failingOutput := &ParsedTestResult{}
	xml.Unmarshal([]byte(initialXMLOutputToProduce), failingOutput)
	failingOutput.Functions[0].Incidents[0].Type = "fail"

	passingOutput := &ParsedTestResult{}
	xml.Unmarshal([]byte(initialXMLOutputToProduce), passingOutput)
	passingOutput.Functions[0].Incidents[0].Type = "pass"

	testRunner := makeTestRunner(t, failingOutput, passingOutput, passingOutput)

	result, err := GenerateTestResult("testname", os.TempDir(), 2 /*repetitions*/, testRunner)
	if err != nil {
		t.Errorf("Error generating test result: %s", err)
		t.FailNow()
	}

	if result == nil {
		t.Errorf("Unexpected missing test result")
		t.FailNow()
	}

	if result.TestCaseName != "testname" {
		t.Errorf("Unexpected test case name. Got %s", result.TestCaseName)
	}

	actualParsedResult, err := result.Parse()
	if err != nil {
		t.Errorf("Could not read/parse results xml file at %s: %s", result.PathToResultsXML, err)
		t.FailNow()
	}

	if !testResultsEqual(actualParsedResult, failingOutput) {
		t.Errorf("Unexpected actual  output. Got %v", actualParsedResult)
		t.FailNow()
	}
}

func TestFailingOnceWithTagTestResult(t *testing.T) {
	failingOutput := &ParsedTestResult{}
	xml.Unmarshal([]byte(initialXMLOutputToProduce), failingOutput)

	passingIncident1 := Incident{}
	passingIncident1.Type = "pass"
	passingIncident1.DataTag = "tag1"

	failingIncident2 := Incident{}
	failingIncident2.Type = "fail"
	failingIncident2.DataTag = "tag2"

	passingIncident3 := Incident{}
	passingIncident3.Type = "pass"
	passingIncident3.DataTag = "tag3"

	failingOutput.Functions[0].Incidents = append([]Incident(nil), passingIncident1, failingIncident2, passingIncident3)

	if len(failingOutput.Functions[0].FailingIncidents()) != 1 {
		t.Errorf("Incorrect number of failing incidents. Got %v", failingOutput.Functions[0].FailingIncidents())
		t.FailNow()
	}
	if failingOutput.Functions[0].FailingIncidents()[0] != "initTestCase" {
		t.Errorf("Incorrect failing tagged incidents. Got %v", failingOutput.Functions[0].FailingIncidents()[0])
		t.FailNow()
	}

	passingOutput := &ParsedTestResult{}
	xml.Unmarshal([]byte(initialXMLOutputToProduce), passingOutput)

	passingOutput.Functions[0].Incidents = append([]Incident(nil), failingOutput.Functions[0].Incidents...)
	passingOutput.Functions[0].Incidents[1].Type = "pass"

	testRunner := makeTestRunner(t, failingOutput, passingOutput, passingOutput)

	result, err := GenerateTestResult("testname", os.TempDir(), 2 /*repetitions*/, testRunner)
	if err != nil {
		t.Errorf("Error generating test result: %s", err)
		t.FailNow()
	}

	if result == nil {
		t.Errorf("Unexpected missing test result")
		t.FailNow()
	}

	if result.TestCaseName != "testname" {
		t.Errorf("Unexpected test case name. Got %s", result.TestCaseName)
	}

	actualParsedResult, err := result.Parse()
	if err != nil {
		t.Errorf("Could not read/parse results xml file at %s: %s", result.PathToResultsXML, err)
		t.FailNow()
	}

	if !testResultsEqual(actualParsedResult, failingOutput) {
		t.Errorf("Unexpected actual  output. Got %v", actualParsedResult)
		t.FailNow()
	}
}

func TestFailingNonTestLibTest(t *testing.T) {
	runner := func([]string) error {
		// simulate "make check" failing, but we did not write a results .xml file
		return &exec.ExitError{}
	}

	result, err := GenerateTestResult("testname", os.TempDir(), NoRepetitionsOnFailure, runner)
	if result != nil {
		t.Errorf("Unexpected test result. Expected nil got %v", result)
		t.FailNow()
	}

	if err == nil {
		t.Errorf("Unexpected test success. Expected error")
		t.FailNow()
	}
}
