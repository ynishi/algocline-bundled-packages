---
name: moa
version: 0.2.0
category: aggregation
result_shape: "shape { answer: string, layers: array of shape { aggregated: string, layer: number, proposers: array of shape { model?: string, proposer: number, text: string } }, n_layers: number, n_proposers: number, total_llm_calls: number }"
description: "Mixture-of-Agents (Wang 2024) — L-layer × n-proposer aggregation with Aggregate-and-Synthesize"
source: moa/init.lua
generated: gen_docs (V0)
---

# moa — Mixture-of-Agents (Wang 2024) — L-layer, n-proposer aggregation

## Contents

- [Primary citation](#primary-citation)
- [Algorithm (Wang 2024 §2.2)](#algorithm-wang-2024-2-2)
- [Defaults (Wang 2024 §3)](#defaults-wang-2024-3)
- [Proposer models (paper main experiment, Wang 2024 §3)](#proposer-models-paper-main-experiment-wang-2024-3)
- [Entry contract](#entry-contract)
- [EXTENSION POINTS](#extension-points)
- [Comparison with related packages](#comparison-with-related-packages)
- [Parameters](#parameters)
- [Result](#result)

## Primary citation {#primary-citation}

Wang, J., Wang, J., Athiwaratkun, B., Zhang, C., & Zou, J. (2024).
"Mixture-of-Agents Enhances Large Language Model Capabilities".
arXiv:2406.04692.
https://arxiv.org/abs/2406.04692

## Algorithm (Wang 2024 §2.2) {#algorithm-wang-2024-2-2}

Layered aggregation. For each layer i, n proposer agents A_{i,1..n}
generate responses to the current input x_i, and an aggregator ⊕
synthesizes them into y_i, which becomes the next layer's input:

```
  y_i     = ⊕_{j=1}^{n}[A_{i,j}(x_i)] + x_1
  x_{i+1} = y_i
```

where ⊕ denotes applying the **Aggregate-and-Synthesize** prompt
(Table 1) to the n proposer outputs, and `+` is text concatenation.

The default MoA configuration runs **L=3 layers** with **n=6 proposers
per layer** (Wang 2024 §3 main experiment). MoA-Lite uses **L=2** for
cost efficiency. The final layer's aggregator output is the answer.

## Defaults (Wang 2024 §3) {#defaults-wang-2024-3}

| Symbol     | Value | Label | Source                                          |
|------------|-------|-------|-------------------------------------------------|
| L          | 3     | (L)   | Wang §3 "We use 3 MoA layers"                   |
| n          | 6     | (L)   | Wang §3 main exp uses 6 open-source proposers   |
| temp       | 0.7   | (X)   | Wang §3 main config does not state a temperature|
|            |       |       | for the layered MoA run. 0.7 is the only        |
|            |       |       | numeric value §3 names (single-proposer         |
|            |       |       | ablation row); pkg uses 0.7 to anchor the       |
|            |       |       | default to that one named value rather than an  |
|            |       |       | implementer-chosen number.                      |
| max_tokens | 2048  | (X)   | Paper does not specify. (X) infrastructure;     |
|            |       |       | provenance: AS_PROMPT requires synthesizing all |
|            |       |       | proposer outputs, so a larger budget than       |
|            |       |       | per-proposer is required by construction.       |

The **AS_PROMPT_TEMPLATE** (Aggregate-and-Synthesize) is (L) — the
Lua string literal is identical to Wang 2024 Table 1's English text
(punctuation / capitalization / line breaks all match; the only
transformation is the Python `{}` placeholder rendered as Lua `%s`).

## Proposer models (paper main experiment, Wang 2024 §3) {#proposer-models-paper-main-experiment-wang-2024-3}

The main MoA experiment uses these 6 open-source proposers (all
accessible via Together AI):

  - Qwen1.5-110B-Chat
  - Qwen1.5-72B-Chat
  - WizardLM-8x22B
  - LLaMA-3-70B-Instruct
  - Mixtral-8x22B-v0.1
  - dbrx-instruct

These models are (L) for reproducing paper results, but they are NOT
hard-coded by this pkg — the caller MUST supply `proposers` (REQUIRED
extension point). Hard-coding 6 specific Together AI model IDs would
bind the pkg to a specific API tier and exclude OSS / local-model
callers.

## Entry contract {#entry-contract}

See `M.spec` below for the formal machine-readable contract:

- `build_proposer_prompt`   — pure, direct-args. returns { prompt, system }
- `build_aggregator_prompt` — pure, direct-args. returns { prompt, system }
- `run`                     — Strategy, ctx-threading. orchestrates L · n + L LLM calls

Two pure helpers are LLM-independent and unit-testable. `run` is the
only LLM-mediated entry.

## EXTENSION POINTS {#extension-points}

```
┌──────────────────────────────────────────────────────────────────────┐
│ REQUIRED                                                             │
│   ctx.task                  (string)         problem / user query    │
│   ctx.proposers             (array, multi-model PATH; matches Wang  │
│       §3 main config) — list of specs, each                          │
│       { model = string [, system = string] }; pkg makes one LLM      │
│       call per proposer per layer                                    │
│     OR                                                               │
│   ctx.personas              (array, single-model rotation PATH;     │
│       outside Wang §3's multi-model setup) — array of system-prompt  │
│       strings; pkg uses a single model and rotates personas per      │
│       proposer. Convenient for OSS callers without 6 distinct        │
│       models; sacrifices the paper's distinct-model diversity        │
│       property.                                                      │
├──────────────────────────────────────────────────────────────────────┤
│ (L)-override OPTION                                                  │
│   ctx.n_layers              (number ≥ 1)     override L=3 default    │
├──────────────────────────────────────────────────────────────────────┤
│ (X) infrastructure (paper does not specify or specifies only         │
│ ablation)                                                            │
│   ctx.temperature           (number)         per-LLM temperature     │
│   ctx.proposer_tokens       (number)         max tokens per proposer │
│   ctx.aggregator_tokens     (number)         max tokens per aggreg.  │
│   ctx.proposer_prompt       (string template) override proposer body │
│   ctx.aggregator_prompt     (string template) override AS_PROMPT     │
│   ctx.system_prompt         (string)         override proposer sys.  │
├──────────────────────────────────────────────────────────────────────┤
│ Stability tier:                                                      │
│   stable     : n_layers / temperature / proposer_tokens / aggreg_t   │
│   v2-opt-in  : proposer_prompt / aggregator_prompt / system_prompt   │
│                (template format may evolve in future versions)       │
│   experimental : personas (single-model fallback, paper guarantee    │
│                  not held)                                           │
└──────────────────────────────────────────────────────────────────────┘
```

Overriding `aggregator_prompt` invalidates the AS_PROMPT_TEMPLATE
(L) guarantee. Caller is responsible for keeping ⊕ semantics consistent.

## Comparison with related packages {#comparison-with-related-packages}

vs `panel` (sequential multi-role discussion): panel uses heterogeneous
caller-supplied roles per turn; one model per turn. moa runs n
proposers in parallel and applies an explicit Aggregate-and-Synthesize
step.

vs `dmad` (Du 2023 Multi-Agent Debate): dmad has N agents debating
(each agent sees others' previous-round answers) for R rounds and
aggregates by majority vote. moa is layered hierarchical aggregation
with an explicit synthesizer prompt at each layer boundary.

vs `sc` (Self-Consistency, Wang 2022): sc samples N independent paths
from one model with majority voting. moa uses N distinct models /
personas and an LLM-as-judge aggregator at each layer.

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.aggregator_prompt` | string | optional | Override AS_PROMPT_TEMPLATE (X) |
| `ctx.aggregator_tokens` | number | optional | Max tokens per aggregator (default: 2048, (X) infrastructure) |
| `ctx.n_layers` | number | optional | Number of layers L (default: 3, (L) Wang §3) |
| `ctx.personas` | array of string | optional | Single-model rotation PATH (outside Wang §3 main config): array of system-prompt strings |
| `ctx.proposer_prompt` | string | optional | Override proposer prompt (X) |
| `ctx.proposer_tokens` | number | optional | Max tokens per proposer (default: 512, (X) infrastructure) |
| `ctx.proposers` | array of shape { model?: string, system?: string } | optional | Multi-model PATH (Wang §3 main config): array of proposer specs; each layer reuses the same list |
| `ctx.system_prompt` | string | optional | Override proposer system prompt (X) |
| `ctx.task` | string | **required** | Problem statement (required) |
| `ctx.temperature` | number | optional | LLM temperature (default: 0.7, (X) Wang §3 main config does not state a value) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | — | Final aggregator output from layer L |
| `layers` | array of shape { aggregated: string, layer: number, proposers: array of shape { model?: string, proposer: number, text: string } } | — | Per-layer records: proposer outputs + aggregator output |
| `n_layers` | number | — | L actually executed |
| `n_proposers` | number | — | n actually used (from proposers / personas length) |
| `total_llm_calls` | number | — | Total LLM calls (= L · (n + 1)) |
