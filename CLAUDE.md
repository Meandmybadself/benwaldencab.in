# Benwalden Cabin — project notes

Static site for the Benwalden cabin, hosted on **GitHub Pages** (custom domain
`benwaldencab.in` via `CNAME`). No build step for the main page — `index.html`
is self-contained (inline CSS + JS). Pushing to `main` deploys.

## Layout

- `index.html` — main page. Fetches live data feeds at runtime; each section
  hides itself if its feed is unavailable.
- `trailcam/index.html` — **generated**. Do not edit directly; edit
  `build-trailcam.sh` and re-run it.
- `sw.js` — service worker (offline + caching).
- `bg.webp`, `looncallalert.mp3` — hero image, loon-call audio.

## Live data feeds (subdomains)

- `weather.benwaldencab.in/forecast` — Tempest weather station
- `birdweather.benwaldencab.in/{detections,species}` — BirdNET Pi via Birdweather
- `admin.benwaldencab.in/api/public/businesses` — local businesses

## Service worker (`sw.js`)

Registered from both `index.html` and the generated `trailcam/index.html`.

Routing:
- HTML navigations → **network-first** (fresh online, cached shell offline)
- The live feeds above (matched by hostname in `API_HOSTS`) → **network-first**
  (fresh online, last-known data offline)
- Everything else (assets, fonts, CSS) → **stale-while-revalidate**

Install precaches the app shell (`PRECACHE_URLS`), including every trail-cam
image. `skipWaiting` + `clients.claim` + a `controllerchange` reload in the page
push updates out on the next visit.

Gotchas:
- **Bump `CACHE_VERSION`** when the precached shell changes so old caches are
  purged on activation.
- The trail-cam image entries in `PRECACHE_URLS` live between the
  `trailcam-images:start` / `:end` markers and are **auto-generated** by
  `build-trailcam.sh`. Don't hand-edit them.
- Test offline behavior on `localhost` (or prod https) — service workers don't
  run over plain-http LAN IPs.

## build-trailcam.sh

Scans `trailcam/images/`, converts non-WebP → WebP (`cwebp`), regenerates
`trailcam/index.html`, and syncs the image list into `sw.js`. Bash 3.2-compatible
(macOS default). Also run in CI (`.github/workflows/build-trailcam.yml`). Run
after adding/removing trail-cam images.

## Local dev

`./dev.sh` → `http://localhost:8000`.
