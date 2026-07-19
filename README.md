# Benwalden Cabin Website

A beautiful static webpage for the Benwalden cabin on the Gunflint Trail in Northern Minnesota.

https://benwaldencab.in

## Structure

- `index.html` — the main page (self-contained: inline CSS + JS).
- `trailcam/` — trail-camera photo gallery. **`trailcam/index.html` is generated** — edit `build-trailcam.sh`, not the HTML.
- `sw.js` — service worker (offline support + caching).
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

## Local development

```sh
./dev.sh   # serves on http://localhost:8000
```

Note: service workers only run on `https://` or `localhost` — use `localhost`, not the LAN IP, to test offline behavior.

## Deployment

Hosted on GitHub Pages (custom domain via `CNAME`). Pushing to `main` publishes.
