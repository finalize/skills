# 罠: iOS

実際に踏んだもの。見出しに、踏んだ時期と版を書いてある。
生成するスキルの「罠」に写す前に、その罠がいまの環境でも起きるかを1回流して確かめる。

## iOS（Xcode 27・iOS 27、2026-09 Sagashi）

- 横向きの `XCTAttachment(screenshot: app.screenshot())` は壊れる（2622×1206 の中に、回転した正方形だけ）。
  UI テストを走らせながら、裏で `xcrun simctl io <udid> screenshot` を回して撮る
- `Logger.info` は残らない。起動する前に
  `xcrun simctl spawn <udid> log stream --level info --predicate 'subsystem == "..."'` を始めておく
- Xcode を更新した後の最初の `xcrun simctl` は、部品の導入で1〜2分かかる。裏で流す
- Xcode 27 では Simulator.app が DeviceHub.app に置き換わった。`open -a Simulator` は失敗する
- 実機は `xcrun devicectl device process launch --console --terminate-existing <bundle id>` で起動してログを読む。
  画面がロック中だと失敗するので、再試行で回す（7回止まった）。アプリへの引数は `--` の後ろに置く
- UI テストで作った場面（対象が中央に止まっている、建物が無い）で通っても、実機で外れる。タップの判定は実機のログで確かめる
- 性能は Release で測る（惑星を作る時間が Debug 1349ms、Release 59ms）
- `swift file.swift`（インタプリタ）はコンパイラごと落ちることがある。`swiftc file.swift -o x && ./x` にする
- USD に `metersPerUnit` が無いと 0.01 とみなされ、RealityKit もそれに従う（60 単位が 0.6 m）。大きさは見た目でなく数値で確かめる
