# skills

Claude Code に覚えさせておきたい、**自分で書いたスキル**を置く。

個人開発のリポジトリが増えて、同じ作法を毎回説明し直していた。
リポジトリ1つに閉じる話はそれぞれの `CLAUDE.md` に、
**複数のリポジトリにまたがる作法**をここに書く。

## 置き場所の分担

```
<クローンした場所>/skills/<名前>/SKILL.md    ← ここ（git で追う）。main の作業ツリーが、そのまま張る元
        ↓ symlink（install.sh）
~/.claude/skills/<名前>/                     ← Claude Code
~/.agents/skills/<名前>/                     ← Codex・Cursor・Gemini CLI（Claude Code 専用のスキルは張らない）
~/.codex/claude.config.toml                  ← ask-codex のプロファイル（Codex が入っているとき）
~/.claude/skills/wrangler/ など              ← 入れただけのスキル。実ディレクトリのまま、git で追わない
```

**クローンは1つにして、そこから張る。** 置き場所はどこでもよい（`install.sh` は、自分のある場所から張る）。
張る元と作業用でクローンを分けると、張ってある側が古いままになる。

symlink の先は作業ツリーなので、**main の作業ツリーの中身が、そのまま全部のセッションに効く**。
ブランチを切り替えたり、書きかけを置いたりすると、ほかのセッションがそれを使う。直す作業は `git worktree` でやる（下の「直すとき」）。

`~/.claude/skills` は Cloudflare 一式など**入れたスキルと同居している**。
だからディレクトリごと symlink にはせず、**スキル1つずつ張る**。
`install.sh` は同じ名前の実ディレクトリがあれば黙って避ける（上書きしない）。

