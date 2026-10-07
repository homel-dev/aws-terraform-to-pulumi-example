#!/usr/bin/env bash
set -euo pipefail

sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl jq awscli python3

sudo install -d -m 0755 /opt/myorg/runtime
sudo tee /usr/local/bin/myorg-poc-app >/dev/null <<'PYAPP'
#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"myorg-poc-ok\\n")

    def log_message(self, fmt, *args):
        pass

HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
PYAPP
sudo chmod 0755 /usr/local/bin/myorg-poc-app

sudo tee /etc/systemd/system/myorg-poc-app.service >/dev/null <<'UNIT'
[Unit]
Description=MyOrg POC application stand-in
After=network-online.target
Wants=network-online.target
ConditionPathExists=/opt/myorg/runtime/customer-module.bin

[Service]
Type=simple
ExecStart=/usr/local/bin/myorg-poc-app
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable myorg-poc-app.service
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*

# Deliberately do not fetch the external boot artifact here.
