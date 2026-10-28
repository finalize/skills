#!/bin/sh
# Claude Code から Codex に1回聞いて、最終回答だけを標準出力に返す。
# 使い方: ask.sh [-e 努力度] [-w] [-C ディレクトリ] [-k] [プロンプト]
#   -e  model_reasoning_effort を上書き (low|medium|high|xhigh)。既定はプロファイルの xhigh
#   -w  workspace-write で実行する。省略時は read-only
#   -C  作業ディレクトリ。既定は現在地
#   -k  セッションを残す (あとで `codex exec resume` で続けるとき)
#   -S  最終回答の形を JSON Schema で縛る (schemas/ に反論用がある)
#   プロンプトを省略するか - を渡すと、標準入力から読む
set -eu

effort=""
sandbox=""
dir="."
keep=""
schema=""
while getopts "e:wC:kS:" opt; do
  case $opt in
    S) schema=$OPTARG ;;
    e) effort=$OPTARG ;;
    w) sandbox="workspace-write" ;;
    C) dir=$OPTARG ;;
    k) keep=1 ;;
    *) exit 2 ;;
  esac
done
shift $((OPTIND - 1))
prompt=${1:--}

profile="${CODEX_HOME:-$HOME/.codex}/claude.config.toml"
if [ ! -e "$profile" ]; then
  skill_dir=$(cd "$(dirname "$0")/.." && pwd -P)
  echo "Codex のプロファイルがない。次で張ってから、もう一度呼ぶ:" >&2
  echo "  ln -s \"$skill_dir/claude.config.toml\" \"$profile\"" >&2
  exit 1
fi

out=$(mktemp -t codex-ask.XXXXXX)
log="$out.log"

set -- exec -p claude -C "$dir" -o "$out"
if [ -n "$effort" ]; then set -- "$@" -c "model_reasoning_effort=\"$effort\""; fi
if [ -n "$sandbox" ]; then set -- "$@" -s "$sandbox"; else set -- "$@" --skip-git-repo-check; fi
if [ -z "$keep" ]; then set -- "$@" --ephemeral; fi
if [ -n "$schema" ]; then set -- "$@" --output-schema "$schema"; fi

# プロンプトを引数で渡すとき、標準入力が開いたままだと codex は EOF を待って止まる。
if [ "$prompt" = "-" ]; then
  codex "$@" - >"$log" 2>&1 || status=$?
else
  codex "$@" "$prompt" >"$log" 2>&1 </dev/null || status=$?
fi

if [ "${status:-0}" -ne 0 ]; then
  echo "codex が失敗した (終了コード ${status})。ログ: $log" >&2
  tail -20 "$log" >&2
  rm -f "$out"
  exit "$status"
fi
cat "$out"
# -o のファイルは末尾に改行が付かないので足す
if [ -n "$(tail -c1 "$out")" ]; then echo; fi
rm -f "$out" "$log"
