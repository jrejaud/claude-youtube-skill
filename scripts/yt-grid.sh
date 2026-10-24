#!/bin/bash
# yt-grid.sh — show YouTube results as a thumbnail grid with DeArrow thumbnails
# (community frame → random non-promo frame → YouTube fallback, via lib-dearrow.sh).
#
# Usage:  yt-grid.sh --tsv FILE [--html | --inline] [--no-open]
#   FILE = TAB cols: videoId num title channel views approval duration [age]
#
# Output modes:
#   --html    (default) write a contact-sheet page and open it in the browser.
#             Each tile links to the video; the page path is printed on stdout.
#   --inline  print each thumbnail inline in the terminal (iTerm2 `imgcat`, kitty
#             `kitten icat`, or `wezterm imgcat`), caption underneath.

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib-dearrow.sh"

TSV=""; MODE="html"; OPEN=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tsv) TSV="$2"; shift 2;;
    --html) MODE="html"; shift;;
    --inline) MODE="inline"; shift;;
    --no-open) OPEN=0; shift;;
    *) echo "unknown arg: $1" >&2; exit 64;;
  esac
done
[[ -n "$TSV" && -f "$TSV" ]] || { echo "usage: yt-grid.sh --tsv FILE [--html|--inline] [--no-open]" >&2; exit 64; }

WORK="${YT_GRID_DIR:-${TMPDIR:-/tmp}/yt-grid}"
mkdir -p "$WORK"; rm -f "$WORK"/g-*.img 2>/dev/null || true

declare -a VID NUM TIT CHN VWS APR DUR AGE THM
i=0
while IFS=$'\t' read -r vid num title channel views approval duration age || [[ -n "$vid" ]]; do
  [[ -z "$vid" || "$vid" == "videoId" ]] && continue
  i=$((i+1))
  VID[$i]="$vid"; NUM[$i]="${num:-$i}"; TIT[$i]="$title"; CHN[$i]="$channel"
  VWS[$i]="$views"; APR[$i]="$approval"; DUR[$i]="$duration"; AGE[$i]="${age:-}"; THM[$i]="$WORK/g-$i.img"
  dearrow_thumb "$vid" "$(dur_to_sec "$duration")" "${THM[$i]}" >/dev/null 2>&1 &
done < "$TSV"
wait
n=$i
[[ "$n" -gt 0 ]] || { echo "no results" >&2; exit 1; }

# Same tiers as the results table: 💚 90+ · 🟠 75-90 · 🤮 50-75 · 💀 <50
rating_emoji() {
  local a="$1"
  [[ "$a" =~ ^[0-9]+$ ]] || { printf '—'; return; }
  if   (( a >= 90 )); then printf '💚'
  elif (( a >= 75 )); then printf '🟠'
  elif (( a >= 50 )); then printf '🤮'
  else                     printf '💀'
  fi
}
meta() { # $1 = index
  local j="$1" m
  m="$(rating_emoji "${APR[$j]}") ${CHN[$j]} · ${VWS[$j]}"
  [[ -n "${AGE[$j]}" ]] && m="$m · ${AGE[$j]}"
  printf '%s · %s' "$m" "${DUR[$j]}"
}

if [[ "$MODE" == "inline" ]]; then
  if   command -v imgcat >/dev/null; then show() { imgcat --width 40 "$1"; }
  elif [[ -x "$HOME/.iterm2/imgcat" ]]; then show() { "$HOME/.iterm2/imgcat" --width 40 "$1"; }
  elif command -v kitten >/dev/null; then show() { kitten icat --align left "$1"; }
  elif command -v wezterm >/dev/null; then show() { wezterm imgcat --width 40 "$1"; }
  else echo "no inline image tool (imgcat / kitten icat / wezterm imgcat); use --html" >&2; exit 1; fi
  for ((j=1; j<=n; j++)); do
    [[ -s "${THM[$j]}" ]] && show "${THM[$j]}"
    printf '%s. %s\n   %s\n\n' "${NUM[$j]}" "${TIT[$j]}" "$(meta "$j")"
  done
  exit 0
fi

esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' <<< "$1"; }
PAGE="$WORK/results.html"
{
  cat <<'HEAD'
<!doctype html><meta charset="utf-8"><title>YouTube results</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
:root{color-scheme:dark}body{margin:0;padding:20px;background:#111;color:#eee;font:15px/1.35 system-ui,sans-serif}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:18px}
a{color:inherit;text-decoration:none}.tile img{width:100%;aspect-ratio:16/9;object-fit:cover;border-radius:8px;background:#222}
.t{font-weight:600;margin-top:6px}.m{color:#aaa;font-size:13px;margin-top:2px}
</style><div class="grid">
HEAD
  for ((j=1; j<=n; j++)); do
    img=""; [[ -s "${THM[$j]}" ]] && img="g-$j.img"
    printf '<a class="tile" href="https://www.youtube.com/watch?v=%s"><img src="%s" alt=""><div class="t">%s. %s</div><div class="m">%s</div></a>\n' \
      "${VID[$j]}" "$img" "${NUM[$j]}" "$(esc "${TIT[$j]}")" "$(esc "$(meta "$j")")"
  done
  echo '</div>'
} > "$PAGE"
echo "$PAGE"
if (( OPEN )); then
  if command -v open >/dev/null; then open "$PAGE"; elif command -v xdg-open >/dev/null; then xdg-open "$PAGE" >/dev/null 2>&1; fi
fi
