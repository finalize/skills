---
name: shogo-vp-npm-release
description: Vite+（vp）のモノレポで npm パッケージを作る・出すとき。contrast-kit と termpic で揃えてある構成、公開するパッケージと公開しない website の分け方、出す前に通すもの、bumpp でのリリース手順。
---

# Vite+ モノレポから npm に出す

contrast-kit と termpic が同じ形。3つ目を作るならこれを写す。

## 構成

```
packages/<パッケージ名>/   ← npm に出すのはここだけ
apps/website/             ← 見せるためのサイト。出さない
pnpm-workspace.yaml
vite.config.ts
tsconfig.json
LICENSE
README.md
```

- **root の `package.json` は `name: <repo>-workspace` / `version: 0.0.0` / `private`。** root を publish しない。
- `apps/website` も `private: true` / `version: 0.0.0` のまま上げない。**版を持つのは `packages/` の中だけ。**
- 公開するパッケージには `license: MIT` と root の `LICENSE` を置く。

root の script は3つだけ:

```json
"ready":   "vp run -r build && vp check && vp run -r test",
"dev":     "vp run website#dev",
"prepare": "vp config"
```

公開するパッケージ側:

```json
"files": ["dist"],
"scripts": {
  "build": "vp pack",
  "dev": "vp pack --watch",
  "test": "vp test",
  "check": "vp check",
  "prepublishOnly": "vp run build",
  "release": "bumpp && npm publish"
}
```

`files: ["dist"]` を忘れるとソースごと配る。`prepublishOnly` は `vp run build`（`vp build` ではない）。

## 出す手順

1. `pnpm ready` を root で通す。これが `-r build` → `check` → `-r test` をまとめている。
   **個別に `vp test` だけ叩いて済ませない。** 型とビルドはここでしか見ていない。
2. `packages/<名前>` に降りて `pnpm release`。`bumpp` が版を上げてタグを打ち、続けて publish する。
3. コミットの一行目の末尾に `（v0.3.0）` を付ける → `shogo-commit-style`

**termpic の `packages/termpic` には `release` script が無い**（contrast-kit にはある）。
termpic を出すときは先に足す。

## 依存の張り方

termpic は contrast-kit を `^0.3.0` のように**範囲で**依存する。
片方を上げたらもう片方の範囲を見る。上げたこと自体がコミット1本になる
（`contrast-kit の依存範囲を ^0.3.0 に上げる（v0.2.2）`）。

## 揃えるワークフロー

`.github/workflows/` に4つ置く。新しいリポジトリでは既存からコピーする。

| ファイル | 役目 |
|---|---|
| `ci.yml` | 検査とビルド |
| `claude.yml` | Issue/PR から Claude を呼ぶ |
| `dependabot-auto-merge.yml` | patch と minor だけ自動マージ。major は弾く |
| `update-screenshots.yml` | website のスクリーンショットを撮り直す |

`dependabot-auto-merge.yml` が見る `steps.meta.outputs.update-type` は
**PR に含まれる中で最も大きい semver 変更**。まとめ PR にメジャーが混ざっていればそこで止まる。
