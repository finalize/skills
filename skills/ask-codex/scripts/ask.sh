#!/bin/sh
# Claude Code から Codex に1回聞いて、最終回答だけを標準出力に返す。
# 使い方: ask.sh [-e 努力度] [-w] [-C ディレクトリ] [-k] [-r セッション] [-S スキーマ] [プロンプト]
#   -e  model_reasoning_effort を上書き (low|medium|high|xhigh|max)。既定はプロファイルの max
#   -w  作業ディレクトリに書ける権限 (プロファイルの claude-write) で実行する。省略時は読むだけ (claude-read)
#   -C  作業ディレクトリ。既定は現在地
#   -k  セッションを残す (あとで続けるとき)。続け方を標準エラーに出す
#   -r  -k で残したセッションを続ける。渡すのは、続け方に出た名前 (UUID)。-e・-w・-C は引き継がないので、付け直す
#   -S  最終回答の形を JSON Schema で縛る。名前 (objections・report) か、ファイルの場所
#   プロンプトを省略するか - を渡すと、標準入力から読む。オプションはプロンプトの前に書く (後ろの引数は受け付けない)
# 終わると、Codex が使ったトークンを標準エラーに1行出し、
# ${XDG_STATE_HOME:-~/.local/state}/ask-codex/usage.tsv に1行足す (失敗したときも)。
# 記録に失敗しても、回答と終了コードは変えない。
set -eu
# パス名の展開は使わない。設定から読んだ名前 (プラグイン、MCP) を空白で区切って回すので、名前の中の * や ? を展開させない
set -f
umask 077

usage() { sed -n '3,10p' "$0" >&2; }

effort=""
perm="claude-read"
dir="."
keep=""
resume=""
schema=""
while getopts "e:wC:kr:S:" opt; do
  case $opt in
    S) schema=$OPTARG ;;
    e) effort=$OPTARG ;;
    w) perm="claude-write" ;;
    C) dir=$OPTARG ;;
    k) keep=1 ;;
    r)
      # 受けるのは UUID だけ (続け方に出すのも UUID)。codex exec resume にそのまま渡すので、ほかの形は通さない
      #   - で始まる名前は、codex のオプションとして読まれる (--last は、直前のどのセッションでも続ける)
      #   UUID でない名前が見つからないと、codex は黙って新しいセッションを始めた (2026-11-22、codex-cli 0.164.0)。
      #   前の続きのつもりで、何も知らない相手の回答を受け取る
      case $OPTARG in
        "" | *[!0-9A-Fa-f-]*) resume="" ;;
        *) resume=$(printf '%s\n' "$OPTARG" | LC_ALL=C grep -E '^[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$' || true) ;;
      esac
      if [ -z "$resume" ]; then
        printf '%s\n' "-r のセッションの名前を受け付けない: [$OPTARG] (-k のときに出た続け方の名前を、そのまま渡す。UUID の形)" >&2
        exit 2
      fi
      keep=1
      ;;
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
# 設定は TOML として読まず、行で探す。書き方の揺れ (引用符、ドットのキー) は拾い、迷う書き方は止める側に倒す。
# 文字のエスケープで書いた鍵は拾えないので、エスケープがあれば止まる
# 呼ぶのはたいてい Claude。止まった理由を消すために、Claude が自分で設定を書き換えないように言い添える
handoff="(Claude へ: 設定やプロファイルを自分で書き換えない。この理由を利用者に伝えて、判断を待つ)"
stop() { # 理由には設定の行を入れることがある。macOS の sh の echo はバックスラッシュを解釈するので、printf で出す
  printf '%s\n' "止めた: $1" >&2
  printf '%s\n' "$handoff" >&2
  exit 1
}
lower() { printf '%s/' "${1%/}" | LC_ALL=C tr '[:upper:]' '[:lower:]'; }

