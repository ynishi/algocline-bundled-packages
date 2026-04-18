---
name: bot
version: 0.1.0
category: reasoning
result_shape: "shape { answer: string, errors_found: boolean, instantiated_reasoning: string, template_key: string, template_name: string, template_pattern: string, verification: string }"
description: "Buffer of Thoughts — identify problem type, apply thought template, verify"
source: bot/init.lua
generated: gen_docs (V0)
---

# bot — Buffer of Thoughts: template-based meta-reasoning

> Identifies the problem type, retrieves an appropriate thought template (structured reasoning pattern), instantiates it for the specific problem, then verifies the result. Efficient because it leverages pre-defined reasoning patterns rather than discovering them from scratch each time.

## Contents

- [Parameters](#parameters)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.gen_tokens` | number | optional | Max tokens per instantiate / verify step (default 500) |
| `ctx.task` | string | **required** | Problem to solve (required) |
| `ctx.templates` | map of string to shape { name: string, pattern: string } | optional | Custom template_key → {name, pattern} map; defaults to built-in TEMPLATES |
