---
name: recipe_quick_vote
version: 0.1.0
category: recipe
result_shape: quick_voted
description: "Adaptive-stop majority vote. sc-style sampler looped under SPRT gate. Exits as soon as declared (α, β) error rates permit, or truncates with an explicit verdict for consumer escalation. Fills the Quick slot between recipe_safe_panel (fixed n) and recipe_deep_panel (heavy per-branch reasoning)."
source: recipe_quick_vote/init.lua
generated: gen_docs (V0)
---

# recipe_quick_vote(RecipeQuickVote) — adaptive-stop majority vote with SPRT gate

> Fills the Quick slot of the recipe family. For a task admitting a single short answer, samples independent reasoning paths one at a time and exits as soon as SPRT declares the leading answer confirmed (H1 accepted) or rejected (H0 accepted) at the declared `(α, β)` error rates. Truncates at `max_n` if neither boundary is hit; that case surfaces as `outcome = "truncated"` and `needs_investigation = true` so the consumer can route to `recipe_safe_panel` / `recipe_deep_panel`.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [Theoretical foundations](#theoretical-foundations)
- [Caveats](#caveats)
- [Comparison with related packages](#comparison-with-related-packages)
- [Result](#result)

## Usage {#usage}

```lua
local recipe = require("recipe_quick_vote")
return recipe.run({
    task = "What is 17 × 23?",
    p0 = 0.5, p1 = 0.80,
    alpha = 0.05, beta = 0.10,
    max_n = 8, min_n = 3,
})
```

## Algorithm {#algorithm}

1. Sample 1 — `sc`-style reasoning + extraction; the normalized
   answer is committed as the "leader" (one LLM call for reasoning,
   one for extraction).
2. For samples `2..max_n`, generate reasoning with a diversity hint,
   extract, set `outcome = (normalized_answer == leader_norm)`, call
   `sprt.observe`. Once `i >= min_n`, inspect `sprt.decide`:
   `accept_h1 → "confirmed"`, `accept_h0 → "rejected"`, otherwise
   keep sampling.
3. If the loop reaches `max_n` without a verdict, `outcome =
   "truncated"` and `needs_investigation = true`.

## Theoretical foundations {#theoretical-foundations}

SPRT tests `H0: p_agree ≤ p0` against `H1: p_agree ≥ p1`, where
`p_agree` is the probability that a newly drawn independent sample
agrees with the first sample's answer. Under a well-posed task with
a high-confidence answer, `p_agree ≈ per-sample accuracy`, so the
recipe doubles as a per-task p-estimate gate that can feed
`condorcet` / `recipe_safe_panel` downstream.

## Caveats {#caveats}

POC simplification: a single committed leader from sample 1; a
runner-up that overtakes the leader is not tracked separately and
surfaces as `accept_h0` (leader rejected) so the consumer can
re-enter with the new plurality. Full multi-arm dynamic-leader SPRT
is deferred to v0.2.

## Comparison with related packages {#comparison-with-related-packages}

- `recipe_safe_panel` — fixed `n ≈ 5-7`, cheap heuristic majority;
  ~8 LLM calls for `math_basic`, no early stop.
- `recipe_deep_panel` — per-branch `ab_mcts` tree search; ~52 LLM
  calls at `N=3, budget=8`.
- `recipe_quick_vote` — adaptive stop via SPRT. `E[N]` is
  Wald-Wolfowitz minimal at the declared `(α, β)`. On easy tasks
  exits at 3-4 calls; on hard tasks truncates with an explicit
  statistical verdict the consumer can escalate.

## Result {#result}

Returns `quick_voted` shape:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | — | Leader answer from sample 1 (cleaned, not normalized) |
| `leader_norm` | string | — | Normalized leader key used for agreement tests |
| `n_samples` | number | — | Total samples drawn (1 leader + k agreement observations) |
| `needs_investigation` | boolean | — | True only when outcome == 'truncated' (evidence inconclusive at declared α/β). 'rejected' is a conclusive verdict and does NOT set this flag. |
| `outcome` | one_of("confirmed", "rejected", "truncated") | — | Terminal state: confirmed=H1 accepted, rejected=H0 accepted, truncated=no verdict at max_n |
| `params` | shape { alpha: number, beta: number, max_n: number, min_n: number, p0: number, p1: number } | — | Echoed parameter values |
| `samples` | array of shape { answer: string, norm: string, reasoning: string } | — | Per-sample reasoning + extracted answer |
| `sprt` | shape { a_bound: number, b_bound: number, log_lr: number, n: number } | — | Final SPRT state snapshot |
| `total_llm_calls` | number | — | 2 × n_samples (reasoning + extract per sample) |
| `verdict` | one_of("accept_h1", "accept_h0", "continue") | — | Underlying SPRT verdict from the final decide() |
| `vote_counts` | map of string to number | — | { [norm] = count } tally across all samples |
