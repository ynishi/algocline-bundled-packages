--- critic — Rubric-based structured evaluation and targeted revision
---
--- Unlike reflect (freeform self-critique), critic evaluates on predefined
--- rubric dimensions (accuracy, logic, completeness, etc.), assigns per-
--- dimension scores, generates targeted feedback, and revises only the
--- weakest areas. Produces a structured quality profile.
---
--- Based on: "Judging LLM-as-a-Judge with MT-Bench and Chatbot Arena"
---            (Zheng et al., arXiv 2306.05685, 2023)
---            + rubric-based evaluation methodology from education research
---
--- Pipeline:
---   Step 1: generate  — produce initial answer
---   Step 2: evaluate  — score each rubric dimension independently
---   Step 3: revise    — targeted revision of dimensions below threshold
---   Step 4: re-score  — verify improvement (optional)
---
--- Usage:
---   local critic = require("critic")
---   return critic.run(ctx)
---
--- ctx.task (required): The task/question to solve
--- ctx.answer: Pre-supplied answer to evaluate (default: nil → auto-generate)
--- ctx.rubric: Table of dimension names (default: see DEFAULT_RUBRIC)
--- ctx.threshold: Minimum acceptable score per dimension (default: 7)
--- ctx.max_revisions: Maximum revision rounds (default: 2)
--- ctx.gen_tokens: Max tokens for generation (default: 600)
--- ctx.eval_tokens: Max tokens per dimension evaluation (default: 200)
--- ctx.revise_tokens: Max tokens for revision (default: 600)

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "critic",
    version = "0.1.0",
    description = "Rubric-based structured evaluation — per-dimension scoring with targeted revision of weak areas",
    category = "evaluation",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task           = T.string:describe("The task/question to solve"),
                answer         = T.string:is_optional():describe("Pre-supplied answer to evaluate (default: nil → auto-generate)"),
                rubric         = T.any:is_optional():describe("List of dimensions — either string names or {name, description} tables"),
                threshold      = T.number:is_optional():describe("Minimum acceptable per-dimension score (default: 7)"),
                max_revisions  = T.number:is_optional():describe("Max revision rounds (default: 2)"),
                gen_tokens     = T.number:is_optional():describe("Max tokens for initial generation (default: 600)"),
                eval_tokens    = T.number:is_optional():describe("Max tokens per dimension evaluation (default: 200)"),
                revise_tokens  = T.number:is_optional():describe("Max tokens for revision (default: 600)"),
            }),
            result = T.shape({
                answer         = T.string:describe("Final (possibly revised) answer"),
                initial_answer = T.string:describe("Initial answer before any revisions"),
                scores         = T.table:describe("Final per-dimension score map (dim_name → number)"),
                avg_score      = T.number:describe("Average of final per-dimension scores"),
                revisions      = T.number:describe("Number of revision rounds actually performed"),
                history        = T.array_of(T.shape({
                    round      = T.number:describe("0-based round index (0 = initial evaluation)"),
                    answer     = T.string:describe("Answer evaluated in this round"),
                    scores     = T.array_of(T.shape({
                        dimension = T.string:describe("Rubric dimension name"),
                        score     = T.number:describe("Per-dimension score (1-10)"),
                        feedback  = T.string:describe("Parsed feedback for this dimension"),
                        raw       = T.string:describe("Raw evaluator output"),
                    })):describe("Per-dimension evaluation records"),
                    avg_score  = T.number:describe("Round average score"),
                    weak_count = T.number:describe("Dimensions below threshold this round"),
                })):describe("Per-round evaluation trace"),
                rubric         = T.array_of(T.shape({
                    name        = T.string:describe("Dimension name"),
                    description = T.string:describe("Dimension description (mirrors name when raw string rubric provided)"),
                })):describe("Normalized rubric used for evaluation"),
                threshold      = T.number:describe("Threshold value used (echoed from input)"),
            }),
        },
    },
}

local DEFAULT_RUBRIC = {
    { name = "accuracy", description = "Factual correctness of all claims" },
    { name = "logic", description = "Logical coherence and valid reasoning" },
    { name = "completeness", description = "Coverage of all relevant aspects" },
    { name = "clarity", description = "Clear, well-organized presentation" },
    { name = "nuance", description = "Appropriate caveats, edge cases, and limitations" },
}

--- Parse score from dimension evaluation.
--- Expects "SCORE: N/10" pattern.
local function parse_score(text)
    local lower = text:lower()
    local score = tonumber(lower:match("score:%s*(%d+)"))
    if score then
        return math.max(1, math.min(10, score))
    end
    -- Fallback: any N/10 pattern
    local n = tonumber(text:match("(%d+)/10"))
    if n then
        return math.max(1, math.min(10, n))
    end
    return 5  -- Default: middling
end

