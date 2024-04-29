# Binary size bot

The bot listens for Gerrit merges, receiving notifications via webhooks or directly via SSH client.
When a merge is detected, it triggers an artifact fetch from COIN. The bot then extracts
the artifact tarball and updates Influx databases with new file sizes. Files that can be monitored
are specified in the configuration file.
```
usage: main.py [-h] [--configuration FILE] [--ssh]

options:
  -h, --help            show this help message and exit
  --configuration FILE  load configuration from FILE (default: config.json)
  --ssh                 Listen gerrit SSH stream (.ssh/config credentials required)
```

## Configuration content:
```
{
    "tests_json": "qtlite_tests.json",  // Points to test set
    "email_info": {
        "smtp_server": "smtp.qt.io",
        "email_sender": "",
        "email_cc": ""
    },
    "gerrit_info": {
        "server_url": "codereview.qt-project.org",
        "server_port": 29418
    },
    "database_info": {
        "server_url": "https://testresults.qt.io/influxdb",
        "database_name": "",
        "username": "",
        "password": ""
    },
    "webhook_server_info": {
        "port": 8088
    }
}

```

## Test set content:
```
{
   "branch": "dev",  // Monitored branch
   "integration": "qt/qtdeclarative", // Monitored project
   "series": "qtlite_binary_size", // influxdb series
   "coin_id": "debian-11.6-static-qtlite-arm64", // Monitored build type
   "builds_to_check" : [
      {
         "name": "qt/qtdeclarative",  // Artifact file
         "size_comparision": [
            {
               "file": "bin/qml",  // File inside artifact
               "threshold": 0.05
            }
         ]
      }
   ]
}
```


## Exclusions
Excluded rules:

Excluded file patterns:


## Installation
To install this script as a service

Modify config.json with your credentials
Copy the service file to the systemd directory of your choice such as /etc/systemd/system/.
Reload the daemon with systemctl daemon-reload.
Start the service.


## Prerequsites

The included systemd service file assumes you have pipenv installed for the qt user.
You must manually install required packaged into the pipenv, as the service does not do this
automatically.
