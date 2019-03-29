# JIRA bot to close issues

Listen to gerrit events and close corresponding JIRA tasks when there is a "Fixes:" footer in the commit message.

## Prerequisites and building

You need to have [pipenv](https://pipenv.readthedocs.io/en/latest/) installed.
Run `make` to install dependencies.

## Connecting to a JIRA account using OAuth

* Generate a private/public rsa certificate pair (`jiracloser.pem`, `jiracloser.pub`) in the root directory (next to this readme file).
  * See for example https://www.madboa.com/geek/openssl/#key-rsa

* Log in to JIRA as admin.
* Find "Integrations" -> "Application Links"
  * Enter a random URL (e.g. https://www.qt.io) and click "Create new link"
  * Fill out the fields, it does not really matter:
    * Name: Gerrit Issue Bot
    * Type: Generic
    * Service Provider Name: Qt JIRA bot (anything goes)
    * Consumer key: jira-gerrit-bot-oauth-consumer
    * Shared Secret: 8aG2#dwV24$e9J43@s8b  # this is actually unused, put some random garbage here to make sure
    * Request Token URL: https://www.qt.io
    * Access token URL: https://www.qt.io
    * Authorize URL: https://www.qt.io
    * Create incoming link: yes
  * Next page (this is important, can be edited later under incoming authentication)
    * Consumer key: jira-gerrit-oauth
    * Consumer Name: Gerrit Issue Closer
    * Public Key: content of `jiracloser.pub`
  * You can delete the outgoing auth after this excercise

* Log in to JIRA with the bot user.
* In a terminal run: `make oauth`
* The script puts out a URL, which must be *opened as the bot user*
* Click Allow
* Press enter in the terminal
* Copy the `oauth_token` and `oauth_token_secret` into config.ini.

## Running the bot

`make run`

## Running tests

Run `make test` which runs a style check, type checking and the automated tests.
Please make sure that all of them pass before contributing.

It's also possible to generate coverage information (`make coverage` will open a a browser).
