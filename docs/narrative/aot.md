---
name: aot
version: 0.2.0
category: reasoning
result_shape: "shape { depth_used: number, final_answer: string, final_question: string, initial_depth_budget: number }"
description: "Atom of Thoughts — Markov test-time scaling via DAG decompose + contract (Teng 2025 §3.3 Algorithm 1)."
source: aot/init.lua
generated: gen_docs (V0)
---

# aot(AoT) — Atom of Thoughts: Markov test-time scaling via DAG contraction

> Decomposes a question into an atomic-state DAG, contracts the independent atoms into the dependent ones to produce a smaller self-contained question, and iterates until the depth budget is exhausted. Each contracted question is answerable from its predecessor alone (Markov property), so the reasoning trace does not need to retain earlier history.

## Contents

- [Algorithm (paper §3.3, Algorithm 1 verbatim)](#algorithm-paper-3-3-algorithm-1-verbatim)
- [Phase order](#phase-order)
- [Implementation choices (paper does not prescribe; spelled out)](#implementation-choices-paper-does-not-prescribe-spelled-out)
- [Caveats](#caveats)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Algorithm (paper §3.3, Algorithm 1 verbatim) {#algorithm-paper-3-3-algorithm-1-verbatim}

```
Input:  Initial question Q_0
Output: Final answer A

 1: i ← 0
 2: D ← None
 3: while i < D or D is None do
 4:   G_i ← decomposeLLM(Q_i)               -- DAG decomposition
 5:   if D is None then
 6:     D ← GetMaxPathLength(G_i)           -- depth fixed at i=0 only
 7:   end if
 8:   Q_ind ← { Q_i ∈ Q | ∄ Q_j ∈ Q, (Q_j, Q_i) ∈ E }  -- indep atoms
 9:   Q_dep ← { Q_i ∈ Q | ∃ Q_j ∈ Q, (Q_j, Q_i) ∈ E }  -- dependent
10:   Q_{i+1} ← contractLLM(Q_ind, Q_dep)   -- SINGLE LLM call
11:   i ← i + 1
12: end while
13: A ← solveLLM(Q_D)                       -- direct solve, no aggregation
14: return A
```

## Phase order {#phase-order}

1. `decompose` — DAG decomposition (line 4). Returns subquestions
   with `{id, text, depend}` and a `parse_ok` flag distinguishing
   successful parses from silent empty returns.
2. `get_max_path_length` — pure DAG longest-path (line 6, first
   iteration only). Counted in nodes (paper does not specify
   nodes-vs-edges; nodes follows the §3.3 + Appendix A "solution
   depths" tabulation).
3. `split_indep_dep` — pure partition (lines 8-9).
4. `contract` — single LLM call that folds Q_ind into Q_dep as
   known conditions (line 10, Appendix B.3 prompt literal).
5. `solve` — direct answer (line 13). No history aggregation.

`M.run` uses **nested dispatch** (calls `M.decompose` /
`M.split_indep_dep` / `M.get_max_path_length` / `M.contract` /
`M.solve` through the `M` table, not internal closures) so the
`S.instrument` wrappers fire on every sub-call. This catches a bad
intermediate shape before it leaks into the outer result
(`alc_shapes/README` §Producer usage "Nested dispatch").

## Implementation choices (paper does not prescribe; spelled out) {#implementation-choices-paper-does-not-prescribe-spelled-out}

Every default below records its source explicitly in its inline
comment: paper-literal citations with section refs, industry-
standard heuristics with source links, or implementation-choice
rationale spelled out. No default is implicit.

 - `max_depth` = nil — Paper Algorithm 1 line 6 fixes D
   from `GetMaxPathLength(G_0)` with no upper cap. nil reproduces
   paper behaviour; a finite value protects against runaway when
   an LLM emits a pathologically long decomposition.
 - `consistency_check` = false — Paper §4.3 introduces
   consistency_check as an optional refinement outside Algorithm 1;
   off by default to match the base algorithm. Caveat — the
   paper §4.3 literal is "synthesized answer / Q_{i+1} result
   consistency", i.e. checks whether the cumulative answer is
   consistent with the next iteration's result. This pkg uses a
   text-level equivalence proxy ("does answering the contracted
   question imply a correct answer to the original?") which is
   cheaper at prompt level but evaluates a slightly different
   property; treat as an early-detection heuristic, not a literal
   paper §4.3 reproduction.
 - `final_aggregation_runs` = 1 — Paper §5 AoT* variant
   runs N=3 independent runs and asks an LLM selector to pick the
   best answer. Default 1 corresponds to base Algorithm 1; set 3
   for the paper's AoT* configuration.
 - `decompose_prompt_template` / `contract_prompt_template` /
   `solve_prompt_template` — Paper Appendix B.2 / B.3 give
   the template *intent* but no single verbatim string is fully
   transcribed in the paper body; the defaults below are written
   to capture the paper's instructions (JSON DAG output / known-
   conditions framing / direct answer) without being literal
   paper text. Callers requiring paper-exact prompts should grab
   the official Appendix wording and pass it via override.
 - `decompose_tokens` = 800 / `contract_tokens` = 600 /
   `solve_tokens` = 500 — Per-call generation caps. Paper
   does not specify (paper runs typical default OpenAI settings).
   Sized to fit typical JSON DAGs / contracted questions / direct
   answers; callers should override for verbose domains.
 - `consistency_tokens` = 16 — Consistency-check answer is
   a single yes/no word, 16 tokens is generous.
 - `selector_tokens` = 8 — AoT* selector returns a single
   digit (1..N). 8 tokens is generous.
 - `consistency_yes_token` = "yes" — Plain-text token
   that consistency_check uses to decide "keep iterating". Lower-
   cased substring match. Override if domain language differs.
 - sys prompts (`decompose_system_prompt`, `contract_system_prompt`,
   `solve_system_prompt`, `consistency_system_prompt`,
   `selector_system_prompt`) — All five system prompts are
   impl-authored persona conditioning text. Unlike s1 (which
   unifies sys across phases for the single-pass paper Qwen
   persona invariant), AoT's paper *does* separate
   decompose / contract / solve as distinct LLM calls (Algorithm 1
   lines 4, 10, 13), so per-phase persona conditioning here matches
   the paper's per-phase LLM call structure. The literal wording is
   impl choice; callers needing a different persona should fork the
   call_* helpers.

## Caveats {#caveats}

The contraction step depends critically on the quality of the
**first** DAG decomposition (paper §7 limitation). When the initial
decomposition fails to capture parallelism / independence the
contracted question can drift away from the original (Appendix C.1
"illusions"). Enable `consistency_check = true` to add a per-
iteration text-level proxy check.

The depth budget D is fixed on the first iteration from
`GetMaxPathLength(G_0)` (Algorithm 1 line 6) and never recomputed.
`max_depth` caps D to prevent runaway; setting nil reproduces paper
behaviour.

The decomposition LLM call returns a JSON object that this pkg
parses via `alc.json_decode` with a regex-based bracket fallback.
When parsing fails the loop terminates gracefully and the current
question is solved directly; `decompose.result.parse_ok` makes the
distinction explicit so callers can distinguish "no subquestions
needed" from "LLM returned unparseable text".

## References {#references}

- Teng, F., Yu, Z., Shi, Q., Zhang, J., Wu, C., Luo, Y. (2025).
  "Atom of Thoughts for Markov LLM Test-Time Scaling". NeurIPS 2025
  / arXiv:2502.12018. §3.3 Algorithm 1, §4 decomposition / contract,
  §4.3 consistency_check refinement, §5 AoT*, §7 limitations,
  Appendix B.2 / B.3 prompt templates.
  https://arxiv.org/abs/2502.12018
- Official implementation: https://github.com/qixucen/atom

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.consistency_check` | boolean | optional | Enable §4.3 optional refinement (default: false; paper §4.3 introduces this outside Algorithm 1). The paper §4.3 literal evaluates 'synthesized answer / Q_{i+1} result consistency'; this impl uses a text-level equivalence proxy ('does answering the contracted question imply a correct answer to the original?') as a cheaper prompt-level approximation. |
| `ctx.consistency_tokens` | number | optional | Token cap for the consistency_check LLM call (default: 16;— verdict is a single yes/no word) |
| `ctx.consistency_yes_token` | string | optional | Plain-text token consistency_check looks for to keep iterating (default: "yes"; implementation choice — lower-cased substring match) |
| `ctx.contract_prompt_template` | string | optional | Override template for the contract phase (default captures paper Appendix B.3 intent; implementation choice) |
| `ctx.contract_tokens` | number | optional | Token cap for each contract LLM call (default: 600; implementation choice) |
| `ctx.decompose_prompt_template` | string | optional | Override template for the decompose phase (default captures paper Appendix B.2 intent; implementation choice) |
| `ctx.decompose_tokens` | number | optional | Token cap for each decompose LLM call (default: 800; implementation choice) |
| `ctx.final_aggregation_runs` | number | optional | Independent runs whose answers are pooled by an LLM selector (default: 1 = base Algorithm 1; paper §5 AoT* variant uses N=3, set 3 to reproduce) |
| `ctx.max_depth` | number | optional | Hard cap on depth budget D (default: nil = paper behaviour, no cap; implementation choice — runaway protection for pathological decompositions) |
| `ctx.selector_tokens` | number | optional | Token cap for the AoT* selector LLM call (default: 8;— reply is a single digit) |
| `ctx.solve_prompt_template` | string | optional | Override template for the solve phase (default: plain answer prompt; implementation choice) |
| `ctx.solve_tokens` | number | optional | Token cap for the final solve LLM call (default: 500; implementation choice) |
| `ctx.task` | string | **required** | Original question to solve (paper §3.3 input Q_0) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `depth_used` | number | — | Number of contraction iterations actually executed. Ranges over [0, depth_budget]; equals depth_budget when the loop completes the full D iterations, < depth_budget when an early termination fires (parse failure / all-independent / consistency rejection). |
| `final_answer` | string | — | Direct answer to the final contracted question (paper §3.3 line 13) |
| `final_question` | string | — | Final contracted question that solve was applied to |
| `initial_depth_budget` | number | — | Depth D fixed on the first iteration from GetMaxPathLength(G_0), before max_depth cap (paper §3.3 line 6) |
