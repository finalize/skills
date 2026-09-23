// HTML で組む動きの道具。motion_page.py が場面のファイル（example_scene.js など）の前に埋め込み、
// capture.mjs が init() のあと setFrame(i) を 1 コマずつ呼んで撮る。
// 見た目は時刻 t だけで決まるように書く。撮る時刻の一覧は motion_page.py が SAMPLES に入れる
// （動きのぼかしのため、1 コマを何回かに分けて撮って重ねる。速く動くところほど細かく）。
// 場面のファイルは次を用意する: init()（setupStage → 場面を作る → setupOverlays → SAMPLES.length を返す）と
// render(t)（renderScenes(t) → カメラ → drawGrain(t)）。場面は scenes.push({ g, t0, t1, update(t) })。
"use strict";
const W = 1920, H = 1080, FPS = 30;
const SAMPLES = window.SAMPLES;
const DATA = window.DATA;
// 配色とフォントは見本の値。作品ごとに差し替える（フォントは motion_page.py の fonts と名前をそろえる）
const C = {
  navy: "#1d2b53", navyD: "#121a36", navyDD: "#0b1128", coral: "#ff6b5b", coralD: "#c9402f",
  yellow: "#ffd23f", yellowD: "#e9a800", cream: "#fff4dc", sky: "#a9e0f8", skyD: "#4fa9dd",
  indigo: "#2d2f6e", white: "#ffffff",
};
const DELA = "Dela Gothic One", YUSEI = "Yusei Magic", HIRA = "Hiragino Sans", AVENIR = "Avenir Next";

