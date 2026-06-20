---@module 'flow.ir.interpreter'
-- Exec stage of the Def→Compile→Exec pipeline.
--
-- Walks a compiled IR. Total responsibility:
--   - eval_expr  : Expr → value
--   - exec_node  : Node → ctx' (in-place mutation under documented keys)
--
-- ## Dispatch injection
--
-- Host dispatch is injected via `opts.dispatch(ref, input)` so the
-- interpreter stays host-neutral. The default stub returns nil and
-- raises on call, which is spec-friendly: tests provide their own
-- recorder; production callers inject their own dispatcher.
--
-- ## Path resolution
--
--   read:  "$.ctx.foo.bar"      → ctx.foo.bar (table walk, missing key → nil)
--   read:  "$.ctx.items[2]"     → ctx.items[2] (1-based; [-1] = last)
--   write: "ctx.foo.bar"        → ctx.foo.bar (intermediate tables auto-created)
--   write: "ctx.items[3]"       → ctx.items[3] (intermediate tables auto-created;
--                                negative index is NOT supported on write)
--
-- Reads are absolute and rooted at ctx (the "$" sigil is required, only
-- the `$.ctx.*` sub-tree is exposed). Writes are relative to ctx and
-- always create missing tables along the path. Index errors / non-table
-- intermediates on reads return nil (silent missing-key); writes through
-- a non-table intermediate are *replaced* with a fresh table.
--
-- Bracket selectors (`[N]`) follow RFC 9535's integer index subset:
-- 1-based, negatives count from the tail on READ (-1 = last). Negative
-- indexes on WRITE raise (no well-defined semantics when the array does
-- not yet exist). Wildcards / slices / filter expressions are out of
-- scope. See `flow.ir.path` for the parser.
--
-- ## Surface
--
-- 7 Node kinds × 8 Expr ops. The schema discriminated + `open = false`
-- guard ensures unknown kind / op never reaches here.

local path_mod = require("flow.ir.path")
local token_mod = require("flow.token")
local state_mod = require("flow.state")
local util_mod  = require("flow.util")

local M = {}

local TOKEN_HEX_BYTES = 32

--- Sentinel raised by `return_early` to unwind to the nearest `M.exec`
--- frame without being absorbed by `try`. Detected by identity (table key).
local RETURN_EARLY_SENTINEL = {}
M._RETURN_EARLY_SENTINEL = RETURN_EARLY_SENTINEL

local function is_return_early(err)
    return type(err) == "table" and err[RETURN_EARLY_SENTINEL] == true
end

-- ── path utils ──────────────────────────────────────────────────────

--- Resolve a `$.ctx.*` read path against the ctx table.
---
--- Walks the segments after `$.ctx`. A non-table intermediate yields
--- nil (missing-key semantics), which lets `eq(path, lit)` test for
--- presence as `eq(path, lit(nil))`. Negative integer segments index
--- from the array tail (`[-1]` = last element); out-of-range negatives
--- yield nil rather than raising.
---
---@param ctx table
---@param at  string  e.g. "$.ctx.verdict" or "$.ctx.items[2]"
---@return any|nil value
---@return string? err  set only on malformed path
local function read_path(ctx, at)
    local parts, parse_err = path_mod.parse(at)
    if not parts then
        return nil, "read_path: " .. tostring(parse_err) .. ": " .. at
    end
    if parts[1] ~= "$" or parts[2] ~= "ctx" then
        return nil, "read_path: only $.ctx.* supported, got " .. at
    end
    local cur = ctx
    for i = 3, #parts do
        if type(cur) ~= "table" then return nil end
        local seg = parts[i]
        if type(seg) == "number" then
            local n = seg
            if n < 0 then
                -- RFC 9535: negative index counts from the end. Use Lua's
                -- `#cur` as the length; out-of-range negative → nil.
                local len = #cur
                if -n > len then return nil end
                n = len + 1 + n
            end
            cur = cur[n]
        else
            cur = cur[seg]
        end
    end
    return cur
end

