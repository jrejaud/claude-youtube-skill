#!/usr/bin/env node
// yt-page.mjs — render YouTube search results as a clean results page: YouTube's layout with the
// chrome stripped out. Thumbnails, titles, channel, views, age and length, plus what YouTube hides:
// the like ratio (Return YouTube Dislike), honest titles (DeArrow) and content-farm flags.
//
//   yt-page.mjs --manifest FILE.tsv --out results.html [--query "lord of the rings"] [--note "7 Shorts hidden"]
//
// Manifest: one row per result, TAB-separated:
//   thumbPath  videoId  num  title  channel  views  approval  duration  age  [farm 0|1]  [honest 0|1]
// approval = integer percent liked, or "-". Thumbnails are inlined as data: URIs so the page is a
// single self-contained file (an iTerm browser pane can't load file:// paths next to it).
import fs from 'node:fs';

const a = process.argv.slice(2);
const opt = (k, d = '') => { const i = a.indexOf(k); return i >= 0 ? a[i + 1] : d; };
const manifest = opt('--manifest'), out = opt('--out');
if (!manifest || !out) { console.error('usage: yt-page.mjs --manifest FILE.tsv --out results.html [--query Q] [--note N]'); process.exit(2); }
const query = opt('--query'), note = opt('--note');

const esc = (s) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const mime = (buf) => (buf[0] === 0x89 ? 'image/png' : buf.slice(0, 4).toString('latin1') === 'RIFF' ? 'image/webp' : 'image/jpeg');
const tier = (p) => (!/^\d+$/.test(p) ? null : +p >= 90 ? 'good' : +p >= 75 ? 'mixed' : +p >= 50 ? 'poor' : 'bad');

const rows = fs.readFileSync(manifest, 'utf8').split('\n').filter((l) => l.trim()).map((l) => l.split('\t'));
const cards = rows.map(([thumb, vid, num, title, channel, views, approval, duration, age, farm, honest]) => {
  let src = '';
  try { const b = fs.readFileSync(thumb); if (b.length) src = `data:${mime(b)};base64,${b.toString('base64')}`; } catch {}
  const t = tier(approval);
  const live = /^live$/i.test(duration || '');
  return `<a class="card" href="https://www.youtube.com/watch?v=${esc(vid)}">
  <div class="thumb">${src ? `<img src="${src}" alt="">` : ''}<span class="num">${esc(num)}</span>${duration ? `<span class="dur${live ? ' live' : ''}">${esc(duration)}</span>` : ''}</div>
  <div class="body">
    <div class="title">${esc(title)}${honest === '1' ? ' <span class="tag honest" title="Title from DeArrow">honest title</span>' : ''}</div>
    <div class="chan">${esc(channel)}${farm === '1' ? ' <span class="tag farm" title="Uploads like a content farm">🏭 content farm</span>' : ''}</div>
    <div class="meta">${[views && `${esc(views)} views`, age && esc(age)].filter(Boolean).join(' · ')}</div>
    ${t ? `<div class="rating ${t}"><b>${esc(approval)}%</b> liked</div>` : '<div class="rating none">no rating data</div>'}
  </div>
</a>`;
}).join('\n');

const html = `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(query || 'YouTube results')}</title>
<style>
:root{color-scheme:dark;--bg:#0f0f0f;--fg:#f1f1f1;--dim:#aaa;--card:#181818}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.35 -apple-system,"Roboto","Segoe UI",Arial,sans-serif}
header{padding:18px 20px 6px;display:flex;align-items:baseline;gap:12px;flex-wrap:wrap}
header h1{margin:0;font-size:20px;font-weight:600}
header .note{color:var(--dim);font-size:14px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:22px 16px;padding:12px 20px 28px}
.card{color:inherit;text-decoration:none;display:block}
.thumb{position:relative;aspect-ratio:16/9;border-radius:12px;overflow:hidden;background:#222}
.thumb img{width:100%;height:100%;object-fit:cover;display:block}
.num{position:absolute;left:8px;top:8px;background:rgba(0,0,0,.75);font-weight:700;font-size:14px;padding:2px 8px;border-radius:6px}
.dur{position:absolute;right:8px;bottom:8px;background:rgba(0,0,0,.8);font-weight:600;font-size:13px;padding:2px 6px;border-radius:4px}
.dur.live{background:#cc0000}
.body{padding:10px 2px 0}
.title{font-weight:600;font-size:16px;line-height:1.3;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
.chan,.meta{color:var(--dim);font-size:14px;margin-top:4px}
.tag{display:inline-block;font-size:12px;font-weight:600;padding:1px 7px;border-radius:999px;vertical-align:1px}
.tag.farm{background:#3d2a12;color:#ffb020}
.tag.honest{background:#13304a;color:#7cc4ff}
.rating{display:inline-block;margin-top:8px;font-size:14px;padding:3px 10px;border-radius:999px}
.rating b{font-size:15px}
.rating.good{background:#123d24;color:#4ade80}
.rating.mixed{background:#3d3212;color:#ffd166}
.rating.poor{background:#3d2412;color:#ff9f43}
.rating.bad{background:#3d1414;color:#ff6b61}
.rating.none{background:#262626;color:var(--dim)}
</style></head><body>
<header><h1>${esc(query ? `“${query}”` : 'Results')}</h1>${note ? `<span class="note">${esc(note)}</span>` : ''}</header>
<main class="grid">
${cards}
</main></body></html>`;
fs.writeFileSync(out, html);
console.log(out);
