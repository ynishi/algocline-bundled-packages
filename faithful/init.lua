--- faithful — Faithful Chain-of-Thought with formal verification
---
--- Translates natural language reasoning into a formal representation
--- (code, logic, or structured proof) for verification, then produces
--- a natural language answer grounded in the verified formal output.
--- Catches reasoning errors that are invisible in natural language.
---
--- Based on: Lyu et al., "Faithful Chain-of-Thought Reasoning" (2023,
--- arXiv:2301.13379) + Gao et al., "PAL: Program-Aided Language Models"
--- (2023, arXiv:2211.10435)
---
--- Pipeline (3-4 LLM calls):
---   Step 1: Reason     — natural language chain-of-thought
---   Step 2: Formalize  — translate reasoning to formal representation
---   Step 3: Verify     — check formal representation for correctness
---   Step 4: Answer     — produce final answer grounded in verification
---
--- Usage:
---   local faithful = require("faithful")
---   return faithful.run(ctx)
---
--- ctx.task (required): The problem to solve
--- ctx.format: Formal representation type — "code", "logic", or "auto" (default: "auto")
--- ctx.gen_tokens: Max tokens per step (default: 500)

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "faithful",
    version = "0.1.0",
    description = "Faithful CoT — formalize reasoning into code/logic for verification, then answer",
    category = "reasoning",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task       = T.string:describe("The problem to solve"),
                format     = T.string:is_optional():describe("Formal representation type: code / logic / auto (default: auto)"),
                gen_tokens = T.number:is_optional():describe("Max tokens per step (default: 500)"),
            }),
            result = T.shape({
                answer       = T.string:describe("Final answer grounded in formal verification"),
                format       = T.string:describe("Formal representation actually used: code / logic"),
                nl_reasoning = T.string:describe("Step 1 natural-language reasoning chain"),
                formal       = T.string:describe("Step 2 formal representation (code or logic derivation)"),
                verification = T.string:describe("Step 3 verification output"),
                errors_found = T.boolean:describe("True if verification surfaced any errors in the reasoning"),
            }),
        },
    },
}

