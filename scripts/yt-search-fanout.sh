#!/usr/bin/env bash
# yt-search-fanout.sh — Multi-order YouTube search with reupload de-duplication.
#
# Beats the black-box `order=relevance` ranker by issuing several passes over
# different sort orders and merging. Then collapses the flood's biggest source —
# reuploads — by grouping near-identical titles and keeping the EARLIEST upload
# (the original, not the thief). Finally drops blocklisted channels.
#
# Usage:  yt-search-fanout.sh "query" [--limit N] [--orders relevance,date,viewCount]
# Output: a single JSON {items:[...]} in the same shape as `youtube search-videos`,
#         deduped and blocklist-filtered, each item carrying its source order(s).
#
# Rationale for the default orders:
#   relevance — YouTube's guess (kept, but no longer the ONLY input)
#   date      — recency escape hatch; surfaces the good old/new video relevance buries
#   viewCount — popularity escape hatch; different long-tail than relevance

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLOCK="$SELF_DIR/yt-blocklist.sh"
export PATH="$SELF_DIR:$PATH"   # use the sibling `youtube` CLI

query="${1:?usage: yt-search-fanout.sh \"query\" [--limit N] [--orders a,b,c]}"; shift || true
limit=8
orders="relevance,date,viewCount"
while [ $# -gt 0 ]; do
  case "$1" in
    --limit)  limit="$2"; shift 2 ;;
    --orders) orders="$2"; shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

# --- Fan out over each order, tag every item with the order it came from ---
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
IFS=',' read -r -a order_arr <<< "$orders"
for o in "${order_arr[@]}"; do
  youtube search-videos "$query" --limit "$limit" --order "$o" 2>/dev/null \
    | jq -c --arg o "$o" '.items[]? | select(.id.videoId) | {order:$o, item:.}' >> "$tmp" || true
done

# --- Merge by videoId, collapse reuploads by normalized title, filter blocklist ---
# Normalized title = lowercased, punctuation/whitespace-stripped, first 60 chars.
# Within a title group we keep the earliest publishedAt = the original upload.
merged=$(jq -s -c '
  def norm(t): (t // "" | ascii_downcase | gsub("[^a-z0-9]"; "") | .[0:60]);
  # dedup by videoId first, remembering every order that surfaced it
  (reduce .[] as $r ({};
      ($r.item.id.videoId) as $v
      | .[$v] = ((.[$v] // {item:$r.item, orders:[]}) | .orders += [$r.order] | .item = $r.item)
   ))
  | [ .[] | .item + {sources: (.orders // [])} ]
  # collapse near-duplicate titles, keep earliest upload
  | group_by(norm(.snippet.title))
  | map( sort_by(.snippet.publishedAt) | .[0] + {dupes: (length - 1)} )
  | {items: .}
' "$tmp")

# --- Blocklist filter (drop items whose channelId or @handle is blocked) ---
# Collect candidate channel ids, ask the blocklist which are blocked, subtract.
cids=$(printf '%s' "$merged" | jq -r '.items[].snippet.channelId' | sort -u)
blocked=""
if [ -n "$cids" ]; then
  # shellcheck disable=SC2086
  blocked=$(bash "$BLOCK" filter $cids 2>/dev/null || true)
fi

if [ -n "$blocked" ]; then
  printf '%s' "$merged" | jq -c --argjson bl "$(printf '%s\n' "$blocked" | jq -R . | jq -s .)" \
    '.items |= map(select(.snippet.channelId as $c | ($bl | index($c)) | not))'
else
  printf '%s' "$merged"
fi
