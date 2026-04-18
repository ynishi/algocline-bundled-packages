---
name: prism
version: 0.1.0
category: intent
result_shape: "shape { clarifications: array of shape { question: string, sub_intent: string, sub_intent_index: number }, dependencies: array of shape { from: number, to: number }, specified_task: string, sub_intents: array of shape { status: one_of(\"specified\", \"underspecified\"), text: string }, user_response?: string, was_underspecified: boolean }"
description: "Cognitive-load-aware intent decomposition — logical dependency ordering for minimal-friction clarification"
source: prism/init.lua
generated: gen_docs (V0)
---

# Prism — cognitive-load-aware intent decomposition and logical clarification

> Decomposes complex user intents into structured sub-intents, identifies logical dependencies among them, and generates clarification questions in dependency order to minimize user cognitive load.

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.clarify_tokens` | number | optional | Max tokens per clarification phase (default 400) |
| `ctx.decompose_tokens` | number | optional | Max tokens for decomposition phase (default 600) |
| `ctx.max_sub_intents` | number | optional | Maximum sub-intents to extract (default 8) |
| `ctx.task` | string | **required** | Task or request to analyze (required) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `clarifications` | array of shape { question: string, sub_intent: string, sub_intent_index: number } | — | Empty when task was fully specified; otherwise one entry per underspecified sub-intent |
| `dependencies` | array of shape { from: number, to: number } | — | Empty when task was fully specified or no dependencies detected |
| `specified_task` | string | — | Fully-specified task (equals input task when was_underspecified=false) |
| `sub_intents` | array of shape { status: one_of("specified", "underspecified"), text: string } | — | All extracted sub-intents in natural parse order |
| `user_response` | string | optional | Raw alc.specify response; present only when was_underspecified=true |
| `was_underspecified` | boolean | — | Whether any sub-intent required clarification |
