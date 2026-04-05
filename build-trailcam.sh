#!/usr/bin/env bash
# Scans trailcam/images/ and regenerates trailcam/index.html.
# Run locally or via CI after adding images to the images directory.
# Compatible with bash 3.2+ (macOS default) and bash 5 (Linux/CI).
set -euo pipefail

IMAGES_DIR="trailcam/images"
OUTPUT="trailcam/index.html"

# ---------------------------------------------------------------------------
# Convert any non-webp images to webp, then remove the originals.
# Requires cwebp: brew install webp (macOS) / apt install webp (Linux/CI).
# ---------------------------------------------------------------------------
convert_to_webp() {
  if ! command -v cwebp &>/dev/null; then
    echo "Warning: cwebp not found — skipping WebP conversion." \
         "(Install: brew install webp  or  apt install webp)"
    return
  fi

  local converted=0
  while IFS= read -r -d '' src; do
    local dest="${src%.*}.webp"
    echo "  Converting: $(basename "$src") → $(basename "$dest")"
    if cwebp -q 82 -mt "$src" -o "$dest" 2>/dev/null; then
      rm "$src"
      converted=$((converted + 1))
    else
      echo "  Warning: conversion failed for $src — keeping original."
    fi
  done < <(
    find "$IMAGES_DIR" -maxdepth 1 -type f \
      \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" \) \
      -print0
  )

  [[ $converted -gt 0 ]] && echo "Converted $converted file(s) to WebP." || true
}

convert_to_webp

# Collect image files into array (bash 3.2-compatible, no mapfile)
images=()
while IFS= read -r -d '' file; do
  images+=("$file")
done < <(
  find "$IMAGES_DIR" -maxdepth 1 -type f \
    \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \
       -o -iname "*.webp" -o -iname "*.gif" \) \
    -print0 | sort -rz
)

