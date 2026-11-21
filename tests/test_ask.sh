#!/usr/bin/env bash
# ask-codex の ask.sh: 守り（止まる条件）と引数の扱い。偽の codex で流す（モデルは呼ばない）。
# HOME・CODEX_HOME・XDG_STATE_HOME・一時ファイルは全部 fixture に向けるので、本物の環境には触らない。
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$here/.." && pwd -P)
# shellcheck source=tests/lib.sh
. "$here/lib.sh"
ASK=${ASK_SH:-$repo/skills/ask-codex/scripts/ask.sh}
PROFILE_SRC=${ASK_PROFILE:-$repo/skills/ask-codex/claude.config.toml}

fx=$(new_tmp)
trap 'rm -rf "$fx"' EXIT
home="$fx/home"
ch="$home/.codex"
# ask.sh は jq を使う。偽の codex を先頭に置き、あとは最小限の PATH にする
tools="$here/fake:/usr/bin:/bin:$(dirname "$(command -v jq)")"
mkdir -p "$ch" "$home/.ssh/sub" "$fx/state" "$fx/tmp" "$fx/plain" "$fx/elsewhere" "$fx/vault/sub"
cp "$PROFILE_SRC" "$ch/claude.config.toml"
git init -q "$fx/repo"
mkdir -p "$fx/repo/a/b/c"

# run <現在地> <ask.sh の引数...> : 結果は RC・OUT・ERR。
#   FAKE_MODE・FAKE_MCP_JSON・FAKE_MCP_BASE_JSON・FAKE_MCP_RC は呼ぶ前に置く
run() {
  local cwd=$1
  shift
  : >"$fx/fake.log"
  OUT=$(cd "$cwd" && env -i PATH="$tools" HOME="$home" CODEX_HOME="$ch" XDG_STATE_HOME="$fx/state" \
    FAKE_TMP="$fx/tmp" FAKE_LOG="$fx/fake.log" FAKE_MODE="${FAKE_MODE:-ok}" \
    FAKE_MCP_JSON="${FAKE_MCP_JSON:-[]}" FAKE_MCP_BASE_JSON="${FAKE_MCP_BASE_JSON:-}" FAKE_MCP_RC="${FAKE_MCP_RC:-0}" \
    /bin/sh "$ASK" "$@" 2>"$fx/err" </dev/null)
  RC=$?
  ERR=$(cat "$fx/err")
}
called() { grep -c '^--- call' "$fx/fake.log" | tr -d ' '; }
argv() { grep '^argv' "$fx/fake.log" | sed 's/^argv\[[0-9]*\]=//' | tr '\n' ' '; }
put() { # put <ディレクトリ> <中身> : そこに .codex/config.toml を置く
  mkdir -p "$1/.codex"
  printf '%s\n' "$2" >"$1/.codex/config.toml"
}
clear_cfg() {
  rm -rf "$fx/repo/.codex" "$fx/repo/a/.codex" "$fx/repo/a/b/.codex" "$fx/repo/a/b/c/.codex" "$fx/plain/.codex" "$fx/.codex"
  rm -f "$ch/config.toml"
}
stopped() { # stopped <説明> : 止まって、codex の exec を呼んでいないこと
  check "$1: 終了コード" 1 "$RC"
  check "$1: codex を呼ばない" 0 "$(called)"
}
passed() {
  check "$1: 終了コード" 0 "$RC"
  check "$1: codex を呼ぶ" 1 "$(called)"
}

# --- ふつうの呼び出し
run "$fx/plain" -C "$fx/plain" "境界値を見て"
passed "読むだけ"
check "回答を返す" "FAKE ANSWER" "$OUT"
has "プロファイルを付ける" "exec -p claude -C $fx/plain" "$(argv)"
has "読むだけの権限" 'default_permissions="claude-read"' "$(argv)"
has "読むだけなら git の外でも走る" "--skip-git-repo-check" "$(argv)"
has "セッションを残さない" "--ephemeral" "$(argv)"
has "標準入力を閉じる" "stdin_bytes=0" "$(cat "$fx/fake.log")"
has "トークンを出す" "入力 1200 (うちキャッシュ 800)" "$ERR"
has "トークンを記録する" "claude-read" "$(tail -1 "$fx/state/ask-codex/usage.tsv")"
check "一時ファイルを残さない" "" "$(ls "$fx/tmp")"

