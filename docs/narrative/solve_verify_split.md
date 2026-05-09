---
name: solve_verify_split
version: 0.1.0
category: orchestration
description: "Compute-optimal split between solution generation (SC) and generative verification (GenRM) under a fixed inference budget. Implements Singhi et al. (arXiv:2504.01005, COLM 2025) §3.1 cost model C(S,V) = S·(1+λV) and §5.2 power-law allocator S_opt ∝ C^a, V_opt ∝ C^b as five direct-args entries: cost, score_split, optimal_split, sc_pure, compare_paths. Pure Computation — no alc.llm calls; caller drives test-time inference with sc / step_verify / cove. Fills gap not covered by compute_alloc (paradigm choice) or gumbel_search/ab_mcts (search depth-vs-width): intra-paradigm S↔V split."
source: solve_verify_split/init.lua
generated: gen_docs (V0)
---

# solve_verify_split(SolveVerifySplit) — compute-optimal SC vs GenRM split

> Pure-computation package implementing the compute-optimal split between solution generation (Self-Consistency) and generative verification (GenRM) under a fixed inference compute budget. Implements paper §3.1 cost model and §3.2 / §5.2 power-law inference scaling laws as Pure Computation primitives (no LLM calls).

## Contents

- [Usage](#usage)
- [Theoretical foundations](#theoretical-foundations)
- [Algorithm](#algorithm)
- [Injection points](#injection-points)
- [Caveats](#caveats)
- [Comparison with related packages](#comparison-with-related-packages)
- [References](#references)

## Usage {#usage}

```lua
local svs = require("solve_verify_split")

-- §3.1 cost in isolation
svs.cost(4, 3, 1.0)            -- = 16
svs.cost(4, 1, 2.0)            -- = 12 (GenRM-FT λ=2)

-- Optimal allocation (caller fits α_S, α_V from grid)
local r = svs.optimal_split(100, {
    lambda = 2.0,
    exponent_solve = 0.57, exponent_verify = 0.39,
    prefactor_solve = 1.0, prefactor_verify = 1.0,
})
```

## Theoretical foundations {#theoretical-foundations}

```math
C(S, V) = S · (1 + λ · V)            -- paper §3.1
S_opt(C) = α_S · C^a                  -- paper §5.2
V_opt(C) = α_V · C^b
```

where `λ = T_V / T_S`. Paper-default exponents (§5.2 Llama-3.1-8B +
GenRM-FT + MATH): `a = 0.57, b = 0.39`. Appendix J alternates
transferred only: Qwen-2.5-7B + MATH (`0.75, 0.32`),
Llama-3.3-70B + MATH (`0.69, 0.43`). `α_S, α_V` have no numeric
value in the paper; caller MUST fit them from a `(S, V)` grid via
§3.2 Step 5 log-linear regression.

## Algorithm {#algorithm}

The pkg's allocator (paper §3.2 fits the parameters but has no
pseudocode):

1. `S_raw = α_S · B^a`, `V_raw = α_V · B^b`.
2. `S_int = round(S_raw)`, `V_int = round(V_raw)`.
3. `C_actual = S_int · (1 + λ · V_int)`.
4. If `C_actual > B`, rescale `(S_int, V_int)` within `B`.
5. If `V_int == 0`, take the pure SC path: `S = round(B), V = 0`.

Domain: paper §3.1 implies `S ≥ 1` and `V ≥ 0`. The pure `cost`
entry accepts `S ≥ 0` / `V ≥ 0`; `optimal_split` always returns
`S_opt ≥ 1`.

## Injection points {#injection-points}

Paper-faithful defaults: `lambda = 1.0` (§3.1 GenRM-Base equal-token),
`exponent_solve = 0.57`, `exponent_verify = 0.39`,
`integer_method = "round"`, `rescale_method = "scale_proportional"`,
`sc_fallback_when_v_zero = true`.

REQUIRED:

- `B` — budget (§3.1 C unit, > 0).
- `params.lambda` — `λ = T_V / T_S` (§3.1).
- `params.exponent_solve` — `a` in `S_opt ∝ C^a` (§5.2).
- `params.exponent_verify` — `b` in `V_opt ∝ C^b` (§5.2).
- `params.prefactor_solve` — `α_S` (caller-fit, §3.2 Step 5).
- `params.prefactor_verify` — `α_V` (caller-fit, §3.2 Step 5).

OPTIONAL paper-faithful: `opts.integer_method` (`round` / `floor` /
`ceil`), `opts.rescale_method` (`scale_proportional` /
`prefer_solve` / `prefer_verify`), `opts.v_cap` / `opts.s_cap`,
`opts.sc_fallback_when_v_zero`. Paper §3.2 does not fix these.

OPTIONAL non-paper-faithful: `opts.cost_model = "independent"`
(uses `C = S·c_s + V_total·c_v`; paper §3.1 has per-solution V
structure).

## Caveats {#caveats}

Cross-over observations (paper §5.1, observations not constants):

- Llama-3.1-8B + GenRM-FT + MATH: GenRM matches SC at 8× compute,
  +3.8% accuracy at 128×.
- Qwen-2.5-7B + MATH: 64× to match, +5.4% at 512×.
- Llama-3.3-70B + GenRM-Base + MATH: 4× to match, +1.7% at 64×.
- QwQ-32B (thinking) + MATH: 4× to match, +2.5% at 16×.

The cross-over is verifier-quality and model-dependent (Appendix E:
GenRM-FT vs Base differs by 16×); the pkg does not hardcode a
multiplier.

Out of scope for v1: `fit_exponents` log-linear regression (caller
fits in v1), cross-over multiplier auto-estimation, multi-question
budget partition, and the `independent` cost model (declared but
not implemented).

## Comparison with related packages {#comparison-with-related-packages}

Category: orchestration (allocator alongside `compute_alloc`).

## References {#references}

- Singhi, ..., Bansal, ..., Hosseini, ..., Grover, ..., Chang, ...,
  Rohrbach, ..., Rohrbach, ... (2025). "When To Solve, When To
  Verify: Compute-Optimal Problem Solving and Generative
  Verification for LLM Reasoning". COLM 2025.
  https://arxiv.org/abs/2504.01005
