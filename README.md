# skills

Claude Code に覚えさせておきたい、**自分で書いたスキル**を置く。

個人開発のリポジトリが増えて、同じ作法を毎回説明し直していた。
リポジトリ1つに閉じる話はそれぞれの `CLAUDE.md` に、
**複数のリポジトリにまたがる作法**をここに書く。

## 置き場所の分担

```
~/workspace/skills/skills/<名前>/SKILL.md   ← ここ（git で追う）
        ↓ symlink
~/.claude/skills/<名前>/                     ← Claude Code
~/.agents/skills/<名前>/                     ← Codex・Cursor・Gemini CLI
~/.claude/skills/wrangler/ など              ← 入れただけのスキル。実ディレクトリのまま、git で追わない
```

`~/.claude/skills` は Cloudflare 一式など**入れたスキルと同居している**。
だからディレクトリごと symlink にはせず、**スキル1つずつ張る**。
`install.sh` は同じ名前の実ディレクトリがあれば黙って避ける（上書きしない）。

`SKILL.md` は [Agent Skills](https://agentskills.io) の共通形式なので、中身はそのままで
他のエージェントでも動く。違うのは読む場所だけ。`~/.agents/skills` が Codex・Cursor・
Gemini CLI の共通の置き場で、Claude Code だけが `~/.claude/skills` を見る。

## 入れる

```sh
git clone git@github.com:finalize/skills.git ~/workspace/skills
~/workspace/skills/install.sh
```

Claude Code はセッション開始時にスキル一覧を読む。反映されなければ起動し直す。

## 中身

| スキル | いつ効く |
|---|---|
| `shogo-commit-style` | コミットメッセージ・PR のタイトルと本文を書くとき |
| `shogo-vp-npm-release` | Vite+ のモノレポで npm パッケージを作る・出すとき |
| `shogo-workers-ship` | Cloudflare Workers に載せるツールのデプロイまわりを触るとき |
| `effective-tests` | テストを書く・足す・直すとき。実装の写しを避け、仕様と性質で固定する書き方と、差し替えの型と、罠。LLM 生成テストの研究と古典の出典つき |
| `spec-decisions` | 作る前に仕様を書くとき。決めごとだけを書き、1つに1つの例、決められない点は「要確認」で人に返す。`effective-tests` の前に来る |
| `html-motion-video` | テロップ・オープニング・エンディングなど、2D の動きを MP4 にするとき。HTML/SVG を時刻だけから描き、Playwright で Chrome を並べて撮り、動きのぼかしと合成した音を付ける。そのまま動く雛形つき |

## 足すとき

```sh
mkdir -p skills/shogo-<名前>
$EDITOR skills/shogo-<名前>/SKILL.md
./install.sh
```

```markdown
---
name: shogo-<名前>
description: いつ読むべきかを1〜2文で。ここだけが毎ターン context に載る。
---
```

書くときの決め事:

- **当たり前のことを書かない。** 既定の振る舞いを変える情報だけ。特に、一度踏んだ地雷。
- **`description` がトリガーの全部。** 本文は呼ばれるまで読まれないが、`description` は使わなくても毎ターン載る。
  短く、いつ効くかが分かる文にする。
- 本文は500行以内。長い参照は同じディレクトリの別ファイルに逃がす。
- **自分の作法のスキルは名前に `shogo-` を付ける。** 個人スキルはプロジェクトの同名スキルを隠す。
  `release` `deploy` のような名前は衝突する。誰にでも効く汎用のスキル（`effective-tests`）には付けないが、
  一語の名前は避ける。
- 実例を削らない。このリポジトリの価値は原則ではなく、実際に使った一行と、実際に壊れた話にある。

`/skill-doctor` で各スキルの context コストと使われた回数が出る。増えてきたらそこで間引く。

## そのうち

他人に配る段になったら `marketplace.json` と `plugins/<名前>/plugin.json` を足す。
`skills/` の位置はそのままで、`/plugin marketplace add finalize/skills` で入るようになる。
