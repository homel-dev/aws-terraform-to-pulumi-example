"""Synthetic POC fixture; replace when the real customer app is available."""

import os
import socket
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        status = 200
        message = b"myorg-poc-ok\n"

        if self.path == "/db":
            endpoint = os.environ.get("MYORG_DB_ENDPOINT", "")
            try:
                host, port = endpoint.rsplit(":", 1)
                with socket.create_connection((host, int(port)), timeout=3):
                    pass  # TCP reachability, NOT authentication or SQL readiness
                message = b"database-tcp-ok\n"
            except (ValueError, OSError):
                status, message = 503, b"database-unreachable\n"
        elif self.path == "/dependency":
            try:
                with urllib.request.urlopen(
                    os.environ["MYORG_RUNTIME_HTTPS_URL"], timeout=5
                ) as response:
                    if response.status >= 400:
                        raise OSError("dependency HTTP failure")
                message = b"dependency-ok\n"
            except (KeyError, OSError, ValueError):
                status, message = 503, b"dependency-unreachable\n"
        elif self.path != "/":
            status, message = 404, b"not-found\n"

        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(message)))
        self.end_headers()
        self.wfile.write(message)

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", int(os.environ["MYORG_APP_PORT"])), Handler).serve_forever()
