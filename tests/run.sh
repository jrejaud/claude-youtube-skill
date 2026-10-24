#!/usr/bin/env bash
# tests/run.sh — regression tests. Offline ones always run; pass --network for the live API ones.
# Exit 0 = all passed.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=1; }

# 1. A live stream's duration is "LIVE"; dur_to_sec must return 0, not crash the arithmetic (2026-10-24).
source "$ROOT/scripts/lib-dearrow.sh"
[[ "$(dur_to_sec LIVE 2>&1)" == "0" ]] && ok "dur_to_sec LIVE -> 0" || bad "dur_to_sec LIVE"
[[ "$(dur_to_sec 1:02:03)" == "3723" ]] && ok "dur_to_sec 1:02:03 -> 3723" || bad "dur_to_sec 1:02:03"
[[ "$(dur_to_sec -)" == "0" ]] && ok "dur_to_sec - -> 0" || bad "dur_to_sec -"

# 2. yt-page.mjs renders one card per row, the rating tier, the LIVE badge and the farm tag.
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
printf '\x89PNG\r\n\x1a\n' > "$T/t.png"
printf '%s\n' \
  "$T/t.png	aaaaaaaaaaa	1	Good video	Chan A	1.2M	96	5:21	2y	0	0" \
  "$T/t.png	bbbbbbbbbbb	2	Hated trailer	Chan B	7.4M	59	2:14	3d	0	1" \
  "$T/t.png	ccccccccccc	3	Live thing	Chan C	11M	-	LIVE	1d	1	0" > "$T/m.tsv"
node "$ROOT/scripts/yt-page.mjs" --manifest "$T/m.tsv" --out "$T/p.html" --query q >/dev/null
P="$(cat "$T/p.html")"
[[ "$(grep -o 'class="card"' <<< "$P" | wc -l | tr -d ' ')" == "3" ]] && ok "yt-page: 3 cards" || bad "yt-page card count"
grep -q 'rating poor"><b>59%' <<< "$P" && ok "yt-page: 59% is the poor tier" || bad "yt-page tier"
grep -q 'dur live">LIVE' <<< "$P" && ok "yt-page: LIVE badge" || bad "yt-page LIVE badge"
grep -q 'content farm' <<< "$P" && ok "yt-page: farm tag" || bad "yt-page farm tag"
grep -q 'honest title' <<< "$P" && ok "yt-page: honest-title tag" || bad "yt-page honest tag"

# 3. (network) yt-enrich.sh given all 24 ids as ONE argument (what zsh passes for ${IDS//,/ },
#    since it does not word-split): xargs -I capped the rebuilt command at 255 bytes and every call
#    failed with "command line cannot be assembled, too long" (2026-10-24).
if [[ "${1:-}" == "--network" ]]; then
  ids="dQw4w9WgXcQ jNQXAC9IVRw 9bZkp7q19f0 kJQP7kiw5Fk OPf0YbXqDm0 JGwWNGJdvx8 RgKAFK5djSk CevxZvSJLk8 fRh_vgS2dFE hT_nvWreIhg 09R8_2nJtjg YQHsXMglC9A pRpeEdMmmQ0 60ItHLz5WEA kffacxfA7G4 nfWlot6h_JM 2Vv-BfVoq4g lp-EO5I60KA SlPhMPnQ58k e-ORhEE9VVg uelHwf8o7_U ktvTqknDobU YykjpeuMNEk 3tmd-ClpJxA"
  out="$("$ROOT/scripts/yt-enrich.sh" "$ids" 2>&1)"
  ! grep -q 'cannot be assembled' <<< "$out" && ok "yt-enrich: 24 ids, no xargs error" || bad "yt-enrich xargs"
  [[ "$(grep -c '"likes"' <<< "$out")" -ge 20 ]] && ok "yt-enrich: ratings for 24 ids" || bad "yt-enrich output"
fi
exit $fail
