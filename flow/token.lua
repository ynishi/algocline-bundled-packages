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
---@param token { value: string }
---@param opts { slot: string, payload: table? }
---@return { slot: string, payload: table, _expect_token: string, _expect_slot: string }
function M.wrap(token, opts)
    assert(type(token) == "table" and type(token.value) == "string",
        "flow.token_wrap: token must have a string `value`")
    assert(type(opts) == "table" and type(opts.slot) == "string" and opts.slot ~= "",
        "flow.token_wrap: opts.slot must be a non-empty string")

    local payload = util.shallow_copy(opts.payload or {})
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
---@param _token { value: string }
---@param result table
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

return M
