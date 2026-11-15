#!/usr/bin/env node
// Render a sf-security-audit Markdown report as a self-contained HTML page for human reading (no dependencies).
// Supports the Markdown subset the report template uses: headings, paragraphs, nested lists, tables, fenced
// code, blockquotes, rules, **bold**, `code` and [links](url). Every piece of report text is HTML-escaped —
// reports quote org code and metadata verbatim, so nothing from the report is ever emitted as markup. The page
// loads nothing external (works offline and leaks nothing when opened).
//
// Usage: node render-report-html.mjs <report.md> [--out <report.html>]

import fs from 'node:fs';
import path from 'node:path';

const SEVERITIES = ['Critical', 'High', 'Medium', 'Low', 'Info'];
const FINDING_RE = new RegExp(`^\\[(${SEVERITIES.join('|')})\\]\\s+([A-Z]+-\\d+)\\s+[—–-]\\s+(.*)$`);

// ---------------------------------------------------------------- args

function usage(code) {
  (code ? console.error : console.log)('Usage: node render-report-html.mjs <report.md> [--out <report.html>]');
  process.exit(code);
}

const args = process.argv.slice(2);
let input;
let out;
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--out') out = args[++i];
  else if (args[i] === '-h' || args[i] === '--help') usage(0);
  else input = args[i];
}
if (!input || !fs.existsSync(input)) usage(1);
out ??= input.replace(/\.md$/i, '') + '.html';

