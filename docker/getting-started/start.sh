#!/bin/bash
set -e

echo "🚀 Starting Tyk Self-Managed with Getting Started additions..."
docker compose -p tyk-getting-started -f ../self-managed/docker-compose.yml -f docker-compose.yml up -d

echo "⏳ Waiting for Tyk Dashboard to be ready..."
sleep 15

echo "🛠️ Bootstrapping APIs and Portal..."
docker run --rm \
  --network tyk \
  -v $(pwd)/bootstrap:/bootstrap \
  -w /bootstrap \
  ghcr.io/orange-opensource/hurl:latest \
  --very-verbose --http1.1 --test --variables-file variables.env bootstrap.hurl

echo "✅ Getting Started environment is ready!"
