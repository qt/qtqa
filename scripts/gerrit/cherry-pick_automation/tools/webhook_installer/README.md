# Webhook installer

This script configures repositories in gerrit to send events
about changes to the Qt Cherry-pick bot.


## Usage
1. run `npm install` to configure dependencies
2. configure your gerrit username and password in config.json in this project's root directory
or via environment variables (same names as config.json)
3. Edit webhook_installer's `repos` list variable with a list of the repos to update.
    - These should be fully scoped, such as `qt/qtbase` or `qt-extensions/qtquickcalendar`
4. run `node webhook_installer.js`
    - By default, the script will submit the new configurations without review.
    - To run the installer without submitting changes, run `node webhook_installer.js nosubmit`

### Note:
The script does not retry failed requests. Be sure to read the log for any issues and take
action on failed changes manually. Failures may occur if the gerrit server is busy and responds
with a 500 error.
