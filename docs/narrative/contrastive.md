---
name: contrastive
version: 0.1.0
category: reasoning
result_shape: "shape { answer: string, contrasts: array of shape { error_analysis: string, wrong_reasoning: string }, total_contrasts: number }"
description: "Contrastive CoT — generate correct and incorrect reasoning, learn from contrast"
source: contrastive/init.lua
generated: gen_docs (V0)
---

# Contrastive — learn from correct AND incorrect reasoning

> Generates both a correct reasoning path and a plausible-but-wrong path, then contrasts them to strengthen the final answer. The only strategy that explicitly models failure modes.

## Contents

- [Parameters](#parameters)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.n_contrasts` | number | optional | Number of contrast pairs (default: 2) |
| `ctx.task` | string | **required** | The problem to solve |
