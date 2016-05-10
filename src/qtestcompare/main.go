/****************************************************************************
**
** Copyright (C) 2016 Robin Burchell <robin.burchell@viroteck.net>
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

package main

import (
	"archive/zip"
	"encoding/xml"
	"flag"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"os"
	"sort"
	"strconv"

	"code.qt.io/qt/qtqa.git/src/goqtestlib"
	"github.com/olekukonko/tablewriter"
)

func loadTestResult(path string) *goqtestlib.ParsedTestResult {
	tr := goqtestlib.TestResult{PathToResultsXML: path}
	r, err := tr.Parse()
	if err != nil {
		log.Fatalf("Can't open result at path %s: %s", path, err)
	}

	return r
}

type MergedTestResult struct {
	Name                string
	OldDuration         *float64
	NewDuration         *float64
	OldInstructionReads *float64
	NewInstructionReads *float64
}

type ByName []MergedTestResult

func (s ByName) Len() int { return len(s) }
func (s ByName) Swap(i int, j int) {
	s[i], s[j] = s[j], s[i]
}
func (s ByName) Less(i int, j int) bool {
	return s[i].Name < s[j].Name
}

func describeChange(pChange float64) string {
	pStr := strconv.FormatFloat(pChange, 'f', 2, 64)
	if pChange > 0 {
		return fmt.Sprintf("+%s%%", pStr)
	} else if pChange < 0 {
		return fmt.Sprintf("%s%% FASTER! :)", pStr)
	} else {
		return "more or less the same"
	}
}

type MergedTestResults map[string]MergedTestResult

func (results *MergedTestResults) addOldTestCase(prefix string, testCase *goqtestlib.ParsedTestResult) {
	// XXX: add a way to specify what type of benchmarkresult to look for.
	for _, fn := range testCase.Functions {
		qualifiedName := prefix + fn.Name
		for _, br := range fn.BenchmarkResults {
			nameWithTag := qualifiedName
			if br.Tag != "" {
				nameWithTag += ":" + br.Tag
			}
			res := (*results)[nameWithTag]
			res.Name = nameWithTag
			val := br.Value
			if br.Metric == "WalltimeMilliseconds" {
				res.OldDuration = &val
			} else if br.Metric == "InstructionReads" {
				res.OldInstructionReads = &val
			}
			(*results)[nameWithTag] = res
		}
	}
}

func (results *MergedTestResults) addNewTestCase(prefix string, testCase *goqtestlib.ParsedTestResult) {
	for _, fn := range testCase.Functions {
		qualifiedName := prefix + fn.Name
		for _, br := range fn.BenchmarkResults {
			nameWithTag := qualifiedName
			if br.Tag != "" {
				nameWithTag += ":" + br.Tag
			}
			res := (*results)[nameWithTag]
			res.Name = nameWithTag
			val := br.Value
			if br.Metric == "WalltimeMilliseconds" {
				res.NewDuration = &val
			} else if br.Metric == "InstructionReads" {
				res.NewInstructionReads = &val
			}
			(*results)[nameWithTag] = res
		}
	}
}

func (results *MergedTestResults) compare(output io.Writer) {
	// convert mergedResults to a slice, and sort it for stable results.
	sortedResults := []MergedTestResult{}

	for _, mr := range *results {
		sortedResults = append(sortedResults, mr)
	}

	sort.Sort(ByName(sortedResults))

	table := tablewriter.NewWriter(output)
	table.SetAutoFormatHeaders(false)
	table.SetHeader([]string{"Test", "From", "To", "Details"})
	table.SetBorder(false)

	totalPChange := 0.0

	for _, mr := range sortedResults {
		row := []string{}
		row = append(row, mr.Name)

		if mr.OldInstructionReads != nil && mr.NewInstructionReads != nil {
			pChange := (*mr.NewInstructionReads - *mr.OldInstructionReads) / *mr.OldInstructionReads * 100
			totalPChange += pChange
			row = append(row, strconv.FormatFloat(*mr.OldInstructionReads, 'f', 2, 64)+" instr")
			row = append(row, strconv.FormatFloat(*mr.NewInstructionReads, 'f', 2, 64)+" instr")
			row = append(row, describeChange(pChange))

		} else if mr.OldDuration != nil && mr.NewDuration != nil {
			pChange := (*mr.NewDuration - *mr.OldDuration) / *mr.OldDuration * 100
			totalPChange += pChange
			row = append(row, strconv.FormatFloat(*mr.OldDuration, 'f', 2, 64)+" ms")
			row = append(row, strconv.FormatFloat(*mr.NewDuration, 'f', 2, 64)+" ms")
			row = append(row, describeChange(pChange))
		} else {
			// the comparison can't be made because either the data types are
			// differing between the two runs, or we're missing a test in one
			// run.
			//
			// try find something to display for old and new. fall back to "-"
			// if we can't.
			ostr := "-"
			nstr := "-"

			if mr.OldDuration != nil {
				ostr = strconv.FormatFloat(*mr.OldDuration, 'f', 2, 64) + " ms"
			} else if mr.OldInstructionReads != nil {
				ostr = strconv.FormatFloat(*mr.OldInstructionReads, 'f', 2, 64) + " instr"
			}

			if mr.NewDuration != nil {
				nstr = strconv.FormatFloat(*mr.NewDuration, 'f', 2, 64) + " ms"
			} else if mr.NewInstructionReads != nil {
				nstr = strconv.FormatFloat(*mr.NewInstructionReads, 'f', 2, 64) + " instr"
			}

			row = append(row, ostr)
			row = append(row, nstr)
			row = append(row, "-")
		}

		table.Append(row)
	}

	verdict := ""
	totalPStr := strconv.FormatFloat(totalPChange, 'f', 2, 64)
	if totalPChange > 0 {
		verdict = fmt.Sprintf("+%s%% :(", totalPStr)
	} else if totalPChange < 0 {
		verdict = fmt.Sprintf("%s%% :)", totalPStr)
	} else {
		verdict = "more or less the same"
	}

	table.SetFooter([]string{"Overall result", "", "", verdict})
	table.Render()

}

func compareSingleTestRuns(oxml string, nxml string) {
	oldTest := loadTestResult(oxml)
	newTest := loadTestResult(nxml)

	if oldTest.Name != newTest.Name {
		log.Fatalf("I can't compare two totally different things (old: %s, new: %s)", oldTest.Name, newTest.Name)
		return
	}

	// merge the test functions into a singular representation.
	mergedResults := MergedTestResults{}
	prefix := ""
	mergedResults.addOldTestCase(prefix, oldTest)
	mergedResults.addNewTestCase(prefix, newTest)

	mergedResults.compare(os.Stdout)
}

func unmarshalTestResult(reader io.ReadCloser) (*goqtestlib.ParsedTestResult, error) {
	defer reader.Close()
	xmlContents, err := ioutil.ReadAll(reader)
	if err != nil {
		return nil, fmt.Errorf("Error reading results xml file: %s", err)
	}

	testCase := &goqtestlib.ParsedTestResult{}
	if err = xml.Unmarshal(xmlContents, &testCase); err != nil {
		return nil, fmt.Errorf("Error unmarshalling testlib xml output: %s", err)
	}
	return testCase, nil
}

type testArchive struct {
	reader *zip.ReadCloser
}

func openTestArchive(path string) (*testArchive, error) {
	reader, err := zip.OpenReader(path)
	return &testArchive{reader}, err
}

func (archive *testArchive) forEachTestCase(callback func(path string, testCase *goqtestlib.ParsedTestResult) error) error {
	for _, f := range archive.reader.File {
		reader, err := f.Open()
		if err != nil {
			log.Fatalf("Error opening entry in zip archive %s: %s", f.Name, err)
		}
		result, err := unmarshalTestResult(reader)
		if err != nil {
			log.Fatalf("Error unpacking test result for %s from zip archive: %s", f.Name, err)
		}
		if err := callback(f.Name, result); err != nil {
			return err
		}
	}
	return nil
}

func (archive *testArchive) Close() error {
	return archive.reader.Close()
}

func compareArchivedTestRuns(oarch string, narch string) {
	fmt.Printf("Comparing zipped runs %s vs %s\n", oarch, narch)

	or, err := openTestArchive(oarch)
	if err != nil {
		log.Fatalf("Can't open old archive: %s\n", err)
	}
	defer or.Close()

	nr, err := openTestArchive(narch)
	if err != nil {
		log.Fatalf("Can't open new archive: %s\n", err)
	}
	defer nr.Close()

	// this is a map of xml to result, so e.g:
	// qml/binding.xml -> result.
	mergedResults := MergedTestResults{}

	or.forEachTestCase(func(path string, testCase *goqtestlib.ParsedTestResult) error {
		mergedResults.addOldTestCase(path+"/", testCase)
		return nil
	})
	nr.forEachTestCase(func(path string, testCase *goqtestlib.ParsedTestResult) error {
		mergedResults.addNewTestCase(path+"/", testCase)
		return nil
	})

	mergedResults.compare(os.Stdout)
}

func main() {
	var nf = flag.String("new", "", "the changed XML result to compare against")
	var of = flag.String("old", "", "the baseline XML result to compare against")

	var na = flag.String("newarchive", "", "the changed archived results to compare against")
	var oa = flag.String("oldarchive", "", "the baseline archived results to compare against")
	flag.Parse()

	nxml := *nf
	oxml := *of

	narch := *na
	oarch := *oa

	hasNewFile := len(nxml) > 0
	hasOldFile := len(oxml) > 0

	hasNewArch := len(narch) > 0
	hasOldArch := len(oarch) > 0

	if (!hasNewFile || !hasOldFile) && (!hasNewArch || !hasOldArch) {
		log.Fatalf("You need to provide either -new & -old, or -newarchive & -oldarchive.")
		return
	}

	if hasNewFile && hasOldFile {
		compareSingleTestRuns(oxml, nxml)
	} else {
		compareArchivedTestRuns(oarch, narch)
	}
}
