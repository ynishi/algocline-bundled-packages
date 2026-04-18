---
name: recipe_safe_panel
version: 0.1.0
category: recipe
result_shape: safe_paneled
description: "Verified safe majority-vote panel — Condorcet-sized, Anti-Jury gated, inverse-U monitored, confidence-calibrated. Composes condorcet + sc + inverse_u + calibrate with known failure mode awareness."
source: recipe_safe_panel/init.lua
generated: gen_docs (V0)
---

# recipe_safe_panel — Verified safe majority-vote panel

> Recipe package: composes condorcet, sc, inverse_u, and calibrate into a safety-gated panel vote. The recipe ensures that majority voting is only applied when the mathematical preconditions are met, and provides early warnings when adding more agents would degrade rather than improve accuracy.

## Contents

- [Result](#result)

## Result {#result}

Returns `safe_paneled` shape:

| key | type | optional | description |
|---|---|---|---|
| `abort_reason` | string | optional | Abort reason (nil when not aborted) |
| `aborted` | boolean | — | True if early-abort triggered |
| `answer` | string | optional | Consensus answer (nil on abort) |
| `anti_jury` | boolean | — | Condorcet anti-jury detection |
| `confidence` | number | — | Meta-confidence estimate |
| `expected_accuracy` | number | — | Condorcet expected majority accuracy |
| `is_safe` | boolean | — | Vote-prefix stability safe flag |
| `margin_gap` | number | — | (top - runner_up) / n |
| `n_distinct_answers` | number | — | Count of unique answers |
| `needs_investigation` | boolean | — | True if meta-confidence below threshold |
| `panel_size` | number | — | Actual panel size used |
| `plurality_fraction` | number | — | Top-answer vote fraction |
| `stages` | array of discriminated by "name" | — | Per-stage detail (discriminated by name) |
| `target_met` | boolean | — | Whether expected accuracy >= target |
| `total_llm_calls` | number | — |  |
| `unanimous` | boolean | — | All votes identical |
| `vote_counts` | map of string to number | — | { [normalized_answer] = count } tally |
