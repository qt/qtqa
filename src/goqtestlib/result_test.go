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
	"encoding/xml"
	"testing"
)

func TestXMLSchema(t *testing.T) {
	rawXML := `<?xml version="1.0" encoding="UTF-8"?>
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
<TestFunction name="getSetCheck">
<Message type="qwarn" file="" line="0">
    <Description><![CDATA[QIODevice::seek (QTcpSocket): Cannot call seek on a sequential device]]></Description>
    </Message>
<Incident type="pass" file="" line="0" />
    <Duration msecs="0.115120"/>
</TestFunction>
<TestFunction name="readLine2">
<Incident type="pass" file="" line="0">
    <DataTag><![CDATA[1024 - 4]]></DataTag>
</Incident>
<Incident type="pass" file="" line="0">
    <DataTag><![CDATA[1024 - 3]]></DataTag>
</Incident>
<BenchmarkResult metric="InstructionReads" tag="" value="19838" iterations="1" />
</TestFunction>
<Duration msecs="760.801970"/>
</TestCase>`

	actual := &ParsedTestResult{}
	err := xml.Unmarshal([]byte(rawXML), &actual)
	if err != nil {
		t.Errorf("Error decoding XML: %s", err)
		t.FailNow()
	}

	if actual.Name != "tst_QIODevice" {
		t.Errorf("Invalid name attribute decoding. Got %s", actual.Name)
	}

	if actual.Env.QtVersion != "5.6.0" {
		t.Errorf("Error decoding Qt version from environment. Got %s", actual.Env.QtVersion)
	}

	if actual.Duration.Msecs != 760.801970 {
		t.Errorf("Error decoding Test Duration. Got %f", actual.Duration.Msecs)
	}

	if len(actual.Functions) != 3 {
		t.Errorf("Incorrect number of parsed test functions. Got %v", len(actual.Functions))
		t.FailNow()
	}

	function := actual.Functions[0]

	if function.Name != "initTestCase" {
		t.Errorf("Incorrectly parsed test function name for first test function. Got %v", function.Name)
	}

	if len(function.Incidents) != 1 {
		t.Errorf("Incorrectly parsed incidents for first test function. Parsed %v incidents", len(function.Incidents))
		t.FailNow()
	}

	if function.Duration.Msecs != 0.274962 {
		t.Errorf("Wrong duration %v", function.Duration.Msecs)
	}

	incident := function.Incidents[0]

	if incident.Type != "pass" {
		t.Errorf("Incorrectly parsed type for incident. Got %v", incident.Type)
	}

	if incident.File != "" {
		t.Errorf("Incorrectly parsed file name for incident. Got %v", incident.File)
	}

	if incident.Line != 0 {
		t.Errorf("Incorrectly parsed line number for incident. Got %v", incident.Line)
	}

	function = actual.Functions[1]

	if len(function.Messages) != 1 {
		t.Errorf("Incorrectly parsed number of messages incident. Got %v", len(function.Messages))
	}

	if function.Duration.Msecs != 0.115120 {
		t.Errorf("Wrong duration %v", function.Duration.Msecs)
	}

	message := function.Messages[0]

	if message.Type != "qwarn" {
		t.Errorf("Incorrectly parsed message type. Got %v", len(message.Type))
	}

	if message.Description != "QIODevice::seek (QTcpSocket): Cannot call seek on a sequential device" {
		t.Errorf("Incorrectly parsed message description. Got %v", message.Description)
	}

	function = actual.Functions[2]

	if len(function.Incidents) != 2 {
		t.Errorf("Incorrectly parsed incidents for third test function. Parsed %v incidents", len(function.Incidents))
		t.FailNow()
	}

	if function.Duration.Msecs != 0.0 {
		t.Errorf("Wrong duration %v", function.Duration.Msecs)
	}

	incident = function.Incidents[0]
	if incident.Type != "pass" {
		t.Errorf("Incorrectly parsed incident type. Got %v", incident.Type)
	}

	if incident.DataTag != "1024 - 4" {
		t.Errorf("Incorrectly parsed incident data tag. Got %v", incident.Type)
	}

	incident = function.Incidents[1]
	if incident.DataTag != "1024 - 3" {
		t.Errorf("Incorrectly parsed incident data tag. Got %v", incident.Type)
	}

	if len(function.BenchmarkResults) != 1 {
		t.Fatalf("Incorrectly parsed number of benchmark results. Expected 1 got %v", len(function.BenchmarkResults))
	}

	result := function.BenchmarkResults[0]
	if result.Metric != "InstructionReads" {
		t.Errorf("Incorrectly parsed benchmark metric %s", result.Metric)
	}

	if result.Value != 19838 {
		t.Errorf("Incorrectly parsed benchmark value %v", result.Value)
	}

	if result.Iterations != 1 {
		t.Errorf("Incorrectly parsed benchmark iteration count %v", result.Iterations)
	}
}
