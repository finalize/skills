#!/usr/bin/env bash
# Rex に新しいセッションを作り、その中で claude を指示文つきで起動する。出力は1行の JSON（session と block）。
# 使い方: launch.sh -l <ラベル> -C <作業フォルダ> -m <モデル> -i <指示文のファイル> [-p <権限モード>] [-e <effort>]
#   モデルは必ず渡す（既定に頼らない。/model を誰かが打つと既定が変わる）
#   権限モードの既定は auto。子は設計のファイルを書く。plan mode は計画のファイル以外の編集を止める
#   （Claude Code の文書の記述。ここでは試していない）
#   試すときは TOWER_CLAUDE_BIN に claude の代わりのコマンドを入れる
set -euo pipefail

label="" dir="" model="" brief="" mode="auto" effort=""
while getopts "l:C:m:i:p:e:" opt; do
  case $opt in
    l) label=$OPTARG ;;
    C) dir=$OPTARG ;;
    m) model=$OPTARG ;;
    i) brief=$OPTARG ;;
    p) mode=$OPTARG ;;
    e) effort=$OPTARG ;;
    *) exit 2 ;;
  esac
done
if [ -z "$label" ] || [ -z "$dir" ] || [ -z "$model" ] || [ -z "$brief" ]; then
  sed -n '3,7p' "$0" >&2
  exit 2
fi
[ -d "$dir" ] || { echo "作業フォルダが無い: $dir" >&2; exit 1; }
[ -s "$brief" ] || { echo "指示文が無いか空: $brief" >&2; exit 1; }
brief="$(cd "$(dirname "$brief")" && pwd)/$(basename "$brief")"

args=("${TOWER_CLAUDE_BIN:-claude}" --model "$model" --permission-mode "$mode" -n "$label")
[ -z "$effort" ] || args+=(--effort "$effort")

# 指示文は長く、引用符・$・改行を含む。中身は起動した先で cat で読み、1つの引数として渡す
cmd="exec $(printf '%q ' "${args[@]}")\"\$(cat $(printf '%q' "$brief"))\""
rex new "$label" -c "$dir" --window Claude --json -- bash -c "$cmd" |
  jq -c '{session: .session_id, block: .initial_windows[0].block_ids[0]}'