run "$fx/repo" -w -C "$fx/repo" "直して"
passed "書く権限"
has "書く権限を付ける" 'default_permissions="claude-write"' "$(argv)"
lacks "書くときは git の外では走らせない" "--skip-git-repo-check" "$(argv)"

run "$fx/plain" -e low -k "x"
has "推論の強さ" 'model_reasoning_effort="low"' "$(argv)"
lacks "-k なら残す" "--ephemeral" "$(argv)"
has "続け方を出す" "resume th_fake_123" "$ERR"

: >"$fx/fake.log"
OUT=$(cd "$fx/plain" && printf '長いプロンプト\n2行目\n' | env -i PATH="$tools" HOME="$home" CODEX_HOME="$ch" \
  XDG_STATE_HOME="$fx/state" FAKE_TMP="$fx/tmp" FAKE_LOG="$fx/fake.log" /bin/sh "$ASK" - 2>/dev/null)
check "標準入力のプロンプト" "FAKE ANSWER" "$OUT"
has "標準入力を渡す" "stdin_bytes=30" "$(cat "$fx/fake.log")"

# --- 引数
run "$fx/plain" "ここを見て" -C "$fx/repo" -w
check "プロンプトの後ろの引数: 終了コード" 2 "$RC"
check "プロンプトの後ろの引数: codex を呼ばない" 0 "$(called)"
has "プロンプトの後ろの引数: 理由を言う" "プロンプトの後ろに引数がある" "$ERR"

run "$fx/plain" -S report "x"
has "-S は名前で引ける（report）" "--output-schema $repo/skills/ask-codex/schemas/report.json" "$(argv)"
run "$fx/plain" -S objections "x"
has "-S は名前で引ける（objections）" "--output-schema $repo/skills/ask-codex/schemas/objections.json" "$(argv)"
run "$fx/plain" -S schemas/report.json "x"
has "-S はスキルからの相対でも引ける" "--output-schema $repo/skills/ask-codex/schemas/report.json" "$(argv)"
run "$fx/plain" -S nosuch "x"
check "-S に無い名前: 終了コード" 2 "$RC"
check "-S に無い名前: codex を呼ばない" 0 "$(called)"

run "$fx/plain" -C "$fx/nosuchdir" "x"
check "無い作業ディレクトリ: 終了コード" 2 "$RC"

