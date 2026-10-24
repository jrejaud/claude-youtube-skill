#!/usr/bin/env bash
# yt-enrich.sh — Fetch RYD (like/dislike) and DeArrow (honest titles) for YouTube video IDs
# Usage: yt-enrich.sh ID1 ID2 ID3 ...
# Output: JSON lines with {id, likes, dislikes, dearrow_title}

set -uo pipefail

if [ $# -eq 0 ]; then
  echo "Usage: yt-enrich.sh VIDEO_ID [VIDEO_ID ...]" >&2
  exit 1
fi

# Fetch RYD data in parallel
ryd_data=$(printf '%s\n' "$@" | xargs -P 10 -n 1 sh -c \
  'curl -s "https://returnyoutubedislikeapi.com/votes?videoId=$1" 2>/dev/null | jq -c "{id: .id, likes: .likes, dislikes: .dislikes}" 2>/dev/null || echo "{\"id\":\"$1\",\"likes\":null,\"dislikes\":null}"' _)

# Fetch DeArrow data in parallel
dearrow_data=$(printf '%s\n' "$@" | xargs -P 10 -n 1 sh -c \
  'title=$(curl -s "https://sponsor.ajay.app/api/branding?videoID=$1" 2>/dev/null | jq -r ".titles[]? | select(.original == false) | .title" 2>/dev/null | head -1); if [ -n "$title" ]; then echo "$1|$title"; fi' _)

# Merge: output RYD data with DeArrow titles appended
echo "$ryd_data" | while IFS= read -r line; do
  vid_id=$(echo "$line" | jq -r '.id // empty')
  [ -z "$vid_id" ] && continue
  # Check if there's a DeArrow title for this ID
  da_title=$(echo "$dearrow_data" | grep "^${vid_id}|" 2>/dev/null | head -1 | cut -d'|' -f2- || true)
  if [ -n "$da_title" ]; then
    echo "$line" | jq -c --arg t "$da_title" '. + {dearrow_title: $t}'
  else
    echo "$line" | jq -c '. + {dearrow_title: null}'
  fi
done
