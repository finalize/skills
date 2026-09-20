---
name: shogo-workers-ship
description: Cloudflare Workers に載せる個人サイト・公開ツール（hidori、shogo-site）で、デプロイまわりの script や GitHub Actions を足す・直すとき。pnpm の script 名の衝突、配色検査の組み込み、Dependabot 自動マージを取りこぼさない日次再デプロイ。
---

# Workers に載せるときの共通の作法

hidori と shogo-site で同じ形にしてある。片方で直したらもう片方も見る。

## `deploy` という script 名は使えない

**`pnpm deploy` は pnpm の組み込みコマンドで、`package.json` の script は実行されない。**
一度これで黙って何も起きなかった。デプロイの script 名は `ship`。

```json
"ship": "opennextjs-cloudflare build && opennextjs-cloudflare deploy"   // hidori（Next.js + OpenNext）
"ship": "astro build && wrangler deploy -c dist/server/wrangler.json"   // shogo-site（Astro）
```

CI からも `pnpm run ship` で呼ぶ（`pnpm ship` ではなく `run` を挟む）。

## `check` に配色の検査を入れる

自作の contrast-kit を使って、CSS 変数の組み合わせを CI で落とす。

```json
"check": "next typegen && tsc --noEmit && eslint && node scripts/check-contrast.mjs"
```

`scripts/check-contrast.mjs` は各リポジトリに実体を置く（共通パッケージにしていない）。
中身は `parseCssVariables` → `extractRuleBlock` → `auditPairs` → `suggestAccessible` で、
見る CSS のパスだけがリポジトリごとに違う。

- hidori: `app/globals.css`
- shogo-site: `src/styles/global.css`

`extractRuleBlock` はセレクタを素の `indexOf` で探す。セレクタ名が他の文字列に含まれていると誤爆する。

## CI は「毎日 main を撮り直す」

`.github/workflows/ci.yml` の `on` は4つ。**`schedule` を落とさない。**

```yaml
on:
  push: { branches: [main] }
  pull_request:
  workflow_dispatch:
  schedule:
    - cron: "37 1 * * *"   # hidori。shogo-site は "43 1 * * *"
```

理由: **Dependabot の自動マージは `GITHUB_TOKEN` でマージするので、main への `push` イベントが発火しない。**
これが無いと、Dependabot がマージした内容だけ本番に出ないまま溜まる。

分を `00` にしない。毎時ちょうどは GitHub 側が混んでいて、遅延と取りこぼしが起きる。
リポジトリごとに違う半端な分を使う（37 / 43）。

## そのほか

- `deploy` ジョブは `needs: build`。push(main) / schedule / workflow_dispatch のときだけ走らせる。
- `build` ジョブの `name:` がブランチ保護の必須チェック名になる。**変えるなら GitHub 側の設定も直す。**
- `concurrency` の group は `ci-${{ github.ref }}-${{ github.event_name }}`、`cancel-in-progress: true`。
  group に `github.event_name` が入っているのは、同じ ref で走る schedule と push を別の列として扱うため。
- マイグレーションがあるなら、デプロイの前に当てる（hidori の D1）。
