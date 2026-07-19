#!/usr/bin/env bash
# Regenerates trails.json from trails.config.json by pulling trail geometry
# from OpenStreetMap and elevation from open-elevation / USGS. Requires network.
#
# Run after editing trails.config.json. Also syncs trails.json into the
# service-worker precache list (build-trailcam.sh owns the trailcam side).
set -euo pipefail
cd "$(dirname "$0")"

python3 build-trails.py

# Keep the service worker precaching trails.json for offline use.
SW="sw.js"
if [[ -f "$SW" ]] && ! grep -q "'/trails.json'" "$SW"; then
  echo "Note: add '/trails.json' to PRECACHE_URLS in $SW (see README)."
fi

echo "Done. Wrote trails.json"
