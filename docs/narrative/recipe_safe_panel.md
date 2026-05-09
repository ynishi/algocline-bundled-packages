---
name: recipe_safe_panel
version: 0.1.0
category: recipe
result_shape: safe_paneled
description: "Verified safe majority-vote panel — Condorcet-sized, Anti-Jury gated, inverse-U monitored, confidence-calibrated. Composes condorcet + sc + inverse_u + calibrate with known failure mode awareness."
source: recipe_safe_panel/init.lua
generated: gen_docs (V0)
---

# recipe_safe_panel(RecipeSafePanel) — verified safe majority-vote panel

> Recipe package that composes `condorcet`, `sc`, `inverse_u`, and `calibrate` into a safety-gated panel vote. Ensures majority voting is only applied when mathematical preconditions are met and gives early warnings when adding more agents would degrade accuracy.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [Theoretical foundations](#theoretical-foundations)
- [Caveats](#caveats)
- [References](#references)
- [Result](#result)

## Usage {#usage}

```lua
local safe_panel = require("recipe_safe_panel")
return safe_panel.run(ctx)
```

## Algorithm {#algorithm}

1. `condorcet` — panel-size design. `is_anti_jury(p)` gates entry:
   when `p < 0.5`, majority vote provably degrades with more agents.
   `optimal_n(p, target)` computes the minimum panel size to reach
   the target accuracy.
2. `sc` — `sc.run({ task, n })` samples N independent reasoning
   paths with diversity hints to maximize independence; the majority
   answer is extracted via vote counting.
3. `inverse_u` — vote-prefix stability check. Builds a
   progressive-majority series from the first 3, 5, 7, ... votes of
   the single `sc` run and feeds it to `inverse_u.detect` as a
   lightweight stability proxy. This is not a true inverse-U test
   (Chen 2024 concerns accuracy across independent panels of
   increasing size); a prefix of one run tends to approach the
   majority fraction monotonically and usually reports "safe". A
   true inverse-U test requires repeating `sc.run` at multiple N.
4. `calibrate` — meta-confidence gate. Synthesizes vote margin,
   Condorcet expected accuracy, and `inverse_u` safety into a single
   confidence assessment; low confidence raises
   `needs_investigation`.

## Theoretical foundations {#theoretical-foundations}

- Condorcet Jury Theorem: `P(Maj_n) → 1` as `n → ∞` when `p > 0.5`;
  Anti-Jury: `P(Maj_n) → 0` as `n → ∞` when `p < 0.5`.
- Chen et al. NeurIPS 2024 Theorem 2: vote accuracy is inverse-U
  shaped in N when `p1 + p2 > 1` and `α < 1 - 1/t`.

## Caveats {#caveats}

See `M.caveats`. Key: Anti-Jury abort, inverse-U detection,
independence violation from same-model sampling.

## References {#references}

- Condorcet, M. (1785). "Essai sur l'application de l'analyse...".
- Chen, L. et al. (2024). "Are More LM Calls All You Need? Scaling
  Laws in Multi-Agent Systems". NeurIPS 2024.
- Wang, X. et al. (2022). "Self-Consistency Improves Chain of
  Thought Reasoning in Language Models".
  https://arxiv.org/abs/2203.11171

ctx.task (required): The problem to solve
ctx.p_estimate (required): Estimated per-agent accuracy in (0, 1].
    REQUIRED with no default — silent fallback to 0.7 would bypass
    the Anti-Jury gate on tasks where the real p < 0.5. Estimate via
    a pilot (sc.run at n=1 over a labeled sample, then
    condorcet.estimate_p) or pass an explicit value based on task
    difficulty.
ctx.target_accuracy: Target majority-vote accuracy (default: 0.95)
ctx.max_n: Maximum panel size (default: 15)
ctx.confidence_threshold: Calibrate gate threshold (default: 0.7)
ctx.scaling_check: Run inverse_u analysis (default: true)
ctx.gen_tokens: Max tokens per LLM call (default: 400)

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
