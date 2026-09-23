# html-motion-video の参照

`SKILL.md` の手順で使う道具の一覧、実際に使った形、確認の一行。

## motion_lib.js

座標は 1920×1080 の SVG（`#stage`）。場面は `cam`（揺れ・ズームを掛ける `<g>`）の下に作る。

| 道具 | 使い方 |
|---|---|
| `el(tag, attrs, parent, text)` | SVG の要素を作る |
| `lin(t, a, b)` `lerp` `clamp` | 区間の進み具合（0〜1）など |
| `eOutCubic` `eInCubic` `eInOut` `eOutBack` `eElastic` | イージング。`eOutBack` は行き過ぎて戻る、`eElastic` はびよんと揺れて止まる |
| `place(e, x, y, s, r, sy)` | 位置・大きさ・回転をまとめて付ける |
| `slam(t, hit, from=2.4, dur=0.13)` | 叩きつけ。`hit` に向かって from 倍 → 1 倍へ加速し、当たったあと弾む。`{ s, o }` を返す |
| `pop(t, t0, dur=0.3)` | ぽんと出る（0 → 1、行き過ぎて戻る） |
| `shout(rx, ry, n, seed)` | 叫びのギザギザ吹き出し |
| `round(rx, ry, a1, a2, tip)` | 丸い吹き出し。角度 a1〜a2（度、y 下向き）からしっぽを出す |
| `wobbly(rx, ry, seed, tail)` | 手描き風のもやもや（つぶやき）。tail は 3 点の曲線 |
| `cloud(rx, ry, n, seed)` | 考えごとの雲 |
| `anger(parent, size, color)` | 💢 |
| `sparkle(r)` `teardrop(r)` | きらめき、汗 |
| `word(parent, text, o)` | 太い文字。`o`: font size fill / stroke sw（縁）/ outer ow（外の白縁）/ shadow sdx sdy（ずらした影）/ anchor |
| `pill(parent, parts, o)` | 角の丸い札。幅はフォントを読み終えてから測る。`{ g, w }` を返す |
| `speedLines(...)` → `flicker(sets, t, rate)` | 集中線。3 組を切り替えてちらつかせる |
| `halftone(parent, id, color, r, step)` | 端ほど見える網点 |
| `radialBg(parent, id, inner, outer, cx, cy)` | 円く明るい地 |
| `shakeAt(t, [[時刻, 強さ px], ...])` | 当たった瞬間から減っていく揺れ `[dx, dy, 回転]` |
| `setupStage()` `setupOverlays()` `renderScenes(t)` `drawGrain(t)` | 場面のファイルの `init()` / `render(t)` から呼ぶ |

場面の形:

```js
scenes.push({
  g, t0: 1.0, t1: 2.02, update(t) {          // t0〜t1 の間だけ表示して update を呼ぶ
    const s = slam(t, 1.2);                   // 1.2 秒に叩きつける（音の「ドン」も 1.2 秒）
    place(bubble, 650, 560, s.s, -5 + 9 * (s.s - 1));
    bubble.setAttribute("opacity", s.o);
  },
});
```

場面の切り替えに使った形: 丸く開く（`clipPath` の円の半径）、横に振る（2 場面を同じ動きで動かす）、
まばたき（上下からまぶたの形を閉じて開く）、斜めに切る（回した長方形の `clipPath`）、白く飛ばす（`#flash` の不透明度）。

### 画面を振るときの片方向のぼかし

```js
const u = lin(t, PAN[0], PAN[1]);
const slope = u < 0.5 ? 12 * u * u : 12 * (1 - u) * (1 - u);        // eInOut の傾き
const speed = 2300 * slope / (PAN[1] - PAN[0]);                       // px/秒
const sd = u > 0 && u < 1 ? Math.min(60, speed * 0.0009) : 0;
panBlur.setAttribute("stdDeviation", `${sd.toFixed(1)} 0`);           // 縦に振るなら "0 sd"
// filter は filterUnits="userSpaceOnUse" で、動く範囲より広く取る
```

### 重なるラベルを消すとき

コマごとに「見せたいか」を 0/1 で決め、0 が 12 コマ未満しか続かないなら 1 に戻してから、0.3 ずつ近づけて不透明度にする。
一瞬くぐるだけのものまで消すと、点滅に見える。

