#!/usr/bin/env bash
# dispatch-tasks の heavy.sh: 鍵の取り合い。使い捨てのリポジトリで流す。待ちの間隔は1秒に縮める。
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$here/.." && pwd -P)
# shellcheck source=tests/lib.sh
. "$here/lib.sh"
HEAVY=${HEAVY_SH:-$repo/skills/dispatch-tasks/scripts/heavy.sh}

fx=$(new_tmp)
trap 'rm -rf "$fx"' EXIT
git init -q "$fx/repo"
lock="$fx/repo/.git/tower-heavy.lock"
log="$fx/log"
export TOWER_HEAVY_POLL=1

# 仕事: 始めと終わりの時刻（秒）を log に書く。$0 = 名前、$1 = log、$2 = 秒
job='echo "$0 start $(date +%s)" >>"$1"; sleep "$2"; echo "$0 end $(date +%s)" >>"$1"'
heavy() { (cd "$fx/repo" && /bin/bash "$HEAVY" "$@"); }
at() { awk -v n="$1" -v w="$2" '$1 == n && $2 == w { print $3 }' "$log"; } # at <名前> start|end
dead_pid() { # 確実に消えた pid
  /bin/sleep 0 &
  wait $!
  echo $!
}
no_overlap() { # no_overlap <説明> <名前1> <名前2> : 2つの仕事の時間が重なっていないこと
  local s1 e1 s2 e2
  s1=$(at "$2" start) e1=$(at "$2" end) s2=$(at "$3" start) e2=$(at "$3" end)
  if [ -z "$s1" ] || [ -z "$e1" ] || [ -z "$s2" ] || [ -z "$e2" ]; then
    ng "$1 — 記録が足りない: $(tr '\n' ' ' <"$log")"
  elif [ "$s2" -ge "$e1" ] || [ "$s1" -ge "$e2" ]; then
    ok "$1"
  else
    ng "$1 — 重なった: $2 ${s1}〜${e1}、$3 ${s2}〜${e2}"
  fi
}

# --- 同時に2本 → 1本ずつ
: >"$log"
heavy -l A -- /bin/sh -c "$job" A "$log" 2 2>/dev/null &
heavy -l B -- /bin/sh -c "$job" B "$log" 2 2>/dev/null &
wait
no_overlap "同時に出した2本は重ならない" A B
check "終わったら鍵が残らない" "" "$(ls -d "$lock" 2>/dev/null)"

# --- 終了コードをそのまま返す
heavy -l x -- /bin/sh -c 'exit 3' 2>/dev/null
check "コマンドの終了コードを返す" 3 "$?"
check "失敗しても鍵を返す" "" "$(ls -d "$lock" 2>/dev/null)"

# --- 持ち主の書き方
heavy -l "ラベル" -- /bin/sh -c 'cat "$1" >"$2"' sh "$lock/owner" "$fx/owner.copy" "改行を
含む引数" 2>/dev/null
check "持ち主は4行（改行入りの引数でも増えない）" 4 "$(wc -l <"$fx/owner.copy" | tr -d ' ')"
check "pid= は1行" 1 "$(grep -c '^pid=' "$fx/owner.copy")"
has "ラベルを書く" "label=ラベル" "$(cat "$fx/owner.copy")"

# --- 持ち主が消えた鍵は外して取る
mkdir "$lock"
printf 'label=dead\npid=%s\nsince=x\ncmd=x\n' "$(dead_pid)" >"$lock/owner"
out=$(heavy -l C -- /bin/echo ran 2>&1)
check "持ち主が消えた鍵: 終了コード" 0 "$?"
has "持ち主が消えた鍵: 外したと言う" "持ち主のプロセスが消えた鍵を外す" "$out"
has "持ち主が消えた鍵: 走る" "ran" "$out"

