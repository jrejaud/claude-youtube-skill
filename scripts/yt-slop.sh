#!/usr/bin/env bash
# yt-slop.sh — Content-farm ("slop") scorer for YouTube CHANNELS.
#
# Flags AI/reupload content-FARMS by behavior, NOT by "was a machine involved."
# Good AI-made content has none of these signatures and will NOT be flagged.
#
# Design contract (see SKILL.md "Slop scoring"):
#   * The 🏭 flag REQUIRES a behavioral CORE signal (upload velocity or
#     view/sub laundering). Cosmetic AUX signals (no branding, templated name,
#     spammy description, brand-new) can only ESCALATE a core signal, never
#     trigger the flag alone. => a plain new small channel is NEVER flagged.
#   * This scores; it does not remove. False positives cost nothing — the video
#     still appears, just wearing 🏭. Only the blocklist removes (yt-blocklist.sh).
#   * Missing/private channel data => no flag (neutral). Never flag on absence.
#
# Usage:  yt-slop.sh CHANNEL_ID [CHANNEL_ID ...]
# Output: JSONL, one line per channel:
#   {channel_id,name,subs,age_days,vids,velocity,core,aux,score,flag,reasons}

set -uo pipefail
export PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd):$PATH"   # use the sibling `youtube` CLI

if [ $# -eq 0 ]; then
  echo "Usage: yt-slop.sh CHANNEL_ID [CHANNEL_ID ...]" >&2
  exit 1
fi

# Batch: /channels accepts up to 50 comma-separated ids in one call.
ids=$(printf '%s,' "$@" | sed 's/,$//')

youtube raw /channels \
  -G \
  --data-urlencode "part=snippet,statistics,brandingSettings" \
  --data-urlencode "id=${ids}" 2>/dev/null \
| jq -c '
  def num(x): (x // "0" | tostring | tonumber? // 0);
  .items[]?
  | .id as $cid
  | (.snippet.title // "?") as $name
  | num(.statistics.subscriberCount) as $subs
  | num(.statistics.videoCount)      as $vids
  | num(.statistics.viewCount)       as $views
  | ((now - ((.snippet.publishedAt // "1970-01-01T00:00:00Z") | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601)) / 86400) as $agedays
  | (($agedays / 7) | if . < 1 then 1 else . end) as $weeks
  | ($vids / $weeks) as $vel
  | (.snippet.description // "") as $desc
  | ([$desc | scan("https?://")] | length) as $urls
  | ([$desc | scan("#[A-Za-z0-9_]+")] | length) as $tags
  | ((.brandingSettings.image.bannerExternalUrl // "" | length) > 0) as $branded
  | ($agedays < 180) as $young
  | ($subs < 5000)   as $tiny
  # --- CORE (behavioral) signals: required for a flag ---
  | ([
      ( if   $vel > 10 and ($young or $tiny) then {c:3, r:"content-farm upload rate (\($vel|floor)/wk) on a young/low-sub channel"}
        elif $vel > 20                        then {c:2, r:"very high upload rate (\($vel|floor)/wk)"}
        elif $vel > 7  and ($young or $tiny)  then {c:2, r:"high upload rate (\($vel|floor)/wk) on a young/low-sub channel"}
        elif $vel > 5  and $young             then {c:1, r:"elevated upload rate (\($vel|floor)/wk) on a new channel"}
        else empty end ),
      ( if $young and $vids > 0 and ($views / $vids) > 100000 and $subs < 50000
        then {c:2, r:"young channel with viral views but few subs (reupload-laundering signature)"}
        else empty end )
    ]) as $core_sigs
  # --- AUX (cosmetic) signals: escalate only ---
  | ([
      ( if ($branded | not) then {a:1, r:"no channel branding/banner"} else empty end ),
      ( if ($name | test("(?i)(daily|facts|top ?[0-9]|shorts|viral|clips|hub|central|compilation|24 ?/ ?7|best of|mindblow|amazing)")) then {a:1, r:"templated/generic channel name"} else empty end ),
      ( if ($urls > 5 or $tags > 8) then {a:1, r:"link/hashtag-stuffed channel description"} else empty end ),
      ( if $agedays < 90 then {a:1, r:"very new channel (<90d)"} else empty end )
    ]) as $aux_sigs
  | ([$core_sigs[].c] | add // 0) as $core
  | ([$aux_sigs[].a] | add // 0) as $aux
  | {
      channel_id: $cid,
      name: $name,
      subs: $subs,
      age_days: ($agedays | floor),
      vids: $vids,
      velocity: (($vel * 10 | round) / 10),
      core: $core,
      aux: $aux,
      score: ($core + $aux),
      flag: (($core >= 2) or ($core >= 1 and $aux >= 2)),
      reasons: ([$core_sigs[].r] + [$aux_sigs[].r])
    }
'
