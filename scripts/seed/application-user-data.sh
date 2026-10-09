#!/usr/bin/env bash
set -euo pipefail

# Synthetic HTTP application, not the real application package.
# The deploy script prepends SEED_DB_HOST, SEED_RUNTIME_URL and
# SEED_BOOTSTRAP_URL to the launch template user data.
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y python3 curl ca-certificates
install -d -m 0755 /opt/myorg-seed

if [[ -n "$SEED_BOOTSTRAP_URL" ]]; then
  # Deliberately download but never execute an unknown external artifact.
  curl --fail --show-error --silent --location --proto '=https' --tlsv1.2 \
    "$SEED_BOOTSTRAP_URL" -o /opt/myorg-seed/external-package
fi

cat > /opt/myorg-seed/application.py <<'PY'
import http.server
import os
import socket
import ssl
import urllib.parse


class Application(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/":
            body, status = "seed application is running\n", 200
        elif self.path == "/db":
            try:
                with socket.create_connection((os.environ["SEED_DB_HOST"], 3306), timeout=5):
                    pass
                body, status = "MySQL TCP/3306 reachable\n", 200
            except (OSError, TimeoutError) as exc:
                body, status = f"MySQL unreachable: {exc}\n", 503
        elif self.path == "/dependency":
            host = urllib.parse.urlparse(os.environ["SEED_RUNTIME_URL"]).hostname
            try:
                with socket.create_connection((host, 443), timeout=8) as sock:
                    with ssl.create_default_context().wrap_socket(sock, server_hostname=host):
                        pass
                body, status = "external HTTPS/TLS reachable\n", 200
            except (OSError, TimeoutError, ssl.SSLError) as exc:
                body, status = f"external HTTPS/TLS unreachable: {exc}\n", 503
        else:
            body, status = "not found\n", 404

        data = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


http.server.ThreadingHTTPServer(("0.0.0.0", 8080), Application).serve_forever()
PY

cat > /etc/systemd/system/myorg-seed-application.service <<'UNIT'
[Unit]
Description=Disposable MyOrg seed application
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/myorg-seed-application.env
ExecStart=/usr/bin/python3 /opt/myorg-seed/application.py
Restart=on-failure
User=nobody
Group=nogroup

[Install]
WantedBy=multi-user.target
UNIT

printf 'SEED_DB_HOST=%q\nSEED_RUNTIME_URL=%q\n' "$SEED_DB_HOST" "$SEED_RUNTIME_URL" \
  > /etc/myorg-seed-application.env
chmod 0600 /etc/myorg-seed-application.env
systemctl daemon-reload
systemctl enable --now myorg-seed-application.service
