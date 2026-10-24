# claude-youtube-skill

A [Claude Code](https://claude.com/claude-code) skill that lets an AI agent search YouTube properly:
no clickbait titles, a real like/dislike rating on every result, content-farm channels flagged,
reuploads collapsed back to the original, and an actual model watching the video when you ask what
is in it.

You say *"search youtube for lord of the rings"*. The agent comes back with this page (a real run):

![Results page for lord of the rings: DeArrow thumbnails, duration badges and a like-ratio pill on each video; the Rings of Power trailer shows 59% liked](docs/results-page.png)

- **Thumbnails and titles** — from [DeArrow](https://dearrow.ajay.app) when the uploader's are clickbait
- **"NN% liked"** — likes vs. dislikes from [Return YouTube Dislike](https://returnyoutubedislike.com)
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
| `yt-grid.sh` + `yt-page.mjs` | The results as a clean YouTube-style page: DeArrow thumbnails, like ratio, content-farm tags. Or inline thumbnails in iTerm2/kitty/WezTerm |
| `yt-browse.sh` | fzf picker with thumbnail previews (iTerm2) |

`SKILL.md` is the part Claude reads: when to fire, the exact workflow, the result format, and a
verification block you can run to check your install.

## Notes

- Everything except search/metadata (YouTube API key) and video understanding (Gemini key) uses
  free, keyless community APIs.
- Search costs 100 quota units; the fan-out does three, so ~33 searches a day on the free 10,000.
- Personal use. Respect YouTube's terms and creators' rights.

MIT licensed.
