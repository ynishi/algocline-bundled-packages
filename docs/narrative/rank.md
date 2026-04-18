---
name: rank
version: 0.1.0
category: selection
result_shape: tournament
description: "Tournament selection — generate candidates, pairwise LLM-as-Judge ranking"
source: rank/init.lua
generated: gen_docs (V0)
---

# Rank — generate candidates and select best via pairwise comparison

> Generates N candidate responses, then uses LLM-as-Judge to perform pairwise tournament selection. Produces a winner with reasoning.

## Contents

- [Result](#result)

## Result {#result}

Returns `tournament` shape:

| key | type | optional | description |
|---|---|---|---|
| `best` | string | — | Winner text |
| `best_index` | number | — | Winner original index (1-based) |
| `candidates` | array of string | — | Input candidate texts |
| `matches` | array of shape { a: number, b: number, reason: string, winner: number } | — | Pairwise match log |
| `total_wins` | number | — | Winner's win count |
