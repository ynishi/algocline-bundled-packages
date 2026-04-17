# algocline docstring convention (V0)

**Status**: V0 — single specification. No legacy / fallback modes.
**Scope**: `{pkg}/init.lua` の先頭 `---` ブロック + `M.meta` 宣言
**Generator**: `tools/gen_docs.lua` (Pure Lua)
**Lint**: `tools/gen_docs.lua --lint-only` / `--strict`

## 0. 思想

- docstring は **Markdown として valid**
- heuristic は一切持たない。explicit Markdown 構文のみで成立させる
- generator の責務は「`---` prefix を剥がして Markdown として投影する」だけ
- 規約違反は `lint` が **error** として検出し、`--strict` で build を止める

## 1. Docstring の全体構造

```lua
--- {Pkg} — {one-liner}
---
--- {abstract: 1-3 文の概要}
---
--- ## {Section 1}
---
--- {body}
---
--- ## {Section 2}
--- ...
```

### 1.1. 必須要素

| 要素 | 形式 | 備考 |
|---|---|---|
| 1 行目 | `{Pkg} — {one-liner}` | `{Pkg}` は pkg 名、`—` は em dash。generator はこれを `# H1` title として投影 |
| summary | 平文 1-3 文 | 1 行目の下、空行を挟んで書く。H2 に入るまで継続と解釈される |

### 1.2. 推奨 Section

pkg の複雑度に応じて H2 を追加する。セクション名は自由だが、以下が慣例:

| Section | いつ書くか |
|---|---|
| `## Usage` | 最小呼び出し例。ほぼ全 pkg で推奨 |
| `## When to use` | 類似 pkg との使い分けが非自明な場合 |
| `## Algorithm` | アルゴリズムが 3 段階以上ある場合 |
| `## Theoretical foundations` | 論文背景 / 理論根拠 |
| `## Caveats` | 既知の制約 / 適用範囲 |
| `## Empirical validation` | 実測データ / ベンチマーク |
| `## Comparison with related packages` | 同カテゴリに類似 pkg がある場合 |
| `## References` | 原著論文 / 文献リスト |

**`## Parameters` は書かない** — §6 を参照。

## 2. Heading

- H1 (`#`) は **書かない** (generator が 1 行目から合成する)
- H2 (`##`) を最上位の section 分割に使う
- H3 (`###`) は H2 の subsection として使う
- H4 以下は使わない
- heading 直後は必ず 1 行空ける

NG 例:

```lua
--- ## Algorithm
---   1. step                  ← 空行なしで list 開始
```

OK 例:

```lua
--- ## Algorithm
---
--- 1. step
```

## 3. Code fence

