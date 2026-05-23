--- propose_verify — 2-call Propose → Verify Strategy
---
--- Generates a candidate answer (propose call), then runs an independent
--- LLM verifier that returns an accept/reject verdict with a confidence
--- score (verify call). Total LLM calls: exactly 2.
---
--- ## Usage
---
--- ```lua
--- local pv = require("propose_verify")
--- return pv.run(ctx)
--- ```
---
--- ## Helpers
---
--- ```lua
--- -- Build the propose prompt only (pure, no LLM):
--- local prompt = pv.build_propose_prompt(task, proposer_hint)
---
--- -- Build the verify prompt only (pure, no LLM):
--- local vp = pv.build_verify_prompt(task, candidate, verifier_hint)
---
--- -- Parse verifier text into structured verdict (pure, no LLM):
--- local verdict = pv.parse_verify(text)
--- -- verdict = { accept: bool, score: number 0..1, rationale: string }
--- ```
---
--- ## Narrative
---
--- propose_verify implements the two-role Propose-then-Verify primitive
--- that underpins large-scale LLM self-improvement research. The proposer
--- generates a candidate answer at creative temperature; the verifier
--- scores it with deterministic temperature and emits an accept/reject
--- verdict with a numeric confidence score. The score threshold is
--- caller-required (no default) — the caller decides what "good enough"
--- means for their domain. The verdict string is compatible with
--- swarm_frame parse_verdict conventions for aggregation in multi-agent
--- pipelines, but swarm_frame is not a dependency.
---
--- ## Entry contract
---
--- - `build_propose_prompt(task, proposer_hint?)` — pure, returns the
---   proposer prompt string. No LLM call.
--- - `build_verify_prompt(task, candidate, verifier_hint?)` — pure,
---   returns the verifier prompt string. No LLM call.
--- - `parse_verify(text)` — pure, parses verifier LLM output into
---   `{ accept, score, rationale }`. No LLM call.
--- - `run(ctx)` — Strategy entry, ctx-threading. Issues exactly 2
---   `alc.llm` calls (propose → verify) and returns the structured
---   result.
---
--- ## Caveats
---
--- ### Required ctx fields
---
--- - `task` (string) — the question or task to solve. The implementation
---   falls back through `ctx.task → ctx.text → ctx.idea → ctx.question`
---   so callers wired to any of the common field names work without
---   changes.
--- - `score_threshold` (number, 0..1) — the minimum verifier score for
---   the verdict to be "accepted". No default is provided because the
---   acceptance bar is domain-specific: a math problem might need 0.95
---   while a creative-writing rewrite might want 0.5. Caller must inject
---   this value.
---
--- ### Optional ctx fields
---
--- - `proposer_hint` (string) — extra instruction appended to the
---   proposer prompt (e.g. "answer in one sentence"). Injects domain
---   guidance without replacing the base template.
--- - `verifier_hint` (string) — extra instruction appended to the
---   verifier prompt (e.g. "focus on factual accuracy"). Same shape as
---   proposer_hint for the verify call.
--- - `propose_temperature` (number, default 0.7) — temperature for the
---   propose call. The default 0.7 is the industry-standard
---   creative-generation default cited by OpenAI / Anthropic
---   documentation; overriding away from 0.7 removes that creative-
---   diversity baseline.
--- - `verify_temperature` (number, default 0.0) — temperature for the
---   verify call. The default 0.0 is the industry-standard deterministic
---   judgment baseline used by scorers and classifiers; overriding above
---   zero makes the verdict non-deterministic across re-runs.
---
--- ### Why no `score_threshold` default
---
--- An accept/reject bar is intrinsically domain-specific (mathematical
--- correctness vs creative quality vs factual recall each warrant
--- different cutoffs). Picking a single library-wide default would
--- silently misclassify cases for most callers; requiring it forces the
--- caller to make a conscious choice.
---
--- ### Why no `swarm_frame` dependency
---
--- The verdict string `"DONE path=accepted | rejected"` is compatible
--- with `swarm_frame.parse_verdict` so callers that aggregate with
--- swarm_frame can consume it directly, but the pkg itself stays
--- single-shot to keep the dependency surface minimal.
---
--- ## References
---
--- - Cobbe et al. (2021). "Training Verifiers to Solve Math Word
---   Problems", arXiv:2110.14168 §3 — verifier prompt pattern (industry-
---   standard verifier-prompt formulation).
--- - Zhou et al. (2023). "Language Agent Tree Search Unifies Reasoning,
---   Acting, and Planning in Language Models" (LATS), arXiv:2309.08987
---   §3.2 — node-scoring rationale (industry adoption of independent
---   verifier scoring at planning nodes).
--- - ReAct-style propose/verify caller patterns — widely-cited tool-use
---   convention that pairs a candidate generator with an independent
---   verifier step.

local M = {}

---@type AlcMeta
M.meta = {
    name        = "propose_verify",
    version     = "0.1.0",
    description = "2-call Propose→Verify Strategy: propose a candidate answer then verify it with a scored accept/reject verdict",
    category    = "validation",
    alc_shapes_compat = "^0.25",
}

-- ─── Defaults ────────────────────────────────────────────────────────────────

--- (I) industry standard creative generation temperature
local DEFAULT_PROPOSE_TEMP = 0.7
--- (I) industry standard deterministic judgment temperature
local DEFAULT_VERIFY_TEMP  = 0.0

-- ─── Pure helpers ────────────────────────────────────────────────────────────

