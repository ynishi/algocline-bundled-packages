---
name: hegelian
version: 0.1.0
category: reasoning
result_shape: "shape { N: number, answer: string, final_synthesis: string, iterations: array of shape { antithesis: string, iteration: number, synthesis: string, tau_i: number }, thesis_0: string }"
description: "Hegelian dialectical self-reflection — thesis/antithesis/synthesis with temperature annealing (Abdali 2025)"
source: hegelian/init.lua
generated: gen_docs (V0)
---

# hegelian — Self-reflecting LLMs via Hegelian dialectical self-reflection

## Contents

- [Primary citation](#primary-citation)
- [Algorithm (Abdali 2025 §3, Algorithm 1)](#algorithm-abdali-2025-3-algorithm-1)
  - [Stage name mapping vs paper-literal terms](#stage-name-mapping-vs-paper-literal-terms)
- [Defaults (Abdali 2025 Appendix A, Table 2: "Experimental hyper-parameters")](#defaults-abdali-2025-appendix-a-table-2-experimental-hyper-parameters)
- [Entry contract](#entry-contract)
- [EXTENSION POINTS](#extension-points)
- [Comparison with related packages](#comparison-with-related-packages)
- [History](#history)
- [Parameters](#parameters)
- [Result](#result)

## Primary citation {#primary-citation}

Abdali, S., Yang, J., Sundararajan, H., Rangarajan Sridhar, V. K., &
Liden, L. (Microsoft Research). "Self-reflecting Large Language Models:
A Hegelian Dialectical Approach". arXiv:2501.14917 (v3, 2025-02).
https://arxiv.org/abs/2501.14917

## Algorithm (Abdali 2025 §3, Algorithm 1) {#algorithm-abdali-2025-3-algorithm-1}

```
  T_0  ← bootstrap initial thesis (single LLM call at temperature τ_0)
  for i = 0, 1, ..., N-1:
      A_i  ← M(T_i, τ_a, p_a)                  -- antithesis,  Alg.1 L6
      τ(i) = τ_0 · exp(-θ · i)                  -- decay,       §3.2 (annealing)
      S_i  ← M(T_i, A_i, τ(i), p_s)             -- synthesis,   Alg.1 L8
      T_{i+1} ← S_i                             -- update,      Alg.1 L16
  return S_{N-1}                                -- final synthesis
```

Three LLM-mediated stages per iteration:

  Thesis      T_0          single bootstrap call before loop, temperature τ_0
  Antithesis  A_i          per-iteration, temperature τ_a (fixed)
  Synthesis   S_i          per-iteration, temperature τ(i) (annealing)

### Stage name mapping vs paper-literal terms {#stage-name-mapping-vs-paper-literal-terms}

The pkg uses classical Hegelian terms "Thesis / Antithesis / Synthesis"
as a stable English mapping. The paper itself uses different literal
labels in two places:

  pkg term       Abdali §3 (main text)    Abdali Algorithm 1 step
  -----------    ----------------------   ------------------------
  Thesis      ↔  "Understanding"          (bootstrap, before loop)
  Antithesis  ↔  "Sublation"              "Generate Opposition"
  Synthesis   ↔  "Speculation"            "Cancel & Unify"

Symbols (T_i / A_i / S_i / τ_0 / τ_a / θ / N) match the paper. The
choice of "Thesis/Antithesis/Synthesis" as the pkg-facing names is a
(X) translation decision — the underlying algorithm is paper-literal.
The paper also denotes antithesis temperature as τ_A (opposition
temperature); the pkg uses lowercase τ_a / `tau_a` for Lua identifier
hygiene.

**No "rebuttal" stage exists in the paper** (verified against Abdali §3 /
Algorithm 1 / Appendix A Table 2, 2026-05-15 WebFetch).

## Defaults (Abdali 2025 Appendix A, Table 2: "Experimental hyper-parameters") {#defaults-abdali-2025-appendix-a-table-2-experimental-hyper-parameters}

| Symbol | Value | Label | Source                                                |
|--------|-------|-------|-------------------------------------------------------|
| τ_0    | 0.7   | (L)   | Table 2 "Initial temperature"                         |
| τ_a    | 0.5   | (L)   | Table 2 "Opposition temperature" (paper symbol τ_A)   |
| θ      | 0.3   | (X)   | within paper-stated (L) range [0.1, 0.5] from Table 2 |
| N      | 5     | (L)   | Table 2 "Max iterations" (idea generation value;      |
|        |       |       | paper also reports N=3 for math reasoning)            |

θ default 0.3 is the midpoint of the paper-stated range [0.1, 0.5]
(Table 2). 0.3 is NOT itself a literal Table 2 value — only the range is.
Caller is expected to tune θ for their specific model and task. The pkg
enforces θ ∈ [0.1, 0.5] (the paper range) at runtime; values outside
the range are rejected.

## Entry contract {#entry-contract}

See `M.spec` below for the formal machine-readable contract:

- `temperature_at`         — pure math, direct-args. returns τ(i) = τ_0 · exp(-θ · i)
- `build_thesis_prompt`    — pure string, direct-args. returns { prompt, system }
- `build_antithesis_prompt`— pure string, direct-args. returns { prompt, system }
- `build_synthesis_prompt` — pure string, direct-args. returns { prompt, system }
- `run`                    — Strategy, ctx-threading. orchestrates N iterations via `alc.llm`

All four sub-entries are LLM-independent and unit-testable without `alc` mocks.
`run` is the only LLM-mediated entry.

## EXTENSION POINTS {#extension-points}

```
┌──────────────────────────────────────────────────────────────────────┐
│ REQUIRED                                                             │
│   ctx.task                  (string)         task to apply dialectic │
├──────────────────────────────────────────────────────────────────────┤
│ (L)-override OPTION                                                  │
│   ctx.tau_0                 (number)         override τ_0 default    │
│   ctx.tau_a                 (number)         override τ_a default    │
│   ctx.N                     (number)         override iteration count│
├──────────────────────────────────────────────────────────────────────┤
│ (X) caller-tunable within paper range                                │
│   ctx.theta                 (number ∈ [0.1, 0.5])  decay constant    │
├──────────────────────────────────────────────────────────────────────┤
│ (X) infrastructure (paper does not specify)                          │
│   ctx.gen_tokens            (number)         max tokens per LLM call │
│   ctx.thesis_prompt         (string template) override thesis prompt │
│   ctx.antithesis_prompt     (string template) override antithesis    │
│   ctx.synthesis_prompt      (string template) override synthesis     │
│   ctx.system_thesis         (string)          system prompt thesis   │
│   ctx.system_antithesis     (string)          system prompt anti     │
│   ctx.system_synthesis      (string)          system prompt synth    │
├──────────────────────────────────────────────────────────────────────┤
│ Stability tier:                                                      │
│   stable     : tau_0 / tau_a / theta / N / gen_tokens                │
│   v2-opt-in  : *_prompt / system_* (template override; format may    │
│                evolve in future versions)                            │
└──────────────────────────────────────────────────────────────────────┘
```

Note: overriding any (L) default invalidates the paper's effect guarantee.
The pkg accepts the override and proceeds, but the docstring no longer
claims paper-explicit behaviour for the run.

## Comparison with related packages {#comparison-with-related-packages}

vs `dmad` (Du 2023 Multi-Agent Debate): dmad implements 3 agents debating
in parallel over multiple rounds with shared answer history; hegelian
implements a single-thread thesis/antithesis/synthesis dialectic with
temperature annealing. The two methodologies are from different papers
and are NOT variants of the same algorithm.

vs `panel` (sequential multi-role discussion): panel uses heterogeneous
caller-supplied roles per turn. hegelian's roles (thesis vs antithesis)
are paper-defined and structurally asymmetric.

vs `negation` (destruction conditions): negation explicitly tries to break
a candidate via failure-condition enumeration. hegelian constructs a
genuine counter-position and forces integration.

## History {#history}

hegelian/ was extracted from dmad/ v0.1.0 (commit 54faaa5, 2026-03-15)
in 2026-05-15. The Hegelian dialectic implementation had been mixed
into dmad/ alongside the Du 2023 citation despite Du's paper not
describing a dialectic. This pkg restores the Hegelian methodology with
the correct paper citation (Abdali 2025) and removes the non-paper
"rebuttal" stage that had been inserted in dmad/ v0.1.0.

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.N` | number | optional | Max iterations (default: 5, (L) Abdali Table 2) |
| `ctx.antithesis_prompt` | string | optional | Override antithesis prompt template (X) |
| `ctx.gen_tokens` | number | optional | Max tokens per LLM call (default: 600, (X) infrastructure) |
| `ctx.synthesis_prompt` | string | optional | Override synthesis prompt template (X) |
| `ctx.system_antithesis` | string | optional | Override antithesis system prompt (X) |
| `ctx.system_synthesis` | string | optional | Override synthesis system prompt (X) |
| `ctx.system_thesis` | string | optional | Override thesis system prompt (X) |
| `ctx.task` | string | **required** | Task or question (required) |
| `ctx.tau_0` | number | optional | Initial temperature (default: 0.7, (L) Abdali Table 2) |
| `ctx.tau_a` | number | optional | Antithesis/opposition temperature (default: 0.5, (L) Abdali Table 2) |
| `ctx.thesis_prompt` | string | optional | Override thesis prompt template (X) |
| `ctx.theta` | number | optional | Decay constant θ ∈ [0.1, 0.5] (default: 0.3, (X) within paper range) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `N` | number | — | Number of iterations actually executed |
| `answer` | string | — | Final synthesis S_{N-1}; alias of result.final_synthesis |
| `final_synthesis` | string | — | S_{N-1} — final integrated position |
| `iterations` | array of shape { antithesis: string, iteration: number, synthesis: string, tau_i: number } | — | Per-iteration log: { i, A_i, τ(i), S_i } for i = 0..N-1 |
| `thesis_0` | string | — | Initial thesis T_0 from bootstrap LLM call |
