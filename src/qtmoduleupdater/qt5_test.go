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
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestGitModules(t *testing.T) {
	ref := "refs/heads/5.12"
	subModules, err := getQt5ProductModules("qt/qt5", ref, "")
	assert.Nil(t, err, "No errors expected retrieving the submodules")

	qqc, ok := subModules["qt/qtquickcontrols"]
	assert.True(t, ok, "Could not find qtquickcontrols in submodules")

	assert.Equal(t, []string{"qt/qtdeclarative"}, qqc.requiredDependencies)
	assert.Equal(t, []string{"qt/qtgraphicaleffects"}, qqc.optionalDependencies)
}
