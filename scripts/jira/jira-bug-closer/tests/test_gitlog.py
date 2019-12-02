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

import asyncio
import pytest
import os
from typing import List
from git import Repository, ChangeRange, FixedByTag
from logger import get_logger
from git.repository import Version
from config import Config

log = get_logger('test')

# make sure we have a checkout, otherwise this fails
loop = asyncio.get_event_loop()
for repo_name in ('qt/qtbase', 'qt/qtdeclarative', 'qt/qtdatavis3d', 'yocto/meta-qt5', 'qt/tqtc-qt5'):
    loop.run_until_complete(Repository(repo_name)._check_repo())


dev_branch_version = "5.14.0"


@pytest.mark.parametrize("branch,expected,branches,tags", [
    ('dev', '5.12.0',
     ['5.10', '5.11', '5.11.0', '5.11.1', 'dev'],
     ['v5.11.0', 'v5.11.0-alpha1', 'v5.11.0-beta1', 'v5.11.0-beta2', 'v5.11.0-beta3', 'v5.11.0-beta4', 'v5.11.0-rc1', 'v5.11.0-rc2', 'v5.11.1']),
    ('wip/myfeature', None,
     ['5.10', '5.11', '5.11.0', '5.11.1', 'dev'],
     ['v5.11.0', 'v5.11.0-alpha1', 'v5.11.0-beta1', 'v5.11.0-beta2', 'v5.11.0-beta3', 'v5.11.0-beta4', 'v5.11.0-rc1', 'v5.11.0-rc2', 'v5.11.1']),
    ('5.12.0', '5.12.0',
     ['5.10', '5.11', '5.11.0', '5.11.1', 'dev'],
     ['v5.11.0', 'v5.11.0-alpha1', 'v5.11.0-beta1', 'v5.11.0-beta2', 'v5.11.0-beta3', 'v5.11.0-beta4', 'v5.11.0-rc1', 'v5.11.0-rc2', 'v5.11.1']),
    ('5.9.4', '5.9.4',
     ['5.10', '5.11', '5.11.0', '5.11.1', 'dev'],
     ['v5.11.0', 'v5.11.0-alpha1', 'v5.11.0-beta1', 'v5.11.0-beta2', 'v5.11.0-beta3', 'v5.11.0-beta4', 'v5.11.0-rc1', 'v5.11.0-rc2', 'v5.11.1']),
    ('5.11', '5.11.2',
     ['5.10', '5.11', '5.11.0', '5.11.1', 'dev'],
     ['v5.11.0', 'v5.11.0-alpha1', 'v5.11.0-beta1', 'v5.11.0-beta2', 'v5.11.0-beta3', 'v5.11.0-beta4', 'v5.11.0-rc1', 'v5.11.0-rc2', 'v5.11.1']),
    ('5.11', '5.11.2',
     ['5.10', '5.11', 'dev'],
     ['v5.11.0', 'v5.11.0-alpha1', 'v5.11.0-beta1', 'v5.11.0-beta2', 'v5.11.0-beta3', 'v5.11.0-beta4', 'v5.11.0-rc1', 'v5.11.0-rc2', 'v5.11.1']),
    ('5.12', '5.12.0',
     ['5.10', '5.11', '5.11.0', '5.11.1', 'dev'],
     ['v5.11.0', 'v5.11.0-alpha1', 'v5.11.0-beta1', 'v5.11.0-beta2', 'v5.11.0-beta3', 'v5.11.0-beta4', 'v5.11.0-rc1', 'v5.11.0-rc2', 'v5.11.1']),
    ('5.12', '5.12.1',
     ['5.12.0', '5.12'],
     []),
    ('5.12', '5.12.1',
     ['5.12', '5.12.0'],
     []),
])
@pytest.mark.asyncio
async def test_versions(branch: str, expected: str, branches: List[str], tags: List[str]):
    version = await Repository._guess_version(branch, branches, tags)
    assert version == expected


