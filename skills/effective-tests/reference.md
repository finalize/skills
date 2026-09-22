# effective-tests の参照

`SKILL.md` の手順を支える、コードの形・差し替えの対応表・罠・測った結果・出典。

## 固定するものの形

### 設計の判断

```swift
// ここが設計の判断。朝いちばんに開いたとき、昨日まで続いていた分を
// 0 と出すと「途切れた」と見えるが、実際にはまだ途切れていない。
check("今日まだ・昨日はやった", streak(days: [yesterday], asOf: today), 1)
// 実際に途切れるのは、昨日もやっていないとき。
check("一昨日で止まっている", streak(days: [twoDaysAgo], asOf: today), 0)
```

### 外部仕様は出典の参照値

```ts
test("RFC 4648 のテストベクタと一致する", () => {
  // https://www.rfc-editor.org/rfc/rfc4648#section-10
  expect(base64("foobar")).toBe("Zm9vYmFy");
  expect(base64("fooba")).toBe("Zm9vYmE=");
});
```

### 実際に壊れた入力

```ts
// 実例: 2026-03-31 23:59 の予定が翌月の一覧に混ざっていた
test("月末ぎりぎりの予定は当月に入る", () => {
  expect(monthOf(at(2026, 3, 31, 23, 59))).toBe("2026-03");
});
```

### 優先順位は表

```go
tests := []struct{ name string; cancelled, shipped bool; want Status }{
	{"取り消しは何より先", true, true, StatusCancelled},
	{"出荷済みは支払い待ちより先", false, true, StatusShipped},
	{"何も無ければ支払い待ち", false, false, StatusAwaitingPayment},
}
```

### 取れないときの契約

```go
srv := httptest.NewServer(handler)
url := srv.URL
srv.Close() // 閉じた先に撃つ
sum := run(url)
if len(sum.Latencies) != 0 {
	t.Errorf("失敗した分の遅延は積まない: %d", len(sum.Latencies))
}
```

### 保存形式はファイルの中身を読む

```swift
// cat して確かめられることを利点にしているので、秒数の小数で書かれていないことを押さえる。
let text = try String(contentsOf: file, encoding: .utf8)
check("日時が ISO 8601 で書かれている", text.contains("2026-04-01T"), true)
```

### 実装を写せない形（性質）

QuickCheck、Hypothesis、Wlaschin の7分類、metamorphic testing。

| 性質 | 書き方 |
|---|---|
| 道が違っても着く先は同じ | `f(a, b) == f(b, a)`、`sort(shuffle(xs)) == sort(xs)` |
| 行って戻る | `decode(encode(x)) == x` を代表値で回す |
| 変わらないもの | 変換の前後で要素数・合計・並びが保たれる |
| 2度やっても1度と同じ | `f(f(x)) == f(x)`。同じ種なら同じ結果 |
| 求めるのは難しいが確かめるのは易しい | 並べ替えの結果が非減少で、元と同じ要素を持つ |
| 別の実装と照らす | 遅いが素直な実装、または前の版と同じ答えを返す |
| 並び順が実装の都合なら集合で比べる | `sorted(result) == sorted(expected)` |
| 出力の全部が条件を満たす | 出力を回して1つずつ確かめる。「提案した色は、関わる全ての組で 4.5:1 以上」 |
| 並行の両側 | 最大同時数が上限を**超えない** かつ **2 以上**（本当に並行している） |
| 返ってくること | 別 goroutine で走らせ、`time.After` で打ち切る。返らないのは close 忘れか待つ相手の間違い |
| 混ざらないこと | 並行に書いたログの各行が `msg=` をちょうど1つ含む。`-race` 付きで |

```go
var inflight, peak atomic.Int64
srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
	cur := inflight.Add(1)
	for { old := peak.Load(); if cur <= old || peak.CompareAndSwap(old, cur) { break } }
	time.Sleep(10 * time.Millisecond)
	inflight.Add(-1)
}))
run(srv.URL, Concurrency: 5)
switch got := peak.Load(); {
case got > 5: t.Errorf("同時に走った最大 = %d, 上限を超えている", got)
case got < 2: t.Errorf("同時に走った最大 = %d, 並行に撃てていない", got)
}
```