- **fence は explicit** (`` ``` ``) のみ。4-space indent fence は禁止
- 言語指定は任意。Lua コードなら `` ```lua `` を**推奨**
- 数式は `` ```math `` を使う (GitHub MathJax で rendering される)
- 1 snippet = 1 fence。複数 snippet は独立 fence で並べる

```lua
--- ## Usage
---
--- ```lua
--- local pkg = require("pkg")
--- return pkg.run(ctx)
--- ```
```

数式:

```lua
--- ## Equation
---
--- ```math
--- \chi^2 = \sum_{i=1}^{N} \frac{(O_i - E_i)^2}{E_i}
--- ```
```

inline:

```lua
--- Calls `ctx.llm()` internally.
```

## 4. Lists

### 4.1. Bullet

- `-` (hyphen) を使う。`*` / `+` は禁止
- インデントは半角 2 スペース

```lua
--- Available strategies:
---
--- - ucb: upper confidence bound
--- - panel: role diversity
```

### 4.2. Numbered

- `1.` / `2.` / `3.` で書く
- サブ項目は 3 スペースインデント + bullet

```lua
--- ## Algorithm
---
--- 1. Generate N candidates
--- 2. For each rubric dimension:
---    - Query judge
---    - Rank within block
--- 3. Return ranking by mean rank
```

letter-numbering (`a.` / `b.`) は renderer 依存なので禁止。

## 5. References

bullet list として書く。fence で囲まない。継続行は 2 スペースインデント。

```lua
--- ## References
---
--- - Friedman, M. (1937). "The use of ranks to avoid the assumption of
---   normality ...," J. Am. Stat. Assoc. 32(200): 675–701.
--- - Nemenyi, P. B. (1963). "Distribution-free Multiple Comparisons,"
---   PhD thesis, Princeton University.
```

論文への link は References 内で書く。body に裸 URL を書かない。

## 6. Parameters — `M.meta.input_shape` を SSoT とする

**原則**: Parameters は docstring に書かない。必ず `M.meta.input_shape` に `alc_shapes` DSL で declare する。generator が `## Parameters` table を自動合成する。

```lua
local S = require("alc_shapes")
local T = S.T

M.meta = {
    name         = "f_race",
    version      = "0.1.0",
    category     = "selection",
    description  = "Friedman race — rank-based early stopping",
    input_shape  = T.shape({
        task         = T.string:describe("Problem statement"),
        n_candidates = T.number:is_optional():describe("Number of candidates (default 6)"),
        rubric       = T.array_of(T.shape({
            name      = T.string,
            criterion = T.string,
        })):is_optional():describe("Rubric dimensions"),
        delta        = T.number:is_optional():describe("Significance level (default 0.05)"),
    }, { open = true }),
    result_shape = "...",
}
```

Generator が展開する Parameters table:

| key | type | required | description |
|---|---|---|---|
| `ctx.delta` | number | optional | Significance level (default 0.05) |
| `ctx.n_candidates` | number | optional | Number of candidates (default 6) |
| `ctx.rubric` | array of shape | optional | Rubric dimensions |
| `ctx.task` | string | **required** | Problem statement |

`lint` は `input_shape` が宣言済みで同時に `## Parameters` section が docstring に書かれている場合 `E_PARAMETERS_CONFLICT` error を返す。

## 7. Comparison with related packages

bullet list + 各行 `pkg名 — 説明`:

```lua
--- ## Comparison with related packages
---
--- - `cs_pruner` — anytime-valid CS, requires t in the hundreds.
--- - `gumbel_search` — Sequential Halving, batched.
--- - `listwise_rank` — post-hoc full ranking, no early stop.
```

## 8. Luadoc annotations

`---@param` / `---@return` / `---@type` 等は **narrative の後** に集約する。generator はこの行で docstring 抽出を打ち切る。

```lua
--- Pkg — one-liner
---
--- {narrative …}
---
---@type AlcMeta
local M = {
  meta = { … }
}

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx) … end
```

## 9. Encoding

- UTF-8 のみ
- em dash `—` / en dash `–` は使用可
- 日本語は書かない (公開用途のため英語統一)

## 10. Links

GitHub-style link:

```lua
--- See [the README](../README.md) for the derivation.
```

裸 URL は禁止 (References section 内の citation のみ許可)。

## 11. 禁止事項

| NG | 理由 |
|---|---|
| H1 (`#`) | generator が自動生成するため重複 |
| `$...$` / `$$...$$` inline LaTeX | GitHub 外で rendering が壊れる |
| 4-space indent fence | explicit `` ``` `` に統一 |
| HTML tag (`<br>` 等) | Markdown のみ |
| 絵文字 | CRAN / llms.txt 環境で壊れる |
| 3 層以上の list nesting | renderer 依存 |
| `## Parameters` を手書き | §6 `input_shape` が SSoT |

## 12. `M.meta` 必須フィールド

| field | type | 用途 |
|---|---|---|
| `name` | string | pkg 識別子。ディレクトリ名と一致すること |
| `version` | string | SemVer |
| `description` | string | one-line 要約。frontmatter と llms.txt entry に投影 |
| `category` | string | llms.txt の grouping key |

推奨:

| field | type | 用途 |
|---|---|---|
| `input_shape` | `T.shape(...)` | §6 Parameters の SSoT |
| `result_shape` | string or `T.shape(...)` | frontmatter `result_shape:` |

## 13. Lint rule 一覧

`tools/gen_docs.lua --lint-only` で検出。`--strict` で error を build 失敗化。

| Code | Severity | 内容 |
|---|---|---|
| `E_H1_IN_DOCSTRING` | error | docstring 内に `# ` 行がある |
| `E_META_MISSING_NAME` | error | `meta.name` 欠落 |
| `E_META_MISSING_VERSION` | error | `meta.version` 欠落 |
| `E_META_MISSING_DESCRIPTION` | error | `meta.description` 欠落 |
| `E_META_MISSING_CATEGORY` | error | `meta.category` 欠落 |
| `E_NAME_MISMATCH` | error | `meta.name` ≠ pkg directory name |
| `E_PARAMETERS_CONFLICT` | error | `input_shape` 宣言 + `## Parameters` section 両立 |
| `W_FAKE_LABEL` | warning | `Usage:` / `Args:` 等の fake label。`## Usage` に昇格すべき |
| `W_EMPTY_NARRATIVE` | warning | summary も section も無い |
| `W_DESCRIPTION_MULTILINE` | warning | `meta.description` に改行が含まれる |

## 14. Reference 実装

`cot/init.lua` が V0 の golden example:

```lua
--- CoT — iterative chain-of-thought reasoning
---
--- Builds a reasoning chain step by step, then synthesizes the chain
--- into a single coherent conclusion.
---
--- ## Usage
---
--- ```lua
--- local cot = require("cot")
--- return cot.run({ task = "Why is the sky blue?", depth = 3 })
--- ```
---
--- ## Behavior
---
--- For each step `i` in `1..depth`, the LLM is asked for the next key
--- insight conditional on all prior insights. After the last step, a
--- final synthesis prompt collapses the chain into `result.conclusion`.

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name         = "cot",
    version      = "0.1.0",
    description  = "Iterative chain-of-thought — cumulative reasoning steps, then synthesis",
    category     = "reasoning",
    input_shape  = T.shape({
        task  = T.string:describe("The question or task to reason about"),
        depth = T.number:is_optional():describe("Number of reasoning steps (default: 3)"),
    }),
    result_shape = "shape",
}

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx) … end

return M
```

`tests/test_gen_docs.lua` が `cot/init.lua` を golden fixture として pin 留めしており、pipeline 改修時の回帰を即検知する。
