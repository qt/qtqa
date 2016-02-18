/****************************************************************************
**
** Copyright (C) 2016 The Qt Company Ltd.
** Contact: https://www.qt.io/licensing/
**
** This file is part of the QtCore module of the Qt Toolkit.
**
** $QT_BEGIN_LICENSE:LGPL$
** Commercial License Usage
** Licensees holding valid commercial Qt licenses may use this file in
** accordance with the commercial license agreement provided with the
** Software or, alternatively, in accordance with the terms contained in
** a written agreement between you and The Qt Company. For licensing terms
** and conditions see https://www.qt.io/terms-conditions. For further
** information use the contact form at https://www.qt.io/contact-us.
**
** GNU Lesser General Public License Usage
** Alternatively, this file may be used under the terms of the GNU Lesser
** General Public License version 3 as published by the Free Software
** Foundation and appearing in the file LICENSE.LGPL3 included in the
** packaging of this file. Please review the following information to
** ensure the GNU Lesser General Public License version 3 requirements
** will be met: https://www.gnu.org/licenses/lgpl-3.0.html.
**
** GNU General Public License Usage
** Alternatively, this file may be used under the terms of the GNU
** General Public License version 2.0 or (at your option) the GNU General
** Public license version 3 or any later version approved by the KDE Free
** Qt Foundation. The licenses are as published by the Free Software
** Foundation and appearing in the file LICENSE.GPL2 and LICENSE.GPL3
** included in the packaging of this file. Please review the following
** information to ensure the GNU General Public License requirements will
** be met: https://www.gnu.org/licenses/gpl-2.0.html and
** https://www.gnu.org/licenses/gpl-3.0.html.
**
** $QT_END_LICENSE$
**
****************************************************************************/
package goqtestlib

import (
	"archive/tar"
	"compress/gzip"
	"encoding/xml"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"os"
)

// Environment provides information about the environment used to
// run the unit tests, such as the Qt version used.
type Environment struct {
	QtVersion    string
	QtBuild      string
	QTestVersion string
}

// IncidentHeader provides the fields that are common for Incident
// and Message, basically the file name and line numbers of
// where the message was produced or the incident happened.
type IncidentHeader struct {
	Type string `xml:"type,attr"`
	File string `xml:"file,attr"`
	Line int    `xml:"line,attr"`
}

// Duration measures the time it took to run the test.
type Duration struct {
	Msecs float64 `xml:"msecs,attr"`
}

// Incident usually refers to a failing or a passing test function.
type Incident struct {
	IncidentHeader
	DataTag string `xml:",omitempty"`
}

// Message represents an arbitrary message produced by QTestLib, usually qDebug() output.
type Message struct {
	IncidentHeader
	Description string
}

// BenchmarkResult represents the results produced when running benchmarks with QTestLib.
type BenchmarkResult struct {
	Metric     string  `xml:"metric,attr"`
	Tag        string  `xml:"tag,attr"`
	Value      float64 `xml:"value,attr"`
	Iterations int     `xml:"iterations,attr"`
}

// TestFunction represents the results of running a single test function.
type TestFunction struct {
	Name             string            `xml:"name,attr"`
	Incidents        []Incident        `xml:"Incident"`
	Messages         []Message         `xml:"Message"`
	BenchmarkResults []BenchmarkResult `xml:"BenchmarkResult"`
	Duration         Duration          `xml:"Duration"`
}

// FailingIncidents returns a list of incidents that represent tests failures
// while the test function was running. For example in table driven tests
// that is one entry per failed test row.
func (t *TestFunction) FailingIncidents() []string {
	var failures []string
	for _, incident := range t.Incidents {
		if incident.Type == "fail" {
			name := t.Name
			/* No support for tags at the moment due to quoting issues on Windows
			if incident.DataTag != "" {
				name += ":"
				name += incident.DataTag
			}
			*/
			failures = append(failures, name)
			break
		}
	}
	return failures
}

// ParsedTestResult represents the parsed output of running tests with QTestLib.
type ParsedTestResult struct {
	XMLName   xml.Name       `xml:"TestCase"`
	Name      string         `xml:"name,attr"`
	Env       Environment    `xml:"Environment"`
	Functions []TestFunction `xml:"TestFunction"`
	Duration  Duration       `xml:"Duration"`
}

// FailingFunctions returns list of test functions that failed during an earlier run.
func (p *ParsedTestResult) FailingFunctions() []string {
	var failing []string
	for _, f := range p.Functions {
		failing = append(failing, f.FailingIncidents()...)
	}
	return failing
}

// TestResult provides access to the results of executing a single unit test, such as tst_qiodevice in Qt.
type TestResult struct {
	TestCaseName     string // local to the module, for example tests/auto/corelib/io/qiodevice
	PathToResultsXML string // path where the testlib xml output is stored
}

// Parse attempts to read the XML file the PathToResultsXML field points to.
func (r *TestResult) Parse() (*ParsedTestResult, error) {
	xmlContents, err := ioutil.ReadFile(r.PathToResultsXML)
	if err != nil {
		return nil, fmt.Errorf("Error reading results xml file %s: %s", r.PathToResultsXML, err)
	}

	testCase := &ParsedTestResult{}
	if err = xml.Unmarshal(xmlContents, &testCase); err != nil {
		return nil, fmt.Errorf("Error unmarshalling testlib xml output: %s", err)
	}

	return testCase, err
}

// TestResultCollection is a collection of test results after running tests on a module of source code.
type TestResultCollection []TestResult

// Archive produces a .tar.gz archive of the collection and writes it into the given destination writer.
func (collection *TestResultCollection) Archive(destination io.Writer) (err error) {
	compressor := gzip.NewWriter(destination)

	archiver := tar.NewWriter(compressor)

	log.Printf("Collecting %v test results ...\n", len(*collection))

	for _, result := range *collection {
		stat, err := os.Stat(result.PathToResultsXML)
		if err != nil {
			return fmt.Errorf("Error call stat() on %s: %s", result.PathToResultsXML, err)
		}
		header, err := tar.FileInfoHeader(stat, "")
		if err != nil {
			return fmt.Errorf("Error creating tar file header for %s: %s", result.PathToResultsXML, err)
		}
		header.Name = result.TestCaseName + ".xml"

		if err := archiver.WriteHeader(header); err != nil {
			return fmt.Errorf("Error writing tar file header for %s: %s", result.PathToResultsXML, err)
		}

		file, err := os.Open(result.PathToResultsXML)
		if err != nil {
			return fmt.Errorf("Error opening results file %s: %s", result.PathToResultsXML, err)
		}

		if _, err := io.Copy(archiver, file); err != nil {
			file.Close()
			return fmt.Errorf("Error writing results file %s into archive: %s", result.PathToResultsXML, err)
		}

		file.Close()
	}

	if err := archiver.Close(); err != nil {
		return err
	}

	if err := compressor.Close(); err != nil {
		return err
	}

	return nil
}