@pytest.mark.parametrize("change,expected", [
    (
        ChangeRange(repository='qt/qtbase', branch='dev', before='128a6eec065dfe683e6d776183d63908ca02e8f', after='b0085dbeeac47d0ce566750d93f1b1f865d07cd'),
        [FixedByTag(repository='qt/qtbase', branch='dev', version=dev_branch_version,
                    sha1='bd0279c4173eb627d432d9a05411bbc725240d4e', task_numbers=["QTBUG-69548"], fixes=[],
                    author='Kai Koehne', subject='Logging: Accept .ini files written by QSettings')],
    ),
    (
        ChangeRange(repository='qt/qtbase', branch='dev', before='0bb760260eb055f813247bf9ef06e372cac219d3', after='b0085dbeeac47d0ce566750d93f1b1f865d07cd'),
        [FixedByTag(repository='qt/qtbase', branch='dev', version=dev_branch_version,
                    sha1='bd0279c4173eb627d432d9a05411bbc725240d4e', task_numbers=["QTBUG-69548"], fixes=[],
                    author='Kai Koehne', subject='Logging: Accept .ini files written by QSettings'),

         FixedByTag(repository='qt/qtbase', branch='dev', version=dev_branch_version, sha1='8a450f570b8dc40f61a68db0ca5eb69a7a97272c', author='Robbert Proost',
                    subject='QUrl: Support IPv6 addresses with zone id', fixes=[], task_numbers=["QTBUG-25550"]),
         FixedByTag(repository='qt/qtbase', branch='dev', version=dev_branch_version, sha1='3f80783b1188afdf032571b48bc47a160d6dccf6', author='Ryan Chu',
                    subject='Rework QNetworkReply tests to use docker-based test servers', fixes=[], task_numbers=["QTQAINFRA-1686"])]
    ),
    (
        ChangeRange(repository='qt/qtbase', branch='refs/heads/dev', before='ed7f86cb077d33d0dd9e646af28e3f57c160b570', after='458b0ba8e04349a0a7ca82598a5bf7472991ebc8'),
        [
            FixedByTag(repository='qt/qtbase', branch='dev', version=dev_branch_version, sha1='823acb069d92b68b36f1b2bb59575bb0595275b4', author='Tor Arne Vestbø', fixes=[], task_numbers=["QTBUG-63572"], subject='macOS: Don\'t call [NSOpenGLContext update] for every frame'),
            FixedByTag(repository='qt/qtbase', branch='dev', version=dev_branch_version, sha1='491e427bb2d3cafccbb26d2ca3b7e128d786a564', author='Thiago Macieira', fixes=[], task_numbers=["QTBUG-69800"], subject='QTimer: Add const to some singleShot methods'),
            FixedByTag(repository='qt/qtbase', branch='dev', version=dev_branch_version, sha1='ca14151a0cdd3bc5fa364b2816bcd3b51af4bf3d', author='Mitch Curtis', fixes=[], task_numbers=["QTBUG-69492"], subject='tst_qspinbox: include actual emission count in failure message'),
            FixedByTag(repository='qt/qtbase', branch='dev', version=dev_branch_version, sha1='58e3e32adf227e91771fa421f2657f758ef1411b', author='Mitch Curtis', fixes=[], task_numbers=["QTBUG-69492"], subject='tst_qdatetimeedit: hide testWidget when creating widgets on the stack'),
            FixedByTag(repository='qt/qtbase', branch='dev', version=dev_branch_version, sha1='64a560d977a0a511ef541d6116d82e7b5c911a92', author='Thiago Macieira', fixes=[], task_numbers=["QTBUG-69744"], subject='QObject: do allow setProperty() to change the type of the property'),
            FixedByTag(repository='qt/qtbase', branch='dev', version=dev_branch_version, sha1='c6cca0f492717582cb113f3d62e97f554798cf14', author='Paul Wicking', fixes=[], task_numbers=["QTBUG-58420"], subject='Doc: Update out-of-date image in QColorDialog documentation'),
            FixedByTag(repository='qt/qtbase', branch='dev', version=dev_branch_version, sha1='6953e513f9034b98a48d83b67afd671f1ee33aeb', author='Paul Wicking', fixes=[], task_numbers=["QTBUG-56077"], subject='Doc: Clean up Qt::ApplicationAttribute docs'),
            FixedByTag(repository='qt/qtbase', branch='dev', version=dev_branch_version, sha1='87704611151af78cfef17ae518c40bfb49c7b934', author='Paul Wicking', fixes=[], task_numbers=["QTBUG-63248"], subject='Doc: Update really old screenshot in Sliders Example'),
            FixedByTag(repository='qt/qtbase', branch='dev', version=dev_branch_version, sha1='ae289884db05cbaac71156983974eebfb9b59730', author='Paul Wicking', fixes=[], task_numbers=["QTBUG-62072"], subject='Doc: Fix wrong link in QFont documentation'),
            FixedByTag(repository='qt/qtbase', branch='dev', version=dev_branch_version, sha1='cdf154e65a3137597f62880361c407e368aae0d6', author='Allan Sandfeld Jensen', fixes=[], task_numbers=["QTBUG-69724"], subject='Optimize blits of any compatible formats'),
            FixedByTag(repository='qt/qtbase', branch='dev', version=dev_branch_version, sha1='d2d59e77d5e16bc79ddfed37f4f29d1dcd9b92a7', author='Paul Wicking', fixes=[], task_numbers=["QTBUG-53856"], subject='Doc: Increase precision in description of convenience typedefs'),
            FixedByTag(repository='qt/qtbase', branch='dev', version=dev_branch_version, sha1='1c8f9eb79da837db8e37cf6348de459088c3a20e', author='Allan Sandfeld Jensen', fixes=[], task_numbers=["QTBUG-69724"], subject='Add missing optimization for loading RGB32 to RGBA64 using NEON'),
            FixedByTag(repository='qt/qtbase', branch='dev', version=dev_branch_version, sha1='66be5445e64b54bf60069dfee5dd918459e3deed', author='Friedemann Kleint', fixes=[], task_numbers=["QTBUG-53717"], subject='Windows: Implement Qt::WindowStaysOnBottomHint'),
            FixedByTag(repository='qt/qtbase', branch='dev', version=dev_branch_version, sha1='f0ff73f631093b11c77d8d6fb548acfe8eb62583', author='Joerg Bornemann', fixes=[], task_numbers=["QTBUG-67905"], subject='QProcess::startDetached: Fix behavior change on Windows'),
            FixedByTag(repository='qt/qtbase', branch='dev', version=dev_branch_version, sha1='8c4207dddf9b2af0767de2ef0a10652612d462a5', author='Eirik Aavitsland', fixes=[], task_numbers=["QTBUG-69449"], subject='Fix crash in qppmhandler for certain malformed image files'),
            FixedByTag(repository='qt/qtbase', branch='dev', version=dev_branch_version, sha1='81910b5f3cfb8c8b0c009913d62dacff4e73bc3b', author='Timur Pocheptsov', fixes=[], task_numbers=["QTBUG-69677"], subject='SecureTransport - disable lock on sleep for the custom keychain'),
            FixedByTag(repository='qt/qtbase', branch='dev', version=dev_branch_version, sha1='db738cbaf1ba7a4886f7869db16dbb9107a8e65e', author='Ales Erjavec', fixes=[], task_numbers=["QTBUG-69404", "QTBUG-30116"], subject='QCommonStylePrivate::viewItemSize: Fix text width bounds calculation'),
            FixedByTag(repository='qt/qtbase', branch='dev', version=dev_branch_version, sha1='780dc2291bc0e114bab8b9ccd8706708f6b47270', author='Kai Koehne', fixes=[], task_numbers=["QTBUG-67443"], subject='Fix builds with some MinGW distributions'),
            FixedByTag(repository='qt/qtbase', branch='dev', version=dev_branch_version, sha1='c5af04cf8aa7bf2fbeaaf2a40f169fe8c17239f1', author='Błażej Szczygieł', fixes=[], task_numbers=["QTBUG-61948"], subject='HiDPI: Fix calculating window mask from pixmap on drag and drop'),
            FixedByTag(repository='qt/qtbase', branch='dev', version=dev_branch_version, sha1='4126de887799c61793bf1f9efc8b7ac7b66c8b32', author='Gabriel de Dietrich', fixes=[], task_numbers=["QTBUG-69496"], subject='QCocoaMenuLoader - ensure that ensureAppMenuInMenu indeed, ensures'),
            FixedByTag(repository='qt/qtbase', branch='dev', version=dev_branch_version, sha1='6f87926df55edb119e5eeb53c3beac135fdf72e2', author='Gatis Paeglis', fixes=[], task_numbers=["QTBUG-68501", "QTBUG-69628"], subject='xcb: partly revert 3bc0f1724ae49c2fd7e6d7bcb650350d20d12246'),
            FixedByTag(repository='qt/qtbase', branch='dev', version=dev_branch_version, sha1='0dfdf23d05d09cbffcec4021c9cbebfb6eeddfa7', author='Paul Wicking', fixes=[], task_numbers=["QTBUG-59487"], subject='Doc: Synchronize documentation with code snippet'),
            FixedByTag(repository='qt/qtbase', branch='dev', version=dev_branch_version, sha1='46fc3d3729df9e81e42f87c46907d6eb81a0c669', author='Friedemann Kleint', fixes=[], task_numbers=["QTBUG-69637"], subject='Windows QPA: Fix override cursor being cleared when crossing window borders'),
            FixedByTag(repository='qt/qtbase', branch='dev', version=dev_branch_version, sha1='e386cd03d12e401b9e3945602e9621a86009fa11', author='Paul Wicking', fixes=[], task_numbers=["QTBUG-68109"], subject='Doc: Remove reference to QTestEvent'),
            FixedByTag(repository='qt/qtbase', branch='dev', version=dev_branch_version, sha1='341d967068516ff850227f718eaff46530cd97c2', author='Paul Wicking', fixes=[], task_numbers=["QTBUG-69678"], subject='Doc: Fix broken links after page rename'),
            FixedByTag(repository='qt/qtbase', branch='dev', version=dev_branch_version, sha1='6a1c26b08a56cd71315fcbbf2743c32072d806d2', author='Paul Wicking', fixes=[], task_numbers=["QTBUG-69483"], subject='Doc: Update signals and slots introduction page'),
            FixedByTag(repository='qt/qtbase', branch='dev', version=dev_branch_version, sha1='9a30a8f4fc19a90835e4d1032f9ab753ff3b2ae6', author='Edward Welbourne', fixes=[], task_numbers=["QTBUG-23307"], subject='Link from QLocale to where date-time formats are explained'),
            FixedByTag(repository='qt/qtbase', branch='dev', version=dev_branch_version, sha1='2dfa41e0eac65f5772ec61364f9afd0ce49fecc7', author='Mårten Nordheim', fixes=[], task_numbers=["QTBUG-65960"], subject='Return to eventloop after emitting encrypted'),
            FixedByTag(repository='qt/qtbase', branch='dev', version=dev_branch_version, sha1='f43e947dc405b6a2324656f631c804db8e8dec3d', author='Jüri Valdmann', fixes=[], task_numbers=["QTBUG-69626"], subject='QJsonDocument: Make emptyObject an object')
        ],
    ),
    (
        # There is a commit with a line "Fixes:" which doesn't have any bug number since it's part of the normal commit message.
        # Should not trigger anything here.
        ChangeRange(repository='yocto/meta-qt5', branch='refs/heads/upstream/jansa/master', before='4587cc3b2b8707ed71eb15b9a0a460d76099606e', after='a563a6f0e7f4bbbadf8b0d85b06f63878e6142c2'),
        []
    ),
    (
        # test that a newly created branch works (before will be None), using the very first commits of the dev branch
        ChangeRange(repository='qt/qtbase', branch='dev', before=None, after='07bed9a211115c56bfa63983b0502f691f19f789'),
        []
    ),
    (
        # The first commit has broken encoding in the author name, check that we don't crash on that
        ChangeRange(repository='qt/qtdatavis3d', branch='refs/heads/5.11.2', before=None, after='7997c3aca1d6e03dd31e145d70a7a40df17e5330'),
        []
    ),
    (
        # This has a long Fixes: random comment line, skip it
        ChangeRange(repository='qt/qtlocation-mapboxgl', branch='upstream/12268-android-collator-wrapper', before='d9e4c61923813b61ffccb6439d0fd3e9993a1a05', after='7e51e52f0cabd909557b763f10e90ac0444e90a1'),
        []
    ),
    (
        # Invalid version number: tqtc/5.12
        ChangeRange(repository='qt/tqtc-qt5', branch='refs/heads/tqtc/5.12', before='33276c1719d2623dff6aec11e1f3dc1cb0e45847', after='bc644fd6c9b4ef409efc5a4378420c3aca2d07b8'),
        [
            FixedByTag(repository='qt/tqtc-qt5', branch='tqtc/5.12', version=None, sha1='bb6a91d5d4c684e8a97feca61449b41628afaefa', author='Joni Jantti', fixes=[], task_numbers=['QTQAINFRA-2103'], subject='Provisioning: PyPFD2')
        ]
    ),
    (
        ChangeRange(repository='qt/qtdeclarative', branch='refs/heads/5.12.0', before='920f50731a8fe7507aece1318c9e91f3f12b525e', after='9e9acff340032bd4ec5ee6fbd1b13cd51e14ca3d'),
        [
            FixedByTag(repository='qt/qtdeclarative', branch='5.12.0', version='5.12.0', sha1='9e9acff340032bd4ec5ee6fbd1b13cd51e14ca3d', author='Shawn Rutledge', fixes=['QTBUG-70258'], task_numbers=[], subject='MultiPointTouchArea: capture the mouse position on press')
        ]
    ),
    (
        ChangeRange(repository='qt/qtlocation-mapboxgl', branch='refs/heads/upstream/user-location-delegate-method', before='246be964f2e222118643bacac1a70c2692f2bdec', after='04add9801e557b06c08189659c4fbb8bdc7d235b'),
        []
    ),
    (
        ChangeRange(repository='qt/qtdeclarative', branch='refs/heads/5.13.0', before='722fd8b86e7c3b5d6e4c3382f2710e4d3bfed3ec~', after='722fd8b86e7c3b5d6e4c3382f2710e4d3bfed3ec'),
        [
            FixedByTag(repository='qt/qtdeclarative', branch='5.13.0', version='5.13.0', sha1='722fd8b86e7c3b5d6e4c3382f2710e4d3bfed3ec', author='Allan Sandfeld Jensen', fixes=['QTBUG-32525', 'QTBUG-70748'], task_numbers=[], subject='Render inline custom text objects'),
        ]
    ),
])
@pytest.mark.asyncio
async def test_parsing(event_loop, change: ChangeRange, expected: List[FixedByTag]):
    async with Repository(change.repository) as repo:
        fixes = await repo.parse_commit_messages(change)
        change.__repr__()
        for fix in fixes:
            fix.__repr__()
        assert fixes == expected