--- Determine the best formal representation for a given task.
local function detect_format(task)
    local lower = task:lower()
    -- Math/calculation signals
    if lower:match("calculat") or lower:match("how many")
        or lower:match("how much") or lower:match("solve")
        or lower:match("equation") or lower:match("percent")
        or lower:match("ratio") or lower:match("average")
        or lower:match("sum") or lower:match("total")
        or lower:match("combin") or lower:match("probab") then
        return "code"
    end
    -- Logic/argument signals
    if lower:match("if .+ then") or lower:match("implies")
        or lower:match("valid") or lower:match("contradict")
        or lower:match("all .+ are") or lower:match("none .+ are")
        or lower:match("syllogism") or lower:match("logical") then
        return "logic"
    end
    -- Default to code (more general verification)
    return "code"
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local format = ctx.format or "auto"
    local gen_tokens = ctx.gen_tokens or 500

    if format == "auto" then
        format = detect_format(task)
    end

    alc.log("info", string.format("faithful: using '%s' formal representation", format))

    -- ─── Step 1: Natural language reasoning ───
    alc.log("info", "faithful: Step 1 — natural language reasoning")

    local nl_reasoning = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Think through this step by step. Show your complete "
                .. "reasoning chain. Identify the key quantities, "
                .. "relationships, and logical steps.",
            task
        ),
        {
            system = "You are a careful reasoner. Show every step clearly. "
                .. "Identify all variables, constraints, and relationships.",
            max_tokens = gen_tokens,
        }
    )

    -- ─── Step 2: Formalize ───
    alc.log("info", "faithful: Step 2 — formalizing reasoning")

    local formalize_instruction
    if format == "code" then
        formalize_instruction = string.format(
            "Task: %s\n\n"
                .. "Natural language reasoning:\n\"\"\"\n%s\n\"\"\"\n\n"
                .. "Translate this reasoning into a Python program that:\n"
                .. "1. Defines all variables and relationships explicitly\n"
                .. "2. Performs all calculations step by step\n"
                .. "3. Prints the final answer with a label\n"
                .. "4. Includes assertions or checks where possible\n\n"
                .. "Output ONLY the Python code (no markdown fences, no explanation).",
            task, nl_reasoning
        )
    else -- logic
        formalize_instruction = string.format(
            "Task: %s\n\n"
                .. "Natural language reasoning:\n\"\"\"\n%s\n\"\"\"\n\n"
                .. "Translate this reasoning into formal logic:\n"
                .. "1. State each premise as a formal proposition (P1, P2, ...)\n"
                .. "2. Show each inference step with the rule used\n"
                .. "3. Derive the conclusion explicitly\n"
                .. "4. Check for any logical fallacies\n\n"
                .. "Format:\n"
                .. "PREMISES:\n  P1: ...\n  P2: ...\n"
                .. "DERIVATION:\n  S1: ... (from P1, P2 by modus ponens)\n"
                .. "CONCLUSION: ...\n"
                .. "VALIDITY: VALID / INVALID (reason)",
            task, nl_reasoning
        )
    end

    local formal = alc.llm(formalize_instruction, {
        system = format == "code"
            and "You are a precise programmer. Translate reasoning into "
                .. "executable code. Output only code, no commentary."
            or "You are a formal logician. Translate arguments into "
                .. "rigorous logical form. Check validity.",
        max_tokens = gen_tokens,
    })

    -- ─── Step 3: Verify the formal representation ───
    alc.log("info", "faithful: Step 3 — verifying formal representation")

    local verify_instruction
    if format == "code" then
        verify_instruction = string.format(
            "Task: %s\n\n"
                .. "Original reasoning:\n\"\"\"\n%s\n\"\"\"\n\n"
                .. "Formalized as code:\n```\n%s\n```\n\n"
                .. "Verify this code:\n"
                .. "1. Does the code faithfully represent the reasoning?\n"
                .. "2. Are all variables and relationships correct?\n"
                .. "3. Are there any bugs, off-by-one errors, or wrong formulas?\n"
                .. "4. Mentally trace through the code — what would it output?\n\n"
                .. "State:\n"
                .. "EXPECTED OUTPUT: (what the code would print)\n"
                .. "ERRORS FOUND: (list any errors, or NONE)\n"
                .. "CORRECTED ANSWER: (the correct answer based on your trace)",
            task, nl_reasoning, formal
        )
    else
        verify_instruction = string.format(
            "Task: %s\n\n"
                .. "Original reasoning:\n\"\"\"\n%s\n\"\"\"\n\n"
                .. "Formalized as logic:\n\"\"\"\n%s\n\"\"\"\n\n"
                .. "Verify this formal derivation:\n"
                .. "1. Are all premises correctly extracted?\n"
                .. "2. Is each inference step valid?\n"
                .. "3. Does the conclusion follow?\n"
                .. "4. Are there any hidden assumptions?\n\n"
                .. "State:\n"
                .. "VALIDITY: VALID / INVALID\n"
                .. "ERRORS FOUND: (list any errors, or NONE)\n"
                .. "CORRECTED CONCLUSION: (the correct conclusion)",
            task, nl_reasoning, formal
        )
    end

    local verification = alc.llm(verify_instruction, {
        system = "You are a meticulous verifier. Check every step. "
            .. "Find errors if they exist. Be precise about corrections.",
        max_tokens = gen_tokens,
    })

    local has_errors = verification:upper():match("ERRORS FOUND:%s*NONE") == nil
        and not verification:upper():match("NO ERRORS")

    alc.log("info", string.format(
        "faithful: verification complete — errors found: %s",
        tostring(has_errors)
    ))

    -- ─── Step 4: Final grounded answer ───
    alc.log("info", "faithful: Step 4 — producing grounded answer")

    local final_answer = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Reasoning:\n\"\"\"\n%s\n\"\"\"\n\n"
                .. "Formal verification result:\n\"\"\"\n%s\n\"\"\"\n\n"
                .. "Based on the formal verification, provide the final "
                .. "correct answer. If the verification found errors, "
                .. "use the corrected result. Be clear and concise.",
            task, nl_reasoning, verification
        ),
        {
            system = "You are an expert. Ground your answer in the formal "
                .. "verification results. If errors were found in the original "
                .. "reasoning, use the corrected version.",
            max_tokens = 300,
        }
    )

    ctx.result = {
        answer = final_answer,
        format = format,
        nl_reasoning = nl_reasoning,
        formal = formal,
        verification = verification,
        errors_found = has_errors,
    }
    return ctx
end

-- Malli-style self-decoration (see alc_shapes/README). inline T.shape
-- for both input and result; wrapper validates in ALC_SHAPE_CHECK=1.
M.run = S.instrument(M, "run")

return M