# --- 失敗の扱い
FAKE_MODE=empty run "$fx/plain" "x"
check "回答が空: 失敗にする" 1 "$RC"
has "回答が空: 理由を言う" "最終回答が空" "$ERR"
check "回答が空: ログとイベントを残す" 2 "$(find "$fx/tmp" -type f | wc -l | tr -d ' ')"
rm -f "$fx/tmp"/*

FAKE_MODE=fail run "$fx/plain" "x"
check "codex の失敗: 終了コードをそのまま返す" 3 "$RC"
has "codex の失敗: ログの場所を出す" "codex が失敗した (終了コード 3)" "$ERR"
has "codex の失敗: ログの中身を出す" "fake codex: boom" "$ERR"
has "codex の失敗: 記録には残す" "3" "$(tail -1 "$fx/state/ask-codex/usage.tsv" | cut -f5)"
rm -f "$fx/tmp"/*

# --- プロファイルが無い・切れている
mv "$ch/claude.config.toml" "$fx/keep.toml"
ln -s "$fx/nowhere.toml" "$ch/claude.config.toml"
run "$fx/plain" "x"
stopped "切れた symlink"
hint=$(printf '%s\n' "$ERR" | sed -n 's/^  ln -sfn/ln -sfn/p')
has "切れた symlink: 張り直し方を出す" "ln -sfn" "$hint"
if [ -n "$hint" ] && /bin/sh -c "$hint" 2>/dev/null; then ok "切れた symlink: 案内どおりに打てる"; else ng "切れた symlink: 案内どおりに打てない"; fi
rm -f "$ch/claude.config.toml"
mv "$fx/keep.toml" "$ch/claude.config.toml"

# --- 守り1: 場所で読めなくしたディレクトリの中を -C にしない
run "$fx" -C "$home/.ssh/sub" "x"
stopped "止めた場所の中"
if [ -d "$home/.SSH/SUB" ]; then # 大文字と小文字を区別しないファイルシステムだけ
  run "$fx" -C "$home/.SSH/SUB" "x"
  stopped "止めた場所の中（大文字）"
fi
ln -s "$home/.ssh/sub" "$fx/elsewhere/link"
run "$fx" -C "$fx/elsewhere/link" "x"
stopped "止めた場所の中（symlink 経由）"
run "$fx" -C "$home" "x"
passed "止めた場所の親"

# --- 公開しない側（~/.codex/config.toml）に足した、案件ごとの場所
put "$home" "[permissions.claude-read.filesystem]
\"$fx/vault\" = \"deny\""
run "$fx" -C "$fx/vault/sub" "x"
stopped "公開しない側で止めた場所の中"
has "公開しない側で止めた場所の中: 理由を言う" "読めなくした" "$ERR"
run "$fx/plain" "x"
passed "公開しない側が deny だけを足す"
put "$home" "[permissions.claude-read.filesystem.\"/\"]
\"**/*.secret\" = \"deny\" # 名前の決まり"
run "$fx/plain" "x"
passed "公開しない側が名前の deny を足す"
put "$home" "[permissions.claude-read.filesystem]
\"$home/.ssh\" = \"read\""
run "$fx/plain" "x"
stopped "公開しない側が deny 以外を書く"
put "$home" "[permissions.claude-write.filesystem]
\"$fx/vault\" = \"deny\""
run "$fx/plain" "x"
stopped "公開しない側が claude-write の表に書く"
put "$home" "[permissions.claude-read]
extends = \":read-only\""
run "$fx/plain" "x"
stopped "公開しない側が claude-read そのものを書き換える"
put "$home" 'default_permissions = "claude-read"'
run "$fx/plain" "x"
stopped "公開しない側が default_permissions に書く"
clear_cfg

# --- 守り2: sandbox_mode
put "$home" '# sandbox_mode = "read-only"
model = "x"'
run "$fx/plain" "x"
passed "sandbox_mode がコメントだけ"
put "$home" 'sandbox_mode = "read-only"'
run "$fx/plain" "x"
stopped "土台の設定に sandbox_mode"
clear_cfg
for d in "$fx/repo" "$fx/repo/a" "$fx/repo/a/b" "$fx/repo/a/b/c"; do
  put "$d" 'sandbox_mode = "danger-full-access"'
  run "$fx" -C "$fx/repo/a/b/c" "x"
  stopped "sandbox_mode: ${d#"$fx"/}"
  clear_cfg
done
put "$fx" 'sandbox_mode = "danger-full-access"'
run "$fx" -C "$fx/plain" "x"
passed "git の外では、-C の親の設定は Codex も読まない"
clear_cfg

# --- 守り3: ほかの設定がプロファイルの permissions に触れる
for d in "$fx/repo" "$fx/repo/a/b" "$fx/repo/a/b/c"; do
  put "$d" '[permissions.claude-read.filesystem]
"~/.ssh" = "read"'
  run "$fx" -C "$fx/repo/a/b/c" "x"
  stopped "claude-read の書き換え: ${d#"$fx"/}"
  clear_cfg
done
put "$fx/repo/a/b" '[permissions.claude-read.filesystem]
"/x" = "deny"'
run "$fx" -C "$fx/repo/a/b/c" "x"
stopped "リポジトリの設定は、deny を足すだけでも止める"
clear_cfg

