#!/bin/sh
# PNG の連番（FRAMES/f0001.png …）を MP4（H.264, 30 fps）にする。音（WAV）があれば AAC で一緒に入れる。
# PNG の sRGB の印が動画に引き継がれて iec61966-2-1 になるので、色の印は setparams で BT.709 に付け直す。
#   sh encode.sh FRAMES_DIR OUT.mp4 [AUDIO.wav]
set -eu
cd "$(dirname "$0")"
FRAMES=${1:?frames dir}
OUT=${2:?out.mp4}
AUDIO=${3:-}

if [ -n "$AUDIO" ] && [ -f "$AUDIO" ]; then
  set -- -i "$AUDIO" -map 0:v -map 1:a -c:a aac -b:a 192k -shortest
else
  set --
fi

ffmpeg -y -loglevel error -stats \
  -framerate 30 -i "$FRAMES/f%04d.png" "$@" \
  -vf "scale=out_color_matrix=bt709:out_range=tv,format=yuv420p,setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709:range=tv" \
  -colorspace bt709 -color_primaries bt709 -color_trc bt709 \
  -c:v libx264 -preset slow -crf 16 -profile:v high -movflags +faststart \
  "$OUT"
