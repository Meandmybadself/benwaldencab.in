# Benwalden Cabin Website

A beautiful static webpage for the Benwalden cabin on the Gunflint Trail in Northern Minnesota.

https://benwaldencab.in

## Structure

- `index.html` — the main page (self-contained: inline CSS + JS).
- `trailcam/` — trail-camera photo gallery. **`trailcam/index.html` is generated** — edit `build-trailcam.sh`, not the HTML.
- `sw.js` — service worker (offline support + caching).
- `trails.config.json` / `trails.json` — curated nearby-hikes config and its generated data (see below).
- `bg.webp`, `looncallalert.mp3` — hero image and loon-call audio.

## Live data feeds

The page fetches these at runtime (all fail gracefully / hide their section if offline):

- `weather.benwaldencab.in/forecast` — Tempest weather station
- `birdweather.benwaldencab.in/…` — BirdNET Pi detections & species
- `admin.benwaldencab.in/api/public/businesses` — local businesses

## Offline & caching (service worker)

`sw.js` makes the site work fully offline while keeping online visitors current:

| Request type | Strategy | Behavior |
|---|---|---|
| HTML page navigations | network-first → cache | Latest when online, cached shell when offline |
| Live data feeds (above) | network-first → cache | Fresh when online, last-known data when offline |
| Static assets & fonts | stale-while-revalidate | Instant load, refreshed in the background |

On install it **precaches the app shell** — both pages, `bg.webp`, the audio, and every trail-cam image. Updates roll out automatically: the worker uses `skipWaiting` + `clients.claim`, and the page reloads once when an updated worker takes control.

**When you change the shell** (CSS, images, etc.), bump `CACHE_VERSION` in `sw.js` to purge old caches on the next visit. The trail-cam image list in `sw.js` is kept in sync automatically (see below).

## Building the trail-cam page

```sh
./build-trailcam.sh
```

Scans `trailcam/images/`, converts any non-WebP images to WebP (needs `cwebp`), regenerates `trailcam/index.html`, **and syncs the trail-cam image list into `sw.js`'s precache** (the block between the `trailcam-images:start` / `:end` markers — do not edit it by hand). Run it after adding or removing images. CI also runs it via `.github/workflows/build-trailcam.yml`.

## Nearby trails

The "Trails Nearby" section on the home page renders an offline SVG map of
trailheads along the Gunflint Trail plus a card per trail (distance, elevation
gain, and an elevation sparkline). It reads a committed, precached `trails.json`
— no runtime API calls.

The cabin itself is shown as a "you are here" marker, set by the `home` object
in `trails.config.json`.

Edit the curated list in **`trails.config.json`** (add/remove a trail, tweak a
blurb or difficulty, or move the cabin marker), then regenerate:

```sh
./build-trails.sh          # needs network + python3
```

This runs `build-trails.py`, which pulls each trail's path geometry from
**OpenStreetMap** (one combined Overpass query) and samples elevation from
open-elevation (USGS 3DEP / SRTM fallback), then writes `trails.json`. Long
thru-hikes (Border Route, Kekekabic) are clipped to the corridor bbox so the map
stays focused; their distances come from the official OSM `distance` tag.

Trail geometry is © OpenStreetMap contributors (ODbL) — the attribution line in
the section and `trails.json` must stay. `trails.json` is precached by the
service worker, so bump `CACHE_VERSION` in `sw.js` after regenerating it.

## Local development

```sh
./dev.sh   # serves on http://localhost:8000
```

Note: service workers only run on `https://` or `localhost` — use `localhost`, not the LAN IP, to test offline behavior.

## Deployment

Hosted on GitHub Pages (custom domain via `CNAME`). Pushing to `main` publishes.
