---
name: meta_prompt
version: 0.1.0
category: reasoning
result_shape: "shape { answer: string, experts_consulted: array of shape { focus: string, question: string, response: string, role: string }, total_experts: number }"
description: "Meta-Prompting — orchestrator identifies and dispatches to specialist personas"
source: meta_prompt/init.lua
generated: gen_docs (V0)
---

# meta_prompt(Meta-Prompting) — orchestrator dispatches to specialist personas

> A meta-orchestrator analyzes the task, identifies required expertise, then sequentially delegates to specialist personas, collecting and integrating their outputs into a unified final answer.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [Theoretical foundations](#theoretical-foundations)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local mp = require("meta_prompt")
return mp.run({ task = "Explain the implications of quantum entanglement" })
```

## Algorithm {#algorithm}

Given a task, the pkg performs three phases:

1. Orchestration — the meta-orchestrator identifies up to `max_experts`
   specialist roles and formulates a focused question for each.
2. Expert consultation — each specialist is queried sequentially,
   receiving prior expert outputs as accumulated context.
3. Synthesis — the meta-orchestrator integrates all expert analyses
   into a single, conflict-resolved final answer.

## Theoretical foundations {#theoretical-foundations}

Based on Suzgun & Kalai (2024), Meta-Prompting frames the LLM as a
conductor that recruits specialist sub-agents from the same model.
The scaffolding is task-agnostic: no domain-specific prompts are
hard-coded. Performance gains arise from structured decomposition and
role-conditioned generation rather than from additional fine-tuning.

## References {#references}

- Suzgun, M. & Kalai, A. T. (2024). "Meta-Prompting: Enhancing Language
  Models with Task-Agnostic Scaffolding". arXiv:2401.12954.
  https://arxiv.org/abs/2401.12954

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.max_experts` | number | optional | Maximum number of expert consultations (default: 4) |
| `ctx.task` | string | **required** | The problem to solve |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | — | Orchestrator's integrated synthesis of all expert analyses |
| `experts_consulted` | array of shape { focus: string, question: string, response: string, role: string } | — | Sequential expert consultations with the question asked and the response received |
| `total_experts` | number | — | Count of experts actually consulted (may be < max_experts due to parsing fallback) |
