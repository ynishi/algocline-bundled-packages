---
name: sc
version: 0.2.0
category: aggregation
result_shape: voted
description: "Independent multi-path sampling with majority vote aggregation"
source: sc/init.lua
generated: gen_docs (V0)
---

# sc — Self-Consistency: independent sampling with majority vote

> Samples multiple reasoning paths for the same problem, then selects the most consistent answer by majority voting.

## Contents

- [Algorithm](#algorithm)
- [Usage](#usage)
- [Caveats](#caveats)
- [Comparison with related packages](#comparison-with-related-packages)
- [References](#references)
- [Result](#result)

## Algorithm {#algorithm}

1. Sample `n` independent reasoning paths for the same task (varied via
   `temperature_hint` for diversity)
2. Extract a normalized answer per path
3. Tally votes; the majority answer wins (with `consensus` LLM-synthesized
   summary across the winning paths)

## Usage {#usage}

```lua
local sc = require("sc")
return sc.run(ctx)
```

## Caveats {#caveats}

`gen_tokens` is exposed but other token budgets (extract / consensus)
are intentionally NOT exposed as ctx knobs. Per-knob workflow simulation
showed that no consumer workflow can tune those integers alone without
ALSO changing the coupled prompt or signal path. If a future workflow
truly demands tuning, design the coupled pieces together (prompt override
+ token budget, or structured contract + parser + budget) — do NOT simply
expose the integers. See call-site comments below for the per-knob
analysis.

## Comparison with related packages {#comparison-with-related-packages}

vs `panel` / `moa`: those use heterogeneous personas / models. `sc` uses
a single agent with sampling-induced diversity. Cheaper but lower coverage.

vs `usc` (Universal Self-Consistency): `usc` lets the LLM pick the best
among samples (LLM-as-judge). `sc` uses deterministic majority voting.

## References {#references}

Wang et al. (2022). "Self-Consistency Improves Chain of Thought Reasoning
in Language Models". arXiv:2203.11171.

## Result {#result}

Returns `voted` shape:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | optional | Majority answer (nil when no paths converge) |
| `answer_norm` | string | optional | Normalized vote key |
| `consensus` | string | — | LLM-synthesized majority summary |
| `n_sampled` | number | — | Number of sampled paths |
| `paths` | array of shape { answer: string, reasoning: string } | — | Per-path reasoning + extracted answer |
| `total_llm_calls` | number | — |  |
| `vote_counts` | map of string to number | — | { [norm] = count } tally |
| `votes` | array of string | — | Normalized vote per path, 1-indexed |
