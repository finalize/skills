"""見本の音（3 秒）: 0.8 秒の叩きつけに「ドン」とブラスとシンバル、💢 の「びよーん」、札の「ポン」、きらめき、最後に風切り。"""
import os

import numpy as np

from synth import *  # noqa: F401,F403

HERE = os.path.dirname(os.path.abspath(__file__))
DUR = 3.0
N = int(SR * DUR)
bus = np.zeros((N, 2))
wet = np.zeros((N, 2))                # 残響を付ける分

place(bus, whoosh(0.35, 300, 2000), 0.48, 0.25)
place(bus, thump(), 0.8, 0.6)
stab = brass([NOTE[n] for n in ("F4", "A4", "C5")], 0.5)
place(bus, stab, 0.8, 0.45)
place(wet, stab, 0.8, 0.2)
place(bus, crash(1.6), 0.8, 0.3, 0.2)
place(bus, boing(), 0.95, 0.15, 0.5)
place(bus, pop(), 1.05, 0.2, -0.2)
place(wet, chime(NOTE["C7"], 1.2), 1.62, 0.05, -0.5)
place(bus, whoosh(0.4, 400, 3000), 2.6, 0.2)
master(bus + reverb(wet), os.path.join(HERE, "example_audio.wav"))
