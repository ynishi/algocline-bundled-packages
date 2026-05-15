---
name: reconcile
version: 0.1.0
category: aggregation
result_shape: "shape { answer: string, consensus: boolean, history: array of array of shape { agent: number, answer: string, confidence: number, explanation: string, normalized: string, raw_text?: string, round: number, weight: number }, n_agents: number, rounds_used: number, tally: array of shape { answer: string, count: number, weight: number }, total_llm_calls: number }"
description: "ReConcile (Chen 2023) — round-table consensus with §B.5 confidence-weighted voting and early-stop"
source: reconcile/init.lua
generated: gen_docs (V0)
---

# reconcile — ReConcile (Chen 2023) — round-table consensus with

> confidence-weighted voting

## Contents

- [Primary citation](#primary-citation)
- [Algorithm (Chen 2023 §3 / Algorithm 1)](#algorithm-chen-2023-3-algorithm-1)
- [Defaults (Chen 2023 §3, §4 footnote)](#defaults-chen-2023-3-4-footnote)
- [Entry contract](#entry-contract)
- [EXTENSION POINTS](#extension-points)
- [Comparison with related packages](#comparison-with-related-packages)
- [Parameters](#parameters)
- [Result](#result)

## Primary citation {#primary-citation}

Chen, J. C.-Y., Saha, S., & Bansal, M. (2023). "ReConcile: Round-Table
Conference Improves Reasoning via Consensus among Diverse LLMs".
arXiv:2309.13007.
https://arxiv.org/abs/2309.13007

Canonical repo (used for §B.5 5-bucket confidence calibration and
discussion prompt structure):
https://github.com/dinobby/ReConcile
— `utils.py::trans_confidence` : 5-bucket calibrated weight mapping
— `utils.py::parse_output`      : answer / explanation / confidence
                                  parser

## Algorithm (Chen 2023 §3 / Algorithm 1) {#algorithm-chen-2023-3-algorithm-1}

```
  r ← 0
  while r ≤ R and ¬consensus(answers):
      for each agent A_i:
          if r = 0:
              (a_i, e_i, p_i) ← A_i(init_prompt(task))
          else:
              others_view ← format_others(answers[r-1], explanations[r-1],
                                          confidences[r-1], convincing[r-1])
              (a_i, e_i, p_i) ← A_i(discussion_prompt(task, others_view))
      answers[r] ← (a_1, …, a_n)
      team_answer[r] ← argmax_a Σ_i f(p_i) · 𝟙(a_i = a)    -- §4
      r ← r + 1
  return team_answer[r-1]
```

Three phases (§3):

  Phase 1  (Initial)        : each agent generates (answer, explanation,
                               confidence) independently
  Phase 2  (Discussion)     : up to R rounds; each agent revises after
                               seeing others' (answer, explanation,
                               confidence) + "convincing" sample set
  Phase 3  (Vote)           : confidence-weighted argmax over current
                               round's normalized answers

Consensus criterion: all agents agree on the same normalized answer.
When consensus is reached, the loop terminates early.

## Defaults (Chen 2023 §3, §4 footnote) {#defaults-chen-2023-3-4-footnote}

| Symbol            | Value | Label | Source                                |
|-------------------|-------|-------|---------------------------------------|
| n (agents)        | 3     | (L)   | §3 main exp uses 3 diverse agents     |
| R (max_rounds)    | 3     | (L)   | §3 "up to three discussion rounds"    |
| convincing_count  | 4     | (L)   | §4 "we select a small number of       |
|                   |       |       | samples (4 in our experiments)"       |
| gen_tokens        | 600   | (X)   | Paper does not specify; infrastructure|
| temperature       | nil   | (X)   | Paper does not fix; API default used  |

The **5-bucket confidence calibration** is (L) — Lua transcription
of repo `utils.py::trans_confidence`; same boundary values, same
weights, top-to-bottom first-match evaluation (see
`M.CONFIDENCE_BUCKETS` for the shape contract):

  p ≤ 0.6        → 0.1
  0.6 < p < 0.8  → 0.3
  0.8 ≤ p < 0.9  → 0.5
  0.9 ≤ p < 1.0  → 0.8
  p = 1.0        → 1.0

## Entry contract {#entry-contract}

See `M.spec` below for the formal machine-readable contract:

- `confidence_to_weight`     — pure, direct-args. f(p) per §B.5 buckets
- `compute_weighted_argmax`  — pure, direct-args. §4 Phase 3 formula
- `check_consensus`          — pure, direct-args. all-agree predicate
- `build_discussion_prompt`  — pure, direct-args. returns { prompt, system }
- `run`                      — Strategy, ctx-threading. orchestrates N to N·(R+1) LLM calls

Four pure helpers are LLM-independent and unit-testable. `run` is the
only LLM-mediated entry.

## EXTENSION POINTS {#extension-points}

```
┌──────────────────────────────────────────────────────────────────────┐
│ REQUIRED                                                             │
│   ctx.task                  (string)         problem / question      │
│   ctx.agents                (array, diverse-LLM PATH; matches Chen  │
│       §3 main config) — list of specs, each                          │
│       { model = string [, system = string] }                         │
│     OR                                                               │
│   ctx.personas              (array, single-model rotation PATH;     │
│       outside Chen §3's diverse-LLM setup) — array of system-prompt  │
│       strings; single model + persona rotation. Sacrifices the       │
│       paper's distinct-LLM diversity property.                       │
├──────────────────────────────────────────────────────────────────────┤
│ (L)-override OPTION                                                  │
│   ctx.max_rounds            (number ≥ 1)     override R=3 default    │
│   ctx.convincing_count      (number ≥ 0)     override 4 (L §4 fn)    │
├──────────────────────────────────────────────────────────────────────┤
│ (X) infrastructure (paper does not specify)                          │
│   ctx.gen_tokens            (number)         max tokens per LLM call │
│   ctx.temperature           (number)         per-LLM temperature     │
│   ctx.init_prompt           (string template) override Phase 1 prompt│
│   ctx.discussion_prompt     (string template) override Phase 2 prompt│
│   ctx.system_prompt         (string)         override system prompt  │
│   ctx.parse_fn              (function)       custom response parser  │
│   ctx.confidence_buckets    (array of {threshold,weight})            │
│                                              override 5-bucket scale │
│                                              (X — invalidates §B.5)  │
├──────────────────────────────────────────────────────────────────────┤
│ Stability tier:                                                      │
│   stable     : max_rounds / convincing_count / gen_tokens / temp     │
│   v2-opt-in  : *_prompt / system_prompt / parse_fn                   │
│   experimental : personas (single-model fallback) /                  │
│                  confidence_buckets (paper guarantee not held)       │
└──────────────────────────────────────────────────────────────────────┘
```

## Comparison with related packages {#comparison-with-related-packages}

vs `dmad` (Du 2023): dmad does N agents × R rounds + majority vote on
extracted `\boxed{}` answers, no confidence weighting. reconcile adds
(1) confidence elicitation per agent per round, (2) §B.5 calibrated
weights, (3) early-stop on consensus.

vs `moa` (Wang 2024): moa uses an explicit Aggregate-and-Synthesize
LLM call as the ⊕ operator. reconcile aggregates by deterministic
confidence-weighted argmax (no aggregator LLM).

vs `dci` (Prakash 2026): dci runs 4 fixed roles through 8 typed-act
stages and emits a decision_packet with first-class minority_report.
reconcile is flatter: same-role agents converge via confidence-weighted
voting, simpler stop condition.

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.agents` | array of shape { model?: string, system?: string } | optional | Diverse-LLM PATH (Chen §3 main config): array of agent specs |
| `ctx.confidence_buckets` | array of shape { lo: number, lo_op?: string, weight: number } | optional | Override the §B.5 5-bucket calibration (X — invalidates paper guarantee). See M.CONFIDENCE_BUCKETS for the shape contract. |
| `ctx.convincing_count` | number | optional | Convincing-sample count (default: 4, (L) Chen §4 footnote) |
| `ctx.discussion_prompt` | string | optional | Override Phase 2 prompt (X) |
| `ctx.gen_tokens` | number | optional | Max tokens per LLM call (default: 600, (X) infrastructure) |
| `ctx.init_prompt` | string | optional | Override Phase 1 prompt (X) |
| `ctx.max_rounds` | number | optional | Max discussion rounds R (default: 3, (L) Chen §3) |
| `ctx.parse_fn` | any | optional | Custom (answer, explanation, confidence) parser fn(raw) → { answer, explanation, confidence } (X) |
| `ctx.personas` | array of string | optional | Single-model rotation PATH (outside Chen §3 main config): persona system prompts |
| `ctx.system_prompt` | string | optional | Override system prompt (X) |
| `ctx.task` | string | **required** | Problem statement (required) |
| `ctx.temperature` | number | optional | LLM temperature (default: API default, (X) Chen §3 does not state a value) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | — | Final team answer (normalized form of winning bucket) |
| `consensus` | boolean | — | true if all agents agreed at termination round; false if R+1 rounds exhausted |
| `history` | array of array of shape { agent: number, answer: string, confidence: number, explanation: string, normalized: string, raw_text?: string, round: number, weight: number } | — | history[r+1][i] = agent i's response at round r |
| `n_agents` | number | — | N actually used |
| `rounds_used` | number | — | Number of rounds completed (1..R+1; 1 = consensus at init phase) |
| `tally` | array of shape { answer: string, count: number, weight: number } | — | Vote tally at termination round |
| `total_llm_calls` | number | — | Total LLM calls actually made |
