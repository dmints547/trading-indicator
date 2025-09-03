#!/usr/bin/env bash
# Probe script for trading-indicator service endpoints (/ready and /ops/diagnostics).
# Usage:
#   BACKEND_URL=https://my-service.example.com KEY=$PROBE_API_KEY ./tools/check_ops_exposure.sh
# or
#   ./tools/check_ops_exposure.sh http://localhost:5000 my-local-api-key
set -euo pipefail

# Accept positional args for convenience
if [ "${4:-}" != "" ]; then
  HOST="$4"
else
  HOST="${BACKEND_URL:-http://localhost:5000}"
fi

if [ "${5:-}" != "" ]; then
  KEY="$5"
else
  KEY="${KEY:-${PROBE_API_KEY:-}}"
fi

TIMEOUT="${TIMEOUT:-6}"

echo "Probing host: $HOST"
echo

# Basic TCP port check (best-effort)
host_only="$(echo "$HOST" | sed -E 's#https?://##' | cut -d/ -f1)"
host_host="$(echo "$host_only" | cut -d: -f1)"
host_port="$(echo "$host_only" | sed -n 's/.*:\([0-9]\+\)/\1/p' || true)"
if [ -z "$host_port" ]; then
  if [[ "$HOST" == https:* ]]; then host_port=443; else host_port=80; fi
fi

if command -v nc >/dev/null 2>&1; then
  if (echo > /dev/tcp/"$host_host"/"$host_port") >/dev/null 2>&1; then
    echo "Port $host_port open on $host_host"
  else
    echo "Port $host_port closed/unreachable on $host_host"
  fi
else
  echo "nc not available; skipping TCP port check"
fi
echo

# helper to run a probe and print status + snippet of body
probe_path() {
  local path="$1"
  echo "==> GET ${HOST%/}${path} (no auth)"
  http_out="$(curl -sS -m "$TIMEOUT" -w "\n%{http_code}" -X GET "${HOST%/}${path}" 2>&1 || true)"
  body="$(echo "$http_out" | sed '$d')"
  code="$(echo "$http_out" | tail -n1)"
  echo "HTTP ${code}"
  echo "Body (first 1024 chars):"
  echo "${body:0:1024}"
  echo -e "\n---\n"

  if [ -n "$KEY" ]; then
    echo "==> GET ${HOST%/}${path} (with X-API-KEY header)"
    http_out="$(curl -sS -m "$TIMEOUT" -w "\n%{http_code}" -X GET -H "X-API-KEY: ${KEY}" "${HOST%/}${path}" 2>&1 || true)"
    body="$(echo "$http_out" | sed '$d')"
    code="$(echo "$http_out" | tail -n1)"
    echo "HTTP ${code}"
    echo "Body (first 1024 chars):"
    echo "${body:0:1024}"
    echo -e "\n---\n"

    echo "==> GET ${HOST%/}${path} (with wrong key 'badkey')"
    http_out="$(curl -sS -m "$TIMEOUT" -w "\n%{http_code}" -X GET -H "X-API-KEY: badkey" "${HOST%/}${path}" 2>&1 || true)"
    body="$(echo "$http_out" | sed '$d')"
    code="$(echo "$http_out" | tail -n1)"
    echo "HTTP ${code}"
    echo "Body (first 1024 chars):"
    echo "${body:0:1024}"
    echo -e "\n---\n"
  fi
}

probe_path "/ready"
probe_path "/ops/diagnostics"

echo "Probe finished."
echo "If /ops/diagnostics returns 200 without auth, consider rotating API_KEY immediately and blocking public access."
