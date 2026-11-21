# ask-codex を測った記録

`SKILL.md` を使うときに読む必要はない。直すときと、効き目を疑うときに読む。

## 起動とトークン（2026-10-28）

MCP とプラグインを切り推論を medium にしたプロファイルで、起動は約7.0秒から4.5秒、トークンは7,267から4,807に減り、
仕込んだ境界バグを2回とも確信度「高」で指摘した（1件のみ）。

- この数字は、いまの既定を表していない。コミットされたプロファイルの推論は、当時 xhigh、2026-11-02 から max。
  medium はコミットされていない設定での測定で、記録のまま残している
- いまの既定（max）の重さは `delegate.md` にある。差分レビュー1回で、入力170万トークン・9分半
- 2026-11-21、推論 low・空のディレクトリ・一言だけ返させる呼び出しは、4秒・入力 21,028（うちキャッシュ 12,288）・出力 5

## 標準入力待ち

引数でプロンプトを渡すと、標準入力の EOF を待って止まる（200秒止まった）。`ask.sh` は `</dev/null` で塞ぐ。
Codex 側では未解決の issue（openai/codex #20919）で、`</dev/null` が案内されている回避策（2026-11-21 に確認）。

## 実装前の計画の反論役（2026-10-28）

反論に根拠と確かめ方を必須にし、受け取る側が確かめて採否を表にして報告する手順にした。
新しい被験者（opus）で試すと、手順を渡さなくても偽の反論（仕込んだ5件）は採らなかった。
差が出たのは、手順の最初の版が Codex の `expands_scope` を信じて、確かめて成り立った本物の穴を承認待ちで止めたこと。
範囲の判断を受け取る側に直し、同じ入力で穴が計画に入り、偽の反論を採らないのを確かめた
（各条件1件、直した入力と同じ入力での再確認）。

## 読めなくする決まり

2026-11-06: プロファイルの permissions で秘密と実データの置き場を読めなくした。`codex sandbox` と実際の呼び出しで、
作業ディレクトリの外のものも含め、ダミーのファイルが止まるのを確かめた。

2026-11-21: レビューで見つかった抜けを直した。確かめ方は、リポジトリの `tests/sandbox.sh`（本物の `codex sandbox`、134項目）と
`tests/test_ask.sh`（偽の codex、116項目）。codex-cli 0.164.0。

- 一覧に無かった名前（`.dev.vars`、`.env.staging`、`*.p8`、`service_account.json`、`*firebase-adminsdk*.json`、`*.tfstate` など）と
  場所（`~/.codex/auth.json`、`~/.claude.json`、会話の記録、シェルの履歴、wrangler のログイン）が読めた。足して、止まるのを見た。
  `.env.example` と `.env.sample`、git、`sh`、`zsh -l` は動くままなのも見た
- リポジトリの根と `-C` の間のディレクトリの設定を、`ask.sh` は見ていなかった。Codex は、信頼したプロジェクトなら間の
  `.codex/config.toml` も読む。そこで `claude-read` の場所の deny を read に書き換えると、止めたはずのファイルが読めた。
  `-C` から根まで全部見る形にした
- プロファイルに `[mcp_servers.node_repl]`（enabled = false）を書くと、その MCP が無い Mac では
  `invalid transport in mcp_servers.node_repl` で落ちた（2026-11-20）。`ask.sh` が `codex mcp list --json` から名前を取り、
  あるものだけを `-c mcp_servers.<名前>.enabled=false` で切る形にした。同じ `-c` を付けた `codex mcp list --json` で、
  enabled が false になるのを見た。信頼したプロジェクトの設定（間のディレクトリを含む）が定義する MCP も、一覧に出て、同じ形で切れた
- プラグインは、コマンドラインから切れるのを確かめられなかった（`codex plugin list` が40秒たっても返らない）。
  プロファイルに名前で書き、土台で有効なのに切っていないものがあれば `ask.sh` が止まる形にした
- 案件ごとの場所は、公開しない `~/.codex/config.toml` の `[permissions.claude-read.filesystem]` に deny の行だけを足す。
  土台の設定に足した deny が、プロファイルの決まりに合成される（`claude-write` にも引き継がれる）のを見た
  （この仕組みは、あとで外した。下の 2026-11-21 の記録）
- `-w` で `.claude/settings.json` に書けた。読むだけにした（`.git` と `.codex` は、Codex が初めから書けなくしている）
- プロンプトの後ろの `-C`・`-w` を黙って捨てていた。回答が空でも成功にしていた。どちらも止まる形にした

本物の `codex exec` で確かめたのは、新しい `ask.sh` が組むのと同じ引数（`-c mcp_servers.<名前>.enabled=false` を含む）で
1回呼んで、回答が返ることまで（2026-11-21、古いプロファイルのまま）。

2026-11-21（プラグインが MCP を持ち込んでいる Mac）: 新しいプロファイルと新しい `ask.sh` を合わせて、本物の `codex exec` で通した。
`ask.sh -e low` が `invalid transport in mcp_servers.cua_repl` で落ちた。`codex mcp list --json` は土台の設定だけの見え方で、
プロファイルが切ったプラグインの MCP（`cua_repl`）も返す。`codex -p claude mcp list --json` が返したのは `node_repl` だけだった。
一覧を `-p claude` を付けて取る形に直し、同じ呼び出しで回答が返るのを見た（読むだけ。`-e low` と `-e xhigh`）。
偽の codex は、どちらの呼び方にも同じ一覧を返し、無い MCP を切っても落ちなかったので、テストでは見つからなかった。
偽物を本物の振る舞いに合わせ、この入力を `tests/test_ask.sh` に足した（121項目）。

2026-11-21: 案件ごとの場所の仕組み（公開しない `~/.codex/config.toml` に deny の行を足す）を外した。スキルを特定の案件に寄せないため。
外す前に、この書き方の不具合も見た。土台の設定に `[permissions.claude-read.filesystem]` だけを足すと、`-p claude` を付けない
`codex`（`codex mcp list`、`codex login status`、`codex features list`）が
`config defines [permissions] profiles but does not set default_permissions` で設定を読めなくなる（codex-cli 0.164.0）。
`tests/sandbox.sh` は `-p claude` を付けた呼び方だけを見ていたので、気づけなかった。
いまは、土台の設定が `claude-read` / `claude-write` に触れていれば、deny を足すだけでも `ask.sh` は止まる（リポジトリの設定と同じ）。
読めなくする場所は、プロファイルにだけ書く。`tests/sandbox.sh` は129項目、`tests/test_ask.sh` は119項目になった。

## まだ確かめていないこと

- 書く権限（`-w`）での、新しいプロファイルと新しい `ask.sh` を合わせた、本物の `codex exec` での通し（読むだけは上のとおり通した）
- MCP とプラグインが、exec の中で実際に使えなくなっていること（見たのは `codex mcp list` の表示まで）
- `sandbox_mode` があると決まりが効かなくなる件。Codex の文書にはそう書いてある。0.164.0 のソースの読みでは
  「`-c default_permissions` を渡していれば、そちらが先に選ばれる」で、食い違っている。`ask.sh` は止める側に倒している
- Codex に調査や下書きを寄せて、Claude のトークンが減るか