--- Build the proposer prompt.
--- Pure function — no LLM call, no side effects.
---@param task string  The question / task to solve
---@param proposer_hint string|nil  Optional extra instruction for the proposer
---@return string
function M.build_propose_prompt(task, proposer_hint)
    local base = string.format(
        "Task: %s\n\nThink step by step and produce the best answer you can.",
        task
    )
    if proposer_hint and #proposer_hint > 0 then
        base = base .. string.format("\n\nAdditional guidance: %s", proposer_hint)
    end
    return base
end

--- Build the verifier prompt.
--- Pure function — no LLM call, no side effects.
--- Verifier prompt pattern follows Cobbe et al. 2021 §3 (industry-
--- standard verifier-prompt format): present the task and candidate,
--- ask for correctness judgment + score.
---@param task string         The original task
---@param candidate string    The proposed candidate answer
---@param verifier_hint string|nil  Optional extra instruction for the verifier
---@return string
function M.build_verify_prompt(task, candidate, verifier_hint)
    local base = string.format(
        "Task: %s\n\n"
            .. "Candidate answer:\n\"\"\"\n%s\n\"\"\"\n\n"
            .. "Evaluate the candidate answer:\n"
            .. "1. Is it correct and complete? (yes/no)\n"
            .. "2. Confidence score: a number between 0.0 (wrong) and 1.0 (perfect).\n"
            .. "3. Brief rationale (one or two sentences).\n\n"
            .. "Respond in this exact format:\n"
            .. "ACCEPT: yes|no\n"
            .. "SCORE: <0.0..1.0>\n"
            .. "RATIONALE: <text>",
        task, candidate
    )
    if verifier_hint and #verifier_hint > 0 then
        base = base .. string.format("\n\nAdditional guidance: %s", verifier_hint)
    end
    return base
end

--- Parse verifier output into a structured verdict.
--- Pure function — no LLM call, no side effects.
--- Handles malformed output gracefully (returns accept=false, score=0).
--- Citation: Cobbe et al. 2021 §3 verifier prompt pattern (industry-
--- standard ACCEPT/SCORE/RATIONALE shape).
---@param text string  Raw verifier LLM output
---@return table  { accept: bool, score: number, rationale: string }
function M.parse_verify(text)
    -- Extract ACCEPT field (case-insensitive)
    local accept_raw = text:match("[Aa][Cc][Cc][Ee][Pp][Tt]%s*:%s*(%S+)")
    local accept = false
    if accept_raw then
        accept = (accept_raw:lower() == "yes"
               or accept_raw:lower() == "true"
               or accept_raw:lower() == "1")
    end

    -- Extract SCORE field (float 0..1)
    local score_raw = text:match("[Ss][Cc][Oo][Rr][Ee]%s*:%s*([%d%.]+)")
    local score = 0.0
    if score_raw then
        local n = tonumber(score_raw)
        if n then
            -- Clamp to [0, 1]
            score = math.max(0.0, math.min(1.0, n))
        end
    end

    -- Extract RATIONALE field (remainder of that line)
    local rationale = text:match("[Rr][Aa][Tt][Ii][Oo][Nn][Aa][Ll][Ee]%s*:%s*(.-)%s*$")
    if not rationale or #rationale == 0 then
        rationale = "No rationale provided."
    end

    return { accept = accept, score = score, rationale = rationale }
end

-- ─── Strategy entry ──────────────────────────────────────────────────────────

--- Run the 2-call propose→verify cycle.
--- Returns structured result with verdict string compatible with
--- swarm_frame parse_verdict conventions.
---@param ctx table  AlcCtx. Required: task (or text/idea/question fallback),
---                  score_threshold. Optional: proposer_hint, verifier_hint,
---                  propose_temperature, verify_temperature.
---@return table  Updated ctx with ctx.result set.
function M.run(ctx)
    -- Task fallback chain
    local task = ctx.task or ctx.text or ctx.idea or ctx.question
    if not task or #task == 0 then
        error("propose_verify: ctx.task (or ctx.text/idea/question) is required")
    end

    -- score_threshold is REQUIRED — no default (X)
    local threshold = ctx.score_threshold
    if threshold == nil then
        error("propose_verify: ctx.score_threshold is required (no default — caller must supply)")
    end

    local propose_temp = ctx.propose_temperature or DEFAULT_PROPOSE_TEMP
    local verify_temp  = ctx.verify_temperature  or DEFAULT_VERIFY_TEMP

    -- ── Call 1: Propose ──────────────────────────────────────────────────────
    local propose_prompt = M.build_propose_prompt(task, ctx.proposer_hint)

    local candidate = alc.llm(propose_prompt, {
        system      = "You are an expert. Provide a clear, accurate, well-reasoned answer.",
        temperature = propose_temp,
        max_tokens  = 600,
    })

    -- ── Call 2: Verify ───────────────────────────────────────────────────────
    local verify_prompt = M.build_verify_prompt(task, candidate, ctx.verifier_hint)

    local verify_raw = alc.llm(verify_prompt, {
        system      = "You are a rigorous evaluator. Judge the candidate answer strictly and objectively.",
        temperature = verify_temp,
        max_tokens  = 300,
    })

    -- ── Parse verdict ────────────────────────────────────────────────────────
    local parsed = M.parse_verify(verify_raw)

    -- Accept only if both the verifier says accept AND score >= threshold
    local final_accept = parsed.accept and (parsed.score >= threshold)
    local verdict = final_accept
        and "DONE path=accepted"
        or  "DONE path=rejected"

    ctx.result = {
        answer          = candidate,
        score           = parsed.score,
        rationale       = parsed.rationale,
        total_llm_calls = 2,
        verdict         = verdict,
    }
    return ctx
end

return M
