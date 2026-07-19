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
- `trails.config.json` — curated nearby-hikes list (hand-edited).
- `trails.json` — **generated** from the config by `build-trails.py`; committed
  and precached. Do not hand-edit.
- `robots.txt`, `sitemap.xml`, `site.webmanifest` — SEO + PWA (see SEO section).
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

## Nearby trails (build-trails.py / .sh)

The "Trails Nearby" home-page section renders an **offline inline-SVG map** of
trailheads along the Gunflint Trail + a card per trail (distance, elevation gain,
elevation sparkline), all from a committed, precached `trails.json`. Renderer JS
lives inline in `index.html` (last `<script>` before the SW script); CSS is the
`.trails-*` / `.trail-*` block.

The cabin's "you are here" marker comes from the `home` object in
`trails.config.json` (name + lat/lon, hardcoded — geocoded once from the site's
Google Maps link). It's drawn as a distinct rust-colored house pin, folded into
the marker collision-spread, with its label auto-placed on the open side.

Pipeline: edit `trails.config.json` → run `./build-trails.sh` (needs network).
`build-trails.py`:
- pulls all trail geometry + the CR-12 road spine in **one** Overpass query
  (per-trail queries got rate-limited/429'd — keep it combined),
- clips geometry to the config bbox so long thru-hikes don't blow out the map,
- uses the OSM `distance` tag for relations (else measures geometry),
- samples elevation via open-elevation (batch) with USGS EPQS fallback.

Desktop: two-column layout (scrollable compact list left, short 55% map right;
`--trails-map-h` drives both the map height and the list scroll box). Clicking a
trail path / marker / card opens Google Maps directions to the trailhead (wide
transparent `.trail-hit` lines make the thin paths clickable).

Trailheads >3 km from the road get an `access` field (nearest road point);
the renderer draws a dashed connector so they don't float (e.g. Eagle Mountain,
reached by forest road). Note: OSM's trail endpoint may be the *summit*, not the
parking area — set a `trailhead` override in `trails.config.json` when needed
(Eagle Mountain uses one).

`build-trails.py` also injects a static, crawlable trail list into the
`<!--trails:start-->…<!--trails:end-->` block in `index.html` (SEO / no-JS
fallback; JS replaces it at runtime). `python3 build-trails.py --inject-only`
refreshes that block from `trails.json` with no network.

Gotchas:
- `trails.json` is precached — **bump `CACHE_VERSION` in `sw.js`** after
  regenerating it.
- Do NOT wire build-trails into the pre-commit hook or CI: it hits external APIs
  (Overpass + elevation) that are flaky. It's a manual, occasional build.
- OSM attribution (ODbL) in the section credit + `trails.json` must stay.
- SVG map projection is equirectangular (`lonScale = cos(midLat)`); markers get
  collision-spread so overlapping trailheads (Gunflint Lake cluster) stay legible.
- After editing the config, re-run the full build **and** re-inject the static
  list (the full build does both; `--inject-only` does just the injection).

## SEO / PWA

- `index.html` `<head>`: title, meta description, OG + Twitter, canonical, a
  JSON-LD `LodgingBusiness` + `WebSite` graph (name/address/geo/image), a
  `manifest` link, and a `preload` of `bg.webp` (LCP hero).
- `robots.txt` (allow all + sitemap), `sitemap.xml` (`/` and `/trailcam/` — bump
  `lastmod` on real changes), `site.webmanifest` (installable PWA).
- The Trails list is server-rendered as static HTML for crawlers (see above).
- Trail-cam page SEO (description/canonical/OG/manifest) lives in
  `build-trailcam.sh` — regenerate after changing it.

## build-trailcam.sh

Scans `trailcam/images/`, converts non-WebP → WebP (`cwebp`), regenerates
`trailcam/index.html`, and syncs the image list into `sw.js`. Bash 3.2-compatible
(macOS default). Also run in CI (`.github/workflows/build-trailcam.yml`). Run
after adding/removing trail-cam images.

## Local dev

`./dev.sh` → `http://localhost:8000`.