# --- MCP: Codex から見えるものを全部切る
FAKE_MCP_JSON='[{"name":"alpha","enabled":true},{"name":"beta","enabled":false},{"name":"gamma","enabled":true}]' run "$fx/plain" "x"
passed "MCP がある"
has "有効な MCP を切る（alpha）" "-c mcp_servers.alpha.enabled=false" "$(argv)"
has "有効な MCP を切る（gamma）" "-c mcp_servers.gamma.enabled=false" "$(argv)"
lacks "初めから無効な MCP には触らない" "mcp_servers.beta" "$(argv)"
has "一覧は作業ディレクトリで取る" "mcp list (cwd=$fx/plain)" "$(cat "$fx/fake.log")"
run "$fx/plain" "x"
lacks "MCP が無ければ何も足さない" "mcp_servers" "$(argv)"
FAKE_MCP_JSON='[{"name":"my.server","enabled":true}]' run "$fx/plain" "x"
stopped "切れない名前の MCP"
FAKE_MCP_RC=1 run "$fx/plain" "x"
stopped "MCP の一覧が取れない"
FAKE_MCP_JSON='{"servers":[]}' run "$fx/plain" "x"
stopped "MCP の一覧の形が違う"

# 実際に壊れた入力（2026-11-21、codex-cli 0.164.0）。土台で有効なプラグインが MCP（cua_repl）を持ち込み、
# プロファイルがそのプラグインを切っている。土台の見え方の一覧から切る名前を取ると、exec から見えない cua_repl まで
# 切ろうとして、本物の codex exec が「invalid transport in `mcp_servers.cua_repl`」で落ちた。
FAKE_MCP_BASE_JSON='[{"name":"cua_repl","enabled":true},{"name":"node_repl","enabled":true}]' \
  FAKE_MCP_JSON='[{"name":"node_repl","enabled":true}]' run "$fx/plain" "x"
passed "プロファイルが切ったプラグインの MCP が、土台の一覧にだけ出る"
check "プロファイルが切ったプラグインの MCP が、土台の一覧にだけ出る: 回答を返す" "FAKE ANSWER" "$OUT"
has "exec から見える MCP は切る" "-c mcp_servers.node_repl.enabled=false" "$(argv)"
lacks "exec から見えない MCP には触らない" "mcp_servers.cua_repl" "$(argv)"

put "$fx/repo/a/b" '[mcp_servers.projsrv]
command = "true"'
run "$fx" -C "$fx/repo/a/b/c" "x"
stopped "リポジトリの MCP が一覧に出ない（信頼されていない）"
FAKE_MCP_JSON='[{"name":"projsrv","enabled":true}]' run "$fx" -C "$fx/repo/a/b/c" "x"
passed "リポジトリの MCP が一覧に出る"
has "リポジトリの MCP も切る" "-c mcp_servers.projsrv.enabled=false" "$(argv)"
put "$fx/repo/a/b" 'mcp_servers = { x = { command = "true" } }'
run "$fx" -C "$fx/repo/a/b/c" "x"
stopped "リポジトリの MCP の書き方を読み取れない"
clear_cfg

# --- プラグイン
put "$fx/repo" '[plugins."some@market"]
enabled = true'
run "$fx" -C "$fx/repo/a/b/c" "x"
stopped "リポジトリの設定がプラグインに触れる"
clear_cfg
put "$home" '[plugins."browser@openai-bundled"]
enabled = true

[plugins."newone@somewhere"]
enabled = true

[plugins."newone@somewhere".settings]
x = 1

[plugins."offone@somewhere"]
enabled = false'
run "$fx/plain" "x"
stopped "土台で有効なプラグインを、プロファイルが切っていない"
has "足す行を出す" '[plugins."newone@somewhere"]' "$ERR"
lacks "プロファイルが切っているものは言わない" "browser@openai-bundled" "$ERR"
lacks "土台で無効なものは言わない" "offone@somewhere" "$ERR"
put "$home" '[plugins."browser@openai-bundled"]
enabled = true'
run "$fx/plain" "x"
passed "土台で有効でも、プロファイルが切っていれば通る"
put "$home" 'plugins."x@y".enabled = true'
run "$fx/plain" "x"
stopped "土台のプラグインの書き方を読み取れない"
clear_cfg

finish
