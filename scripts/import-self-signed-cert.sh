#!/usr/bin/env bash
set -euo pipefail

region="${1:-us-east-1}"
domain="${2:-poc.example.com}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

openssl req -x509 -newkey rsa:3072 -sha256 -days 30 -nodes \
  -subj "/CN=${domain}" \
  -keyout "${tmp}/key.pem" \
  -out "${tmp}/cert.pem" >/dev/null 2>&1

arn="$(aws acm import-certificate \
  --region "$region" \
  --certificate "fileb://${tmp}/cert.pem" \
  --private-key "fileb://${tmp}/key.pem" \
  --query CertificateArn --output text)"

printf '%s\n' "$arn"
