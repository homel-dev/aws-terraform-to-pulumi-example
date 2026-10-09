#!/bin/sh
set -eu

# Exactly the EC2 bootstrap boundary: fetch customer material at runtime,
# never during docker build and never push it to the image registry.
: "${ARTIFACT_URL:?ARTIFACT_URL is required}"
case "$ARTIFACT_URL" in
  https://*) ;;
  *) echo 'ARTIFACT_URL must use HTTPS' >&2; exit 2 ;;
esac

umask 077
tmpfile="$(mktemp /tmp/myorg-artifact.XXXXXX)"
trap 'rm -f "$tmpfile"' EXIT INT TERM
curl --fail --silent --show-error --location \
  --proto '=https' --proto-redir '=https' --tlsv1.2 \
  --connect-timeout 15 --max-time 120 \
  "$ARTIFACT_URL" --output "$tmpfile"

if [ -n "${ARTIFACT_SHA256:-}" ]; then
  printf '%s  %s\n' "$ARTIFACT_SHA256" "$tmpfile" | sha256sum -c -
fi

install -m 0400 "$tmpfile" /opt/myorg/runtime/customer-module.bin
rm -f "$tmpfile"
trap - EXIT INT TERM
exec python3 /opt/myorg/app.py
