#!/bin/sh
# 見本と motion_page.py の既定のフォントを fonts/ に取ってくる（どちらも SIL Open Font License。動画に使ってよい）。
#   Dela Gothic One: 太い見出し・叫び   Yusei Magic: 手書き風・つぶやき
set -eu
cd "$(dirname "$0")"
mkdir -p fonts
base=https://github.com/google/fonts/raw/main/ofl
curl -sfL -o fonts/DelaGothicOne-Regular.ttf "$base/delagothicone/DelaGothicOne-Regular.ttf"
curl -sfL -o fonts/OFL-DelaGothicOne.txt "$base/delagothicone/OFL.txt"
curl -sfL -o fonts/YuseiMagic-Regular.ttf "$base/yuseimagic/YuseiMagic-Regular.ttf"
curl -sfL -o fonts/OFL-YuseiMagic.txt "$base/yuseimagic/OFL.txt"
ls -l fonts
