# 罠: macOS のアプリ

実際に踏んだもの。見出しに、踏んだ時期と版を書いてある。
生成するスキルの「罠」に写す前に、その罠がいまの環境でも起きるかを1回流して確かめる。

## macOS のアプリ（2026-09 lr）

- 合成のクリックやキーは、本人が使っている画面に届く。本人の作業を2回止めた。試験用の窓を作り、
  「最前面が試験用の窓でなければ何もしない」ガードを付ける。許可のダイアログは本人に押してもらう
- `RegisterEventHotKey` で登録したホットキーは、合成キーを受けない（4通りの送り方で試した）
- `NSStatusItem` のメニューは、System Events の `menu bar 2` では取れない
- accessory のアプリでは、`frontmost` が別のアプリ（端末）を返す
- SwiftUI の `Picker` の `.disabled` は、AX からは enabled=true に見える
- 本物の Mac に無い条件（ノッチ）は、アプリの試験用の設定で作る（`defaults write … fakeNotch -bool true`）
- zsh では `log` が組み込みとぶつかる。`/usr/bin/log show --predicate …` と書く
