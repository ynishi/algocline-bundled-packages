---
name: coa
version: 0.1.0
category: reasoning
result_shape: "shape { abstract_chain: string, answer: string, grounded_chain: string, groundings: array of shape { depth: number, query: string, result: string, tool: string, var: string }, placeholders_resolved: number, tools_used: map of string to string }"
description: "Chain-of-Abstraction — reason with abstract placeholders, then ground via parallel knowledge resolution. Decouples reasoning structure from concrete facts."
source: coa/init.lua
generated: gen_docs (V0)
---

# coa — Chain-of-Abstraction reasoning

> Generates reasoning chains with abstract placeholders instead of concrete facts, then grounds them via parallel knowledge lookups. Decouples the reasoning structure from specific knowledge, enabling parallel tool calls and cleaner reasoning chains.

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.gen_tokens` | number | optional | Max tokens for the abstract chain and final answer (default 600) |
| `ctx.ground_tokens` | number | optional | Max tokens per grounding call (default 300) |
| `ctx.max_depth` | number | optional | Max dependency-resolution depth (default 3) |
| `ctx.task` | string | **required** | Problem to solve (required) |
| `ctx.tools` | map of string to string | optional | tool_name → description; defaults to a single 'knowledge' tool |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `abstract_chain` | string | — | Raw abstract chain with [FUNC tool("query") = yN] placeholders |
| `answer` | string | — | Final answer produced from the grounded chain |
| `grounded_chain` | string | — | Chain after placeholder substitution |
| `groundings` | array of shape { depth: number, query: string, result: string, tool: string, var: string } | — | Per-placeholder resolution trace in resolution order |
| `placeholders_resolved` | number | — | Count of placeholders actually resolved |
| `tools_used` | map of string to string | — | Echo of the tools map used for this run |
