#!/usr/bin/env bash
# skills/ の各スキルを ~/.claude/skills/<名前> に symlink する。
# 何度流しても同じ結果になる。入れただけのスキル（実ディレクトリ）には触らない。
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dest="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills"
mkdir -p "$dest"

# 張る
for dir in "$repo"/skills/*/; do
  dir="${dir%/}"
  [ -d "$dir" ] || continue
  name="$(basename "$dir")"
  target="$dest/$name"

  if [ -e "$target" ] && [ ! -L "$target" ]; then
    echo "skip    $name — 同じ名前の実ディレクトリがある。入れたスキルとぶつかるので触らない" >&2
    continue
  fi

  ln -sfn "$dir" "$target"
  echo "link    $name"
done

# このリポジトリを指していた symlink のうち、元が消えたものを外す
for link in "$dest"/*; do
  [ -L "$link" ] || continue
  case "$(readlink "$link")" in
    "$repo"/skills/*)
      [ -d "$link" ] && continue
      rm "$link"
      echo "unlink  $(basename "$link") — リポジトリ側から消えている"
      ;;
  esac
done
