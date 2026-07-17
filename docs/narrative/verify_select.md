---
name: verify_select
version: 0.1.0
category: selection
result_shape: "shape { candidates: number, rationale: string, selected: string, verdicts: array of shape { index: number, score: number, verdict: string } }"
description: "Generate-then-verify best-of-N selection via a rubric verifier"
source: verify_select/init.lua
generated: gen_docs (V0)
---

# verify_select(VerifySelect) — generate-then-verify best-of-N selection

> A boost strategy aimed at 26-generation models, positioned as a successor to self-consistency (`sc`, majority vote). Instead of tallying identical answers, it samples `n` diverse candidates in a single parallel round-trip (`alc.llm_batch`), then runs a single verifier pass (`alc.llm`) that scores every candidate against a rubric and selects the best with a rationale.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [API](#api)
- [Comparison with related packages](#comparison-with-related-packages)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local vs = require("verify_select")
return vs.run(ctx)
```

## Algorithm {#algorithm}

1. Generate `n` candidates in one `alc.llm_batch` round-trip. Each batch
   item carries a distinct system persona to induce diversity (temperature
   diversity is assumed on the host side).
2. Run one `alc.llm` verifier pass. The verifier receives ALL candidates
   plus the rubric, scores each 0-10, and emits a structured verdict block
   with `SELECTED:` and `RATIONALE:` markers.
3. Parse the verdict block into per-candidate `{ index, score, verdict }`
   records, resolve the selected candidate, and return it with the rationale.

## API {#api}

- `ctx.task`   — string, required. Empty / whitespace-only → error.
- `ctx.n`      — number, optional. Candidate count (default 3).
- `ctx.rubric` — string, optional. Selection criteria injected verbatim
  into the verifier prompt. Omitted → a generic accuracy/completeness rubric.

Result (`ctx.result`):
- `selected`   — string, the winning candidate text.
- `candidates` — number, how many candidates were generated.
- `verdicts`   — array of `{ index, score, verdict }`, one per candidate.
- `rationale`  — string, the verifier's justification for the selection.

## Comparison with related packages {#comparison-with-related-packages}

vs `sc`: `sc` deterministically majority-votes identical answers. This
picks the highest-quality answer via a rubric verifier — better when
candidates diverge in quality rather than converging on one answer.

vs `rank`: `rank` runs an O(n) pairwise elimination tournament (many
`alc.llm` calls). This uses a single verifier pass over all candidates
(2 round-trips total) — cheaper, at the cost of pairwise granularity.

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.n` | number | optional | Number of candidates to generate (default: 3) |
| `ctx.rubric` | string | optional | Selection criteria injected into the verifier prompt (default: generic accuracy/completeness rubric) |
| `ctx.task` | string | **required** | Problem to solve (required, non-empty) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `candidates` | number | — | Number of candidates generated |
| `rationale` | string | — | Verifier justification for the selection |
| `selected` | string | — | The winning candidate text |
| `verdicts` | array of shape { index: number, score: number, verdict: string } | — | Per-candidate verifier records |
