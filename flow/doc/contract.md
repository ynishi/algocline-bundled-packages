# Frame-compatible pkg contract v1 (optional)

`flow` works with every existing bundled pkg as-is — the `flow.token_verify`
call is fail-open, so a pkg that does not echo `_flow_token` / `_flow_slot`
simply gets the boundary verified and no per-call verification.

A pkg author can **opt in** to the v1 contract below to get stricter
verification. Non-opt-in pkg stay fully supported.

## v1 contract

A Frame-compatible pkg MUST satisfy all three:

### 1. Echo `_flow_token` and `_flow_slot` on result

When `ctx._flow_token` and `ctx._flow_slot` are present on the input,
the result table MUST include:

```lua
result._flow_token = ctx._flow_token
result._flow_slot  = ctx._flow_slot
```

When the caller did NOT pass those fields (flow-unaware caller), the pkg
MUST NOT add them to the result.

### 2. Propagate the token into internal LLM calls (recommended)

When the pkg calls `alc.llm` internally for sub-decisions, embed the
token + slot tags into the system or user prompt so the LLM itself
echoes them back — the pkg can then reject mismatched sub-decisions
before they reach the caller.

```lua
local system = opts.system or ""
if ctx._flow_token then
    system = system
        .. "\n[flow_token=" .. ctx._flow_token .. "]"
        .. "[flow_slot=" .. ctx._flow_slot .. "]"
end
```

This is **recommended, not required** — pkg that run multiple internal
LLM calls may not need per-call verification as long as the pkg's own
output reflects the expected token.

### 3. Declare the contract version in meta

```lua
M.meta = {
    name          = "...",
    version       = "...",
    flow_contract = "v1",
    -- ...
}
```

Declaring `flow_contract = "v1"` is how tooling and Frame-aware Recipe
implementations know to treat this pkg as strictly verifiable.

## Non-goals of the contract

- The contract does **not** require the pkg to use `flow` itself, only to
  cooperate with a `flow`-driven caller.
- It does **not** forbid additional fields in either `ctx` or `result`.
- It does **not** specify any behavior for flow-unaware callers — the pkg
  must remain usable as a plain `M.run(ctx)` package.

## Migration sketch

For an existing pkg (e.g. `ab_mcts/init.lua`) the minimum diff is roughly:

```diff
 function M.run(ctx)
     -- ... existing logic ...
     return {
         answer     = best.answer,
         best_score = best.score,
         tree_stats = stats,
+        _flow_token = ctx._flow_token,
+        _flow_slot  = ctx._flow_slot,
     }
 end

 M.meta = {
     name          = "ab_mcts",
     version       = "...",
+    flow_contract = "v1",
     -- ...
 }
```

No behavior change for non-Frame callers; Frame callers get per-call
slot and token verification.
