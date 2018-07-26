#!/bin/bash

# Run this script on the file server as root to enable automatic extraction of replicated coin build artifact packages.

sudo yum -y install incron
echo "QT" | sudo tee -a /etc/incron.allow
sudo incrontab -u QT incrontab.txt
