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

func TestModuleYamlMarshalling(t *testing.T) {
	var module YAMLDependencies
	module.Dependencies = make(map[string]*YAMLModule)

	module.Dependencies["a"] = &YAMLModule{
		Ref:      "refs/heads/foo",
		Required: false,
	}
	module.Dependencies["b"] = &YAMLModule{
		Ref:      "refs/heads/bar",
		Required: true,
	}

	var yamlStr string
	var err error
	yamlStr, err = module.ToString()
	assert.Nil(t, err, "Conversion to yaml string must succeed")

	assert.Equal(t, `dependencies:
  a:
    ref: refs/heads/foo
    required: false
  b:
    ref: refs/heads/bar
    required: true
`, yamlStr, "Yaml output should be as expected")
}

func TestProposedUpdateFailsForModulesThatDependOnMoreThanQtBase(t *testing.T) {
	// Make sure that this always points to the latest LTS branch. If it fails, update it.
	ref := "refs/heads/5.12"
	qt5Modules, err := getQt5ProductModules("qt/qt5", ref, "")

	assert.Nil(t, err, "Retrieving qt5 modules expected to work")

	todoMap, availableModules, err := loadTodoAndDoneModuleMapFromSubModules(ref, qt5Modules)
	assert.Nil(t, err, "No error expected creating module map")

	_, ok := availableModules["qt/qtbase"]
	assert.True(t, ok, "qt/qtbase must be present in the module map")

	qtSvg, ok := todoMap["qt/qtsvg"]
	assert.True(t, ok, "qtsvg must be present in the module map")
	yamlObject, err := qtSvg.maybePrepareUpdatedDependenciesYaml(availableModules)
	assert.Nil(t, err, "No error expected preparing dependencies.yaml update")
	assert.NotNil(t, yamlObject, "Yaml object must be defined for qtsvg")

	yamlStr, err := yamlObject.ToString()
	assert.Nil(t, err, "Conversion to yaml string must succeed")

	assert.Nil(t, err, "It should be possible to create a new dependencies.yaml file for qtsvg")
	assert.NotEqual(t, "", yamlStr, "Yaml string must not be empty for qtsvg")

	qtDeclarative, ok := todoMap["qt/qtdeclarative"]
	assert.True(t, ok, "qtdeclarative must be present in the module map")
	yamlObject, err = qtDeclarative.maybePrepareUpdatedDependenciesYaml(availableModules)

	assert.Nil(t, err, "It should be possible to create a new dependencies.yaml file for qtdeclarative")
	assert.Nil(t, yamlObject, "Yaml string be empty for qtdeclarative because dependencies are not available yet")
}

func TestRemovalOfNonExistentOptionalDependencies(t *testing.T) {
	// Make sure that this always points to the latest LTS branch. If it fails, update it.
	ref := "refs/heads/5.12"
	qt5Modules, err := getQt5ProductModules("qt/qt5", ref, "")
	assert.Nil(t, err, "Retrieving qt5 modules expected to work")

	_, haveSvg := qt5Modules["qt/qtsvg"]
	assert.True(t, haveSvg, "qtsvg needs to be in qt5.git")
	delete(qt5Modules, "qt/qtsvg")

	qtDeclarative := qt5Modules["qt/qtdeclarative"]
	assert.NotNil(t, qtDeclarative, "need qtdeclarative")

	assert.Contains(t, qtDeclarative.optionalDependencies, "qt/qtsvg")
	qtDeclarativeModule, err := NewModule("qt/qtdeclarative", ref, qt5Modules)
	assert.Nil(t, err, "There shall not be any error creating the module")

	assert.NotNil(t, qtDeclarativeModule, "qtdeclarative module shall exist")

	assert.Contains(t, qtDeclarativeModule.RequiredDependencies, "qt/qtbase")
	assert.NotContains(t, qtDeclarativeModule.OptionalDependencies, "qt/qtsvg")
}

func TestQueryChangeStatus(t *testing.T) {
	status, err := getGerritChangeStatus("qt/qtbase", "dev", "Ie6f0e2e3bb198a95dd40e7416adc8ffb29f3b2ba")
	assert.Nil(t, err, "Querying should not produce an error")
	assert.Equal(t, "MERGED", status)

	status, err = getGerritChangeStatus("qt/qtbase", "dev", "I6e4349f4d72de307a579f59bb689fd0638690403")
	assert.Nil(t, err, "Querying should not produce an error")
	assert.Equal(t, "ABANDONED", status)

}