@pytest.mark.parametrize("versions,sorted_versions", [
    (
        [Version("5.12"), Version("5.12.0"), Version("5.12.1")],
        [Version("5.12"), Version("5.12.0"), Version("5.12.1")],
    ),
    (
        [Version("5.12.0"), Version("5.12"), Version("5.12.1")],
        [Version("5.12"), Version("5.12.0"), Version("5.12.1")],
    ),
    (
        [Version("5.12.1"), Version("5.12.0"), Version("5.12")],
        [Version("5.12"), Version("5.12.0"), Version("5.12.1")],
    ),
])
def test_version_class(versions: List[Version], sorted_versions: List[Version]):
    assert sorted(versions) == sorted_versions
    assert Version("5.12") < Version("5.12.0")
    assert Version("5.12.0") > Version("5.12")
    assert Version("5.12") <= Version("5.12.0")
    assert Version("5.12.0") >= Version("5.12")
    assert Version("5.12.0") != Version("5.12")

def test_have_secrets():
    dir_name = os.path.join(os.path.dirname(os.path.abspath(__file__)))
    assert os.path.exists(os.path.join(dir_name, "../jira_gerrit_bot_id_rsa"))

    config = Config()
    oauth = config.get_oauth_data("production")
    assert oauth.access_token != "get_this_by_running_oauth_dance.py"
    assert oauth.token_secret != "get_this_by_running_oauth_dance.py"
    assert oauth.key_cert
    assert os.path.exists(os.path.join(dir_name, "..", f"{oauth.key_cert_file}.pem"))
    assert os.path.exists(os.path.join(dir_name, "..", f"{oauth.key_cert_file}.pub"))
