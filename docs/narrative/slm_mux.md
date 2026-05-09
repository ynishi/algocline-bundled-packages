---
name: slm_mux
version: 0.1.0
category: selection
result_shape: slm_muxed
description: "Complementarity-driven K-subset selection over a pool of small language models. Implements Wang et al. (arXiv:2510.05077, ICLR 2026 Poster) §3.1 Algorithm 1 (confidence-based inference selection) and §3.2 𝒪(S) = UnionAcc(S) − λ · Contradiction(S) with exhaustive search. Pure Computation pkg — no alc.llm calls; caller drives test-time inference. Fills selection-axis gap not covered by router_*/cascade (single-best routing) or ab_select/mbr_select (single-best selection): N→K subset complementarity over a pre-computed calibration tensor."
source: slm_mux/init.lua
generated: gen_docs (V0)
---

# slm_mux(SLMMux) — complementarity-driven K-subset selection over SLM pool

> Pure-computation package for orchestrating Small Language Models via complementarity-driven K-subset selection. Implements paper §3.1 Algorithm 1 (inference-time confidence selection) and §3.2 objective `𝒪(S) = UnionAcc(S) − λ · Contradiction(S)` with exhaustive K-subset search.

## Contents

- [Usage](#usage)
- [Theoretical foundations](#theoretical-foundations)
- [Injection points](#injection-points)
- [Caveats](#caveats)
- [References](#references)

## Usage {#usage}

```lua
local mux = require("slm_mux")

-- One per SLM in the pool:
local profiles = {
  { samples = { {"A","A","A"}, {"B","C","B"}, ... },
    correct = { "A", "B", ... } },
  { samples = { ... }, correct = { ... } },
  ...
}

local r = mux.run(profiles, 2)            -- best 2-subset by 𝒪(S)
local c = mux.confidence({"A","A","B"})   -- → { y_star="A", s=2/3 }
```

## Theoretical foundations {#theoretical-foundations}

Per-model confidence (Algorithm 1):

```math
f_i(y) = (1/k) · Σ_{j=1}^{k} 𝟙(y_i^(j) = y)
y_i*   = argmax_y f_i(y)
s_i    = f_i(y_i*)
```

Inference-time selection (Algorithm 1):

```math
S_max = max_{i ∈ S} s_i
I*    = { i ∈ S : s_i = S_max }
return y_{i*}*  where i* = (|I*|=1 ? unique : argmax_{i ∈ I*} a_i)
```

Subset objective (§3.2):

```math
UnionAcc(S)      = (1/|𝒟|) · Σ_x 𝟙{ ∃ m ∈ S : m(x) is correct }
Contradiction(S) = (1/|𝒟|) · Σ_x 𝟙{ ∃ m_1 ∈ S consistently wrong
                                      ∧ ∃ m_2 ∈ S correct on x }
𝒪(S)            = UnionAcc(S) − λ · Contradiction(S)
```

K-subset selection: `argmax_{S ⊆ pool, |S|=K} 𝒪(S)` via exhaustive
enumeration.

Inference-time confidence concentration (out-of-paper reference,
derived from a Hoeffding union bound on Bernoulli sample-mean
concentration of `s_i`):

```math
Pr( î = i* ) ≥ 1 − 2(K−1) · exp( −N · γ² / 2 )
```

where `N` is sample count per model, `K` is subset size, and
`γ = p_{i*} − max_{j ≠ i*} p_j > 0` is the true confidence gap.

## Injection points {#injection-points}

Paper-faithful defaults: `λ = 1.0` (§4.3), `search_method =
"exhaustive"` (§3.2), `consistency_threshold = 0.0`,
`s_tie_break = "validation_accuracy"`.

REQUIRED:

- `profiles` — array of N SLM profiles
  `{ samples, correct, validation_accuracy? }`. Caller pre-computes
  the calibration tensor (paper §4.3 uses 500 questions); pkg never
  calls `alc.llm`.
- `k` — subset size `1 ≤ k ≤ N` for `select_subset` / `run`.

OPTIONAL paper-faithful: `lambda`, `tie_break_yi`,
`subset_tie_break`, `s_tie_break` (paper does not numerically fix
the tie-break choices; defaults remain paper-faithful).

OPTIONAL non-paper-faithful (loss of paper guarantees):

- `search_method = "greedy_forward" | "greedy_backward"` — practical
  fallback when `C(N, K)` is prohibitive; loses global optimality.
- `consistency_threshold > 0.0` — sensitivity analysis only.
- `partial_coverage` — `error` (default, fail-fast, paper-faithful)
  vs `skip_missing` / `treat_as_wrong` (not paper-faithful research
  knobs). `skip_missing` normalises by `effective_M`, breaking
  exact cross-subset comparability.

## Caveats {#caveats}

Out of scope for v1: online inference orchestration (callers wire
Algorithm 1 via `sc` / `panel` / `smc_sample` / `particle_infer`),
calibration data resampling, and auto-tuning of `λ`.

## References {#references}

- Wang, ..., Wan, ..., Kang, ..., Chen, ..., Xie, ..., Krishna, ...,
  Reddi, ..., Du, ... (2025). "SLM-MUX: Orchestrating Small Language
  Models for Reasoning". ICLR 2026 Poster.
  https://arxiv.org/abs/2510.05077
