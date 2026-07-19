#!/usr/bin/env python3
"""Build trails.json for the Gunflint Trail hikes section.

Reads trails.config.json, pulls each trail's path geometry from OpenStreetMap
(Overpass API), samples ground elevation along the path, computes distance and
elevation gain, and writes a compact trails.json that index.html renders
(offline, via the service-worker precache).

Usage:  ./build-trails.sh   (or  python3 build-trails.py)

Data:  Trail & road geometry (c) OpenStreetMap contributors, ODbL.
       Elevation from open-elevation (SRTM) with USGS 3DEP (EPQS) fallback.
"""

import functools
import json
import math
import re
import sys
import time
import urllib.error
import urllib.request

print = functools.partial(print, flush=True)  # noqa: A001 - unbuffered progress

CONFIG = "trails.config.json"
OUTPUT = "trails.json"
UA = "benwaldencab.in trail-build/1.0 (+https://benwaldencab.in)"

OVERPASS_ENDPOINTS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
]

ATTRIBUTION = (
    "Trail & road geometry © OpenStreetMap contributors (ODbL). "
    "Elevation: USGS 3DEP / SRTM."
)


# --------------------------------------------------------------------------
# HTTP helpers
# --------------------------------------------------------------------------
def _post(url, body, headers, timeout=180):
    req = urllib.request.Request(url, data=body.encode("utf-8"), headers=headers)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def _get(url, timeout=30):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def overpass(query):
    """Run an Overpass query, trying mirrors and backing off on failure."""
    last = None
    for endpoint in OVERPASS_ENDPOINTS:
        for attempt in range(4):
            try:
                raw = _post(
                    endpoint,
                    query,
                    {"Content-Type": "text/plain", "User-Agent": UA},
                    timeout=300,
                )
                return json.loads(raw)
            except (urllib.error.URLError, ValueError, TimeoutError) as exc:
                last = exc
                print(f"  overpass {endpoint} attempt {attempt + 1} failed: {exc}")
                time.sleep(5 * (attempt + 1))
    raise RuntimeError(f"Overpass unavailable: {last}")


# --------------------------------------------------------------------------
# Geometry helpers  (coords are [lat, lon])
# --------------------------------------------------------------------------
def haversine(a, b):
    """Great-circle distance between two [lat, lon] points, in meters."""
    r = 6371000.0
    lat1, lon1, lat2, lon2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    dlat, dlon = lat2 - lat1, lon2 - lon1
    h = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


def line_length(pts):
    return sum(haversine(pts[i], pts[i + 1]) for i in range(len(pts) - 1))


def simplify(pts, tol_m=15.0):
    """Douglas-Peucker simplification with a meters tolerance."""
    if len(pts) < 3:
        return pts[:]

    def perp(pt, a, b):
        # Approx planar perpendicular distance in meters.
        latf = 111320.0
        lonf = 111320.0 * math.cos(math.radians((a[0] + b[0]) / 2))
        ax, ay = a[1] * lonf, a[0] * latf
        bx, by = b[1] * lonf, b[0] * latf
        px, py = pt[1] * lonf, pt[0] * latf
        dx, dy = bx - ax, by - ay
        if dx == 0 and dy == 0:
            return math.hypot(px - ax, py - ay)
        t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)
        t = max(0.0, min(1.0, t))
        cx, cy = ax + t * dx, ay + t * dy
        return math.hypot(px - cx, py - cy)

    dmax, idx = 0.0, 0
    for i in range(1, len(pts) - 1):
        d = perp(pts[i], pts[0], pts[-1])
        if d > dmax:
            dmax, idx = d, i
    if dmax > tol_m:
        left = simplify(pts[: idx + 1], tol_m)
        right = simplify(pts[idx:], tol_m)
        return left[:-1] + right
    return [pts[0], pts[-1]]