### 描画・出力も性質で

- 端末の表は「見出しは全角2文字＋2スペース」のように**幅の規則**で見る。`[]rune` で切る（表示幅はバイト数でもルーン数でもない）
- 色を付ける出力は、色あり／なしの両方で桁が揃うことを見る（詰めてから色を付けているか）
- 画像は `nil` でないことを見ても検査にならない。**描いてから塗られた割合を数える。** 「縁より塗りのほうが多い」のような関係で書く

### 書かないテストの実例

- `fetch` を差し替えて `mock.calls[0]` の body を `toEqual` するのは実装の写し。残すなら
  「このヘッダが無いと 400 が返る」のように**無いと何が起きるか**をコメントに書く。書けないなら消す
- 週の始まりは地域で変わる。「どの曜日から」ではなく
  `zip(grid, grid.dropFirst()).allSatisfy { $0.day + 1 == $1.day }` で「揃っているか」を見る
- 「速くて信頼できる」は本物の時計では両立しない（Go blog, synctest）

## 外に出ないための差し替え

| 出たくなるもの | 差し替え |
|---|---|
| HTTP の相手 | ローカルの偽サーバ。必要な endpoint だけ返す構造体を1つ（Go: `httptest.NewServer`） |
| HTTP ハンドラ | listen しない（Go: `httptest.NewRecorder` + `httptest.NewRequest`） |
| 環境変数 | `getenv` を引数で受け、テストは `map` を引く関数を渡す（下の罠） |
| 時計 | `now func() time.Time` を持つ／今日を引数で受ける |
| ファイル | 一時ディレクトリを注入し、別のインスタンスで開き直して書けたことを見る |
| 設定の保存先 | 名前つきの別の入れ物（`UserDefaults(suiteName: "test-\(UUID())")` + `defer removeSuite`） |
| キーボード・入力イベント | 判定を `process(event)` に切り出し、合成したイベントの列を流す |
| 画面・ハードウェア | 幾何を数字だけの関数にして、手元に無い実機の寸法を渡す |
| 乱数 | 生成器を引数で受け、テストは種つき（下） |
| 通信の層 | `(Request) async throws -> (Data, Response)` を注入 |
| 署名の検証 | **モックにしない。** 鍵を作って本物の署名の札を作り、宛先違いを弾くか見る |
| DB | 手書きの偽物（インメモリの表）。モックより fake（Google: 本物に近く振る舞う） |

差し替えるのは**管理外の依存**（他所のサービス、時計、乱数）だけ。自分で管理している DB やファイルは本物か fake を使う（Khorikov）。

入力イベントの形。イベント列と、起きてよいことの対応を表で流す。

```swift
static func check(_ name: String, _ events: [Event], expect: [Side]) {
    let watcher = Watcher()
    var fired: [Side] = []
    watcher.onTap = { fired.append($0) }
    for event in events { watcher.process(event) }
    ...
}
check("左⌘ 単独押し", [flags(CMD | LCMD), flags(0)], expect: [.left])
check("⌘C", [flags(CMD | LCMD), keyDown(CMD | LCMD), flags(0)], expect: [])
// 状態が持ち越されていないか
check("⌘C の直後に 左⌘ 単独", [flags(CMD | LCMD), keyDown(CMD | LCMD), flags(0), flags(CMD | LCMD), flags(0)], expect: [.left])
```

種を渡せない乱数（Swift の `SystemRandomNumberGenerator` など）は同じ問題を2度作れない。テスト側に置く。

```swift
struct SeededGenerator: RandomNumberGenerator {   // splitmix64
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
```

「同じ種なら同じ結果」を1ケース入れておく。ここが崩れると他のテストが毎回別の入力になる。

## 罠（実際に踏んだもの）

