---
name: distill
version: 0.1.0
category: extraction
result_shape: "shape { chunks_processed: number, extractions?: array of string, relevant_chunks?: number, summary: string }"
description: "MapReduce summarization — parallel chunk processing with unified reduction"
source: distill/init.lua
generated: gen_docs (V0)
---

# distill — MapReduce summarization and extraction

> Splits large text into chunks, processes each in parallel, then reduces into a unified result.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [Theoretical foundations](#theoretical-foundations)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local distill = require("distill")
return distill.run(ctx)
```

## Algorithm {#algorithm}

Three-phase MapReduce pipeline (LLM×MapReduce §3):

1. **Chunk** — split `ctx.text` into overlapping windows of `chunk_size` lines
   with `chunk_overlap` lines of context carry-over
2. **Map** — process each chunk in parallel via `alc.parallel`; each LLM call
   extracts information relevant to `ctx.goal`; chunks with no relevant content
   respond with the sentinel `NONE`
3. **Reduce** — filter out `NONE` responses, concatenate surviving extractions,
   and synthesize a unified result via a single LLM call

## Theoretical foundations {#theoretical-foundations}

Based on LLM×MapReduce (Chen et al. 2024, arXiv:2410.09342). The paper
demonstrates that the MapReduce paradigm enables LLMs to process arbitrarily
long documents by decomposing them into independent map tasks and merging the
partial results in a single reduce pass. The `NONE` sentinel filter ensures
the reduce context contains only relevant extractions, mitigating noise from
irrelevant chunks.

## References {#references}

- Chen, Zhu, Wang, Li, Liu, Han (2024). "LLM×MapReduce: Simplified Long-Sequence
  Processing using Large Language Models". arXiv:2410.09342.

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.chunk_overlap` | number | optional | Overlap lines between chunks (default 5) |
| `ctx.chunk_size` | number | optional | Lines per chunk passed to alc.chunk (default 100) |
| `ctx.goal` | string | optional | What to extract/summarize (default 'Summarize the key points') |
| `ctx.map_tokens` | number | optional | Max tokens per map call (default 300) |
| `ctx.reduce_tokens` | number | optional | Max tokens for the final reduce call (default 600) |
| `ctx.text` | string | **required** | Source text to process (required) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `chunks_processed` | number | — | Number of chunks produced by alc.chunk (0 when the input did not split) |
| `extractions` | array of string | optional | Per-chunk raw map outputs in chunk order. Present only on the normal path — absent on both early-return paths. |
| `relevant_chunks` | number | optional | Count of chunks whose map output was not 'NONE'. Absent on the no-chunks early-return path; present on both the all-filtered and normal paths. |
| `summary` | string | — | Final synthesized output. Empty string on the no-chunks early-return path, a canned 'No relevant information' message when every chunk was filtered out, and the reduce-phase LLM output on the normal path. |
