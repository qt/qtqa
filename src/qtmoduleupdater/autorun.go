/****************************************************************************
**
** Copyright (C) 2019 The Qt Company Ltd.
** Contact: https://www.qt.io/licensing/
**
** This file is part of the repo tools module of the Qt Toolkit.
**
** $QT_BEGIN_LICENSE:GPL-EXCEPT$
** Commercial License Usage
** Licensees holding valid commercial Qt licenses may use this file in
** accordance with the commercial license agreement provided with the
** Software or, alternatively, in accordance with the terms contained in
** a written agreement between you and The Qt Company. For licensing terms
** and conditions see https://www.qt.io/terms-conditions. For further
** information use the contact form at https://www.qt.io/contact-us.
**
** GNU General Public License Usage
** Alternatively, this file may be used under the terms of the GNU
** General Public License version 3 as published by the Free Software
** Foundation with exceptions as appearing in the file LICENSE.GPL3-EXCEPT
** included in the packaging of this file. Please review the following
** information to ensure the GNU General Public License requirements will
** be met: https://www.gnu.org/licenses/gpl-3.0.html.
**
** $QT_END_LICENSE$
**
****************************************************************************/
package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"os"
)

// AutoRunSettings is used to read autorun.json.
type AutoRunSettings struct {
	Version     int               `json:"version"`
	Branches    []string          `json:"branches"`
	ProductRefs map[string]string `json:"productRefs"`
}

func (settings *AutoRunSettings) load() error {
	file, err := os.Open("autorun.json")
	if err != nil {
		return fmt.Errorf("Error opening autorun.json for reading: %s", err)
	}
	defer file.Close()
	content, err := ioutil.ReadAll(file)
	if err != nil {
		return fmt.Errorf("Error reading from autorun.json: %s", err)
	}
	return json.Unmarshal(content, settings)
}

func (settings *AutoRunSettings) runUpdates(gerrit *gerritInstance) {
	// ### might make sense to turn this into a loop over known products or read from settings. On the other hand we want
	// to avoid coding products into the file for now but rather query a list of products from Gerrit (in the future). Therefore
	// I'm keeping the product out of the file
	product := "qt/qt5"
	for _, branch := range settings.Branches {
		productRef := ""
		if specificProductRef, ok := settings.ProductRefs[branch]; ok {
			productRef = specificProductRef
		}
		batch, err := newModuleUpdateBatch(product, branch, productRef)
		if err != nil {
			fmt.Printf("Error loading update batch state for %s/%s: %s\n", product, branch, err)
			continue
		}

		if err := batch.runOneIteration(gerrit); err != nil {
			fmt.Printf("Error iterating on update batch for %s/%s: %s\n", product, branch, err)
			continue
		}
	}
}