--- Write `value` into ctx under a `ctx.*` path, auto-creating tables.
---
--- A non-table intermediate is *replaced* with a fresh table (e.g.
--- writing "ctx.a.b" when ctx.a == "string" overwrites ctx.a). Callers
--- are expected to keep ctx well-typed; this is a deliberate choice
--- over a silent failure path.
---
--- Integer index segments (`[N]`) are supported on write and use the
--- integer key directly (so `ctx.items[3] = v` does `ctx.items[3] = v`
--- with intermediate `ctx.items` auto-created as a fresh table when
--- absent). Negative indexes on WRITE raise — "write to the tail of an
--- array that might not exist yet" has no well-defined semantics.
---
---@param ctx   table
---@param at    string  e.g. "ctx.foo.bar" or "ctx.items[3]"
---@param value any
local function write_path(ctx, at, value)
    local parts, parse_err = path_mod.parse(at)
    if not parts then
        error("write_path: " .. tostring(parse_err) .. ": " .. at, 2)
    end
    if parts[1] ~= "ctx" then
        error("write_path: only ctx.* supported, got " .. at, 2)
    end
    local cur = ctx
    for i = 2, #parts - 1 do
        local k = parts[i]
        if type(k) == "number" and k < 0 then
            error("write_path: negative index not supported on write: " .. at, 2)
        end
        if type(cur[k]) ~= "table" then cur[k] = {} end
        cur = cur[k]
    end
    local last = parts[#parts]
    if type(last) == "number" and last < 0 then
        error("write_path: negative index not supported on write: " .. at, 2)
    end
    cur[last] = value
end

-- ── Expr eval ───────────────────────────────────────────────────────

--- Evaluate an Expr against ctx.
---
--- `path` returns the value at the JSONPath-ish ref (or nil).
--- `lit` returns the literal value as-is.
--- `eq` returns boolean (Lua `==` semantics; nil == nil is true).
--- `and` returns boolean (short-circuit; true iff every arg is truthy).
--- `not` returns boolean (truthiness inversion).
--- `lt` returns boolean (Lua `<` semantics; numeric for numbers,
---     lexicographic for strings, raises on mixed/unordered types).
--- `or` returns boolean (short-circuit; true on first truthy arg,
---     false if every arg is non-truthy).
--- `len` returns integer (Lua `#` semantics; works on strings and
---     sequence-style arrays; raises on values without a length op).
---
---@param expr flow.ir.Expr
---@param ctx  table
---@return any
local function eval_expr(expr, ctx, env)
    local op = expr.op
    if op == "lit" then
        return expr.value
    elseif op == "path" then
        local v, err = read_path(ctx, expr.at)
        if err then error(err, 2) end
        return v
    elseif op == "var" then
        if env == nil then
            error("eval_expr: var '" .. expr.name .. "' has no enclosing binding env", 2)
        end
        return env[expr.name]
    elseif op == "eq" then
        return eval_expr(expr.lhs, ctx, env) == eval_expr(expr.rhs, ctx, env)
    elseif op == "and" then
        for _, sub in ipairs(expr.args) do
            if not eval_expr(sub, ctx, env) then return false end
        end
        return true
    elseif op == "not" then
        return not eval_expr(expr.arg, ctx, env)
    elseif op == "lt" then
        return eval_expr(expr.lhs, ctx, env) < eval_expr(expr.rhs, ctx, env)
    elseif op == "or" then
        for _, sub in ipairs(expr.args) do
            if eval_expr(sub, ctx, env) then return true end
        end
        return false
    elseif op == "len" then
        return #eval_expr(expr.arg, ctx, env)
    elseif op == "concat" then
        local parts = {}
        for i, sub in ipairs(expr.args) do
            local v = eval_expr(sub, ctx, env)
            if type(v) ~= "string" then
                error(
                    "eval_expr: concat arg[" .. i .. "] must be a string, got "
                        .. type(v) .. " (no implicit tostring coercion)", 2)
            end
            parts[i] = v
        end
        return table.concat(parts)
    elseif op == "add" then
        local lhs = eval_expr(expr.lhs, ctx, env)
        local rhs = eval_expr(expr.rhs, ctx, env)
        if type(lhs) ~= "number" then
            error("eval_expr: add.lhs must be a number, got " .. type(lhs), 2)
        end
        if type(rhs) ~= "number" then
            error("eval_expr: add.rhs must be a number, got " .. type(rhs), 2)
        end
        return lhs + rhs
    elseif op == "get" then
        local from = eval_expr(expr.from, ctx, env)
        if type(from) ~= "table" then
            error("eval_expr: get.from must be a table, got " .. type(from), 2)
        end
        local key = eval_expr(expr.key, ctx, env)
        local kt = type(key)
        if kt ~= "string" and kt ~= "number" then
            error("eval_expr: get.key must be a string or number, got " .. kt, 2)
        end
        return from[key]
    elseif op == "sub" or op == "mul" or op == "div" or op == "mod" then
        local lhs = eval_expr(expr.lhs, ctx, env)
        local rhs = eval_expr(expr.rhs, ctx, env)
        if type(lhs) ~= "number" then
            error("eval_expr: " .. op .. ".lhs must be a number, got " .. type(lhs), 2)
        end
        if type(rhs) ~= "number" then
            error("eval_expr: " .. op .. ".rhs must be a number, got " .. type(rhs), 2)
        end
        if (op == "div" or op == "mod") and rhs == 0 then
            error("eval_expr: " .. op .. ".rhs must be non-zero", 2)
        end
        if op == "sub" then return lhs - rhs
        elseif op == "mul" then return lhs * rhs
        elseif op == "div" then return lhs / rhs
        else return lhs % rhs end
    elseif op == "gt" then
        return eval_expr(expr.lhs, ctx, env) > eval_expr(expr.rhs, ctx, env)
    elseif op == "gte" then
        return eval_expr(expr.lhs, ctx, env) >= eval_expr(expr.rhs, ctx, env)
    elseif op == "lte" then
        return eval_expr(expr.lhs, ctx, env) <= eval_expr(expr.rhs, ctx, env)
    elseif op == "ne" then
        return eval_expr(expr.lhs, ctx, env) ~= eval_expr(expr.rhs, ctx, env)
    elseif op == "exists" then
        return eval_expr(expr.arg, ctx, env) ~= nil
    elseif op == "format" then
        local fmt = eval_expr(expr.fmt, ctx, env)
        if type(fmt) ~= "string" then
            error("eval_expr: format.fmt must be a string, got " .. type(fmt), 2)
        end
        local args = {}
        for i, sub in ipairs(expr.args) do
            args[i] = eval_expr(sub, ctx, env)
        end
        return string.format(fmt, table.unpack(args))
    elseif op == "filter" then
        local from = eval_expr(expr.from, ctx, env)
        if type(from) ~= "table" then
            error("eval_expr: filter.from must be an array, got " .. type(from), 2)
        end
        local results = {}
        local inner_env = {}
        if env then for k, v in pairs(env) do inner_env[k] = v end end
        for _, item in ipairs(from) do
            inner_env[expr.var] = item
            if eval_expr(expr.pred, ctx, inner_env) then
                results[#results + 1] = item
            end
        end
        return results
    elseif op == "fold" then
        local from = eval_expr(expr.from, ctx, env)
        if type(from) ~= "table" then
            error("eval_expr: fold.from must be an array, got " .. type(from), 2)
        end
        local acc = eval_expr(expr.init, ctx, env)
        local inner_env = {}
        if env then for k, v in pairs(env) do inner_env[k] = v end end
        for _, item in ipairs(from) do
            inner_env[expr.acc_var]  = acc
            inner_env[expr.item_var] = item
            acc = eval_expr(expr.fn, ctx, inner_env)
        end
        return acc
    end
    error("eval_expr: unknown op " .. tostring(op), 2)
end

-- ── stub dispatch ───────────────────────────────────────────────────

--- Spec-friendly default: returns nil and a "no dispatch configured" reason.
---
--- The interpreter treats `(nil, reason)` from dispatch as a fatal error
--- when invoked via the default; spec runs always inject their own
--- recorder via `opts.dispatch`, and production callers inject their own
--- dispatcher.
---
---@param ref string
---@param _input any
---@return nil
---@return string reason
local function default_dispatch(ref, _input)
    return nil, "default_dispatch: no dispatch configured for " .. ref
end

-- ── Node exec ───────────────────────────────────────────────────────

--- Execute one Node against ctx (in-place mutation).
---
--- `step`   evaluates `in_` (if present), calls opts.dispatch(ref, in),
---          writes the result to ctx[out].
--- `seq`    walks children in order.
--- `branch` evaluates cond, dispatches to then_ / else_ by truthiness.
--- `let`    evaluates `value` against ctx and binds the result to ctx[at]
---          (pure value bind; no host call).
--- `loop`   while-loop with hard `max` cap; writes 0 to `counter` before
---          entering, then increments and writes before each iteration.
---          `cond` is evaluated before each iteration; on exit the
---          counter retains the count of completed iterations.
--- `call`   looks up `opts.flows[flow]`, builds a fresh sub-ctx by
---          evaluating each `args[k]` against the caller's ctx, executes
---          the sub-flow against sub-ctx, then writes the full sub-ctx
---          to caller's ctx[out]. Recursion is bounded by
---          `opts.max_call_depth` (default 64).
--- `fanout` evaluates `items` to an array, runs `body` per item against
---          a branch-local ctx (shallow copy of caller's ctx + `bind`
---          written to the item), and writes the joined result to
---          ctx[out]. `join` ∈ {"all", "any", "race", "all_settled"}:
---            `all` — every branch runs; out is an array of per-branch
---                    final ctx tables (Promise.all / try_join_all).
---            `any` — branches run in order; first non-raising branch's
---                    final ctx is out; all-fail raises; empty items
---                    yields out = {} (Promise.any / select_ok).
---            `race` — first branch to settle wins, success OR raise:
---                    runs items in order until one completes; serial
---                    fallback always settles item[1] first, so out is
---                    item[1]'s ctx on success or item[1]'s error is
---                    re-raised on failure (Promise.race /
---                    select_all-first). Empty items yields out = {}.
---            `all_settled` — every branch runs, NEVER raises; out is
---                    an array of per-item records:
---                      { status = "fulfilled", value  = <branch ctx> }
---                      { status = "rejected",  reason = <error string> }
---                    (Promise.allSettled / join_all). Empty items
---                    yields out = {}.
---          The MVP interpreter is serial; `opts.scheduler` is a
---          reserved forward-compat slot for a future concurrent
---          scheduler (no-op when nil).
---          Note: in `any` / `race`, the identity of the winning
---          branch is iteration-order-dependent under the serial
---          fallback; a concurrent scheduler may select differently.
---          Flows should not depend on which branch wins — only on
---          the sub-ctx contents.
---
--- Errors raise (`error(... , 2)`) rather than returning nil-reason; the
--- caller (`M.exec`) treats Node exec as transactional from the caller's
--- POV (no partial ctx repair on error). Callers wanting recovery should
--- pcall around `M.exec`.
---
---@param node flow.ir.Node
---@param ctx  table
---@param opts flow.ir.ExecOpts  guaranteed populated by M.exec
---@return table ctx
local function exec_node(node, ctx, opts)
    local kind = node.kind
    if kind == "step" then
        local input = nil
        if node.in_ then input = eval_expr(node.in_, ctx) end
        local result, derr = opts.dispatch(node.ref, input)
        if derr and result == nil then
            error("exec: step '" .. node.ref .. "': " .. derr, 2)
        end
        write_path(ctx, node.out, result)
    elseif kind == "seq" then
        for _, child in ipairs(node.children) do
            exec_node(child, ctx, opts)
        end
    elseif kind == "branch" then
        local cond_val = eval_expr(node.cond, ctx)
        if cond_val then
            exec_node(node.then_, ctx, opts)
        elseif node.else_ ~= nil then
            exec_node(node.else_, ctx, opts)
        end
    elseif kind == "let" then
        write_path(ctx, node.at, eval_expr(node.value, ctx))
    elseif kind == "loop" then
        write_path(ctx, node.counter, 0)
        local n = 0
        while n < node.max and eval_expr(node.cond, ctx) do
            n = n + 1
            write_path(ctx, node.counter, n)
            exec_node(node.body, ctx, opts)
        end
    elseif kind == "call" then
        if opts._call_depth >= opts.max_call_depth then
            error("exec: call: max_call_depth (" .. opts.max_call_depth .. ") exceeded", 2)
        end
        local sub_flow = (opts.flows or {})[node.flow]
        if sub_flow == nil then
            error("exec: call: flow '" .. node.flow .. "' not registered in opts.flows", 2)
        end
        local sub_ctx = {}
        for k, expr in pairs(node.args) do
            sub_ctx[k] = eval_expr(expr, ctx)
        end
        opts._call_depth = opts._call_depth + 1
        exec_node(sub_flow, sub_ctx, opts)
        opts._call_depth = opts._call_depth - 1
        write_path(ctx, node.out, sub_ctx)
    elseif kind == "fanout" then
        local items = eval_expr(node.items, ctx)
        if type(items) ~= "table" then
            error("exec: fanout.items: expected array, got " .. type(items), 2)
        end
        if node.join == "all" then
            local results = {}
            for i, item in ipairs(items) do
                local branch_ctx = {}
                for k, v in pairs(ctx) do branch_ctx[k] = v end
                write_path(branch_ctx, node.bind, item)
                exec_node(node.body, branch_ctx, opts)
                results[i] = branch_ctx
            end
            write_path(ctx, node.out, results)
        elseif node.join == "any" then
            -- first non-raising branch wins; empty items → {}; all-fail raises
            local winner, last_err
            for _, item in ipairs(items) do
                local branch_ctx = {}
                for k, v in pairs(ctx) do branch_ctx[k] = v end
                write_path(branch_ctx, node.bind, item)
                local ok, ex_err = pcall(exec_node, node.body, branch_ctx, opts)
                if ok then
                    winner = branch_ctx
                    last_err = nil
                    break
                else
                    last_err = ex_err
                end
            end
            if last_err then
                error("exec: fanout(any): all branches failed; last error: "
                    .. tostring(last_err), 2)
            end
            write_path(ctx, node.out, winner or {})
        elseif node.join == "race" then
            -- first branch to settle wins (success OR raise). In the serial
            -- fallback the first item always settles first; out is item[1]'s
            -- branch ctx on success, item[1]'s error is re-raised on
            -- failure. Empty items yields out = {}.
            if #items == 0 then
                write_path(ctx, node.out, {})
            else
                local first_item = items[1]
                local branch_ctx = {}
                for k, v in pairs(ctx) do branch_ctx[k] = v end
                write_path(branch_ctx, node.bind, first_item)
                local ok, ex_err = pcall(exec_node, node.body, branch_ctx, opts)
                if not ok then
                    error("exec: fanout(race): first settled branch failed: "
                        .. tostring(ex_err), 2)
                end
                write_path(ctx, node.out, branch_ctx)
            end
        else
            -- join == "all_settled": every branch runs; failures are caught
            -- and recorded as { status="rejected", reason=<msg> } records;
            -- successful branches yield { status="fulfilled", value=<ctx> }.
            local results = {}
            for i, item in ipairs(items) do
                local branch_ctx = {}
                for k, v in pairs(ctx) do branch_ctx[k] = v end
                write_path(branch_ctx, node.bind, item)
                local ok, ex_err = pcall(exec_node, node.body, branch_ctx, opts)
                if ok then
                    results[i] = { status = "fulfilled", value = branch_ctx }
                else
                    results[i] = { status = "rejected", reason = tostring(ex_err) }
                end
            end
            write_path(ctx, node.out, results)
        end
    elseif kind == "switch" then
        local on_val = eval_expr(node.on, ctx)
        local matched = false
        for _, c in ipairs(node.cases) do
            if eval_expr(c.match, ctx) == on_val then
                exec_node(c.body, ctx, opts)
                matched = true
                break
            end
        end
        if not matched and node.else_ ~= nil then
            exec_node(node.else_, ctx, opts)
        end
    elseif kind == "try" then
        local ok, ex_err = pcall(exec_node, node.body, ctx, opts)
        if not ok then
            -- Don't swallow return_early — it must unwind to M.exec.
            if is_return_early(ex_err) then error(ex_err, 0) end
            if node.err_at ~= nil then
                write_path(ctx, node.err_at, tostring(ex_err))
            end
            exec_node(node.catch, ctx, opts)
        end
    elseif kind == "return_early" then
        if node.value ~= nil then
            write_path(ctx, node.out, eval_expr(node.value, ctx))
        end
        error({ [RETURN_EARLY_SENTINEL] = true }, 0)
    elseif kind == "map" then
        local items = eval_expr(node.in_, ctx)
        if type(items) ~= "table" then
            error("exec: map.in_: expected array, got " .. type(items), 2)
        end
        local results = {}
        for i, item in ipairs(items) do
            write_path(ctx, node.bind, item)
            exec_node(node.body, ctx, opts)
            local v, perr = read_path(ctx, "$." .. node.collect)
            if perr then error(perr, 2) end
            results[i] = v
        end
        write_path(ctx, node.out, results)
    elseif kind == "reduce" then
        local items = eval_expr(node.in_, ctx)
        if type(items) ~= "table" then
            error("exec: reduce.in_: expected array, got " .. type(items), 2)
        end
        write_path(ctx, node.acc, eval_expr(node.init, ctx))
        for _, item in ipairs(items) do
            write_path(ctx, node.bind, item)
            exec_node(node.body, ctx, opts)
        end
        local v, perr = read_path(ctx, "$." .. node.acc)
        if perr then error(perr, 2) end
        write_path(ctx, node.out, v)
    elseif kind == "fail" then
        local msg = eval_expr(node.message, ctx)
        if type(msg) ~= "string" then
            error("exec: fail.message must eval to a string, got " .. type(msg), 2)
        end
        error("exec: fail: " .. msg, 2)
    elseif kind == "assert" then
        local cond = eval_expr(node.cond, ctx)
        if not cond then
            local msg = eval_expr(node.message, ctx)
            if type(msg) ~= "string" then
                error("exec: assert.message must eval to a string, got " .. type(msg), 2)
            end
            error("exec: assert: " .. msg, 2)
        end
    elseif kind == "once" then
        -- Resume guard: read ctx at $.<node.flag>. If truthy, skip body;
        -- otherwise run body and set flag = true on completion. Persistence
        -- across sessions is the caller's responsibility (e.g. by holding
        -- the flag under a FlowState data subtree and saving after exec).
        local read_at = "$." .. node.flag
        local cur, perr = read_path(ctx, read_at)
        if perr then error(perr, 2) end
        if not cur then
            exec_node(node.body, ctx, opts)
            write_path(ctx, node.flag, true)
        end
    elseif kind == "wrap_step" then
        -- Evaluate slot Expr to a non-empty string.
        local slot = eval_expr(node.slot, ctx)
        if type(slot) ~= "string" or slot == "" then
            error("exec: wrap_step.slot must eval to a non-empty string, got "
                .. type(slot), 2)
        end
        -- Evaluate input payload (or nil).
        local input = nil
        if node.in_ then input = eval_expr(node.in_, ctx) end
        if input ~= nil and type(input) ~= "table" then
            error("exec: wrap_step '" .. slot .. "': in_ must eval to a table or nil, "
                .. "got " .. type(input), 2)
        end

        -- Issue + wrap. Bound variant requires opts.state.
        local req
        if node.bound then
            local st = opts.state
            if type(st) ~= "table" then
                error("exec: wrap_step '" .. slot .. "': bound=true requires "
                    .. "opts.state (FlowState) to be provided", 2)
            end
            req = token_mod.wrap_bound(st, { slot = slot, payload = input })
        else
            local tok
            if opts.state then
                tok = token_mod.issue(opts.state)
            else
                -- Stateless variant: synthesize an ephemeral token. The
                -- echo contract still works (dispatch sees _flow_token /
                -- _flow_slot in the payload), and verify checks equality
                -- against req._expect_token.
                tok = { value = util_mod.random_hex(TOKEN_HEX_BYTES) }
            end
            req = token_mod.wrap(tok, { slot = slot, payload = input })
        end

        -- Dispatch.
        local result, derr = opts.dispatch(node.ref, req.payload)
        if derr and result == nil then
            error("exec: wrap_step '" .. slot .. "' (ref '" .. node.ref .. "'): "
                .. derr, 2)
        end

        -- Verify (fail-open on missing echo).
        local ok
        if node.bound then
            ok = token_mod.verify_bound(opts.state, slot, result)
        else
            ok = token_mod.verify(nil, result, req)
        end

        if not ok then
            if node.on_mismatch ~= nil then
                -- Surface verify result for the fallback Node before
                -- handing control off.
                write_path(ctx, node.out, result)
                exec_node(node.on_mismatch, ctx, opts)
            else
                error("exec: wrap_step '" .. slot .. "': token/slot mismatch "
                    .. "(set on_mismatch to handle, or check pkg echo contract)", 2)
            end
        else
            write_path(ctx, node.out, result)
        end
    else
        error("exec: unknown kind " .. tostring(kind), 2)
    end
    return ctx
end

---@class flow.ir.ExecOpts
---@field dispatch       fun(ref: string, input: any): any, string?
---@field flows          table<string, flow.ir.Node>?  registry for `call.flow`
---@field max_call_depth integer?  recursion cap for `call` (default 64)
---@field state          table?  optional FlowState. When present, `wrap_step`
---                              issues / persists tokens via this state. Required
---                              when any `wrap_step` Node has `bound = true`.
---@field scheduler      any?  reserved forward-compat slot for concurrent
---                           fanout schedulers; the MVP interpreter is
---                           serial and ignores this field.

--- Execute a compiled IR.
---
--- Mutates `ctx` in place and also returns it (convenient one-liner usage
--- `local ctx = flow.ir.exec(ir, {}, { dispatch = ... })`).
--- Errors raise via `error()` — callers wanting recovery should pcall.
---
--- `opts.flows` must include every name referenced by a `call` Node in
--- the IR (compile can validate eagerly via `compile.opts.flows`).
--- `opts.max_call_depth` caps `call` recursion at 64 by default.
---
---@param compiled flow.ir.Node  IR validated by flow.ir.compile
---@param ctx      table         initial ctx (mutated in place)
---@param opts     flow.ir.ExecOpts?
---@return table ctx
function M.exec(compiled, ctx, opts)
    opts = opts or {}
    opts.dispatch = opts.dispatch or default_dispatch
    opts.max_call_depth = opts.max_call_depth or 64
    opts._call_depth = 0
    local ok, ex_err = pcall(exec_node, compiled, ctx, opts)
    if not ok then
        if is_return_early(ex_err) then return ctx end
        error(ex_err, 0)
    end
    return ctx
end

--- Public default dispatch helper.
---
--- Exposed so callers (test harnesses, host wrappers) can compose with
--- it, e.g. fall back to it for unknown refs:
---
---   opts.dispatch = function(ref, input)
---       if my_dispatcher[ref] then return my_dispatcher[ref](input) end
---       return flow.ir.default_dispatch(ref, input)  -- raise on unknown
---   end
M.default_dispatch = default_dispatch

-- Exported for spec; not part of the public API contract.
M._eval_expr  = eval_expr
M._read_path  = read_path
M._write_path = write_path

return M
