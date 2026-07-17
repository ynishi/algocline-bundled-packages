---
name: triangulate
version: 0.1.0
category: validation
result_shape: "shape { agreed: boolean, answers: array of string, final: string, history: array of shape { results: array of shape { answer: string, method: string, raw: string }, round: number }, rounds_used: number }"
description: "Agreement-checked verification across N independent solution paths"
source: triangulate/init.lua
generated: gen_docs (V0)
---

# triangulate(Triangulate) — agreement-checked verification across N independent solution paths

> Solve the same task N times via deliberately independent methods (alternative decomposition / independent derivation / reverse-computation check) and compare the structured answers. When the paths agree, the answer is confirmed with no verifier call and no extra cost; when they disagree, only the mismatch is fed back into a bounded reconsideration loop, so verification cost is paid only when an error actually exists.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [API](#api)
- [Comparison with related packages](#comparison-with-related-packages)
- [Caveats](#caveats)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local triangulate = require("triangulate")
return triangulate.run({ task = "Compute the number of trailing zeros in 100!." })
```

## Algorithm {#algorithm}

1. **Diversify** — build N method hints. When `ctx.methods` is given, each hint
   drives one path (path count = `#ctx.methods`). Otherwise a default persona
   group is used whose hints explicitly induce route independence.
2. **Solve in parallel** — one `alc.llm_batch` round-trip runs all N paths at
   once. Each path is instructed to end with a single `ANSWER:` marker line so
   the final answer can be extracted structurally.
3. **Agreement check** — extract each path's `ANSWER:` answer, normalize it
   (trim / lowercase / whitespace-collapse / trailing-punctuation strip), and
   test for an exact match across all paths. Agreement → confirmed, stop.
4. **Reconsider on mismatch** — when paths disagree, present the per-path answers
   (the mismatch points) back to every path and re-solve in another parallel
   round, up to `ctx.max_rounds` times. If the paths still split, the result is
   returned with `agreed = false` — the disagreement is surfaced, never hidden.

## API {#api}

- `ctx.task`       — string, required. Empty / whitespace-only → error.
- `ctx.n`          — number, optional. Independent path count (default 2).
  Ignored when `ctx.methods` is provided (its length wins).
- `ctx.methods`    — string array, optional. Per-path method hints. Omitted →
  a default persona group that induces route independence.
- `ctx.max_rounds` — number, optional. Max reconsideration rounds after the
  initial solve when paths disagree (default 1). Total solve rounds ≤
  `1 + max_rounds`.

Result (`ctx.result`):
- `final`       — string, the confirmed answer when agreed; otherwise the final
  round's plurality answer (path 1 wins ties).
- `agreed`      — boolean, whether the final round's paths reached exact match.
- `rounds_used` — number, solve rounds executed (initial round counts as 1).
- `answers`     — string array, the final round's per-path extracted answers.
- `history`     — array of `{ round, results = [ { method, answer, raw } ] }`
  recording every round's per-path method, extracted answer, and raw response.

## Comparison with related packages {#comparison-with-related-packages}

vs `verify_select` (selection): `verify_select` generates N candidates then
spends a dedicated verifier pass to *select* the best — verification cost is
always paid. This spends no verifier: agreement across independent paths *is*
the acceptance signal, so the deterministic (already-agreeing) regime costs
only the N parallel solves.

vs `sc` (self-consistency, majority vote): `sc` samples the *same* method many
times and tallies identical answers, so correlated mistakes (a shared reasoning
flaw) survive the vote. Triangulation instead varies the *method* per path — the
classic surveying idea of fixing a point from independent bearings — so
independent routes must coincidentally share an error to agree wrongly, which
is far less likely than a majority of same-method samples repeating one mistake.

## Caveats {#caveats}

- Agreement is only as strong as the route independence. With `ctx.methods`
  omitted the default persona group is engineered to pull paths apart; supplying
  near-identical `ctx.methods` collapses the guarantee toward `sc`-style
  correlated voting.
- The per-call token budget (`ctx.solve_tokens`, default 500) is an
  implementation knob left undeclared in `M.spec`; it bounds each path's
  response and is not part of the stable contract.
- On a persistent split the result reports `agreed = false` rather than forcing
  a winner. Callers that must always act should branch on `agreed` and treat
  `final` (the plurality / path-1 answer) as a low-confidence fallback.

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.max_rounds` | number | optional | Maximum reconsideration rounds after the initial solve when paths disagree (default: 1; implementation choice — one re-convergence attempt bounds worst-case cost; total solve rounds <= 1 + max_rounds) |
| `ctx.methods` | array of string | optional | Per-path method hints, one path per entry (path count becomes #methods). Omitted → a default persona group whose hints induce route independence (alternative decomposition / independent derivation / reverse-computation check) |
| `ctx.n` | number | optional | Number of independent solution paths (default: 2; implementation choice — two paths already surface a disagreement while holding cost at 2x; ignored when ctx.methods is provided, whose length sets the path count) |
| `ctx.task` | string | **required** | Task/problem to solve and triangulate (required, non-empty) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `agreed` | boolean | — | True if the final round's paths reached an exact normalized match |
| `answers` | array of string | — | Final round's per-path extracted answers |
| `final` | string | — | Confirmed answer when agreed; otherwise the final round's plurality answer (path 1 wins ties) |
| `history` | array of shape { results: array of shape { answer: string, method: string, raw: string }, round: number } | — | Ordered per-round record of every path's method/answer/raw |
| `rounds_used` | number | — | Solve rounds executed (initial round counts as 1) |
