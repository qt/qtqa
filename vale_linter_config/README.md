This directory includes Vale prose linter configs for linting Qt
documentation source files (.qdoc, .qdocinc, .qml, .cpp) and generated
HTML output. For more info about Vale, refer to https://vale.sh/.

These instructions are also available at the Qt Wiki:
https://wiki.qt.io/Setting_Up_Vale

## Introduction

The directory includes two config files, a set of rules, and a
vocabulary list:

- `.vale-qdoc.ini` — for linting QDoc source files (.qdoc, .qdocinc,
  .qml, .cpp). Requires a patched Vale build with QDoc parser support.
- `.vale.ini` — for linting generated HTML output. Works with the
  standard Vale release.

Follow these steps to get started:

1. Install Vale:

   - To lint QDoc sources (.qdoc, .qdocinc, .qml, .cpp), download
     the patched Vale binary with QDoc parser support (minimum
     v3.15.1-qdoc) from
     https://github.com/veshivas/vale/releases.

   - To lint generated HTML only, install the standard Vale release
     from a package manager or from
     https://vale.sh/docs/vale-cli/installation/.

2. Run `vale sync` from this directory to download the packages listed
   in the config. This downloads the Microsoft style guide rules. Run
   it once per config:

   ```
   vale --config=.vale-qdoc.ini sync
   vale --config=.vale.ini sync
   ```

   For other available packages, see https://vale.sh/hub/.

3. Run `vale ls-config` to verify Vale finds the config. You should see
   the config printed in JSON format.

4. Run Vale against your files:

   QDoc sources:
   ```
   vale --config=.vale-qdoc.ini <file.qdoc|directory>
   ```

   Generated HTML:
   ```
   vale --config=.vale.ini <file.html|directory>
   ```

   You should see a list of issues (categorized as error, warning, or
   suggestion) based on the checks configured in the respective config.

## Amend or add new rules

Vale rules are simple text files in YAML format. You can either enable
or disable individual rules in a style, which is a directory with
different YAML files for each rule. You could also add a new rule under
a custom style. See https://vale.sh/docs/topics/styles/ for more info.

## Vocabularies or terms list

The directory also includes the Qt vocabulary, which is a subdirectory
in `styles/config/vocabularies/`, containing two files: `accept.txt`
and `reject.txt`. The vale config file in this directory ignores
terms/words in the accept list and warns about the reject list.

You can extend or update the vocabularies list either by updating the
existing ones, or creating a new vocabulary for your project or product
documentation. It is recommended to have a unified list of vocabularies
rather than several project-specific ones. See
https://vale.sh/docs/topics/vocab/ for more info.

## Pre-commit hook

The `vale-pre-commit` script is a pre-commit hook that lints only the
lines changed in a commit, so pre-existing issues in untouched parts of
a file do not block your work. It covers:

- `.qdoc`, `.qdocinc`, `.qml` — linted directly via Vale.
- `.cpp`, `.h`, `.cc`, `.cxx` — only the `/*!...*/` doc-comment blocks
  that contain changed lines are linted.

For single-line edits, filtering is column-precise: a pre-existing
warning at the start of a line is not reported if only the end of that
line was changed.

The hook blocks the commit on warnings, errors, and suggestions.
You can bypass it with `git commit --no-verify`.

### Requirements

The hook requires the patched Vale build described in step 1 above,
installed and available on PATH.

When running the hook outside of qtqa (for example in qtbase or
qtdoc), set `VALE_CONFIG_PATH` to point to the config file in qtqa:

```
VALE_CONFIG_PATH=/path/to/qtqa/vale_linter_config/.vale-qdoc.ini git commit
```

Set this variable permanently in your shell profile to avoid passing
it on every commit.

### Installation

Navigate to the hooks directory of the repository you want to lint:

```
cd <repository checkout>/.git/hooks
```

In qtqa, where vale_linter_config is part of the same repository,
create a symlink:

```
ln -s ../../vale_linter_config/vale-pre-commit pre-commit
```

In other Qt repositories such as qtbase, where qtqa is a sibling
checkout, use the path to qtqa:

```
ln -s <path to qtqa>/vale_linter_config/vale-pre-commit pre-commit
```

If a pre-commit hook already exists (for example a clang-format hook),
do not replace it with a symlink. Instead, add the following line at
the top of the existing file, before any early exits:

```
# In qtqa:
"$(git rev-parse --show-toplevel)/vale_linter_config/vale-pre-commit" || exit 1

# In other repositories:
"<path to qtqa>/vale_linter_config/vale-pre-commit" || exit 1
```
