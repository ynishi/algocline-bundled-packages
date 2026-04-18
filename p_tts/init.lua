--- p_tts — Plan-Test-Then-Solve (constraint-first reasoning)
---
--- Before solving, generates expected properties and test cases the answer
--- must satisfy. Then solves while checking against those constraints.
--- Finally verifies the solution against all generated test cases.
---
--- Unlike decompose (splits into subtasks) or reflect (post-hoc critique),
--- p_tts generates verifiable constraints BEFORE solving, creating a
--- specification-driven approach to reasoning.
---
--- Based on: "Planning with Large Language Models for Code Generation"
---            (Zhang et al., arXiv 2303.05510, 2023)
---            + test-driven development methodology applied to reasoning
---            + "Specification-Driven LLM Reasoning" concepts
---
--- Pipeline:
---   Step 1: plan       — analyze task and identify key requirements
---   Step 2: test       — generate verifiable properties/constraints
---   Step 3: solve      — solve while aware of constraints
---   Step 4: verify     — check solution against each constraint
---   Step 5: repair     — fix violations (if any)
---
--- Usage:
---   local p_tts = require("p_tts")
---   return p_tts.run(ctx)
---
--- ctx.task (required): The task/question to solve
--- ctx.max_constraints: Max constraints to generate (default: 6)
--- ctx.max_repairs: Max repair attempts (default: 2)
--- ctx.plan_tokens: Max tokens for planning (default: 400)
--- ctx.gen_tokens: Max tokens for solving (default: 600)
--- ctx.verify_tokens: Max tokens per constraint check (default: 150)

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "p_tts",
    version = "0.1.0",
    description = "Plan-Test-Then-Solve — generate constraints before solving, verify solution against specification",
    category = "planning",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task            = T.string:describe("The task/question to solve"),
                max_constraints = T.number:is_optional():describe("Max constraints to generate (default: 6)"),
                max_repairs     = T.number:is_optional():describe("Max repair attempts (default: 2)"),
                plan_tokens     = T.number:is_optional():describe("Max tokens for planning (default: 400)"),
                gen_tokens      = T.number:is_optional():describe("Max tokens for solving (default: 600)"),
                verify_tokens   = T.number:is_optional():describe("Max tokens per constraint check (default: 150)"),
            }),
            result = T.shape({
                answer            = T.string:describe("Final answer after verify+repair"),
                plan              = T.string:describe("Planning phase LLM output"),
                constraints       = T.array_of(T.string):describe("Verifiable constraints the answer must satisfy"),
                pass_count        = T.number:describe("Number of constraints passing in the final round"),
                fail_count        = T.number:describe("Number of constraints failing in the final round"),
                total_constraints = T.number:describe("Total number of constraints generated"),
                repairs           = T.number:describe("Number of repair rounds performed"),
                all_passed        = T.boolean:describe("Whether all constraints passed"),
                history = T.array_of(T.shape({
                    attempt = T.number:describe("Round index (0-based)"),
                    answer  = T.string:describe("Answer produced in this round"),
                    results = T.array_of(T.shape({
                        constraint = T.string:describe("The constraint being checked"),
                        verdict    = T.one_of({ "pass", "fail" })
                            :describe("Verification verdict for this constraint"),
                        reason     = T.string:describe("Rationale behind the verdict"),
                    })):describe("Per-constraint verification results"),
                    pass_count = T.number:describe("PASS count for this round"),
                    fail_count = T.number:describe("FAIL count for this round"),
                })):describe("Per-round repair history"),
            }),
        },
    },
}

