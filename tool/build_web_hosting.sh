#!/usr/bin/env bash
# Release web build tuned for Firebase Hosting: bundle CanvasKit locally so
# cellular / strict networks are not blocked on gstatic, and silence wasm dry-run noise.
set -euo pipefail
cd "$(dirname "$0")/.."
flutter build web --release --no-web-resources-cdn --no-wasm-dry-run
echo "Output: build/web — deploy with: firebase deploy --only hosting"
