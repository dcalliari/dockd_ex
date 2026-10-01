#!/usr/bin/env bash
# Gera os arquivos servidos em priv/static a partir das fontes SVG desta pasta.
# Requer rsvg-convert e ImageMagick (magick). Rode da raiz do repositório.
set -euo pipefail

src=design/assets/marca
out=priv/static
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cp "$src/favicon.svg" "$out/favicon.svg"

for px in 16 32 48; do
  rsvg-convert "$src/favicon.svg" -w "$px" -h "$px" -o "$tmp/$px.png"
done
magick "$tmp/16.png" "$tmp/32.png" "$tmp/48.png" "$out/favicon.ico"

rsvg-convert "$src/icone-app.svg" -w 180 -h 180 -o "$out/apple-touch-icon.png"
rsvg-convert "$src/favicon.svg" -w 192 -h 192 -o "$out/icon-192.png"
rsvg-convert "$src/favicon.svg" -w 512 -h 512 -o "$out/icon-512.png"
rsvg-convert "$src/icone-app.svg" -w 512 -h 512 -o "$out/icon-maskable-512.png"
rsvg-convert "$src/thumbnail.svg" -w 1200 -h 630 -o "$out/images/og.png"
