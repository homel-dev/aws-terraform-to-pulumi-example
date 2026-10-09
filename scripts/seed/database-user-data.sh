#!/usr/bin/env bash
set -euo pipefail

# Ubuntu 24.04 LTS: mysql-server provides a real MySQL service.
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y mysql-server

# The seeded DB SG permits TCP/3306 from the application SG.
sed -i -E 's/^[[:space:]]*bind-address[[:space:]]*=.*/bind-address = 0.0.0.0/' \
  /etc/mysql/mysql.conf.d/mysqld.cnf
systemctl enable --now mysql
systemctl restart mysql
mysql --execute='CREATE DATABASE IF NOT EXISTS myorg_seed;'
