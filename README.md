# claude-youtube-skill

A [Claude Code](https://claude.com/claude-code) skill that lets an AI agent search YouTube properly:
no clickbait titles, a real like/dislike rating on every result, content-farm channels flagged,
reuploads collapsed back to the original, and an actual model watching the video when you ask what
is in it.

You say *"find me a good video on replacing a bike chain"*. The agent comes back with:

```
| # | Title                                   | Channel             | Views | Rating | Age | Length |
|---|-----------------------------------------|---------------------|-------|--------|-----|--------|
| 1 | How to replace a bike chain             | Park Tool           | 2.1M  | 💚     | 4y  | 9:12   |
| 2 | Chain replacement, quick-link method    | GCN Tech            | 640K  | 💚     | 2y  | 6:48   |
| 3 | 10 Bike Hacks Pros Don't Want You To Know | Daily Bike Facts 🏭 | 1.4M  | 🟠     | 3w  | 8:01   |
```

- **Title** — the [DeArrow](https://dearrow.ajay.app) community title when the uploader's is clickbait
- **Rating** — likes vs. dislikes from [Return YouTube Dislike](https://returnyoutubedislike.com)
- **🏭** — the channel behaves like a content farm (upload velocity, view laundering), flagged, never hidden
- Shorts dropped, reuploads collapsed to the earliest upload, your own channel blocklist applied

And for a link: *"is this video legit?"* → Gemini watches it (frames + audio) and says whether it
actually demonstrates what the title claims.

## Install

```bash
git clone https://github.com/jrejaud/claude-youtube-skill ~/.claude/skills/youtube-search
mkdir -p ~/.config/claude-youtube
cat > ~/.config/claude-youtube/env <<'EOF'
YOUTUBE_API_KEY=...   # Google Cloud console → YouTube Data API v3 → API key (free)
GEMINI_API_KEY=...    # https://aistudio.google.com/apikey (only for youtube-vision)
EOF
chmod 600 ~/.config/claude-youtube/env
```

Dependencies: `bash`, `curl`, `jq`, `node` (for `yt-frames`), plus `yt-dlp`, `ffmpeg` and `mpv` for
playback and `fzf` for the optional interactive picker.

Restart Claude Code. The skill triggers on its own whenever you mention YouTube or paste a link.

## What's inside

| Script | Does |
|---|---|
| `youtube` | Read-only YouTube Data API v3 CLI: search, videos, channels, playlists, comments, transcripts |
| `yt-search-fanout.sh` | Searches by relevance, date and view count, merges, collapses reuploads, applies the blocklist |
| `yt-enrich.sh` | Return YouTube Dislike counts + DeArrow titles, in parallel |
| `yt-slop.sh` | Content-farm scoring per channel. Flags on behaviour, never on "AI was involved" |
| `yt-blocklist.sh` | Your own channel blocklist — the only thing that removes results |
| `dearrow` | CLI for the DeArrow branding API, including the privacy-preserving hash-prefix lookup |
| `lib-dearrow.sh` | De-clickbaited thumbnails: community frame → random frame avoiding sponsor segments → original |
| `yt-frames` | YouTube's own auto-extracted frames, no key, no download |
| `youtube-vision` | Gemini watches the video: `ask`, `summarize`, `key-moments` |
| `yt-show` | Download with yt-dlp and play locally in mpv — no youtube.com, no ads |
| `yt-grid.sh` | Thumbnail grid of the results (DeArrow thumbnails): browser contact sheet, or inline in iTerm2/kitty/WezTerm |
| `yt-browse.sh` | fzf picker with thumbnail previews (iTerm2) |

`SKILL.md` is the part Claude reads: when to fire, the exact workflow, the result format, and a
verification block you can run to check your install.

## Notes

- Everything except search/metadata (YouTube API key) and video understanding (Gemini key) uses
  free, keyless community APIs.
- Search costs 100 quota units; the fan-out does three, so ~33 searches a day on the free 10,000.
- Personal use. Respect YouTube's terms and creators' rights.

MIT licensed.
