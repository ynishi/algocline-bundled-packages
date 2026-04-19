---
name: recipe_quick_vote
version: 0.1.0
category: recipe
result_shape: quick_voted
description: "Adaptive-stop majority vote. sc-style sampler looped under SPRT gate. Exits as soon as declared (α, β) error rates permit, or truncates with an explicit verdict for consumer escalation. Fills the Quick slot between recipe_safe_panel (fixed n) and recipe_deep_panel (heavy per-branch reasoning)."
source: recipe_quick_vote/init.lua
generated: gen_docs (V0)
---

# recipe_quick_vote — Adaptive-stop majority vote with SPRT gate

> Fills the Quick slot of the recipe family. Given a task that admits a single short answer, samples independent reasoning paths one at a time and exits as soon as SPRT declares the leading answer confirmed (H1 accepted) or rejected (H0 accepted) at the declared (α, β) error rates. Truncates at max_n if neither boundary is hit — that case is surfaced as `outcome = "truncated"` and `needs_investigation = true` so the consumer can route to recipe_safe_panel / recipe_deep_panel.

## Contents

- [Result](#result)

## Result {#result}

Returns `quick_voted` shape:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | — | Leader answer from sample 1 (cleaned, not normalized) |
| `leader_norm` | string | — | Normalized leader key used for agreement tests |
| `n_samples` | number | — | Total samples drawn (1 leader + k agreement observations) |
| `needs_investigation` | boolean | — | True unless outcome == 'confirmed' |
| `outcome` | one_of("confirmed", "rejected", "truncated") | — | Terminal state: confirmed=H1 accepted, rejected=H0 accepted, truncated=no verdict at max_n |
| `params` | shape { alpha: number, beta: number, max_n: number, min_n: number, p0: number, p1: number } | — | Echoed parameter values |
| `samples` | array of shape { answer: string, norm: string, reasoning: string } | — | Per-sample reasoning + extracted answer |
| `sprt` | shape { a_bound: number, b_bound: number, log_lr: number, n: number } | — | Final SPRT state snapshot |
| `total_llm_calls` | number | — | 2 × n_samples (reasoning + extract per sample) |
| `verdict` | one_of("accept_h1", "accept_h0", "continue") | — | Underlying SPRT verdict from the final decide() |
| `vote_counts` | map of string to number | — | { [norm] = count } tally across all samples |
