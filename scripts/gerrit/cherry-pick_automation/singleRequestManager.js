/* eslint-disable no-unused-vars */
// Copyright (C) 2020 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

exports.id = "singleRequestManager";

// The singleRequestManager processes incoming changes linerally.
// When start() is called, the request progresses through branch
// validation, tries to create a cherry pick, and tries to stage it.
class singleRequestManager {
  constructor(logger, retryProcessor, requestProcessor) {
    this.logger = logger;
    this.retryProcessor = retryProcessor;
    this.requestProcessor = requestProcessor;
    this.handleValidBranch = this.handleValidBranch.bind(this);
    this.requestProcessor.addListener(
      "singleRequest_validBranch",
      this.handleValidBranch
    );
    this.ltsTargetChecked = this.ltsTargetChecked.bind(this);
    this.requestProcessor.addListener(
      "singleRequest_ltsTargetChecked",
      this.ltsTargetChecked
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
    _this.logger.log(
      `Starting SingleRequest Manager process for ${parentJSON.fullChangeID}`,
      "verbose", parentJSON.uuid
    );
    branches.forEach(function (branch) {
      _this.requestProcessor.emit(
        "validateBranch", _this.requestProcessor.toolbox.deepCopy(parentJSON), branch,
        "singleRequest_validBranch"
      );
    });
  }

  handleValidBranch(parentJSON, branch, newParentRev) {
    let _this = this;
    _this.requestProcessor.emit(
      "checkLtsTarget", parentJSON, branch, newParentRev,
      "singleRequest_ltsTargetChecked"
    );
  }

  ltsTargetChecked(parentJSON, branch, newParentRev) {
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
