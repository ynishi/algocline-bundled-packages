---
name: sot
version: 0.1.0
category: generation
result_shape: "shape { output: string, section_count: number, sections: array of string, skeleton: array of string }"
description: "Skeleton-of-Thought — outline-first parallel section generation"
source: sot/init.lua
generated: gen_docs (V0)
---

# sot(SoT) — Skeleton-of-Thought parallel generation

> Generates a structural outline first, then fills each section in parallel via alc.parallel (single alc.llm_batch round-trip). Produces structurally coherent long-form output.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [Theoretical foundations](#theoretical-foundations)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local sot = require("sot")
return sot.run(ctx)
```

## Algorithm {#algorithm}

1. **Skeleton generation** — prompt the LLM to produce a numbered
   outline of up to `max_sections` section titles.
2. **Parallel fill** — send all sections concurrently via
   `alc.parallel` (single `alc.llm_batch` round-trip), each prompt
   carrying the full outline for context so sections do not overlap.
3. **Assembly** — concatenate fills under `## {title}` headings to
   produce the final long-form output.

## Theoretical foundations {#theoretical-foundations}

Ning et al. (2023) demonstrate that skeleton-guided parallel decoding
reduces end-to-end latency by up to 2.39x on 8 of 12 tested models
(paper §3.1.1). The key invariant is that each section is
self-contained enough to be written without the other fills, which
the skeleton prompt enforces by asking for independently writable
aspects. This pkg uses `alc.parallel` (not `alc.map`) to match the
paper's single-batch parallel decoding claim.

## References {#references}

- Ning, X., Lin, Z., Zhou, Z., Wang, T., Yang, H., Zhang, M., Meng, F.,
  Zhou, J. (2023). "Skeleton-of-Thought: Prompting LLMs for Efficient
  Parallel Generation". arXiv:2307.15337.

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.max_sections` | number | optional | Maximum outline sections (default: 6) |
| `ctx.section_tokens` | number | optional | Max tokens per section fill (default: 400) |
| `ctx.skeleton_tokens` | number | optional | Max tokens for skeleton generation (default: 300) |
| `ctx.task` | string | **required** | The task requiring long-form output |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `output` | string | — | Final assembled long-form output (## headings + filled sections) |
| `section_count` | number | — | Count of sections parsed and filled |
| `sections` | array of string | — | Per-section LLM fills in the same order as skeleton |
| `skeleton` | array of string | — | Parsed section titles from skeleton (fallback: single-element = original task) |