// ================================================================ 道具
const NS = "http://www.w3.org/2000/svg";
function el(tag, attrs = {}, parent = null, text = null) {
  const e = document.createElementNS(NS, tag);
  for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, v);
  if (text !== null) e.textContent = text;
  if (parent) parent.appendChild(e);
  return e;
}
const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const lin = (t, a, b) => clamp((t - a) / (b - a));
const lerp = (a, b, u) => a + (b - a) * u;
const eOutCubic = (x) => 1 - Math.pow(1 - x, 3);
const eInCubic = (x) => x * x * x;
const eInOut = (x) => (x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2);
const eOutBack = (x, s = 1.7) => (x <= 0 ? 0 : 1 + (s + 1) * Math.pow(x - 1, 3) + s * Math.pow(x - 1, 2));
const eElastic = (x) => (x <= 0 ? 0 : x >= 1 ? 1 : Math.pow(2, -9 * x) * Math.sin((x * 9 - 0.75) * (2 * Math.PI / 3)) + 1);
function rng(seed) {                         // 決まった乱数（mulberry32）
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const f1 = (v) => v.toFixed(1);
function place(e, x, y, s = 1, r = 0, sy = null) {
  e.setAttribute("transform", `translate(${f1(x)},${f1(y)}) rotate(${r.toFixed(2)}) scale(${s.toFixed(4)},${(sy ?? s).toFixed(4)})`);
}
function show(e, on) { e.style.display = on ? "" : "none"; }

// 叩きつける: 当たる瞬間 hit に向かって from 倍 → 1 倍へ加速し、当たったあと小さく弾む
function slam(t, hit, from = 2.4, dur = 0.13) {
  const t0 = hit - dur;
  if (t < t0) return { s: from, o: 0 };
  if (t < hit) { const p = (t - t0) / dur; return { s: 1 + (from - 1) * (1 - p * p), o: clamp(p * 4) }; }
  const u = t - hit;
  return { s: 1 - 0.07 * Math.exp(-u * 11) * Math.cos(u * 40), o: 1 };
}
// ぽんと出る（行き過ぎて戻る）
const pop = (t, t0, dur = 0.3) => eOutBack(lin(t, t0, t0 + dur));

// ---------------------------------------------------------------- 形
// 叫びの吹き出し（ギザギザ）
function shout(rx, ry, n, seed) {
  const r = rng(seed);
  const pts = [];
  for (let i = 0; i < 2 * n; i++) {
    const a = (i + (r() - 0.5) * 0.5) / (2 * n) * 2 * Math.PI;
    const k = i % 2 === 0 ? 1.0 + r() * 0.17 : 0.84 + r() * 0.05;
    pts.push([rx * k * Math.cos(a), ry * k * Math.sin(a)]);
  }
  return "M" + pts.map((p) => p.map(f1).join(",")).join("L") + "Z";
}
// 丸い吹き出し（しっぽ付き）。a1 < a2 の間からしっぽを出す（角度は度、y は下向き）
function round(rx, ry, a1, a2, tip) {
  const p = (a) => [rx * Math.cos(a * Math.PI / 180), ry * Math.sin(a * Math.PI / 180)].map(f1).join(",");
  return `M${p(a2)}A${rx},${ry} 0 1 1 ${p(a1)}L${tip.map(f1).join(",")}Z`;
}
// もやもやした吹き出し（つぶやき）: 楕円をゆっくり揺らした線
function wobbly(rx, ry, seed, tail = null) {
  const r = rng(seed);
  const ph = [r() * 6.28, r() * 6.28, r() * 6.28];
  const n = 96, pts = [];
  for (let i = 0; i < n; i++) {
    const a = i / n * 2 * Math.PI;
    const k = 1 + 0.035 * Math.sin(3 * a + ph[0]) + 0.025 * Math.sin(5 * a + ph[1]) + 0.012 * Math.sin(9 * a + ph[2]);
    pts.push([rx * k * Math.cos(a), ry * k * Math.sin(a)]);
  }
  let d = "M" + pts.map((p) => p.map(f1).join(",")).join("L") + "Z";
  if (tail) d += `M${tail[0].map(f1).join(",")}Q${tail[1].map(f1).join(",")} ${tail[2].map(f1).join(",")}`;
  return d;
}
// 考えごとの雲
function cloud(rx, ry, n, seed) {
  const r = rng(seed);
  const pts = [];
  for (let i = 0; i < n; i++) {
    const a = (i + (r() - 0.5) * 0.3) / n * 2 * Math.PI;
    pts.push([rx * Math.cos(a), ry * Math.sin(a)]);
  }
  let d = `M${pts[0].map(f1).join(",")}`;
  for (let i = 0; i < n; i++) {
    const q = pts[(i + 1) % n], p = pts[i];
    const rr = Math.hypot(q[0] - p[0], q[1] - p[1]) * (0.55 + r() * 0.12);
    d += `A${f1(rr)},${f1(rr)} 0 0 1 ${q.map(f1).join(",")}`;
  }
  return d + "Z";
}
// 怒りのマーク（💢）
function anger(parent, size, color) {
  const g = el("g", {}, parent);
  const piece = (w, col) => {
    for (let k = 0; k < 4; k++) {
      el("path", {
        d: `M${-size},${-size * 0.3} Q${-size * 0.34},${-size * 0.34} ${-size * 0.3},${-size}`,
        transform: `rotate(${k * 90})`, fill: "none", stroke: col, "stroke-width": w, "stroke-linecap": "round",
      }, g);
    }
  };
  piece(size * 0.62, C.white);
  piece(size * 0.3, color);
  return g;
}
function teardrop(r) {
  return `M0,${-r * 1.9} C${r * 0.6},${-r * 0.9} ${r},${-r * 0.4} ${r},${r * 0.2} A${r},${r} 0 0 1 ${-r},${r * 0.2} C${-r},${-r * 0.4} ${-r * 0.6},${-r * 0.9} 0,${-r * 1.9}Z`;
}
function sparkle(r) {
  const q = r * 0.22;
  return `M0,${-r} Q${q},${-q} ${r},0 Q${q},${q} 0,${r} Q${-q},${q} ${-r},0 Q${-q},${-q} 0,${-r}Z`;
}

// 太い文字（縁取り・外側の白縁・ずらした影）
function word(parent, text, o) {
  const g = el("g", {}, parent);
  const base = {
    x: 0, y: 0, "font-family": o.font, "font-size": o.size, "text-anchor": o.anchor || "middle",
    "dominant-baseline": "central", "stroke-linejoin": "round", "paint-order": "stroke",
  };
  if (o.weight) base["font-weight"] = o.weight;
  if (o.spacing) base["letter-spacing"] = o.spacing;
  const edge = o.outer ? o.ow : o.sw || 0;
  if (o.shadow) el("text", { ...base, x: o.sdx ?? 10, y: o.sdy ?? 12, fill: o.shadow, stroke: o.shadow, "stroke-width": edge }, g, text);
  if (o.outer) el("text", { ...base, fill: o.outer, stroke: o.outer, "stroke-width": o.ow }, g, text);
  el("text", { ...base, fill: o.fill, stroke: o.stroke || "none", "stroke-width": o.sw || 0 }, g, text);
  return g;
}
// 角の丸い札（左上の「その1」や、下の数字）。parts は [[文字, フォント, 大きさ, 太さ], ...]
function pill(parent, parts, o) {
  const g = el("g", {}, parent);
  const bg = el("rect", { rx: o.h / 2, ry: o.h / 2, height: o.h, y: -o.h / 2, fill: o.bg }, g);
  const tx = el("text", { x: 0, y: 0, "dominant-baseline": "central", fill: o.fg }, g);
  for (const [s, font, size, weight] of parts) {
    const sp = el("tspan", { "font-family": font, "font-size": size }, tx, s);
    if (weight) sp.setAttribute("font-weight", weight);
  }
  const w = tx.getComputedTextLength() + o.pad * 2;
  bg.setAttribute("width", w);
  tx.setAttribute("x", o.pad);
  if (o.align === "right") { bg.setAttribute("x", -w); tx.setAttribute("x", -w + o.pad); }
  return { g, w };
}

// 集中線（3 組をコマごとに切り替えてちらつかせる）
function speedLines(parent, cx, cy, n, r0, r1, color, opacity, seed) {
  const sets = [];
  for (let s = 0; s < 3; s++) {
    const r = rng(seed + s * 101);
    let d = "";
    for (let i = 0; i < n; i++) {
      const a = (i + r()) / n * 2 * Math.PI, w = (0.2 + r() * 0.8) * Math.PI / 180, ri = lerp(r0, r1, r());
      const p = (ang, rad) => `${f1(cx + rad * Math.cos(ang))},${f1(cy + rad * Math.sin(ang))}`;
      d += `M${p(a, ri)}L${p(a - w, 1600)}L${p(a + w, 1600)}Z`;
    }
    sets.push(el("path", { d, fill: color, opacity }, parent));
  }
  return sets;
}
function flicker(sets, t, rate = 15) {
  const k = Math.floor(t * rate) % sets.length;
  sets.forEach((s, i) => show(s, i === k));
}

// 網点（端ほど見える）
function halftone(parent, id, color, r, step) {
  const pat = el("pattern", { id, width: step, height: step, patternUnits: "userSpaceOnUse" }, defs);
  el("circle", { cx: step / 2, cy: step / 2, r, fill: color }, pat);
  const gr = el("radialGradient", { id: id + "g", cx: "50%", cy: "50%", r: "70%" }, defs);
  el("stop", { offset: "0.35", "stop-color": "#000" }, gr);
  el("stop", { offset: "1", "stop-color": "#fff" }, gr);
  const m = el("mask", { id: id + "m" }, defs);
  el("rect", { width: W, height: H, fill: `url(#${id}g)` }, m);
  return el("rect", { width: W, height: H, fill: `url(#${id})`, mask: `url(#${id}m)` }, parent);
}
function radialBg(parent, id, inner, outer, cx = "50%", cy = "50%") {
  const gr = el("radialGradient", { id, cx, cy, r: "75%" }, defs);
  el("stop", { offset: "0", "stop-color": inner }, gr);
  el("stop", { offset: "1", "stop-color": outer }, gr);
  return el("rect", { width: W, height: H, fill: `url(#${id})` }, parent);
}

// 画面の揺れ（当たった瞬間から減っていく）。list は [時刻, 強さ px]。t の連続した関数にして、ぼかしが自然に付くように
function shakeAt(t, list) {
  let x = 0, y = 0, r = 0;
  list.forEach(([t0, a], k) => {
    const u = t - t0;
    if (u < 0 || u > 0.7) return;
    const e = a * Math.exp(-u * 9);
    x += e * (Math.sin(u * 97 + k) + 0.5 * Math.sin(u * 151 + 2 * k));
    y += e * (Math.cos(u * 83 + 3 * k) + 0.5 * Math.sin(u * 131 + k));
    r += e * 0.035 * Math.sin(u * 71 + k);
  });
  return [x, y, r];
}

// ================================================================ 舞台
const scenes = [];            // { g, t0, t1, update(t) }。t0〜t1 の間だけ表示して update を呼ぶ
let defs, cam, flash, grain, grainTile;

async function setupStage() {
  // 埋め込んだフォントを全部読み終えてから作る（文字の幅を測るものがあるので）
  await Promise.all([...document.fonts].map((f) => f.load().catch(() => {})));
  await document.fonts.ready;
  const svg = document.getElementById("stage");
  defs = el("defs", {}, svg);
  cam = el("g", {}, svg);
  return svg;
}

function setupOverlays() {
  flash = document.getElementById("flash");
  grain = document.getElementById("grain");
  grainTile = document.createElement("canvas");
  grainTile.width = grainTile.height = 256;
  const gc = grainTile.getContext("2d"), img = gc.createImageData(256, 256), r = rng(3);
  for (let i = 0; i < 256 * 256; i++) {
    const v = Math.floor(r() * 255);
    img.data.set([v, v, v, 255], i * 4);
  }
  gc.putImageData(img, 0, 0);
}

function renderScenes(t) {
  for (const s of scenes) {
    const on = t >= s.t0 && t < s.t1;
    show(s.g, on);
    if (on) s.update(t);
  }
}

function drawGrain(t) {
  const ctx = grain.getContext("2d");
  const r = rng(Math.round(t * FPS) + 7);                           // 1 コマの中では同じ粒
  ctx.clearRect(0, 0, W, H);
  ctx.save();
  ctx.translate(-Math.floor(r() * 256), -Math.floor(r() * 256));
  ctx.fillStyle = ctx.createPattern(grainTile, "repeat");
  ctx.fillRect(0, 0, W + 256, H + 256);
  ctx.restore();
}

function setFrame(i) {
  render(Math.max(0, SAMPLES[i]));
  return new Promise((ok) => requestAnimationFrame(() => ok()));
}
window.setFrame = setFrame;
