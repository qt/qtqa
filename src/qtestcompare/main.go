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
	"code.qt.io/qt/qtqa.git/src/goqtestlib"
	"flag"
	"fmt"
	"github.com/olekukonko/tablewriter"
	"log"
	"os"
	"sort"
	"strconv"
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
	Name     string
	OldValue *float64
	NewValue *float64
}

type ByName []MergedTestResult

func (s ByName) Len() int { return len(s) }
func (s ByName) Swap(i int, j int) {
	s[i], s[j] = s[j], s[i]
}
func (s ByName) Less(i int, j int) bool {
	return s[i].Name < s[j].Name
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
			if br.Metric == "WalltimeMilliseconds" {
				res := mergedResults[fn.Name]
				res.Name = fn.Name
				res.OldValue = &(br.Value)
				mergedResults[fn.Name] = res
			}
		}
	}
	for _, fn := range newTest.Functions {
		for _, br := range fn.BenchmarkResults {
			if br.Metric == "WalltimeMilliseconds" {
				res := mergedResults[fn.Name]
				res.Name = fn.Name
				res.NewValue = &(br.Value)
				mergedResults[fn.Name] = res
			}
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

		if mr.OldValue != nil {
			row = append(row, strconv.FormatFloat(*mr.OldValue, 'f', 2, 64))
		} else {
			row = append(row, "-")
		}

		if mr.NewValue != nil {
			row = append(row, strconv.FormatFloat(*mr.NewValue, 'f', 2, 64))
		} else {
			row = append(row, "-")
		}

		if mr.OldValue != nil && mr.NewValue != nil {
			pChange := (*mr.NewValue - *mr.OldValue) / *mr.OldValue
			pStr := strconv.FormatFloat(pChange, 'f', 2, 64)
			if pChange > 0 {
				row = append(row, fmt.Sprintf("+%s%% FASTER! :)", pStr))
			} else if pChange < 0 {
				row = append(row, fmt.Sprintf("%s%%", pStr))
			} else {
				row = append(row, "more or less the same")
			}

			totalPChange += pChange
		} else {
			row = append(row, "-")
		}

		table.Append(row)
	}

	verdict := ""
	totalPStr := strconv.FormatFloat(totalPChange, 'f', 2, 64)
	if totalPChange > 0 {
		verdict = fmt.Sprintf("+%s%% :)", totalPStr)
	} else if totalPChange < 0 {
		verdict = fmt.Sprintf("%s%% :(", totalPStr)
	} else {
		verdict = "more or less the same"
	}

	table.SetFooter([]string{newTest.Name, "", "", verdict})
	table.Render()

}
