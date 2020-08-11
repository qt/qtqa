# Warn Hanging Changes (after enabling Cherry-pick mode)

This script posts a negative code review `(-1)` if a change in a given repo
is not committed to the masterlike branch and includes instructions
to move the change to dev and add a `Pick-to:` footer.


## Usage
1. run `npm install` to configure dependencies
2. configure your gerrit username and password in config.json in this project's root directory
or via environment variables (same names as config.json)
    - **You Must use the Qt Cherry-Pick Bot account credentials or update
    the `commentPosterAccountId` variable in the script.** This prevents the
    script from posting the same comment twice if the script is re-run.
3. Edit warn_hanging_changes' `repos` list variable with a list of the repos to update.
    - These should be fully scoped, such as `qt/qtbase` or `qt-extensions/qtquickcalendar`
4. run `node warn_hanging_changes.js`

### Note:
The script does not retry failed requests. Be sure to read the log for any issues and take
action on failed changes manually. Failures may occur if the gerrit server is busy and responds
with a 500 error.
