---
name: dmad
version: 0.2.0
category: reasoning
result_shape: "shape { answer: string, debate_log: array of shape { agent: number, round: number, text: string }, last_answers: array of string, n_agents: number, n_rounds: number, responses: array of array of string, tally: array of shape { answer: string, count: number }, total_llm_calls: number }"
description: "Multi-Agent Debate (Du 2023) — N parallel agents, R debate rounds, majority vote"
source: dmad/init.lua
generated: gen_docs (V0)
---

# dmad — Multi-Agent Debate (Du 2023) — N parallel agents, R debate rounds

## Contents

- [Primary citation](#primary-citation)
- [Algorithm (Du 2023 §3)](#algorithm-du-2023-3)
- [Defaults (Du 2023 repo `gsm/gen_gsm.py`)](#defaults-du-2023-repo-gsm-gen-gsm-py)
- [Entry contract](#entry-contract)
- [EXTENSION POINTS](#extension-points)
- [Comparison with related packages](#comparison-with-related-packages)
- [History](#history)
- [Parameters](#parameters)
- [Result](#result)

## Primary citation {#primary-citation}

Du, Y., Li, S., Torralba, A., Tenenbaum, J. B., & Mordatch, I. (2023).
"Improving Factuality and Reasoning in Language Models through
Multiagent Debate". arXiv:2305.14325.
https://arxiv.org/abs/2305.14325

Canonical reference implementation (paper has no numbered Algorithm
block — repo is treated as the literal source for prompt templates and
default parameters):
https://github.com/composable-models/llm_multiagent_debate
— `gsm/gen_gsm.py`   : N=3 agents, R=2 rounds, INIT / DEBATE string
                       literals lifted into Lua (prefix / per-agent
                       block / suffix structure preserved; per-agent
                       block keeps the triple-backtick wrapper)
— `gsm/eval_gsm.py`  : `most_frequent` first-wins majority on `\boxed{}`

## Algorithm (Du 2023 §3) {#algorithm-du-2023-3}

```
  round 0 (init):  for each agent i = 1..N (parallel):
                       a_{i,0} ← LLM(INIT_TEMPLATE(task))
  for r = 1..R:
      for each agent i = 1..N (parallel):
          others ← { a_{j,r-1} : j ≠ i }
          a_{i,r} ← LLM(DEBATE_TEMPLATE(task, others))
  answers ← { extract(a_{i,R}) : i = 1..N }
  return majority_vote(answers)         -- eval_gsm.py: most_frequent
```

Three pieces compose the algorithm:

  N (n_agents)  3   parallel reasoning agents (each is one LLM thread)
  R (n_rounds)  2   debate rounds after the initial proposal
  aggregate     majority vote, first-wins tie-break, on extracted answers

Total LLM calls: N + N·R = N·(R+1). Default 3·(2+1) = 9.

## Defaults (Du 2023 repo `gsm/gen_gsm.py`) {#defaults-du-2023-repo-gsm-gen-gsm-py}

| Symbol | Value | Label | Source                                                    |
|--------|-------|-------|-----------------------------------------------------------|
| N      | 3     | (L)   | `gen_gsm.py` agents=3                                     |
| R      | 2     | (L)   | `gen_gsm.py` rounds=2                                     |
| temp   | nil   | (X)   | Paper does not fix temperature; repo omits the param so   |
|        |       |       | OpenAI API default is used. Pkg leaves nil to mirror this |
| tokens | 500   | (X)   | Paper does not specify max_tokens. (X) infrastructure;    |
|        |       |       | provenance: prior dmad v0.1.0 baseline (commit 54faaa5)   |

The INIT and DEBATE prompt templates are (L) — Lua transcriptions of
the corresponding `gen_gsm.py` string literals. The DEBATE template
is built from `prefix + per-agent block (each wraps a response in
``` triple backticks ```) + suffix`, matching repo `construct_message`
byte-for-byte (modulo Python f-string `{}` ↔ Lua `%s` substitution
and the implicit `\n` semantics). The `\boxed{answer}` sentinel that
`extract_boxed` reads back is preserved. Overriding the templates
(X-mode) invalidates the paper's effect guarantee but the pkg
accepts the override.

## Entry contract {#entry-contract}

See `M.spec` below for the formal machine-readable contract:

- `build_init_prompt`   — pure, direct-args. returns { prompt, system }
- `build_debate_prompt` — pure, direct-args. returns { prompt, system }
- `extract_boxed`       — pure, direct-args. returns final-answer string
- `aggregate_majority`  — pure, direct-args. returns { answer, count, tally }
- `run`                 — Strategy, ctx-threading. orchestrates N·(R+1) LLM calls

The four sub-entries are LLM-independent and unit-testable. `run` is
the only LLM-mediated entry.

## EXTENSION POINTS {#extension-points}

```
┌──────────────────────────────────────────────────────────────────────┐
│ REQUIRED                                                             │
│   ctx.task                  (string)         problem statement       │
├──────────────────────────────────────────────────────────────────────┤
│ (L)-override OPTION                                                  │
│   ctx.n_agents              (number ≥ 2)     override N default      │
│   ctx.n_rounds              (number ≥ 1)     override R default      │
├──────────────────────────────────────────────────────────────────────┤
│ (X) infrastructure (paper does not specify)                          │
│   ctx.gen_tokens            (number)         max tokens per LLM call │
│   ctx.temperature           (number)         per-LLM temperature     │
│   ctx.init_prompt           (string template) override init prompt   │
│   ctx.debate_prompt         (string template) override debate prompt │
│   ctx.system_prompt         (string)         override system prompt  │
│   ctx.extract_fn            (function)       custom answer extractor │
│                                              (default: extract_boxed)│
├──────────────────────────────────────────────────────────────────────┤
│ Stability tier:                                                      │
│   stable     : n_agents / n_rounds / gen_tokens / temperature        │
│   v2-opt-in  : *_prompt / system_prompt / extract_fn                 │
│                (template/extractor format may evolve)                │
└──────────────────────────────────────────────────────────────────────┘
```

Overriding any (L) default invalidates the paper's effect guarantee.

## Comparison with related packages {#comparison-with-related-packages}

vs `hegelian` (Abdali 2025): hegelian is single-thread Thesis/Antithesis/
Synthesis with temperature annealing — a different paper, different
algorithm. dmad runs N agents in parallel debating each other.

vs `sc` (Self-Consistency, Wang 2022): sc samples N independent paths
in a single round, no inter-path interaction. dmad has R rounds of
explicit cross-agent visibility.

vs `moa` (Wang 2024): moa is L-layer hierarchical aggregation
(proposers + aggregators). dmad is flat: every agent sees every other
agent's previous-round response.

## History {#history}

dmad v0.1.0 (commit 54faaa5, 2026-03-15) cited Du 2023 but implemented
a Hegelian dialectic with a "rebuttal" stage that has no source in
Du's paper. The Hegelian methodology was extracted to a separate
`hegelian/` pkg (Abdali 2025 paper-explicit, commit e030095 + doc
correction 5838927, 2026-05-15). This v0.2.0 rewrites dmad as pure
Du 2023 Multi-Agent Debate; the "rebuttal" stage is removed (no Du
paper basis); Hegelian users should switch to `require("hegelian")`.

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.debate_prompt` | string | optional | Override DEBATE template (X) |
| `ctx.gen_tokens` | number | optional | Max tokens per LLM call (default: 500, (X) infrastructure) |
| `ctx.init_prompt` | string | optional | Override INIT template (X) |
| `ctx.n_agents` | number | optional | Number of parallel agents (default: 3, (L) Du repo gen_gsm.py) |
| `ctx.n_rounds` | number | optional | Number of debate rounds after init (default: 2, (L) Du repo gen_gsm.py) |
| `ctx.system_prompt` | string | optional | Override system prompt (X) |
| `ctx.task` | string | **required** | Problem statement (required) |
| `ctx.temperature` | number | optional | LLM temperature (default: API default, (X) infrastructure; paper does not fix) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | — | Final majority-vote answer |
| `debate_log` | array of shape { agent: number, round: number, text: string } | — | Flat chronological log of (agent, round, text) tuples |
| `last_answers` | array of string | — | Extracted answer per agent at round R |
| `n_agents` | number | — | N actually used |
| `n_rounds` | number | — | R actually used |
| `responses` | array of array of string | — | responses[r+1][i] = a_{i,r} (1-based for Lua); responses[1] = init, responses[R+1] = final |
| `tally` | array of shape { answer: string, count: number } | — | Full vote tally |
| `total_llm_calls` | number | — | Total LLM calls made (= N·(R+1)) |
