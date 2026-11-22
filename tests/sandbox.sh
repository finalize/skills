#!/usr/bin/env bash
# 本物の `codex sandbox` で、ask-codex のプロファイルの「読めなくする決まり」を確かめる。モデルは呼ばない。
# 使い方: tests/sandbox.sh   （codex が無ければ飛ばす。手元用で、tests/run.sh からは呼ばない）
#   CODEX_HOME は一時ディレクトリに向けるので、本物の ~/.codex の設定は読まない。
#   場所の決まり（~/.ssh など）は HOME を偽物にして、ダミーのファイルで見る。本物の秘密は開かない。
#   最後に本物の HOME で、git とシェルが動くこと（止めすぎていないこと）だけを見る。
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$here/.." && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh"

if ! command -v codex >/dev/null 2>&1; then
  echo "sandbox.sh: 飛ばす（codex が無い）"
  exit 0
fi

# /tmp の下に作る。$TMPDIR の下は claude-write で書ける場所（:tmpdir）なので、「外には書けない」の確かめに使えない
tmp=$(new_tmp /tmp)
trap 'rm -rf "$tmp"' EXIT
ch="$tmp/codexhome" home="$tmp/home" ws="$tmp/ws" out="$tmp/outside"
mkdir -p "$ch" "$home" "$ws" "$out"
cp "$repo/skills/ask-codex/claude.config.toml" "$ch/claude.config.toml"
git init -q "$ws"

mk() { for f in "$@"; do mkdir -p "$(dirname "$f")" && echo "DUMMY" >"$f"; done; }

# sb <権限> <コマンド...> : fixture の CODEX_HOME と偽物の HOME で流す
sb() {
  perm=$1
  shift
  (cd "$ws" && HOME="${SB_HOME:-$home}" CODEX_HOME="$ch" codex sandbox -p claude -P "$perm" -C "$ws" -- "$@" >/dev/null 2>"$tmp/err")
}
denied() { # denied <権限> <ファイル>
  if sb "$1" /bin/cat "$2"; then ng "読めてはいけない（$1）: ${2#"$tmp"/}"; else ok "止まる（$1）: ${2#"$tmp"/}"; fi
}
allowed() {
  if sb "$1" /bin/cat "$2"; then ok "読める（$1）: ${2#"$tmp"/}"; else ng "読めるはず（$1）: ${2#"$tmp"/} [$(head -1 "$tmp/err")]"; fi
}

# --- 設定が読み込めること（node_repl のような、無い MCP への指定で落ちないこと）
mk "$ws/README.txt"
allowed claude-read "$ws/README.txt"

# --- 名前で止めるもの。作業ディレクトリの中と外の両方
names=".env .env.local .env.foo.local .env.development .env.production .env.test .env.deploy
.env.staging .env.stg .env.prod .env.dev .env.preview .envrc .dev.vars .dev.vars.staging
a.pem a.key AuthKey_ABC123.p8 a.p12 a.pfx release.keystore
app-credentials.json my-service-account.json service_account.json serviceaccount.json
proj-firebase-adminsdk-ab12c.json proj-sa-key-1.json deploy-key.json prod.tfvars terraform.tfstate
docs/a/x.docx docs/a/x.doc docs/a/x.xlsx docs/a/x.xlsm docs/a/x.xls docs/a/x.csv docs/a/x.pdf
docs/a/x.pptx docs/a/x.ppt docs/a/x.zip docs/top.pdf"
for n in $names; do
  mk "$ws/$n" "$out/$n"
  denied claude-read "$ws/$n"
  denied claude-read "$out/$n"
done

# --- 止めすぎていないこと。変数の名前を見るためのファイルと、ふつうのファイル
for n in .env.example .env.sample src/data.csv docs/a/readme.md src/main.ts; do
  mk "$ws/$n"
  allowed claude-read "$ws/$n"
done
mk "$out/note.txt"
allowed claude-read "$out/note.txt"

