--- meta_prompt(Meta-Prompting) — orchestrator dispatches to specialist personas
---
--- A meta-orchestrator analyzes the task, identifies required expertise,
--- then sequentially delegates to specialist personas, collecting and
--- integrating their outputs into a unified final answer.
---
--- ## Usage
---
--- ```lua
--- local mp = require("meta_prompt")
--- return mp.run({ task = "Explain the implications of quantum entanglement" })
--- ```
---
--- ## Algorithm
---
--- Given a task, the pkg performs three phases:
---
--- 1. Orchestration — the meta-orchestrator identifies up to `max_experts`
---    specialist roles and formulates a focused question for each.
--- 2. Expert consultation — each specialist is queried sequentially,
---    receiving prior expert outputs as accumulated context.
--- 3. Synthesis — the meta-orchestrator integrates all expert analyses
---    into a single, conflict-resolved final answer.
---
--- ## Theoretical foundations
---
--- Based on Suzgun & Kalai (2024), Meta-Prompting frames the LLM as a
--- conductor that recruits specialist sub-agents from the same model.
--- The scaffolding is task-agnostic: no domain-specific prompts are
--- hard-coded. Performance gains arise from structured decomposition and
--- role-conditioned generation rather than from additional fine-tuning.
---
--- ## References
---
--- - Suzgun, M. & Kalai, A. T. (2024). "Meta-Prompting: Enhancing Language
---   Models with Task-Agnostic Scaffolding". arXiv:2401.12954.
---   https://arxiv.org/abs/2401.12954

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "meta_prompt",
    version = "0.1.0",
    description = "Meta-Prompting — orchestrator identifies and dispatches to specialist personas",
    category = "reasoning",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task        = T.string:describe("The problem to solve"),
                max_experts = T.number:is_optional():describe("Maximum number of expert consultations (default: 4)"),
            }),
            result = T.shape({
                answer            = T.string:describe("Orchestrator's integrated synthesis of all expert analyses"),
                experts_consulted = T.array_of(T.shape({
                    role     = T.string:describe("Expert role title assigned by the orchestrator"),
                    focus    = T.string:describe("Aspect of the task assigned to this expert"),
                    question = T.string:describe("Specific question posed to the expert"),
                    response = T.string:describe("Expert's analysis in response to the question"),
                })):describe("Sequential expert consultations with the question asked and the response received"),
                total_experts     = T.number:describe("Count of experts actually consulted (may be < max_experts due to parsing fallback)"),
            }),
        },
    },
}

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local max_experts = ctx.max_experts or 4

    -- Phase 1: Orchestrator analyzes the task and identifies required experts
    local analysis = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "As the META-ORCHESTRATOR, analyze this task and identify what specialized "
                .. "expertise is needed to solve it well.\n\n"
                .. "For each expert, specify:\n"
                .. "- Role: [specific expert title]\n"
                .. "- Focus: [what aspect they should address]\n"
                .. "- Question: [specific question to ask them]\n\n"
                .. "List up to %d experts, in the order they should be consulted.\n"
                .. "Format each as:\n"
                .. "EXPERT: [role] | FOCUS: [aspect] | QUESTION: [question]",
            task, max_experts
        ),
        {
            system = "You are a meta-orchestrator who plans problem-solving by identifying "
                .. "the right experts. Be specific about each expert's role and what to ask them.",
            max_tokens = 400,
        }
    )

    -- Parse expert specifications
    local experts = {}
    for line in analysis:gmatch("[^\n]+") do
        local role = line:match("EXPERT:%s*([^|]+)")
        local focus = line:match("FOCUS:%s*([^|]+)")
        local question = line:match("QUESTION:%s*(.+)")
        if role and focus and question then
            experts[#experts + 1] = {
                role = role:match("^%s*(.-)%s*$"),
                focus = focus:match("^%s*(.-)%s*$"),
                question = question:match("^%s*(.-)%s*$"),
            }
        end
    end

    -- Fallback: if parsing failed, create a single general expert
    if #experts == 0 then
        alc.log("warn", "meta_prompt: expert parsing failed, using general expert fallback")
        experts = { {
            role = "Domain Expert",
            focus = "Complete analysis",
            question = task,
        } }
    end

    alc.log("info", string.format("meta_prompt: identified %d experts", #experts))

    -- Phase 2: Consult each expert sequentially, building context
    local consultations = {}
    local accumulated = ""

    for i, expert in ipairs(experts) do
        local prior_context = ""
        if #consultations > 0 then
            prior_context = "Previous expert consultations:\n" .. accumulated .. "\n"
        end

        local response = alc.llm(
            string.format(
                "Original task: %s\n\n"
                    .. "%s"
                    .. "You are a %s.\n"
                    .. "Your focus area: %s\n\n"
                    .. "Question for you: %s\n\n"
                    .. "Provide your expert analysis.",
                task, prior_context, expert.role, expert.focus, expert.question
            ),
            {
                system = string.format(
                    "You are a %s with deep expertise. Provide precise, actionable analysis "
                        .. "within your area of focus. Reference prior expert inputs when relevant.",
                    expert.role
                ),
                max_tokens = 400,
            }
        )

        consultations[#consultations + 1] = {
            role = expert.role,
            focus = expert.focus,
            question = expert.question,
            response = response,
        }

        accumulated = accumulated .. string.format(
            "  [%s] %s\n", expert.role, response
        )
    end

    -- Phase 3: Orchestrator integrates all expert outputs
    local expert_summary = ""
    for i, c in ipairs(consultations) do
        expert_summary = expert_summary .. string.format(
            "Expert %d — %s:\n  Focus: %s\n  Analysis: %s\n\n",
            i, c.role, c.focus, c.response
        )
    end

    local synthesis = alc.llm(
        string.format(
            "Original task: %s\n\n"
                .. "Expert consultations:\n%s"
                .. "As the META-ORCHESTRATOR, integrate all expert analyses into a "
                .. "comprehensive final answer. Resolve any conflicts between experts. "
                .. "Ensure no key insight is lost.",
            task, expert_summary
        ),
        {
            system = "You are the meta-orchestrator. Synthesize expert inputs into a "
                .. "unified, actionable answer. Highlight where experts agree and resolve disagreements.",
            max_tokens = 600,
        }
    )

    ctx.result = {
        answer = synthesis,
        experts_consulted = consultations,
        total_experts = #consultations,
    }
    return ctx
end

-- Malli-style self-decoration (see alc_shapes/README). inline T.shape
-- for both input and result; wrapper validates in ALC_SHAPE_CHECK=1.
M.run = S.instrument(M, "run")

return M
