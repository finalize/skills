#!/usr/bin/env bash
# skills/ の各スキルを、各エージェントが読む場所に symlink する。
# 何度流しても同じ結果になる。入れただけのスキル（実ディレクトリ）には触らない。
#   .claude-only を置いたスキル（Claude Code が前提のもの）は、~/.agents/skills には張らない
#   ask-codex のプロファイルを、Codex の置き場（~/.codex）から張る。実ファイルがあれば触らずに知らせる
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ~/.claude は Claude Code（Cursor も、互換のためにここを読む）。
# ~/.agents は Agent Skills 標準の共通の置き場で、Codex・Cursor・Gemini CLI が読む。
claude_dest="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills"
agents_dest="$HOME/.agents/skills"

for dest in "$claude_dest" "$agents_dest"; do
  mkdir -p "$dest"
  echo "→ $dest"

  # 張る
  for dir in "$repo"/skills/*/; do
    dir="${dir%/}"
    [ -d "$dir" ] || continue
    name="$(basename "$dir")"
    target="$dest/$name"

    if [ "$dest" = "$agents_dest" ] && [ -e "$dir/.claude-only" ]; then
      # 前に張ったものが残っていれば外す（このリポジトリを指す symlink だけ）
      if [ -L "$target" ] && [ "$(readlink "$target")" = "$dir" ]; then
        rm "$target"
        echo "  unlink  $name — Claude Code 専用（.claude-only）なので、ここには張らない"
      fi
      continue
    fi

    if [ -e "$target" ] && [ ! -L "$target" ]; then
      echo "  skip    $name — 同じ名前の実ディレクトリがある。入れたスキルとぶつかるので触らない" >&2
      continue
    fi

    ln -sfn "$dir" "$target"
    echo "  link    $name"
  done

  # 行き先が消えた symlink を外す。外すのは次の2つだけ
  #   このリポジトリを指していたもの（スキルを消した）
  #   リポジトリを別の場所へ移す前に張ったもの（どこかの skills/<同じ名前> を指して切れている）
  for link in "$dest"/*; do
    [ -L "$link" ] || continue
    [ -e "$link" ] && continue
    case "$(readlink "$link")" in
      "$repo"/skills/*) reason="リポジトリ側から消えている" ;;
      */skills/"$(basename "$link")") reason="行き先が無い（リポジトリを移す前の古い symlink）" ;;
      *) continue ;;
    esac
    rm "$link"
    echo "  unlink  $(basename "$link") — $reason"
  done
done

# ask-codex のプロファイル。Codex が入っているとき（置き場があるとき）だけ張る
codex_home="${CODEX_HOME:-$HOME/.codex}"
profile_src="$repo/skills/ask-codex/claude.config.toml"
profile="$codex_home/claude.config.toml"
if [ -f "$profile_src" ] && [ -d "$codex_home" ]; then
  echo "→ $codex_home"
  if [ -e "$profile" ] && [ ! -L "$profile" ]; then
    echo "  skip    claude.config.toml — 実ファイルがある。中身を見て、消してから流し直す（張り直すまで、リポジトリの決まりは使われない）" >&2
  else
    ln -sfn "$profile_src" "$profile"
    echo "  link    claude.config.toml"
  fi
fi
