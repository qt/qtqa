#!/usr/bin/env python3

# Convenience tool to get the JIRA tokens in place.
# This helps with the initial setup when connecting the bot for the first time.

# This is example code from Atlassian - https://bitbucket.org/atlassianlabs/atlassian-oauth-examples/
# The modified version for Python requests was copied from this fork:
# https://bitbucket.org/MicahCarrick/atlassian-oauth-examples/src/68d005311b9b74d6a85787bb87ccc948766486d3/python-requests/example.py?at=default&fileviewer=file-view-default

from oauthlib.oauth1 import SIGNATURE_RSA  # type: ignore
from requests_oauthlib import OAuth1Session  # type: ignore
from jira.client import JIRA  # type: ignore


def read(file_path: str) -> str:
    """ Read a file and return it's contents. """
    with open(file_path) as f:
        return f.read()


# The Consumer Key created while setting up the "Incoming Authentication" in
# JIRA for the Application Link.
CONSUMER_KEY = 'jira-gerrit-oauth'

# The contents of the rsa.pem file generated (the private RSA key)
RSA_KEY = read('jiracloser.pem')

# The URLs for the JIRA instance
JIRA_SERVER = 'https://bugreports-test.qt.io'
REQUEST_TOKEN_URL = JIRA_SERVER + '/plugins/servlet/oauth/request-token'
AUTHORIZE_URL = JIRA_SERVER + '/plugins/servlet/oauth/authorize'
ACCESS_TOKEN_URL = JIRA_SERVER + '/plugins/servlet/oauth/access-token'


# Step 1: Get a request token

oauth = OAuth1Session(CONSUMER_KEY, signature_type='auth_header',
                      signature_method=SIGNATURE_RSA, rsa_key=RSA_KEY)
request_token = oauth.fetch_request_token(REQUEST_TOKEN_URL)

print("STEP 1: GET REQUEST TOKEN")
print("  oauth_token={}".format(request_token['oauth_token']))
print("  oauth_token_secret={}".format(request_token['oauth_token_secret']))
print("\n")


# Step 2: Get the end-user's authorization

print("STEP2: AUTHORIZATION")
print("  Visit to the following URL to provide authorization:")
print("  {}?oauth_token={}".format(AUTHORIZE_URL, request_token['oauth_token']))
print("\n")

while input("Press any key to continue..."):
    pass


# Step 3: Get the access token

access_token = oauth.fetch_access_token(ACCESS_TOKEN_URL, verifier="some_verifier")

print("STEP2: GET ACCESS TOKEN")
print("  oauth_token={}".format(access_token['oauth_token']))
print("  oauth_token_secret={}".format(access_token['oauth_token_secret']))
print("\n")


# Now you can use the access tokens with the JIRA client. Hooray!

jira = JIRA(options={'server': JIRA_SERVER}, oauth={
    'access_token': access_token['oauth_token'],
    'access_token_secret': access_token['oauth_token_secret'],
    'consumer_key': CONSUMER_KEY,
    'key_cert': RSA_KEY
})

# print all of the project keys just as an example
print("Verifying that the access works, listing JIRA projects:")
for project in jira.projects():
    print(project.key)
