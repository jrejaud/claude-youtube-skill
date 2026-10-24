#!/usr/bin/env bash
# yt-blocklist.sh — Human-curated channel blocklist for YouTube search.
#
# The negative-space version of an allowlist: starts empty, costs one line to
# append when you spot a garbage channel, never constrains discovery — it only
# subtracts KNOWN offenders. Automation (yt-slop.sh) only FLAGS; this is the
# only thing that REMOVES, and it removes exactly what you personally tell it to.
#
# Blocklist file: $YT_BLOCKLIST, default youtube-blocklist.txt in the skill root
#   One entry per line: a channelId (UC...) or a @handle. '#' starts a comment.
#   Trailing "  # reason" is allowed and ignored by matching.
#
# Usage:
#   yt-blocklist.sh add <channelId|@handle> [reason...]   append an offender
#   yt-blocklist.sh list                                  show current blocklist
#   yt-blocklist.sh check <channelId> [channelTitle]      exit 0 if blocked, 1 if not
#   yt-blocklist.sh filter <id> [<id> ...]                print only the BLOCKED ids
#
# Matching is by channelId (exact) or @handle (case-insensitive). channelTitle
# is accepted by `check` only for the human-readable message.

set -uo pipefail

BL="${YT_BLOCKLIST:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/youtube-blocklist.txt}"

ensure() { [ -f "$BL" ] || { mkdir -p "$(dirname "$BL")"; printf '# YouTube channel blocklist — one channelId (UC...) or @handle per line. "#" = comment.\n' > "$BL"; }; }

# Normalized, comment-stripped, non-empty entries (lowercased for @handle compare)
entries() { ensure; sed 's/#.*//' "$BL" | awk 'NF' | sed 's/[[:space:]]*$//'; }

is_blocked() { # $1 = channelId or @handle to test
  local needle="$1" e
  local low
  low=$(printf '%s' "$needle" | tr '[:upper:]' '[:lower:]')
  while IFS= read -r e; do
    [ -z "$e" ] && continue
    # exact channelId match
    [ "$e" = "$needle" ] && return 0
    # case-insensitive @handle match
    [ "$(printf '%s' "$e" | tr '[:upper:]' '[:lower:]')" = "$low" ] && return 0
  done < <(entries)
  return 1
}

cmd="${1:-}"; shift || true
case "$cmd" in
  add)
    ensure
    entry="${1:?usage: yt-blocklist.sh add <channelId|@handle> [reason]}"; shift || true
    reason="$*"
    if is_blocked "$entry"; then echo "already blocked: $entry" >&2; exit 0; fi
    if [ -n "$reason" ]; then printf '%s  # %s\n' "$entry" "$reason" >> "$BL"; else printf '%s\n' "$entry" >> "$BL"; fi
    echo "blocked: $entry${reason:+  ($reason)}"
    ;;
  list)
    ensure; cat "$BL"
    ;;
  check)
    id="${1:?usage: yt-blocklist.sh check <channelId> [channelTitle]}"
    title="${2:-}"
    if is_blocked "$id" || { [ -n "$title" ] && is_blocked "$title"; }; then
      echo "BLOCKED: ${title:-$id}" >&2; exit 0
    fi
    exit 1
    ;;
  filter)
    for id in "$@"; do is_blocked "$id" && printf '%s\n' "$id"; done
    exit 0
    ;;
  *)
    echo "usage: yt-blocklist.sh {add|list|check|filter} ..." >&2; exit 2
    ;;
esac
