"""見本（3 秒）。道具一式が動くかを最初にこれで確かめる。

  npm install && sh fetch_fonts.sh
  python3 example.py --frames 1,25,40,70    要所だけ描いて見る（数秒）
  python3 example.py                        動きのぼかしと音を付けて example.mp4 にする
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import motion_page  # noqa: E402

DATA = {"text": "できた！", "tag": "動作確認"}
NF = 90
# 叩きつけと最後に白く飛ばすところは 24 枚、ほかは 6 枚に分けて撮る
WINDOWS = [(0.6, 1.1, 24), (2.7, 3.0, 24)]

if __name__ == "__main__":
    motion_page.run("example_scene.js", NF, WINDOWS, 6, DATA, "example.mp4", "example_audio.py", "example_audio.wav",
                    sys.argv[1:], "example_frames")
