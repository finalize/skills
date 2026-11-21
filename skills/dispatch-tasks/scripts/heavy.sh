#!/usr/bin/env bash
# 重い処理（全体の検査・pre-commit の付いた git commit・pre-push の E2E が付いた git push）を、
# 同じリポジトリの worktree の間で1本ずつ回す。鍵は git の共通ディレクトリに置くので、別のリポジトリとは取り合わない。
# 子が同時に全体のテストを回すと時間切れで落ち、E2E は固定のポートを取り合って落ちる（2026-11-21）。
#
# 使い方: heavy.sh -l <ラベル> [-t 待つ上限の秒] -- <コマンド...>
#   例: heavy.sh -l 101 -- git push -u origin HEAD
#       heavy.sh -l 102 -- env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 git commit -F /path/to/msg
#       heavy.sh -l tower -- sh -c 'while kill -0 <pid> 2>/dev/null; do sleep 10; done'   （先に走っていた処理が終わるまで鍵を持つ）
# 鍵の持ち主は <git の共通ディレクトリ>/tower-heavy.lock/owner。持ち主のプロセスが消えていれば外して取る。
#   外すのは1人ずつ（tower-heavy.lock.break を作れた人だけ）で、その中で持ち主を読み直してから外す。
#   2人が同時に外しにいくと、先に取り直した人の鍵を後の人が消して、2本が重なる。
#   後始末は自分の鍵だけを消す。持ち主が自分でなくなっていたら触らない。
# 待ちの間隔は15秒。TOWER_HEAVY_POLL で変えられる（テスト用）。
#
# 知っている穴: この包みのシェルだけが SIGKILL されると、中の処理が生きていても「持ち主が消えた」と見なされ、次が入る。
#   中の処理を & で起こして pid を持ち主に書けば見分けられるが、ジョブ制御の無い bash では & で起こした子は
#   SIGINT を無視するので、割り込みで止まらなくなる（確かめた）。前面で動かす形は変えない。
set -euo pipefail

usage() { sed -n '6,9p' "$0" >&2; }

label=""
max_wait=7200
while getopts "l:t:" o; do
  case $o in
    l) label=$OPTARG ;;
    t) max_wait=$OPTARG ;;
    *)
      usage
      exit 2
      ;;
  esac
done
shift $((OPTIND - 1))
[ "${1:-}" = "--" ] && shift
if [ -z "$label" ] || [ $# -eq 0 ]; then
  usage
  exit 2
fi

# git の外では止まる。共通ディレクトリが分からないまま進むと、現在地に鍵を作って素通りする
if ! common=$(git rev-parse --git-common-dir 2>/dev/null); then
  echo "git のリポジトリの中で呼ぶ（鍵は git の共通ディレクトリに置く）" >&2
  exit 2
fi
lock="$(cd "$common" && pwd)/tower-heavy.lock"
breaker="$lock.break"
poll=${TOWER_HEAVY_POLL:-15}

# 持ち主の pid。cmd= に改行入りの引数が書かれていても、最初の pid= だけを読む
owner_pid() { sed -n 's/^pid=//p' "$lock/owner" 2>/dev/null | head -1 || true; }

waited=0
until mkdir "$lock" 2>/dev/null; do
  owner=$({ tr '\n' ' ' <"$lock/owner"; } 2>/dev/null || echo "?")
  pid=$(owner_pid)
  if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
    # 外す途中で落ちた人の印が残っていたら片付ける（ふつうは一瞬で消える）
    if [ -n "$(find "$breaker" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then rmdir "$breaker" 2>/dev/null || true; fi
    if mkdir "$breaker" 2>/dev/null; then
      now=$(owner_pid)
      if [ -n "$now" ] && ! kill -0 "$now" 2>/dev/null; then
        echo "持ち主のプロセスが消えた鍵を外す: ${owner}" >&2
        rm -rf "$lock"
      fi
      rmdir "$breaker" 2>/dev/null || true
      continue
    fi
    # ほかの人が外している最中。下で待ってから見直す
  fi
  if [ "$waited" -ge "$max_wait" ]; then
    echo "待ちきれなかった（${max_wait} 秒）。持ち主: ${owner}" >&2
    exit 75
  fi
  if [ $((waited % 300)) -eq 0 ]; then
    echo "鍵が空くのを待つ（${waited} 秒）。持ち主: ${owner}" >&2
  fi
  sleep "$poll"
  waited=$((waited + poll))
done

held=1
release() {
  [ "$held" = 1 ] || return 0
  held=0
  p=$(owner_pid)
  # 持ち主が書かれる前（空）か、自分のときだけ消す。外されて、ほかの人が取り直していたら触らない
  if [ -z "$p" ] || [ "$p" = "$$" ]; then rm -rf "$lock"; fi
}
trap release EXIT
# 止める合図を受けたら、鍵を返して終わる（返した後に、鍵を持たないまま先へ進まない）。
# 中の処理が動いている間に届いた合図は、bash がその処理の終わりまで待ってから扱うので、鍵は処理が終わるまで持ったまま
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
printf 'label=%s\npid=%s\nsince=%s\ncmd=%s\n' "$label" "$$" "$(date '+%m-%d %H:%M:%S')" "$(printf '%s' "$*" | tr '\n' ' ')" >"$lock/owner"
echo "鍵を取った（${label}）: $*" >&2
"$@"
