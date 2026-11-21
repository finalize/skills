# 罠: シェル

実際に踏んだもの。見出しに、踏んだ時期と版を書いてある。
生成するスキルの「罠」に写す前に、その罠がいまの環境でも起きるかを1回流して確かめる。

## シェル（2026-09〜10 に踏んだもの。2026-11-21 に macOS 27.2・Claude Code 2.1.329 で、グロブ・`timeout`・`grep` の3つを流し直した）

- zsh では、一致しないグロブ（`rm -f Foo.usd*`、`--include=*.swift`）で止まり、`&&` の後ろが走らない。グロブは引用するか、ファイル名を書く
- `| grep` や `| tail` をつなぐと、終了コードが消える（`xcodebuild … | grep` で2回）。`set -o pipefail` にするか、終了コードを別に見る
- zsh では、変数は空白で分かれない。`pnpm $step` が1語として渡り、偽の失敗になる。配列にする
- macOS に `timeout` が無い機体がある（2026-09〜10 は exit 127 だった。macOS 27.2 には `/usr/bin/timeout` がある）。
  `command -v timeout` で見て、無ければ `perl -e 'alarm 60; exec @ARGV' <コマンド>` で代える
- Claude Code の Bash ツールでは、`grep` はシェルの関数で、同梱の ugrep に回る（`whence -f grep` で見える）。
  日本語と `.{0,300}` で complexity limits に当たる。`command grep`・`/usr/bin/grep`・`rg` を使う。スクリプトの中の `grep` は素の grep
- `zsh -ilc` は親の PATH を引き継ぐ。新しい端末を再現するなら `env -i` から始める
