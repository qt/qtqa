# Qt Module Updater

This is a tool that serves the purpose of automating the process of keeping pinned dependencies between Qt git repositories up-to-date.

Qt modules in git repositories depend on modules from other repositories and therefore each repository encodes its dependencies to other repositories using a configuration file called ```dependencies.yaml```. It lists the required and optional dependencies as well as the commit sha1s that are known to work.

All repositories with their dependencies form a graph, with qtbase typically at the root. A newer version of qtbase shall result in a change to ```dependencies.yaml``` in qtsvg. Once approved by the CI system, a change to qtdeclarative is needed to pull in the newer version of qtsvg and implicitly qtbase.

This tool automates the pushing of updates through the graph of dependencies and once all modules of qt5.git are complete, an update of submodule sha1s to qt5.git will be posted.

## Algorithm

The process of updating dependencies starts by collecting a list of all repositories and determining the root of the graph. That's typically qtbase. From there on, updates to all repositories are posted that only depend on the root. All other repositories remain in a "todo" list. The root is remembered in a "done" list and all repositories that we are currently trying to bring up-to-date are in a "pending" list. Once this process is started, the program saves its state in personal branch under refs/personal/qt_submodule_updater_bot/state/<branch> and terminates.

The next time the Qt Module Updater is started, it resumes the state and begins checking the state of all pending updates. If an update succeeded, then the corresponding repository is added to the "done" list and we can prepare updates for repositories that have now their dependencies satisfied by picking them from the "todo" list. If the update failed, the repository is dropped from the batch of updates and all other repositories that directly or indirectly depend on the failed one are also removed. After every such iteration of processing pending updates and pushing new ones to Gerrit, the process terminates and saves its state.

When the todo list is empty and there are no more pending updates, the batch update is complete. If during that update there were no failures, the Qt Module Updater will also push a change to qt5.git with an update to all submodule sha1s of the new consistent set of modules.

## Usage

The Qt Module Updater is written in Golang and requires at least version 1.13. To build the program, simply clone the repository and run

    go build

When running the program, git repositories will be cloned from Qt's Gerrit instance and stored as bare clones in the ```git-repos``` sub-directory.

Every invocation requires passing a ```-branch=``` that specifies the Qt version branch to use as reference. By default, repositories from ```qt/qt5``` are picked up, but it is possible to override this with the ```-product=``` parameter.

When run in a production environment, it is desirable to pass the ```-stage-as-bot``` parameter, to ensure that changes are pushed as the special Qt Submodule Update bot.

For manual testing, it is also possible to use the ```-manual-stage``` parameter to merely push changes to Gerrit but not automatically stage them.

