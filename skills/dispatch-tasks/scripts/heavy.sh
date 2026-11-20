#!/usr/bin/env bash
# 重い処理（全体の検査・pre-commit の付いた git commit・pre-push の E2E が付いた git push）を、
# 同じリポジトリの worktree の間で1本ずつ回す。鍵は git の共通ディレクトリに置くので、別のリポジトリとは取り合わない。
# 子が同時に全体のテストを回すと時間切れで落ち、E2E は固定のポートを取り合って落ちる（2026-11-21）。
#
# 使い方: heavy.sh -l <ラベル> [-t 待つ上限の秒] -- <コマンド...>
#   例: heavy.sh -l 612 -- git push -u origin HEAD
#       heavy.sh -l 614 -- env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 git commit -F /path/to/msg
# 鍵の持ち主は <git の共通ディレクトリ>/tower-heavy.lock/owner。持ち主のプロセスが消えていれば外して取る。
set -euo pipefail

label=""
max_wait=7200
while getopts "l:t:" o; do
  case $o in
    l) label=$OPTARG ;;
    t) max_wait=$OPTARG ;;
    *) exit 2 ;;
  esac
done
shift $((OPTIND - 1))
[ "${1:-}" = "--" ] && shift
if [ -z "$label" ] || [ $# -eq 0 ]; then
  echo "使い方: heavy.sh -l <ラベル> [-t 待つ上限の秒] -- <コマンド...>" >&2
  exit 2
fi

lock="$(cd "$(git rev-parse --git-common-dir)" && pwd)/tower-heavy.lock"
waited=0
until mkdir "$lock" 2>/dev/null; do
  owner=$({ tr '\n' ' ' < "$lock/owner"; } 2>/dev/null || echo "?")
  pid=$(sed -n 's/^pid=//p' "$lock/owner" 2>/dev/null || true)
  if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
    echo "持ち主のプロセスが消えた鍵を外す: ${owner}" >&2
    rm -rf "$lock"
    continue
  fi
  if [ "$waited" -ge "$max_wait" ]; then
    echo "待ちきれなかった（${max_wait} 秒）。持ち主: ${owner}" >&2
    exit 75
  fi
  if [ $((waited % 300)) -eq 0 ]; then
    echo "鍵が空くのを待つ（${waited} 秒）。持ち主: ${owner}" >&2
  fi
  sleep 15
  waited=$((waited + 15))
done
trap 'rm -rf "$lock"' EXIT INT TERM HUP
printf 'label=%s\npid=%s\nsince=%s\ncmd=%s\n' "$label" "$$" "$(date '+%m-%d %H:%M:%S')" "$*" > "$lock/owner"
echo "鍵を取った（${label}）: $*" >&2
"$@"
