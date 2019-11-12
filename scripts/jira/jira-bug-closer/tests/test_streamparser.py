#!/usr/bin/env python3
#############################################################################
##
## Copyright (C) 2019 The Qt Company Ltd.
## Contact: https://www.qt.io/licensing/
##
## This file is part of the Quality Assurance module of the Qt Toolkit.
##
## $QT_BEGIN_LICENSE:GPL-EXCEPT$
## Commercial License Usage
## Licensees holding valid commercial Qt licenses may use this file in
## accordance with the commercial license agreement provided with the
## Software or, alternatively, in accordance with the terms contained in
## a written agreement between you and The Qt Company. For licensing terms
## and conditions see https://www.qt.io/terms-conditions. For further
## information use the contact form at https://www.qt.io/contact-us.
##
## GNU General Public License Usage
## Alternatively, this file may be used under the terms of the GNU
## General Public License version 3 as published by the Free Software
## Foundation with exceptions as appearing in the file LICENSE.GPL3-EXCEPT
## included in the packaging of this file. Please review the following
## information to ensure the GNU General Public License requirements will
## be met: https://www.gnu.org/licenses/gpl-3.0.html.
##
## $QT_END_LICENSE$
##
#############################################################################

import pytest
from gerrit import GerritStreamParser, GerritEvent


