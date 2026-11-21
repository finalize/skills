#!/usr/bin/env bash
# チケットの worktree を、origin の既定ブランチの最新から切る。上流は付けない（--no-track）。
# 使い方: worktree.sh -r <リポジトリ> -n <フォルダの接尾辞> -b <ブランチ> [-f <基点>]
#   作る場所は <本体のフォルダ>-<接尾辞>（兄弟のフォルダ。例: myapp-101）
#   基点の既定は origin/HEAD の指す先（例: origin/develop）。同じフォルダかブランチが既にあれば何もせず止まる
set -euo pipefail

repo="" name="" branch="" base=""
while getopts "r:n:b:f:" opt; do
  case $opt in
    r) repo=$OPTARG ;;
    n) name=$OPTARG ;;
    b) branch=$OPTARG ;;
    f) base=$OPTARG ;;
    *) exit 2 ;;
  esac
done
if [ -z "$repo" ] || [ -z "$name" ] || [ -z "$branch" ]; then
  sed -n '3,5p' "$0" >&2
  exit 2
fi

# どの worktree から呼ばれても、兄弟は本体（最初の worktree）の隣に作る
main=$(git -C "$repo" worktree list --porcelain | sed -n '1s/^worktree //p')
dest="${main}-${name}"

git -C "$main" fetch -q --prune origin
if [ -z "$base" ]; then
  base=$(git -C "$main" symbolic-ref -q --short refs/remotes/origin/HEAD) || {
    echo "origin/HEAD が無い。-f で基点を渡す（例: -f origin/develop）" >&2
    exit 1
  }
fi

if [ -e "$dest" ]; then
  echo "既にある: $dest" >&2
  exit 1
fi
if git -C "$main" show-ref -q --verify "refs/heads/$branch"; then
  echo "ブランチが既にある: $branch" >&2
  exit 1
fi

# --no-track: origin/develop から -b で切ると上流が develop になり、push の行き先を取り違えうる
git -C "$main" worktree add -q --no-track -b "$branch" "$dest" "$base"

# 設計の下書き（.tower/）を git に載せない。info/exclude は全部の worktree で共有され、リポジトリには残らない
exclude="$(git -C "$main" rev-parse --git-common-dir)/info/exclude"
case "$exclude" in /*) ;; *) exclude="$main/$exclude" ;; esac
mkdir -p "$(dirname "$exclude")"
# 末尾が改行で終わっていないと、前の行につながって（*.swp.tower/ のように）効かない。先に改行を足す
if [ -s "$exclude" ] && [ -n "$(tail -c1 "$exclude")" ]; then echo >>"$exclude"; fi
grep -qxF '.tower/' "$exclude" 2>/dev/null || echo '.tower/' >>"$exclude"
# 全角の文字の直前の変数は {} で囲む（bash 3.2 は続く全角を変数名の一部と読む）
echo "${dest} $(git -C "$dest" rev-parse --short HEAD) ${branch}（基点 ${base}）"