image_count=${#images[@]}
echo "Found $image_count image(s). Writing $OUTPUT..."

# ---------------------------------------------------------------------------
# Helper: extract a human-readable date from common trail-cam filenames.
# Recognises patterns like 20240115_143022, IMG_20240115, 2024-01-15, etc.
# ---------------------------------------------------------------------------
format_date() {
  local name="$1"
  if [[ "$name" =~ ([0-9]{4})[_-]?([0-9]{2})[_-]?([0-9]{2}) ]]; then
    local y="${BASH_REMATCH[1]}" m="${BASH_REMATCH[2]}" d="${BASH_REMATCH[3]}"
    local months=("" Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)
    local idx=$((10#$m))
    echo "${months[$idx]} $((10#$d)), $y"
  fi
}

# ---------------------------------------------------------------------------
# Build grid items
# ---------------------------------------------------------------------------
grid_html=""
for filepath in ${images[@]+"${images[@]}"}; do
  filename=$(basename "$filepath")
  src="images/$filename"
  date_label=$(format_date "$filename")

  grid_html+="      <figure class=\"photo\" onclick=\"openLightbox(this)\" data-src=\"${src}\">"
  grid_html+="<img src=\"${src}\" alt=\"Trail camera${date_label:+ — $date_label}\" loading=\"lazy\">"
  if [[ -n "$date_label" ]]; then
    grid_html+="<figcaption>${date_label}</figcaption>"
  fi
  grid_html+="</figure>"$'\n'
done

# Pluralisation and empty-state
if [[ $image_count -eq 1 ]]; then
  capture_label="1 capture"
else
  capture_label="${image_count} captures"
fi

if [[ $image_count -eq 0 ]]; then
  main_content='  <p class="empty">No footage yet — check back soon.</p>'
else
  main_content="  <div class=\"grid\">"$'\n'"${grid_html}  </div>"
fi

# ---------------------------------------------------------------------------
# Write the full page (using printf to avoid heredoc escaping issues)
# ---------------------------------------------------------------------------
{
printf '%s\n' '<!DOCTYPE html>'
printf '%s\n' '<html lang="en">'
printf '%s\n' '<head>'
printf '%s\n' '  <meta charset="UTF-8">'
printf '%s\n' '  <meta name="viewport" content="width=device-width, initial-scale=1.0">'
printf '%s\n' '  <title>Trail Camera — Benwalden</title>'
printf '%s\n' '  <meta name="description" content="Trail camera footage from Benwalden cabin on the Gunflint Trail.">'
printf '%s\n' '  <meta name="theme-color" content="#80A6BC">'
printf '%s\n' '  <link rel="icon" type="image/webp" href="../bg.webp">'
printf '%s\n' '  <link rel="apple-touch-icon" href="../bg.webp">'
printf '%s\n' '  <link rel="stylesheet" type="text/css" href="https://cloud.typography.com/6984932/7080032/css/fonts.css">'
printf '%s\n' '  <link rel="preconnect" href="https://fonts.googleapis.com">'
printf '%s\n' '  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>'
printf '%s\n' '  <link href="https://fonts.googleapis.com/css2?family=Crimson+Text:wght@600;700&family=Work+Sans:wght@400;500&display=swap" rel="stylesheet">'
printf '%s\n' '  <style>'
printf '%s\n' '    *, *::before, *::after { margin: 0; padding: 0; box-sizing: border-box; }'
printf '%s\n' ''
printf '%s\n' '    body {'
printf '%s\n' '      background: #0f1318;'
printf '%s\n' '      color: #fff;'
printf '%s\n' '      font-family: "Ringside Narrow A", "Ringside Narrow B", "Work Sans", "Arial Narrow", Arial, sans-serif;'
printf '%s\n' '      -webkit-font-smoothing: antialiased;'
printf '%s\n' '      -moz-osx-font-smoothing: grayscale;'
printf '%s\n' '      min-height: 100vh;'
printf '%s\n' '    }'
printf '%s\n' ''
printf '%s\n' '    header {'
printf '%s\n' '      padding: 2.5rem 2rem 2rem;'
printf '%s\n' '      border-bottom: 1px solid rgba(255,255,255,0.08);'
printf '%s\n' '    }'
printf '%s\n' ''
printf '%s\n' '    .back-link {'
printf '%s\n' '      display: inline-flex;'
printf '%s\n' '      align-items: center;'
printf '%s\n' '      gap: 0.4rem;'
printf '%s\n' '      color: rgba(255,255,255,0.45);'
printf '%s\n' '      text-decoration: none;'
printf '%s\n' '      font-size: 0.75rem;'
printf '%s\n' '      text-transform: uppercase;'
printf '%s\n' '      letter-spacing: 0.1em;'
printf '%s\n' '      transition: color 0.2s;'
printf '%s\n' '      margin-bottom: 0.75rem;'
printf '%s\n' '    }'
printf '%s\n' '    .back-link:hover { color: #80A6BC; }'
printf '%s\n' '    .back-link svg { width: 14px; height: 14px; fill: currentColor; }'
printf '%s\n' ''
printf '%s\n' '    h1 {'
printf '%s\n' '      font-family: "Chronicle Display A", "Chronicle Display B", "Crimson Text", Georgia, serif;'
printf '%s\n' '      font-weight: 600;'
printf '%s\n' '      font-size: 2.25rem;'
printf '%s\n' '      line-height: 1;'
printf '%s\n' '      text-shadow: 1px 1px 3px rgba(0,0,0,0.5);'
printf '%s\n' '    }'
printf '%s\n' ''
printf '%s\n' '    .subtitle {'
printf '%s\n' '      font-size: 0.75rem;'
printf '%s\n' '      text-transform: uppercase;'
printf '%s\n' '      letter-spacing: 0.12em;'
printf '%s\n' '      color: #80A6BC;'
printf '%s\n' '      margin-top: 0.5rem;'
printf '%s\n' '    }'
printf '%s\n' ''
printf '%s\n' '    main { padding: 2rem; }'
printf '%s\n' ''
printf '%s\n' '    .grid {'
printf '%s\n' '      columns: 3 280px;'
printf '%s\n' '      column-gap: 1rem;'
printf '%s\n' '    }'
printf '%s\n' ''
printf '%s\n' '    .photo {'
printf '%s\n' '      break-inside: avoid;'
printf '%s\n' '      margin-bottom: 1rem;'
printf '%s\n' '      border-radius: 4px;'
printf '%s\n' '      overflow: hidden;'
printf '%s\n' '      background: #1c2028;'
printf '%s\n' '      cursor: pointer;'
printf '%s\n' '      transition: transform 0.2s ease, box-shadow 0.2s ease;'
printf '%s\n' '    }'
printf '%s\n' '    .photo:hover {'
printf '%s\n' '      transform: translateY(-2px);'
printf '%s\n' '      box-shadow: 0 8px 24px rgba(0,0,0,0.5);'
printf '%s\n' '    }'
printf '%s\n' '    .photo img { width: 100%; height: auto; display: block; }'
printf '%s\n' '    .photo figcaption {'
printf '%s\n' '      padding: 0.5rem 0.65rem;'
printf '%s\n' '      font-size: 0.7rem;'
printf '%s\n' '      text-transform: uppercase;'
printf '%s\n' '      letter-spacing: 0.08em;'
printf '%s\n' '      color: rgba(255,255,255,0.4);'
printf '%s\n' '    }'
printf '%s\n' ''
printf '%s\n' '    .empty {'
printf '%s\n' '      color: rgba(255,255,255,0.3);'
printf '%s\n' '      font-size: 0.9rem;'
printf '%s\n' '      text-transform: uppercase;'
printf '%s\n' '      letter-spacing: 0.1em;'
printf '%s\n' '      margin-top: 4rem;'
printf '%s\n' '      text-align: center;'
printf '%s\n' '    }'
printf '%s\n' ''
printf '%s\n' '    #lightbox {'
printf '%s\n' '      display: none;'
printf '%s\n' '      position: fixed;'
printf '%s\n' '      inset: 0;'
printf '%s\n' '      background: rgba(0,0,0,0.92);'
printf '%s\n' '      z-index: 100;'
printf '%s\n' '      align-items: center;'
printf '%s\n' '      justify-content: center;'
printf '%s\n' '      cursor: zoom-out;'
printf '%s\n' '    }'
printf '%s\n' '    #lightbox.open { display: flex; }'
printf '%s\n' '    #lightbox img {'
printf '%s\n' '      max-width: 92vw;'
printf '%s\n' '      max-height: 92vh;'
printf '%s\n' '      object-fit: contain;'
printf '%s\n' '      border-radius: 3px;'
printf '%s\n' '      box-shadow: 0 0 60px rgba(0,0,0,0.8);'
printf '%s\n' '      cursor: default;'
printf '%s\n' '    }'
printf '%s\n' '    #lightbox-close {'
printf '%s\n' '      position: absolute;'
printf '%s\n' '      top: 1.25rem; right: 1.5rem;'
printf '%s\n' '      background: none; border: none;'
printf '%s\n' '      color: rgba(255,255,255,0.5);'
printf '%s\n' '      font-size: 1.8rem;'
printf '%s\n' '      cursor: pointer;'
printf '%s\n' '      line-height: 1;'
printf '%s\n' '      transition: color 0.15s;'
printf '%s\n' '    }'
printf '%s\n' '    #lightbox-close:hover { color: #fff; }'
printf '%s\n' '    .lb-nav {'
printf '%s\n' '      position: absolute;'
printf '%s\n' '      top: 50%; transform: translateY(-50%);'
printf '%s\n' '      background: none; border: none;'
printf '%s\n' '      color: rgba(255,255,255,0.4);'
printf '%s\n' '      font-size: 2.5rem;'
printf '%s\n' '      cursor: pointer;'
printf '%s\n' '      padding: 0 1rem;'
printf '%s\n' '      transition: color 0.15s;'
printf '%s\n' '      line-height: 1;'
printf '%s\n' '    }'
printf '%s\n' '    .lb-nav:hover { color: #fff; }'
printf '%s\n' '    #lb-prev { left: 0; }'
printf '%s\n' '    #lb-next { right: 0; }'
printf '%s\n' ''
printf '%s\n' '    @media (max-width: 640px) {'
printf '%s\n' '      header { padding: 1.75rem 1.25rem 1.25rem; }'
printf '%s\n' '      main { padding: 1.25rem; }'
printf '%s\n' '      h1 { font-size: 1.8rem; }'
printf '%s\n' '      .grid { columns: 2 140px; column-gap: 0.6rem; }'
printf '%s\n' '      .photo { margin-bottom: 0.6rem; }'
printf '%s\n' '    }'
printf '%s\n' '  </style>'
printf '%s\n' '</head>'
printf '%s\n' '<body>'
printf '%s\n' ''
printf '%s\n' '<header>'
printf '%s\n' '  <a href="/" class="back-link">'
printf '%s\n' '    <svg viewBox="0 0 24 24"><path d="M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z"/></svg>'
printf '%s\n' '    Benwalden'
printf '%s\n' '  </a>'
printf '%s\n' '  <h1>Trail Camera</h1>'
printf '  <p class="subtitle">Gunflint Trail, Minnesota &nbsp;&middot;&nbsp; %s</p>\n' "$capture_label"
printf '%s\n' '</header>'
printf '%s\n' ''
printf '%s\n' '<main>'
printf '%s\n' "$main_content"
printf '%s\n' '</main>'
printf '%s\n' ''
printf '%s\n' '<div id="lightbox" role="dialog" aria-modal="true" aria-label="Photo viewer">'
printf '%s\n' '  <button id="lightbox-close" aria-label="Close">&times;</button>'
printf '%s\n' '  <button class="lb-nav" id="lb-prev" aria-label="Previous">&#8249;</button>'
printf '%s\n' '  <img id="lb-img" src="" alt="Trail camera capture">'
printf '%s\n' '  <button class="lb-nav" id="lb-next" aria-label="Next">&#8250;</button>'
printf '%s\n' '</div>'
printf '%s\n' ''
printf '%s\n' '<script>'
printf '%s\n' '  const lightbox = document.getElementById("lightbox");'
printf '%s\n' '  const lbImg    = document.getElementById("lb-img");'
printf '%s\n' '  const photos   = Array.from(document.querySelectorAll(".photo"));'
printf '%s\n' '  let current    = 0;'
printf '%s\n' ''
printf '%s\n' '  function openLightbox(el) {'
printf '%s\n' '    current = photos.indexOf(el);'
printf '%s\n' '    lbImg.src = el.dataset.src;'
printf '%s\n' '    lbImg.alt = el.querySelector("img").alt;'
printf '%s\n' '    lightbox.classList.add("open");'
printf '%s\n' '    document.body.style.overflow = "hidden";'
printf '%s\n' '  }'
printf '%s\n' ''
printf '%s\n' '  function closeLightbox() {'
printf '%s\n' '    lightbox.classList.remove("open");'
printf '%s\n' '    document.body.style.overflow = "";'
printf '%s\n' '    lbImg.src = "";'
printf '%s\n' '  }'
printf '%s\n' ''
printf '%s\n' '  function navigate(dir) {'
printf '%s\n' '    current = (current + dir + photos.length) % photos.length;'
printf '%s\n' '    const el = photos[current];'
printf '%s\n' '    lbImg.src = el.dataset.src;'
printf '%s\n' '    lbImg.alt = el.querySelector("img").alt;'
printf '%s\n' '  }'
printf '%s\n' ''
printf '%s\n' '  document.getElementById("lightbox-close").addEventListener("click", closeLightbox);'
printf '%s\n' '  document.getElementById("lb-prev").addEventListener("click", function(e) { e.stopPropagation(); navigate(-1); });'
printf '%s\n' '  document.getElementById("lb-next").addEventListener("click", function(e) { e.stopPropagation(); navigate(1); });'
printf '%s\n' '  lightbox.addEventListener("click", function(e) { if (e.target === lightbox) closeLightbox(); });'
printf '%s\n' ''
printf '%s\n' '  document.addEventListener("keydown", function(e) {'
printf '%s\n' '    if (!lightbox.classList.contains("open")) return;'
printf '%s\n' '    if (e.key === "Escape")     closeLightbox();'
printf '%s\n' '    if (e.key === "ArrowLeft")  navigate(-1);'
printf '%s\n' '    if (e.key === "ArrowRight") navigate(1);'
printf '%s\n' '  });'
printf '%s\n' '</script>'
printf '%s\n' ''
printf '%s\n' '</body>'
printf '%s\n' '</html>'
} > "$OUTPUT"

echo "Done. Wrote $OUTPUT"
