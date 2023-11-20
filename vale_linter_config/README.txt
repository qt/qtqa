This directory includes the vale prose linter config,
which is required to run vale. For more info. about
vale, refer to https://vale.sh/.

Introduction
=============

The directory includes, a config file, few rules
to check for, and a vocabulary list. Follow these
instructions to lint HTML file(s) using the latest
version of vale along with this config:

1. Install the vale either from github or use a
   package manager of your choice. Refer to
   https://vale.sh/docs/vale-cli/installation/ for
   more info.
2. Export the VALE_CONFIG_PATH environment variable
   with the absolute path to `.vale.ini`.
3. Run the `vale ls-config` command to test if it
   finds the config. You should see the config in
   JSON format.
4. Run the `vale sync` to download the packages listed
   in the config. The current version of the config file
   will download the Microsoft style guide rules, but you
   can add more packages to the list. For the list of
   packages offered by vale, see https://vale.sh/hub/.
5. Now call `vale` either with a single HTML file or
   a bunch of files in a directory. You should see
   a list of issues (categorized as error, warning,
   or suggestion) that vale found based on the checks
   configured in the .vale.ini.

Amend or add new rules
======================

Vale rules are simple text files in YAML format. You can
either enable or disable individual rules in a style, which
is a directory with different YAML files for each rule.
You could also add a new rule under a custom style. See
 https://vale.sh/docs/topics/styles/ for more info.

Vocabularies or terms list
==========================

The directory also includes the Qt vocabulary, which is a sub directory
in the `styles\Vocab`, containing two files: 'accept.txt' and
'reject.txt'. The vale config file in this directory ignores terms/words
in the accept list and warns about the reject list.

You can extend or update the vocabularies list either by updating the
existing ones, or creating a new vocabulary for your project or product
documentation. It is recommended to have a unified list of vocabularies
than several project-specific ones. See
https://vale.sh/docs/topics/vocab/ for more info.
