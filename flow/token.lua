---@module 'flow.token'
-- ReqToken: random nonce issued against a FlowState and echoed by
-- downstream pkg results. Verification is fail-open: if a pkg does
-- not echo the token/slot, we treat the call as boundary-verified only.
--
-- The pattern is analogous to the AMQP correlation_id RPC idiom
-- (RabbitMQ): caller generates a nonce, sends it with the request,
-- and only accepts a reply that echoes the same nonce.

local util  = require("flow.util")
local state = require("flow.state")

local TOKEN_HEX_BYTES = 32

local M = {}

--- Issue a token bound to a state. If the state already has a
--- persisted token (resume), return it; otherwise generate a new
--- random value, store it on the state, and persist the state.
---@param st table
---@return { value: string, _state_key: string }
function M.issue(st)
    if type(st._token_value) == "string" and st._token_value ~= "" then
        return { value = st._token_value, _state_key = state.key(st) }
    end

    local value = util.random_hex(TOKEN_HEX_BYTES)
    st._token_value = value
    state.save(st)
    return { value = value, _state_key = state.key(st) }
end

--- Wrap a payload with the token + slot contract. The returned
--- object carries the payload the pkg should receive, plus verify
--- metadata under `_expect_*` keys which the caller retains.
--- `_flow_token` and `_flow_slot` are reserved keys owned by flow —
--- supplying a payload that already contains either raises an error,
--- rather than silently overwriting caller data.
---@param token { value: string }
---@param opts { slot: string, payload: table? }
---@return { slot: string, payload: table, _expect_token: string, _expect_slot: string }
function M.wrap(token, opts)
    assert(type(token) == "table" and type(token.value) == "string",
        "flow.token_wrap: token must have a string `value`")
    assert(type(opts) == "table" and type(opts.slot) == "string" and opts.slot ~= "",
        "flow.token_wrap: opts.slot must be a non-empty string")

    local payload_in = opts.payload or {}
    assert(type(payload_in) == "table",
        "flow.token_wrap: opts.payload must be a table or nil")
    assert(payload_in._flow_token == nil,
        "flow.token_wrap: opts.payload contains reserved key '_flow_token'")
    assert(payload_in._flow_slot == nil,
        "flow.token_wrap: opts.payload contains reserved key '_flow_slot'")

    local payload = util.shallow_copy(payload_in)
    payload._flow_token = token.value
    payload._flow_slot  = opts.slot

    return {
        slot          = opts.slot,
        payload       = payload,
        _expect_token = token.value,
        _expect_slot  = opts.slot,
    }
end

--- Verify that a pkg result echoed the expected token/slot. Fail-open:
--- if the result omits `_flow_token` / `_flow_slot`, the call is
--- considered boundary-verified only and we return true. Returns
--- false only when echoed values are present AND mismatched.
---
--- The leading `_token` parameter is intentionally unused: its
--- presence preserves API symmetry with `flow.token_wrap(token, opts)`
--- and reserves a hook for future token-rotation semantics where
--- `verify` may need to compare against the active token rather than
--- the one captured in `req._expect_token`.
---@param _token { value: string } -- reserved; see note above
---@param result any
---@param req { _expect_token: string, _expect_slot: string }
---@return boolean
function M.verify(_token, result, req)
    if type(result) ~= "table" then
        return true
    end
    if result._flow_token ~= nil and result._flow_token ~= req._expect_token then
        return false
    end
    if result._flow_slot ~= nil and result._flow_slot ~= req._expect_slot then
        return false
    end
    return true
end

-- ---------------------------------------------------------------------
-- Session-spanning bound API
-- ---------------------------------------------------------------------
-- `wrap_bound` / `verify_bound` persist the verify-side req under
-- `state.data._flow_req_<slot>` so that the call-and-verify cycle can
-- straddle an alc.llm yield or a full session restart. They are thin
-- state-lifecycle wrappers on top of `wrap` / `verify`; the Light Frame
-- discipline means the driver loop still belongs to the caller, but the
-- hand-off itself no longer requires the caller to juggle `req`
-- in-memory across a yield boundary.
--
-- Error semantics (non-symmetric, matches proposal §3.3):
--   wrap_bound   — assert on invalid input / reserved-key collision
--                  (inherits from `wrap`).
--   verify_bound — bool return, fail-open (inherits from `verify`).
--                  On a TRUE result (match or no-echo) we auto-delete
--                  `_flow_req_<slot>`; pass `opts.keep=true` to retain
--                  it (e.g. for idempotent re-entry). On FALSE we keep
--                  the record so callers can inspect / retry.

local FLOW_REQ_PREFIX = "_flow_req_"

--- Issue+wrap in one call, persisting the verify-side req under
--- `state.data._flow_req_<slot>`. Returns the same shape as `wrap`.
---
--- Intended pairing: `wrap_bound` → (dispatch payload) →
--- `verify_bound(st, slot, result)`. The persisted record survives a
--- full session restart as long as the FlowState itself is resumed.
---@param st table
---@param opts { slot: string, payload: table? }
---@return { slot: string, payload: table, _expect_token: string, _expect_slot: string }
function M.wrap_bound(st, opts)
    assert(type(st) == "table", "flow.token_wrap_bound: st must be a table")
    assert(type(opts) == "table" and type(opts.slot) == "string" and opts.slot ~= "",
        "flow.token_wrap_bound: opts.slot must be a non-empty string")

    local tok = M.issue(st)
    local req = M.wrap(tok, opts)
    st.data[FLOW_REQ_PREFIX .. opts.slot] = req
    state.save(st)
    return req
end

--- Verify a pkg result against the persisted req for `slot`. On a
--- successful verify (match or fail-open), the persisted record is
--- auto-deleted unless `opts.keep == true`. On mismatch (false), the
--- record is retained so the caller can inspect / retry.
---
--- Raises when no persisted record exists for `slot` — this is a
--- programmer error (verify_bound called without a prior wrap_bound /
--- llm_bound), not a verify failure.
---@param st table
---@param slot string
---@param result any
---@param opts { keep: boolean? }?
---@return boolean
function M.verify_bound(st, slot, result, opts)
    assert(type(st) == "table", "flow.token_verify_bound: st must be a table")
    assert(type(slot) == "string" and slot ~= "",
        "flow.token_verify_bound: slot must be a non-empty string")

    local key = FLOW_REQ_PREFIX .. slot
    local req = st.data[key]
    assert(req ~= nil,
        "flow.token_verify_bound: no persisted req for slot '" .. slot .. "'")

    local ok = M.verify(nil, result, req)
    local keep = type(opts) == "table" and opts.keep == true
    if ok and not keep then
        st.data[key] = nil
        state.save(st)
    end
    return ok
end

return M
