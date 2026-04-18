--- bot — Buffer of Thoughts: template-based meta-reasoning
---
--- Identifies the problem type, retrieves an appropriate thought template
--- (structured reasoning pattern), instantiates it for the specific problem,
--- then verifies the result. Efficient because it leverages pre-defined
--- reasoning patterns rather than discovering them from scratch each time.
---
--- Based on: Yang et al., "Buffer of Thoughts: Thought-Augmented Reasoning
--- with Large Language Models" (2024, arXiv:2406.04271)
---
--- Pipeline (3-4 LLM calls):
---   Step 1: Distill  — identify problem type and retrieve thought template
---   Step 2: Instantiate — apply template to the specific problem
---   Step 3: Verify   — check the instantiated reasoning
---   Step 4: Answer   — produce final answer (merged with Step 3 if clean)
---
--- Usage:
---   local bot = require("bot")
---   return bot.run(ctx)
---
--- ctx.task (required): The problem to solve
--- ctx.templates: Custom template library (optional; uses built-in if absent)
--- ctx.gen_tokens: Max tokens per step (default: 500)

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "bot",
    version = "0.1.0",
    description = "Buffer of Thoughts — identify problem type, apply thought template, verify",
    category = "reasoning",
}

local template_shape = T.shape({
    name    = T.string:describe("Human-readable template title (e.g., 'Arithmetic / Calculation')"),
    pattern = T.string:describe("Numbered reasoning steps that structure the instantiate phase"),
})

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task       = T.string:describe("Problem to solve (required)"),
                templates  = T.map_of(T.string, template_shape):is_optional()
                    :describe("Custom template_key → {name, pattern} map; defaults to built-in TEMPLATES"),
                gen_tokens = T.number:is_optional():describe("Max tokens per instantiate / verify step (default 500)"),
            }),
            result = T.shape({
                answer                 = T.string
                    :describe("Final answer extracted from the verification LLM output (falls back to full verification text)"),
                template_key           = T.string
                    :describe("Selected template key; 'analytical' is used as a fallback when parsing fails"),
                template_name          = T.string:describe("Display name of the selected template"),
                template_pattern       = T.string:describe("Reasoning steps of the selected template"),
                instantiated_reasoning = T.string:describe("LLM output from Step 2 (template applied to the specific task)"),
                verification           = T.string:describe("Full Step-3 verification text including ERRORS: and FINAL ANSWER: sections"),
                errors_found           = T.boolean
                    :describe("True when verification did not emit ERRORS: NONE (or NO ERRORS) — i.e., errors were reported"),
            }),
        },
    },
}

--- Built-in thought template library.
--- Each template defines a structured reasoning pattern for a problem class.
local TEMPLATES = {
    arithmetic = {
        name = "Arithmetic / Calculation",
        pattern = "1. Identify all quantities and their relationships\n"
            .. "2. Set up equations or formulas\n"
            .. "3. Perform calculations step by step (show intermediate results)\n"
            .. "4. Verify by substitution or estimation\n"
            .. "5. State the numerical answer with units",
    },
    logic = {
        name = "Logical Reasoning / Deduction",
        pattern = "1. List all premises and given conditions\n"
            .. "2. Identify what needs to be proven or determined\n"
            .. "3. Apply logical rules (modus ponens, contrapositive, etc.)\n"
            .. "4. Chain deductions step by step\n"
            .. "5. Check for hidden assumptions or fallacies\n"
            .. "6. State the conclusion",
    },
    causal = {
        name = "Causal Analysis / Why Questions",
        pattern = "1. Identify the effect to be explained\n"
            .. "2. List candidate causes\n"
            .. "3. For each cause, evaluate: mechanism, evidence, alternatives\n"
            .. "4. Distinguish correlation from causation\n"
            .. "5. Identify the most likely causal chain\n"
            .. "6. Note confounding factors and uncertainty",
    },
    comparison = {
        name = "Comparison / Decision Making",
        pattern = "1. Define the evaluation criteria\n"
            .. "2. Analyze each option against every criterion\n"
            .. "3. Identify trade-offs and deal-breakers\n"
            .. "4. Weight criteria by importance\n"
            .. "5. Synthesize the ranking with justification\n"
            .. "6. State the recommendation with caveats",
    },
    creative = {
        name = "Creative / Open-Ended Generation",
        pattern = "1. Understand the constraints and objectives\n"
            .. "2. Brainstorm diverse approaches (at least 3)\n"
            .. "3. Evaluate each approach for feasibility and quality\n"
            .. "4. Select and develop the best approach\n"
            .. "5. Refine: check for gaps, improve clarity\n"
            .. "6. Present the polished output",
    },
    analytical = {
        name = "Analysis / Explanation",
        pattern = "1. Define the subject and scope of analysis\n"
            .. "2. Break into components or dimensions\n"
            .. "3. Examine each component with evidence\n"
            .. "4. Identify patterns, connections, and tensions\n"
            .. "5. Synthesize findings into a coherent narrative\n"
            .. "6. State conclusions with confidence levels",
    },
    procedural = {
        name = "How-To / Procedural",
        pattern = "1. Identify the goal and prerequisites\n"
            .. "2. List the major phases or stages\n"
            .. "3. Detail each step within each phase\n"
            .. "4. Note decision points and alternatives\n"
            .. "5. Identify common pitfalls and how to avoid them\n"
            .. "6. Summarize the critical path",
    },
}