- **比較の補助関数は実際と期待を同じ型に縛る。** `check(_ name: String, _ actual: T, _ expected: T)`。
  別々の型にすると `Int?` と `Int` を渡せて、中身が同じでも `Optional(1)` と `1` で食い違って落ちる。
  Optional を比べるときは期待側を `.some(1)` と書く。
- **常に 0 を返す乱数を `shuffled(using:)` に渡すと返ってこない**（棄却法が終わらない）。
  並びを固定したいなら乱数を殺すのではなく、順序を渡す口（`ordered:`）を足す。
- **`os.Setenv` を使うテストは並列で壊れる。** 環境変数はプロセス全体で共有される。
  `Load(getenv func(string) string)` の形にして注入する。
- **画像は描くまで中身が無い。** SF Symbols の名前を打ち間違えても `nil` になるだけで何も言われず、
  「抜く」処理を間違えて全部消えていても画像は作れる。描いて数える。
- **UI の枠組みの拡張は、本体だけを別にコンパイルして初めて落ちる。** SwiftUI が足している
  `remove(atOffsets:)` を Foundation の型で使っても、同じモジュールに SwiftUI を import するファイルが
  あればアプリのビルドは通る。画面を持たないファイルだけを `swiftc` に渡すテストが検出器。
- **偽の DB を配列で持つなら、消すときはその場で削る。** 配列を作り直すと `Object.assign` で写した参照が古いまま。
- **`-race` は必ず付ける。** 集計を1つの goroutine に閉じ込め損ねると、テストは通っても `-race` が競合として見つける。

## 走らせ方の補足

- 割合の目安は unit 8割・結合 1.5割・端から端 0.5割（Google）。上に行くほど少なく
- iOS でも Foundation だけの `Day` / `Store` は macOS 上で `swiftc` でコンパイルして走る
- ブラウザが要るテスト（実測、描画）は Node のテストと別の project に分け、要るときだけ回す
- 変異スコアの道具: PIT、Stryker、Go の `gremlins` 等

## このスキル自体を確かめたこと（2026-09-23）

README に仕様があり、実装がそれと2か所で食い違う小さな Go パッケージに「テストを書いて `go test` を通せ」と頼み、
書かれたテストをバグ入りと直した実装の両方に当てた。効くテスト＝バグ入りで落ち、直した版で通る。

| モデル | スキル | 効くテストを書いた | 実装に合わせた期待値 | 壊して確かめた |
|---|---|---|---|---|
| Claude Fable 5.1 | 無し（別プロセス） | 2/2 | 0/2 | 0/2 |
| Claude Fable 5.1 | 説明文だけ | 2/2 | 0/2 | 0/2 |
| Claude Fable 5.1 | 本文を読んだ | 4/4 | 0/4 | 3/4 |
| Claude Haiku 4.5 | 無し | 1/2 | **1/2**（食い違いに気づいた上で「現在の実装に合わせて作成」） | 0/2 |
| Claude Haiku 4.5 | 本文を読んだ | 2/2 | 0/2（1本は実装のほうを直した） | 1/2（ただし `t.Logf` の無効なテストとして） |

- 強いモデルでは「仕様から起こす」「落ちたら実装を疑う」はもう既定の振る舞いで、上乗せは「壊して確かめる」だけ。
- 弱いモデルでは、食い違いに気づいてもテストを実装に合わせる方に倒れることがあり、スキルがそれを止めた。

続けて、研究が問題にしている難しい3場面を Haiku 4.5 で測った（`SKILL.md` を手順だけに分割した後。各条件2本、別プロセス）。

| 場面 | スキル無し | スキルあり |
|---|---|---|
| **A 自分で実装した直後**（README と `panic("TODO")` の骨組みを渡し、実装とテストを書かせる） | 2/2 実装が仕様どおり、2/2 テストがバグ入りを暴く | 同じ（1本は壊して確かめた） |
| **B 仕様書が無い**（意図は関数のコメントにだけあり、コードはそれと食い違う） | **2/2 が矛盾に気づいて報告した上で、テストは実装に合わせた**（バグ入りで通り、直した版で落ちる） | 2/2 がコメントを仕様として実装を直し、テストはバグ入りで落ち直した版で通る |
| **C 落ちているテストを通せ**（仕様どおりのテストが落ちている） | 2/2 実装を直し、テストは触らず | 同じ |

