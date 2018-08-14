#!/bin/sh

# Copyright (C) 2017 The Qt Company Ltd.
# Contact: https://www.qt.io/licensing/
#
# You may use this file under the terms of the 3-clause BSD license.
# See the file LICENSE in qt/qtrepotools for details.
#

#testing=echo
#set -x

allow_review=0
forward=false

# <module> <source> <branch> [--ff]
# $PWD is $GITDIR
do_push()
{
    ssh="ssh $(git config remote.gerrit.url | sed 's,^ssh://,,; s,/.*$,,; s,:, -p ,')"
    bad=$($ssh gerrit query --format=JSON "project:qt/$1 branch:$3 \(status:staging OR status:staged OR status:integrating\)" | wc -l)
    if test x$bad != x1; then
        if test -n "$4"; then
            echo "*********** $1 is busy. Retry later."
            exit 1
        fi
        if test $allow_review = 0; then
            echo "*********** $1 is busy. Retry later or pass --review."
            exit 1
        fi
        echo "*********** $1 is busy. Pushing for review."
        $testing git push -q gerrit $2:refs/for/$3 || exit
    else
        # Note that there is a race condition between direct pushing and staging.
        # The user MUST pay attention to whether the push to staging succeeds.
        $testing git push -q gerrit $2:refs/heads/$3 $2:refs/staging/$3 || exit
    fi
}

# <phase>
# $PWD is $GITDIR, $curbranch, $newbranch and $mod are set
dupe_check()
{
    phase=$newbranch-$1
    donephase=$(git config qtbranching.$curbranch.done)
    if test x$phase = x$donephase; then
        echo "Module $mod already processed."
        exit
    fi
}

# $PWD is $GITDIR, $phase and $curbranch are set
dupe_commit()
{
    $testing git config qtbranching.$curbranch.done $phase
}

# $PWD is $GITDIR, $curbranch is set
dupe_reset()
{
    $testing git config --unset qtbranching.$curbranch.done
}

# <phase>
# $PWD is $GITDIR, $curbranch and $newbranch are set
handle_module()
{
    # Note: this only works if the supermodule refers to commits which already
    # have the right version.

    mod=$(basename $(pwd))
    case $mod in
    qtrepotools|qtqa)
        # These modules are never branched.
        exit 0
        ;;
    esac

    case $1 in
    branch)
        # This is inherently idempotent.
        echo "Creating $newbranch from $curbranch in $mod"

        git fetch gerrit || exit
        $testing git push -q gerrit gerrit/$curbranch:refs/heads/$newbranch || exit
        git config -f ../.gitmodules submodule.$mod.branch $newbranch || exit
        ;;
    sync)
        # This is can be repeated at will.
        echo "Syncing $curbranch and $newbranch in $mod"

        git fetch gerrit || exit

        currevs=$(git rev-list ^gerrit/$newbranch gerrit/$curbranch) || exit
        newrevs=$(git rev-list gerrit/$newbranch ^gerrit/$curbranch) || exit
        if test -z "$currevs"; then
            if test -z "$newrevs"; then
                echo "  Branches already in sync."
            else
                echo "  Updating $curbranch"
                do_push $mod gerrit/$newbranch $curbranch --ff
            fi
        else
            if test -z "$newrevs"; then
                if $forward; then
                    echo "  $newbranch is trailing - skipping."
                else
                    echo "  Updating $newbranch"
                    do_push $mod gerrit/$curbranch $newbranch --ff
                fi
            else
                echo "  Branches diverged - skipping."
            fi
        fi
        ;;
    merge)
        # This is not idempotent. We have a duplicate check to avoid uploading multiple
        # merges for review. Use 'reset' to start the next round if necessary.
        dupe_check merge
        echo "Merging $curbranch into $newbranch in $mod"

        git fetch gerrit || exit
        head=$(git rev-parse gerrit/$newbranch) || exit
        curhead=$(git rev-parse gerrit/$curbranch) || exit
        if test $head = $curhead; then
            echo "$newbranch already up-to-date."
        else
            git checkout $head || exit
            if git merge --ff-only $curhead; then
                do_push $mod HEAD $newbranch --ff
            else
                ### This needs to deal with conflicted merges
                git merge $curhead -m "Merge $curbranch into $newbranch" || exit
                git commit -q --amend -C HEAD  # Hack to ensure Change-Id
                do_push $mod HEAD $newbranch
            fi
        fi

        dupe_commit
        ;;
    reset)
        dupe_reset
        ;;
    bump)
        # This is not idempotent at all.
        dupe_check bump

        # The module version can diverge from the branch version (which always follows
        # the Qt release starting with 5.6). Only engin.io is affected by this.
        case $mod in
