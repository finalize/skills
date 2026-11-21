#!/usr/bin/env bash
# スクリプトのテストと lint を全部流す。
# 使い方: tests/run.sh [名前...]   例: tests/run.sh ask heavy   （名前は test_<名前>.sh の <名前>）
#   偽の codex・rex・claude と、一時ディレクトリの中の使い捨てのリポジトリで流す。
#   本物の ~/.claude・~/.agents・~/.codex、Rex のセッション、Codex には触らない。モデルも呼ばない。
#   本物の codex sandbox で読ませない決まりを見るのは、別の tests/sandbox.sh（手元用）。
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [ $# -gt 0 ]; then
  list=""
  for n in "$@"; do list="$list $here/test_$n.sh"; done
else
  list=$(ls "$here"/test_*.sh)
fi

failed=""
for t in $list; do
  echo "== $(basename "$t")"
  if [ ! -f "$t" ]; then
    echo "  無い: $t"
    failed="$failed $(basename "$t")"
    continue
  fi
  if ! /bin/bash "$t"; then failed="$failed $(basename "$t")"; fi
done

if [ -n "$failed" ]; then
  echo "失敗:$failed"
  exit 1
fi
echo "全部通った"
