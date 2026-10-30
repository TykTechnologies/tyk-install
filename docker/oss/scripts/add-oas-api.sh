#!/usr/bin/env bash
# Turn one Tyk OAS document into the file pair the open source Gateway loads from apps/:
# <id>.json (generated classic wrapper, is_oas: true) and <id>-oas.json (your document).
# A bare OpenAPI file dropped into apps/ is not loaded, and the wrapper is not meant to be
# written by hand, so this runs a throwaway Gateway with apps/ mounted writable, posts the
# document to its Gateway API, and stops it. Then restart the real Gateway.
# Usage: scripts/add-oas-api.sh my-api.oas.json     (run from docker/oss; Redis must be up)
set -euo pipefail
cd "$(dirname "$0")/.."
DOC="${1:?usage: scripts/add-oas-api.sh <tyk-oas-document.json>}"
[ -f "${DOC}" ] || { echo "no such file: ${DOC}"; exit 1; }
[ "$(python3 -c 'import json,sys; print("x-tyk-api-gateway" in json.load(open(sys.argv[1])))' "${DOC}")" = "True" ] \
  || { echo "${DOC} has no x-tyk-api-gateway extension; a plain OpenAPI document is not a Tyk API definition"; exit 1; }

GATEWAY_VERSION="$(grep -E '^GATEWAY_VERSION=' .env 2>/dev/null | cut -d= -f2 || true)"
GATEWAY_VERSION="${GATEWAY_VERSION:-v5.16.0}"
SECRET="$(grep -E '^TYK_GW_SECRET=' confs/tyk.env | cut -d= -f2 | cut -d' ' -f1)"
NAME="tyk-oas-import-$$"

docker compose up -d tyk-redis >/dev/null
docker run -d --rm --name "${NAME}" --network tyk-oss -p 127.0.0.1::8080 \
  -v "$(pwd)/apps:/opt/tyk-gateway/apps" \
  -e TYK_GW_SECRET="${SECRET}" -e TYK_GW_STORAGE_TYPE=redis -e TYK_GW_STORAGE_ADDRS=tyk-redis:6379 \
  -e TYK_GW_USEDBAPPCONFIGS=false -e TYK_GW_APPPATH=/opt/tyk-gateway/apps \
  -e TYK_GW_POLICIES_POLICYSOURCE=file -e TYK_GW_POLICIES_POLICYRECORDNAME=/opt/tyk-gateway/policies/policies.json \
  -e TYK_GW_ALLOWINSECURECONFIGS=true -e TYK_GW_LOGLEVEL=error \
  "tykio/tyk-gateway:${GATEWAY_VERSION}" >/dev/null
trap 'docker stop "${NAME}" >/dev/null 2>&1 || true' EXIT
PORT="$(docker port "${NAME}" 8080/tcp | head -1 | sed 's/.*://')"
for _ in $(seq 1 30); do
  curl -sf "http://127.0.0.1:${PORT}/hello" >/dev/null && break
  sleep 2
done

RESP="$(curl -s -X POST "http://127.0.0.1:${PORT}/tyk/apis/oas" -H "x-tyk-authorization: ${SECRET}" \
  -H 'Content-Type: application/json' --data-binary "@${DOC}")"
ID="$(printf '%s' "${RESP}" | sed -n 's/.*"key":"\([^"]*\)".*/\1/p')"
[ -n "${ID}" ] || { echo "Gateway rejected the document: ${RESP}"; exit 1; }
curl -s "http://127.0.0.1:${PORT}/tyk/reload/group" -H "x-tyk-authorization: ${SECRET}" >/dev/null
for _ in $(seq 1 15); do
  [ -f "apps/${ID}.json" ] && [ -f "apps/${ID}-oas.json" ] && break
  sleep 1
done
[ -f "apps/${ID}.json" ] && [ -f "apps/${ID}-oas.json" ] || { echo "pair not written for ${ID}"; exit 1; }
echo "written: apps/${ID}.json apps/${ID}-oas.json"
echo "now: docker compose restart tyk-gateway"
