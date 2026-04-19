# flow — Light Frame for composing algo-based pkg

Two primitives (FlowState + ReqToken) over `alc.state`, nothing more.
`flow` is a **substrate**, not an orchestrator: it does not provide `M.run`,
and the driver loop stays in user code (Functional Core / Imperative Shell).

```lua
local flow = require("flow")

local st  = flow.state_new({ key_prefix = "my_run", id = task_id, resume = true })
local tok = flow.token_issue(st)

if not flow.state_get(st, "gate_ok") then
    local req = flow.token_wrap(tok, { slot = "gate", payload = { q = task } })
    local out = orch_gatephase.run(req.payload)
    assert(flow.token_verify(tok, out, req), "gate: token/slot mismatch")
    flow.state_set(st, "gate_ok", true)
    flow.state_save(st)
end
```

## When to use flow

Use `flow` when you want to compose **multiple bundled algo pkg** (ab_mcts /
cascade / coevolve / orch_gatephase / ...) with:

- one persistent checkpoint across all pkg calls
- slot-level guarantees that a result came back from the right call site
- resumable progression across sessions
- no Agent-boundary abstraction

Do **not** use `flow` for:

- a single pkg call (use the pkg directly)
- pure computation pipelines without state (use plain Lua)
- workflows that need a managed driver loop (use an orchestrator pkg such as
  `orch_gatephase` — `flow` deliberately omits one)

## Primitives

### FlowState

A plain Lua table persisted to `alc.state` under
`key_prefix .. ":" .. id`. No metatable, no inheritance.

| API | behavior |
|---|---|
| `flow.state_new({ key_prefix, id, identity?, resume? })` | Create or restore. When `resume=true`, `data` and the internal token value are loaded from the persisted record. `identity` always comes from `opts` (never overwritten by the persisted record) **and, since v0.2.0, is compared by structural equality against the persisted `identity` on resume — a mismatch raises an error**. Legacy checkpoints written by flow 0.1.0 (no persisted `identity` field) are accepted with an `alc.log("warn", ...)` message for backward compatibility. |
| `flow.state_key(state)` | Returns `key_prefix .. ":" .. id`. |
| `flow.state_get(state, k)` | Read `state.data[k]`. |
| `flow.state_set(state, k, v)` | Write `state.data[k]`. Does NOT persist. |
| `flow.state_save(state)` | Persist `data`, `identity`, and internal token via `alc.state.set`. |

**Invariant**: only `alc.state` is used for persistence; `flow` never
requires new primitives from the runtime.

### ReqToken

A random nonce issued per Flow and echoed by downstream pkg results.
The pattern is analogous to AMQP's `correlation_id` RPC idiom: the caller
generates a nonce, sends it with the request, and accepts the reply only
when it echoes the same nonce.

| API | behavior |
|---|---|
| `flow.token_issue(state)` | Issue a new token (or restore the existing one on resume) and persist it. Returns `{ value, _state_key }`. |
| `flow.token_wrap(token, { slot, payload? })` | Embed `_flow_token` / `_flow_slot` into `payload`; return `{ slot, payload, _expect_token, _expect_slot }`. The caller's payload table is NOT mutated. |
| `flow.token_verify(token, result, req)` | Returns `true` when `result` either omits echo fields (fail-open) or echoes the expected token+slot. Returns `false` only when echoed values are PRESENT and MISMATCHED. |

**Fail-open rationale**: bundled pkg do not echo tokens today, and requiring
them to would break the "no existing pkg rewrite" property. Pkg authors
opt into the stricter v1 contract (see `contract.md`) to get per-call
verification; non-opt-in pkg still verify at the Frame boundary.

### flow.llm (sugar for direct LLM calls)

```lua
local out = flow.llm({
    token = tok,
    slot  = "classify",
    prompt = "...",
    llm_opts = { system = "...", max_tokens = 512 },
})
```

Embeds `[flow_token=...][flow_slot=...]` into the prompt, then checks for
the echoed tags in the response. Fail-open when no tags are present;
`error()` when tags are present but mismatched.

**Note** — as of 2026-04-19, `alc.llm`
(`crates/algocline-engine/src/bridge/llm.rs`) does not expose
structured output (response_format / tool_use). When that capability
lands upstream, a stricter `flow.llm({..., strict = true})` variant
can be added on top.

## Canonical patterns

### 1. Phase gate (state_get / state_set around a pkg call)

```lua
if not flow.state_get(st, "phase_ok") then
    local req = flow.token_wrap(tok, { slot = "phase", payload = {...} })
    local out = somepkg.run(req.payload)
    assert(flow.token_verify(tok, out, req), "phase: token/slot mismatch")
    flow.state_set(st, "phase_ok", true)
    flow.state_save(st)
end
```

Six visible lines. Deliberately not hidden behind a helper — the
save-on-success semantics and the "what happens on failure" path are
explicit at the call site.

### 2. Fan-out (nested value with per-branch flag)

```lua
local branches = flow.state_get(st, "branches") or {}
for i, approach in ipairs(approaches) do
    local bkey = "branch_" .. i
    if not branches[bkey] then
        local req = flow.token_wrap(tok, { slot = bkey, payload = {...} })
        local out = ab_mcts.run(req.payload)
        assert(flow.token_verify(tok, out, req), bkey .. ": token/slot mismatch")
        branches[bkey] = { answer = out.answer, ... }
        flow.state_set(st, "branches", branches)
        flow.state_save(st)
    end
end
```

Note that `flow.state_set("branches", branches)` is not an atomic
partial-update against a concurrent writer — it replaces the whole
`branches` value on each `save`. `flow` v0.1 assumes one driver.

## API surface summary

```
flow.state_new / state_key / state_get / state_set / state_save
flow.token_issue / token_wrap / token_verify
flow.llm
flow.meta
```

`flow.run` is intentionally absent.

## References

- `flow/doc/contract.md` — optional Frame-compatible pkg contract v1
- `tests/flow/test_integ_gate_scale.lua` — 5-gate Coding-pipeline scale example
- `tests/flow/test_integ_swarm_mcts.lua` — fan-out + consensus + commit
- `tests/flow/test_integ_ensemble_vote.lua` — bare flow.llm × N + pure-compute chain
- `recipe_deep_panel/` — production Recipe that composes ab_mcts × N + ensemble_div + condorcet + calibrate on top of flow
- `workspace/tasks/flow-frame/design-full.md` — design record
- `workspace/tasks/flow-frame/bp-research.md` — Lua / substrate BP research