# パス $1 を、実体のパスにして出す。ディレクトリなら、そのまま辿る。ファイルなら、親のディレクトリを辿って名前を付け直す。
# どちらも辿れなければ (まだ無い場所)、書かれたまま出す
real_of() {
  if r=$(CDPATH='' cd -- "$1" 2>/dev/null && pwd -P); then
    printf '%s\n' "$r"
  elif r=$(CDPATH='' cd -- "$(dirname -- "$1")" 2>/dev/null && pwd -P); then
    printf '%s\n' "${r%/}/$(basename -- "$1")"
  else
    printf '%s\n' "$1"
  fi
}
# プロファイルに書かれた場所 $1 (~/ か / で始まる) を、実体のパスにして出す
place_of() {
  p=$1
  # shellcheck disable=SC2088 # 設定に書かれた文字どおりの ~/ と比べている (シェルに展開させたいのではない)
  case $p in "~/"*) p="${HOME:-}/${p#\~/}" ;; esac
  p=${p%/}
  [ -n "$p" ] || p=/ # 場所が / そのもの
  real_of "$p"
}

# 1) プロファイルの、場所 (~/ か / で始まり、* を含まない) の deny。場所を書くのはプロファイルだけ (ほかの設定が足していたら、下で止まる)
deny_re="s/^[[:space:]]*[\"']((~\\/|\\/)[^\"'*]*)[\"'][[:space:]]*=[[:space:]]*[\"']deny[\"'].*/\\1/p"
denied_dirs=$(sed -nE "$deny_re" "$profile") || stop "$profile を読めない"
[ -n "$denied_dirs" ] || stop "$profile から、場所で読めなくしたディレクトリを読み取れない"
# どの表に書いた deny でも見る。大文字と小文字は区別しない (区別しないファイルシステムで、書き方の違う同じ場所を通さない)
abs_lower=$(lower "$abs_dir")
while IFS= read -r d; do
  [ -n "$d" ] || continue
  # シンボリックリンクを含むなら、作業ディレクトリと同じく実体のパスで比べる
  d=$(place_of "$d")
  case "$abs_lower" in
    "$(lower "$d")"*) stop "作業ディレクトリ $abs_dir は、読めなくした $d の中にある" ;;
  esac
done <<LIST
$denied_dirs
LIST

# Codex 自身の認証と記録は、CODEX_HOME の下にある。プロファイルは ~/.codex の下を場所で止めているので、
# CODEX_HOME が別の場所を指していると、その下は止まらない。止めていなければ、足す行を出して止まる。
# ここは「止めてある」と言う側の検査なので、上とは逆に、厳しく照らす:
#   読むだけの権限 (claude-read) の場所の表に書いたものだけを数える (書く権限の表にだけ書いても、読むだけの呼び出しでは止まらない)
#   大文字と小文字を区別する (区別するファイルシステムでは、別の場所)
#   実体の場所を取り違えていないかを見る (コマンド置換は、名前の終わりの改行を落とす)
odd_home() {
  stop "CODEX_HOME ($codex_home) に、プロファイルに場所として書けない文字 (* 引用符 バックスラッシュ 改行) がある。その下の Codex の認証と記録を読めなくしてあるかを、確かめられない"
}
nl='
'
case $codex_home in *"$nl"*) odd_home ;; esac
codex_real=$(real_of "$codex_home")
[ "$codex_real" -ef "$codex_home" ] || stop "CODEX_HOME ($codex_home) の実体の場所を確かめられない"
case $codex_real in *"*"* | *'"'* | *"'"* | *"\\"* | *"$nl"*) odd_home ;; esac
read_denied=$(sed -nE '/^\[permissions\.claude-read\.filesystem\][[:space:]]*(#.*)?$/,/^[[:space:]]*\[/p' "$profile" | sed -nE "$deny_re") ||
  stop "$profile を読めない"
read_real=""
while IFS= read -r d; do
  [ -n "$d" ] || continue
  read_real="$read_real
