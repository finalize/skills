#!/usr/bin/env bash
# install.sh。HOME を偽物にして流す（本物の ~/.claude・~/.agents・~/.codex の symlink には触らない）。
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$here/.." && pwd -P)
# shellcheck source=tests/lib.sh
. "$here/lib.sh"
INSTALL_SRC=${INSTALL_SH:-$repo/install.sh}

fx=$(new_tmp)
trap 'rm -rf "$fx"' EXIT
home="$fx/home"
mkdir -p "$home" "$fx/repo"
cp "$INSTALL_SRC" "$fx/repo/install.sh"
cp -R "$repo/skills" "$fx/repo/skills"
all=$(cd "$repo/skills" && for d in */; do printf '%s ' "${d%/}"; done)
shared=$(cd "$repo/skills" && for d in */; do [ -e "$d/.claude-only" ] || printf '%s ' "${d%/}"; done)

# inst [環境変数=値...] : 偽物の HOME で fixture の install.sh を流す。出力は OUT
inst() { OUT=$(env -i PATH=/usr/bin:/bin HOME="$home" "$@" /bin/bash "$fx/repo/install.sh" 2>&1); }
names() { (cd "$1" 2>/dev/null && for l in *; do [ -L "$l" ] && printf '%s ' "$l"; done); }

# --- 初回
inst
check "Claude Code の置き場には全部張る" "$all" "$(names "$home/.claude/skills")"
check "共通の置き場には、Claude Code 専用のものを張らない" "$shared" "$(names "$home/.agents/skills")"
lacks "専用のものは共通の置き場に無い（ask-codex）" "ask-codex" "$(names "$home/.agents/skills")"
check "行き先はリポジトリのスキル" "$fx/repo/skills/effective-tests" "$(readlink "$home/.claude/skills/effective-tests")"
check "Codex の置き場が無ければ、プロファイルは張らない" "" "$(ls -d "$home/.codex" 2>/dev/null)"

# --- 何度流しても同じ
before=$(ls -l "$home/.claude/skills" "$home/.agents/skills" | awk '{print $9, $10, $11}')
inst
check "何度流しても同じ" "$before" "$(ls -l "$home/.claude/skills" "$home/.agents/skills" | awk '{print $9, $10, $11}')"

# --- 前の版が共通の置き場に張った、専用スキルの symlink は外す
ln -s "$fx/repo/skills/ask-codex" "$home/.agents/skills/ask-codex"
inst
has "前に張った専用スキルを外す" "unlink  ask-codex" "$OUT"
lacks "外した後は無い" "ask-codex" "$(names "$home/.agents/skills")"

# --- 同じ名前の実ディレクトリには触らない
rm "$home/.claude/skills/effective-tests"
mkdir "$home/.claude/skills/effective-tests"
echo mine >"$home/.claude/skills/effective-tests/keep"
inst
has "実ディレクトリは避けると言う" "skip    effective-tests" "$OUT"
check "実ディレクトリの中身を残す" "mine" "$(cat "$home/.claude/skills/effective-tests/keep")"
rm -r "$home/.claude/skills/effective-tests"

# --- リポジトリから消したスキルは外す
rm -r "$fx/repo/skills/ambition-upgrade"
inst
has "消したスキルを外す" "unlink  ambition-upgrade" "$OUT"
lacks "消したスキルは残らない" "ambition-upgrade" "$(names "$home/.claude/skills")"

# --- 人が張った、切れた symlink には触らない
ln -s "$fx/nowhere/other-tool" "$home/.claude/skills/someone-elses"
inst
has "関係ない切れた symlink は残す" "someone-elses" "$(names "$home/.claude/skills")"
rm "$home/.claude/skills/someone-elses"

# --- リポジトリを移した後。古い場所を指して切れた symlink を外す
mv "$fx/repo" "$fx/repo-moved"
rm -r "$fx/repo-moved/skills/fix-with-evidence"
OUT=$(env -i PATH=/usr/bin:/bin HOME="$home" /bin/bash "$fx/repo-moved/install.sh" 2>&1)
has "移す前の古い symlink を外す" "unlink  fix-with-evidence" "$OUT"
lacks "古い symlink は残らない" "fix-with-evidence" "$(names "$home/.claude/skills")"
check "残りは新しい場所を指す" "$fx/repo-moved/skills/effective-tests" "$(readlink "$home/.claude/skills/effective-tests")"
mv "$fx/repo-moved" "$fx/repo"

# --- CLAUDE_CONFIG_DIR
inst CLAUDE_CONFIG_DIR="$fx/cfg"
has "CLAUDE_CONFIG_DIR の下に張る" "effective-tests" "$(names "$fx/cfg/skills")"

# --- Codex のプロファイル
mkdir "$home/.codex"
inst
check "Codex の置き場があれば、プロファイルを張る" "$fx/repo/skills/ask-codex/claude.config.toml" "$(readlink "$home/.codex/claude.config.toml")"
rm "$home/.codex/claude.config.toml"
echo "# 手で置いた写し" >"$home/.codex/claude.config.toml"
inst
has "実ファイルがあれば知らせる" "skip    claude.config.toml" "$OUT"
check "実ファイルは上書きしない" "# 手で置いた写し" "$(cat "$home/.codex/claude.config.toml")"
rm "$home/.codex/claude.config.toml"
ln -s "$fx/nowhere.toml" "$home/.codex/claude.config.toml"
inst
check "切れた symlink は張り直す" "$fx/repo/skills/ask-codex/claude.config.toml" "$(readlink "$home/.codex/claude.config.toml")"

finish
