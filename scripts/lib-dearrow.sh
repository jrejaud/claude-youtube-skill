#!/bin/bash
# lib-dearrow.sh — shared DeArrow thumbnail resolution, sourced by yt-thumbs.sh
# and yt-browse.sh. Mirrors the DeArrow extension's thumbnail logic:
#
#   1. Community thumbnail — if a crowdsourced frame exists, use it.
#   2. Random non-promo frame — otherwise generate a screenshot at a RANDOM
#      time, using SponsorBlock data so the time never lands inside a sponsor/
#      self-promo/intro/outro/etc. segment. (This is what DeArrow does instead
#      of falling back to the uploader's clickbait thumbnail.)
#   3. YouTube fallback — only if both above fail (e.g. generation errored).
#
# Functions: dearrow_thumb <videoId> <durationSeconds|0> <outPath>
#            dur_to_sec   "H:MM:SS" | "MM:SS" | "SS"  -> seconds
#
# Needs: curl, jq, awk. Talks to:
#   dearrow-thumb.ajay.app, sponsor.ajay.app, i.ytimg.com

# SponsorBlock categories to AVOID (URL-encoded JSON array):
# sponsor, selfpromo, interaction, intro, outro, preview, music_offtopic
DA_SB_CATS='%5B%22sponsor%22%2C%22selfpromo%22%2C%22interaction%22%2C%22intro%22%2C%22outro%22%2C%22preview%22%2C%22music_offtopic%22%5D'
DA_THUMB='https://dearrow-thumb.ajay.app/api/v1/getThumbnail'
DA_SB='https://sponsor.ajay.app/api/skipSegments'

# "23:52" / "1:02:03" / "92" -> integer seconds (0 on parse failure)
dur_to_sec() {
  local d="${1:-}"; [[ "$d" =~ ^[0-9:]+$ ]] || { echo 0; return; }   # "-", "LIVE", "" -> 0
  local IFS=:; read -ra p <<< "$d"
  case "${#p[@]}" in
    3) echo $(( 10#${p[0]}*3600 + 10#${p[1]}*60 + 10#${p[2]} ));;
    2) echo $(( 10#${p[0]}*60 + 10#${p[1]} ));;
    1) echo $(( 10#${p[0]} ));;
    *) echo 0;;
  esac
}

# Pick a random time in [5%,95%] of duration that avoids all promo segments.
# Args: durationSeconds  segmentsFile("start end" per line). Echoes integer secs.
_da_pick_time() {
  local dur="$1" segfile="$2"
  awk -v dur="$dur" -v seed="${RANDOM}${RANDOM}" '
    function within(t,   i){ for(i=1;i<=n;i++) if(t>=s[i]-2 && t<=e[i]+2) return 1; return 0 }
    BEGIN{ srand(seed); if(dur+0<=10) exit 1; lo=dur*0.05; hi=dur*0.95; if(hi<=lo){print int(dur/2); exit 0} }
    { s[NR]=$1+0; e[NR]=$2+0; n=NR }
    END{
      for(try=0; try<40; try++){ t=lo+rand()*(hi-lo); if(!within(t)){ printf "%.0f\n", t; exit 0 } }
      printf "%.0f\n", lo+rand()*(hi-lo)   # all attempts hit segments: take last anyway
    }' "$segfile"
}

# Resolve the best DeArrow thumbnail into <out>. Echoes the source kind to stderr
# (community | frame@Ns | yt-fallback). Returns 0 on success.
dearrow_thumb() {
  local vid="$1" dur="${2:-0}" out="$3"
  local code

  # 1) community thumbnail — ONLY if a real submission exists in the branding DB.
  # (getThumbnail with no time returns a server-auto-picked frame even when there
  # is NO submission, so we must gate on the branding API, not on that response.)
  local ncom
  ncom=$(curl -s "https://sponsor.ajay.app/api/branding?videoID=${vid}" 2>/dev/null | jq -r '.thumbnails | length' 2>/dev/null || echo 0)
  if [[ "$ncom" =~ ^[0-9]+$ && "$ncom" -gt 0 ]]; then
    code=$(curl -s -o "$out" -w '%{http_code}' "${DA_THUMB}?videoID=${vid}" 2>/dev/null || echo 000)
    if [[ "$code" == 200 && -s "$out" ]]; then echo "community" >&2; return 0; fi
  fi

  # 2) random non-promo frame
  local segfile sb
  segfile="$(mktemp "${TMPDIR:-/tmp}/da-seg.XXXXXX")"
  sb=$(curl -s "${DA_SB}?videoID=${vid}&categories=${DA_SB_CATS}" 2>/dev/null)
  if printf '%s' "$sb" | jq -e 'type=="array"' >/dev/null 2>&1; then
    printf '%s' "$sb" | jq -r '.[].segment | "\(.[0]) \(.[1])"' > "$segfile" 2>/dev/null
    # backfill duration from SponsorBlock if caller didn't supply one
    if awk -v d="$dur" 'BEGIN{exit !(d+0<=0)}'; then
      dur=$(printf '%s' "$sb" | jq -r '[.[].videoDuration] | max // 0' 2>/dev/null)
    fi
  else
    : > "$segfile"
  fi

  local t=""
  awk -v d="$dur" 'BEGIN{exit !(d+0>10)}' && t=$(_da_pick_time "$dur" "$segfile")
  rm -f "$segfile"

  if [[ -n "$t" ]]; then
    code=$(curl -s -o "$out" -w '%{http_code}' "${DA_THUMB}?videoID=${vid}&time=${t}&generateNow=true" 2>/dev/null || echo 000)
    if [[ "$code" == 200 && -s "$out" ]]; then echo "frame@${t}s" >&2; return 0; fi
  fi

  # 3) YouTube fallback — maxresdefault (1280x720) first, mqdefault (320px) only for
  # videos with no HD upload. -f makes the 404 fall through to the next size.
  local name
  for name in maxresdefault mqdefault; do
    if curl -sfL --max-time 15 -o "$out" "https://i.ytimg.com/vi/${vid}/${name}.jpg" 2>/dev/null && [[ -s "$out" ]]; then
      echo "yt-fallback:${name}" >&2; return 0
    fi
  done
  return 1
}
