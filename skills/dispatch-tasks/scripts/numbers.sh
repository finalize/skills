#!/usr/bin/env bash
# 番号で始まるフォルダ・ファイル（spec・ADR など）の、今いちばん大きい番号と次の番号を出す。
# 使い方: numbers.sh -r <リポジトリ> <フォルダ>...   例: numbers.sh -r . specs/frontend specs/backend docs/adr
#   origin を fetch した後の全部のブランチの履歴と、全部の worktree のコミット前のものを見る
#   出るのは目安。司令塔の外のセッションも同じ番号を取りにいくので、作る直前にもう一度流す
#   <フォルダ> はリポジトリの根からの道で書く。-r はリポジトリの中ならどこでもよい（根に寄せる）
set -euo pipefail

repo="."
while getopts "r:" opt; do
  case $opt in
    r) repo=$OPTARG ;;
    *) exit 2 ;;
  esac
done
shift $((OPTIND - 1))
if [ $# -eq 0 ]; then
  sed -n '3,6p' "$0" >&2
  exit 2
fi

# 根に寄せる。下のディレクトリのまま git log に道を渡すと、現在地からの相対と読まれて履歴の分が丸ごと抜け、
# 使用済みの番号を「次」と返す（終了コードは 0 のまま）
repo=$(git -C "$repo" rev-parse --show-toplevel)

git -C "$repo" fetch -q --prune origin

dirs=()
for d in "$@"; do dirs+=("${d%/}/"); done

all=$(mktemp -t tower-numbers.XXXXXX)
trap 'rm -f "$all"' EXIT
# ブランチごとに ls-tree すると ref が数百あって20秒かかる。履歴を1回なめれば0.3秒で済む。
# 付け替えて消えた番号も「使った」に数える（取り直さない方が安全）
git -C "$repo" log --all --format= --name-only -- "${dirs[@]}" >>"$all"
git -C "$repo" worktree list --porcelain | sed -n 's/^worktree //p' |
  while IFS= read -r wt; do
    for d in "${dirs[@]}"; do
      [ -d "$wt/$d" ] || continue
      ls "$wt/$d" | sed "s#^#$d#"
    done
  done >>"$all"

for d in "${dirs[@]}"; do
  names=$(grep -F "$d" "$all" | sed "s#^$d##; s#/.*##" | grep -E '^[0-9]+' | sort -u || true)
  if [ -z "$names" ]; then
    echo "${d%/}: 番号のついたものが無い"
    continue
  fi
  max=$(printf '%s\n' "$names" | grep -oE '^[0-9]+' | sort -n | tail -1)
  next=$(printf "%0${#max}d" $((10#$max + 1)))
  top=$(printf '%s\n' "$names" | grep -E "^${max}([^0-9]|$)" | tr '\n' ' ')
  echo "${d%/}: 最大 ${max}（${top% }）→ 次は ${next}"
done