--- Build a concise template catalog string for LLM selection.
local function template_catalog(templates)
    local lines = {}
    for key, tmpl in pairs(templates) do
        lines[#lines + 1] = string.format("  %s: %s", key, tmpl.name)
    end
    table.sort(lines)
    return table.concat(lines, "\n")
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local templates = ctx.templates or TEMPLATES
    local gen_tokens = ctx.gen_tokens or 500

    -- ─── Step 1: Distill — identify problem type ───
    alc.log("info", "bot: Step 1 — identifying problem type")

    local catalog = template_catalog(templates)

    local classification = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Classify this task into ONE of the following problem types:\n%s\n\n"
                .. "Reply with ONLY the type key (e.g., 'arithmetic', 'logic', etc.).\n"
                .. "If none fits well, reply with the closest match.",
            task, catalog
        ),
        {
            system = "You are a problem classifier. Output only the type key.",
            max_tokens = 20,
        }
    )

    -- Parse the selected template key
    local selected_key = nil
    local lower = classification:lower():match("%a+")
    if lower and templates[lower] then
        selected_key = lower
    else
        -- Fuzzy match: find key that appears in the response
        for key, _ in pairs(templates) do
            if classification:lower():match(key) then
                selected_key = key
                break
            end
        end
    end

    -- Fallback to analytical if no match
    if not selected_key then
        selected_key = "analytical"
        alc.log("warn", string.format(
            "bot: could not parse template key from '%s', defaulting to 'analytical'",
            classification
        ))
    end

    local template = templates[selected_key]

    alc.log("info", string.format(
        "bot: problem type identified as '%s' (%s)",
        selected_key, template.name
    ))

    -- ─── Step 2: Instantiate — apply template to problem ───
    alc.log("info", "bot: Step 2 — instantiating thought template")

    local instantiated = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Follow this structured reasoning template:\n\n%s\n\n"
                .. "Apply each step of this template to the specific task above. "
                .. "Show your work for every step. Do not skip any step.",
            task, template.pattern
        ),
        {
            system = "You are a methodical reasoner. Follow the template precisely. "
                .. "Show concrete work for each numbered step.",
            max_tokens = gen_tokens,
        }
    )

    -- ─── Step 3: Verify ───
    alc.log("info", "bot: Step 3 — verifying reasoning")

    local verification = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Reasoning template used: %s\n\n"
                .. "Reasoning:\n\"\"\"\n%s\n\"\"\"\n\n"
                .. "Verify this reasoning:\n"
                .. "1. Was each template step followed correctly?\n"
                .. "2. Are there any logical errors or incorrect facts?\n"
                .. "3. Is the conclusion well-supported by the steps?\n\n"
                .. "Then provide the FINAL ANSWER — either confirm the original "
                .. "conclusion or provide a corrected version.\n\n"
                .. "ERRORS: (list errors, or NONE)\n"
                .. "FINAL ANSWER: (the correct, complete answer)",
            task, template.name, instantiated
        ),
        {
            system = "You are a rigorous verifier. Check the reasoning against "
                .. "the template structure. Correct any errors found.",
            max_tokens = gen_tokens,
        }
    )

    -- Extract final answer from verification
    local final_answer = verification:match("FINAL ANSWER:%s*(.+)")
    if not final_answer or #final_answer == 0 then
        final_answer = verification
    end

    local has_errors = verification:upper():match("ERRORS:%s*NONE") == nil
        and not verification:upper():match("NO ERRORS")

    alc.log("info", string.format(
        "bot: complete — template='%s', errors_found=%s",
        selected_key, tostring(has_errors)
    ))

    ctx.result = {
        answer = final_answer,
        template_key = selected_key,
        template_name = template.name,
        template_pattern = template.pattern,
        instantiated_reasoning = instantiated,
        verification = verification,
        errors_found = has_errors,
    }
    return ctx
end

M.run = S.instrument(M, "run")

return M
