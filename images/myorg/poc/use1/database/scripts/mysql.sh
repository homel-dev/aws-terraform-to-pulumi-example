#!/usr/bin/env bash
set -euo pipefail
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server jq awscli
sudo systemctl enable mysql
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*
