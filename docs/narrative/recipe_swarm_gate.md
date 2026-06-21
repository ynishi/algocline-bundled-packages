---
name: recipe_swarm_gate
version: 0.1.0
category: recipe
result_shape: "shape { branches?: map of string to shape { answer: string, approach: string, best_score: number, tree_stats: any }, picked?: string, stage?: string, status: string }"
description: "Parallel ab_mcts swarm + orch_gatephase consensus + commit gates, composed over the flow Frame. Fills the Swarm slot of the recipe family — a task admitting multiple independent reasoning angles is fanned out to N ab_mcts branches with caller-supplied approach hints, then the branches' best answers are collapsed through structured Phase gates with ReqToken-bounded verification at every pkg boundary."
source: recipe_swarm_gate/init.lua
generated: gen_docs (V0)
---

# recipe_swarm_gate(RecipeSwarmGate) — parallel ab_mcts swarm + gate aggregation

> Fills the "parallel + fan-in + verify" slot of the recipe family: given a task that admits multiple independent reasoning angles, spawn N `ab_mcts.run` branches with distinct approach hints (the "swarm"), then collapse them through `orch_gatephase` consensus + commit gates. The recipe runs on top of the `flow` Frame so mid-flight checkpoint is preserved across resume; each pkg call is ReqToken-wrapped at the boundary so a stale verdict from a prior session cannot leak into a fresh branch slot.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [Design rationale](#design-rationale)
- [Caveats](#caveats)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local recipe = require("recipe_swarm_gate")
return recipe.run({
    task        = "Design a rate limiter for a chat API.",
    task_id     = "rate_limiter_2026_06",
    approaches  = { "top-down", "bottom-up", "analogical" },
    budget      = 8,
    max_depth   = 3,
    resume      = false,
})
```

## Algorithm {#algorithm}

1. **root_gate** — `orch_gatephase` validates the task and confirms
   the approach list is plausible. Gate keyword `^OK$`.
2. **fan-out** — for each approach, `ab_mcts.run({task = task ..
   " / approach=" .. approach, budget, max_depth})` runs
   independently; results land under `state.data.branches[bkey]`.
   Each call is `flow.token_wrap`-ed at the boundary.
3. **consensus_gate** — `orch_gatephase` compares the branches'
   `answer / best_score` triples and emits `pick=branch_N`.
4. **commit_gate** — final `orch_gatephase` review against the
   picked branch; emits `COMMIT` or fails.

## Design rationale {#design-rationale}

This is a *recipe* (composition over algorithms), not a faithful
implementation of any single paper — `ab_mcts` and `orch_gatephase`
are the algorithm-level libs. The composition draws on:

  * **ab_mcts** — implements AB-MCTS (Sakana AI 2025,
    arXiv:2503.04412 §3 "AB-MCTS" / Algorithm 1) which explores the
    (width × depth) reasoning tree with Thompson sampling; see the
    pkg's own docstring for the algorithm citation. The recipe
    fan-out treats each branch as one ab_mcts run with a distinct
    approach hint, on the empirical observation that ensembling
    diverse seeds lifts accuracy.
  * **orch_gatephase** — implements the Phase-gate discipline
    (structured verification with retry-on-fail), used here for the
    root / consensus / commit reviews so the aggregator's verdict is
    gate-bounded rather than a free-form pick.

The recipe assumes branch outputs are exchangeable conditional on
the approach hint; under that assumption the consensus pick targets
the highest `best_score` over the swarm. The "exchangeability +
consensus pick" framing is a working assumption of this recipe, not
a theorem derived from either paper.

## Caveats {#caveats}

* Branch diversity depends entirely on the approach strings supplied
  by the caller. With near-duplicate approach strings the swarm
  collapses to a single mode and the consensus_gate degenerates to a
  tie-break. The recipe does not inject a diversity penalty; if you
  need that, route the approach list through `ensemble_div` first.
* `flow.token_verify` is currently a pass-through for pkg results
  that do not echo `_flow_token` / `_flow_slot`. ab_mcts and
  orch_gatephase do not echo as of flow v0.7.0, so the verify call
  guards only against future-state echoes. The boundary-wrap is kept
  so that opt-in echo support lights up automatically.
* Total LLM calls scale as roughly `n_approaches * budget + 2 *
  gate_calls`. For budget=8, n_approaches=3 expect ~32-40 calls in
  typical runs; size the deployment budget accordingly.

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.approaches` | array of string | optional | Caller-supplied approach hints (default: {"top-down", "bottom-up", "analogical"}) |
| `ctx.budget` | number | optional | ab_mcts expansion iterations per branch (default: 8) |
| `ctx.max_depth` | number | optional | ab_mcts tree depth per branch (default: 3) |
| `ctx.resume` | boolean | optional | Resume from prior flow state if present (default: false) |
| `ctx.task` | string | **required** | Problem statement |
| `ctx.task_id` | string | **required** | Stable identity used as the flow state key suffix |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `branches` | map of string to shape { answer: string, approach: string, best_score: number, tree_stats: any } | optional | Per-branch ab_mcts result, keyed by branch_N |
| `picked` | string | optional | Consensus gate final_output (the "pick=branch_N" verdict text) |
| `stage` | string | optional | On failure, the gate that rejected ("root_gate" / "consensus_gate" / "commit_gate") |
| `status` | string | — | "done" / "failed" |
