---@module 'flow.llm'
-- Bare LLM call helper with slot + token tag echo.
--
-- alc.llm (crates/algocline-engine/src/bridge/llm.rs as of 2026-04-19)
-- does not expose structured output (response_format / tool_use).
-- We therefore embed `[flow_token=...][flow_slot=...]` into the prompt
-- and verify echo via regex on the returned string. If the LLM omits
-- the tags, we treat the call as unverified (fail-open): the error is
-- raised only when the echoed tag is PRESENT and MISMATCHED.

local util  = require("flow.util")
local token = require("flow.token")
local state = require("flow.state")

local M = {}

--- Append the flow verification tags to a prompt. Private helper kept
--- here so that `llm` and `llm_bound` cannot drift on tag shape — the
--- exact byte-pattern is what `util.parse_tag` matches on the echo
--- side, and a rename on one caller without the other would silently
--- turn every call into a fail-open pass.
---@param prompt string
---@param token_value string
---@param slot string
---@return string
local function append_flow_tags(prompt, token_value, slot)
    return prompt
        .. "\n\n[flow_token=" .. token_value .. "]"
        .. "[flow_slot=" .. slot .. "]"
end

--- Issue a bare LLM call tied to a slot + token.
--- `opts = { token = { value = ... }, slot = string, prompt = string, llm_opts = table? }`
--- Passes `llm_opts` straight through to `alc.llm` (system / max_tokens / etc).
--- Returns whatever `alc.llm` returned (typically a string).
---@param opts { token: { value: string }, slot: string, prompt: string, llm_opts: table? }
---@return any
function M.llm(opts)
    assert(type(opts) == "table", "flow.llm: opts must be a table")
    assert(type(opts.token) == "table" and type(opts.token.value) == "string",
        "flow.llm: opts.token.value must be a string")
    assert(type(opts.slot) == "string" and opts.slot ~= "",
        "flow.llm: opts.slot must be a non-empty string")
    assert(type(opts.prompt) == "string",
        "flow.llm: opts.prompt must be a string")
    assert(type(alc) == "table" and type(alc.llm) == "function",
        "flow.llm: alc.llm is not available")

    local tagged_prompt = append_flow_tags(opts.prompt, opts.token.value, opts.slot)

    local out = alc.llm(tagged_prompt, opts.llm_opts)

    if type(out) == "string" then
        local echoed_token = util.parse_tag(out, "flow_token")
        local echoed_slot  = util.parse_tag(out, "flow_slot")
        if echoed_token and echoed_token ~= opts.token.value then
            error("flow.llm: token mismatch (got " .. echoed_token
                .. ", expected " .. opts.token.value .. ")")
        end
        if echoed_slot and echoed_slot ~= opts.slot then
            error("flow.llm: slot mismatch (got " .. echoed_slot
                .. ", expected " .. opts.slot .. ")")
        end
    end

    return out
end

-- ---------------------------------------------------------------------
-- Session-spanning bound API
-- ---------------------------------------------------------------------
-- `llm_bound` is the state-bound counterpart of `llm`: it issues a
-- token against `st`, persists the verify-side req under
-- `state.data._flow_req_<slot>` BEFORE calling alc.llm, and on return
-- either:
--   * success (match or fail-open echo)   → auto-deletes `_flow_req_<slot>`
--   * token / slot mismatch on echo       → auto-rollback (delete) + error
--
-- The pre-call persist means that a mid-call alc.llm yield or a full
-- session crash leaves a detectable record on resume. The post-call
-- auto-delete keeps `state.data` clean when the happy path terminates.
-- Error-on-mismatch (rather than bool) inherits `flow.llm` semantics:
-- a present-but-wrong echo is a hard fail, not a recoverable condition.
--
-- Persist shape (intentionally asymmetric with `wrap_bound`):
--   llm_bound   → { slot, _expect_token, _expect_slot }      (no prompt/payload)
--   wrap_bound  → { slot, payload, _expect_token, _expect_slot }  (full req)
-- Callers probing `state.data._flow_req_<slot>` after a crash must
-- tolerate both shapes. Rationale: the prompt is supplied per
-- llm_bound invocation and is not part of the verify contract —
-- persisting it would double the state footprint without enabling
-- any automatic retry (retry is driver-policy, not primitive).
--
-- Hard-error residue (distinct from auto-rollback):
--   auto-rollback fires ONLY on echo mismatch. If `alc.llm` itself
--   raises (e.g. network failure / rate-limit throw), the error is
--   propagated verbatim and `_flow_req_<slot>` stays persisted. This
--   is deliberate: a hard error from alc.llm is indistinguishable,
--   from the caller's vantage, from a yield followed by a full
--   session restart — and the driver's resume path owns the cleanup
--   decision. Do NOT wrap `alc.llm` in `pcall` here; that would
--   destroy the yield/restart signal and convert every crash into
--   a silent rollback.
--
-- This is NOT a retry primitive. Higher-level policy (timeout, retry,
-- circuit breaker) belongs in the driver loop.

--- Session-spanning, state-bound bare LLM call. Persists verify state
--- before dispatching to `alc.llm`; auto-cleans on success; rolls back
--- and raises on mismatch.
---
--- Shape matches `flow.llm` (minus the externally-supplied `token`):
--- opts = { slot = string, prompt = string, llm_opts = table? }.
---@param st table
---@param opts { slot: string, prompt: string, llm_opts: table? }
---@return any
function M.llm_bound(st, opts)
    assert(type(st) == "table", "flow.llm_bound: st must be a table")
    assert(type(opts) == "table", "flow.llm_bound: opts must be a table")
    assert(type(opts.slot) == "string" and opts.slot ~= "",
        "flow.llm_bound: opts.slot must be a non-empty string")
    assert(type(opts.prompt) == "string",
        "flow.llm_bound: opts.prompt must be a string")
    assert(type(alc) == "table" and type(alc.llm) == "function",
        "flow.llm_bound: alc.llm is not available")

    local tok  = token.issue(st)
    local slot = opts.slot
    local key  = state.REQ_PREFIX .. slot

    st.data[key] = {
        slot          = slot,
        _expect_token = tok.value,
        _expect_slot  = slot,
    }
    state.save(st)

    local tagged_prompt = append_flow_tags(opts.prompt, tok.value, slot)

    local out = alc.llm(tagged_prompt, opts.llm_opts)

    local mismatch
    if type(out) == "string" then
        local echoed_token = util.parse_tag(out, "flow_token")
        local echoed_slot  = util.parse_tag(out, "flow_slot")
        if echoed_token and echoed_token ~= tok.value then
            mismatch = "flow.llm_bound: token mismatch (got " .. echoed_token
                .. ", expected " .. tok.value .. ")"
        elseif echoed_slot and echoed_slot ~= slot then
            mismatch = "flow.llm_bound: slot mismatch (got " .. echoed_slot
                .. ", expected " .. slot .. ")"
        end
    end

    -- Either branch clears the record: success terminates the cycle,
    -- mismatch rolls back so a retry (with a fresh token) starts clean.
    st.data[key] = nil
    state.save(st)

    if mismatch then
        error(mismatch)
    end
    return out
end

return M
