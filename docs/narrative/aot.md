---
name: aot
version: 0.1.0
category: reasoning
result_shape: "shape { depth_used: number, final_answer: string, final_question: string, initial_depth_budget: number }"
description: "Atom of Thoughts — Markov test-time scaling via DAG decompose + contract."
source: aot/init.lua
generated: gen_docs (V0)
---

# aot(AoT) — Atom of Thoughts: Markov test-time scaling via DAG contraction

> Decomposes a question into an atomic-state DAG, contracts the independent atoms into the dependent ones to produce a smaller self-contained question, and iterates until depth budget is reached. Each contracted question is answerable from its predecessor alone (Markov property), so the reasoning trace does not need to retain earlier history.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [Caveats](#caveats)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local aot = require("aot")
return aot.run(ctx)
```

## Algorithm {#algorithm}

1. decompose: ask the LLM to split the question into subquestions
   with a dependency annotation (DAG `{id, text, depend: [ids]}`).
2. On the first iteration, set the depth budget D from the longest
   path through the initial DAG (`get_max_path_length`).
3. split_indep_dep: separate subquestions with no incoming edges
   (independent atoms) from those with incoming edges (dependent).
4. contract: ask the LLM to fold the independent atoms into the
   dependent ones as known conditions, producing a new self-contained
   question for the next iteration.
5. Repeat steps 1-4 until the depth budget is exhausted.
6. solve: ask the LLM to answer the final contracted question
   directly. No aggregation across history.

## Caveats {#caveats}

The contraction step depends critically on the quality of the
**first** DAG decomposition (paper §7 limitation). When the initial
decomposition fails to capture parallelism / independence the
contracted question can drift away from the original (Appendix C.1
"illusions"). The `consistency_check` knob enables an optional
per-iteration check that asks the LLM whether the contracted
question still serves the original; paper §4.3 introduces this as a
refinement outside Algorithm 1, off by default to match the base
algorithm.

The depth budget D is fixed on the first iteration from
`GetMaxPathLength(G_0)` (Algorithm 1 line 6) and never recomputed.
The `max_depth` knob caps D to prevent runaway when an LLM emits a
long pathological decomposition; setting it to nil reproduces paper
behaviour.

The paper's "AoT*" variant performs N independent runs and lets the
LLM pick the best answer (§5). The `final_aggregation_runs` knob
exposes this; default `1` corresponds to the base algorithm. Set to
`3` for the AoT* configuration described in the paper.

The decomposition LLM call returns a JSON object that this pkg
parses via `alc.json_decode` with a regex-based bracket fallback
(sibling pattern to dci). If the LLM emits an unparseable payload,
iteration aborts and the current question is solved directly.

## References {#references}

- Teng, F., Yu, Z., Shi, Q., Zhang, J., Wu, C., Luo, Y. (2025).
  "Atom of Thoughts for Markov LLM Test-Time Scaling". NeurIPS 2025
  / arXiv:2502.12018. §3.3 Algorithm 1, §4 decomposition / contract,
  §4.3 consistency_check refinement, §7 limitations.
  https://arxiv.org/abs/2502.12018
- Official implementation: https://github.com/qixucen/atom

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.consistency_check` | boolean | optional | Enable the §4.3 optional refinement that verifies contraction quality each iteration (default: false; paper §4.3 introduces this outside Algorithm 1) |
| `ctx.contract_prompt_template` | string | optional | Override template for the contract phase (default derives from paper Appendix B.3) |
| `ctx.contract_tokens` | number | optional | Token cap for each contract LLM call (default: 600) |
| `ctx.decompose_prompt_template` | string | optional | Override template for the decompose phase (default derives from paper Appendix B.2) |
| `ctx.decompose_tokens` | number | optional | Token cap for each decompose LLM call (default: 800) |
| `ctx.final_aggregation_runs` | number | optional | Number of independent runs whose answers are pooled by an LLM selector — paper §5 AoT* variant (default: 1 = base algorithm, set to 3 for AoT*) |
| `ctx.max_depth` | number | optional | Hard cap on the depth budget D (default: nil = paper behaviour, no cap; implementation choice — runaway protection) |
| `ctx.solve_prompt_template` | string | optional | Override template for the solve phase (default: plain answer prompt) |
| `ctx.solve_tokens` | number | optional | Token cap for the final solve LLM call (default: 500) |
| `ctx.task` | string | **required** | Original question to solve |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `depth_used` | number | — | Number of contraction iterations actually executed |
| `final_answer` | string | — | Direct answer to the final contracted question |
| `final_question` | string | — | Final contracted question that solve was applied to |
| `initial_depth_budget` | number | — | Depth D fixed on the first iteration from GetMaxPathLength(G_0), before max_depth cap |
