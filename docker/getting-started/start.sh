#!/bin/bash
set -e

echo "🚀 Starting Tyk Self-Managed with Getting Started additions..."
docker compose -p tyk-getting-started -f ../self-managed/docker-compose.yml -f docker-compose.yml up -d

# bootstrap.hurl retries the Dashboard and Portal readiness endpoints, so no fixed sleep here.
echo "🛠️ Bootstrapping APIs and Portal..."
docker run --rm \
  --network tyk \
  -v "$(pwd)/bootstrap:/bootstrap" \
  -w /bootstrap \
  ghcr.io/orange-opensource/hurl:8.1.0 \
  --very-verbose --http1.1 --test --variables-file variables.env bootstrap.hurl

echo "✅ Getting Started environment is ready!"
