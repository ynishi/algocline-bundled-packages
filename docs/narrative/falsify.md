---
name: falsify
version: 0.1.0
category: exploration
result_shape: "shape { all_hypotheses: array of shape { confidence: number, derived_from?: number, history: array of shape { refutation: string, round: number, verdict: string }, id: number, refutation_attempts: number, status: string, text: string }, answer: string, stats: shape { initial_count: number, rounds: number, total_derived: number, total_generated: number, total_refuted: number, total_survived: number }, survivors: array of shape { confidence: number, derived_from?: number, history: array of shape { refutation: string, round: number, verdict: string }, id: number, refutation_attempts: number, status: string, text: string } }"
description: "Sequential Falsification — Popper-style hypothesis exploration via active refutation, pruning, and successor derivation. Expands search space through refutation-driven insight."
source: falsify/init.lua
generated: gen_docs (V0)
---

# falsify — Sequential Falsification for Hypothesis Exploration

> Explores hypothesis space via Popper's falsificationism: generate hypotheses, attempt to refute each one, prune the refuted, derive new hypotheses from the refutation insights. Unlike verify_first (checks consistency) or cove (verification chain), falsify actively ATTACKS hypotheses and uses refutation failures as evidence of robustness, while refutation successes drive the generation of improved successor hypotheses.

## Contents

- [Parameters](#parameters)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.derive_on_refute` | boolean | optional | Generate successor hypotheses from refuted ones (default: true) |
| `ctx.initial_hypotheses` | number | optional | Seed hypothesis count (default: 4) |
| `ctx.max_hypotheses` | number | optional | Upper bound on active hypotheses (default: 12) |
| `ctx.max_rounds` | number | optional | Maximum falsification rounds (default: 3) |
| `ctx.task` | string | **required** | The problem or question to investigate |
