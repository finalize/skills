# shellcheck shell=bash
# テストの共通部品。source して使う。macOS の bash 3.2 で動く書き方にする。
# 全角の文字の直前の変数は ${} で囲む（bash 3.2 は続く全角を変数名の一部と読む）。

passes=0
fails=0

ok() {
  passes=$((passes + 1))
  if [ -n "${VERBOSE:-}" ]; then echo "  ok   $*"; fi
}

ng() {
  fails=$((fails + 1))
  echo "  FAIL $*"
}

# check <説明> <期待> <実際>
check() {
  if [ "$2" = "$3" ]; then ok "$1"; else ng "$1 — 期待 [$2] 実際 [$3]"; fi
}

# has <説明> <含まれるはずの文字列> <全体>
has() {
  case "$3" in
    *"$2"*) ok "$1" ;;
    *) ng "$1 — [$2] が無い: [$(printf '%s' "$3" | head -3 | cut -c1-200)]" ;;
  esac
}

# lacks <説明> <含まれないはずの文字列> <全体>
lacks() {
  case "$3" in
    *"$2"*) ng "$1 — [$2] がある" ;;
    *) ok "$1" ;;
  esac
}

# 一時ディレクトリを作って、実体のパスを返す。終わりに消すのは呼ぶ側（trap）
new_tmp() {
  d=$(mktemp -d "${1:-/tmp}/skills-test.XXXXXX") || exit 1
  (cd "$d" && pwd -P)
}

finish() {
  echo "$(basename "$0"): ${passes} 通過、${fails} 失敗"
  [ "$fails" -eq 0 ]
}
