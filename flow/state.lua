---@module 'flow.state'
-- FlowState: a plain table persisted via alc.state KV primitive.
-- No metatables, no OO. Users pass the state value to every fn.

local util = require("flow.util")

local M = {}

--- Build the alc.state key for this state.
---@param state table
---@return string
function M.key(state)
    return state.key_prefix .. ":" .. state.id
end

--- Create a new FlowState. When `opts.resume` is true and a persisted
--- record exists under the same key, `data` and the internal token
--- value are restored; `identity` is taken from `opts` and not
--- overwritten by the persisted record.
---
--- Since v0.2.0, on resume the caller-supplied `identity` is compared
--- against the persisted `identity` by structural equality. A mismatch
--- raises an error — this prevents silent parameter drift when the
--- same id is reused with different run parameters. Legacy checkpoints
--- written by flow 0.1.0 (no persisted `identity` field) are accepted
--- with a warning via `alc.log` for backward compatibility.
---@param opts { key_prefix: string, id: string, identity: table?, resume: boolean? }
---@return table
function M.new(opts)
    assert(type(opts) == "table", "flow.state_new: opts must be a table")
    assert(type(opts.key_prefix) == "string" and opts.key_prefix ~= "",
        "flow.state_new: opts.key_prefix must be a non-empty string")
    assert(type(opts.id) == "string" and opts.id ~= "",
        "flow.state_new: opts.id must be a non-empty string")

    local state = {
        key_prefix   = opts.key_prefix,
        id           = opts.id,
        identity     = opts.identity or {},
        data         = {},
        _token_value = nil,
    }

    if opts.resume and type(alc) == "table" and alc.state and alc.state.get then
        local persisted = alc.state.get(M.key(state))
        if type(persisted) == "table" then
            if persisted.identity ~= nil then
                if not util.deep_equal(state.identity, persisted.identity) then
                    error(string.format(
                        "flow.state_new: identity mismatch on resume for key %q "
                            .. "— the persisted checkpoint was written with a "
                            .. "different identity. Either use a fresh id or "
                            .. "pass the same identity as the original run.",
                        M.key(state)), 2)
                end
            elseif type(alc.log) == "function" then
                -- Legacy checkpoint (flow 0.1.0) — no persisted identity.
                -- Accept for backward compatibility but surface a warning.
                alc.log("warn", string.format(
                    "flow.state_new: resuming legacy checkpoint for key %q "
                        .. "(no persisted identity — identity validation "
                        .. "skipped for this run)",
                    M.key(state)))
            end
            state.data         = persisted.data or {}
            state._token_value = persisted._token_value
        end
    end

    return state
end

--- Read a user-domain key from state.data.
---@param state table
---@param k string
---@return any
function M.get(state, k)
    return state.data[k]
end

--- Write a user-domain key to state.data. Does not persist; call save.
---@param state table
---@param k string
---@param v any
function M.set(state, k, v)
    state.data[k] = v
end

--- Persist data + identity + internal token to alc.state under the
--- state key. Since v0.2.0 identity is persisted so that a subsequent
--- resume can validate that run parameters match the original run.
---@param state table
function M.save(state)
    assert(type(alc) == "table" and alc.state and alc.state.set,
        "flow.state_save: alc.state.set is not available")
    alc.state.set(M.key(state), {
        data         = state.data,
        identity     = state.identity,
        _token_value = state._token_value,
    })
end

return M
