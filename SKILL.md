---
name: youtube-search
description: REQUIRED for all YouTube searches and video content analysis. Auto-activates when the user asks to find, search, look up, play, watch, summarize or fact-check YouTube videos, and whenever a youtube.com or youtu.be URL appears in the message for any purpose (a bare URL means "tell me about this"). Uses the bundled `youtube` CLI (Data API v3) for search and metadata, enriches every result with Return YouTube Dislike ratings, DeArrow de-clickbaited titles and a content-farm flag, uses `youtube-vision` (Gemini actually watches the video) for content questions, and mpv/yt-dlp for playback. Never use WebSearch or WebFetch for YouTube — youtube.com blocks them, and a fetched watch page is nav-menu boilerplate, not the video.
---

# YouTube Search

Every script lives in `scripts/` next to this file. Paths below are relative to the skill root
(`~/.claude/skills/youtube-search/` if installed there).

**Keys** — export them, or put them in `~/.config/claude-youtube/env` (override with `$YT_SKILL_ENV`):

| Var | Used by | Get it |
|---|---|---|
| `YOUTUBE_API_KEY` | `youtube`, `yt-search-fanout.sh`, `yt-slop.sh` | Google Cloud console → enable YouTube Data API v3 → API key (free, 10,000 units/day) |
| `GEMINI_API_KEY` | `youtube-vision` | https://aistudio.google.com/apikey |

