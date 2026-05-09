---
name: recipe_ranking_funnel
version: 0.1.0
category: recipe
result_shape: funnel_ranked
description: "Verified 3-stage ranking funnel — listwise screening, multi-axis scoring, pairwise final rank. -87% calls vs naive pairwise on N=8 (verified). Encodes known failure modes as caveats."
source: recipe_ranking_funnel/init.lua
generated: gen_docs (V0)
---

# recipe_ranking_funnel(RecipeRankingFunnel) — verified 3-stage ranking funnel

> Recipe package that composes `listwise_rank` and `pairwise_rank` into a cost-efficient funnel for ranking large candidate sets (`N ≥ 20`), applying the IR classic `Recall (cheap) → Precision (medium) → Final Rank (expensive)` pattern.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [Caveats](#caveats)
- [Empirical validation](#empirical-validation)
- [References](#references)
- [Result](#result)

## Usage {#usage}

```lua
local funnel = require("recipe_ranking_funnel")
return funnel.run(ctx)
```

## Algorithm {#algorithm}

1. `listwise_rank` — coarse screening. Rank all N candidates via
   sliding-window listwise permutation; keep `top_k1` (default
   `ceil(N/3)`). Cost: `O(N / window_size)` LLM calls.
2. Multi-axis LLM scoring — score survivors on quality axes
   (correctness, completeness, relevance), rank by average, keep
   `top_k2` (default `min(top_k1, 5)`). Cost: `top_k1` LLM calls.
   With defaults, Stage 2 fires only when `top_k1 > 5` (i.e.
   `N >= 16`); otherwise `#survivors_1 == top_k2` and Stage 2 is
   skipped (flagged as `scoring_skipped`). Pass `ctx.top_k2`
   explicitly lower than `top_k1` to force it on smaller N.
3. `pairwise_rank` — precise pairwise comparison of the final
   `top_k2` candidates in `allpair` mode with bidirectional
   position-bias cancellation. Cost: `top_k2 · (top_k2 - 1)` LLM
   calls.

The composition reflects: `listwise_rank` screens cheapest (1 LLM
call per window, no calibration problem); multi-axis scoring is a
middle-ground evaluation; `pairwise_rank` is the most accurate
LLM-as-judge method but `O(N²)` — applying it only to `top_k2 ≤ 5`
keeps cost manageable.

## Caveats {#caveats}

See `M.caveats` for the full list. Key items: `listwise window_size
< ceil(N/2)` loses top candidates; `N < 6` makes the funnel
overhead counterproductive; `pairwise allpair` on `N > 12`
explodes.

## Empirical validation {#empirical-validation}

Not yet populated. Run `alc_eval` with a ranking scenario and fill
`M.verified` from the actual eval record.

## References {#references}

- Sun, W. et al. (2023). "Is ChatGPT Good at Search?". EMNLP 2023.
- Qin, Z. et al. (2024). "Large Language Models are Effective Text
  Rankers with Pairwise Ranking Prompting". NAACL 2024.
- Inoue, Y. et al. (2025). "Wider or Deeper? Scaling LLM
  Inference-Time Compute with Adaptive Branching Tree Search".
  NeurIPS 2025.
ctx.judge_gen_tokens: Max tokens per pairwise judgement call in
    Stage 3 (and in the N<6 direct-pairwise bypass). Pairwise
    judgements only need a short verdict (e.g. "A>B"), so this
    defaults to 20 — lower than gen_tokens on purpose. (default: 20)

## Result {#result}

Returns `funnel_ranked` shape:

| key | type | optional | description |
|---|---|---|---|
| `best` | string | — | Top-ranked text |
| `best_index` | number | — | Top-ranked original index (1-based) |
| `bypass_reason` | string | optional | Reason for bypass (nil when not bypassed) |
| `funnel_bypassed` | boolean | — | True when N < 6 bypasses funnel stages |
| `funnel_shape` | array of number | — | Candidate counts per stage [N, s1_out, s2_out] |
| `naive_baseline_calls` | number | — | Hypothetical full-pairwise call count |
| `naive_baseline_kind` | string | — | Baseline method identifier |
| `ranking` | array of shape { original_index: number, pairwise_score: number, rank: number, text: string } | — | Final ranking |
| `savings_percent` | number | optional | LLM call savings vs baseline (nil on bypass) |
| `stages` | array of discriminated by "name" | — | Per-stage detail (discriminated by name) |
| `total_llm_calls` | number | — |  |
| `warnings` | array of shape { code: string, data: table, message: string, severity: one_of("warn", "critical") } | — | Diagnostic warnings |
