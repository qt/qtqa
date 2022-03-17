# Introduction
A new branching model introduced during the 2019 Qt Contributor's summit
outlined a method of pushing all changes to the `dev` branch of qt5
modules, and cherry-picking those changes to other appropriate branches.

As part of this design, automation is called for in managing the
cherry-pick operations to as high a degree as possible. This script
operates as a bot to perform such associated tasks.

### How it works
This bot runs as a nodejs server, listening to incoming webhook requests
from gerrit. Such webhooks are configured gerrit-side on a per-repo basis.
Processing requests are stored in a postgres database, which is used
to restore any in-process items and listeners upon restarting the service.

1. When an incoming request is received and is of type "change-merged",
   it is immediately stored in a local postgres database for state-tracking.
2. The incoming commit message is then scanned for the "Pick-to:" footer
   and any branches found in the footer are validated against the gerrit
   repo the change was merged to.
3. For each validated branch, a cherry-pick operation is attempted. For
   invalid branches, the bot will post to the original change and alert the
   owner of the change.
    -  If the change is part of a relation chain, and the pick
       requires a parent on the target branch, the bot will search up the
       relation chain for a parent which has a pick on the same target branch.
       If none is found, it will pick to the target branch head.
    -  If the pick was created on branch head, but the bot expected to see
       the immediate parent on the relation chain also picked to the target
       branch, the bot will listen for the expected parent to be created
       for 48 hours. If the expected parent pick is created during this
       period, the cherry-pick will be reparented to its immediate parent
       pick from the original relation chain.
4. Upon successful creation of the cherry-pick, the bot will either:
    1. Add reviewers and alert the original owner that the change has
       conflicts.
    2. Automatically approve and stage the change if gerrit did not
       report any git conflicts. Changes in a relation chain will be staged
       together whenever possible.
    -  **Note**: If the cherry-pick was created from a change that was part of
       a relation chain, but the cherry-pick was picked onto the target
       branch head without conflicts, it will be staged automatically.
       In this case, the change will not be reparented, even if a pick
       correlating to the original change's parent is created on the
       target branch. This is acceptable, since the cherry pick had no
       conflicts and should not have any direct dependencies on
       any other changes.

### Installation and running

#### Pre-requisites
1. This bot has been developed on a Linux host, though it may function
   on Windows.
2. NodeJS >= 12.13.1
3. npm >= 6.12.1
4. A postgres database with read/write access

#### Installation
1. `npm install` in the project directory

#### General configuration options
Configuration set via config.json OR environment variables

**Note:** Environment variables override configuration in config.json

1. `WEBHOOK_PORT` Port to listen on for gerrit webhook events. `Default: 8083`
   - This is overridden in HEROKU instances by the PORT environment variable,
     which is randomly assigned and cannot be set by the user.
   - See https://devcenter.heroku.com/articles/runtime-principles#web-servers
2. `GERRIT_IPV4` IPv4 address of the gerrit server. Set this or the IPv6
   address to whitelist incoming requests. `Default: 54.194.93.196`
3. `GERRIT_IPV6` IP address of the gerrit server. Set this or the IPv4 address
   to whitelist incoming requests. `Default: ''`
4. `GERRIT_URL` Gerrit Hostname for sending REST requests. HTTPS is assumed
   unless explicitly specified with `http://` prefix or `GERRIT_PORT` set to 80.
   `Default: codereview.qt-project.org`
5. `GERRIT_PORT` Port to connect to gerrit's REST API. `Default: 443`
6. `GERRIT_USER` Basic Authentication user with permission to access the
   gerrit's REST API. `Default: ''`
7. `GERRIT_PASS` Basic Authentication password gerrit REST API user.
   `Default: ''`
8. **Optional** `SES_ACCESS_KEY_ID`: The access key ID for connecting with an Amazon SES
   email client. `Default: ''`
9. **Optional** `SES_SECRET_ACCESS_KEY`: The access key secret for connecting with an Amazon
   SES email client. `Default: ''`
10. **Optional** `ADMIN_EMAIL` Email address where critical debug messages are sent.
   `Default: ''`
11. **Optional** `EMAIL_SENDER` Email address from which critical debug messages are sent.
   Note the formatting of the default sender.
   `Default: '"Cherry-Pick Bot" <cherrypickbot@qt.io>'`

#### PostgreSQL database configuration
> postgreSQLconfig.json
1. `user` Database username with read/write access `Default: "postgres"`
2. `host`: Postgres database URL `Default: ''`
3. `password`: Database user password `Default: ''`
4. `database`: The database to be used by cherry-pick bot `Default: ''`
5. `port`: Port postgres is listening on for connections `Default: '5432'`

> `DATABASE_URL` environment variable - Overrides postgreSQLconfig.json
1. See https://devcenter.heroku.com/articles/heroku-postgresql#provisioning-heroku-postgres

#### Running
1. `npm start` in the project directory

#### Test
This beta bot currently has no tests.
