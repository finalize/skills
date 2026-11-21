#!/usr/bin/env bash
# dispatch-tasks の worktree.sh と numbers.sh。使い捨てのリポジトリと、手元の bare な origin で流す。
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$here/.." && pwd -P)
# shellcheck source=tests/lib.sh
. "$here/lib.sh"
SC=${TOWER_SCRIPTS:-$repo/skills/dispatch-tasks/scripts}

fx=$(new_tmp)
trap 'rm -rf "$fx"' EXIT
mkdir -p "$fx/tmp"
# 利用者の git の設定に左右されないようにする
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
# numbers.sh の一時ファイルも fixture の中に作らせる
export PATH="$here/fake:$PATH" FAKE_TMP="$fx/tmp"

git init -q --bare -b develop "$fx/origin.git"
git clone -q "$fx/origin.git" "$fx/app" 2>/dev/null
(
  cd "$fx/app" || exit 1
  git checkout -q -b develop 2>/dev/null
  mkdir -p specs/frontend docs/adr web/src notes
  echo x >specs/frontend/201-menu.md
  echo x >specs/frontend/202-flow.md
  echo x >docs/adr/0064-a.md
  echo x >web/src/a.ts
  echo x >notes/readme.md
  git add -A && git commit -qm init && git push -q -u origin develop
  git remote set-head origin develop >/dev/null
  # 外の作業: 別のブランチに 203 を足して push する（手元のどの worktree にも出ていない）
  git checkout -q -b other
  echo x >specs/frontend/203-outside.md
  git add -A && git commit -qm other && git push -q origin other
  git checkout -q develop && git branch -qD other
)

# --- worktree.sh
out=$(/bin/bash "$SC/worktree.sh" -r "$fx/app" -n 101 -b feat/101-menu 2>&1)
check "worktree: 終了コード" 0 "$?"
has "worktree: 既定ブランチの最新から切る" "feat/101-menu（基点 origin/develop）" "$out"
check "worktree: 兄弟のフォルダにできる" "$fx/app-101" "$(ls -d "$fx/app-101" 2>/dev/null)"
git -C "$fx/app-101" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1
check "worktree: 上流を付けない" 128 "$?"
mkdir -p "$fx/app-101/.tower" && echo d >"$fx/app-101/.tower/design.md"
check "worktree: .tower/ は git に見えない" "" "$(git -C "$fx/app-101" status --short)"

/bin/bash "$SC/worktree.sh" -r "$fx/app" -n 101 -b feat/101-menu >/dev/null 2>&1
check "worktree: 同じフォルダがあれば止まる" 1 "$?"
/bin/bash "$SC/worktree.sh" -r "$fx/app" -n 102 -b feat/101-menu >/dev/null 2>&1
check "worktree: 同じブランチがあれば止まる" 1 "$?"
/bin/bash "$SC/worktree.sh" -r "$fx/app" >/dev/null 2>&1
check "worktree: 引数が足りない" 2 "$?"

# info/exclude が改行で終わっていないとき
git init -q "$fx/app2"
(
  cd "$fx/app2" || exit 1
  git commit -q --allow-empty -m i
  git remote add origin "$fx/origin.git" && git fetch -q origin
  git remote set-head origin develop >/dev/null
  printf '*.swp' >.git/info/exclude
)
/bin/bash "$SC/worktree.sh" -r "$fx/app2" -n 9 -b feat/9 >/dev/null 2>&1
mkdir -p "$fx/app2-9/.tower" && echo d >"$fx/app2-9/.tower/design.md"
check "worktree: 改行で終わらない exclude でも .tower/ は見えない" "" "$(git -C "$fx/app2-9" status --short)"
check "worktree: もとの行を壊さない" "*.swp" "$(head -1 "$fx/app2/.git/info/exclude")"

# --- numbers.sh
echo x >"$fx/app-101/specs/frontend/204-draft.md"
out=$(cd "$fx/app-101" && /bin/bash "$SC/numbers.sh" -r . specs/frontend docs/adr 2>&1)
has "numbers: コミット前のものも数える" "specs/frontend: 最大 204（204-draft.md）→ 次は 205" "$out"
has "numbers: 桁を保つ" "docs/adr: 最大 0064（0064-a.md）→ 次は 0065" "$out"
rm "$fx/app-101/specs/frontend/204-draft.md"

want="specs/frontend: 最大 203（203-outside.md）→ 次は 204"
check "numbers: 根から。ほかのブランチの番号を数える" "$want" "$(cd "$fx/app-101" && /bin/bash "$SC/numbers.sh" -r . specs/frontend 2>&1)"
check "numbers: 下のディレクトリから -r . でも同じ答え" "$want" "$(cd "$fx/app-101/web" && /bin/bash "$SC/numbers.sh" -r . specs/frontend 2>&1)"
check "numbers: -r に下のディレクトリを渡しても同じ答え" "$want" "$(/bin/bash "$SC/numbers.sh" -r "$fx/app-101/web/src" specs/frontend 2>&1)"
check "numbers: 番号の付いたものが無い" "notes: 番号のついたものが無い" "$(cd "$fx/app-101" && /bin/bash "$SC/numbers.sh" -r . notes 2>&1)"
/bin/bash "$SC/numbers.sh" -r "$fx/app-101" >/dev/null 2>&1
check "numbers: フォルダを渡さない" 2 "$?"
check "numbers: 一時ファイルを残さない" "" "$(ls "$fx/tmp")"

finish