`SKILL.md` は [Agent Skills](https://agentskills.io) の共通形式なので、中身はそのままで
他のエージェントでも動く。違うのは読む場所だけ。`~/.agents/skills` が Codex・Cursor・
Gemini CLI の共通の置き場で、Claude Code は `~/.claude/skills` を見る。
Cursor は互換のために `~/.claude/skills` も読むので、両方に張ったスキルは Cursor からは二重に見えうる
（Cursor の文書の記述。重複をまとめるかは確かめていない）。

Claude Code が前提のスキル（`ask-codex`・`dispatch-tasks`）には `.claude-only` を置いてある。
`install.sh` は、それを `~/.agents/skills` には張らない。

## 入れる

### 前提

| 使うもの | 要るもの |
|---|---|
| どのスキルも | Claude Code。`install.sh` は bash で動く |
| `ask-codex` | Codex の CLI（`codex`。ログイン済みであること）と `jq`。codex-cli 0.164.0 で確かめた |
| `dispatch-tasks` | Rex（`rex`）、`jq`、`git`。子が Codex を呼ぶので、`ask-codex` の前提も要る |

スクリプトは macOS（bash 3.2 と BSD の道具）で動かしている。ほかの OS では確かめていない。

### 初めて入れる

```sh
git clone git@github.com:finalize/skills.git    # 置き場所はどこでもよい。ここでは、いまいる場所の skills に入る
./skills/install.sh
```

Claude Code はセッション開始時にスキル一覧を読む。反映されなければ起動し直す。

`install.sh` は、Codex の置き場（`~/.codex`）があれば、`ask-codex` のプロファイルも `~/.codex/claude.config.toml` に張る。

### ask-codex を使う前に

- `ask.sh` が「有効なプラグインを、プロファイルが切っていない」と言って止まったら、出てきた行を
  `skills/ask-codex/claude.config.toml` に足す（Codex で有効にしているプラグインは、環境ごとに違う）。
- 読めなくする名前や場所を足すときも、同じプロファイルに書く（公開されるので、案件の名前や受け取ったデータの場所は書かない）。
  `~/.codex/config.toml` には書かない（そこが `claude-read` / `claude-write` に触れていると、`ask.sh` は止まる）。
- プロファイルに足したら `tests/sandbox.sh` を流して、読めなくする決まりが効いたままなのを見る。

### 更新するとき

クローンした場所（main の作業ツリー）で流す。

```sh
pgrep -f 'heavy.sh|ask.sh'    # 何も出ないこと（張ってあるスクリプトを、ほかのセッションが動かしていない）
git pull --ff-only
./install.sh
```

`pull` した時点で、張ってあるスキルは新しい版に替わる（symlink の先が、この作業ツリーなので）。
`install.sh` も流し直す。増えたスキルを張り、消えたスキルと、Claude Code 専用になったスキルの `~/.agents/skills` の symlink を外す。

クローンを別の場所へ移したときも、移した先で `install.sh` を流す。symlink を張り直し、古い場所を指して切れたものを外す。

### 直すとき

main の作業ツリーは張る元なので、そこでは直さない。`git worktree` を切って、そこで直す。

```sh
git worktree add ../skills-fix -b <ブランチ>    # 置き場所はどこでもよい
# 直して、main に入れる
git worktree remove ../skills-fix
git pull --ff-only                               # main の作業ツリーで。上の「更新するとき」と同じ
```

`ask.sh` を直している間に Codex の見直しを頼むときは、張ってある版（`~/.claude/skills/ask-codex/scripts/ask.sh`）で呼ぶ。
直している最中のスクリプトをその場で動かすと、書き換えたところで壊れる。

`~/.codex/claude.config.toml` が symlink でなく実ファイル（手で置いた写し）だと、`install.sh` は上書きせずに知らせる。
そのときは、次の順でやる。

1. 写しにだけ書いてある決まりを見る。要るものは、リポジトリのプロファイル（`skills/ask-codex/claude.config.toml`）に足す。
   このファイルは公開されるので、案件の名前や受け取ったデータの場所は書かない（そういう決まりは引き継げない）。
   足さなかった決まりは、写しを消した時点で効かなくなる
2. 写しを消して、`install.sh` を流し直す
3. `ask.sh -e low` を1回流して、通るのを見る

## 中身

| スキル | いつ効く |
|---|---|
| `effective-tests` | テストを書く・足す・直すとき。実装の写しを避け、仕様と性質で固定する書き方と、差し替えの型と、罠。LLM 生成テストの研究と古典の出典つき |
| `ambition-upgrade` | 「もっと野心的に」「依頼を強化して」と頼まれたとき。高度・深さ・幅の3方向で依頼を見直してから動く。時間と費用は3〜5倍 |
| `make-verify-skill` | 画面や CLI の変更を「動いた」と言う前に、確かめる手段が無いとき。起動・診断・操作・証拠・後片付けの手順と機能の地図を、リポジトリごとのスキルとして作り、一度通してから渡す |
| `fix-with-evidence` | 不具合や遅さを直すとき。利用者と同じ面で自分で再現し、動かして得た証拠で原因を絞り、同じ面で直ったのを見てから終える |
| `prevent-repeated-mistakes` | 同じ指摘を二度したとき。メモや CLAUDE.md に足す前に、構造・型・lint やフック・テストの順で起きなくし、過去の実際の誤りで止まるのを確かめる |
| `ask-codex` | Codex に別視点を頼むとき（差分レビュー、2回外したバグ、計画の穴探し、読む量の多い調査）。呼び出し用の `ask.sh` と、秘密と実データを読ませないプロファイルつき。Claude Code が前提 |
| `dispatch-tasks` | 複数のチケットを、司令塔のセッションから Rex の別々のセッションに割り振るとき。worktree・番号・起動・見張り・鍵のスクリプトと、指示文の雛形つき。Claude Code と Rex が前提 |

出どころと、それぞれを測った記録（何が変わり、何が変わらなかったか。まだ確かめていないこと）は、
各スキルの `references/measured.md` にある（`effective-tests` は `reference.md`）。ここには写さない。

## 足すとき

```sh
mkdir -p skills/<名前>
$EDITOR skills/<名前>/SKILL.md
./install.sh
```

```markdown
---
name: <名前>
description: いつ読むべきかを1〜2文で。ここだけが毎ターン context に載る。
---
```

書くときの決め事:

- **当たり前のことを書かない。** 既定の振る舞いを変える情報だけ。特に、一度踏んだ地雷。
- **`description` がトリガーの全部。** 本文は呼ばれるまで読まれないが、`description` は使わなくても毎ターン載る。
  短く、いつ効くかが分かる文にする。時間や費用が大きいスキルは、頼まれたときだけ呼ばれる条件にするか、除く条件を書く。
  `<` と `>` は書かない（一覧では `&lt;` `&gt;` と表示される）。
- 本文は500行以内。長い参照は同じディレクトリの別ファイルに逃がす。
- **出どころと、測った記録は `references/measured.md` に置く。** 本文は呼ばれるたびに載るので、振る舞いを変えることだけを書く。
  README にも経緯を書かない（二重に持つと、片方が古くなる）。
- **名前に自分の名前は入れない。一語の名前は避け、2語以上にする。** 個人スキルはプロジェクトの同名スキルを隠すので、
  `release` `deploy` のような一語の名前は衝突する。動詞から始めると何をするスキルかが名前で分かる（`ask-codex` `dispatch-tasks`）。
- **実例を削らない。まとまった実例は `references/examples.md` に置く。** このリポジトリの価値は原則ではなく、実際に使った一行と、
  実際に壊れた話にある。本文は特定のリポジトリの話に寄せず、どんな例があって、いつ読むかだけを書く。
- **罠には、踏んだ時期と版を書く。** OS や道具が変わると成り立たなくなる。写す前・頼る前に、いまも起きるかを流す。
- **案件の名前、チケットや PR の番号、受け取ったデータの場所は書かない。** このリポジトリは公開している。「仕事のリポジトリ」のように伏せる。
- **Claude Code が前提のスキルには `.claude-only` を置く。** `install.sh` が `~/.agents/skills` に張らなくなる。

`/skill-doctor` で各スキルの context コストと使われた回数が出る。増えてきたらそこで間引く。

## テスト

```sh
tests/run.sh       # スクリプトのテストと lint。偽の codex・rex・claude と、使い捨てのリポジトリで流す
tests/sandbox.sh   # 本物の codex sandbox で、ask-codex の読ませない決まりを見る（モデルは呼ばない。手元用）
```

スクリプトかプロファイルを直したら流す。どちらも、本物の `~/.claude`・`~/.agents`・`~/.codex` には触らない。
GitHub Actions でも `tests/run.sh` を流す。

## そのうち

他人に配る段になったら、`.claude-plugin/marketplace.json` と、プラグインの `.claude-plugin/plugin.json` を足す
（Claude Code の文書の配置。足す前に文書を見直す）。`/plugin marketplace add finalize/skills` で入るようになる。
