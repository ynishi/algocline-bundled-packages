---
name: dci
version: 0.1.0
category: synthesis
result_shape: deliberated
description: "Deliberative Collective Intelligence (DCI-CF). 4 roles (Framer/Explorer/Challenger/Integrator) × 14 typed epistemic acts (6 classes) × shared workspace (6 fields) × 8-stage convergence algorithm. Emits a decision_packet with 5 non-nil components (selected_option, residual_objections, minority_report, next_actions, reopen_triggers). Stage 7 fallback cascade (outranking → minimax → satisficing → Integrator arbitration) preserves minority_report even on forced convergence."
source: dci/init.lua
generated: gen_docs (V0)
---

# dci — Deliberative Collective Intelligence (DCI-CF).

> Implements the 8-stage structured deliberation algorithm from:   Prakash, Sunil   "From Debate to Deliberation: Structured Collective Reasoning    with Typed Epistemic Acts" (arXiv:2603.11781, 2026-03-12)

## Contents

- [Parameters](#parameters)
- [Result](#result)

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
