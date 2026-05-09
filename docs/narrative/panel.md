---
name: panel
version: 0.1.0
category: synthesis
result_shape: paneled
description: "Multi-perspective deliberation with distinct roles and moderator synthesis."
source: panel/init.lua
generated: gen_docs (V0)
---

# panel(Panel) — multi-perspective deliberation with moderator synthesis

> Multiple roles present positions, each responding to prior arguments, and a moderator synthesizes the final answer from the deliberation.

## Contents

- [Usage](#usage)
- [Result](#result)

## Usage {#usage}

```lua
local panel = require("panel")
return panel.run(ctx)
```

## Result {#result}

Returns `paneled` shape:

| key | type | optional | description |
|---|---|---|---|
| `arguments` | array of shape { role: string, text: string } | — | Per-role position statements |
| `synthesis` | string | — | Moderator synthesis |