# --- 持ち主が生きている鍵は待つ。上限で 75
mkdir "$lock"
printf 'label=alive\npid=%s\nsince=x\ncmd=x\n' "$$" >"$lock/owner"
heavy -l D -t 2 -- /bin/echo ran >"$fx/out" 2>&1
check "待ちの上限: 終了コード" 75 "$?"
lacks "待ちの上限: 走らない" "ran" "$(cat "$fx/out")"
check "待ちの上限: 人の鍵を消さない" "$lock" "$(ls -d "$lock" 2>/dev/null)"
rm -rf "$lock"

# --- pid= の無い持ち主（手で作った鍵）は外さない
mkdir "$lock"
dead_pid >"$lock/owner"
heavy -l E -t 2 -- /bin/echo ran >"$fx/out" 2>&1
check "pid= の無い鍵は外さない" 75 "$?"
rm -rf "$lock"

# --- 持ち主が消えた鍵を、2人が同時に外しにいく。片方の rm を3秒遅らせて窓を広げる
: >"$log"
mkdir -p "$fx/slowbin"
printf '#!/bin/sh\nsleep 3\nexec /bin/rm "$@"\n' >"$fx/slowbin/rm"
chmod +x "$fx/slowbin/rm"
mkdir "$lock"
printf 'label=dead\npid=%s\nsince=x\ncmd=x\n' "$(dead_pid)" >"$lock/owner"
(cd "$fx/repo" && PATH="$fx/slowbin:$PATH" /bin/bash "$HEAVY" -l S -- /bin/sh -c "$job" S "$log" 3 2>/dev/null) &
sleep 1
heavy -l F -- /bin/sh -c "$job" F "$log" 3 2>/dev/null &
sleep 5
heavy -l G -- /bin/sh -c "$job" G "$log" 1 2>/dev/null &
wait
no_overlap "外す所の競合: 遅い人と速い人が重ならない" S F
no_overlap "外す所の競合: 3人目も重ならない（S と）" S G
no_overlap "外す所の競合: 3人目も重ならない（F と）" F G
check "外す所の競合: 印が残らない" "" "$(ls -d "$lock.break" 2>/dev/null)"

# --- 後始末は自分の鍵だけ。走っている間に持ち主が変わっていたら、終わっても消さない
heavy -l H -- /bin/sh -c 'printf "label=other\npid=%s\n" "$2" >"$1/owner"; sleep 1' sh "$lock" "$$" 2>/dev/null
check "持ち主が変わった鍵は消さない" "$lock" "$(ls -d "$lock" 2>/dev/null)"
rm -rf "$lock"

# --- 包みのシェルに TERM が届いても、中の処理が終わるまで鍵を持つ
: >"$log"
(cd "$fx/repo" && exec /bin/bash "$HEAVY" -l T -- /bin/sh -c "$job" T "$log" 3) 2>/dev/null &
wpid=$!
sleep 1
kill -TERM "$wpid" 2>/dev/null
sleep 1
check "TERM の後も、中の処理が動いている間は鍵がある" "$lock" "$(ls -d "$lock" 2>/dev/null)"
wait "$wpid" 2>/dev/null
check "TERM を受けた包みは 143 で終わる" 143 "$?"
check "中の処理が終わったら鍵を返す" "" "$(ls -d "$lock" 2>/dev/null)"
has "中の処理は最後まで走る" "T end" "$(cat "$log")"

# --- git の外では止まる
mkdir -p "$fx/nogit"
(cd "$fx/nogit" && /bin/bash "$HEAVY" -l X -- /bin/echo ran) >"$fx/out" 2>&1
check "git の外: 終了コード" 2 "$?"
lacks "git の外: 走らない" "ran" "$(cat "$fx/out")"
check "git の外: 現在地に鍵を作らない" "" "$(ls -d "$fx/nogit/tower-heavy.lock" 2>/dev/null)"

# --- 引数が足りない
heavy -l X 2>/dev/null
check "コマンドが無い: 終了コード" 2 "$?"

finish
