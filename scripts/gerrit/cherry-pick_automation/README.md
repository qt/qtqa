# Introduction
A new branching model introduced during the 2019 Qt Contributor's summit
outlined a method of pushing all changes to the `dev` branch of qt5
modules, and cherry picking those changes to other appropriate branches.

As part of this design, automation is called for in managing the
cherry-pick operations to as high a degree as possible. This script
operates as a bot to perform such associated tasks.

### How it works
This bot runs as a nodejs server, listening to incoming webhook requests
from gerrit. Such webhooks are configured gerrit-side on a per-repo basis.

1. When an incoming request is received and is of type "change-merged",
it is immediately stored in a local postgres database for state-tracking.
2. The incoming commit message is then scanned for the "Pick-to:" footer
and any branches found in the footer are validated against the gerrit
repo the change was merged to.
3. For each validated branch, a cherry-pick operation is attempted. For
invalid branches, the bot will post to the original change and alert the
owner of the change.
4. Upon successful creation of the cherry-pick, the bot will either:
    1. Add reviewers and alert the original owner that the change has
    merge conflicts.
    2. Automatically approve and stage the change if gerrit did not
    report any git conflicts.

### What this proof-of-concept does NOT (yet) do
1. This does not pull forward from release branches to dev for patches
submitted directly to those release branches.
2. This does not currently verify that cherry-picks are submitted for
automatic merging in the same order they were merged in the source
branch (`dev`). It could be possible to queue automatic staging requests
until an earlier patch merges.
3. This does not currently verify if a cherry-pick already exists, but
the pick operation should fail if a pick with the same change ID exists
on the target branch. The bot will currently post a comment on the
original change with the failure reason if this occurs.
4. This does not currently listen for an automatically staged cherry-pick
to pass or fail integration.
5. This bot does not currently resume operations from stored database
entries if it is restarted.
6. Branch validation does not currently verify that the target branch
is open to receiving changes.

### Installation and running

#### Pre-requisites
1. This bot has been developed on a Linux host, though it may function
on Windows.
2. NodeJS >= 12.13.1
3. npm >= 6.12.1

#### Installation
1. `npm install` in the project directory

#### General configuration options (config.json)
1. `WEBHOOK_PORT` Port to listen on for gerrit webhook events. `Default: 8083`
2. `GERRIT_IPV4` IPv4 address of the gerrit server. Set this or the IPv6 address
to whitelist incoming requests. `Default: 54.194.93.196`
3. `GERRIT_IPV6` IP address of the gerrit server. Set this or the IPv4 address
to whitelist incoming requests. `Default: ''`
4. `GERRIT_URL` Gerrit Host url base for sending REST requests.
`Default: codereview.qt-project.org`
5. `GERRIT_PORT` Port to connect to gerrit's REST API. `Default: 443`
6. `GERRIT_USER` Basic Authentication user with permission to access the
gerrit's REST API. `Default: ''`
7. `GERRIT_PASS` Basic Authentication password gerrit REST API user.
`Default: ''`
8. `SMTP_SERVER` The anonymous email server to connect to for bot mails.
This is separate from gerrit. `Default: smtp.intra.qt.io`
9. `SMTP_PORT` Port to connect to the email server on. `Default:25`

#### PostgreSQL database configuration (postgreSQLconfig.json)
1. `user` Databse username with read/write access `Default: "postgres"`
2. `host`: Postgres database URL `Default: ''`
3. `password`: Databse user password `Default: ''`
4. `database`: The database to be used by cherrypick bot `Default: ''`
5. `port`: Port postgres is listening on for connections `Default: '5432'`

#### Running
1. `npm start` in the project directory

#### Test
This proof-of-concept bot currently has no tests.
