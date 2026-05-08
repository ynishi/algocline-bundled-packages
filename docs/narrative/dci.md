---
name: dci
version: 0.1.0
category: synthesis
result_shape: deliberated
description: "Deliberative Collective Intelligence with typed epistemic acts"
source: dci/init.lua
generated: gen_docs (V0)
---

# dci(DCI-CF) — 8-stage structured deliberation with typed epistemic acts

> 8-stage structured deliberation algorithm with 4 reasoning archetypes, 14 typed epistemic acts, shared workspace, and a guaranteed decision_packet emission with first-class minority_report preservation.

## Contents

- [Algorithm](#algorithm)
- [Theoretical foundations](#theoretical-foundations)
- [Entry contract](#entry-contract)
- [Comparison with related packages](#comparison-with-related-packages)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Algorithm {#algorithm}

4 roles (fixed): `framer` / `explorer` / `challenger` / `integrator`.

14 acts organized into 6 classes (paper §4.1):

| Class | Acts |
|---|---|
| Orienting | `frame`, `clarify`, `reframe` |
| Generative | `propose`, `extend`, `spawn` (skeleton-only in v1) |
| Critical | `ask`, `challenge` |
| Integrative | `bridge`, `synthesize`, `recall` |
| Epistemic | `ground`, `update` |
| Decisional | `recommend` |

DCI-CF 8 stages:

1. **Stage 0** — init session
2. **Stage 1** — independent proposals (per-role act(s))
3. **Stage 2** — canonicalize & cluster options
4. **Stages 3-6** (loop up to `Rmax=2`):
   - Collect challenges / evidence
   - Admit new hypotheses (cutoff)
   - Revise & compress options
   - Score against criteria + convergence test (dominance or no_blocking)
5. **Stage 7** — fallback cascade
6. **Stage 8** — finalize decision packet (5 components completeness)

## Theoretical foundations {#theoretical-foundations}

Forces the session to emit a `decision_packet` with first-class
`minority_report` preservation even on fallback. Stage 7 fallback
cascade (outranking → minimax → satisficing → Integrator arbitration)
guarantees decision emission regardless of convergence quality, while
the typed epistemic act constraint keeps the reasoning trace auditable.

## Entry contract {#entry-contract}

- `run` — Strategy, ctx-threading. `ctx.task` required;
  returns `ctx.result :: deliberated shape` (see `alc_shapes`)

## Comparison with related packages {#comparison-with-related-packages}

Category: `synthesis` (panel-family alongside `panel`, `moa`, `recipe_*`).
vs `panel`: `panel` runs heterogeneous agents in parallel and aggregates.
DCI-CF runs fixed-role agents through a structured 8-stage protocol with
typed acts, yielding richer trace + guaranteed decision_packet shape.

## References {#references}

Prakash & Sunil (2026). "From Debate to Deliberation: Structured Collective
Reasoning with Typed Epistemic Acts". arXiv:2603.11781.

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.auto_card` | boolean | optional | Emit a Card on completion (default: false) |
| `ctx.card_pkg` | string | optional | Card pkg.name override (default: 'dci_<task_hash>') |
| `ctx.gen_tokens` | number | optional | Max tokens per LLM generation (default: 400) |
| `ctx.max_options` | number | optional | Max option count after canonicalize (default: 5) |
| `ctx.max_rounds` | number | optional | Rmax per DCI-CF (default: 2, paper §5 Table 1) |
| `ctx.num_finalists` | number | optional | Finalist count after revise (default: 3) |
| `ctx.roles` | array of string | optional | Role names (default: framer/explorer/challenger/integrator) |
| `ctx.scenario_name` | string | optional | Explicit scenario name for the emitted Card |
| `ctx.task` | string | **required** | Deliberation task / decision question |

## Result {#result}

Returns `deliberated` shape:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | — | Selected option's final answer text |
| `card_id` | string | optional | Emitted Card id (only when auto_card=true) |
| `convergence` | one_of("dominance", "no_blocking", "fallback") | — | How the session converged |
| `decision_packet` | shape { minority_report: array of shape { confidence: number, position: string, rationale: string }, next_actions: array of string, reopen_triggers: array of string, residual_objections: array of string, selected_option: shape { answer: string, evidence: array of string, rationale: string } } | — | 5-component decision packet; all 5 fields MUST be non-nil |
| `history` | array of table | — | Per-stage typed-act log (14-act typed) |
| `stats` | shape { options_count: number, rounds_used: number, total_acts: number, total_llm_calls: number } | — | Execution statistics |
| `workspace` | shape { emerging_ideas: array of string, key_frames: array of string, next_actions: array of string, problem_view: string, synthesis_in_progress: string, tensions: array of string } | — | Shared workspace 6 fields after finalization |