def stitch(segments):
    """Greedily order segments into one continuous polyline by nearest endpoint."""
    if not segments:
        return []
    remaining = [list(s) for s in segments if len(s) >= 2]
    if not remaining:
        return []
    chain = remaining.pop(0)
    while remaining:
        tail = chain[-1]
        best_i, best_d, best_rev = None, float("inf"), False
        for i, seg in enumerate(remaining):
            d0 = haversine(tail, seg[0])
            d1 = haversine(tail, seg[-1])
            if d0 < best_d:
                best_i, best_d, best_rev = i, d0, False
            if d1 < best_d:
                best_i, best_d, best_rev = i, d1, True
        seg = remaining.pop(best_i)
        if best_rev:
            seg = seg[::-1]
        chain.extend(seg[1:] if best_d < 5 else seg)
    return chain


def resample(pts, n):
    """Resample a polyline to n points spaced evenly by distance."""
    if len(pts) <= 2 or n <= 2:
        return pts[:]
    total = line_length(pts)
    if total == 0:
        return pts[:]
    step = total / (n - 1)
    out = [pts[0]]
    acc, target = 0.0, step
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        seg = haversine(a, b)
        while seg > 0 and acc + seg >= target:
            frac = (target - acc) / seg
            out.append([a[0] + (b[0] - a[0]) * frac, a[1] + (b[1] - a[1]) * frac])
            target += step
        acc += seg
    if len(out) < n:
        out.append(pts[-1])
    return out[:n]


# --------------------------------------------------------------------------
# OSM extraction (one combined query for all trails + the road)
# --------------------------------------------------------------------------
def clip_bbox(seg, bbox):
    """Split a polyline into the sub-paths that fall inside bbox."""
    s, w, nth, e = bbox
    out, cur = [], []
    for p in seg:
        if s <= p[0] <= nth and w <= p[1] <= e:
            cur.append(p)
        elif len(cur) >= 2:
            out.append(cur)
            cur = []
        else:
            cur = []
    if len(cur) >= 2:
        out.append(cur)
    return out


def parse_distance_km(val):
    """Parse an OSM `distance` tag like '105 km' or '65 mi' into kilometers."""
    if not val:
        return None
    m = re.search(r"([\d.]+)\s*(km|mi|mile|miles)?", str(val))
    if not m:
        return None
    n = float(m.group(1))
    unit = (m.group(2) or "km").lower()
    return n * 1.60934 if unit.startswith("mi") else n


def fetch_all(cfg):
    """Fetch every trail's geometry and the road spine in a single request.

    Returns (by_name, dist_km, road):
      by_name  -> {osm_name: [segment, ...]}  (segments are lists of [lat,lon])
      dist_km  -> {osm_name: official route distance in km, if tagged}
      road     -> stitched, simplified [lat,lon] polyline of County Road 12
    """
    s, w, nth, e = cfg["bbox"]
    selectors = []
    for t in cfg["trails"]:
        nm = t.get("osm_name", t["name"]).replace('"', '\\"')
        kind = "relation" if t["kind"] == "relation" else "way"
        selectors.append(f'{kind}["name"="{nm}"]({s},{w},{nth},{e});')
    selectors.append(f'way["name"="Gunflint Trail"]["highway"]({s},{w},{nth},{e});')
    query = f'[out:json][timeout:300];({"".join(selectors)});out geom;'

    print("Fetching all trail + road geometry in one Overpass query...")
    data = overpass(query)

    by_name, dist_km, road_segs = {}, {}, []
    for el in data.get("elements", []):
        tags = el.get("tags", {})
        name = tags.get("name")
        if el["type"] == "relation":
            segs = [
                [[p["lat"], p["lon"]] for p in m["geometry"]]
                for m in el.get("members", [])
                if m.get("type") == "way" and "geometry" in m
            ]
            by_name.setdefault(name, []).extend(segs)
            d = parse_distance_km(tags.get("distance"))
            if d:
                dist_km[name] = d
        elif el["type"] == "way" and "geometry" in el:
            geom = [[p["lat"], p["lon"]] for p in el["geometry"]]
            if name == "Gunflint Trail" and tags.get("highway"):
                road_segs.append(geom)
            else:
                by_name.setdefault(name, []).append(geom)

    road = simplify(stitch(road_segs), tol_m=60.0)
    return by_name, dist_km, road


