#!/usr/bin/env bash
# 書き方の検査。スクリプトの構文と shellcheck、bash 3.2 の全角の罠、SKILL.md の frontmatter と参照先。
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$here/.." && pwd -P)
# shellcheck source=tests/lib.sh
. "$here/lib.sh"
cd "$repo" || exit 1

bash_scripts="install.sh skills/dispatch-tasks/scripts/*.sh tests/*.sh tests/fake/rex tests/fake/claude"
sh_scripts="skills/ask-codex/scripts/ask.sh tests/fake/codex tests/fake/mktemp"

# --- 構文。macOS の /bin/bash は 3.2
# shellcheck disable=SC2086 # 一覧を語に分けて、グロブも展開させる
for f in $bash_scripts; do
  if /bin/bash -n "$f" 2>/dev/null; then ok "bash -n $f"; else ng "bash -n $f"; fi
done
# shellcheck disable=SC2086
for f in $sh_scripts; do
  if /bin/sh -n "$f" 2>/dev/null; then ok "sh -n $f"; else ng "sh -n $f"; fi
done

# --- 実行権限
# shellcheck disable=SC2086
for f in $bash_scripts $sh_scripts; do
  case $f in tests/lib.sh) continue ;; esac
  if [ -x "$f" ]; then ok "実行権限 $f"; else ng "実行権限が無い: $f"; fi
done

# --- shellcheck（あれば）。警告以上が出たら落とす
if command -v shellcheck >/dev/null 2>&1; then
  # shellcheck disable=SC2086
  out=$(shellcheck -x -S warning -f gcc $bash_scripts $sh_scripts 2>&1)
  check "shellcheck（警告以上が無い）" "" "$out"
else
  echo "  飛ばす: shellcheck が無い"
fi

# --- bash 3.2 は、全角の文字の直前の $var を変数名の続きと読む（"$max（" は unbound variable で落ちた）。${var} と書く
# shellcheck disable=SC2086
out=$(perl -ne 'print "$ARGV:$.: $_" if !/^\s*#/ && /\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7F]/; close ARGV if eof' $bash_scripts $sh_scripts)
check "全角の文字の直前に、波かっこの無い変数が無い" "" "$out"

# --- SKILL.md
for d in skills/*/; do
  name=$(basename "$d")
  f="${d}SKILL.md"
  if [ ! -f "$f" ]; then
    ng "SKILL.md が無い: $name"
    continue
  fi
  check "$name: 1行目は ---" "---" "$(sed -n '1p' "$f")"
  fm=$(sed -n '2,/^---$/p' "$f")
  check "$name: name はフォルダの名前と同じ" "$name" "$(printf '%s\n' "$fm" | sed -n 's/^name:[[:space:]]*//p')"
  desc=$(printf '%s\n' "$fm" | sed -n 's/^description:[[:space:]]*//p')
  if [ -n "$desc" ]; then ok "$name: description がある"; else ng "$name: description が無い"; fi
  # Claude Code の一覧では < > が &lt; &gt; と表示される
  case $desc in
    *"<"* | *">"*) ng "$name: description に < か > がある" ;;
    *) ok "$name: description に < > が無い" ;;
  esac
  # Agent Skills の決まりは1024文字まで
  if [ "$(printf '%s' "$desc" | wc -m | tr -d ' ')" -le 1024 ]; then ok "$name: description は1024文字まで"; else ng "$name: description が長すぎる"; fi
  check "$name: 本文は500行まで" "yes" "$([ "$(wc -l <"$f")" -le 500 ] && echo yes || echo no)"
  # 本文が指す同梱のファイルがあること（`references/x.md`、`scripts/x.sh`、`${CLAUDE_SKILL_DIR}/scripts/x.sh` など）
  refs=$(grep -oE '(`|\$\{CLAUDE_SKILL_DIR\}/)(references|schemas|scripts)/[A-Za-z0-9._/-]*|`reference\.md' "$f" |
    sed -E 's/^`//; s/^\$\{CLAUDE_SKILL_DIR\}\///' | sort -u)
  for r in $refs; do
    if [ -e "$d$r" ]; then ok "$name: $r がある"; else ng "$name: 本文が指す $r が無い"; fi
  done
done

finish
