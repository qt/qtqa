/****************************************************************************
 **
 ** Copyright (C) 2020 The Qt Company Ltd.
 ** Contact: https://www.qt.io/licensing/
 **
 ** This file is part of the qtqa module of the Qt Toolkit.
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

exports.id = "singleRequestManager";

// The singleRequestManager processes incoming changes linerally.
// When start() is called, the request progresses through branch
// validation, tries to create a cherry pick, and tries to stage it.
class singleRequestManager {
  constructor(retryProcessor, requestProcessor) {
    this.retryProcessor = retryProcessor;
    this.requestProcessor = requestProcessor;
    this.handleValidBranch = this.handleValidBranch.bind(this);
    this.requestProcessor.addListener(
      "singleRequest_validBranchReadyForPick",
      this.handleValidBranch
    );
    this.handleNewCherryPick = this.handleNewCherryPick.bind(this);
    this.requestProcessor.addListener("singleRequest_newCherryPick", this.handleNewCherryPick);
    this.handleCherryPickDone = this.handleCherryPickDone.bind(this);
    this.requestProcessor.addListener("singleRequest_cherryPickDone", this.handleCherryPickDone);
    this.handleCherrypickReadyForStage = this.handleCherrypickReadyForStage.bind(this);
    this.requestProcessor.addListener(
      "singleRequest_cherrypickReadyForStage",
      this.handleCherrypickReadyForStage
    );
    this.handleStagingDone = this.handleStagingDone.bind(this);
    this.requestProcessor.addListener("singleRequest_stagingDone", this.handleStagingDone);
  }

  start(parentJSON, branches) {
    let _this = this;
    branches.forEach(function(branch) {
      _this.requestProcessor.emit(
        "validateBranch", parentJSON, branch,
        "singleRequest_validBranchReadyForPick"
      );
    });
  }

  handleValidBranch(parentJSON, branch, newParentRev) {
    let _this = this;
    _this.requestProcessor.emit(
      "validBranchReadyForPick", parentJSON, branch, newParentRev,
      "singleRequest_newCherryPick"
    );
  }

  handleNewCherryPick(parentJSON, cherryPickJSON) {
    let _this = this;
    _this.requestProcessor.emit(
      "newCherryPick", parentJSON, cherryPickJSON,
      "singleRequest_cherryPickDone"
    );
  }

  handleCherryPickDone(parentJSON, cherryPickJSON) {
    let _this = this;
    _this.requestProcessor.emit(
      "cherryPickDone", parentJSON, cherryPickJSON,
      "singleRequest_cherrypickReadyForStage"
    );
  }

  handleCherrypickReadyForStage(parentJSON, cherryPickJSON) {
    let _this = this;
    _this.requestProcessor.emit(
      "cherrypickReadyForStage", parentJSON, cherryPickJSON,
      "singleRequest_stagingDone"
    );
  }

  handleStagingDone(success, data) {
    let _this = this;
    // Stub for later expansion.
  }
}
module.exports = singleRequestManager;
