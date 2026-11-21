#!/usr/bin/env bash
# dispatch-tasks の peek.sh と launch.sh。偽の rex と偽の claude で流す（本物の Rex には何も送らない）。
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$here/.." && pwd -P)
# shellcheck source=tests/lib.sh
. "$here/lib.sh"
SC=${TOWER_SCRIPTS:-$repo/skills/dispatch-tasks/scripts}

fx=$(new_tmp)
trap 'rm -rf "$fx"' EXIT
st="$fx/st"
mkdir -p "$fx/work dir"
export TOWER_PEEK_POLL=1

reset() {
  rm -rf "$st"
  mkdir -p "$st"
}
peek() { FAKE_STATE="$st" PATH="$here/fake:/usr/bin:/bin" /bin/bash "$SC/peek.sh" "$@"; }
launch() { FAKE_STATE="$st" PATH="$here/fake:/usr/bin:/bin" TOWER_CLAUDE_BIN=claude /bin/bash "$SC/launch.sh" "$@"; }

# --- peek.sh: 画面をそのまま見る
reset
printf 'line1\n\nline2\n' >"$st/screen"
out=$(peek -s S -b B)
check "peek: 終了コード" 0 "$?"
check "peek: 空行を除いて出す" "line1
line2" "$out"

reset
printf '\n\n   \n' >"$st/screen"
out=$(peek -s S -b B)
check "peek: 画面が空でも終了コード 0" 0 "$?"
check "peek: 画面が空なら何も出さない" "" "$out"

reset
echo GONE >"$st/screen"
out=$(peek -s S -b B 2>/dev/null)
check "peek: セッションが無ければ終了コード 1" 1 "$?"
check "peek: セッションが無ければ GONE" "GONE" "$out"

# --- peek.sh -w: 止まるか、確認の画面が出るまで待つ
reset
printf 'working\n  esc to interrupt\n' >"$st/screen.1"
printf 'working\n  esc to interrupt\n' >"$st/screen.2"
printf 'done\n❯ \n' >"$st/screen"
check "peek -w: 目印が消えたら IDLE" "IDLE" "$(peek -s S -b B -w -t 30 | head -1)"

reset
printf 'working\n  esc to interrupt\n' >"$st/screen"
check "peek -w: 動き続けていれば TIMEOUT" "TIMEOUT" "$(peek -s S -b B -w -t 3 | head -1)"

reset
printf '⏺ Bash(git push)\n\n Do you want to proceed?\n ❯ 1. Yes\n   2. Yes, and don\047t ask again for git push\n   3. No, and tell Claude what to do differently (esc)\n' >"$st/screen"
check "peek -w: 許可の画面は PROMPT" "PROMPT" "$(peek -s S -b B -w -t 30 | head -1)"

reset
printf ' Do you trust the files in this folder?\n ❯ 1. Yes, I trust this folder\n   2. No, exit\n\n Enter to confirm · Esc to cancel\n' >"$st/screen"
check "peek -w: フォルダの信頼の画面は PROMPT" "PROMPT" "$(peek -s S -b B -w -t 30 | head -1)"

reset
printf '⏺ PR の説明を書いた。見出しは "Do you want the menu to stay open?" にした\n  次にテストを流す\n  esc to interrupt\n' >"$st/screen"
check "peek -w: 本文に同じ英語があるだけなら PROMPT にしない" "TIMEOUT" "$(peek -s S -b B -w -t 3 | head -1)"

reset
printf 'x\n  esc to interrupt\n' >"$st/screen.1"
printf 'x\n  esc to interrupt\n' >"$st/screen.2"
echo GONE >"$st/screen"
out=$(peek -s S -b B -w -t 30 2>/dev/null)
check "peek -w: 待っている途中で消えても終了コード 1" 1 "$?"
check "peek -w: 待っている途中で消えたら GONE" "GONE" "$out"

peek -s S >/dev/null 2>&1
check "peek: 引数が足りない" 2 "$?"

# --- launch.sh
reset
cat >"$fx/brief.md" <<'EOF'
101 を担当してください（"引用符" と 'これ' と $(date) と `id` と $HOME を含む）。
2行目 \n はそのまま。
EOF
out=$(launch -l "101 メニュー" -C "$fx/work dir" -m opus -i "$fx/brief.md" -e xhigh)
check "launch: 終了コード" 0 "$?"
check "launch: session と block を返す" '{"session":"session:fake","block":"block:fake"}' "$out"
has "launch: ラベルを rex に渡す" "arg=101 メニュー" "$(cat "$st/rexnew.log")"
has "launch: 作業フォルダを rex に渡す" "arg=$fx/work dir" "$(cat "$st/rexnew.log")"
child=$(cat "$st/child.out")
has "launch: 引数は9つ（指示文は1つの引数）" "argc=9" "$child"
has "launch: モデルを渡す" "argv[2]=<<opus>>" "$child"
has "launch: 権限モードの既定は auto" "argv[4]=<<auto>>" "$child"
has "launch: effort を渡す" "argv[8]=<<xhigh>>" "$child"
has "launch: 指示文を崩さない" "argv[9]=<<$(cat "$fx/brief.md")>>" "$child"

launch -l x -C "$fx/work dir" -i "$fx/brief.md" >/dev/null 2>&1
check "launch: モデルを渡さなければ止まる" 2 "$?"
launch -l x -C "$fx/nosuch" -m opus -i "$fx/brief.md" >/dev/null 2>&1
check "launch: 作業フォルダが無い" 1 "$?"
: >"$fx/empty.md"
launch -l x -C "$fx/work dir" -m opus -i "$fx/empty.md" >/dev/null 2>&1
check "launch: 指示文が空" 1 "$?"

finish
