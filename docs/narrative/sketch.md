---
name: sketch
version: 0.1.0
category: reasoning
result_shape: "shape { answer: string, paradigm: string, reasoning: string, routing: shape { confidence: number, method: string } }"
description: "Sketch-of-Thought — cognitive-inspired efficient reasoning. Routes to Conceptual Chaining, Chunked Symbolism, or Expert Lexicons based on task type. 60-84% token reduction vs standard CoT."
source: sketch/init.lua
generated: gen_docs (V0)
---

# sketch(Sketch) — Sketch-of-Thought cognitive-inspired efficient reasoning

> Selects one of three cognitive paradigms based on task characteristics, then generates compressed reasoning using that paradigm's notation. Reduces reasoning tokens by 60-84% while maintaining or improving accuracy.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local sketch = require("sketch")
return sketch.run(ctx)
```

## Algorithm {#algorithm}

The pipeline uses 1-2 LLM calls:

1. Route — select paradigm via keyword heuristic (0 LLM calls);
   LLM fallback if ambiguous.
2. Sketch — generate compressed reasoning and final answer.

Three cognitive paradigms:

- Conceptual Chaining — key concepts linked with arrows (episodic
  memory).
- Chunked Symbolism — variables and equations (working memory
  chunking).
- Expert Lexicons — domain notation and abbreviations (expert
  schemas).

## References {#references}

- Aytes, S., Baek, J., Hwang, S. J. (2025). "Sketch-of-Thought:
  Efficient LLM Reasoning with Adaptive Cognitive-Inspired
  Sketching". EMNLP 2025. https://arxiv.org/abs/2503.05179

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.max_tokens` | number | optional | Max tokens for reasoning (default: 200) |
| `ctx.paradigm` | string | optional | Force paradigm name (conceptual_chaining / chunked_symbolism / expert_lexicons); nil => auto-route |
| `ctx.routing_threshold` | number | optional | Keyword confidence threshold for LLM fallback (default: 0.4) |
| `ctx.task` | string | **required** | The problem to solve |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | — | Extracted final answer string |
| `paradigm` | string | — | Paradigm used in execution after routing |
| `reasoning` | string | — | Extracted <sketch>...</sketch> body (or full LLM text if parsing failed) |
| `routing` | shape { confidence: number, method: string } | — | Routing diagnostic: method ∈ {manual, keyword, llm}, confidence 0-1 |
