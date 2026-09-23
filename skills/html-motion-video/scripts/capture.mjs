// HTML のページを 1 コマずつ PNG にする。Playwright（playwright-core）でインストール済みの Chrome を動かす。
// ページの init() で準備し、setFrame(i) でコマ i（0 始まり）を描かせてから撮る。
// Chrome を WORKERS 個同時に起動して、コマを手分けして撮る（1 つの Chrome は画面の合成と PNG 化でほぼ 1 コアしか
// 使わないので、別々に起動して CPU のコアを埋める）。ページは時刻だけで決まるので、誰が撮っても同じ絵になる。
// 長く撮り続けると Chrome が落ちることがあるので、落ちたり応答がなくなったりしたら起動し直して続きから撮る。
// メモリがたまらないよう、RELAUNCH_EVERY 枚ごとにも起動し直す。
//
//   node capture.mjs PAGE.html OUT_DIR all        すべてのコマ → OUT_DIR/f0001.png ...
//   node capture.mjs PAGE.html OUT_DIR 1,90,180   指定したコマだけ（1 始まり）
//   CAPTURE_WORKERS=4 node capture.mjs ...        同時に動かす Chrome の数（既定 8）
import { mkdirSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

import { chromium } from "playwright-core";

const WORKERS = Math.max(1, Number(process.env.CAPTURE_WORKERS || 8));
const RELAUNCH_EVERY = 800, TIMEOUT_MS = 90000;
const [pagePath, outDir, which = "all"] = process.argv.slice(2);
mkdirSync(outDir, { recursive: true });

async function launch() {
  const browser = await chromium.launch({
    channel: "chrome", headless: true, timeout: TIMEOUT_MS,
    args: ["--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1"],
  });
  try {
    const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
    page.setDefaultTimeout(TIMEOUT_MS);
    await page.goto(pathToFileURL(resolve(pagePath)).href);
    const count = await page.evaluate("init()");
    return { browser, page, count };
  } catch (e) {
    await browser.close().catch(() => {});
    throw e;
  }
}

// page.evaluate には時間切れがないので、応答が返らないときは自分で打ち切る
function limit(promise, what) {
  let timer;
  const late = new Promise((_, fail) => { timer = setTimeout(() => fail(new Error(`${what} の応答がない`)), TIMEOUT_MS); });
  return Promise.race([promise, late]).finally(() => clearTimeout(timer));
}

const first = await launch();
const frames = which === "all" ? Array.from({ length: first.count }, (_, i) => i + 1) : which.split(",").map(Number);
const n = Math.min(WORKERS, frames.length);
const maxRestarts = 8 + n;
let next = 0, done = 0, restarts = 0, failed = null;
const t0 = Date.now();

async function worker(s) {
  let since = 0;
  try {
    while (!failed) {
      const k = next++;
      if (k >= frames.length) break;
      const f = frames[k];
      for (;;) {
        try {
          if (since >= RELAUNCH_EVERY) {
            await s.browser.close();
            s = await launch();
            since = 0;
          }
          await limit(s.page.evaluate(`setFrame(${f - 1})`), "setFrame");
          const png = await s.page.screenshot({ type: "png" });
          writeFileSync(join(outDir, `f${String(f).padStart(4, "0")}.png`), png);
          since++;
          done++;
          if (done % 60 === 0 || done === frames.length) {
            const sec = (Date.now() - t0) / 1000;
            console.log(`[capture] ${done}/${frames.length} (${(sec / done).toFixed(3)} s/枚, Chrome ${n} 個)`);
          }
          break;
        } catch (e) {
          if (failed) return;
          if (++restarts > maxRestarts) { failed = e; return; }
          console.log(`[capture] ${f} 枚目で失敗: ${e.message.split("\n")[0]} → Chrome を起動し直して続ける (${restarts}/${maxRestarts})`);
          await s.browser.close().catch(() => {});
          try {
            s = await launch();
          } catch (e2) {
            failed = e2;
            return;
          }
          since = 0;
        }
      }
    }
  } finally {
    await s.browser.close().catch(() => {});
  }
}

// 起動できなかった Chrome があれば、起動できた分だけで撮る
const others = (await Promise.allSettled(Array.from({ length: n - 1 }, () => launch())))
  .filter((r) => r.status === "fulfilled").map((r) => r.value);
if (others.length < n - 1) console.log(`[capture] Chrome ${n} 個のうち ${others.length + 1} 個で撮る`);
await Promise.all([first, ...others].map((s) => worker(s)));
if (failed) throw failed;
