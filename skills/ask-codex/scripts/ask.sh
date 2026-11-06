#!/bin/sh
# Claude Code から Codex に1回聞いて、最終回答だけを標準出力に返す。
# 使い方: ask.sh [-e 努力度] [-w] [-C ディレクトリ] [-k] [-S スキーマ] [プロンプト]
#   -e  model_reasoning_effort を上書き (low|medium|high|xhigh|max)。既定はプロファイルの max
#   -w  作業ディレクトリに書ける権限 (プロファイルの claude-write) で実行する。省略時は読むだけ (claude-read)
#   -C  作業ディレクトリ。既定は現在地
#   -k  セッションを残す (あとで続けるとき)。続け方を標準エラーに出す
#   -S  最終回答の形を JSON Schema で縛る (schemas/ に反論用と報告用がある)
#   プロンプトを省略するか - を渡すと、標準入力から読む
# 終わると、Codex が使ったトークンを標準エラーに1行出し、
# ${XDG_STATE_HOME:-~/.local/state}/ask-codex/usage.tsv に1行足す (失敗したときも)。
# 記録に失敗しても、回答と終了コードは変えない。
set -eu
umask 077

effort=""
perm="claude-read"
dir="."
keep=""
schema=""
while getopts "e:wC:kS:" opt; do
  case $opt in
    S) schema=$OPTARG ;;
    e) effort=$OPTARG ;;
    w) perm="claude-write" ;;
    C) dir=$OPTARG ;;
    k) keep=1 ;;
    *) exit 2 ;;
  esac
done
shift $((OPTIND - 1))
prompt=${1:--}

codex_home="${CODEX_HOME:-${HOME:-}/.codex}"
profile="$codex_home/claude.config.toml"
if [ ! -e "$profile" ]; then
  skill_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
  echo "Codex のプロファイルがない。次で張ってから、もう一度呼ぶ:" >&2
  echo "  ln -s \"$skill_dir/claude.config.toml\" \"$profile\"" >&2
  exit 1
fi
if ! abs_dir=$(CDPATH='' cd -- "$dir" 2>/dev/null && pwd -P); then
  echo "作業ディレクトリが無い: $dir" >&2
  exit 2
fi

# 読めなくする決まりが効かなくなる呼び方と設定があれば、呼ばずに止まる。確かめられないときも止まる。
# 1) 場所で読めなくしたディレクトリの中を作業ディレクトリにすると、その中が読める (-w なら書ける) ようになる
# 2) sandbox_mode がどこかの設定にあると、Codex は permissions を使わず古い設定に切り替わる
# 3) ほかの設定 (リポジトリの .codex/config.toml など) が、このプロファイルの permissions を書き換えられる
# 設定は TOML として読まず、行で探す。書き方の揺れ (引用符、ドットのキー) は拾い、迷う書き方は止める側に倒す
stop() {
  echo "止めた: $1" >&2
  exit 1
}
lower() { printf '%s/' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]'; }

# 1) プロファイルの、場所 (~/ か / で始まり、* を含まない) の deny
denied_dirs=$(sed -nE "s/^[[:space:]]*[\"']((~\\/|\\/)[^\"'*]*)[\"'][[:space:]]*=[[:space:]]*[\"']deny[\"'].*/\\1/p" "$profile") ||
  stop "$profile を読めない"
[ -n "$denied_dirs" ] || stop "$profile から、場所で読めなくしたディレクトリを読み取れない"
abs_lower=$(lower "$abs_dir")
while IFS= read -r d; do
  [ -n "$d" ] || continue
  case $d in "~/"*) d="${HOME:-}/${d#\~/}" ;; esac
  d=${d%/}
  # シンボリックリンクを含むなら、作業ディレクトリと同じく実体のパスで比べる
  if p=$(CDPATH='' cd -- "$d" 2>/dev/null && pwd -P); then d=$p; fi
  case "$abs_lower" in
    "$(lower "$d")"*) stop "作業ディレクトリ $abs_dir は、プロファイルで読めなくした $d の中にある" ;;
  esac
done <<LIST
$denied_dirs
LIST

# 2) と 3)。コメントの行は除いて探す
found() { # $1 のパターンが、設定 $2 のコメントでない行にあれば 0、無ければ 1
  body=$(sed '/^[[:space:]]*#/d' "$2") || stop "$2 を読めない"
  rc=0
  printf '%s\n' "$body" | grep -Eq "$1" || rc=$?
  [ "$rc" -le 1 ] || stop "$2 を確かめられない (grep の終了コード $rc)"
  return "$rc"
}
repo_root=$(git -C "$abs_dir" rev-parse --show-toplevel 2>/dev/null || true)
for conf in "$codex_home/config.toml" "$profile" "$abs_dir/.codex/config.toml" ${repo_root:+"$repo_root/.codex/config.toml"}; do
  [ -f "$conf" ] || continue
  if found "sandbox_mode[\"']?[[:space:]]*=" "$conf"; then
    stop "$conf に sandbox_mode がある。あると、プロファイルの読めなくする決まりが効かない"
  fi
  if [ "$conf" != "$profile" ] && found 'claude-(read|write)' "$conf"; then
    stop "$conf が、プロファイルの permissions (claude-read / claude-write) に触れている"
  fi