- 差が出たのは B だけ。仕様書が無く、目の前のコードが意図と食い違うとき、弱いモデルは**気づいていても写す**。
  スキルの手順2（実装を読む前に仕様を一段落書く）と手順4（落ちたら実装を疑う）がこれを変えた。
- A と C は Haiku でも既定で正しく、スキルの上乗せは無い。「自分で実装した直後」は、仕様が明文化されていれば問題が起きなかった。
  問題が起きるのは仕様が無いときで、B がそれに当たる。
- 本数は各2本。傾向どまり。B のスキルありは、頼まれていない実装の修正まで行った（報告はしている）。

## 出どころ

LLM・エージェントが書くテストについて:

- Google Testing Blog, Change-Detector Tests Considered Harmful (2015) — https://testing.googleblog.com/2015/01/testing-on-toilet-change-detector-tests.html
- Mathews & Nagappan, Design choices made by LLM-based test generators prevent them from finding bugs (2024, preprint) — https://arxiv.org/abs/2412.14137
- Zhao, Zhou & Cohen, Evaluating and Mitigating the Misguidance Effect of Buggy Code in LLM-Generated Unit Tests (ISSTA 2026) — https://arxiv.org/abs/2607.22883
- Li, Yu & Yuan, Escaping the Self-Repair Trap (2026, preprint) — https://arxiv.org/abs/2608.05917
- Wang, Xu, Briand & Liu, MUTGEN (IEEE TSE) — https://arxiv.org/abs/2506.02954
- Foster et al., Mutation-Guided LLM-based Test Generation at Meta (FSE 2025) — https://arxiv.org/abs/2501.12862
- SWE Atlas (2026, preprint; 弱い assertion が変異を通す) — https://arxiv.org/abs/2605.08366
- Anthropic, Claude 3.7 Sonnet / Claude 4 / Claude Sonnet 4.5 system cards（テストの書き換え、特別扱い、モックの検証） — https://www.anthropic.com/claude-4-system-card
- OpenAI, Monitoring Reasoning Models for Misbehavior (2025) — https://arxiv.org/abs/2503.11926
- METR, Recent Frontier Models Are Reward Hacking (2025) — https://metr.substack.com/p/2025-06-05-recent-reward-hacking

古典:

- Kent Beck, Test Desiderata — https://testdesiderata.com/ ／ Canon TDD — https://newsletter.kentbeck.com/p/canon-tdd
- Software Engineering at Google, ch.11–13 — https://abseil.io/resources/swe-book/html/ch11.html
- Google Testing Blog, Test Behaviors Not Methods (2014)、Don't Overuse Mocks (2013)、Mutation Testing (2021)
- Petrović & Ivanković, State of Mutation Testing at Google (ICSE-SEIP 2018)；Petrović et al., Does Mutation Testing Improve Testing Practices? (ICSE 2021) — https://arxiv.org/abs/2103.07189
- Martin Fowler, Eradicating Non-Determinism in Tests — https://martinfowler.com/articles/nonDeterminism.html ／ Mocks Aren't Stubs ／ SelfTestingCode ／ LegacySeam
- Vladimir Khorikov, When to Mock — https://enterprisecraftsmanship.com/posts/when-to-mock/
- Dan North, Introducing BDD — https://dannorth.net/introducing-bdd/
- Gerard Meszaros, xUnit Test Patterns（Erratic Test、Assertion Roulette、Obscure Test） — http://xunitpatterns.com/
- Claessen & Hughes, QuickCheck (ICFP 2000)；Hypothesis docs；Scott Wlaschin, Choosing properties for property-based testing — https://fsharpforfunandprofit.com/posts/property-based-testing-2/
- Go blog, Testing concurrent code with testing/synctest — https://go.dev/blog/synctest
