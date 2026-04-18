---
name: ambig
version: 0.1.0
category: intent
result_shape: "shape { clarifications?: array of shape { description: string, element: string, question: string }, elements: array of shape { description: string, name: string, status: one_of(\"specified\", \"underspecified\") }, questions: array of string, specified_task: string, user_response?: string, verdict: one_of(\"specified\", \"underspecified\"), was_underspecified: boolean }"
description: "Underspecification detection — detect-clarify-integrate pipeline for ambiguous inputs"
source: ambig/init.lua
generated: gen_docs (V0)
---

# Ambig — underspecification detection and clarification pipeline

> Three-stage pipeline: detect ambiguity in the input, generate targeted clarification questions for underspecified elements, then integrate responses to produce a fully-specified task.

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.clarify_tokens` | number | optional | Max tokens for clarification phase (default 400) |
| `ctx.detect_tokens` | number | optional | Max tokens for detection phase (default 500) |
| `ctx.integrate_tokens` | number | optional | Max tokens for integration phase (default 500) |
| `ctx.task` | string | **required** | Task or request to analyze (required) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `clarifications` | array of shape { description: string, element: string, question: string } | optional | One entry per underspecified element; absent when verdict='specified' |
| `elements` | array of shape { description: string, name: string, status: one_of("specified", "underspecified") } | — | All parsed elements including the specified ones |
| `questions` | array of string | — | Clarification questions; empty when verdict='specified' |
| `specified_task` | string | — | Fully-specified task (equals input task when was_underspecified=false) |
| `user_response` | string | optional | Raw alc.specify response; absent when verdict='specified' |
| `verdict` | one_of("specified", "underspecified") | — | Overall verdict derived from the VERDICT: line |
| `was_underspecified` | boolean | — | Whether the clarify/integrate phases ran |
