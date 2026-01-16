#!/usr/bin/env bash
# Rotate/rasterize a simple arrow with tight crop and day/night modes; optional one-shot GIF
#
# Usage examples:
#   $0 -a 90 -o out.png -s 256 -m day
#   $0 --angle 270 --output spin.gif --size 192 --mode night --scale 1.2
#
# Defaults:
#   angle=0, output=arrow<angle>.png, size=128, mode=day, scale=1
#
# Behavior:
#   - If output ends with .gif, generates an animated GIF from 0° to <angle>, plays once (<=36 frames, ~1s).
#   - PNG: transparent background; arrow black (day) or white (night).
#   - GIF: solid background; day = black arrow on white bg; night = white arrow on black bg.
#   - Output is tightly cropped with minimal padding.
#   - All temp/raw files are removed automatically.

set -euo pipefail

# ---------- CLI parsing ----------
print_help() {
  cat <<EOF
Usage: $0 [options]

Options:
  -a, --angle <deg>     Rotation angle in degrees (0° up; clockwise positive). Default: 0
  -o, --output <path>   Output file (.png or .gif). Default: arrow<angle>.png
  -s, --size <px>       Base raster size (trimmed afterward). Default: 128
  -m, --mode <name>     Color mode: day|night. Default: day
  -x, --scale <factor>  Scale factor applied before rotation. Default: 1
  -h, --help            Show this help

Examples:
  $0 -a 90 -o arrow90.png -s 256 -m night
  $0 --angle 270 --output spin.gif --size 192 --mode day --scale 1.2
EOF
}

ANGLE="0"
OUTPUT=""
SIZE="128"
MODE="day"
SCALE="1"

POSITIONAL=()
while (( "$#" )); do
  case "${1:-}" in
    -h|--help) print_help; exit 0 ;;
    -a|--angle) ANGLE="${2:-}"; shift 2 ;;
    --angle=*) ANGLE="${1#*=}"; shift ;;
    -o|--output) OUTPUT="${2:-}"; shift 2 ;;
    --output=*) OUTPUT="${1#*=}"; shift ;;
    -s|--size) SIZE="${2:-}"; shift 2 ;;
    --size=*) SIZE="${1#*=}"; shift ;;
    -m|--mode) MODE="${2:-}"; shift 2 ;;
    --mode=*) MODE="${1#*=}"; shift ;;
    -x|--scale) SCALE="${2:-}"; shift 2 ;;
    --scale=*) SCALE="${1#*=}"; shift ;;
    --) shift; break ;;
    -*) echo "Unknown option: $1" >&2; print_help; exit 2 ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done

# Positional fallback: 1 angle, 2 output, 3 size, 4 mode, 5 scale
if [ "${#POSITIONAL[@]}" -ge 1 ] && [ "$ANGLE" = "0" ]; then ANGLE="${POSITIONAL[0]}"; fi
if [ "${#POSITIONAL[@]}" -ge 2 ] && [ -z "$OUTPUT" ]; then OUTPUT="${POSITIONAL[1]}"; fi
if [ "${#POSITIONAL[@]}" -ge 3 ] && [ "$SIZE" = "128" ]; then SIZE="${POSITIONAL[2]}"; fi
if [ "${#POSITIONAL[@]}" -ge 4 ] && [ "$MODE" = "day" ]; then MODE="${POSITIONAL[3]}"; fi
if [ "${#POSITIONAL[@]}" -ge 5 ] && [ "$SCALE" = "1" ]; then SCALE="${POSITIONAL[4]}"; fi

if [ -z "$OUTPUT" ]; then OUTPUT="arrow${ANGLE}.png"; fi

# ---------- Validation ----------
num_re='^[-+]?[0-9]*\.?[0-9]+$'
int_re='^[1-9][0-9]*$'
printf '%s' "$ANGLE" | grep -Eq "$num_re" || { echo "Error: angle must be numeric" >&2; exit 2; }
printf '%s' "$SIZE"  | grep -Eq "$int_re" || { echo "Error: size must be positive integer" >&2; exit 2; }
printf '%s' "$SCALE" | grep -Eq '^[0-9]*\.?[0-9]+$' || { echo "Error: scale must be numeric" >&2; exit 2; }
case "$MODE" in day|night) ;; *) echo "Error: mode must be 'day' or 'night'"; exit 2;; esac

# ---------- Tools ----------
RSVG=$(command -v rsvg-convert || true)
if command -v magick >/dev/null 2>&1; then IMGMAGICK="magick"
elif command -v convert >/dev/null 2>&1; then IMGMAGICK="convert"
else IMGMAGICK=""; fi
[ -n "$RSVG" ] || [ -n "$IMGMAGICK" ] || { echo "Error: need rsvg-convert or ImageMagick" >&2; exit 3; }
[ -n "$IMGMAGICK" ] || echo "Note: ImageMagick not found; GIF/trim optimizations may be limited." >&2

# ---------- Temp management ----------
WORKDIR="$(mktemp -d)"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT INT TERM

# ---------- Geometry ----------
vb_x=0; vb_y=0; vb_w=512; vb_h=512
cx=256; cy=256

# ---------- Colors ----------
png_arrow_fill_day="#000"
png_arrow_fill_night="#fff"
gif_bg_day="#fff"
gif_bg_night="#000"
gif_arrow_day="#000"
gif_arrow_night="#fff"

# ---------- Arrow geometry ----------
make_arrow_geom() {
  local fill="$1"
  cat <<GEOM
  <path fill="${fill}" d="
    M224 384
    L224 208
    L160 208
    L256 96
    L352 208
    L288 208
    L288 384
    Z"/>
GEOM
}

