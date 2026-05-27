---
name: recipe_trace
version: 0.1.0
category: adapter
description: "Generic LLM call tracer for recipe execution. Wraps alc.llm to collect per-call prompt/response/timing without modifying the recipe itself."
source: recipe_trace/init.lua
generated: gen_docs (V0)
---

# recipe_trace — generic LLM call tracer for recipe execution

> Wraps `alc.llm` before running a recipe, collects per-call trace entries (prompt, response, duration, opts), then restores the original function. The recipe itself is not modified — tracing is fully external.

## Contents

- [Usage](#usage)
- [Caveats](#caveats)

## Usage {#usage}

```lua
local trace = require("recipe_trace")
local recipe = require("recipe_quick_vote")
local result = trace.run({
    task = "What is 2+2?",
    recipe = recipe,
    -- all other fields forwarded to recipe.run as-is
})
-- result.trace = { calls = { {prompt, response, opts, duration_ms}, ... } }
```

## Caveats {#caveats}

The wrapper replaces `alc.llm` on the global `alc` table for the
duration of recipe.run. Recipes that capture `alc.llm` into a local
at load time bypass the hook — all 5 current recipe_* packages call
`alc.llm(...)` directly, so this is safe today. If a future recipe
caches the reference, the hook will miss those calls.

Trace data lives in `ctx.result.trace` alongside the recipe's own
result fields. The trace table is additive — it never overwrites
recipe output keys.
