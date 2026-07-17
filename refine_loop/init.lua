--- refine_loop(RefineLoop) — reflective refinement loop for 26-generation models
---
--- A boost strategy that iterates draft -> reflection -> revise until the
--- reflection stage signals acceptance or an iteration cap is reached. It is a
--- single-strategy distillation of GEPA-style reflective refinement: linguistic
--- self-reflection carries denser learning signal than a sparse scalar reward,
--- which makes each round more sample-efficient than reward-only tuning.
---
--- ## Usage
---
--- ```lua
--- local refine_loop = require("refine_loop")
--- return refine_loop.run({ task = "Explain CAP theorem tradeoffs." })
--- ```
---
--- ## Algorithm
---
--- 1. **Draft** — one `alc.llm` pass produces the initial answer.
--- 2. **Reflection** — one `alc.llm` pass critiques the current draft against
---    the rubric (and, on the first round only, any external eval feedback). If
---    the draft fully satisfies the rubric the reflection returns the literal
---    ASCII marker `ACCEPT`, which triggers early-stop (no revise that round).
--- 3. **Revise** — when the reflection did not accept, one `alc.llm` pass
---    rewrites the draft addressing the critique. Steps 2-3 repeat up to
---    `max_iterations` times.
---
--- ## API
---
--- - `ctx.task`           — string, required. Empty / whitespace-only → error.
--- - `ctx.max_iterations` — number, optional. Max reflection→revise cycles
---   (default 2).
--- - `ctx.rubric`         — string, optional. Critique criteria injected verbatim
---   into every reflection prompt. Omitted → a generic quality rubric.
--- - `ctx.feedback`       — string, optional. External eval feedback injected
---   into the FIRST reflection prompt only (eval-driven refinement v0 hook).
---
--- Result (`ctx.result`):
--- - `final`           — string, the final (possibly revised) answer.
--- - `iterations_used` — number, how many reflection rounds ran.
--- - `accepted`        — boolean, whether a reflection returned `ACCEPT`.
--- - `history`         — table `{ draft = string, iterations = [ { index,
---   reflection, revision?, accepted } ] }` recording every stage.
---
--- ## Comparison with related packages
---
--- vs `reflect` (SelfRefine, Madaan 2023): `reflect` critiques with a
--- convergence marker (`NO_MAJOR_ISSUES`) and no external-signal hook. This
--- package adds a rubric-driven reflection prompt plus a `ctx.feedback` channel
--- so an external evaluator's verdict can steer the first reflection — the GEPA
--- direction of feeding textual eval feedback back into refinement.
---
--- ## References
---
--- - Agrawal et al. (2025). "GEPA: Reflective Prompt Evolution Can Outperform
---   Reinforcement Learning." arXiv:2507.19457.

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "refine_loop",
    version = "0.1.0",
    description = "Reflective draft-reflect-revise loop with rubric and external-feedback hooks",
    category = "refinement",
    alc_shapes_compat = "^0.25",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task = T.string:describe("The task to refine (required, non-empty)"),
                max_iterations = T.number:is_optional()
                    :describe("Maximum reflection->revise cycles (default: 2)"),
                rubric = T.string:is_optional()
                    :describe("Critique criteria injected into every reflection prompt "
                        .. "(default: generic quality rubric)"),
                feedback = T.string:is_optional()
                    :describe("External eval feedback injected into the first reflection "
                        .. "prompt only (eval-driven refinement hook)"),
            }),
            result = T.shape({
                final = T.string:describe("Final (possibly revised) answer"),
                iterations_used = T.number:describe("Number of reflection rounds executed"),
                accepted = T.boolean:describe("True if a reflection returned the ACCEPT marker"),
                history = T.shape({
                    draft = T.string:describe("The initial draft"),
                    iterations = T.array_of(T.shape({
                        index = T.number:describe("1-based round index"),
                        reflection = T.string:describe("Reflection/critique text for the round"),
                        revision = T.string:is_optional()
                            :describe("Revised draft (absent when the round accepted)"),
                        accepted = T.boolean:describe("True if this round's reflection accepted"),
                    })):describe("Ordered refinement rounds"),
                }):describe("Full record of draft and each reflection/revision"),
            }),
        },
    },
}

--- Default rubric used when the caller omits `ctx.rubric`.
local DEFAULT_RUBRIC =
    "Correctness and factual accuracy; completeness relative to the task; "
    .. "clarity and directness; absence of unsupported or fabricated claims."

--- Literal ASCII marker the reflection stage emits to signal acceptance.
--- ASCII only: Lua string.match is byte-oriented, so multibyte markers can
--- break silently inside character classes.
local ACCEPT_MARKER = "ACCEPT"

