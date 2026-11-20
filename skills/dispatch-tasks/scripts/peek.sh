#!/usr/bin/env bash
# 子のセッションの画面の終わりを出す。-w を付けると、止まるか確認の画面が出るまで待つ。
# 使い方: peek.sh -s <session> -b <block> [-n 行数] [-w] [-t 待つ秒数]
#   -w のときは1行目に IDLE（止まった）・PROMPT（確認の画面）・GONE（セッションが無い）・TIMEOUT（時間切れ）を出す
#   画面に出ているものしか見えない。畳まれたツールの結果は、子の会話の記録（jsonl）を読む
set -euo pipefail

s="" b="" lines=30 wait="" timeout=900
while getopts "s:b:n:wt:" opt; do
  case $opt in
    s) s=$OPTARG ;;
    b) b=$OPTARG ;;
    n) lines=$OPTARG ;;
    w) wait=1 ;;
    t) timeout=$OPTARG ;;
    *) exit 2 ;;
  esac
done
if [ -z "$s" ] || [ -z "$b" ]; then
  sed -n '3,5p' "$0" >&2
  exit 2
fi

# -s を付けないと、ほかのセッションの block は見つからない
cap() { rex capture -s "$s" -b "$b" --trim; }

# 子が終わると Rex のセッションごと消える（block が見つからない）。そのときは GONE を出して止まる
if ! out=$(cap 2>&1); then
  echo GONE
  printf '%s\n' "$out" >&2
  exit 1
fi
if [ -n "$wait" ]; then
  state=TIMEOUT idle=0 end=$((SECONDS + timeout))
  while [ "$SECONDS" -lt "$end" ]; do
    if ! out=$(cap 2>&1); then
      state=GONE
      break
    fi
    # 許可・フォルダの信頼・モデルの切り替え・選択肢の画面
    if printf '%s' "$out" | grep -qE 'Do you want|trust the files|Switch model\?|Enter to confirm|Enter to select'; then
      state=PROMPT
      break
    fi
    # 考えている間は「esc to interrupt」が出る。3回続けて無ければ止まったとみなす
    if printf '%s' "$out" | grep -q 'esc to interrupt'; then idle=0; else idle=$((idle + 1)); fi
    if [ "$idle" -ge 3 ]; then
      state=IDLE
      break
    fi
    sleep 5
  done
  echo "$state"
fi
printf '%s\n' "$out" | grep -v '^[[:space:]]*$' | tail -n "$lines"