--- Parse feedback text from evaluation.
local function parse_feedback(text)
    local feedback = text:match("[Ff]eedback:%s*(.-)$")
        or text:match("[Ww]eakness[es]*:%s*(.-)$")
        or text:match("\n(.+)$")
        or ""
    return feedback:match("^%s*(.-)%s*$") or ""
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local rubric = ctx.rubric or DEFAULT_RUBRIC
    local threshold = ctx.threshold or 7
    local max_revisions = ctx.max_revisions or 2
    local gen_tokens = ctx.gen_tokens or 600
    local eval_tokens = ctx.eval_tokens or 200
    local revise_tokens = ctx.revise_tokens or 600

    -- Normalize rubric: accept string list or table list
    local dimensions = {}
    for _, dim in ipairs(rubric) do
        if type(dim) == "string" then
            dimensions[#dimensions + 1] = { name = dim, description = dim }
        else
            dimensions[#dimensions + 1] = dim
        end
    end

    -- ─── Step 1: Generate initial answer ───
    local answer = ctx.answer
    if not answer then
        answer = alc.llm(
            string.format(
                "Task: %s\n\nProvide a thorough, well-reasoned answer.",
                task
            ),
            {
                system = "You are an expert. Provide a comprehensive, accurate answer.",
                max_tokens = gen_tokens,
            }
        )
        alc.log("info", string.format(
            "critic: generated initial answer (%d chars)", #answer
        ))
    end

    local revision_history = {}
    local current_answer = answer

    for revision = 0, max_revisions do
        -- ─── Step 2: Evaluate each dimension ───
        alc.log("info", string.format(
            "critic: evaluating %d dimensions (round %d)", #dimensions, revision
        ))

        local evaluations = alc.map(dimensions, function(dim)
            return alc.llm(
                string.format(
                    "Task: %s\n\n"
                        .. "Answer to evaluate:\n\"\"\"\n%s\n\"\"\"\n\n"
                        .. "Evaluate this answer on the dimension: **%s**\n"
                        .. "(%s)\n\n"
                        .. "Provide:\n"
                        .. "SCORE: [1-10] (1=terrible, 10=excellent)\n"
                        .. "FEEDBACK: [specific strengths and weaknesses on this dimension]",
                    task, current_answer, dim.name, dim.description
                ),
                {
                    system = string.format(
                        "You are an expert evaluator assessing the '%s' dimension. "
                            .. "Be rigorous and specific. Score honestly — reserve 9-10 "
                            .. "for genuinely excellent work. Provide actionable feedback.",
                        dim.name
                    ),
                    max_tokens = eval_tokens,
                }
            )
        end)

        -- Parse evaluation results
        local scores = {}
        local weak_dimensions = {}
        local total_score = 0

        for i, raw in ipairs(evaluations) do
            local score = parse_score(raw)
            local feedback = parse_feedback(raw)

            scores[#scores + 1] = {
                dimension = dimensions[i].name,
                score = score,
                feedback = feedback,
                raw = raw,
            }

            total_score = total_score + score

            if score < threshold then
                weak_dimensions[#weak_dimensions + 1] = {
                    dimension = dimensions[i].name,
                    description = dimensions[i].description,
                    score = score,
                    feedback = feedback,
                }
            end
        end

        local avg_score = total_score / #dimensions

        revision_history[#revision_history + 1] = {
            round = revision,
            answer = current_answer,
            scores = scores,
            avg_score = avg_score,
            weak_count = #weak_dimensions,
        }

        alc.log("info", string.format(
            "critic: round %d — avg=%.1f, %d/%d below threshold (%d)",
            revision, avg_score, #weak_dimensions, #dimensions, threshold
        ))

        -- ─── Step 3: Revise if weak dimensions exist ───
        if #weak_dimensions == 0 or revision >= max_revisions then
            if #weak_dimensions == 0 then
                alc.log("info", "critic: all dimensions above threshold, stopping")
            else
                alc.log("info", string.format(
                    "critic: max revisions reached (%d), stopping", max_revisions
                ))
            end
            break
        end

        -- Build targeted revision prompt
        local weakness_list = {}
        for _, w in ipairs(weak_dimensions) do
            weakness_list[#weakness_list + 1] = string.format(
                "- **%s** (score: %d/10): %s",
                w.dimension, w.score, w.feedback
            )
        end

        alc.log("info", string.format(
            "critic: revising %d weak dimensions", #weak_dimensions
        ))

        current_answer = alc.llm(
            string.format(
                "Task: %s\n\n"
                    .. "Current answer:\n\"\"\"\n%s\n\"\"\"\n\n"
                    .. "The following dimensions scored below %d/10:\n\n%s\n\n"
                    .. "Revise the answer to specifically address these weaknesses. "
                    .. "Improve the weak areas while preserving the strengths.",
                task, current_answer, threshold,
                table.concat(weakness_list, "\n")
            ),
            {
                system = "You are an expert reviser. Focus specifically on the "
                    .. "identified weak dimensions. Make targeted improvements "
                    .. "without degrading areas that scored well.",
                max_tokens = revise_tokens,
            }
        )
    end

    -- Build final score summary
    local final_round = revision_history[#revision_history]
    local score_summary = {}
    for _, s in ipairs(final_round.scores) do
        score_summary[s.dimension] = s.score
    end

    ctx.result = {
        answer = current_answer,
        initial_answer = answer,
        scores = score_summary,
        avg_score = final_round.avg_score,
        revisions = #revision_history - 1,
        history = revision_history,
        rubric = dimensions,
        threshold = threshold,
    }
    return ctx
end

-- Malli-style self-decoration (see alc_shapes/README). inline T.shape
-- for both input and result; wrapper validates in ALC_SHAPE_CHECK=1.
M.run = S.instrument(M, "run")

return M