# --------------------------------------------------------------------------
# Elevation
# --------------------------------------------------------------------------
def elevations(points):
    """Return elevations (meters) for [lat, lon] points. Batch, with fallback."""
    try:
        return _open_elevation(points)
    except Exception as exc:  # noqa: BLE001 - fall back to USGS
        print(f"  open-elevation failed ({exc}); falling back to USGS EPQS...")
        return _epqs(points)


def _open_elevation(points, chunk=100):
    out = []
    for i in range(0, len(points), chunk):
        batch = points[i : i + chunk]
        body = json.dumps(
            {"locations": [{"latitude": p[0], "longitude": p[1]} for p in batch]}
        )
        raw = _post(
            "https://api.open-elevation.com/api/v1/lookup",
            body,
            {"Content-Type": "application/json", "User-Agent": UA},
            timeout=60,
        )
        res = json.loads(raw)["results"]
        out.extend(float(r["elevation"]) for r in res)
        time.sleep(1)
    return out


def _epqs(points):
    out = []
    for p in points:
        url = (
            "https://epqs.nationalmap.gov/v1/json?"
            f"x={p[1]}&y={p[0]}&units=Meters&wkid=4326&includeDate=false"
        )
        try:
            val = json.loads(_get(url, timeout=20)).get("value")
            out.append(float(val) if val not in (None, "") else out[-1] if out else 0.0)
        except Exception:  # noqa: BLE001
            out.append(out[-1] if out else 0.0)
        time.sleep(0.15)
    return out


def gain_ft(profile_m):
    total = 0.0
    for i in range(1, len(profile_m)):
        d = profile_m[i] - profile_m[i - 1]
        if d > 0:
            total += d
    return total * 3.28084


# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
def nearest_endpoint(chain, road):
    """Pick the chain endpoint closest to the road as the trailhead."""
    if not road:
        return chain[0]
    ends = [chain[0], chain[-1]]
    return min(ends, key=lambda pt: min(haversine(pt, r) for r in road))


def main():
    with open(CONFIG) as fh:
        cfg = json.load(fh)

    bbox = cfg["bbox"]
    n_samples = int(cfg.get("sample_points", 48))

    by_name, dist_km, road = fetch_all(cfg)
    print(f"  road: {len(road)} points")

    out_trails = []
    all_lat = [pt[0] for pt in road]
    all_lon = [pt[1] for pt in road]

    home = cfg.get("home")
    if home:
        all_lat.append(home["lat"])
        all_lon.append(home["lon"])

    for t in cfg["trails"]:
        osm_name = t.get("osm_name", t["name"])
        raw_segments = by_name.get(osm_name)
        if not raw_segments:
            print(f"WARNING: no geometry found for {t['name']} - skipping")
            continue
        print(f"Processing {t['name']} ({len(raw_segments)} segments)...")

        # Keep only the portions inside the corridor so long thru-hikes don't
        # blow out the map; short local trails are unaffected.
        segments = [c for s in raw_segments for c in clip_bbox(s, bbox)]
        if not segments:
            print(f"  WARNING: {t['name']} lies outside the corridor - skipping")
            continue

        # Distance: official route distance when tagged, else measured geometry.
        official = dist_km.get(osm_name)
        if official:
            distance_mi = round(official / 1.60934, 1)
        else:
            distance_mi = round(sum(line_length(s) for s in segments) / 1609.34, 1)

        chain = stitch(segments)
        trailhead = t.get("trailhead") or nearest_endpoint(chain, road)

        # If a trailhead sits far off the Gunflint Trail (reached by forest
        # road), record the nearest road point so the map can draw a dashed
        # "access" connector instead of leaving the trail floating.
        access = None
        if road:
            near = min(road, key=lambda r: haversine(trailhead, r))
            if haversine(trailhead, near) > 3000:
                access = [round(near[0], 5), round(near[1], 5)]

        sampled = resample(chain, n_samples)
        print(f"  sampling elevation at {len(sampled)} points...")
        elev_m = elevations(sampled)

        simplified = [simplify(s, tol_m=15.0) for s in segments]
        for s in simplified:
            for p in s:
                all_lat.append(p[0])
                all_lon.append(p[1])

        entry = {
            "name": t["name"],
            "difficulty": t.get("difficulty", ""),
            "blurb": t.get("blurb", ""),
            "distance_mi": distance_mi,
            "official_distance": bool(official),
            "gain_ft": int(round(gain_ft(elev_m))),
            "trailhead": [round(trailhead[0], 5), round(trailhead[1], 5)],
            "segments": [[[round(p[0], 5), round(p[1], 5)] for p in s] for s in simplified],
            "elevation": [int(round(e * 3.28084)) for e in elev_m],
        }
        if access:
            entry["access"] = access
        out_trails.append(entry)
        print(f"  {distance_mi} mi, +{out_trails[-1]['gain_ft']} ft" + ("  [access connector]" if access else ""))

    if not out_trails:
        raise RuntimeError("no trails produced - aborting without writing output")

    data = {
        "generated_from": CONFIG,
        "attribution": ATTRIBUTION,
        "bbox": [min(all_lat), min(all_lon), max(all_lat), max(all_lon)],
        "road": [[round(p[0], 5), round(p[1], 5)] for p in road],
        "trails": out_trails,
    }
    if home:
        data["home"] = {
            "name": home.get("name", "Benwalden"),
            "lat": round(float(home["lat"]), 5),
            "lon": round(float(home["lon"]), 5),
        }
    with open(OUTPUT, "w") as fh:
        json.dump(data, fh, separators=(",", ":"))
    print(f"\nWrote {OUTPUT}: {len(out_trails)} trails.")

    inject_static_list(out_trails)


