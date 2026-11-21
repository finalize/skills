#!/bin/sh
# Claude Code から Codex に1回聞いて、最終回答だけを標準出力に返す。
# 使い方: ask.sh [-e 努力度] [-w] [-C ディレクトリ] [-k] [-S スキーマ] [プロンプト]
#   -e  model_reasoning_effort を上書き (low|medium|high|xhigh|max)。既定はプロファイルの max
#   -w  作業ディレクトリに書ける権限 (プロファイルの claude-write) で実行する。省略時は読むだけ (claude-read)
#   -C  作業ディレクトリ。既定は現在地
#   -k  セッションを残す (あとで続けるとき)。続け方を標準エラーに出す
#   -S  最終回答の形を JSON Schema で縛る。名前 (objections・report) か、ファイルの場所
#   プロンプトを省略するか - を渡すと、標準入力から読む。オプションはプロンプトの前に書く (後ろの引数は受け付けない)
# 終わると、Codex が使ったトークンを標準エラーに1行出し、
# ${XDG_STATE_HOME:-~/.local/state}/ask-codex/usage.tsv に1行足す (失敗したときも)。
# 記録に失敗しても、回答と終了コードは変えない。
set -eu
umask 077

usage() { sed -n '3,9p' "$0" >&2; }

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
    *)
      usage
      exit 2
      ;;
  esac
done
shift $((OPTIND - 1))
# プロンプトの後ろに書いたオプションは、getopts が読まない。黙って捨てると、-C や -w が効かないまま走る
if [ $# -gt 1 ]; then
  echo "プロンプトの後ろに引数がある: $2 (オプションはプロンプトの前に書く。プロンプトは1つ)" >&2
  usage
  exit 2
fi
prompt=${1:--}

skill_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
codex_home="${CODEX_HOME:-${HOME:-}/.codex}"
profile="$codex_home/claude.config.toml"
base="$codex_home/config.toml"
if [ ! -e "$profile" ]; then
  echo "Codex のプロファイルがない (symlink の行き先が消えている場合も含む)。次で張り直してから、もう一度呼ぶ:" >&2
  echo "  ln -sfn \"$skill_dir/claude.config.toml\" \"$profile\"" >&2
  exit 1
fi
if ! abs_dir=$(CDPATH='' cd -- "$dir" 2>/dev/null && pwd -P); then
  echo "作業ディレクトリが無い: $dir" >&2
  exit 2
fi
if [ -n "$schema" ]; then
  case $schema in
    */* | *.json) ;;
    *) schema="$skill_dir/schemas/$schema.json" ;;
  esac
  # schemas/report.json のような、スキルのディレクトリからの相対も受ける
  if [ ! -f "$schema" ] && [ -f "$skill_dir/$schema" ]; then schema="$skill_dir/$schema"; fi
  if [ ! -f "$schema" ]; then
    echo "スキーマが無い: $schema (名前で渡すなら objections か report)" >&2
    exit 2
  fi
  schema="$(CDPATH='' cd -- "$(dirname -- "$schema")" && pwd -P)/$(basename -- "$schema")"
fi
for tool in codex jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool が無い (jq は、切る MCP の一覧を読むのに要る)" >&2
    exit 127
  fi
done

# 読めなくする決まりが効かなくなる呼び方と設定があれば、呼ばずに止まる。確かめられないときも止まる。
# 1) 場所で読めなくしたディレクトリの中を作業ディレクトリにすると、その中が読める (-w なら書ける) ようになる
# 2) sandbox_mode がどこかの設定にあると、Codex は permissions を使わず古い設定に切り替わる
# 3) ほかの設定 (リポジトリの .codex/config.toml など) が、このプロファイルの permissions を書き換えられる
# 4) MCP とプラグインは、読めなくする決まりの外で動く。Codex から見えるものは全部切る
# 設定は TOML として読まず、行で探す。書き方の揺れ (引用符、ドットのキー) は拾い、迷う書き方は止める側に倒す
# 呼ぶのはたいてい Claude。止まった理由を消すために、Claude が自分で設定を書き換えないように言い添える
handoff="(Claude へ: 設定やプロファイルを自分で書き換えない。この理由を利用者に伝えて、判断を待つ)"
stop() {
  echo "止めた: $1" >&2
  echo "$handoff" >&2
  exit 1
}
lower() { printf '%s/' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]'; }

# 1) 場所 (~/ か / で始まり、* を含まない) の deny。プロファイルと、公開しない土台の設定 (案件ごとの場所) の両方から読む
deny_re="s/^[[:space:]]*[\"']((~\\/|\\/)[^\"'*]*)[\"'][[:space:]]*=[[:space:]]*[\"']deny[\"'].*/\\1/p"
denied_dirs=$(sed -nE "$deny_re" "$profile") || stop "$profile を読めない"
[ -n "$denied_dirs" ] || stop "$profile から、場所で読めなくしたディレクトリを読み取れない"
if [ -f "$base" ]; then
  more_dirs=$(sed -nE "$deny_re" "$base") || stop "$base を読めない"
  denied_dirs="$denied_dirs
$more_dirs"
fi
abs_lower=$(lower "$abs_dir")
while IFS= read -r d; do
  [ -n "$d" ] || continue
  # shellcheck disable=SC2088 # 設定に書かれた文字どおりの ~/ と比べている (シェルに展開させたいのではない)
  case $d in "~/"*) d="${HOME:-}/${d#\~/}" ;; esac
  d=${d%/}
  # シンボリックリンクを含むなら、作業ディレクトリと同じく実体のパスで比べる
  if p=$(CDPATH='' cd -- "$d" 2>/dev/null && pwd -P); then d=$p; fi
  case "$abs_lower" in
    "$(lower "$d")"*) stop "作業ディレクトリ $abs_dir は、読めなくした $d の中にある" ;;
  esac
