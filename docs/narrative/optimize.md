---
name: optimize
version: 0.3.0
category: optimization
result_shape: "shape { arm_count: number, best_params: table, best_score: number, card_id?: string, history_key: string, rounds_used: number, status: string, stop_reason?: string, top_5: array of shape { avg_score: number, params: table, pulls: number }, total_evaluations: number }"
description: "Modular parameter optimization orchestrator. Composes pluggable search strategies (UCB1, OPRO, EA, greedy), evaluators (evalframe, custom, LLM judge), and stopping criteria (variance, patience, threshold). Persists history via alc.state."
source: optimize/init.lua
generated: gen_docs (V0)
---

# optimize — Modular parameter optimization orchestrator

> Explores parameter configurations for a target strategy by composing pluggable search strategies, evaluators, and stopping criteria. Persists history in alc.state for incremental optimization across sessions.

## Contents

- [Parameters](#parameters)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.auto_card` | boolean | optional | Emit a Card on completion (default: false) |
| `ctx.card_pkg` | string | optional | Card pkg.name override (default: 'optimize_{target}') |
| `ctx.defaults` | table | optional | Base parameter defaults merged with arm params |
| `ctx.eval_fn` | any | optional | Custom evaluation function (only for evaluator='custom') |
| `ctx.evaluator` | any | optional | Evaluator — name string or config table (default: 'evalframe') |
| `ctx.name` | string | optional | Run name used as state key suffix (default: ctx.target) |
| `ctx.rounds` | number | optional | Max optimization rounds (default: 20) |
| `ctx.scenario` | any | **required** | Eval scenario — inline table or scenario name string |
| `ctx.scenario_name` | string | optional | Explicit scenario name for the emitted Card |
| `ctx.search` | any | optional | Search strategy — name string or config table (default: 'ucb') |
| `ctx.space` | table | **required** | Parameter search space (map of param_name → def {type, min, max, step, values}) |
| `ctx.stop` | any | optional | Stopping criterion — name string or config table (default: 'variance') |
| `ctx.stop_config` | table | optional | Extra config for stopping criterion |
| `ctx.strategy_opts` | table | optional | Extra opts passed through to the target strategy |
| `ctx.target` | string | **required** | Strategy package name to optimize (e.g., 'biz_kernel') |
