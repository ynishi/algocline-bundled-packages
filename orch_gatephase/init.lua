--- orch_gatephase — Gate-Phase Orchestration with Pre/Post Hooks
--- Each phase has pre-event (context setup) and post-event (gate + checks).
--- Task type determines which phases to skip.
--- Based on Thin Agent / Fat Platform (Praetorian).
---
--- Usage:
---   local orch = require("orch_gatephase")
---   return orch.run(ctx)
---
--- ctx.task       (required): Task description
--- ctx.phases     (required): Phase definitions [{name, prompt, gate, checks, ...}, ...]
--- ctx.max_retries (optional): Gate NG retry limit (default: 3)
--- ctx.task_type  (optional): Pre-classified type (bugfix/typo/refactor/feature/test)
--- ctx.skip_rules (optional): Custom skip rules table
--- ctx.on_fail    (optional): "error" | "partial" (default: "error")

local M = {}

---@type AlcMeta
M.meta = {
    name = "orch_gatephase",
    version = "0.1.0",
    description = "Phase orchestration with pre/post hooks and skip rules. "
        .. "Each phase has pre-event (context setup) and post-event (gate + checks). "
        .. "Task type determines which phases to skip. "
        .. "Based on Thin Agent / Fat Platform (Praetorian).",
    category = "orchestration",
}

-- Default skip rules (coding task oriented)
local DEFAULT_SKIP_RULES = {
    bugfix = { "design", "architecture" },
    typo = { "design", "architecture", "review", "test" },
    refactor = { "design" },
    feature = {},
    test = { "design", "architecture", "implement" },
}

--- Expand template variables.
local function expand(template, vars)
    local result = template
    for k, v in pairs(vars) do
        local sv = tostring(v)
        result = result:gsub("{" .. k .. "}", function() return sv end)
    end
    return result
end

--- Check if phase should be skipped.
local function should_skip(phase_name, skip_list)
    if not skip_list then return false end
    for _, name in ipairs(skip_list) do
        if name == phase_name then return true end
    end
    return false
end

--- Pre-hook: prepare context for phase execution.
local function default_pre_hook(phase, prev_output, task)
    local context_parts = {}
    context_parts[#context_parts + 1] = "Task: " .. task

    if prev_output and #prev_output > 0 then
        context_parts[#context_parts + 1] = "Previous phase output:\n" .. prev_output
    end

    if phase.inject then
        context_parts[#context_parts + 1] = phase.inject
    end

    return table.concat(context_parts, "\n\n")
end

--- Post-hook: gate + additional checks. Returns {gate_passed, checks}.
local function default_post_hook(phase, output)
    local results = { gate_passed = true, checks = {} }

    -- Primary gate
    if phase.gate then
        local keyword = phase.gate_keyword or "YES"
        local verdict = alc.llm(
            string.format("Evaluate:\n\n%s\n\n%s", output, phase.gate),
            { system = "Answer " .. keyword .. " or NO with reason.", max_tokens = 80 }
        )
        local passed = verdict:upper():find(keyword) ~= nil
        results.gate_passed = passed
        results.checks[#results.checks + 1] = {
            name = "gate",
            passed = passed,
            detail = verdict,
        }
    end

    -- Additional checks (phase.checks array)
    if phase.checks then
        for _, check in ipairs(phase.checks) do
            local verdict = alc.llm(
                string.format("Check the following output:\n\n%s\n\n%s", output, check.prompt),
                { system = "Answer YES or NO with reason.", max_tokens = 80 }
            )
            local passed = verdict:upper():find("YES") ~= nil
            results.checks[#results.checks + 1] = {
                name = check.name,
                passed = passed,
                detail = verdict,
            }
            if not passed then results.gate_passed = false end
        end
    end

    return results
end

--- Context compression.
local function compress(output, mode)
    if mode == "full" then return output, 0 end
    if #output <= 1500 then return output, 0 end

    local summary = alc.llm(
        "Summarize key points in 3-5 bullets:\n\n" .. output,
        { system = "Concise summarizer.", max_tokens = 300 }
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
    local task_type = ctx.task_type
    local skip_rules = ctx.skip_rules or DEFAULT_SKIP_RULES

    local total_llm_calls = 0

    -- Phase 0: Auto-classify task type if not provided (1 LLM call)
    if not task_type then
        local raw = alc.llm(
            "Classify this software task into one of: bugfix, typo, refactor, feature, test\n\n" .. task,
            { system = "Respond with ONLY the category name.", max_tokens = 20 }
        )
        task_type = raw:lower():match("%w+") or "feature"
        total_llm_calls = total_llm_calls + 1
        alc.log("info", "gatephase: classified as " .. task_type)
    end

    -- Determine skip list and active phases
    local skip_list = skip_rules[task_type] or {}

    local active_phases = {}
    for _, phase in ipairs(phases) do
        local pname = phase.name or "unnamed"
        if not should_skip(pname, skip_list) then
            active_phases[#active_phases + 1] = phase
        else
            alc.log("info", "gatephase: skipping phase [" .. pname .. "] for " .. task_type)
        end
    end

    local results = {}
    local prev_output = ""
    local status = "completed"

    for phase_idx, phase in ipairs(active_phases) do
        local phase_name = phase.name or ("phase_" .. phase_idx)
        local passed = false
        local output = ""
        local attempts = 0
        local feedback_parts = {}

        alc.log("info", string.format("gatephase: phase %d/%d [%s]",
            phase_idx, #active_phases, phase_name))

        for attempt = 1, max_retries do
            attempts = attempt

            -- Pre-hook
            local context = default_pre_hook(phase, prev_output, task)
            if #feedback_parts > 0 then
                context = context .. "\n\nPrevious attempt feedback:\n" ..
                    table.concat(feedback_parts, "\n")
            end

            -- Phase execution
            local prompt = expand(phase.prompt, {
                task = task,
                prev_output = prev_output,
                context = context,
                attempt = tostring(attempt),
            })

            output = alc.llm(prompt, {
                system = phase.system or ("You are a " .. phase_name .. " agent."),
                max_tokens = phase.max_tokens or 2000,
            })
            total_llm_calls = total_llm_calls + 1

            -- Post-hook
            local post_result = default_post_hook(phase, output)
            total_llm_calls = total_llm_calls + #(post_result.checks)

            if post_result.gate_passed then
                passed = true
                alc.log("info", string.format(
                    "gatephase: [%s] ALL CHECKS PASSED (attempt %d)", phase_name, attempt))
                break
            else
                feedback_parts = {}
                for _, check in ipairs(post_result.checks) do
                    if not check.passed then
                        feedback_parts[#feedback_parts + 1] =
                            string.format("[%s] %s", check.name, check.detail)
                    end
                end
                alc.log("info", string.format(
                    "gatephase: [%s] FAILED checks (attempt %d/%d)",
                    phase_name, attempt, max_retries))
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
                "gatephase: [%s] EXHAUSTED retries", phase_name))
            if on_fail == "error" then
                status = "failed"
                break
            else
                status = "partial"
            end
        end

        -- Context compression
        local cm = phase.context_mode or "summary"
        local extra
        prev_output, extra = compress(output, cm)
        total_llm_calls = total_llm_calls + extra
    end

    ctx.result = {
        status = status,
        task_type = task_type,
        skipped_phases = skip_list,
        phases = results,
        final_output = results[#results] and results[#results].output or "",
        total_llm_calls = total_llm_calls,
    }

    return ctx
end

return M