done <<LIST
$denied_dirs
LIST

# 2)〜4)。コメントの行は除いて探す
found() { # $1 のパターンが、設定 $2 のコメントでない行にあれば 0、無ければ 1
  body=$(sed '/^[[:space:]]*#/d' "$2") || stop "$2 を読めない"
  rc=0
  printf '%s\n' "$body" | grep -Eq "$1" || rc=$?
  [ "$rc" -le 1 ] || stop "$2 を確かめられない (grep の終了コード $rc)"
  return "$rc"
}
sandbox_mode_re="sandbox_mode[\"']?[[:space:]]*="

# プロファイル自身
if found "$sandbox_mode_re" "$profile"; then
  stop "$profile に sandbox_mode がある。あると、プロファイルの読めなくする決まりが効かない"
fi

# 土台の設定 (~/.codex/config.toml)。claude-read の filesystem の表に deny の行を足すのは通す
# (公開しない、案件ごとの場所の置き場)。それ以外の形で claude-read / claude-write に触れていたら止まる
if [ -f "$base" ]; then
  if found "$sandbox_mode_re" "$base"; then
    stop "$base に sandbox_mode がある。あると、プロファイルの読めなくする決まりが効かない"
  fi
  touched=$(awk '
    /^[ \t]*#/ || /^[ \t]*$/ { next }
    /^[ \t]*\[/ {
      intab = 0
      if ($0 ~ /claude-(read|write)/) {
        if ($0 ~ /^[ \t]*\[[ \t]*permissions\.claude-read\.filesystem(\.|\])/) intab = 1
        else { print; exit }
      }
      next
    }
    intab {
      if ($0 !~ /=[ \t]*["\047]deny["\047][ \t]*(#.*)?$/) { print; exit }
      next
    }
    /claude-(read|write)/ { print; exit }
  ' "$base") || stop "$base を確かめられない"
  if [ -n "$touched" ]; then
    stop "$base が、プロファイルの permissions に deny を足す以外の形で触れている: $touched"
  fi
fi

# リポジトリの設定と /etc/codex の設定。Codex は、信頼したプロジェクトなら、根から作業ディレクトリまでの
# 全部の .codex/config.toml を読む。だから -C から根まで、間のディレクトリも全部見る
mcp_names_from() { # 設定 $1 が定義する MCP の名前を1行ずつ。読み取れない書き方があれば止まる
  body=$(sed '/^[[:space:]]*#/d' "$1") || stop "$1 を読めない"
  lines=$(printf '%s\n' "$body" | grep -E '(^|[^A-Za-z0-9_])mcp_servers([^A-Za-z0-9_]|$)' || true)
  [ -n "$lines" ] || return 0
  bad=$(printf '%s\n' "$lines" | grep -Ev '^[[:space:]]*(\[+[[:space:]]*)?mcp_servers\.[A-Za-z0-9_-]+([].[:space:]=]|$)' || true)
  [ -z "$bad" ] || stop "$1 の MCP の書き方を読み取れない: $(printf '%s\n' "$bad" | head -1)"
  printf '%s\n' "$lines" | sed -E 's/^[[:space:]]*(\[+[[:space:]]*)?mcp_servers\.([A-Za-z0-9_-]+).*/\2/' | sort -u
}
proj_mcp=""
check_other() {
  [ -f "$1" ] || return 0
  if found "$sandbox_mode_re" "$1"; then
    stop "$1 に sandbox_mode がある。あると、プロファイルの読めなくする決まりが効かない"
  fi
  if found 'claude-(read|write)' "$1"; then
    stop "$1 が、プロファイルの permissions (claude-read / claude-write) に触れている"
  fi
  if found '(^|[^A-Za-z0-9_])plugins([^A-Za-z0-9_]|$)' "$1"; then
    stop "$1 がプラグインに触れている。プラグインは読めなくする決まりの外で動き、コマンドラインから切れるのを確かめられていない"
  fi
  # MCP は名前を控えておき、下で Codex の一覧と突き合わせてから切る
  more_mcp=$(mcp_names_from "$1") || exit 1
  proj_mcp="$proj_mcp
$more_mcp"
}
repo_root=$(git -C "$abs_dir" rev-parse --show-toplevel 2>/dev/null || true)
d=$abs_dir
while :; do
  # CODEX_HOME そのものは土台の設定で、上で見た
  if [ "$d/.codex" != "$codex_home" ]; then check_other "$d/.codex/config.toml"; fi
  if [ -z "$repo_root" ] || [ "$d" = "$repo_root" ] || [ "$d" = "/" ]; then break; fi
  d=$(dirname "$d")
done
check_other /etc/codex/config.toml
check_other /etc/codex/managed_config.toml

# 4) プラグイン。土台の設定で有効なもののうち、プロファイルが切っていないものがあれば止まる
#    (コマンドラインから切れるのを確かめられなかったので、プロファイルに足してもらう)
plugins_in() { # 設定 $1 の [plugins."名前"] のうち、$2 が off なら enabled = false のもの、on ならそれ以外を1行ずつ
  awk -v want="$2" '
    function flush() {
      if (name != "" && ((want == "off" && off) || (want == "on" && !off))) print name
      name = ""; off = 0
    }
    BEGIN {
      q = "[\"\047]"
      pre = "^[ \t]*\\[[ \t]*plugins\\."
      # [plugins."名前"] そのものだけを数える。[plugins."名前".何か] のような下の表は数えない
      exact = pre "(" q "[^\"\047]+" q "|[A-Za-z0-9_@-]+)[ \t]*\\][ \t]*(#.*)?$"
    }
    /^[ \t]*#/ { next }
    /^[ \t]*\[/ {
      flush()
      if ($0 ~ exact) {
        s = $0
        sub(pre, "", s); sub("[ \t]*\\].*$", "", s); gsub(q, "", s)
        name = s
      }
      next
    }
    name != "" && /^[ \t]*enabled[ \t]*=[ \t]*false/ { off = 1 }
    END { flush() }
  ' "$1"
}
if [ -f "$base" ]; then
  if found '^[[:space:]]*plugins[.[:space:]=]' "$base"; then
    stop "$base のプラグインの書き方を読み取れない ([plugins.\"名前\"] の表で書く)"
  fi
  on_plugins=$(plugins_in "$base" on) || stop "$base を確かめられない"
  off_plugins=$(plugins_in "$profile" off) || stop "$profile を確かめられない"
  missing=""
  for name in $on_plugins; do
    printf '%s\n' "$off_plugins" | grep -Fxq -- "$name" || missing="$missing $name"
  done
  if [ -n "$missing" ]; then
    echo "止めた: $base で有効なプラグインを、プロファイルが切っていない。$profile に次を足す:" >&2
    for name in $missing; do printf '  [plugins."%s"]\n  enabled = false\n' "$name" >&2; done
    echo "$handoff" >&2
    exit 1
  fi
fi

# 4) MCP。Codex から見える MCP を全部切る。プロファイルに名前で書くと、その MCP が無い環境では
#    「invalid transport」で落ちるので、呼び出しのたびに一覧を取って、あるものだけ切る。
#    一覧は、exec と同じプロファイルを付けて取る。付けないと、プロファイルが切ったプラグインの MCP も一覧に出て、
#    exec から見えないその MCP を切ろうとして、同じ「invalid transport」で落ちる (2026-11-21、cua_repl)
if ! mcp_json=$(cd "$abs_dir" && codex -p claude mcp list --json 2>/dev/null </dev/null); then
  stop "codex -p claude mcp list --json が失敗した (切る MCP の一覧を取れない)。codex -p claude mcp list を手で流して原因を見る"
fi
if ! mcp_all=$(printf '%s' "$mcp_json" | jq -r 'if type == "array" then .[].name else error("not an array") end' 2>/dev/null); then
  stop "codex -p claude mcp list --json の出力を読み取れない (切る MCP の一覧を取れない)"
fi
mcp_names=$(printf '%s' "$mcp_json" | jq -r '.[] | select(.enabled != false) | .name' 2>/dev/null) ||
  stop "codex -p claude mcp list --json の出力を読み取れない (切る MCP の一覧を取れない)"
for name in $mcp_names; do
  case $name in
    *[!A-Za-z0-9_-]*) stop "MCP の名前 $name を、コマンドラインから切れない (英数字と _ - 以外を含む)" ;;
  esac
done
# リポジトリの設定が定義する MCP は、プロジェクトが信頼されていれば一覧に出る (出たものは上でまとめて切る)。
# 一覧に出ないなら、いまは読まれていない。ただ、走っている間に信頼されて有効になるかを確かめられないので止まる
for name in $proj_mcp; do
  printf '%s\n' "$mcp_all" | grep -Fxq -- "$name" ||
    stop "リポジトリの設定が MCP ($name) を定義しているが、codex -p claude mcp list に出ない。プロジェクトが信頼されていないと一覧に出ず、切れない (利用者が Codex でプロジェクトを信頼するか、定義を外すと通る)"
done

out=$(mktemp -t codex-ask.XXXXXX)
log="$out.log"
events="$out.events.jsonl"

# 読み書きの範囲は、プロファイルの permissions で決める。-s (--sandbox) を渡すと古い設定に切り替わり、
# プロファイルに書いた「読めなくする決まり」が効かなくなるので、渡さない。
set -- exec -p claude -C "$abs_dir" -o "$out" --json -c "default_permissions=\"$perm\""
for name in $mcp_names; do set -- "$@" -c "mcp_servers.$name.enabled=false"; done
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

# 失敗の中身を出す。ログとイベントは残す
show_failure() {
  echo "$1 ログ: $log 、イベント: $events" >&2
  tail -20 "$log" >&2 || true
  jq -Rrn '[inputs | fromjson? | select(type == "object" and (.type == "error" or .type == "turn.failed")) | (.message // .error.message // empty)] | .[-3:] | .[]' "$events" >&2 2>/dev/null || true
  rm -f "$out"
}

if [ "$status" -ne 0 ]; then
  show_failure "codex が失敗した (終了コード ${status})。"
  exit "$status"
fi
# 終了コードが 0 でも、最終回答が書かれていないことがある。空のまま成功にすると、呼んだ側は「指摘なし」と読む
if [ ! -s "$out" ]; then
  show_failure "codex は終了コード 0 だが、最終回答が空だった。"
  exit 1
fi
cat "$out"
# -o のファイルは末尾に改行が付かないので足す
if [ -n "$(tail -c1 "$out")" ]; then echo; fi
rm -f "$out" "$log" "$events"