# --- 場所で止めるもの（HOME を偽物にして、その下のダミーで見る）
locs=".ssh/id_dummy .aws/credentials .config/gcloud/x .config/gh/hosts.yml .docker/config.json .netrc
.git-credentials .npmrc .kube/config .gnupg/x .codex/auth.json .claude.json .claude/projects/p/s.jsonl
.zsh_history .bash_history .wrangler/config/default.toml .config/.wrangler/config/default.toml
Library/Preferences/.wrangler/config/default.toml
.zhistory .zsh_sessions/A1.session .zsh_sessions/A1.history
.claude.json.backup .claude/backups/.claude.json.backup.1 .claude/history.jsonl
.claude/file-history/s1/0123abcd@v1 .claude/paste-cache/p1.txt
.codex/history.jsonl .codex/sessions/2026/11/22/rollout-x.jsonl .codex/archived_sessions/rollout-y.jsonl
Library/Preferences/cloudflare/config/default.json Library/Preferences/cloudflare/state.json
.expo/state.json .app-store/auth/someone/cookie .android/adbkey
.config/gcloud-other/credentials.db .config/gcloud-other/configurations/config_default"
for n in $locs; do
  mk "$home/$n"
  denied claude-read "$home/$n"
done
# 止めすぎていないこと。止めた場所の隣（同じフォルダのほかのファイル、名前の始まりが同じだけのもの）
for n in .zshrc .gitconfig .claude/skills/x/SKILL.md notes.txt \
  .claude/settings.json .claude/CLAUDE.md .codex/config.toml .expo/versions-cache/v.txt .android/adb_usb.ini \
  .config/gcloudish.txt .config/other/note.txt Library/Preferences/other/x.txt; do
  mk "$home/$n"
  allowed claude-read "$home/$n"
done
# 名前の決まりで止めた gcloud の設定フォルダは、作業ディレクトリの中にあっても止まる
mk "$ws/.config/gcloud-x/credentials.db"
denied claude-read "$ws/.config/gcloud-x/credentials.db"

# --- 書く権限（-w）
w() { # w <権限> <ファイル> : 追記できれば 0
  sb "$1" /bin/sh -c 'printf x >>"$1"' sh "$2"
}
mkdir -p "$ws/src" "$ws/.claude" "$ws/.codex"
if w claude-read "$ws/src/new.txt"; then ng "claude-read で書けてはいけない"; else ok "claude-read は書けない"; fi
if w claude-write "$ws/src/new.txt"; then ok "claude-write は作業ディレクトリに書ける"; else ng "claude-write で作業ディレクトリに書けるはず"; fi
if w claude-write "$out/new.txt"; then ng "claude-write で外に書けてはいけない"; else ok "claude-write は外に書けない"; fi
for f in .claude/settings.json .git/config .git/hooks/pre-commit .codex/config.toml; do
  if w claude-write "$ws/$f"; then ng "claude-write で書けてはいけない: $f"; else ok "claude-write は書けない: $f"; fi
done
denied claude-write "$ws/.env"
allowed claude-write "$ws/.claude/../README.txt"
if sb claude-write /bin/sh -c 'mv "$1" "$2" && cat "$2"' sh "$ws/a.pem" "$ws/renamed.txt"; then
  ng "名前を変えて読めてはいけない"
else
  ok "名前で止めたファイルは、名前を変えても読めない"
fi

# --- コマンドからネットワークに出られないこと（つながらない環境でも止まるので、通過しても証拠は弱い）
if command -v curl >/dev/null 2>&1; then
  if sb claude-read /usr/bin/curl -s -m 5 -o /dev/null https://example.com; then ng "claude-read でネットワークに出られた"; else ok "claude-read はネットワークに出られない"; fi
  if sb claude-write /usr/bin/curl -s -m 5 -o /dev/null https://example.com; then ng "claude-write でネットワークに出られた"; else ok "claude-write はネットワークに出られない"; fi
fi

# --- 止めすぎていないこと。本物の HOME で、道具が動くか（秘密は開かない）
SB_HOME=$HOME
for perm in claude-read claude-write; do
  if sb "$perm" /usr/bin/git -C "$ws" status --short; then ok "git が動く（${perm}・本物の HOME）"; else ng "git が動かない（${perm}）: $(head -1 "$tmp/err")"; fi
  if sb "$perm" /bin/sh -c 'ls >/dev/null'; then ok "sh が動く（${perm}・本物の HOME）"; else ng "sh が動かない（${perm}）: $(head -1 "$tmp/err")"; fi
  if sb "$perm" /bin/zsh -lc 'true'; then ok "zsh -l が動く（${perm}・本物の HOME）"; else ng "zsh -l が動かない（${perm}）: $(head -1 "$tmp/err")"; fi
done
unset SB_HOME

finish