done

out=$(mktemp -t codex-ask.XXXXXX)
log="$out.log"
events="$out.events.jsonl"

# 読み書きの範囲は、プロファイルの permissions で決める。-s (--sandbox) を渡すと古い設定に切り替わり、
# プロファイルに書いた「読めなくする決まり」が効かなくなるので、渡さない。
set -- exec -p claude -C "$abs_dir" -o "$out" --json -c "default_permissions=\"$perm\""
if [ -n "$effort" ]; then set -- "$@" -c "model_reasoning_effort=\"$effort\""; fi
if [ "$perm" = "claude-read" ]; then set -- "$@" --skip-git-repo-check; fi
if [ -z "$keep" ]; then set -- "$@" --ephemeral; fi
if [ -n "$schema" ]; then set -- "$@" --output-schema "$schema"; fi

start=$(date +%s)
status=0
# プロンプトを引数で渡すとき、標準入力が開いたままだと codex は EOF を待って止まる。
if [ "$prompt" = "-" ]; then
  codex "$@" - >"$events" 2>"$log" || status=$?
else
  codex "$@" "$prompt" >"$events" 2>"$log" </dev/null || status=$?
fi
seconds=$(($(date +%s) - start))

# 使ったトークンを数えて、出して、記録する。ここで何が失敗しても、回答と終了コードは変えない
record_usage() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "[ask-codex] jq が無いので、トークンを数えられない" >&2
    return 0
  fi
  # turn.completed の usage を足す。1つも無ければ (途中で落ちた、イベントが壊れている) 数は不明
  line=$(jq -Rrn '
    def n: if type == "number" then . else 0 end;
    [inputs | fromjson? | select(type == "object" and .type == "turn.completed") | (.usage // {})]
    | [ length,
        (map(.input_tokens | n) | add // 0),
        (map(.cached_input_tokens | n) | add // 0),
        (map(.output_tokens | n) | add // 0),
        (map(.reasoning_output_tokens | n) | add // 0) ]
    | map(tostring) | join(" ")' "$events" 2>/dev/null) || line=""
  turns=0 input="" cached="" output="" reasoning=""
  if [ -n "$line" ]; then
    read -r turns input cached output reasoning <<EOF
$line
EOF
  fi
  if [ "${turns:-0}" -gt 0 ] 2>/dev/null; then
    echo "[ask-codex] トークン: 入力 $input (うちキャッシュ $cached)、出力 $output (うち推論 $reasoning)、${seconds} 秒" >&2
  else
    input="" cached="" output="" reasoning=""
    echo "[ask-codex] トークン: 数えられない (完了したターンの記録が無い)、${seconds} 秒" >&2
  fi
  state="${XDG_STATE_HOME:-${HOME:-}/.local/state}/ask-codex"
  tsv="$state/usage.tsv"
  if ! {
    mkdir -p "$state" &&
      { [ -s "$tsv" ] || printf 'time\tdir\tpermissions\teffort\tstatus\tseconds\tinput\tcached_input\toutput\treasoning_output\n' >>"$tsv"; } &&
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$abs_dir" "$perm" "${effort:-default}" "$status" "$seconds" \
        "$input" "$cached" "$output" "$reasoning" >>"$tsv"
  } 2>/dev/null; then
    echo "[ask-codex] トークンを $tsv に記録できなかった" >&2
  fi
  if [ -n "$keep" ]; then
    thread=$(jq -Rrn '[inputs | fromjson? | select(type == "object" and .type == "thread.started") | .thread_id] | first // empty' "$events" 2>/dev/null) || thread=""
    if [ -n "$thread" ]; then
      echo "[ask-codex] 続けるとき: codex exec -p claude -C \"$abs_dir\" -c 'default_permissions=\"$perm\"' resume $thread \"<プロンプト>\" </dev/null" >&2
    fi
  fi
  return 0
}
record_usage || true

if [ "$status" -ne 0 ]; then
  echo "codex が失敗した (終了コード ${status})。ログ: $log 、イベント: $events" >&2
  tail -20 "$log" >&2 || true
  if command -v jq >/dev/null 2>&1; then
    jq -Rrn '[inputs | fromjson? | select(type == "object" and (.type == "error" or .type == "turn.failed")) | (.message // .error.message // empty)] | .[-3:] | .[]' "$events" >&2 2>/dev/null || true
  fi
  rm -f "$out"
  exit "$status"
fi
cat "$out"
# -o のファイルは末尾に改行が付かないので足す
if [ -n "$(tail -c1 "$out")" ]; then echo; fi
rm -f "$out" "$log" "$events"
