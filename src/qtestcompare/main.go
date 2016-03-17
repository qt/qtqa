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
	"flag"
	"fmt"
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

func main() {
	var nf = flag.String("new", "", "the changed XML result to compare against")
	var of = flag.String("old", "", "the baseline XML result to compare against")
	flag.Parse()

	nxml := *nf
	oxml := *of

	if len(nxml) == 0 {
		log.Fatalf("no new provided - nothing to compare")
		return
	}

	if len(oxml) == 0 {
		log.Fatalf("no old provided - nothing to compare against")
		return
	}

	oldTest := loadTestResult(oxml)
	newTest := loadTestResult(nxml)

	if oldTest.Name != newTest.Name {
		log.Fatalf("I can't compare two totally different things (old: %s, new: %s)", oldTest.Name, newTest.Name)
		return
	}

	// merge the test functions into a singular representation.
	mergedResults := map[string]MergedTestResult{}

	// XXX: add a way to specify what type of benchmarkresult to look for.
	for _, fn := range oldTest.Functions {
		for _, br := range fn.BenchmarkResults {
			res := mergedResults[fn.Name]
			res.Name = fn.Name
			if br.Metric == "WalltimeMilliseconds" {
				res.OldDuration = &(br.Value)
			} else if br.Metric == "InstructionReads" {
				res.OldInstructionReads = &(br.Value)
			}
			mergedResults[fn.Name] = res
		}
	}
	for _, fn := range newTest.Functions {
		for _, br := range fn.BenchmarkResults {
			res := mergedResults[fn.Name]
			res.Name = fn.Name
			if br.Metric == "WalltimeMilliseconds" {
				res.NewDuration = &(br.Value)
			} else if br.Metric == "InstructionReads" {
				res.NewInstructionReads = &(br.Value)
			}
			mergedResults[fn.Name] = res
		}
	}

	// convert mergedResults to a slice, and sort it for stable results.
	sortedResults := []MergedTestResult{}

	for _, mr := range mergedResults {
		sortedResults = append(sortedResults, mr)
	}

	sort.Sort(ByName(sortedResults))

	table := tablewriter.NewWriter(os.Stdout)
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

	table.SetFooter([]string{newTest.Name, "", "", verdict})
	table.Render()

}