--- Parse numbered constraints from LLM output.
local function parse_constraints(raw)
    local constraints = {}
    for line in raw:gmatch("[^\n]+") do
        local _, constraint = line:match("^%s*(%d+)[%.%)%s]+(.+)")
        if constraint then
            constraint = constraint:match("^%s*(.-)%s*$")
            if #constraint > 10 then
                constraints[#constraints + 1] = constraint
            end
        end
    end
    return constraints
end

--- Parse PASS/FAIL verdict from verification.
local function parse_verdict(text)
    local lower = text:lower()
    if lower:match("fail") or lower:match("violat") or lower:match("not met")
        or lower:match("incorrect") then
        return "fail"
    end
    return "pass"
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local max_constraints = ctx.max_constraints or 6
    local max_repairs = ctx.max_repairs or 2
    local plan_tokens = ctx.plan_tokens or 400
    local gen_tokens = ctx.gen_tokens or 600
    local verify_tokens = ctx.verify_tokens or 150

    -- ─── Step 1: Plan — analyze requirements ───
    alc.log("info", "p_tts: Step 1 — planning")

    local plan = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Before solving, analyze this task:\n"
                .. "1. What type of problem is this? (math, reasoning, factual, creative, etc.)\n"
                .. "2. What are the key requirements?\n"
                .. "3. What are common mistakes people make on this type of problem?\n"
                .. "4. What approach would be most reliable?",
            task
        ),
        {
            system = "You are a strategic planner. Analyze the task before attempting "
                .. "to solve it. Identify requirements, potential pitfalls, and the "
                .. "best approach. Do NOT solve the task yet — only plan.",
            max_tokens = plan_tokens,
        }
    )

    alc.log("info", string.format("p_tts: plan generated (%d chars)", #plan))

    -- ─── Step 2: Test — generate verifiable constraints ───
    alc.log("info", "p_tts: Step 2 — generating constraints")

    local constraints_raw = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Analysis:\n%s\n\n"
                .. "Generate up to %d verifiable constraints that a correct answer "
                .. "MUST satisfy. Each constraint should be:\n"
                .. "- Specific and objectively checkable\n"
                .. "- Independent (checking one doesn't depend on another)\n"
                .. "- Covering different aspects of correctness\n\n"
                .. "Examples of good constraints:\n"
                .. "- 'The answer must be a positive integer'\n"
                .. "- 'The explanation must address X'\n"
                .. "- 'The result must satisfy equation Y'\n"
                .. "- 'The answer must account for edge case Z'\n\n"
                .. "List constraints:\n"
                .. "1. [constraint]\n2. ...",
            task, plan, max_constraints
        ),
        {
            system = "You are a test designer. Generate constraints that a correct "
                .. "answer must satisfy. Think like a teacher designing a rubric: "
                .. "what properties must the answer have? Be specific and verifiable.",
            max_tokens = plan_tokens,
        }
    )

    local constraints = parse_constraints(constraints_raw)

    if #constraints == 0 then
        alc.log("warn", "p_tts: no constraints generated, solving without constraints")
        constraints = { "The answer must be correct and well-reasoned" }
    end

    alc.log("info", string.format(
        "p_tts: %d constraints generated", #constraints
    ))

    -- ─── Step 3+4+5: Solve → Verify → Repair loop ───
    local constraint_list = {}
    for i, c in ipairs(constraints) do
        constraint_list[#constraint_list + 1] = string.format("%d. %s", i, c)
    end
    local constraints_text = table.concat(constraint_list, "\n")

    local current_answer = nil
    local repair_history = {}

    for attempt = 0, max_repairs do
        -- ─── Step 3: Solve ───
        if attempt == 0 then
            alc.log("info", "p_tts: Step 3 — solving with constraint awareness")

            current_answer = alc.llm(
                string.format(
                    "Task: %s\n\n"
                        .. "Planning analysis:\n%s\n\n"
                        .. "Your answer MUST satisfy ALL of these constraints:\n%s\n\n"
                        .. "Solve the task carefully, ensuring each constraint is met.",
                    task, plan, constraints_text
                ),
                {
                    system = "You are an expert solver. You have been given specific "
                        .. "constraints your answer must satisfy. Solve carefully and "
                        .. "verify each constraint is met in your answer.",
                    max_tokens = gen_tokens,
                }
            )
        end

        -- ─── Step 4: Verify against each constraint ───
        alc.log("info", string.format(
            "p_tts: Step 4 — verifying %d constraints (attempt %d)",
            #constraints, attempt
        ))

        local verifications = alc.map(constraints, function(constraint)
            return alc.llm(
                string.format(
                    "Task: %s\n\n"
                        .. "Answer:\n\"\"\"\n%s\n\"\"\"\n\n"
                        .. "Constraint: \"%s\"\n\n"
                        .. "Does this answer satisfy this constraint?\n"
                        .. "VERDICT: PASS or FAIL\n"
                        .. "REASON: [brief explanation]",
                    task, current_answer, constraint
                ),
                {
                    system = "You are a strict test checker. Evaluate whether "
                        .. "the answer satisfies the given constraint. Be rigorous: "
                        .. "PASS only if clearly satisfied. FAIL if violated or unclear.",
                    max_tokens = verify_tokens,
                }
            )
        end)

        -- Parse verification results
        local results = {}
        local failures = {}
        local pass_count = 0

        for i, raw in ipairs(verifications) do
            local verdict = parse_verdict(raw)
            local reason = raw:match("[Rr]eason:%s*(.-)$")
                or raw:match("\n([^\n]+)$")
                or ""
            reason = reason:match("^%s*(.-)%s*$") or ""

            results[#results + 1] = {
                constraint = constraints[i],
                verdict = verdict,
                reason = reason,
            }

            if verdict == "pass" then
                pass_count = pass_count + 1
            else
                failures[#failures + 1] = {
                    index = i,
                    constraint = constraints[i],
                    reason = reason,
                }
            end
        end

        repair_history[#repair_history + 1] = {
            attempt = attempt,
            answer = current_answer,
            results = results,
            pass_count = pass_count,
            fail_count = #failures,
        }

        alc.log("info", string.format(
            "p_tts: %d/%d constraints passed (attempt %d)",
            pass_count, #constraints, attempt
        ))

        -- All passed or max repairs reached
        if #failures == 0 then
            alc.log("info", "p_tts: all constraints satisfied")
            break
        end

        if attempt >= max_repairs then
            alc.log("info", string.format(
                "p_tts: max repairs reached (%d), %d constraints still failing",
                max_repairs, #failures
            ))
            break
        end

        -- ─── Step 5: Repair ───
        local failure_list = {}
        for _, f in ipairs(failures) do
            failure_list[#failure_list + 1] = string.format(
                "- Constraint %d: \"%s\"\n  Failure reason: %s",
                f.index, f.constraint, f.reason
            )
        end

        alc.log("info", string.format(
            "p_tts: Step 5 — repairing %d failed constraints", #failures
        ))

        current_answer = alc.llm(
            string.format(
                "Task: %s\n\n"
                    .. "Current answer:\n\"\"\"\n%s\n\"\"\"\n\n"
                    .. "The following constraints FAILED:\n\n%s\n\n"
                    .. "ALL constraints that must be satisfied:\n%s\n\n"
                    .. "Fix the answer to satisfy ALL failed constraints "
                    .. "while maintaining the constraints that already pass.",
                task, current_answer,
                table.concat(failure_list, "\n"),
                constraints_text
            ),
            {
                system = "You are repairing a solution that violated specific "
                    .. "constraints. Fix each violation precisely. Do not break "
                    .. "constraints that were already passing.",
                max_tokens = gen_tokens,
            }
        )
    end

    -- Final status
    local final_round = repair_history[#repair_history]

    ctx.result = {
        answer = current_answer,
        plan = plan,
        constraints = constraints,
        pass_count = final_round.pass_count,
        fail_count = final_round.fail_count,
        total_constraints = #constraints,
        repairs = #repair_history - 1,
        all_passed = final_round.fail_count == 0,
        history = repair_history,
    }
    return ctx
end

-- Malli-style self-decoration: wrapper asserts ctx against
-- M.spec.entries.run.input and ret.result against .result when
-- ALC_SHAPE_CHECK=1.
M.run = S.instrument(M, "run")

return M