# --------------------------------------------------------------------------
# Static, crawlable trail list injected into index.html (SEO + no-JS fallback)
# --------------------------------------------------------------------------
INDEX = "index.html"
LIST_START = "<!--trails:start-->"
LIST_END = "<!--trails:end-->"


def _esc(s):
    return (str(s or "").replace("&", "&amp;").replace("<", "&lt;")
            .replace(">", "&gt;").replace('"', "&quot;"))


def static_cards(trails):
    """Render the trail list as plain HTML (mirrors the JS-built cards)."""
    out = []
    for i, t in enumerate(trails):
        diff = t.get("difficulty", "")
        diff_html = (f'<span class="trail-diff diff-{_esc(diff.lower())}">{_esc(diff)}</span>'
                     if diff else "")
        meta = []
        if t.get("distance_mi"):
            meta.append(f'<span>{t["distance_mi"]} mi</span>')
        if t.get("gain_ft"):
            meta.append(f'<span>&uarr; {t["gain_ft"]:,} ft</span>')
        blurb = f'<p class="trail-blurb">{_esc(t.get("blurb", ""))}</p>' if t.get("blurb") else ""
        out.append(
            f'<article class="trail-card"><div class="trail-card-head">'
            f'<span class="trail-num">{i + 1}</span>'
            f'<h3 class="trail-name">{_esc(t["name"])}</h3>'
            f'<span class="trail-meta">{diff_html}{"".join(meta)}</span></div>'
            f'{blurb}</article>'
        )
    return "".join(out)


def inject_static_list(trails):
    """Rewrite the block between the trails markers in index.html."""
    try:
        with open(INDEX) as fh:
            html = fh.read()
    except FileNotFoundError:
        print(f"Note: {INDEX} not found - skipping static list injection.")
        return
    if LIST_START not in html or LIST_END not in html:
        print(f"Note: trails markers not found in {INDEX} - skipping.")
        return
    head, rest = html.split(LIST_START, 1)
    _, tail = rest.split(LIST_END, 1)
    html = head + LIST_START + static_cards(trails) + LIST_END + tail
    with open(INDEX, "w") as fh:
        fh.write(html)
    print(f"Injected {len(trails)} static trail cards into {INDEX}.")


if __name__ == "__main__":
    try:
        if "--inject-only" in sys.argv:
            with open(OUTPUT) as fh:
                inject_static_list(json.load(fh)["trails"])
        else:
            main()
    except Exception as exc:  # noqa: BLE001
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(1)
