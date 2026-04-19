---@module 'flow.llm'
-- Bare LLM call helper with slot + token tag echo.
--
-- alc.llm (crates/algocline-engine/src/bridge/llm.rs as of 2026-04-19)
-- does not expose structured output (response_format / tool_use).
-- We therefore embed `[flow_token=...][flow_slot=...]` into the prompt
-- and verify echo via regex on the returned string. If the LLM omits
-- the tags, we treat the call as unverified (fail-open): the error is
-- raised only when the echoed tag is PRESENT and MISMATCHED.

local util = require("flow.util")

local M = {}

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

    local tagged_prompt = opts.prompt
        .. "\n\n[flow_token=" .. opts.token.value .. "]"
        .. "[flow_slot=" .. opts.slot .. "]"

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

return M
