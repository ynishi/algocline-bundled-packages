--- orch_fixpipe — Deterministic Fixed Pipeline
--- Phases execute in strict order. Gate NG triggers retry up to max_retries.
--- Based on Lobster (OpenClaw) deterministic workflow pattern.
---
--- Usage:
---   local orch = require("orch_fixpipe")
---   return orch.run(ctx)
---
--- ctx.task         (required): Task description
--- ctx.phases       (required): Phase definitions [{name, prompt, system, gate, ...}, ...]
--- ctx.max_retries  (optional): Gate NG retry limit (default: 3)
--- ctx.on_fail      (optional): "error" | "partial" (default: "error")
--- ctx.context_mode (optional): "summary" | "full" (default: "summary")

local M = {}

---@type AlcMeta
M.meta = {
    name = "orch_fixpipe",
    version = "0.1.0",
    description = "Deterministic fixed pipeline with gate/retry. "
        .. "Phases execute in strict order. Gate NG triggers retry up to max_retries. "
        .. "Based on Lobster (OpenClaw) deterministic workflow pattern.",
    category = "orchestration",
}

--- Expand template variables: {task}, {prev_output}, {attempt}, {feedback}.
local function expand(template, vars)
    local result = template
    for k, v in pairs(vars) do
        local sv = tostring(v)
        result = result:gsub("{" .. k .. "}", function() return sv end)
    end
    return result
end

--- Gate check: returns (passed, verdict_text).
local function check_gate(gate_prompt, output, gate_keyword)
    local keyword = gate_keyword or "YES"
    local verdict = alc.llm(
        string.format("Evaluate the following output:\n\n%s\n\n%s", output, gate_prompt),
        { system = "You are a quality gate. Answer " .. keyword .. " or NO with a brief reason.",
          max_tokens = 50 }
    )
    return verdict:upper():find(keyword) ~= nil, verdict
end

--- Summarize output for context compression.
local function summarize_output(output, max_len)
    max_len = max_len or 2000
    if #output <= max_len then return output, 0 end
    local summary = alc.llm(
        "Summarize the key points of the following in 3-5 bullet points:\n\n" .. output,
        { system = "You are a concise summarizer.", max_tokens = 300 }
    )
    return summary, 1
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local phases = ctx.phases or error("ctx.phases is required")
    local max_retries = ctx.max_retries or 3
    local on_fail = ctx.on_fail or "error"
    local context_mode = ctx.context_mode or "summary"

    local results = {}
    local prev_output = ""
    local total_llm_calls = 0
    local status = "completed"

    for phase_idx, phase in ipairs(phases) do
        local phase_name = phase.name or ("phase_" .. phase_idx)
        local passed = false
        local output = ""
        local attempts = 0
        local gate_reason = ""

        alc.log("info", string.format("fixpipe: starting phase %d/%d [%s]",
            phase_idx, #phases, phase_name))

        for attempt = 1, max_retries do
            attempts = attempt

            -- Phase execution
            local prompt_vars = {
                task = task,
                prev_output = prev_output,
                attempt = tostring(attempt),
                feedback = gate_reason,
            }
            local prompt = expand(phase.prompt, prompt_vars)
            local system = phase.system or ("You are a " .. phase_name .. " agent.")

            output = alc.llm(prompt, {
                system = system,
                max_tokens = phase.max_tokens or 2000,
            })
            total_llm_calls = total_llm_calls + 1

            -- Gate check
            if phase.gate then
                local gate_passed_flag, verdict = check_gate(
                    phase.gate, output, phase.gate_keyword
                )
                total_llm_calls = total_llm_calls + 1

                if gate_passed_flag then
                    passed = true
                    alc.log("info", string.format(
                        "fixpipe: [%s] gate PASSED (attempt %d/%d)",
                        phase_name, attempt, max_retries))
                    break
                else
                    gate_reason = verdict
                    alc.log("info", string.format(
                        "fixpipe: [%s] gate FAILED (attempt %d/%d): %s",
                        phase_name, attempt, max_retries, verdict))
                end
            else
                -- No gate defined → auto-pass
                passed = true
                break
            end
        end

        results[#results + 1] = {
            name = phase_name,
            output = output,
            gate_passed = passed,
            attempts = attempts,
        }

        if not passed then
            alc.log("warn", string.format(
                "fixpipe: [%s] FAILED after %d attempts", phase_name, max_retries))
            if on_fail == "error" then
                status = "failed"
                break
            else
                status = "partial"
            end
        end

        -- Context compression for next phase
        local cm = phase.context_mode or context_mode
        if cm == "summary" then
            local extra
            prev_output, extra = summarize_output(output)
            total_llm_calls = total_llm_calls + extra
        else
            prev_output = output
        end
    end

    ctx.result = {
        status = status,
        phases = results,
        final_output = results[#results] and results[#results].output or "",
        total_llm_calls = total_llm_calls,
    }

    return ctx
end

return M
