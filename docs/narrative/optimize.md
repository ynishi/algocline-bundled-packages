---
name: optimize
version: 0.3.0
category: optimization
result_shape: "shape { arm_count: number, best_params: table, best_score: number, card_id?: string, history_key: string, rounds_used: number, status: string, stop_reason?: string, top_5: array of shape { avg_score: number, params: table, pulls: number }, total_evaluations: number }"
description: "Modular parameter optimization orchestrator. Composes pluggable search strategies (UCB1, OPRO, EA, greedy), evaluators (evalframe, custom, LLM judge), and stopping criteria (variance, patience, threshold). Persists history via alc.state."
source: optimize/init.lua
generated: gen_docs (V0)
---

# optimize(Optimize) — modular parameter optimization orchestrator

> Explores parameter configurations for a target strategy by composing pluggable search strategies, evaluators, and stopping criteria. Persists history in `alc.state` for incremental optimization across sessions.

## Contents

- [Usage](#usage)
- [Architecture](#architecture)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local optimize = require("optimize")
return optimize.run(ctx)
```

## Architecture {#architecture}

Automatic Prompt Optimization research identifies 4 core concerns:
candidate generation, evaluation, selection, and termination. The
package separates those concerns into composable submodules
(following promptolution's modular architecture). The orchestrator
is intentionally thin — it owns only the loop, state persistence,
and result aggregation; domain logic is delegated to pluggable
components.

- `optimize/init.lua` — orchestrator (this file): loop, state,
  results.
- `optimize/search.lua` — search strategies (`ucb` / `random` /
  `opro` / `ea` / `greedy`).
- `optimize/eval.lua` — evaluators (`evalframe` / `custom` /
  `llm_judge`).
- `optimize/stop.lua` — stopping criteria (`variance` / `patience` /
  `threshold` / `improvement`).

## References {#references}

- Khattab, O. et al. (2023). "DSPy: Compiling Declarative Language
  Model Calls into Self-Improving Pipelines".
  https://arxiv.org/abs/2310.03714
- Yang, C. et al. (2023). "Large Language Models as Optimizers"
  (OPRO). https://arxiv.org/abs/2309.03409
- Guo, Q. et al. (2024). "EvoPrompt: Connecting LLMs with
  Evolutionary Algorithms Yields Powerful Prompt Optimizers". ICLR
  2024. https://arxiv.org/abs/2309.08532
- Yuksekgonul, M. et al. (2024). "TextGrad: Automatic Differentiation
  via Text". Nature 2024. https://arxiv.org/abs/2406.07496
- Hebenstreit, K. et al. (2024). "promptolution: A Unified, Modular
  Framework for Prompt Optimization".
  https://arxiv.org/abs/2512.02840
- APO Survey (2025). "A Systematic Survey of Automatic Prompt
  Optimization Techniques". https://arxiv.org/abs/2502.16923

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

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `arm_count` | number | — | Number of distinct arms in history |
| `best_params` | table | — | Best-ranked parameter set |
| `best_score` | number | — | Average score of best_params |
| `card_id` | string | optional | Emitted Card id (only when auto_card=true) |
| `history_key` | string | — | alc.state key for the persisted history |
| `rounds_used` | number | — | Actual rounds executed this run |
| `status` | string | — | 'converged' (stopper fired) or 'budget_exhausted' |
| `stop_reason` | string | optional | Stopper's reason string; nil when budget_exhausted |
| `top_5` | array of shape { avg_score: number, params: table, pulls: number } | — | Top-5 ranked arms (may contain fewer than 5) |
| `total_evaluations` | number | — | Cumulative evaluations in history (including prior runs) |
