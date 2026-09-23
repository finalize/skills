// 見本（3 秒）: 紺の地に集中線。吹き出しに入った文字が 0.8 秒に叩きつけられて画面が揺れ、札と 💢 がぽんと出て、
// 最後は白く飛ばす。文字は example.py の DATA から受け取る。共通の道具は motion_lib.js。
const DUR = 3, NF = FPS * DUR;
const HIT = 0.8;                                   // 叩きつける瞬間（音の「ドン」もここ）
const SHAKES = [[HIT, 26]];

function sceneHello(root) {
  const g = el("g", {}, root);
  radialBg(g, "bg", "#2a3c73", "#0b1128", "50%", "45%");
  const lines = speedLines(g, 960, 540, 110, 420, 640, C.cream, 0.1, 7);
  halftone(g, "dots", "#14204a", 6, 24);
  const b = el("g", {}, g);
  el("path", { d: shout(560, 300, 24, 3), fill: "#050918", opacity: 0.45, transform: "translate(18,20)" }, b);
  el("path", { d: shout(560, 300, 24, 3), fill: C.white, stroke: C.navyDD, "stroke-width": 12, "stroke-linejoin": "round" }, b);
  word(b, DATA.text, { font: DELA, size: 220, fill: C.yellow, stroke: C.navyDD, sw: 20, outer: C.white, ow: 40 });
  const tag = pill(g, [[DATA.tag, HIRA, 40, 800]], { h: 76, pad: 32, bg: C.coral, fg: C.white });
  const mark = anger(g, 64, C.coral);
  const star = el("path", { d: sparkle(48), fill: C.cream }, g);
  scenes.push({
    g, t0: 0, t1: DUR + 0.1, update(t) {
      flicker(lines, t, 10);
      const s = slam(t, HIT, 2.4);
      place(b, 960, 560, s.s, -4 + 10 * (s.s - 1));
      b.setAttribute("opacity", s.o);
      place(tag.g, 960 - tag.w / 2, 170, pop(t, HIT + 0.25, 0.3), -3);
      place(mark, 1480, 310, pop(t, HIT + 0.15, 0.3), 10);
      const u = lin(t, 1.6, 2.1);
      place(star, 470, 330, Math.sin(Math.PI * u) * 1.1, 45 * u);
    },
  });
}

function camera(t) {
  const [dx, dy, dr] = shakeAt(t, SHAKES);
  cam.setAttribute("transform", `translate(${f1(960 + dx)},${f1(540 + dy)}) rotate(${dr.toFixed(3)}) translate(-960,-540)`);
  flash.style.opacity = eInCubic(lin(t, 2.75, 3.0)).toFixed(3);
}

async function init() {
  await setupStage();
  sceneHello(cam);
  setupOverlays();
  return SAMPLES.length;
}

function render(t) {
  renderScenes(t);
  camera(t);
  drawGrain(t);
}
window.init = init;
window.render = render;
