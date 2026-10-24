#!/bin/bash
# yt-grid.sh — show YouTube results as a clean results page (yt-page.mjs): YouTube's layout without
# the chrome, with DeArrow thumbnails (community frame → random non-promo frame → YouTube's own,
# via lib-dearrow.sh), the like ratio, honest-title and content-farm tags.
#
# Usage:  yt-grid.sh --tsv FILE [--query "search terms"] [--note "7 Shorts hidden"] [--inline] [--no-open]
#   FILE = TAB cols: videoId num title channel views approval duration [age] [farm 0|1] [honest 0|1]
#   approval = integer percent liked, or "-"
#
# Default: write results.html (one self-contained file) and open it in the browser; the path is
# printed on stdout. --inline prints each thumbnail in the terminal instead (iTerm2 `imgcat`,
# kitty `kitten icat`, or `wezterm imgcat`).

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib-dearrow.sh"

TSV=""; MODE="html"; OPEN=1; QUERY=""; NOTE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tsv) TSV="$2"; shift 2;;
    --query) QUERY="$2"; shift 2;;
    --note) NOTE="$2"; shift 2;;
    --html) MODE="html"; shift;;
    --inline) MODE="inline"; shift;;
    --no-open) OPEN=0; shift;;
    *) echo "unknown arg: $1" >&2; exit 64;;
  esac
done
[[ -n "$TSV" && -f "$TSV" ]] || { echo "usage: yt-grid.sh --tsv FILE [--query Q] [--note N] [--inline] [--no-open]" >&2; exit 64; }

WORK="${YT_GRID_DIR:-${TMPDIR:-/tmp}/yt-grid}"
mkdir -p "$WORK"; rm -f "$WORK"/g-*.jpg 2>/dev/null || true

declare -a ROW THM
i=0
while IFS= read -r line || [[ -n "$line" ]]; do
  vid="${line%%$'\t'*}"
  [[ -z "$vid" || "$vid" == "videoId" ]] && continue
  i=$((i+1)); ROW[$i]="$line"; THM[$i]="$WORK/g-$i.jpg"
  duration="$(cut -f7 <<< "$line")"
  dearrow_thumb "$vid" "$(dur_to_sec "$duration")" "${THM[$i]}" >/dev/null 2>&1 &
done < "$TSV"
wait
n=$i
[[ "$n" -gt 0 ]] || { echo "no results" >&2; exit 1; }

if [[ "$MODE" == "inline" ]]; then
  if   command -v imgcat >/dev/null; then show() { imgcat --width 40 "$1"; }
  elif [[ -x "$HOME/.iterm2/imgcat" ]]; then show() { "$HOME/.iterm2/imgcat" --width 40 "$1"; }
  elif command -v kitten >/dev/null; then show() { kitten icat --align left "$1"; }
  elif command -v wezterm >/dev/null; then show() { wezterm imgcat --width 40 "$1"; }
  else echo "no inline image tool (imgcat / kitten icat / wezterm imgcat); drop --inline" >&2; exit 1; fi
  for ((j=1; j<=n; j++)); do
    IFS=$'\t' read -r _ num title channel views approval duration age _ <<< "${ROW[$j]}"
    [[ -s "${THM[$j]}" ]] && show "${THM[$j]}"
    printf '%s. %s\n   %s · %s views · %s%% liked · %s\n\n' "$num" "$title" "$channel" "$views" "$approval" "$duration"
  done
  exit 0
fi

MANIFEST="$WORK/manifest.tsv"; : > "$MANIFEST"
for ((j=1; j<=n; j++)); do printf '%s\t%s\n' "${THM[$j]}" "${ROW[$j]}" >> "$MANIFEST"; done
PAGE="$WORK/results.html"
node "$DIR/yt-page.mjs" --manifest "$MANIFEST" --out "$PAGE" --query "$QUERY" --note "$NOTE" >/dev/null || exit 1
echo "$PAGE"
if (( OPEN )); then
  if command -v open >/dev/null; then open "$PAGE"; elif command -v xdg-open >/dev/null; then xdg-open "$PAGE" >/dev/null 2>&1; fi
fi