Everything else (Return YouTube Dislike, DeArrow, SponsorBlock, YouTube's own frames) needs no key.

## Workflow (every search)

1. **Search with fan-out** — not one `order=relevance` call:
   ```bash
   scripts/yt-search-fanout.sh "the user's search terms" --limit 8
   ```
   Runs three passes (`relevance`, `date`, `viewCount`), merges by videoId, **collapses reuploads**
   (near-identical titles → keeps the earliest upload, i.e. the original, not the thief) and drops
   **blocklisted** channels. Output: `{items:[...]}` in the Data API's search shape, each item also
   carrying `sources` (which orders surfaced it) and `dupes` (reuploads collapsed).
2. **Enrich** — duration, views, ratings, honest titles:
   ```bash
   scripts/youtube videos ID1,ID2,ID3            # duration + views + likes, up to 50 ids, 1 quota unit
   scripts/yt-enrich.sh ID1 ID2 ID3              # JSONL {id, likes, dislikes, dearrow_title}
   ```
3. **Drop Shorts** — anything ≤ 60 s.
4. **Score the channels** for content farms:
   ```bash
   scripts/yt-slop.sh CHANNEL_ID [CHANNEL_ID ...]   # JSONL {channel_id, flag, reasons, ...}
   ```
5. **Show the results page. The page is the answer**, not a chat table: write a TSV
   (`videoId num title channel views approval duration age farm honest`; approval = integer
   percent liked or `-`; farm/honest = 1 or 0) and run
   ```bash
   scripts/yt-grid.sh --tsv results.tsv --query "lord of the rings" --note "8 results · Shorts hidden"
   scripts/yt-grid.sh --tsv results.tsv --inline   # thumbnails in the terminal instead (iTerm2 / kitty / WezTerm)
   ```
   It writes one self-contained page (`yt-page.mjs`) that looks like YouTube with the chrome
   stripped out: DeArrow thumbnails, duration badges, honest titles, a "NN% liked" pill per
   video, and 🏭 on content-farm channels. Then reply in the chat with a line or two: what was
   hidden or flagged, anything badly rated, "say a number to play it". Use the table below only
   where no browser is available.
   When the user picks one ("play 3"), use `scripts/yt-show <id>` (see Playback).
6. *(Opt-in, needs a real TTY + fzf)* `scripts/yt-browse.sh --tsv results.tsv` — fzf list on the
   left, DeArrow thumbnail + metadata preview on the right (iTerm2 `imgcat`), Enter plays it.
   TSV columns: `videoId num title channel views approval duration`.

## Result format

```
### YouTube Results: "<query>"

| # | Title | Channel | Views | Rating | Age | Length |
|---|-------|---------|-------|--------|-----|--------|
| 1 | Video Title Here | Channel Name | 58.5K | 💚 | 2mo | 9:59 |
| 2 | Another Video Title | Channel Name | 7.2K | 🟠 | 3mo | 9:47 |
| 3 | 5 SHOCKING Egypt Secrets | Daily Info Trend 🏭 | 890K | 💚 | 3d | 8:12 |
```

- **Title**: the DeArrow title if one exists, otherwise the original.
- **Rating**: `approval = likes / (likes + dislikes)` from Return YouTube Dislike. The median video
  sits around 98%, so the tiers are skewed: 💚 90%+ · 🟠 75–90 (controversial) · 🤮 50–75 · 💀 <50.
  No data → `—`.
- **🏭** appended to the Channel cell when `yt-slop.sh` flags it. Orthogonal to Rating: a farm can
  still score 💚, which is exactly why the flag exists.
- Views with K/M suffixes; Age relative (`2d`, `3w`, `2mo`, `1y`); Length `m:ss`/`h:mm:ss` from
  the ISO 8601 `contentDetails.duration`. Cap at 8 rows unless asked for more.

## Slop scoring (🏭 content-farm flag)

Flags channels that **behave** like farms (faceless, TTS, stolen footage, 100 uploads in 8 weeks) —
not "a machine was involved". Two rules, don't break them:

1. **Flag, never filter.** A false positive costs nothing; the video still shows, marked. Only the
   blocklist removes.
2. **A flag needs a behavioural CORE signal** — upload velocity, or a young channel with viral views
   and few subs (reupload laundering). Cosmetic AUX signals (no banner, templated name like
   "Daily Facts Hub", link-stuffed description, brand-new) only escalate a core signal; they never
   flag on their own. A small new legit channel is never flagged. Missing data → no flag.

Tuning knobs (velocity thresholds, `core>=2 OR (core>=1 AND aux>=2)`) are at the top of `yt-slop.sh`.
If a farm keeps slipping through, blocklist it rather than lowering thresholds globally.

## Blocklist (human-curated removal)

```bash
scripts/yt-blocklist.sh add <channelId|@handle> [reason]
scripts/yt-blocklist.sh list
scripts/yt-blocklist.sh check <channelId>          # exit 0 = blocked
```

File: `youtube-blocklist.txt` in the skill root (override `$YT_BLOCKLIST`). Starts empty. When the
user says "block that channel" / "never show me these again", `add` it. `yt-search-fanout.sh`
applies it automatically.

## DeArrow (honest titles and thumbnails)

DeArrow is a crowdsourced database of replacement titles and thumbnails for clickbait videos.

```bash
scripts/dearrow resolve <videoId>     # {videoId,title,thumbnailUrl,source}
scripts/dearrow title <videoId>       # replacement title, exit 1 = none
scripts/dearrow thumbnail <videoId> [--time N] [--generate] [--out FILE]
scripts/dearrow branding-hash <videoId> --only   # privacy-preserving hash-prefix lookup
```

Exit codes: `0` ok · `1` no DeArrow data · `2` bad usage · `3` network error. Most videos have no
submission — that's normal. `lib-dearrow.sh` resolves a thumbnail the way the extension does:
community frame → a generated frame at a random time that avoids SponsorBlock sponsor/intro/outro
segments → YouTube's own thumbnail as a last resort.

`scripts/yt-frames get <videoId>` fetches YouTube's own auto-extracted frames (~25/50/75% through,
~7 KB each, no key, no video download) — the cheapest "what does this video actually look like".
Uploads only; for a live broadcast `hq720_live.jpg` is the broadcaster's thumbnail, **not** a frame.

## Watching a video: `youtube-vision`

When the question is about what is *in* a video — summarize, fact-check, "what are the steps", or
a bare URL — let Gemini watch it (frames + audio). Transcripts are often disabled or garbage.

```bash
scripts/youtube-vision ask <url> "<specific question>"
scripts/youtube-vision summarize <url>
scripts/youtube-vision key-moments <url>      # [MM:SS] table of contents
```

Priority: `ask` → `summarize` → `key-moments` → `youtube video <id>` (metadata only) →
`youtube transcript <id>` (last resort). Model: `$YOUTUBE_VISION_MODEL`, default `gemini-2.5-flash`.

