# Verify Branch Config

This script searches all repos with a name pattern and reports on any which do not have a
masterlike (`dev|master`) named branch. This script is read-only.

## Usage
1. run `npm install` to configure dependencies
2. configure your gerrit username and password in config.json in this project's root directory
or via environment variables (same names as config.json)
3. Edit verify_branch_config's `repos` list variable with a list of the repos to update.
    - These should be fully scoped, such as `qt/qtbase` or `qt-extensions/qtquickcalendar`
4. run `node verify_branch_config.js`

### Note:
The script does not retry failed requests. Failures may occur if the gerrit server is busy and responds
with a 500 error.