## motion_page.py

```python
motion_page.run("scene.js", 600,                 # 20 秒 × 30 fps
                [(0.3, 0.6, 24), (8.3, 8.9, 3)],  # 窓: (始め, 終わり, 枚数)。かかる窓の一番多い枚数で撮る
                6,                                # 窓の外の枚数
                {"text": "…"},                    # ページの window.DATA（回ごとに変わる文字・数）
                "out.mp4", "scene_audio.py", "scene_audio.wav", sys.argv[1:], "scene_frames",
                fonts=[("Dela Gothic One", "fonts/DelaGothicOne-Regular.ttf")])
```

`CAPTURE_WORKERS=4 python3 scene.py` で Chrome の数を変える。ほかの重い処理と同時に走らせるときは減らす。

## synth.py

`place(bus, 音, 時刻, 大きさ, 左右)` で `(N, 2)` の配列に並べ、`master(bus + reverb(wet), path)` で書く。

| 部品 | 中身 |
|---|---|
| `kick` `snare` `hat(open_)` `crash` | ドラム。150 BPM で 1・3 拍目にキック、2・4 拍目にスネア、8 分でハイハット |
| `thump` `taiko` | 叩きつける「ドン」、太鼓 |
| `brass(freqs, length)` | シンセのブラスの「ジャッ」。倍音を足すのこぎり波にフィルターの開閉 |
| `bass_note` `pad` `chime` | ベース、和音の下敷き、鐘 |
| `whoosh(length, f0, f1)` | 風切り。帯域が f0 → f1 へ動く |
| `pop` `boing` `slide_whistle` `growl` `breath` `gaan` `riser` `ticks` `sparkle_run` | ポン、びよーん、下がる笛、お腹の音、ため息、ガーン、盛り上げ、カチカチ、キラーン |
| `reverb` `limiter` `tone_shape` `master` | 仕上げ。`master` は低域を削り、平均の音量をそろえ、ピークを抑えて書く |

`NOTE["F4"]` で音の高さ。乱数は読み込んだときの 1 本を呼んだ順に使うので、呼ぶ順を変えなければ毎回同じ音になる。

曲を止める演出（テープ停止）: 止める瞬間から 0.4 秒、読む位置の進み方を 1 → 0 に落とす。

```python
u = np.arange(i1 - i0) / SR
read = stop + u - u ** 2 / (2 * 0.4)
music[i0:i1, ch] = np.interp(read, TT, music_a[:, ch]) * (1 - smooth(u / 0.4)) ** 0.5
```

## YouTube の終了画面

最後の 5〜20 秒に、動画・再生リスト・登録ボタンを重ねられる。20 秒のエンディングの後半 13 秒をこう組んだ:
動画 2 本の枠は 16:9 の 700×394（x = 80 と 830、y = 430）、登録ボタンの丸枠は中心 (1720, 627) 半径 145。
枠の上に札（「次の旅」「おすすめ」「チャンネル登録」）、画面の下を文字が流れる帯。
枠が出そろった 6.7 秒以降は画面を動かさない。YouTube Studio で、枠に合わせて要素を置く。

## 確かめる一行

```sh
# 要所を 1 枚に並べる
ffmpeg -pattern_type glob -i 'frames/f*.png' -vf "scale=640:-1,tile=3x4" -frames:v 1 sheet.png
# できた動画を 1 秒おきに並べる
ffmpeg -i out.mp4 -vf "fps=1,scale=480:-1,tile=5x4" -frames:v 1 sheet.png
# 音のスペクトログラム（鳴る時刻を絵と照らす）
ffmpeg -i out.wav -lavfi "showspectrumpic=s=1800x480:mode=combined:scale=log:fscale=log:legend=1" spec.png
# 送る用の軽い版と、元との差
ffmpeg -i out.mp4 -c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p -colorspace bt709 -color_primaries bt709 \
  -color_trc bt709 -movflags +faststart -c:a copy out_share.mp4
ffmpeg -i out.mp4 -i out_share.mp4 -lavfi psnr -f null -
```

直しの前後で絵が変わっていないかは、同じコマを撮って `md5` を比べる（時刻だけで決まるので、変わらなければ一致する）。
