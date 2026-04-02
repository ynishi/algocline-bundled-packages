--- model_first — Model-First Reasoning
---
--- Separates problem representation from problem solving. First constructs
--- an explicit problem model (entities, state variables, actions with
--- preconditions/effects, and constraints), then reasons within that model.
---
--- Key difference from plan_solve: plan_solve generates "what to do" (action
--- sequence). model_first generates "what exists" (world model) before any
--- solving. This catches constraint violations that plan_solve misses
--- because constraints are implicit in plan_solve but explicit here.
---
--- Based on: Rana & Kumar, "Model-First Reasoning LLM Agents: Reducing
--- Hallucinations through Explicit Problem Modeling"
--- (arXiv:2512.14474, 2025)
---
--- Pipeline (2-4 LLM calls):
---   Step 1: Model    — construct explicit problem model (entities, states,
---                       actions, constraints). Do NOT solve yet.
---   Step 2: Solve    — reason within the model, tracking state transitions
---   Step 3: Verify   — check solution against all model constraints (optional)
---   Step 4: Extract  — concise final answer (optional)
---
--- Usage:
---   local mf = require("model_first")
---   return mf.run(ctx)
---
--- ctx.task (required): The problem to solve
--- ctx.verify: Run constraint verification step (default: true)
--- ctx.extract: Extract concise answer (default: true)
--- ctx.model_tokens: Max tokens for model construction (default: 500)
--- ctx.solve_tokens: Max tokens for solving (default: 600)

local M = {}

---@type AlcMeta
M.meta = {
    name = "model_first",
    version = "0.1.0",
    description = "Model-First Reasoning — construct explicit problem model "
        .. "(entities, states, actions, constraints) before solving. "
        .. "Reduces constraint violations in planning and scheduling tasks.",
    category = "reasoning",
}