#        qtbase)
#            file=src/corelib/global/qglobal.h
#            ver=$(sed -n -e 's,^#define QT_VERSION_STR \+"\([0-9.]\+\).*,\1,p' $file)
#            ;;
        *)
            file=.qmake.conf
            ver=$(sed -n -e 's,^MODULE_VERSION *= *\([0-9.]\+\).*,\1,p' $file)
            ;;
        esac
        vermaj=${ver%%.*}
        vermin=${ver#$vermaj.}
        vermin=${vermin%%.*}
        verpat=${ver#$vermaj.$vermin.}
        case $newbranch in
        *.*.*)
            verpat=$((verpat+1))
            ;;
        *.*)
            vermin=$((vermin+1))
            verpat=0   # that should be pointless
            ;;
        esac
        nextver=$vermaj.$vermin.$verpat
        echo "Bumping $curbranch to $nextver in $mod"

        git fetch gerrit || exit
        git checkout -q gerrit/$curbranch || exit

        sed -i -e "s,^MODULE_VERSION *= *[0-9.]\\+\\(.*\\)$,MODULE_VERSION = $nextver\\1," $file || exit
        case $mod in
        qtbase)
#            nextverhex=$(printf "%02x%02x%02x" $vermaj $vermin $verpat)
#            sed -i -e "s,^\\(#define QT_VERSION_STR \\+\"\\)[0-9.]\\+\\(\".*\\)$,\\1$nextver\\2,; \
#                       s,^\\(#define QT_VERSION \\+0x\\)[0-9a-f]\\+\\(.*\\)$,\\1$nextverhex\\2," $file || exit
            case $newbranch in
            *.*.*)
                ;;
            *.*)
                file2=src/corelib/serialization/qdatastream.h
                perl -e '
                    local $/;
                    $_ = <STDIN>;
                    my ($vermaj, $vermin) = @ARGV;
                    my $ver = "${vermaj}_".($vermin - 1);
                    my $nextver = "${vermaj}_$vermin";
                    my $nextverhex = sprintf("%02x%02x00", $vermaj, $vermin);
                    my $nextnextverhex = sprintf("%02x%02x00", $vermaj, $vermin + 1);
                    s/^(#if QT_VERSION >= 0x)$nextverhex\n(#error [^\n]+\n#endif\n( +)Qt_DefaultCompiledVersion = Qt_)[0-9_]+$/$3Qt_$nextver = Qt_$ver,\n$1$nextnextverhex\n$2$nextver/ms;
                    print $_;
                ' $vermaj $vermin < $file2 > $file2.new
                mv $file2.new $file2 || exit
                file3=src/corelib/serialization/qdatastream.cpp
                perl -e '
                    local $/;
                    $_ = <STDIN>;
                    my ($vermaj, $vermin) = @ARGV;
                    my $ver = "${vermaj}_".($vermin - 1);
                    my $nextver = "${vermaj}_$vermin";
                    s/^( +)(\\value Qt_$ver Version[^\n]+\n)( +\\omitvalue Qt_DefaultCompiledVersion)$/$1$2$1\\value Qt_$nextver Same as Qt_$ver\n$3/ms;
                    s/^( +)(\\value Qt_$ver (Same as [^\n]+\n))( +\\omitvalue Qt_DefaultCompiledVersion)$/$1$2$1\\value Qt_$nextver $3$4/ms;
                    print $_;
                ' $vermaj $vermin < $file3 > $file3.new
                mv $file3.new $file3 || exit
                file="$file $file2 $file3"
                ;;
            esac
            ;;
        *)
            ;;
        esac
        git commit -q -m "Bump version" $file || exit

        do_push $mod HEAD $curbranch

        dupe_commit
        ;;
    esac
}

# <new_branch> <phase>
proceed()
{
    if ! test -f qt.pro; then
        echo "This does not look like a Qt5 top-level repo." >&2
        exit 1
    fi

    ### FIXME: check that everything is clean

    curbranch=$(git symbolic-ref --short HEAD) || exit
    newbranch=$1
    case $curbranch in
    *.*.*)
        echo "Cannot branch from release branch" >&2
        exit 1
        ;;
    *.*)
        case $newbranch in
        $curbranch.*)
            ;;
        *)
            echo "Cannot branch $newbranch from $curbranch" >&2
            exit 1
            ;;
        esac
        ;;
    dev)
        case $newbranch in
        *.*.*)
            echo "Cannot branch $newbranch from dev" >&2
            exit 1
            ;;
        esac
        ;;
    esac

    git fetch gerrit || exit
    git checkout -q gerrit/$curbranch || exit

    # This makes sure we have all submodules, and only the ones we want.
    # It also updates the submodules, so we are on the right branches.
    # Note: don't use --branch here, as it breaks idempotence.
    ./init-repository -f --module-subset=all,-ignore || exit

    for module in $(git config --get-regexp '^submodule\..*\.url$' | sed 's,^submodule\.,,; s,\.url.*,,'); do (
        cd $module || exit
        handle_module $2
    ); done

    if test $2 = branch && ! git diff --quiet .gitmodules; then
        git commit -m "Adjust submodule branches" .gitmodules || exit
        do_push qt5 HEAD $newbranch || exit
    fi
    ### downmerge top-level as well. caveat: branch names in .gitmodules.

    git checkout $curbranch
}

if test x$1 = x--review; then
    shift
    allow_review=1
fi
case $1 in
*.*)
    case $2 in
    branch|sync|merge|bump)
        proceed $1 $2
        exit
        ;;
    forward)
        forward=true
        proceed $1 sync
        exit
        ;;
    esac
    ;;
esac
echo "Usage: $0 [--review] <branch> {branch|sync|merge|bump}" >&2
exit 1
