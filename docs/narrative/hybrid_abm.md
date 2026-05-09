---
name: hybrid_abm
version: 0.1.0
category: simulation
description: "LLM-as-Parameterizer ABM — LLM extracts sim parameters, Pure Lua ABM runs Monte Carlo simulation + sensitivity sweep. Based on FCLAgent (arXiv:2510.12189) hybrid architecture."
source: hybrid_abm/init.lua
generated: gen_docs (V0)
---

# hybrid_abm(HybridABM) — LLM-as-parameterizer agent-based model strategy

> Hybrid architecture: an LLM extracts simulation parameters (Phase A), a pure-Lua ABM runs Monte Carlo (Phases B and C), and a sensitivity sweep (Phase D) tests robustness. The LLM is excellent at extracting domain parameters from natural-language descriptions but terrible at running simulations; ABM is the inverse. Combining them gives better results than either alone.

## Contents

- [Usage](#usage)
- [References](#references)

## Usage {#usage}

```lua
local hybrid = require("hybrid_abm")
return hybrid.run(ctx)
```

## References {#references}

- FCLAgent (2025). "judgment = LLM, execution = rules" decoupling.
  https://arxiv.org/abs/2510.12189
- JASSS position paper (2025). Modular hybrid recommendation.
  https://arxiv.org/abs/2507.19364
ctx.sweep_runs?: number (default 50, for quick eval per perturbation)

Shape policy (why hybrid_abm is NOT S.instrument-decorated):
  Phase 6-a-fix-3: sibling ABM pkgs (boids_abm, epidemic_abm, evogame_abm,
  opinion_abm, schelling_abm, sugarscape_abm) all declare their result
  shape via `abm.mc.shape({numbers = ..., booleans = ...})` because their
  `extract` key set is known at load time.

  hybrid_abm is different: `extract`, `sim_fn`, `classify_fn`,
  `param_schema`, `sweep_params` are ALL supplied by the caller via ctx
  at run time. The set of suffix-expanded keys in ctx.result.simulation
  (K_median / K_rate / K_ci / ...) therefore depends on the caller's
  extract list and cannot be pinned at module load. Declaring a closed
  T.shape({...}) here would either reject valid callers or degrade to
  T.table opaque, and T.table opaque ≡ T.any (no discoverability value).

  Resolution: hybrid_abm stays un-instrumented. Callers that wrap
  hybrid_abm (e.g. a domain-specific pkg that fixes its own extract set)
  should call `abm.mc.shape(...)` with their known keys in their own
  M.spec, then `S.instrument` at their layer. See boids_abm/init.lua for
  the canonical pattern.
