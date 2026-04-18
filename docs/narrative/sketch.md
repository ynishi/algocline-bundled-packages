---
name: sketch
version: 0.1.0
category: reasoning
result_shape: "shape { answer: string, paradigm: string, reasoning: string, routing: shape { confidence: number, method: string } }"
description: "Sketch-of-Thought — cognitive-inspired efficient reasoning. Routes to Conceptual Chaining, Chunked Symbolism, or Expert Lexicons based on task type. 60-84% token reduction vs standard CoT."
source: sketch/init.lua
generated: gen_docs (V0)
---

# sketch — Sketch-of-Thought: cognitive-inspired efficient reasoning

> Selects one of three cognitive paradigms based on task characteristics, then generates compressed reasoning using that paradigm's notation. Reduces reasoning tokens by 60-84% while maintaining or improving accuracy.

## Contents

- [Parameters](#parameters)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.max_tokens` | number | optional | Max tokens for reasoning (default: 200) |
| `ctx.paradigm` | string | optional | Force paradigm name (conceptual_chaining / chunked_symbolism / expert_lexicons); nil => auto-route |
| `ctx.routing_threshold` | number | optional | Keyword confidence threshold for LLM fallback (default: 0.4) |
| `ctx.task` | string | **required** | The problem to solve |