const source = fs.readFileSync(input, 'utf8').replace(/\r\n?/g, '\n').replace(/\u0000/g, '');
// Finding ids that get their own anchor, so "SEC-004" anywhere in the text can link to it.
const findingIds = new Set(
  [...source.matchAll(/^#{2,4}\s+\[(?:Critical|High|Medium|Low|Info)\]\s+([A-Z]+-\d+)/gm)].map((m) => m[1])
);

// ---------------------------------------------------------------- inline

function esc(s) {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

function slug(s) {
  return s.toLowerCase().replace(/<[^>]+>/g, '').replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
}

function inline(text, { autolink = true } = {}) {
  const codes = [];
  let s = text.replace(/`([^`]+)`/g, (_, c) => `\u0000${codes.push(c) - 1}\u0000`);
  s = esc(s);
  s = s.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, (_, label, url) => {
    const raw = url.replace(/&(lt|gt|quot|#39|amp);/g, (e, n) => ({ lt: '<', gt: '>', quot: '"', '#39': "'", amp: '&' })[n]);
    const scheme = raw.match(/^([a-z][\w+.-]*):/i);
    if (scheme && !/^(https?|mailto)$/i.test(scheme[1])) return label;
    return `<a href="${esc(raw)}">${label}</a>`;
  });
  s = s.replace(/\*\*([^*\s](?:[^*]*?[^*\s])?)\*\*/g, '<strong>$1</strong>');
  if (autolink) {
    s = s.replace(/\b([A-Z]+-\d{3})\b/g, (m, id) => (findingIds.has(id) ? `<a class="ref" href="#${slug(id)}">${id}</a>` : m));
  }
  return s.replace(/\u0000(\d+)\u0000/g, (_, i) => `<code>${esc(codes[i])}</code>`);
}

// ---------------------------------------------------------------- blocks

const isBlank = (l) => /^\s*$/.test(l);
const leading = (l) => l.match(/^\s*/)[0].length;
const LIST_RE = /^(\s*)([-*+]|\d+[.)])\s+(.*)$/;
const startsBlock = (l) =>
  /^(`{3,}|~{3,})/.test(l.trim()) || /^#{1,6}\s/.test(l) || /^>/.test(l) || /^\|/.test(l) || LIST_RE.test(l) ||
  /^\s{0,3}([-*_])(\s*\1){2,}\s*$/.test(l);

function splitRow(row) {
  const r = row.trim().replace(/^\|/, '').replace(/\|$/, '');
  const cells = [];
  let cur = '';
  let inCode = false;
  for (let k = 0; k < r.length; k++) {
    const c = r[k];
    if (c === '\\' && r[k + 1] === '|') { cur += '|'; k++; continue; }
    if (c === '`') inCode = !inCode;
    if (c === '|' && !inCode) { cells.push(cur.trim()); cur = ''; continue; }
    cur += c;
  }
  cells.push(cur.trim());
  return cells;
}

function statusClass(cell) {
  const plain = cell.replace(/\*\*/g, '').trim();
  if (/^Fail\b/i.test(plain)) return 'st-fail';
  if (/^Pass\b/i.test(plain)) return 'st-pass';
  if (/^Not (verifiable|covered)/i.test(plain)) return 'st-na';
  return '';
}

function renderTable(header, aligns, rows) {
  if (rows.length === 1 && header.length === SEVERITIES.length && header.every((h, k) => h === SEVERITIES[k])) {
    const tiles = header
      .map((h, k) => `<div class="tile sev-${h.toLowerCase()}"><span class="n">${esc(rows[0][k] ?? '0')}</span><span class="l">${h}</span></div>`)
      .join('');
    return `<div class="tiles">${tiles}</div>`;
  }
  const al = (k) => (aligns[k] ? ` style="text-align:${aligns[k]}"` : '');
  const th = header.map((h, k) => `<th${al(k)}>${inline(h)}</th>`).join('');
  const tb = rows
    .map((r) => `<tr>${header.map((_, k) => {
      const cell = r[k] ?? '';
      const cls = statusClass(cell);
      return `<td${al(k)}${cls ? ` class="${cls}"` : ''}>${inline(cell)}</td>`;
    }).join('')}</tr>`)
    .join('\n');
  return `<div class="table-wrap"><table><thead><tr>${th}</tr></thead><tbody>\n${tb}\n</tbody></table></div>`;
}

// Returns nodes: HTML strings, or { h, text } for headings (sectioned by the page assembler).
function blocks(lines) {
  const nodes = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (isBlank(line)) { i++; continue; }
    let m;

    if ((m = line.trim().match(/^(`{3,}|~{3,})\s*([\w+#.-]*)/))) {
      const fence = m[1];
      const indent = leading(line);
      const buf = [];
      i++;
      while (i < lines.length && !lines[i].trim().startsWith(fence)) {
        buf.push(lines[i].slice(Math.min(indent, leading(lines[i]))));
        i++;
      }
      i++;
      nodes.push(`<pre${m[2] ? ` data-lang="${esc(m[2])}"` : ''}><code>${esc(buf.join('\n'))}</code></pre>`);
      continue;
    }

    if ((m = line.match(/^(#{1,6})\s+(.*?)\s*#*\s*$/))) {
      nodes.push({ h: m[1].length, text: m[2] });
      i++;
      continue;
    }

    if (/^\s{0,3}([-*_])(\s*\1){2,}\s*$/.test(line)) { nodes.push('<hr>'); i++; continue; }

    if (/^>/.test(line)) {
      const buf = [];
      while (i < lines.length && /^>/.test(lines[i])) buf.push(lines[i++].replace(/^>\s?/, ''));
      nodes.push(`<blockquote>${render(blocks(buf))}</blockquote>`);
      continue;
    }

    if (/^\|/.test(line) && i + 1 < lines.length && /^\|?\s*:?-{2,}/.test(lines[i + 1])) {
      const header = splitRow(line);
      const aligns = splitRow(lines[i + 1]).map((c) =>
        c.startsWith(':') && c.endsWith(':') ? 'center' : c.endsWith(':') ? 'right' : '');
      i += 2;
      const rows = [];
      while (i < lines.length && /^\|/.test(lines[i])) rows.push(splitRow(lines[i++]));
      nodes.push(renderTable(header, aligns, rows));
      continue;
    }

    if ((m = line.match(LIST_RE))) {
      const indent = m[1].length;
      const ordered = /\d/.test(m[2]);
      const start = ordered ? parseInt(m[2], 10) : 1;
      const items = [];
      while (i < lines.length) {
        const mm = lines[i].match(LIST_RE);
        if (!mm || mm[1].length !== indent || /\d/.test(mm[2]) !== ordered) break;
        const contentIndent = lines[i].length - mm[3].length;
        const body = [mm[3]];
        let loose = false;
        i++;
        while (i < lines.length) {
          const l = lines[i];
          if (isBlank(l)) {
            let j = i;
            while (j < lines.length && isBlank(lines[j])) j++;
            if (j < lines.length && leading(lines[j]) > indent) {
              while (i < j) { body.push(''); i++; }
              loose = true;
              continue;
            }
            break;
          }
          if (leading(l) > indent) { body.push(l.slice(Math.min(leading(l), contentIndent))); i++; continue; }
          if (!startsBlock(l)) { body.push(l); i++; continue; } // lazy continuation
          break;
        }
        let html = render(blocks(body));
        if (!loose) html = html.replace(/^<p>([\s\S]*?)<\/p>/, '$1');
        items.push(`<li>${html}</li>`);
      }
      const tag = ordered ? 'ol' : 'ul';
      nodes.push(`<${tag}${ordered && start !== 1 ? ` start="${start}"` : ''}>${items.join('\n')}</${tag}>`);
      continue;
    }

    const buf = [line.trim()];
    i++;
    while (i < lines.length && !isBlank(lines[i]) && !startsBlock(lines[i])) buf.push(lines[i++].trim());
    nodes.push(`<p>${inline(buf.join(' '))}</p>`);
  }
  return nodes;
}

function render(nodes) {
  return nodes.map((n) => (typeof n === 'string' ? n : `<h${n.h}>${inline(n.text)}</h${n.h}>`)).join('\n');
}

// ---------------------------------------------------------------- page assembly

const nodes = blocks(source.split('\n'));
let title = 'Salesforce Security Audit';
const intro = [];
const body = [];
const toc = []; // { id, text, findings: [{ id, sev, title }] }
const counts = Object.fromEntries(SEVERITIES.map((s) => [s, 0]));
let inSection = false;
let inFinding = false;
let seenH2 = false;

const closeFinding = () => { if (inFinding) { body.push('</div></details>'); inFinding = false; } };
const closeSection = () => { closeFinding(); if (inSection) { body.push('</section>'); inSection = false; } };

for (const n of nodes) {
  if (typeof n === 'string') { (seenH2 ? body : intro).push(n); continue; }
  if (n.h === 1 && !seenH2) { title = n.text.replace(/[*`]/g, ''); continue; }
  if (n.h === 2) {
    closeSection();
    seenH2 = true;
    const id = slug(n.text);
    toc.push({ id, text: n.text, findings: [] });
    const isFindings = /^findings$/i.test(n.text.trim());
    body.push(`<section id="${id}"${isFindings ? ' class="findings"' : ''}><h2>${inline(n.text, { autolink: false })}</h2>`);
    if (isFindings) body.push('\u0001FILTERS\u0001');
    inSection = true;
    continue;
  }
  const f = n.h >= 3 && n.text.match(FINDING_RE);
  if (f) {
    closeFinding();
    seenH2 = true;
    const [, sev, fid, ftitle] = f;
    const s = sev.toLowerCase();
    counts[sev]++;
    toc.at(-1)?.findings.push({ id: slug(fid), sev: s, fid, title: ftitle });
    body.push(
      `<details class="finding sev-${s}" id="${slug(fid)}" data-sev="${s}" open><summary>` +
        `<span class="badge sev-${s}">${sev}</span><span class="fid">${esc(fid)}</span>` +
        `<span class="ftitle">${inline(ftitle, { autolink: false })}</span></summary><div class="fbody">`
    );
    inFinding = true;
    continue;
  }
  if (n.h <= 3) closeFinding();
  (seenH2 ? body : intro).push(`<h${n.h}>${inline(n.text)}</h${n.h}>`);
}
closeSection();

const filters =
  `<div class="filters" role="group" aria-label="Filter findings by severity">` +
  SEVERITIES.filter((s) => counts[s]).map((s) =>
    `<button type="button" class="chip sev-${s.toLowerCase()}" data-filter="${s.toLowerCase()}" aria-pressed="false">${s} <b>${counts[s]}</b></button>`
  ).join('') +
  `<span class="spacer"></span><button type="button" class="link" data-toggle="collapse">Collapse all</button>` +
  `<button type="button" class="link" data-toggle="expand">Expand all</button></div>`;

const tocHtml = toc
  .map((t) => {
    const sub = t.findings.length
      ? `<ol class="toc-findings">${t.findings.map((f) =>
          `<li data-sev="${f.sev}"><a href="#${f.id}"><span class="dot sev-${f.sev}" aria-hidden="true"></span>` +
          `<span class="tfid">${esc(f.fid)}</span> ${inline(f.title, { autolink: false })}</a></li>`).join('')}</ol>`
      : '';
    return `<li><a href="#${t.id}">${inline(t.text, { autolink: false })}</a>${sub}</li>`;
  })
  .join('\n');

const generated = new Date().toISOString().replace('T', ' ').slice(0, 16) + ' UTC';

const css = `
:root{--bg:#f6f6f3;--surface:#fff;--text:#1d1d1f;--muted:#5d5f63;--border:#e1e1dc;--code-bg:#f0f0ec;--accent:#2a50c8;
--crit:#b3261e;--crit-bg:#fce9e7;--high:#a8470b;--high-bg:#fdeee2;--med:#7a5d00;--med-bg:#fbf3d2;--low:#1d5ea6;--low-bg:#e7f0fb;--info:#55575b;--info-bg:#eeeeec;
--pass:#1e6b3a;--pass-bg:#e5f4ea;color-scheme:light}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#131315;--surface:#1c1c1f;--text:#ececee;--muted:#a3a3aa;--border:#323237;--code-bg:#26262b;--accent:#93a9ff;
--crit:#ff8f86;--crit-bg:#3d1714;--high:#ffb07a;--high-bg:#3b2413;--med:#efcf5c;--med-bg:#352d0f;--low:#8fc3ff;--low-bg:#132a43;--info:#c0c0c6;--info-bg:#2a2a2f;--pass:#7fd69c;--pass-bg:#173322;color-scheme:dark}}
:root[data-theme="dark"]{--bg:#131315;--surface:#1c1c1f;--text:#ececee;--muted:#a3a3aa;--border:#323237;--code-bg:#26262b;--accent:#93a9ff;
--crit:#ff8f86;--crit-bg:#3d1714;--high:#ffb07a;--high-bg:#3b2413;--med:#efcf5c;--med-bg:#352d0f;--low:#8fc3ff;--low-bg:#132a43;--info:#c0c0c6;--info-bg:#2a2a2f;--pass:#7fd69c;--pass-bg:#173322;color-scheme:dark}
*{box-sizing:border-box}
html{scroll-behavior:smooth;scroll-padding-top:16px}
body{margin:0;background:var(--bg);color:var(--text);font:15px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif;-webkit-font-smoothing:antialiased}
a{color:var(--accent);text-decoration:none}a:hover{text-decoration:underline}
code,pre{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:.86em}
code{background:var(--code-bg);padding:.1em .35em;border-radius:4px;overflow-wrap:anywhere}
pre{background:var(--code-bg);border:1px solid var(--border);border-radius:8px;padding:12px 14px;overflow-x:auto;line-height:1.5}
pre code{background:none;padding:0;overflow-wrap:normal}
.confidential{background:var(--crit-bg);color:var(--crit);font-size:13px;font-weight:600;text-align:center;padding:6px 16px}
.layout{display:grid;grid-template-columns:minmax(0,1fr);max-width:1240px;margin:0 auto;padding:0 16px 64px;gap:32px}
@media (min-width:1040px){.layout{grid-template-columns:270px minmax(0,1fr)}nav.toc{position:sticky;top:16px;max-height:calc(100vh - 32px);overflow:auto}}
header.top{grid-column:1/-1;padding:28px 0 8px}
header.top h1{font-size:clamp(22px,3vw,30px);line-height:1.25;margin:0 0 12px;letter-spacing:-.01em}
header.top p{margin:4px 0;color:var(--muted);font-size:14px}
header.top blockquote{margin:12px 0 0;border-left:3px solid var(--border);padding:2px 0 2px 12px;color:var(--muted);font-size:14px}
nav.toc{font-size:13.5px;align-self:start;padding-top:8px}
nav.toc>ol{list-style:none;padding:0;margin:0}
nav.toc>ol>li{margin:2px 0}
nav.toc>ol>li>a{display:block;padding:4px 8px;border-radius:6px;color:var(--text);font-weight:600}
nav.toc a:hover{background:var(--surface);text-decoration:none}
.toc-findings{list-style:none;padding:0 0 6px 8px;margin:0}
.toc-findings a{display:flex;gap:6px;align-items:baseline;padding:2px 8px;border-radius:6px;color:var(--muted);line-height:1.35}
.tfid{font-variant-numeric:tabular-nums;color:var(--text);font-weight:500;white-space:nowrap}
.dot{width:8px;height:8px;border-radius:50%;flex:none;transform:translateY(-1px)}
details.toc-mobile{display:block}
@media (min-width:1040px){details.toc-mobile>summary{display:none}}
details.toc-mobile>summary{cursor:pointer;font-weight:600;padding:10px 12px;background:var(--surface);border:1px solid var(--border);border-radius:8px}
main{min-width:0}
section{background:var(--surface);border:1px solid var(--border);border-radius:12px;padding:8px 24px 20px;margin:0 0 20px}
@media (max-width:600px){section{padding:4px 14px 14px}}
h2{font-size:20px;margin:16px 0 12px;letter-spacing:-.005em}
h3{font-size:16px;margin:20px 0 8px}
h4{font-size:15px;margin:16px 0 6px}
p,ul,ol{margin:8px 0}
ul,ol{padding-left:22px}
li{margin:3px 0}
li>ul,li>ol{margin:3px 0}
hr{border:0;border-top:1px solid var(--border);margin:20px 0}
blockquote{margin:12px 0;border-left:3px solid var(--border);padding:2px 0 2px 12px;color:var(--muted)}
.table-wrap{overflow-x:auto;margin:12px 0;border:1px solid var(--border);border-radius:8px}
table{border-collapse:collapse;width:100%;font-size:14px}
th,td{text-align:left;vertical-align:top;padding:8px 12px;border-bottom:1px solid var(--border)}
th{background:var(--code-bg);font-weight:600;white-space:nowrap}
tr:last-child td{border-bottom:0}
td.st-fail{color:var(--crit);font-weight:500}td.st-pass{color:var(--pass)}td.st-na{color:var(--muted);font-style:italic}
td.st-fail strong{color:var(--crit)}
.tiles{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:10px;margin:16px 0}
@media (max-width:520px){.tiles{grid-template-columns:repeat(3,minmax(0,1fr))}}
.tile{border-radius:10px;padding:12px 14px;background:var(--b);color:var(--c);display:flex;flex-direction:column}
.tile .n{font-size:28px;font-weight:700;line-height:1.1;font-variant-numeric:tabular-nums}
.tile .l{font-size:13px;font-weight:600}
.sev-critical{--c:var(--crit);--b:var(--crit-bg)}.sev-high{--c:var(--high);--b:var(--high-bg)}.sev-medium{--c:var(--med);--b:var(--med-bg)}
.sev-low{--c:var(--low);--b:var(--low-bg)}.sev-info{--c:var(--info);--b:var(--info-bg)}
.dot{background:var(--c)}
.badge{display:inline-block;background:var(--b);color:var(--c);font-size:12px;font-weight:700;padding:2px 8px;border-radius:999px;text-transform:uppercase;letter-spacing:.03em;flex:none}
.filters{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin:4px 0 16px}
.filters .spacer{flex:1}
.chip{font:inherit;font-size:13px;font-weight:600;cursor:pointer;border:1px solid var(--border);background:var(--surface);color:var(--c);border-radius:999px;padding:4px 12px}
.chip b{font-variant-numeric:tabular-nums;margin-left:2px}
.chip[aria-pressed="true"]{background:var(--b);border-color:var(--c)}
button.link{font:inherit;font-size:13px;background:none;border:0;color:var(--accent);cursor:pointer;padding:4px 6px}
details.finding{border:1px solid var(--border);border-left:4px solid var(--c);border-radius:8px;margin:12px 0;background:var(--surface)}
details.finding>summary{cursor:pointer;list-style:none;display:flex;gap:10px;align-items:baseline;flex-wrap:wrap;padding:12px 14px}
details.finding>summary::-webkit-details-marker{display:none}
details.finding>summary::before{content:"\\25B8";color:var(--muted);font-size:12px;transition:transform .15s}
details.finding[open]>summary::before{transform:rotate(90deg)}
details.finding[open]>summary{border-bottom:1px solid var(--border)}
.fid{font-weight:700;font-variant-numeric:tabular-nums;white-space:nowrap}
.ftitle{font-weight:600;flex:1 1 300px;min-width:0}
.fbody{padding:4px 16px 12px}
.fbody>ul:first-child>li>strong:first-child{color:var(--muted);font-weight:600}
a.ref{font-weight:600;white-space:nowrap}
.hidden{display:none!important}
footer{color:var(--muted);font-size:12.5px;text-align:center;padding:8px 16px 32px}
@media print{.confidential{-webkit-print-color-adjust:exact;print-color-adjust:exact}nav.toc,.filters{display:none}.layout{display:block;max-width:none}
section{border:0;padding:0}details.finding{break-inside:avoid-page}body{background:#fff}}
`;

const js = `
(function(){
  var chips=[].slice.call(document.querySelectorAll('[data-filter]'));
  function apply(){
    var on=chips.filter(function(c){return c.getAttribute('aria-pressed')==='true'}).map(function(c){return c.dataset.filter});
    document.querySelectorAll('details.finding, .toc-findings li').forEach(function(el){
      el.classList.toggle('hidden', on.length>0 && on.indexOf(el.dataset.sev)<0);
    });
  }
  chips.forEach(function(c){c.addEventListener('click',function(){
    c.setAttribute('aria-pressed', c.getAttribute('aria-pressed')==='true'?'false':'true'); apply();
  });});
  document.querySelectorAll('[data-toggle]').forEach(function(b){b.addEventListener('click',function(){
    var open=b.dataset.toggle==='expand';
    document.querySelectorAll('details.finding').forEach(function(d){d.open=open});
  });});
  function openTarget(){var t=location.hash&&document.getElementById(decodeURIComponent(location.hash.slice(1)));if(t&&t.tagName==='DETAILS')t.open=true;}
  window.addEventListener('hashchange',openTarget); openTarget();
  window.addEventListener('beforeprint',function(){document.querySelectorAll('details').forEach(function(d){d.open=true})});
})();
`;

const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src data:">
<meta name="referrer" content="no-referrer">
<title>${esc(title)}</title>
<style>${css}</style>
</head>
<body>
<div class="confidential">Confidential — describes exploitable weaknesses. Do not commit, upload or share publicly.</div>
<div class="layout">
<header class="top"><h1>${inline(title, { autolink: false })}</h1>${render(intro)}</header>
<nav class="toc" aria-label="Contents"><details class="toc-mobile" open><summary>Contents</summary><ol>
${tocHtml}
</ol></details></nav>
<main>
${body.join('\n').replace('\u0001FILTERS\u0001', filters)}
</main>
</div>
<footer>Rendered from ${esc(path.basename(input))} by sf-security-audit/render-report-html.mjs · ${generated}</footer>
<script>${js}</script>
</body>
</html>
`;

fs.writeFileSync(out, html);
const total = SEVERITIES.reduce((a, s) => a + counts[s], 0);
console.log(`Wrote ${out} (${total} findings: ${SEVERITIES.map((s) => `${s} ${counts[s]}`).join(', ')})`);