--- Parse constraint violations from verification output.
local function parse_violations(text)
    local violations = {}
    local lower = text:lower()

    -- Check for "no violations" patterns
    if lower:match("no violations") or lower:match("all constraints satisfied")
        or lower:match("no constraint.*violated") then
        return violations
    end

    -- Extract numbered violations
    for line in text:gmatch("[^\n]+") do
        if line:match("[Vv]iolat") or line:match("[Ff]ail") or line:match("[Bb]reak") then
            local v = line:match("^%s*[%-%*%d%.%)]+%s*(.+)")
            if v then
                violations[#violations + 1] = v
            end
        end
    end

    return violations
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local verify = ctx.verify
    if verify == nil then verify = true end
    local extract = ctx.extract
    if extract == nil then extract = true end
    local model_tokens = ctx.model_tokens or 500
    local solve_tokens = ctx.solve_tokens or 600

    -- ─── Step 1: Construct Problem Model ───
    alc.log("info", "model_first: Step 1 — constructing problem model")

    local model = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Analyze this problem and construct an explicit problem model. "
                .. "Do NOT solve the problem yet — only model it.\n\n"
                .. "Define:\n\n"
                .. "1. ENTITIES: All objects, agents, or resources involved.\n"
                .. "   For each: name, type, and initial properties.\n\n"
                .. "2. STATE VARIABLES: Properties that change over time.\n"
                .. "   For each: which entity it belongs to, possible values, "
                .. "initial value.\n\n"
                .. "3. ACTIONS: Operations that can be performed.\n"
                .. "   For each:\n"
                .. "   - Preconditions: what must be true to perform this action\n"
                .. "   - Effects: how state variables change after the action\n\n"
                .. "4. CONSTRAINTS: Rules that must ALWAYS hold.\n"
                .. "   - Hard constraints (never violate)\n"
                .. "   - Ordering constraints (A must happen before B)\n"
                .. "   - Resource constraints (capacity limits, availability)\n\n"
                .. "Be exhaustive. Missing a constraint leads to invalid solutions.",
            task
        ),
        {
            system = "You are a problem analyst and modeler. Your job is to define "
                .. "the problem structure — NOT to solve it. Think like a systems "
                .. "engineer defining requirements. Be precise about constraints: "
                .. "every rule, limit, and dependency must be captured.",
            max_tokens = model_tokens,
        }
    )

    -- Count model elements for logging
    local entity_count = 0
    for _ in model:gmatch("[Ee]ntit") do entity_count = entity_count + 1 end
    local constraint_count = 0
    for _ in model:gmatch("[Cc]onstraint") do constraint_count = constraint_count + 1 end

    alc.log("info", string.format(
        "model_first: model constructed (~%d entity refs, ~%d constraint refs)",
        entity_count, constraint_count
    ))

    -- ─── Step 2: Solve within Model ───
    alc.log("info", "model_first: Step 2 — solving within model")

    local solution = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Problem Model:\n\"\"\"\n%s\n\"\"\"\n\n"
                .. "Using ONLY the model defined above, generate a step-by-step "
                .. "solution. For each step:\n"
                .. "1. State which ACTION you are taking\n"
                .. "2. Verify its PRECONDITIONS are met in the current state\n"
                .. "3. Show the STATE TRANSITION (which variables change)\n"
                .. "4. Confirm no CONSTRAINTS are violated\n\n"
                .. "Track the full state after each step.",
            task, model
        ),
        {
            system = "You are a precise executor working within a defined model. "
                .. "Every action must respect preconditions. Every state transition "
                .. "must be explicit. Every constraint must be checked. If a step "
                .. "would violate a constraint, do not take it — find an alternative.",
            max_tokens = solve_tokens,
        }
    )

    alc.log("info", "model_first: solution generated")

    -- ─── Step 3: Verify constraints (optional) ───
    local violations = {}
    local verified_solution = solution

    if verify then
        alc.log("info", "model_first: Step 3 — verifying constraints")

        local verification = alc.llm(
            string.format(
                "Task: %s\n\n"
                    .. "Problem Model:\n\"\"\"\n%s\n\"\"\"\n\n"
                    .. "Proposed Solution:\n\"\"\"\n%s\n\"\"\"\n\n"
                    .. "Verify this solution against the model:\n"
                    .. "1. Check EVERY action's preconditions are satisfied\n"
                    .. "2. Check EVERY constraint after EVERY step\n"
                    .. "3. Check state variable consistency\n"
                    .. "4. Check no resources exceed capacity\n\n"
                    .. "List ALL violations found. If none, state 'No violations found.'\n"
                    .. "If violations exist, propose corrections.",
                task, model, solution
            ),
            {
                system = "You are a strict constraint checker. Check every step "
                    .. "against every constraint. Be thorough — a single missed "
                    .. "violation can invalidate the entire solution.",
                max_tokens = solve_tokens,
            }
        )

        violations = parse_violations(verification)

        if #violations > 0 then
            alc.log("info", string.format(
                "model_first: %d violations found, repairing", #violations
            ))

            verified_solution = alc.llm(
                string.format(
                    "Task: %s\n\n"
                        .. "Problem Model:\n\"\"\"\n%s\n\"\"\"\n\n"
                        .. "Previous Solution (with violations):\n\"\"\"\n%s\n\"\"\"\n\n"
                        .. "Violations found:\n%s\n\n"
                        .. "Repair the solution to eliminate ALL violations while "
                        .. "still solving the original task. Track state after each step.",
                    task, model, solution,
                    table.concat(violations, "\n")
                ),
                {
                    system = "You are repairing a solution with constraint violations. "
                        .. "Fix each violation while maintaining solution correctness. "
                        .. "Track state transitions explicitly.",
                    max_tokens = solve_tokens,
                }
            )
        else
            alc.log("info", "model_first: no violations found")
        end
    end

    -- ─── Step 4: Extract concise answer (optional) ───
    local final_answer = verified_solution
    if extract then
        alc.log("info", "model_first: Step 4 — extracting concise answer")

        final_answer = alc.llm(
            string.format(
                "Task: %s\n\n"
                    .. "Full solution:\n\"\"\"\n%s\n\"\"\"\n\n"
                    .. "Extract the final answer concisely. Include the key result "
                    .. "and any critical constraints that shaped the solution.",
                task, verified_solution
            ),
            {
                system = "Extract the final answer. Be concise but complete. "
                    .. "Mention key constraints that were binding.",
                max_tokens = 300,
            }
        )
    end

    ctx.result = {
        answer = final_answer,
        model = model,
        solution = verified_solution,
        violations_found = #violations,
        violations = violations,
        verified = verify,
    }
    return ctx
end

return M