$(place_of "$d")"
done <<LIST
$read_denied
LIST
missing=""
for f in auth.json history.jsonl sessions archived_sessions; do
  want="${codex_real%/}/$f/"
  hit=""
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    case $want in "${d%/}/"*) hit=1 ;; esac
  done <<LIST
$read_real
LIST
  [ -n "$hit" ] || missing="$missing $f"
done
if [ -n "$missing" ]; then
  printf '%s\n' "止めた: CODEX_HOME ($codex_home) の下にある Codex の認証と記録を、プロファイルが読めなくしていない。$profile の [permissions.claude-read.filesystem] の表に次を足す:" >&2
  # HOME の下なら、プロファイルのほかの行と同じく ~/ で出す
  shown=$codex_real
  home_real=$(real_of "${HOME:-/}")
  # shellcheck disable=SC2088 # 設定に書く文字どおりの ~/ を出している (シェルに展開させたいのではない)
  case $codex_real in "${home_real%/}"/*) shown="~/${codex_real#"${home_real%/}"/}" ;; esac
  for f in $missing; do printf '  "%s" = "deny"\n' "$shown/$f" >&2; done
  printf '%s\n' "$handoff" >&2
  exit 1
fi

# 2)〜4)。検査する行 (下の body_of が出す行) を、文字で探す
# 設定 $1 の、検査する行を出す。# で始まる行は、コメントとして落とす。ただし、複数行の文字列の区切り (""" か ''') が
# ファイルのどこかにあれば、落とさない。複数行の文字列の中の # で始まる行はコメントではなく、インラインの表の中なら、
# 文字列を閉じた後ろに鍵を続けて書ける。信頼したリポジトリの設定がこの形で claude-read を隠し、deny を read に書き換えると、
# 止めたはずのファイルが読めた (2026-11-21、codex-cli 0.164.0)。
# 区切りが本当に文字列を開いているかは行では見分けきれないので、コメントや値の中にあるだけでも落とさない。
# そのときは、本当のコメントに書いた名前でも止まる。区切りがあるかを確かめられなければ、失敗を返す (呼ぶ側が止まる)
body_of() {
  ml=0
  grep -q -e '"""' -e "'''" "$1" || ml=$?
  case $ml in
    0) cat "$1" ;;
    1) sed '/^[[:space:]]*#/d' "$1" ;;
    *) return "$ml" ;;
  esac
}
found() { # $1 のパターンが、設定 $2 の検査する行にあれば 0、無ければ 1
  body=$(body_of "$2") || stop "$2 を読めない"
  rc=0
  printf '%s\n' "$body" | grep -Eq "$1" || rc=$?
  [ "$rc" -le 1 ] || stop "$2 を確かめられない (grep の終了コード $rc)"
  return "$rc"
}
sandbox_mode_re="sandbox_mode[\"']?[[:space:]]*="
# TOML の鍵は、文字をエスケープしても書ける (バックスラッシュに u・U・x と16進の数字)。ここの検査は文字で探すので、
# そう書いた claude-read や sandbox_mode を拾えない。信頼したリポジトリの設定がこの書き方で deny を read に
# 書き換えると、止めたはずのファイルが読めた (2026-11-21、codex-cli 0.164.0)。
# 鍵か値かは行では見分けきれない (インラインの表) ので、検査する行のどこかにあれば止まる。値や行末のコメントにあっても止まる
escape_re='\\[uUx][0-9A-Fa-f]'
no_escapes() { # 設定 $1 に、文字をエスケープした書き方があれば止まる
  if found "$escape_re" "$1"; then
    stop "$1 に、文字をエスケープした書き方 (バックスラッシュに u・U・x と16進の数字) がある。設定の鍵をこう書かれると、文字で探す検査をすり抜けるので、確かめられない"
  fi
}

# プロファイル自身
no_escapes "$profile"
if found "$sandbox_mode_re" "$profile"; then
  stop "$profile に sandbox_mode がある。あると、プロファイルの読めなくする決まりが効かない"
fi

# 土台の設定 (~/.codex/config.toml)。claude-read / claude-write に触れていたら、deny を足すだけでも止まる。
# そこに足した場所は 1) で見ていないので、-C がその中を指しても気づけない。プラグインと MCP は下で見る
if [ -f "$base" ]; then
  no_escapes "$base"
  if found "$sandbox_mode_re" "$base"; then
    stop "$base に sandbox_mode がある。あると、プロファイルの読めなくする決まりが効かない"
  fi
  if found 'claude-(read|write)' "$base"; then
    stop "$base が、プロファイルの permissions (claude-read / claude-write) に触れている"
  fi
fi

# リポジトリの設定と /etc/codex の設定。Codex は、信頼したプロジェクトなら、根から作業ディレクトリまでの
# 全部の .codex/config.toml を読む。だから -C から根まで、間のディレクトリも全部見る
mcp_names_from() { # 設定 $1 が定義する MCP の名前を1行ずつ。読み取れない書き方があれば止まる
  body=$(body_of "$1") || stop "$1 を読めない"
  lines=$(printf '%s\n' "$body" | grep -E '(^|[^A-Za-z0-9_])mcp_servers([^A-Za-z0-9_]|$)' || true)
  [ -n "$lines" ] || return 0
  bad=$(printf '%s\n' "$lines" | grep -Ev '^[[:space:]]*(\[+[[:space:]]*)?mcp_servers\.[A-Za-z0-9_-]+([].[:space:]=]|$)' || true)
  [ -z "$bad" ] || stop "$1 の MCP の書き方を読み取れない: $(printf '%s\n' "$bad" | head -1)"
  printf '%s\n' "$lines" | sed -E 's/^[[:space:]]*(\[+[[:space:]]*)?mcp_servers\.([A-Za-z0-9_-]+).*/\2/' | sort -u
}
proj_mcp=""
check_other() {
  [ -f "$1" ] || return 0
  no_escapes "$1"
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
# 設定 $1 を、下の2つが行の先頭から照らせる形にして出す。先頭の BOM と、行末の CR (改行が CRLF のとき) を落とす。
# 落とさないと、その行の表を見落とす。本物の codex は、先頭に BOM がある設定を読む (2026-11-21、codex-cli 0.164.0)
plugin_lines() {
  bom=$(printf '\357\273\277')
  text=$(LC_ALL=C sed "1s/^$bom//" "$1") || return 1
  printf '%s\n' "$text" | tr -d '\r'
}
plugins_in() { # 標準入力の設定の [plugins."名前"] のうち、$1 が off なら enabled = false のもの、on ならそれ以外を1行ずつ
  awk -v want="$1" '
    function flush() {
      if (name != "" && ((want == "off" && off) || (want == "on" && !off))) print name
      name = ""; off = 0
    }
    BEGIN {
      q = "[\"\047]"
      pre = "^[ \t]*\\[[ \t]*plugins\\."
      # [plugins."名前"] そのものだけを数える。[plugins."名前".何か] のような下の表は数えない
      exact = pre "(" q "[^]\"\047 \t\\\\]+" q "|[A-Za-z0-9_@-]+)[ \t]*\\][ \t]*(#.*)?$"
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
  '
}
# 標準入力の設定のプラグインの書き方のうち、上の数え方で数えられないものの行を、1つ出す。無ければ何も出さない。
# 数えられない書き方を黙って通すと、土台の設定でそう書いた有効なプラグインが、切られないまま動く (2026-11-21)
#   鍵の先頭に plugins が出てくる行が、[plugins."名前"] か、その下の [plugins."名前".何か] でない
#     ("plugins" と引用符で囲む、ドットの前後の空白、[plugins] の表の中に名前を鍵で書く、plugins."名前".enabled = true)
#   名前の中に ] か空白かバックスラッシュがある (] は名前を切り詰めて読む。空白は、名前を照らすときに2つに分かれる。
#     どちらも別のプラグインと取り違える。バックスラッシュは、足す行を二重引用符で案内すると別の名前になる)
#   下の表だけがあって、[plugins."名前"] の表が無い (enabled の行を見る所が無い。有効かもしれない)
# 複数行の文字列の中の行は、表の行と見分けていない。その中に [plugins."名前"] や enabled = false に見える行を
# わざと書けば、取り違える。土台の設定は利用者自身のファイルなので、そこまでは追わない
odd_plugins() {
  awk '
    BEGIN {
      q = "[\"\047]"
      pre = "^[ \t]*\\[[ \t]*plugins\\."
      name = "(" q "[^]\"\047 \t\\\\]+" q "|[A-Za-z0-9_@-]+)"
      start = "^[ \t]*(\\[+[ \t]*)?" q "?plugins" q "?[ \t]*([.=\\]]|$)"
      ok = pre name "[ \t]*(\\]|\\.)"
    }
    /^[ \t]*#/ { next }
    $0 ~ start && $0 !~ ok { print; bad = 1; exit }
    /^[ \t]*\[/ {
      inplug = ($0 ~ ok)
      if (inplug) {
        s = $0
        sub(pre, "", s)
        match(s, "^" name)
        n = substr(s, 1, RLENGTH)
        rest = substr(s, RLENGTH + 1)
        gsub(q, "", n)
        if (rest ~ "^[ \t]*\\]") whole[n] = 1
        else if (!(n in below)) below[n] = $0
      }
      next
    }
    END {
      if (bad) exit
      for (n in below) if (!(n in whole)) { print below[n]; exit }
    }
  '
}
if [ -f "$base" ]; then
  base_plug=$(plugin_lines "$base") || stop "$base を読めない"
  prof_plug=$(plugin_lines "$profile") || stop "$profile を読めない"
  odd=$(printf '%s\n' "$base_plug" | odd_plugins) || stop "$base を確かめられない"
  if [ -n "$odd" ]; then
    stop "$base のプラグインの書き方を読み取れない ([plugins.\"名前\"] の表で書く): $odd"
  fi
  on_plugins=$(printf '%s\n' "$base_plug" | plugins_in on) || stop "$base を確かめられない"
  off_plugins=$(printf '%s\n' "$prof_plug" | plugins_in off) || stop "$profile を確かめられない"
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
# 続きも、ここまでと同じ検査と同じ指定 (プロファイル、権限、MCP を切る) で呼ぶ。resume の後ろは、セッションとプロンプトだけ
if [ -n "$resume" ]; then set -- "$@" resume "$resume"; fi

start=$(date +%s)
status=0
# プロンプトを引数で渡すとき、標準入力が開いたままだと codex は EOF を待って止まる。
# プロンプトは、必ず -- の後ろで渡す。- で始まるプロンプトを、codex がオプションとして読まないようにする。
# -- が無いと、resume <セッション> --last は「直前のセッションを続け、<セッション> をプロンプトにする」と読まれた
# (2026-11-22、codex-cli 0.164.0)
if [ "$prompt" = "-" ]; then
  codex "$@" -- - >"$events" 2>"$log" || status=$?
else
  codex "$@" -- "$prompt" >"$events" 2>"$log" </dev/null || status=$?
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
    # 名前は、codex が返したものを出す (続きの呼び出しも、thread.started に同じ名前を出す)。
    # セッションが始まらずに落ちたとき (渡したセッションが無い、など) は、名前が無いので案内しない。
    # 始まった後で落ちたときは、そのセッションは残っているので案内する
    if [ -n "$thread" ]; then
      # 続け方は、この ask.sh の -r で案内する。codex exec resume を直接呼ぶと、MCP を切る指定が付かず、上の検査も通らない
      w=""
      if [ "$perm" = "claude-write" ]; then w=" -w"; fi
      printf '%s\n' "[ask-codex] 続けるとき: \"$skill_dir/scripts/ask.sh\" -r $thread$w -C \"$abs_dir\" \"<プロンプト>\"" >&2
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
