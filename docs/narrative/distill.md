---
name: distill
version: 0.1.0
category: extraction
result_shape: "shape { chunks_processed: number, extractions?: array of string, relevant_chunks?: number, summary: string }"
description: "MapReduce summarization — parallel chunk processing with unified reduction"
source: distill/init.lua
generated: gen_docs (V0)
---

# Distill — MapReduce summarization and extraction

> Splits large text into chunks, processes each in parallel, then reduces into a unified result.

## Contents

- [Parameters](#parameters)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.chunk_overlap` | number | optional | Overlap lines between chunks (default 5) |
| `ctx.chunk_size` | number | optional | Lines per chunk passed to alc.chunk (default 100) |
| `ctx.goal` | string | optional | What to extract/summarize (default 'Summarize the key points') |
| `ctx.map_tokens` | number | optional | Max tokens per map call (default 300) |
| `ctx.reduce_tokens` | number | optional | Max tokens for the final reduce call (default 600) |
| `ctx.text` | string | **required** | Source text to process (required) |
