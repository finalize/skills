"""HTML で組んだ動き（motion_lib.js + 場面の js）を撮って MP4 にする共通部分。
フォントと設定を 1 枚の HTML に埋め込み、Playwright で Chrome を並べて撮り（capture.mjs）、
コマごとに分けて撮った画像を平均して動きのぼかしにし、音と一緒に MP4 にする（encode.sh）。

作品のスクリプト（example.py など）から run() を呼ぶ。コマンドの引数:
  --frames 1,40,90  指定したコマだけ（ぼかしなし、1 コマ 1 枚）を描く（確認用）
  --dir DIR         作業フォルダ（既定は一時フォルダ）
  --keep            MP4 にしたあとも、コマの PNG を残す
撮影は Chrome 8 個で手分けする（環境変数 CAPTURE_WORKERS で変えられる）。
分けて撮った画像（20 秒で 10 GB ほど）は、重ね終えたら消す。
"""
import base64
import concurrent.futures
import json
import os
import shutil
import subprocess
import sys
import tempfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
FPS = 30
SHUTTER = 0.5                      # シャッターを開けている長さ（1 コマに対する割合）
# 埋め込むフォント（家族名, このフォルダからのパス）。motion_lib.js の DELA / YUSEI と名前をそろえる
FONTS = [("Dela Gothic One", "fonts/DelaGothicOne-Regular.ttf"), ("Yusei Magic", "fonts/YuseiMagic-Regular.ttf")]


def font_face(family, path):
    full = os.path.join(HERE, path)
    if not os.path.exists(full):
        raise SystemExit(f"フォントがない: {path}（sh fetch_fonts.sh で取ってくる）")
    with open(full, "rb") as f:
        b64 = base64.b64encode(f.read()).decode()
    fmt = "opentype" if path.endswith(".otf") else "truetype"
    return f'@font-face {{ font-family: "{family}"; src: url(data:font/{fmt};base64,{b64}) format("{fmt}"); }}'


def catmull(points):
    """通る点から滑らかな線（SVG の path の d）を作る。飛行機の通り道などに。"""
    p = [points[0]] + list(points) + [points[-1]]
    d = f"M{p[1][0]:.1f},{p[1][1]:.1f}"
    for i in range(1, len(p) - 2):
        p0, p1, p2, p3 = (np.array(v, dtype=float) for v in p[i - 1:i + 3])
        c1, c2 = p1 + (p2 - p0) / 6, p2 - (p3 - p1) / 6
        d += f"C{c1[0]:.1f},{c1[1]:.1f} {c2[0]:.1f},{c2[1]:.1f} {p2[0]:.1f},{p2[1]:.1f}"
    return d


def sample_times(nf, windows, default_n):
    """撮る時刻の一覧と、コマごとの (最初の番号, 枚数)。windows = [(t0, t1, 枚数)]。
    シャッターが開いている間に窓がかかるコマは、かかる窓のうち一番多い枚数で撮る。"""
    times, groups = [], []
    for k in range(nf):
        a, b = (k - SHUTTER / 2) / FPS, (k + SHUTTER / 2) / FPS
        hit = [n for t0, t1, n in windows if a < t1 and t0 < b]
        n = max(hit) if hit else default_n
        groups.append((len(times), n))
        times += [(k + ((j + 0.5) / n - 0.5) * SHUTTER) / FPS for j in range(n)]
    return times, groups


def write_page(path, script, data, times, fonts):
    js = "\n".join(open(os.path.join(HERE, name), encoding="utf-8").read() for name in ("motion_lib.js", script))
    css = "\n".join([font_face(family, file) for family, file in fonts] + [
        "html, body { margin: 0; width: 1920px; height: 1080px; overflow: hidden; background: #0b1128; }",
        "svg, canvas { position: absolute; left: 0; top: 0; }",
        "#grain { mix-blend-mode: overlay; opacity: 0.07; }",
        "#vignette { position: absolute; inset: 0; background: radial-gradient(ellipse at 50% 50%, "
        "rgba(0,0,0,0) 58%, rgba(5,8,26,0.32) 100%); }",
        "#flash { position: absolute; inset: 0; background: #fff; opacity: 0; }",
    ])
    doc = (f"<!doctype html><html><head><meta charset='utf-8'><style>{css}</style></head><body>"
           f"<svg id='stage' width='1920' height='1080' viewBox='0 0 1920 1080'></svg>"
           f"<div id='vignette'></div><canvas id='grain' width='1920' height='1080'></canvas><div id='flash'></div>"
           f"<script>window.SAMPLES = {json.dumps([round(t, 6) for t in times])}; "
           f"window.DATA = {json.dumps(data, ensure_ascii=False)};</script>"
           f"<script>{js}</script></body></html>")
    with open(path, "w", encoding="utf-8") as f:
        f.write(doc)


def parse_args(argv):
    opt, i = {}, 0
    while i < len(argv):
        if argv[i] == "--keep":
            opt["--keep"] = True
            i += 1
        else:
            opt[argv[i]] = argv[i + 1]
            i += 2
    return opt


def run(script, nf, windows, default_n, data, out_mp4, audio_script, audio_wav, argv, work_name, fonts=FONTS):
    """script: 場面の js。nf: コマ数（30 fps）。windows: [(t0, t1, 枚数)] 動きのぼかしで細かく／粗く撮る区間。
    default_n: それ以外の区間の枚数（ふつう 6）。data: ページに window.DATA として渡す設定（文字・回数など）。
    audio_script は audio_wav を書くスクリプト（このフォルダの python で実行する）。"""
    opt = parse_args(argv)
    work = opt.get("--dir", os.path.join(tempfile.gettempdir(), work_name))
    which = opt.get("--frames", "all")
    os.makedirs(work, exist_ok=True)
    page = os.path.join(work, "page.html")
    capture = os.path.join(HERE, "capture.mjs")
    if which != "all":                                  # 確認用: 1 コマ 1 枚
        write_page(page, script, data, [k / FPS for k in range(nf)], fonts)
        subprocess.run(["node", capture, page, os.path.join(work, "frames"), which], check=True)
        return
    times, groups = sample_times(nf, windows, default_n)
    write_page(page, script, data, times, fonts)
    raw = os.path.join(work, "sub")
    shutil.rmtree(raw, ignore_errors=True)
    print(f"[{work_name}] {len(times)} 枚を撮る（{nf} コマ）", flush=True)
    subprocess.run(["node", capture, page, raw, "all"], check=True)
    # コマごとに、分けて撮った画像を平均して動きのぼかしにする
    frames = os.path.join(work, "frames")
    shutil.rmtree(frames, ignore_errors=True)
    os.makedirs(frames)

    def blend(k):
        start, n = groups[k]
        weights = " ".join(["1"] * n)
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-start_number", str(start + 1),
                        "-i", os.path.join(raw, "f%04d.png"),
                        "-vf", f"tmix=frames={n}:weights='{weights}',select='eq(n\\,{n - 1})'",
                        "-frames:v", "1", os.path.join(frames, f"f{k + 1:04d}.png")], check=True)

    with concurrent.futures.ThreadPoolExecutor(8) as pool:
        list(pool.map(blend, range(nf)))
    shutil.rmtree(raw)                                   # 分けて撮った画像はもう使わない
    subprocess.run([sys.executable, os.path.join(HERE, audio_script)], check=True)
    subprocess.run(["sh", os.path.join(HERE, "encode.sh"), frames, out_mp4, os.path.join(HERE, audio_wav)], check=True)
    if not opt.get("--keep"):
        shutil.rmtree(frames)
    print(f"[{work_name}] {os.path.join(HERE, out_mp4)}")
