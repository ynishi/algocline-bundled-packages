---
name: recipe_deep_panel
version: 0.1.0
category: recipe
result_shape: deep_paneled
description: "Deep-reasoning diverse panel: N x ab_mcts fan-out + diversity + calibrate."
source: recipe_deep_panel/init.lua
generated: gen_docs (V0)
---

# recipe_deep_panel(RecipeDeepPanel) — deep-reasoning diverse panel with resume

> Recipe package that composes `ab_mcts × N` + `ensemble_div` + `condorcet` + `calibrate` on top of `flow`. Fills the gap between `recipe_safe_panel` (cheap `sc`-based majority vote) and single-agent `ab_mcts`: when each opinion requires tree-search-quality reasoning and the panel is large enough to need checkpoint-resume, this recipe is the right composition.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [Caveats](#caveats)
- [References](#references)
- [Result](#result)

## Usage {#usage}

```lua
local deep_panel = require("recipe_deep_panel")
return deep_panel.run(ctx)
```

## Algorithm {#algorithm}

1. `condorcet` — panel feasibility + Anti-Jury gate. If `p_estimate
   <= 0.5`, majority vote is provably harmful or useless; abort with
   zero LLM cost.
2. `flow` fan-out of `ab_mcts` — N independent tree searches with
   `flow.state_new` + per-branch `flow.state_get` checkpoints. A
   crash mid-panel resumes at the first incomplete branch. Each
   branch is a full `ab_mcts` run (`2*budget + 1` LLM calls)
   differentiated by a distinct approach-prompt; `flow.token_wrap` /
   `token_verify` tag each call so mis-routed responses across
   parallel branches are detected at the Frame boundary.
3. `ensemble_div` — panel diversity diagnostic. Stage 3a always runs
   answer-level distinctness on normalized answers (`n_distinct /
   n`). Stage 3b runs `ensemble_div.decompose` only when
   `ctx.ground_truth` is numeric and every branch answer parses as a
   number; otherwise skipped with an explicit reason (see
   `M.caveats`).
4. `condorcet.prob_majority` — plurality vote plus Condorcet
   expected accuracy under independence at the declared
   `p_estimate`.
5. `calibrate.assess` — single-call meta-confidence gate. Recipe
   raises `needs_investigation` when confidence falls below
   `ctx.confidence_threshold`.

## Caveats {#caveats}

See `M.caveats`. Key items: Anti-Jury abort, cost explosion with
`N × budget`, resume replay semantics, and numeric-only Stage 3b.

## References {#references}

- Inoue, Y. et al. (2025). "Wider or Deeper? Scaling LLM
  Inference-Time Compute with Adaptive Branching Tree Search".
  NeurIPS 2025 Spotlight. https://arxiv.org/abs/2503.04412
- Condorcet, M. (1785). "Essai sur l'application de l'analyse à la
  probabilité des décisions rendues à la pluralité des voix".
- Krogh, A., Vedelsby, J. (1995). "Neural Network Ensembles, Cross
  Validation, and Active Learning". NeurIPS 7, pp.231-238.
- Wang, X. et al. (2022). "Self-Consistency Improves Chain of
  Thought Reasoning in Language Models".
  https://arxiv.org/abs/2203.11171

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
