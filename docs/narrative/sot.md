---
name: sot
version: 0.1.0
category: generation
result_shape: "shape { output: string, section_count: number, sections: array of string, skeleton: array of string }"
description: "Skeleton-of-Thought — outline-first parallel section generation"
source: sot/init.lua
generated: gen_docs (V0)
---

# SoT — Skeleton-of-Thought parallel generation

> Generates a structural outline first, then fills each section in parallel via alc.map. Produces structurally coherent long-form output.

## Contents

- [Parameters](#parameters)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.max_sections` | number | optional | Maximum outline sections (default: 6) |
| `ctx.section_tokens` | number | optional | Max tokens per section fill (default: 400) |
| `ctx.skeleton_tokens` | number | optional | Max tokens for skeleton generation (default: 300) |
| `ctx.task` | string | **required** | The task requiring long-form output |
