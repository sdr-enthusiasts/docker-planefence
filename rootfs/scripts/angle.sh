#!/usr/bin/env bash
# angle.sh - rotate/rasterize a simple arrow, optional one-shot GIF, with angle label
# Usage:
#   ./angle.sh <degrees> [output] [size_px] [bg] [scale]
# Notes:
#   - If output ends with .gif, generates an animated GIF from 0° to <degrees>, plays once.
#   - Max 36 frames. Total duration ~1s.
#   - Prints the final angle (e.g., "350°") centered near the bottom.
#   - 0° points up; positive is clockwise (90° = right).

set -euo pipefail
angle="${1:-0}"
out="${2:-arrow${angle}.png}"
size="${3:-128}"
bg="${4:-none}"
scale="${5:-1}"

num_re='^[-+]?[0-9]*\.?[0-9]+$'
int_re='^[1-9][0-9]*$'
printf '%s' "$angle" | grep -Eq "$num_re" || { echo "Error: angle must be numeric" >&2; exit 2; }
printf '%s' "$size"  | grep -Eq "$int_re" || { echo "Error: size must be positive integer" >&2; exit 2; }
printf '%s' "$scale" | grep -Eq '^[0-9]*\.?[0-9]+$' || { echo "Error: scale must be numeric" >&2; exit 2; }

# Tools
RSVG=$(command -v rsvg-convert || true)
if command -v magick >/dev/null 2>&1; then IMGMAGICK="magick"
elif command -v convert >/dev/null 2>&1; then IMGMAGICK="convert"
else IMGMAGICK=""; fi
[ -n "$RSVG" ] || [ -n "$IMGMAGICK" ] || { echo "Error: need rsvg-convert or ImageMagick" >&2; exit 3; }

# Arrow geometry in square viewBox
vb_x=0; vb_y=0; vb_w=512; vb_h=512
cx=256; cy=256

# Angle text label (formatted once; numeric with degree sign)
angle_text="$(awk -v a="$angle" 'BEGIN{printf "%.0f", a}')°"

# Choose a readable font size relative to image; add bottom margin so text isn't clipped
# We extend the viewBox vertically by 18% for the text area.
text_band_frac=0.18
text_band_h=$(awk -v h="$vb_h" -v f="$text_band_frac" 'BEGIN{printf "%.0f", h*f}')
vb_h_ext=$((vb_h + text_band_h))
text_y=$(awk -v h="$vb_h" -v tb="$text_band_h" 'BEGIN{printf "%.0f", h + tb*0.78}') # baseline near bottom
font_size=$(awk -v h="$vb_h" 'BEGIN{printf "%.0f", h*0.14}') # ~14% of original box height

arrow_geometry=$(cat <<'GEOM'
  <path fill="#000" d="
    M224 384
    L224 208
    L160 208
    L256 96
    L352 208
    L288 208
    L288 384
    Z"/>
GEOM
)

make_svg() {
  local a="$1"
  local s="$2"
  local label="$3"
  local transform="rotate(${a} ${cx} ${cy})"
  awk "BEGIN{exit !($s!=1)}" && \
    transform="translate(${cx},${cy}) scale(${s}) translate(-${cx},-${cy}) ${transform}"
  cat <<SVG
<svg xmlns="http://www.w3.org/2000/svg" viewBox="${vb_x} ${vb_y} ${vb_w} ${vb_h_ext}">
  <g transform="${transform}">
${arrow_geometry}
  </g>
  <text x="${cx}" y="${text_y}" font-family="DejaVu Sans, Arial, Helvetica, sans-serif"
        font-size="${font_size}" text-anchor="middle" fill="#000">${label}</text>
</svg>
SVG
}

render_png() {
  local svg="$1" out_png="$2"
  if [ -n "$RSVG" ]; then
    if [ "$bg" = "none" ]; then
      printf '%s' "$svg" | "$RSVG" -w "$size" -h "$(awk -v s="$size" -v vh="$vb_h_ext" -v vw="$vb_w" 'BEGIN{printf "%.0f", s*vh/vw}')" -b none -o "$out_png"
    else
      local tmp="${out_png%.png}.tmp.png"
      printf '%s' "$svg" | "$RSVG" -w "$size" -h "$(awk -v s="$size" -v vh="$vb_h_ext" -v vw="$vb_w" 'BEGIN{printf "%.0f", s*vh/vw}')" -b none -o "$tmp"
      if [ -n "$IMGMAGICK" ]; then
        $IMGMAGICK "$tmp" -background "$bg" -alpha remove -alpha off "$out_png"
        rm -f "$tmp"
      else
        mv "$tmp" "$out_png"
      fi
    fi
  else
    # For IM, keep aspect by giving size WxH matching extended viewBox aspect
    local out_h; out_h=$(awk -v s="$size" -v vh="$vb_h_ext" -v vw="$vb_w" 'BEGIN{printf "%.0f", s*vh/vw}')
    if [ "$bg" = "none" ]; then
      printf '%s' "$svg" | $IMGMAGICK -size "${size}x${out_h}" svg:- -background none "$out_png"
    else
      printf '%s' "$svg" | $IMGMAGICK -size "${size}x${out_h}" svg:- -background "$bg" -alpha remove -alpha off "$out_png"
    fi
  fi
}

if [[ "$out" =~ \.gif$ ]]; then
  # Animation: 0° -> final angle, <=36 frames, ~1s total, play once
  final=$(awk "BEGIN{printf \"%.6f\", $angle}")
  abs_final=$(awk "BEGIN{printf \"%.6f\", ($final<0?-1*$final:$final)}")
  max_frames=36
  frames=$(awk -v a="$abs_final" -v m="$max_frames" 'BEGIN{ n=int(a/10)+1; if(n<2)n=2; if(n>m)n=m; print n }')
  step=$(awk -v f="$final" -v n="$frames" 'BEGIN{ if(n<=1){print 0}else{print f/(n-1)} }')

  total_ticks=100
  delay=$(awk -v t="$total_ticks" -v n="$frames" 'BEGIN{d=int(t/n); if(d<2)d=2; print d}')

  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' EXIT

  for i in $(seq 0 $((frames-1))); do
    a=$(awk -v s="$step" -v i="$i" 'BEGIN{printf "%.6f", s*i}')
    # Show live angle per frame (rounded)
    frame_label="$(awk -v ang="$a" 'BEGIN{printf "%.0f", ang}')°"
    svg=$(make_svg "$a" "$scale" "$frame_label")
    render_png "$svg" "$tmpdir/f$(printf "%03d" "$i").png"
  done

  if [ -n "$IMGMAGICK" ]; then
    # -loop 1: play once; stop on last frame
    if [ "$bg" = "none" ]; then
      $IMGMAGICK -delay "$delay" -loop 1 "$tmpdir"/f*.png -layers OptimizeFrame "$out"
    else
      $IMGMAGICK "$tmpdir"/f*.png -background "$bg" -alpha remove -alpha off \
        -delay "$delay" -loop 1 -layers OptimizeFrame "$out"
    fi
  else
    cp "$tmpdir/f000.png" "${out%.gif}.png"
    echo "Note: ImageMagick not found; wrote first frame PNG instead of GIF: ${out%.gif}.png"
    exit 0
  fi

  echo "Wrote GIF: $out (frames:${frames} ~1s, once-only, angle:${angle} size:${size} bg:${bg} scale:${scale})"
  exit 0
fi

# Single PNG: print final angle
svg=$(make_svg "$angle" "$scale" "$angle_text")
render_png "$svg" "$out"
echo "Wrote: $out (angle:${angle} size:${size} bg:${bg} scale:${scale})"
