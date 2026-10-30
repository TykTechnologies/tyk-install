#!/usr/bin/env bash
# Five-minute proof of concept against the running OSS stack: one keyed Tyk OAS API,
# a key limited to 10 requests per minute, and the 429 that proves the limit.
# Usage: scripts/keyed-poc.sh            (run from docker/oss after `docker compose up -d`)
# Exits non-zero unless the Gateway answers, the keyless probe is refused, and
# twelve calls return ten 200s followed by two 429s.
set -euo pipefail
cd "$(dirname "$0")/.."

PORT="${GATEWAY_PORT:-$(grep -E '^GATEWAY_PORT=' .env 2>/dev/null | cut -d= -f2 || true)}"
PORT="${PORT:-8080}"
BASE="http://localhost:${PORT}"
SECRET="$(grep -E '^TYK_GW_SECRET=' confs/tyk.env | cut -d= -f2 | cut -d' ' -f1)"
AUTH="x-tyk-authorization: ${SECRET}"

for _ in $(seq 1 30); do
  curl -sf "${BASE}/hello" >/dev/null && break
  sleep 2
done
echo "gateway: $(curl -s "${BASE}/hello")"

code="$(curl -s -o /dev/null -w '%{http_code}' "${BASE}/httpbin-keyed/get")"
echo "keyed API without a key: ${code} (401 expected)"
[ "${code}" = "401" ]

# The key, the policy and the API must share the same org_id ("default" in this stack).
KEY="$(curl -sf -X POST "${BASE}/tyk/keys" -H "${AUTH}" -H 'Content-Type: application/json' \
  -d '{"org_id":"default","apply_policies":["httpbin-10rpm"]}' | sed -n 's/.*"key":"\([^"]*\)".*/\1/p')"
[ -n "${KEY}" ] || { echo "key creation failed"; exit 1; }
echo "key created from policy httpbin-10rpm (10 requests per minute)"

codes=""
for _ in $(seq 1 12); do
  codes="${codes}$(curl -s -o /dev/null -w '%{http_code} ' -H "Authorization: ${KEY}" "${BASE}/httpbin-keyed/get")"
done
echo "12 calls: ${codes}"
echo "13th call body: $(curl -s -H "Authorization: ${KEY}" "${BASE}/httpbin-keyed/get" | tr -d '\n')"
[ "${codes}" = "200 200 200 200 200 200 200 200 200 200 429 429 " ]
echo "ok: ten 200s then two 429s"
