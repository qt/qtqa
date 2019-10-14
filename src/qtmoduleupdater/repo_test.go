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
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestRepo(t *testing.T) {
	repo, err := OpenRepository("qt/qtbase")
	if err != nil {
		t.Fatalf("Unexpected error opening qtbase repo: %s", err)
	}
	if !strings.HasSuffix(string(repo), "qt/qtbase") {
		t.Fatalf("Unexpected repo path %s", repo)
	}

	ref, err := repo.LookupReference("v5.5.0")
	if err != nil {
		t.Fatalf("Unexpected error looking up reference: %s", err)
	}
	if string(ref) != "2fde9f59eeab68ede92324e7613daf8be3eaf498" {
		t.Fatalf("Incorrect sha1 for v5.5.0 tag")
	}

	tree, err := repo.ListTree(ref)
	if err != nil {
		t.Fatalf("Unexpected error listing tree: %s", err)
	}

	if tree.ID != ref {
		t.Fatalf("Incorrect tree entry for %s", ref)
	}

	qtbaseProEntry, ok := tree.Entries["qtbase.pro"]
	if !ok {
		t.Fatalf("Missing qtbase.pro entry in tree listing")
	}

	if qtbaseProEntry.ID != "24d0f5287ba26ee0e53e34c8860c6c7baf7b0268" {
		t.Fatalf("Unexpected sha1 for qtbase.pro: %s", qtbaseProEntry.ID)
	}

	if qtbaseProEntry.Type != ObjectBlob {
		t.Fatalf("Unexpected entry type for qtbase.pro")
	}

	if qtbaseProEntry.Permissions != "100644" {
		t.Fatalf("Incorrect permissions for qtbase.pro")
	}

	qmakeConf, ok := tree.Entries[".qmake.conf"]
	if !ok {
		t.Fatalf("Missing .qmake.conf in tree listing")
	}

	content, err := repo.LookupBlob(qmakeConf.ID)
	if err != nil {
		t.Fatalf("Unexpected error looking up .qmake.conf blob: %s", err)
	}

	expectedContent := `load(qt_build_config)
CONFIG += qt_example_installs
CONFIG += warning_clean

QT_SOURCE_TREE = $$PWD
QT_BUILD_TREE = $$shadowed($$PWD)

# In qtbase, all modules follow qglobal.h
MODULE_VERSION = $$QT_VERSION
`
	if string(content) != expectedContent {
		t.Fatalf("Unexpected blob content for .qmake.conf: %s", string(content))
	}
}

func TestIndex(t *testing.T) {
	repo, err := OpenRepository("qt/qtbase")
	if err != nil {
		t.Fatalf("Unexpected error opening qtbase repo: %s", err)
	}

	ref, err := repo.LookupReference("v5.5.0")
	if err != nil {
		t.Fatalf("Unexpected error looking up v5.5.0 tag")
	}

	index, err := repo.NewIndex()
	if err != nil {
		t.Fatalf("Could not get index.")
	}
	defer index.Free()

	err = index.ReadTree(ref)
	if err != nil {
		t.Fatalf("Error reading index tree: %s", err)
	}

	if index.EntryCount() != 21452 {
		t.Fatalf("Unexpected index entry count %v", index.EntryCount())
	}
}

func TestNewIndex(t *testing.T) {
	repo, err := OpenRepository("qt/qtbase")
	assert.Nilf(t, err, "Unexpected error opening qtbase repo: %s", err)

	index, err := repo.NewIndex()
	if err != nil {
		t.Fatalf("Could not get index.")
	}
	defer index.Free()

	sampleContent := []byte("Hello World")

	indexEntry := &IndexEntry{
		Permissions: "100644",
		Path:        "test.txt",
	}

	err = index.HashObject(indexEntry, sampleContent)
	assert.Nilf(t, err, "should be able to add data to git database: %s", err)

	assert.Equal(t, OID("5e1c309dae7f45e0f39b1bf3ac3cd9db12e7d689"), indexEntry.ID)

	err = index.Add(indexEntry)
	assert.Nilf(t, err, "should be able to add entry to new index: %s", err)

	tree, err := index.WriteTree()
	assert.Nilf(t, err, "should be able to write tree: %s", err)

	assert.Equal(t, OID("4f11af3e4e067fc319abd053205f39bc40652f05"), tree)
}

func TestLog(t *testing.T) {
	repo, err := OpenRepository("qt/qtbase")
	if err != nil {
		t.Fatalf("Unexpected error opening qtbase repo: %s", err)
	}

	output, err := repo.LogOutput(`--pretty=format:  %m %s`, "--first-parent", "v5.0.0~2..v5.0.0")
	if err != nil {
		t.Fatalf("Unexpected error calling git log: %s", err)
	}
	if len(output) != 2 {
		t.Fatalf("Unexpected length of git log output array: %v", len(output))
	}
	if output[0] != "  > Fix font sizes when X11 has a forced dpi setting" {
		t.Fatalf("Unexpected first line of log output: %s", output[0])
	}
	if output[1] != "  > Fix direct compilation of qtypeinfo.h and others" {
		t.Fatalf("Unexpected second line of log output: %s", output[0])
	}
}