@pytest.mark.parametrize("message,expected,is_branch_update", [
    ("", GerritEvent(type='invalid', project='', branch=''), False),
    ("invalid", GerritEvent(type='invalid', project='', branch=''), False),
    ("{}", GerritEvent(type='invalid', project='', branch=''), False),
    ("""{"random_json": "yeah"}""", GerritEvent(type='invalid', project='', branch=''), False),
    ("""{"type":"comment-added","change":{"project":"qt/qtdeclarative","branch":"dev","id":"I2ebe8fdd5ca121bf884a0f1aaac2272e9ff564d9",
     "number":"236085","subject":"WIP: Implement support for uninitialized variables","owner":{"name":"Lars Knoll","email":"lars.knoll@qt.io","username":"laknoll"},
     "url":"https://codereview.qt-project.org/236085"},"patchSet":{"number":"1","revision":"e0f9e7d6792348ab307e67ac0f775bc5abfc6e07",
     "parents":["3d0e18a0e24d3a475301bc4e9f9ccb7f0074e307"],"ref":"refs/changes/85/236085/1",
     "uploader":{"name":"Lars Knoll","email":"lars.knoll@qt.io","username":"laknoll"},"createdOn":1533480530,
     "author":{"name":"Lars Knoll","email":"lars.knoll@qt.io","username":"laknoll"},"sizeInsertions":37,"sizeDeletions":-1},
     "author":{"name":"Qt Sanity Bot","email":"qt_sanitybot@qt-project.org","username":"qt_sanity_bot"},
     "approvals":[{"type":"Sanity-Review","description":"Sanity-Review","value":"1"},{"type":"Code-Review","description":"Code-Review","value":"-2"}],
     "comment":"Patch Set 1: Code-Review-2 Sanity-Review+1\\n\\nApparently pushing a Work In Progress"}""",
     GerritEvent(type="comment-added", project="qt/qtdeclarative", branch="dev"), False),
    ("""{"type":"change-merged","change":{"project":"qt/qtbase","branch":"dev","id":"I4857e9b43918243af66cc09ff352619595c081c9",
     "number":"235677","subject":"QTextureFileData: Fix build with -no-opengl","owner":{"name":"Jüri Valdmann","email":"juri.valdmann@qt.io","username":"juri.valdmann"},
     "url":"https://codereview.qt-project.org/235677"},"patchSet":{"number":"1","revision":"41d29efb4196d5fd447190d3b8ec26d70b9f8eec",
     "parents":["b0085dbeeac47d0ce566750d93f1b1f865d07cdb"],"ref":"refs/changes/77/235677/1",
     "uploader":{"name":"Jüri Valdmann","email":"juri.valdmann@qt.io","username":"juri.valdmann"},"createdOn":1533042510,
     "author":{"name":"Jüri Valdmann","email":"juri.valdmann@qt.io","username":"juri.valdmann"},"sizeInsertions":1,"sizeDeletions":0},
     "submitter":{"name":"Jüri Valdmann","email":"juri.valdmann@qt.io","username":"juri.valdmann"}}""",
     GerritEvent(type="change-merged", project="qt/qtbase", branch="dev"), False),
    ("""{"type":"ref-updated","submitter":{"name":"Qt CI Bot","email":"qt_ci_bot@qt-project.org","username":"qt_ci_bot"},
     "refUpdate":{"oldRev":"8cde4a825638a414ef55a57662b38e2746b83668","newRev":"a80ed61a98fd0a1d13eab95252db189cdeb0fe96",
     "refName":"master","project":"qtqa/tqtc-coin-ci"}}""",
     GerritEvent(type='ref-updated', project='qtqa/tqtc-coin-ci', branch='master'), True),
    ("""{"type":"ref-updated","submitter":{"name":"Qt CI Bot","email":"qt_ci_bot@qt-project.org","username":"qt_ci_bot"},
     "refUpdate":{"oldRev":"8cde4a825638a414ef55a57662b38e2746b83668","newRev":"a80ed61a98fd0a1d13eab95252db189cdeb0fe96",
     "refName":"refs/staging/master","project":"qtqa/tqtc-coin-ci"}}""",
     GerritEvent(type='ref-updated', project='qtqa/tqtc-coin-ci', branch='refs/staging/master'), False),
    ("""{"type":"patchset-created","change":{"project":"qt/qtopcua","branch":"dev","id":"I0c6ba3451a29e20508b2d59671e9b8d50d47158f","number":"235852",
    "subject":"Split qopcuabrowsing.h/.cpp","owner":{"name":"Jannis Völker","email":"jannis.voelker@basyskom.com","username":"basyskom.jannis.voelker"},
    "url":"https://codereview.qt-project.org/235852"},"patchSet":{"number":"2","revision":"0316904a4a5274166e8b785b09c1727aa6485ede","parents":["8a6ef588fc0de9876a5d64964fb958f7818e24a4"],
    "ref":"refs/changes/52/235852/2","uploader":{"name":"Jannis Völker","email":"jannis.voelker@basyskom.com","username":"basyskom.jannis.voelker"},
    "createdOn":1533542575,"author":{"name":"Jannis Völker","email":"jannis.voelker@basyskom.com","username":"basyskom.jannis.voelker"},
    "sizeInsertions":182,"sizeDeletions":-206},"uploader":{"name":"Jannis Völker","email":"jannis.voelker@basyskom.com","username":"basyskom.jannis.voelker"}}""",
     GerritEvent(type='patchset-created', project='qt/qtopcua', branch='dev'), False),
    ("""{"type":"reviewer-added","change":{"project":"qtqa/tqtc-coin-ci","branch":"master","id":"I40486a0eabeac788ac1c857f47b1dbf9cf538a61",
    "number":"236086","subject":"Webui: Add task failure summary in task search targets",
    "owner":{"name":"Aapo Keskimolo","email":"aapo.keskimolo@qt.io","username":"aakeskimo"},
    "url":"https://codereview.qt-project.org/236086"},"patchSet":{"number":"1","revision":"27c7d3c2e5fa3362cac14f54779c8ba273f782c3",
    "parents":["335d191e4611b6a3af2d0c89b37661d82a217cdc"],"ref":"refs/changes/86/236086/1",
    "uploader":{"name":"Aapo Keskimolo","email":"aapo.keskimolo@qt.io","username":"aakeskimo"},"createdOn":1533498876,
    "author":{"name":"Aapo Keskimolo","email":"aapo.keskimolo@qt.io","username":"aakeskimo"},
    "sizeInsertions":1,"sizeDeletions":-1},"reviewer":{"name":"Joni Jäntti","email":"joni.jantti@qt.io","username":"jojantti"}}""",
     GerritEvent(type='reviewer-added', project='qtqa/tqtc-coin-ci', branch='master'), False),
    ("""{"type":"change-restored","change":{"project":"qt/qtbase","branch":"5.9","id":"I587534fc5723b3d198fe2065fbcf1bee4871a768",
    "number":"236064","subject":"Doc: Fix wrong link in QFont documentation","owner":{"name":"Paul Wicking","email":"paul.wicking@qt.io",
    "username":"paulwicking"},"url":"https://codereview.qt-project.org/236064"},
    "restorer":{"name":"Paul Wicking","email":"paul.wicking@qt.io","username":"paulwicking"}}""",
     GerritEvent(type='change-restored', project='qt/qtbase', branch='5.9'), False),
    ("""{"type":"draft-published","change":{"project":"qt/qtbase","branch":"dev","id":"I91f4e8d43d95c5f30c5bc2571393804209b7a843","number":"236135",
    "subject":"NeworkAccessBackend: Remove duplicated/shadowed member","owner":{"name":"Mårten Nordheim","email":"marten.nordheim@qt.io","username":"manordheim"},
    "url":"https://codereview.qt-project.org/236135"},"patchSet":{"number":"1","revision":"34d84d08e0f4171f4a28729ed8f62762af8d4d2e","parents":["9f2a6715600bf872e41dcd8c4492480b93b4f599"],
    "ref":"refs/changes/35/236135/1","uploader":{"name":"Mårten Nordheim","email":"marten.nordheim@qt.io","username":"manordheim"},"createdOn":1533556341,
    "author":{"name":"Mårten Nordheim","email":"marten.nordheim@qt.io","username":"manordheim"},"sizeInsertions":5,"sizeDeletions":-8},
    "uploader":{"name":"Mårten Nordheim","email":"marten.nordheim@qt.io","username":"manordheim"}}""",
     GerritEvent(type='draft-published', project='qt/qtbase', branch='dev'), False),
    ("""{"type":"change-abandoned","change":{"project":"qt/qtbase","branch":"dev","id":"I5f5d8da9e7af10a26e8271a6488850f120f3a23e","number":"235959","subject":"Blacklist tst_QSharedPointer::invalidConstructs","owner":{"name":"Joni Jäntti","email":"joni.jantti@qt.io","username":"jojantti"},"url":"https://codereview.qt-project.org/235959"},"abandoner":{"name":"Joni Jäntti","email":"joni.jantti@qt.io","username":"jojantti"},"reason":"Problem fixed by: https://codereview.qt-project.org/#/c/236054/"}""",
     GerritEvent(type='change-abandoned', project='qt/qtbase', branch='dev'), False),
    ("""{"type":"merge-failed","change":{"project":"qt/qtvirtualkeyboard","branch":"dev","id":"I7c1f41dfd7ddd25faf2d197652ba04d3d7e12941","number":"215270",
    "subject":"myscript: initial integration","owner":{"name":"Yuntaek Rim","email":"yuntaek.rim@myscript.com","username":"yuntaek.rim"},
    "url":"https://codereview.qt-project.org/215270"},"patchSet":{"number":"18","revision":"1589057210234577d24fdff8ae286a04eb44469d",
    "parents":["fbbd9d5db5fd2547c54d19e7441e761dcfcc213b"],"ref":"refs/changes/70/215270/18",
    "uploader":{"name":"Mitch Curtis","email":"mitch.curtis@qt.io","username":"mitch_curtis"},"createdOn":1531913238,
    "author":{"name":"Yuntaek Rim","email":"yuntaek.rim@myscript.com","username":"yuntaek.rim"},"sizeInsertions":2889,"sizeDeletions":-737},
    "submitter":{"name":"Mitch Curtis","email":"mitch.curtis@qt.io","username":"mitch_curtis"},
    "reason":"Your change could not be merged due to a path conflict.\\n\\nMake sure you staged all dependencies of this change. If the change has dependencies which are currently INTEGRATING, try again when the integration finishes.\\n\\nOtherwise please rebase the change locally and upload the rebased commit for review."}""",
     GerritEvent(type='merge-failed', project='qt/qtvirtualkeyboard', branch='dev'), False),
    ("""{"type":"change-deferred","change":{"project":"pyside/pyside-setup","branch":"5.11","id":"I56796bcf51cae31d885e7cefed8de1f94794ee04","number":"236319","subject":"Qt3DAnimation: add missing classes","owner":{"name":"Cristian Maureira-Fredes","email":"cristian.maureira-fredes@qt.io","username":"crmaurei"},"url":"https://codereview.qt-project.org/236319"},"deferrer":{"name":"Cristian Maureira-Fredes","email":"cristian.maureira-fredes@qt.io","username":"crmaurei"},"reason":"ups, duplicated -\u003e https://codereview.qt-project.org/#/c/236315/"}""",
     GerritEvent(type='change-deferred', project='pyside/pyside-setup', branch='5.11'), False),

    ("""{"submitter":{"name":"Ulf Hermann","email":"ulf.hermann@qt.io","username":"ulherman"},
     "refUpdate":{"oldRev":"0000000000000000000000000000000000000000","newRev":"17007265a1fcab2a7325c48d0c509393139d28b7",
     "refName":"refs/changes/22/266322/2","project":"qt/qtdeclarative"},"type":"ref-updated","eventCreatedOn":1561535488}""",
     GerritEvent(type='ref-updated', project='qt/qtdeclarative', branch='refs/changes/22/266322/2'), False),

    ("""{"submitter":{"name":"Ulf Hermann","email":"ulf.hermann@qt.io","username":"ulherman"},"refUpdate":
     {"oldRev":"e2103019f265dd2fb298f7dc1d57fca492978545","newRev":"cf76d11843ed27f92f1683c4a56bfdae216808cd",
     "refName":"refs/changes/22/266322/meta","project":"qt/qtdeclarative"},"type":"ref-updated","eventCreatedOn":1561535488}""",
     GerritEvent(type='ref-updated', project='qt/qtdeclarative', branch='refs/changes/22/266322/meta'), False),
    ("""{"submitter":{"name":"Ulf Hermann","email":"ulf.hermann@qt.io","username":"ulherman"},
     "refUpdate":{"oldRev":"c060f6e765a2f155b38158f2ed73eac4aad37e02","newRev":"17007265a1fcab2a7325c48d0c509393139d28b7",
     "refName":"refs/staging/dev","project":"qt/qtdeclarative"},"type":"ref-updated","eventCreatedOn":1561535490}""",
     GerritEvent(type='ref-updated', project='qt/qtdeclarative', branch='refs/staging/dev'), False),

    ("""{"reviewer":{"name":"Eike Ziller","email":"eike.ziller@qt.io","username":"con"},"remover":{"name":"Eike Ziller","email":"eike.ziller@qt.io","username":"con"},
     "approvals":[{"type":"Code-Review","description":"Code-Review","value":"0"},{"type":"Sanity-Review","description":"Sanity-Review","value":"0"}],
     "comment":"Removed reviewer Eike Ziller.","patchSet":{"number":12,"revision":"cad02d22ea5330f5bb5b28bcddac011abf822a25",
     "parents":["e3f5912747af1d46178886a0c5eaaddaf6d1a23b"],"ref":"refs/changes/52/275352/12","uploader":{"name":"Simon Hausmann","email":"simon.hausmann@qt.io","username":"shausman"},
     "createdOn":1571843323,"author":{"name":"Simon Hausmann","email":"simon.hausmann@qt.io","username":"shausman"},"kind":"REWORK","sizeInsertions":2142,"sizeDeletions":-3},
     "change":{"project":"qt/qtbase","branch":"dev","id":"I77ec9163ba4dace6c4451f5933962ebe1b3b4b14","number":275352,"subject":"WIP: Initial import of the Qt C++ property binding system",
     "owner":{"name":"Simon Hausmann","email":"simon.hausmann@qt.io","username":"shausman"},"url":"https://codereview.qt-project.org/c/qt/qtbase/+/275352",
     "commitMessage":"WIP: Initial import of the Qt C++ property binding system\\n\\nTODO:\\n  * complete and polish docs.\\n  * consider diagram to illustrate the dependency chains\\n  * consider debug logging category to print dependencies (with source\\n    location of bindings)\\n\\nChange-Id: I77ec9163ba4dace6c4451f5933962ebe1b3b4b14\\n","createdOn":1569508045,"status":"NEW"},
     "project":"qt/qtbase","refName":"refs/heads/dev","changeKey":{"id":"I77ec9163ba4dace6c4451f5933962ebe1b3b4b14"},"type":"reviewer-deleted","eventCreatedOn":1573560822}""",
     GerritEvent(type='reviewer-deleted', project='qt/qtbase', branch='dev'), False),
])
def test_parser(message: str, expected: GerritEvent, is_branch_update: bool):
    parser = GerritStreamParser()
    result = parser.parse(message)
    result.__repr__()
    assert result == expected
    assert result.is_branch_update() == is_branch_update
