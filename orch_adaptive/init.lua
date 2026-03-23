--- orch_adaptive — Adaptive Depth Orchestration
--- Dynamically adjusts phase count, retry budget, and context mode
--- based on task difficulty. Combines with router_daao for pre-classified
--- difficulty, or estimates internally.
---
--- Based on DAAO (arxiv 2509.11079).
---
--- Usage:
---   local orch = require("orch_adaptive")
---   return orch.run(ctx)
---
--- ctx.task         (required): Task description
--- ctx.phases       (required): Phase definitions (superset; trimmed by difficulty)
--- ctx.difficulty   (optional): Pre-classified difficulty from router_daao
--- ctx.depth_config (optional): Custom difficulty→config mapping
--- ctx.on_fail      (optional): "error" | "partial" (default: "error")

local M = {}

M.meta = {
    name = "orch_adaptive",
    version = "0.1.0",
    description = "Adaptive depth orchestration based on task difficulty. "
        .. "Dynamically adjusts phase count, retry budget, and context mode. "
        .. "Combines with router_daao for pre-classified difficulty, "
        .. "or estimates internally. Based on DAAO (arxiv 2509.11079).",
    category = "orchestration",
}

-- Difficulty→execution parameter mapping
local DEFAULT_DEPTH_CONFIG = {
    simple = {
        max_phases = 2,
        max_retries = 1,
        context_mode = "summary",
        max_tokens = 1500,
    },
    medium = {
        max_phases = 4,
        max_retries = 3,
        context_mode = "summary",
        max_tokens = 2000,
    },
    complex = {
        max_phases = 6,
        max_retries = 5,
        context_mode = "full",
        max_tokens = 4000,
    },
}

local CLASSIFY_SYSTEM = [[Classify this software engineering task difficulty.
- simple: 1-2 files, clear change, no design decision
- medium: multi-file, some architectural awareness needed
- complex: design decisions, cross-cutting, regression risk
Respond with ONLY: simple, medium, or complex]]

--- Expand template variables.
local function expand(template, vars)
    local result = template
    for k, v in pairs(vars) do
        local sv = tostring(v)
        result = result:gsub("{" .. k .. "}", function() return sv end)
    end
    return result
end

--- Gate check.
local function check_gate(gate_prompt, output)
    local verdict = alc.llm(
        string.format("Evaluate:\n\n%s\n\n%s", output, gate_prompt),
        { system = "Answer YES or NO with brief reason.", max_tokens = 50 }
    )
    return verdict:upper():find("YES") ~= nil, verdict
end

--- Context compression.
local function compress(output, mode)
    if mode == "full" or #output <= 1500 then return output, 0 end
    local summary = alc.llm(
        "Summarize key points in 3-5 bullets:\n\n" .. output,
        { system = "Concise summarizer.", max_tokens = 300 }
    )
    return summary, 1
end

function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local phases = ctx.phases or error("ctx.phases is required")
    local difficulty = ctx.difficulty
    local depth_config = ctx.depth_config or DEFAULT_DEPTH_CONFIG
    local on_fail = ctx.on_fail or "error"

    local total_llm_calls = 0

    -- Phase 0: Estimate difficulty if not pre-classified
    if not difficulty then
        local raw = alc.llm(task, { system = CLASSIFY_SYSTEM, max_tokens = 20 })
        difficulty = raw:lower():match("%w+") or "medium"
        total_llm_calls = total_llm_calls + 1
        alc.log("info", "adaptive: estimated difficulty = " .. difficulty)
    end

    local config = depth_config[difficulty]
    if not config then
        alc.log("warn", "adaptive: unknown difficulty '" .. difficulty .. "', using medium")
        config = depth_config["medium"]
    end

    -- Determine active phases (depth limit)
    local active_phases = {}
    for i = 1, math.min(config.max_phases, #phases) do
        active_phases[i] = phases[i]
    end

    alc.log("info", string.format(
        "adaptive: difficulty=%s, phases=%d/%d, retries=%d, context=%s",
        difficulty, #active_phases, #phases,
        config.max_retries, config.context_mode
    ))

    -- Main loop (fixpipe-equivalent)
    local results = {}
    local prev_output = ""
    local status = "completed"

    for phase_idx, phase in ipairs(active_phases) do
        local phase_name = phase.name or ("phase_" .. phase_idx)
        local passed = false
        local output = ""
        local attempts = 0
        local feedback = ""

        for attempt = 1, config.max_retries do
            attempts = attempt

            local prompt = expand(phase.prompt, {
                task = task,
                prev_output = prev_output,
                attempt = tostring(attempt),
                feedback = feedback,
                difficulty = difficulty,
            })

            output = alc.llm(prompt, {
                system = phase.system or ("You are a " .. phase_name .. " agent."),
                max_tokens = phase.max_tokens or config.max_tokens,
            })
            total_llm_calls = total_llm_calls + 1

            if phase.gate then
                local gate_ok, verdict = check_gate(phase.gate, output)
                total_llm_calls = total_llm_calls + 1

                if gate_ok then
                    passed = true
                    break
                end
                feedback = verdict
            else
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
            if on_fail == "error" then
                status = "failed"
                break
            end
            status = "partial"
        end

        local extra_calls
        prev_output, extra_calls = compress(output, config.context_mode)
        total_llm_calls = total_llm_calls + extra_calls
    end

    ctx.result = {
        status = status,
        difficulty = difficulty,
        depth_config = config,
        active_phase_count = #active_phases,
        total_phase_count = #phases,
        phases = results,
        final_output = results[#results] and results[#results].output or "",
        total_llm_calls = total_llm_calls,
    }

    return ctx
end

return M
