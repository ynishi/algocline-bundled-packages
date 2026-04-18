---
name: orch_escalate
version: 0.1.0
category: orchestration
result_shape: "shape { escalation_depth: number, levels: array of shape { feedback: string, name: string, output: string, passed: boolean, phase_outputs?: array of string, score: number, threshold: number }, output: string, score: number, selected_level: string, status: string, total_llm_calls: number }"
description: "Cascade escalation: start with lightest strategy, escalate to heavier ones if quality is insufficient. Minimizes cost for easy tasks, guarantees quality for hard ones. Based on Cascade Escalation (Microsoft + DAAO cost optimization)."
source: orch_escalate/init.lua
generated: gen_docs (V0)
---

# orch_escalate — Cascade Escalation Orchestration

> Start with lightest strategy, escalate to heavier ones if quality is insufficient. Minimizes cost for easy tasks, guarantees quality for hard ones.

## Contents

- [Parameters](#parameters)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.levels` | array of any | optional | Custom escalation chain [{name, prompt_template\|multi_phase, threshold, ...}] |
| `ctx.on_fail` | string | optional | "error" \| "partial" (default: "partial") |
| `ctx.task` | string | **required** | Task description |
