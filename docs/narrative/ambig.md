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

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.clarify_tokens` | number | optional | Max tokens for clarification phase (default 400) |
| `ctx.detect_tokens` | number | optional | Max tokens for detection phase (default 500) |
| `ctx.integrate_tokens` | number | optional | Max tokens for integration phase (default 500) |
| `ctx.task` | string | **required** | Task or request to analyze (required) |