### Clickbait / claim verification

Run in parallel, then synthesise a verdict:
- `scripts/youtube engagement <id>` — like/view and comment rates with a qualitative band
- `scripts/youtube channel-details <channelId>` — subs, age, video count
- `scripts/youtube-vision ask <url> "Does this video actually demonstrate <claim>? Quote the claims made and say whether it shows proof."`

Then cross-check the extracted claims with normal web research (the topic is fair game for
WebSearch; only the video itself is not).

```
**Credibility check: <title>**
- Channel: <name> (<subs> subs, <n> videos)
- Engagement: <like/view ratio> — <assessment>
- Gemini verdict: <what it shows vs. what it claims>
- **Rating: LEGIT / SUSPICIOUS / BAIT**
```

Red flags: tiny channel + "WORLD FIRST"; like/view under 2% (normal 3–5%); Gemini says the claim is
never demonstrated; comments asking for proof; a 2-minute video for a full setup guide.

## Playback

```bash
scripts/yt-show <url|id>        # yt-dlp → local mp4 → mpv. No youtube.com page, no ads.
mpv --force-window=immediate --no-resume-playback --ytdl-format="best[height<=720]/best" "<url>"
mpv --no-video --ytdl-format="bestaudio/best" "<url>"      # background audio only
```

Run mpv in the background. Every `--ytdl-format` needs a `/best` fallback — bare `bestaudio` exits 2
on videos without a standalone audio stream. `--no-resume-playback` stops mpv silently resuming
mid-clip. Install `sponsorblock.lua` into mpv to auto-skip sponsor segments.

## CLI reference (`scripts/youtube`, read-only)

| Command | Purpose |
|---|---|
| `search-videos <q> [--limit N] [--order relevance\|date\|rating\|viewCount\|title] [--type video\|channel\|playlist]` | Search (100 quota units) |
| `search-videos <q> --event-type live\|completed\|upcoming` | Broadcasts actually on air — searching the word "live" returns ordinary uploads |
| `search-videos <q> [--duration short\|medium\|long] [--channel <id\|@handle>] [--published-after <RFC3339>] [--region CC] [--lang code]` | Other filters |
| `video <id-or-url>` / `videos <id1,id2,...>` | Metadata; batch up to 50 |
| `channel <id\|@handle\|url>` / `channel-details <id>` / `channels <ids>` | Channel info |
| `channel-videos <id> [--limit N]` / `channel-playlists <id>` / `channel-latest <ids>` | Channel contents, last upload |
| `playlist <id>` / `playlist-items <id> [--limit N]` | Playlists |
| `comments <video-id> [--limit N] [--order time\|relevance] [--search T] [--lines]` | Comment threads |
| `search-comments <q> [--videos N] [--match T]` | Search videos, then pull their comments |
| `captions <id>` / `transcript <id> [--lang L]` | Caption tracks / text |
| `trending [--region CC]` / `categories` / `engagement <id>` | Misc |
| `raw <path> [-G --data-urlencode k=v ...]` | Raw GET, key auto-appended |

IDs accept raw ids, `watch?v=`, `youtu.be/`, `/shorts/`, `/channel/`, `/@handle` URLs and `@handle`.
Wrong guesses: it's `search-videos`, not `search`; `search-comments` filters with `--match`, not `--search`.

## Verification

```bash
scripts/youtube search-videos "rick astley never gonna give you up" --limit 1 | jq -e '.items[0].id.videoId' && echo SEARCH-OK
scripts/yt-search-fanout.sh "rick astley" --limit 3 | jq -e '.items | length > 0' && echo FANOUT-OK
scripts/yt-enrich.sh dQw4w9WgXcQ | jq -e '.likes > 0' && echo RYD-OK
scripts/dearrow hash dQw4w9WgXcQ | jq -e '.prefix == "5f6b"' && echo DEARROW-OK
scripts/yt-slop.sh UCuAXFkgsw1L7xaCfnd5JJOw | jq -e '.flag == false' && echo SLOP-OK
```

Pass criterion: all five `*-OK` lines print.
