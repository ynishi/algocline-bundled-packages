---
name: panel
version: 0.1.0
category: synthesis
result_shape: paneled
description: "Multi-perspective deliberation — distinct roles engage, moderator synthesizes"
source: panel/init.lua
generated: gen_docs (V0)
---

# Panel — multi-perspective deliberation

> Multiple roles present positions responding to prior arguments, then a moderator synthesizes.

## Contents

- [Result](#result)

## Result {#result}

Returns `paneled` shape:

| key | type | optional | description |
|---|---|---|---|
| `arguments` | array of shape { role: string, text: string } | — | Per-role position statements |
| `synthesis` | string | — | Moderator synthesis |
