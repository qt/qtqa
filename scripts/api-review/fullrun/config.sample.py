#############################################################################
##
## Copyright (C) 2021 The Qt Company Ltd.
## Contact: https://www.qt.io/licensing/
##

next_version = '6.2'
previous_versions = ['6.1', '6.0', '5.15']
most_recent_previous_version = previous_versions[0]
task_id = 'QTBUG-xxxxx'
exclude_modules = []

git_email = 'john.doe@qt.io'
qt5_url = 'ssh://codereview.qt-project.org:29418/qt/qt5'
qt5_repo = 'qt5'
commit_hook_cmd = 'scp -p -P 29418 codereview.qt-project.org:hooks/commit-msg'
