#!/usr/bin/env bash
# 子のセッションの画面の終わりを出す。-w を付けると、止まるか確認の画面が出るまで待つ。
# 使い方: peek.sh -s <session> -b <block> [-n 行数] [-w] [-t 待つ秒数]
#   -w のときは1行目に IDLE（止まった）・PROMPT（確認の画面）・GONE（セッションが無い）・TIMEOUT（時間切れ）を出す
#   画面に出ているものしか見えない。畳まれたツールの結果は、子の会話の記録（jsonl）を読む
#   終了コードは、セッションが無い（GONE）ときだけ 1。画面が空でも 0
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
  sed -n '3,6p' "$0" >&2
  exit 2
fi

# -s を付けないと、ほかのセッションの block は見つからない
cap() { rex capture -s "$s" -b "$b" --trim; }

# 子が終わると Rex のセッションごと消える（block が見つからない）。そのときは GONE を出して、終了コード 1 で止まる
gone() {
  echo GONE
  printf '%s\n' "$1" >&2
  exit 1
}

# 確認の画面かどうか。見るのは画面の下の方だけ。
# 子の出力の本文に「Do you want …」とあっても、下に番号つきの選択肢が出ていなければ確認の画面ではない
# （文言は Claude Code 2.1.330 のバイナリの文字列から。本物の確認の画面では確かめていない）
is_prompt() {
  local tail_part
  tail_part=$(grep -v '^[[:space:]]*$' <<<"$1" | tail -n 25 || true)
  # フォルダの信頼・モデルの切り替え・選択肢の画面
  if grep -qE 'trust the files|trust this folder|Switch model\?|Enter to confirm|Enter to select' <<<"$tail_part"; then return 0; fi
  # 許可の画面は、問いの文と、番号つきの選択肢が組で出る
  if grep -q 'Do you want' <<<"$tail_part" &&
    grep -qE '^[[:space:]│]*(❯[[:space:]]*)?[0-9]+\.[[:space:]]+(Yes|No)' <<<"$tail_part"; then return 0; fi
  return 1
}

if ! out=$(cap 2>&1); then gone "$out"; fi
if [ -n "$wait" ]; then
  state=TIMEOUT idle=0 end=$((SECONDS + timeout))
  while [ "$SECONDS" -lt "$end" ]; do
    if ! out=$(cap 2>&1); then gone "$out"; fi
    if is_prompt "$out"; then
      state=PROMPT
      break
    fi
    # 考えている間は「esc to interrupt」が出る。3回続けて無ければ止まったとみなす
    if grep -q 'esc to interrupt' <<<"$out"; then idle=0; else idle=$((idle + 1)); fi
    if [ "$idle" -ge 3 ]; then
      state=IDLE
      break
    fi
    sleep "${TOWER_PEEK_POLL:-5}"
  done
  echo "$state"
fi
# 画面が空だと grep -v は何も選ばず 1 を返す。pipefail で落とさない
grep -v '^[[:space:]]*$' <<<"$out" | tail -n "$lines" || true
