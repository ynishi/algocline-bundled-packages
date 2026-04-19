---
name: recipe_deep_panel
version: 0.1.0
category: recipe
result_shape: deep_paneled
description: "Deep-reasoning diverse panel — N × ab_mcts (Thompson Sampling tree search) fan-out via flow (resume-safe), followed by ensemble_div diversity diagnostic, condorcet expected-accuracy, and calibrate meta-confidence. The heavy-compute counterpart of recipe_safe_panel (which uses sc instead of ab_mcts)."
source: recipe_deep_panel/init.lua
generated: gen_docs (V0)
---

# recipe_deep_panel — Deep-reasoning diverse panel with resume

> Recipe package: composes ab_mcts × N + ensemble_div + condorcet + calibrate on top of flow. Fills the gap between recipe_safe_panel (cheap sc-based majority vote) and single-agent ab_mcts: when each individual opinion requires tree-search-quality reasoning AND the panel is large enough to need checkpoint-resume, this recipe is the right composition.

## Contents

- [Result](#result)

## Result {#result}

Returns `deep_paneled` shape:

| key | type | optional | description |
|---|---|---|---|
| `abort_reason` | string | optional | Abort reason (nil when not aborted) |
| `aborted` | boolean | — | True if early-abort triggered |
| `answer` | any | — | Plurality answer (nil on abort) |
| `anti_jury` | boolean | — | Condorcet anti-jury detection at Stage 1 |
| `branches` | table | — | { [bkey] = { approach, answer, best_score, tree_stats } } |
| `confidence` | number | — | Meta-confidence estimate |
| `decomp` | table | optional | ensemble_div.decompose output (nil if Stage 3b skipped) |
| `diversity` | table | optional | { n_distinct, distinctness, decomp_status } |
| `expected_accuracy` | number | — | Condorcet expected majority accuracy |
| `margin_gap` | number | — | (top - runner_up) / n |
| `n_branches_completed` | number | — | Branches actually finished |
| `n_distinct_answers` | number | — | Count of unique normalized answers |
| `needs_investigation` | boolean | — | True if meta-confidence below threshold |
| `panel_size` | number | — | Requested panel size |
| `plurality_fraction` | number | — | Top-answer vote fraction |
| `stages` | array of table | — | Per-stage detail (heterogeneous) |
| `target_met` | boolean | — | Whether expected accuracy >= ctx.target_accuracy |
| `total_llm_calls` | number | — |  |
| `unanimous` | boolean | — | All normalized votes identical |
| `vote_counts` | map of string to number | — | { [normalized_answer] = count } tally |
