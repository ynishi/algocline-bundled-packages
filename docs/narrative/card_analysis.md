---
name: card_analysis
version: 0.1.0
category: debugging
result_shape: "shape { confidence: number, failure_count?: number, pattern: string, sample_count?: number, suggested_change: string }"
description: "Card failure analyzer — single-card improvement hint generator"
source: card_analysis/init.lua
generated: gen_docs (V0)
---

# card_analysis(CardAnalysis) — Card failure analyzer with one-line improvement hint

> Reads a Card body + its samples sidecar, detects failure samples across common shape conventions, asks the LLM for one structured improvement hint (pattern + suggested_change + confidence).

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [Failure detection](#failure-detection)
- [Output (`ctx.result`)](#output-ctx-result)
- [Caveats](#caveats)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

Normally invoked via the host MCP tool:

```jsonc
alc_card_analyze({ card_id: "<id>", pkg: "card_analysis" })
```

Direct Lua usage (testing / custom hosts):

```lua
local card_analysis = require("card_analysis")
return card_analysis.run({
    card_id = "...",
    card    = <full card body>,
    samples = { ... },  -- raw samples.jsonl rows
})
```

## Algorithm {#algorithm}

Three-step single-shot analyzer:

1. **Failure detection** — scan `ctx.samples` for failure rows using
   a multi-heuristic OR (admission/status/passed/score), then build
   the analysis pool (failures, or all samples on no-signal fallback).
2. **Prompt build** — render the first ≤8 failures with a stable
   field projection (`name` / `case` / `input` / `prompt` / `expected`
   / `response` / `detail` / `score` / `grades`), each value compacted
   to ≤400 chars, plus Card metadata (`pkg.name` / `scenario.name`
   / `model.id`).
3. **LLM + JSON parse** — single `alc.llm` call requesting STRICT JSON;
   `alc.json_extract` parses the response. On parse failure the raw
   output is preserved verbatim (compacted) in `_raw_llm` and a
   sentinel result is returned with `confidence = 0.0`.

## Failure detection {#failure-detection}

Sample shapes vary across pkgs. The analyzer recognizes any of:

  * `admission == "fail"`            (flow_design / flow_refine_orch)
  * `status   == "fail" | "error"`   (status-based pkgs)
  * `passed   == false`              (recipe_safe_panel pattern)
  * `score    < 0.5`                 (numeric grader)

If none of those signals are present, the pkg falls back to "all
samples are interesting" and lets the LLM judge.

## Output (`ctx.result`) {#output-ctx-result}

```jsonc
{
  "pattern":          "<one-line failure pattern summary>",
  "suggested_change": "<concrete prompt or Lua-level change>",
  "confidence":       0.0–1.0,
  "failure_count":    <int>,    // optional (always present in current impl)
  "sample_count":     <int>     // optional (always present in current impl)
}
```

The output shape is locked to the host-side typed struct
`algocline-app::service::card::CardAnalyzeResult` so the result
round-trips through MCP without re-encoding.

## Caveats {#caveats}

- Single LLM call by design; no chain / no self-critique. Higher-quality
  analysis loops belong in a separate pkg (e.g. recipe-style multi-step).
- The first 8 failures are sampled when the failure pool exceeds 8;
  later failures are not visible to the LLM in this version.
- On `samples == 0`, returns a no-samples sentinel without calling the
  LLM (cost-free guard).

## References {#references}

- Host MCP tool contract: `algocline-mcp::service::alc_card_analyze`
  (algocline crate, ctx contract literal in tool description).
- Host result struct: `algocline-app::service::card::CardAnalyzeResult`.

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.card` | any | **required** | Full Card body (host-loaded from card_id) |
| `ctx.card_id` | string | **required** | Card identifier (host-provided) |
| `ctx.samples` | array of any | **required** | samples sidecar rows (host-loaded; may be empty) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `confidence` | number | — | 0.0..=1.0 diagnostic confidence |
| `failure_count` | number | optional | Detected failure sample count (Option<u64> on host side) |
| `pattern` | string | — | One-line failure pattern summary |
| `sample_count` | number | optional | Total samples processed (Option<u64> on host side) |
| `suggested_change` | string | — | Concrete change proposal (1-3 sentences, actionable) |
