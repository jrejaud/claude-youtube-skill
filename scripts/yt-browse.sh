#!/bin/bash
# yt-browse.sh — interactive fzf thumbnail browser for YouTube results.
#
# A foreground picker (NOT the passive top pane): a scrollable list of results
# on the left, a big DeArrow thumbnail + full metadata in the fzf preview pane.
# Enter plays the highlighted video with mpv; Esc/Ctrl-C quits.
#
# Usage:
#   yt-browse.sh --tsv FILE     TAB cols: videoId num title channel views approval duration
#   yt-browse.sh ID ID ...      bare ids (no metadata)
#
# Internal:
#   yt-browse.sh __preview THUMB TITLE CHANNEL VIEWS APPROVAL DURATION
#     rendered by fzf for the highlighted row.
#
# Requires: fzf, mpv, ~/.iterm2/imgcat (iTerm2). DeArrow thumbnails via curl.

set -uo pipefail

IMGCAT="$HOME/.iterm2/imgcat"
WORKDIR="${TMPDIR:-/tmp}/yt-browse"
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# ---- preview subcommand (called by fzf, one row at a time) ------------------
if [[ "${1:-}" == "__preview" ]]; then
  thumb="${2:-}"; title="${3:-}"; channel="${4:-}"; views="${5:-}"; approval="${6:-}"; dur="${7:-}"
  cols="${FZF_PREVIEW_COLUMNS:-50}"
  if [[ -f "$thumb" && -x "$IMGCAT" ]]; then
    "$IMGCAT" --width "$cols" "$thumb" 2>/dev/null || true
  fi
  # rating word from approval%
  rate="—"
  if [[ "$approval" =~ ^[0-9]+$ ]]; then
    if   (( approval >= 90 )); then rate="GOOD ${approval}%"
    elif (( approval >= 75 )); then rate="MIXED ${approval}%"
    elif (( approval >= 50 )); then rate="POOR ${approval}%"
    else                            rate="TRASH ${approval}%"; fi
  fi
  printf '\n%s\n' "$title"
  printf '%s\n' "────────────────────────"
  printf 'Channel : %s\n' "$channel"
  printf 'Views   : %s\n' "$views"
  printf 'Rating  : %s\n' "$rate"
  printf 'Length  : %s\n' "$dur"
  exit 0
fi

# ---- main ------------------------------------------------------------------
command -v fzf >/dev/null || { echo "fzf not installed" >&2; exit 1; }
mkdir -p "$WORKDIR"
rm -f "$WORKDIR"/t-*.img 2>/dev/null || true

# Shared DeArrow resolution: community frame → random non-promo frame → YT fallback.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-dearrow.sh"

# Build the fzf input. Tab-delimited, 8 fields:
#   1 num  2 title  3 channel  4 views  5 rating%  6 duration  7 videoId  8 thumbpath
# fzf shows 1..6; preview uses 8 (thumb) + 2..6 (meta); selection yields 7.
INPUT="$WORKDIR/list.tsv"
: > "$INPUT"
i=0
if [[ "${1:-}" == "--tsv" ]]; then
  tsv="${2:?usage: yt-browse.sh --tsv FILE}"
  [[ -f "$tsv" ]] || { echo "no such tsv: $tsv" >&2; exit 1; }
  while IFS=$'\t' read -r vid num title channel views approval duration || [[ -n "$vid" ]]; do
    [[ -z "$vid" ]] && continue
    i=$((i+1)); [[ -z "$num" ]] && num="$i"
    thumb="$WORKDIR/t-${i}.img"; dearrow_thumb "$vid" "$(dur_to_sec "$duration")" "$thumb" >/dev/null 2>&1 || thumb=""
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$num" "$title" "$channel" "${views:-—}" "${approval:-—}" "${duration:-—}" "$vid" "$thumb" >> "$INPUT"
  done < "$tsv"
else
  [[ $# -gt 0 ]] || { echo "usage: yt-browse.sh --tsv FILE | yt-browse.sh ID ..." >&2; exit 64; }
  for vid in "$@"; do
    i=$((i+1))
    thumb="$WORKDIR/t-${i}.img"; dearrow_thumb "$vid" 0 "$thumb" >/dev/null 2>&1 || thumb=""
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$i" "$vid" "" "—" "—" "—" "$vid" "$thumb" >> "$INPUT"
  done
fi

[[ -s "$INPUT" ]] || { echo "no results to browse" >&2; exit 1; }

sel="$(fzf --delimiter='\t' --with-nth=1,2,3,4,5,6 \
  --ansi --no-hscroll --header='↑↓ browse · Enter ▶ play · Esc quit' \
  --preview="$SELF __preview {8} {2} {3} {4} {5} {6}" \
  --preview-window='up,72%,border-horizontal,wrap' \
  < "$INPUT")" || { echo "(cancelled)"; exit 0; }

vid="$(printf '%s' "$sel" | cut -f7)"
title="$(printf '%s' "$sel" | cut -f2)"
[[ -z "$vid" ]] && { echo "no selection" >&2; exit 0; }

echo "▶ playing: $title  (https://youtube.com/watch?v=$vid)"
nohup mpv "https://www.youtube.com/watch?v=$vid" >/dev/null 2>&1 &