# ---------- SVG builder ----------
make_svg() {
  local a="$1" s="$2" fill="$3"
  local transform="rotate(${a} ${cx} ${cy})"
  awk "BEGIN{exit !($s!=1)}" && \
    transform="translate(${cx},${cy}) scale(${s}) translate(-${cx},-${cy}) ${transform}"
  cat <<SVG
<svg xmlns="http://www.w3.org/2000/svg" viewBox="${vb_x} ${vb_y} ${vb_w} ${vb_h}">
  <g transform="${transform}">
$(make_arrow_geom "$fill")
  </g>
</svg>
SVG
}

# ---------- Helpers ----------
trim_and_pad() {
  local in="$1" out="$2" pad="${3:-2}" bgcol="${4:-none}" fuzz="${5:-1%}"
  if [ -z "$IMGMAGICK" ]; then mv "$in" "$out"; return 0; fi
  if [ "$bgcol" = "none" ]; then
    $IMGMAGICK "$in" -fuzz "$fuzz" -trim +repage -bordercolor none -border "$pad" "$out"
  else
    $IMGMAGICK "$in" -background "$bgcol" -alpha remove -alpha off \
      -fuzz "$fuzz" -trim +repage -bordercolor "$bgcol" -border "$pad" "$out"
  fi
}

rasterize_svg_to_png_rgba() {
  local svg="$1" out_png="$2" w="$3" h="$4"
  if [ -n "$RSVG" ]; then
    printf '%s' "$svg" | "$RSVG" -w "$w" -h "$h" -b none -o "$out_png"
  else
    printf '%s' "$svg" | $IMGMAGICK -size "${w}x${h}" svg:- -background none "$out_png"
  fi
}

# ---------- Output setup ----------
is_gif=0; [[ "$OUTPUT" =~ \.gif$ ]] && is_gif=1
if [ $is_gif -eq 1 ]; then
  if [ "$MODE" = "day" ]; then
    arrow_fill="$gif_arrow_day"; solid_bg="$gif_bg_day"
  else
    arrow_fill="$gif_arrow_night"; solid_bg="$gif_bg_night"
  fi
else
  solid_bg="none"
  if [ "$MODE" = "day" ]; then arrow_fill="$png_arrow_fill_day"
  else arrow_fill="$png_arrow_fill_night"; fi
fi

out_w="$SIZE"; out_h="$SIZE"

render_png_final() {
  local svg="$1" dest="$2"
  local tmp="$WORKDIR/raw.png"
  local trimmed="$WORKDIR/trimmed.png"
  rasterize_svg_to_png_rgba "$svg" "$tmp" "$out_w" "$out_h"
  trim_and_pad "$tmp" "$trimmed" 2 "none" "1%"
  mv "$trimmed" "$dest"
}

render_gif_frame_png() {
  local svg="$1" dest_png="$2" bgcol="$3"
  local tmp="$WORKDIR/frame.raw.png"
  rasterize_svg_to_png_rgba "$svg" "$tmp" "$out_w" "$out_h"
  if [ -n "$IMGMAGICK" ]; then
    $IMGMAGICK "$tmp" -background "$bgcol" -alpha remove -alpha off "$dest_png"
  else
    mv "$tmp" "$dest_png"
  fi
}

# ---------- Main ----------
if [ $is_gif -eq 1 ]; then
  [ -n "$IMGMAGICK" ] || { echo "ImageMagick required for GIF output" >&2; exit 3; }

  final=$(awk "BEGIN{printf \"%.6f\", $ANGLE}")
  abs_final=$(awk "BEGIN{printf \"%.6f\", ($final<0?-1*$final:$final)}")
  max_frames=36
  frames=$(awk -v a="$abs_final" -v m="$max_frames" 'BEGIN{ n=int(a/10)+1; if(n<2)n=2; if(n>m)n=m; print n }')
  step=$(awk -v f="$final" -v n="$frames" 'BEGIN{ if(n<=1){print 0}else{print f/(n-1)} }')

  total_ticks=100
  delay=$(awk -v t="$total_ticks" -v n="$frames" 'BEGIN{d=int(t/n); if(d<2)d=2; print d}')

  framedir="$(mktemp -d)"
  trap 'rm -rf "$WORKDIR" "$framedir"' EXIT INT TERM

  for i in $(seq 0 $((frames-1))); do
    a=$(awk -v s="$step" -v i="$i" 'BEGIN{printf "%.6f", s*i}')
    svg=$(make_svg "$a" "$SCALE" "$arrow_fill")
    f="$framedir/f$(printf "%03d" "$i").png"
    render_gif_frame_png "$svg" "$f" "$solid_bg"
  done

  for f in "$framedir"/f*.png; do
    trimmed="$WORKDIR/trim-$(basename "$f")"
    trim_and_pad "$f" "$trimmed" 2 "$solid_bg" "1%"
    mv "$trimmed" "$f"
  done

  $IMGMAGICK -delay "$delay" -loop 1 "$framedir"/f*.png -layers OptimizeFrame "$OUTPUT"
  echo "Wrote GIF: $OUTPUT (frames:${frames} ~1s, once-only, angle:${ANGLE} size:${SIZE} mode:${MODE} scale:${SCALE})"
  exit 0
fi

svg=$(make_svg "$ANGLE" "$SCALE" "$arrow_fill")
render_png_final "$svg" "$OUTPUT"
echo "Wrote: $OUTPUT (angle:${ANGLE} size:${SIZE} mode:${MODE} scale:${SCALE})"

# Debugging tip: If trim crops too much or leaves halos, tweak -fuzz (0%–3%) and padding (1–4px) in trim_and_pad.
