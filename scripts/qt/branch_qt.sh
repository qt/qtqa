#!/bin/sh

# Copyright (C) 2014 Digia Plc and/or its subsidiary(-ies).
# Contact: http://www.qt-project.org/legal
#
# You may use this file under the terms of the 3-clause BSD license.
# See the file LICENSE in qt/qtrepotools for details.
#

handle_module()
{
    git fetch gerrit || exit

    # Note: this only works if the supermodule refers to commits which already
    # have the right version.

    mod=$(basename $(pwd))
    case $mod in
        qtrepotools|qtqa)
            exit 0
            ;;
        qtbase)
            file=src/corelib/global/qglobal.h
            ver=$(sed -n -e 's,^#define QT_VERSION_STR \+"\([0-9.]\+\).*,\1,p' $file)
            ;;
        *)
            file=.qmake.conf
            ver=$(sed -n -e 's,^MODULE_VERSION \+= \+\([0-9.]\+\).*,\1,p' $file)
            ;;
    esac

    vermaj=${ver%%.*}
    vermin=${ver#$vermaj.}
    vermin=${vermin%%.*}
    verpat=${ver#$vermaj.$vermin.}
    case $1 in
        *.*.*)
            curbranch=$vermaj.$vermin
            newbranch=$ver
            verpat=$((verpat+1))
            ;;
        *.*)
            curbranch=dev
            newbranch=$vermaj.$vermin
            vermin=$((vermin+1))
            verpat=0   # that should be pointless
            ;;
    esac

    nextver=$vermaj.$vermin.$verpat
    echo "Bumping $mod on $curbranch to $nextver, creating $newbranch"

    git checkout -q gerrit/$curbranch || exit

    case $mod in
        qtbase)
            nextverhex=$(printf "%02x%02x%02x" $vermaj $vermin $verpat)
            sed -i -e "s,^\\(#define QT_VERSION_STR \\+\"\\)[0-9.]\\+\\(\".*\\)$,\\1$nextver\\2,; \
                       s,^\\(#define QT_VERSION \\+0x\\)[0-9a-f]\\+\\(.*\\)$,\\1$nextverhex\\2," $file || exit
            ;;
        *)
            sed -i -e "s,^\\(MODULE_VERSION \\+= \\+\\)[0-9.]\\+\\(.*\\)$,\\1$nextver\\2," $file || exit
            ;;
    esac

    git commit -q -m "Bump version" $file || exit

    git push -q gerrit HEAD~1:refs/heads/$newbranch HEAD:refs/heads/$curbranch HEAD:refs/staging/$curbranch
}

proceed()
{
    if ! test -f qt.pro; then
        echo "This does not look like a Qt5 top-level repo." >&2
        exit 1
    fi

    ### FIXME: check that everything is clean

    branch=$(git symbolic-ref --short HEAD) || exit
    case $branch in
        *.*.*)
            echo "Cannot branch from release branch" >&2
            exit 1
            ;;
        *.*)
            case $1 in
                $branch.*)
                    ;;
                *)
                    echo "Cannot branch $1 from $branch" >&2
                    exit 1
                    ;;
            esac
            ;;
        dev)
            case $1 in
                *.*.*)
                    echo "Cannot branch $1 from dev" >&2
                    exit 1
                    ;;
            esac
            ;;
    esac

    git fetch gerrit || exit
    git checkout -q gerrit/$branch || exit
    git push -q gerrit HEAD:refs/heads/$1 || exit

    # This makes sure we have all submodules, and only the ones we want.
    # It also updates the submodules, so we have "orientation" commits.
    ./init-repository -f || exit

    for module in $(git config --get-regexp '^submodule\..*\.url$' | sed 's,^submodule\.,,; s,\.url.*,,'); do (
        cd $module || exit
        handle_module $1
    ); done

    git checkout $branch
}

case $1 in
    *.*)
        proceed $1
        ;;
    *)
        echo "Usage: $0 <version>" >&2
        exit 1
        ;;
esac