--- Trim leading/trailing whitespace from a string (nil-safe).
local function trim(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- True if the reflection is the standalone ACCEPT marker.
--- The reflection prompt asks for "the single word ACCEPT and nothing else",
--- so acceptance requires the whole (trimmed) response to be the marker
--- (a trailing period is tolerated). A plain substring match is wrong here:
--- critiques like "Not ACCEPT — issues: ..." contain the marker and would be
--- misread as acceptance, silently disabling the revision loop.
local function is_accepted(reflection)
    local body = trim(reflection)
    return body == ACCEPT_MARKER or body == ACCEPT_MARKER .. "."
end

--- Build the reflection (critique) prompt. `feedback` is injected only when
--- non-empty (the caller passes it on the first round only).
local function build_reflection_prompt(task, draft, rubric, feedback)
    local p = string.format(
        "Task: %s\n\n"
            .. "Current draft:\n%s\n\n"
            .. "Rubric (critique criteria):\n%s\n\n",
        task, draft, rubric
    )
    if feedback and feedback ~= "" then
        p = p .. string.format("External evaluation feedback to address:\n%s\n\n", feedback)
    end
    p = p
        .. "Critique the draft strictly against the rubric. If it fully satisfies "
        .. "the rubric and needs no further revision, respond with the single word "
        .. ACCEPT_MARKER
        .. " and nothing else. Otherwise, list the concrete improvements required."
    return p
end

--- Build the revise prompt for a round that did not accept.
local function build_revise_prompt(task, draft, reflection)
    return string.format(
        "Task: %s\n\n"
            .. "Previous draft:\n%s\n\n"
            .. "Critique:\n%s\n\n"
            .. "Revise the draft to address EVERY point in the critique while "
            .. "preserving what was already strong. Return only the revised answer.",
        task, draft, reflection
    )
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task
    if type(task) ~= "string" or task:match("^%s*$") then
        error("ctx.task is required (non-empty string)")
    end
    local max_iterations = ctx.max_iterations or 2
    local rubric = ctx.rubric or DEFAULT_RUBRIC
    local feedback = ctx.feedback
    local draft_tokens = ctx.draft_tokens or 500
    local revise_tokens = ctx.revise_tokens or 500
    local reflect_tokens = ctx.reflect_tokens or 300

    -- Phase 1: initial draft.
    local draft = alc.llm(
        string.format("Task: %s\n\nProvide a thorough, high-quality response.", task),
        {
            system = "You are an expert. Produce a complete, self-contained answer.",
            max_tokens = draft_tokens,
        }
    )

    local history = { draft = draft, iterations = {} }
    local accepted = false
    local iterations_used = 0

    for i = 1, max_iterations do
        -- Reflection: rubric every round, feedback on the first round only.
        local round_feedback = (i == 1) and feedback or nil
        local reflection = alc.llm(
            build_reflection_prompt(task, draft, rubric, round_feedback),
            {
                system = "You are a rigorous critic. Judge strictly against the rubric. "
                    .. "Do not be lenient.",
                max_tokens = reflect_tokens,
            }
        )
        iterations_used = i

        local round_accepted = is_accepted(reflection)
        local round = {
            index = i,
            reflection = reflection,
            accepted = round_accepted,
        }

        if round_accepted then
            accepted = true
            history.iterations[i] = round
            if alc.log then
                alc.log("info", string.format("refine_loop: accepted at round %d", i))
            end
            break
        end

        -- Revise (only when not accepted).
        draft = alc.llm(
            build_revise_prompt(task, draft, reflection),
            {
                system = "You are an expert reviser. Address every critique point "
                    .. "while keeping the original strengths.",
                max_tokens = revise_tokens,
            }
        )
        round.revision = draft
        history.iterations[i] = round
    end

    ctx.result = {
        final = draft,
        iterations_used = iterations_used,
        accepted = accepted,
        history = history,
    }
    return ctx
end

-- ─── Test hooks ───
M._internal = {
    trim = trim,
    is_accepted = is_accepted,
    build_reflection_prompt = build_reflection_prompt,
    build_revise_prompt = build_revise_prompt,
    DEFAULT_RUBRIC = DEFAULT_RUBRIC,
    ACCEPT_MARKER = ACCEPT_MARKER,
}

-- Malli-style self-decoration: wrapper asserts input/result against
-- M.spec.entries.run shapes when ALC_SHAPE_CHECK=1 (passthrough otherwise).
M.run = S.instrument(M, "run")

return M
