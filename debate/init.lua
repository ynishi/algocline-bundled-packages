--- debate(Debate) — adversarial two-debater protocol with a judge verdict
---
--- A multi-agent debate strategy in which two debaters argue for opposing
--- positions on a question, alternating for a fixed number of rounds, after
--- which a single judge reads the full transcript and issues a verdict. The
--- protocol operationalizes the "debate as truth amplification" hypothesis:
--- adversarial dialogue between capable arguers surfaces more truthful
--- signals than a single-model direct answer.
---
--- ## Usage
---
--- ```lua
--- local debate = require("debate")
--- return debate.run({
---     question = "Is the Riemann Hypothesis proven?",
---     position_a = "Argue YES / for the affirmative",
---     position_b = "Argue NO / for the negative",
--- })
--- ```
---
--- ## Algorithm
---
--- 1. **Debater A opens** (round 1) — one `alc.llm` pass produces A's opening
---    argument for `position_a`.
--- 2. **Debater B responds** (round 1) — one `alc.llm` pass produces B's
---    argument for `position_b`, seeing A's opening in the transcript.
--- 3. Steps 1-2 repeat for `rounds` (R) rounds. Each debater sees the full
---    prior transcript when composing its next turn (sequential dependency).
--- 4. **Judge verdict** — one `alc.llm` pass reads the full 2R-turn transcript
---    and emits `WINNER:` / `VERDICT:` / `RATIONALE:` markers under the
---    `judge_criteria` rubric.
---
--- Total `alc.llm` call budget: `2R + 1` (7 calls at R=3).
---
--- ## API
---
--- - `ctx.question`       — string, required. Empty / whitespace-only → error.
--- - `ctx.position_a`     — string, optional. Debater A's assigned stance
---   (default: affirmative placeholder).
--- - `ctx.position_b`     — string, optional. Debater B's assigned stance
---   (default: negative placeholder).
--- - `ctx.rounds`         — number, optional. Number of full A/B round pairs
---   (default: 3, from Khan et al. 2024 §3 canonical setting).
--- - `ctx.judge_criteria` — string, optional. Rubric injected verbatim into
---   the judge prompt (default: truthfulness-focused rubric).
---
--- Result (`ctx.result`):
--- - `winner`      — string, "A" or "B" (falls back to "A" if unparsable).
--- - `verdict`     — string, one-line judge decision.
--- - `rationale`   — string, judge's justification for the verdict.
--- - `transcript`  — array of `{ round, side, argument }` records in turn
---   order.
--- - `rounds_used` — number, how many rounds ran (= `rounds` on success).
---
--- ## Comparison with related packages
---
--- vs `panel`: `panel` runs distinct roles (advocate / critic / pragmatist)
--- each contributing one turn, then a moderator synthesizes. `debate` fixes
--- exactly two debaters on opposing positions for `R` alternating rounds and
--- asks the judge to pick a winner rather than synthesize — adversarial
--- rather than deliberative.
---
--- vs `dissent`: `dissent` surfaces minority-view critique against a single
--- draft. `debate` structures a symmetric pro/con exchange over multiple
--- rounds with a terminal verdict rather than a critique-of-draft asymmetry.
---
--- vs `triad`: `triad` runs three mutually critical perspectives without a
--- fixed winner. `debate` binds two arguers to opposing positions and forces
--- a WINNER decision from the judge.
---
--- ## Caveats
---
--- **Provenance of hyperparameters**: `rounds = 3` is the canonical setting
--- reported in Khan et al. 2024 §3 (Table 2). The `judge_criteria` default is
--- an implementation choice echoing the paper's truthfulness framing — the
--- paper describes but does not fix a literal rubric string, so callers with
--- a domain-specific criterion should override this. Debater personas
--- (position_a / position_b) are placeholder strings; the paper's setup
--- assigns concrete opposing propositions per question, so callers should
--- inject question-specific stances for faithful reproduction.
---
--- **Extension points** (override at your own risk to paper effect):
--- - `ctx.rounds`         — Deviating from R=3 diverges from Khan 2024 §3
---   canonical settings; paper reports diminishing returns past ~3 rounds.
--- - `ctx.position_a` / `ctx.position_b` — Placeholder strings; production
---   use should inject stance-specific propositions per the paper's setup.
--- - `ctx.judge_criteria` — Implementation choice default; caller override
---   is the primary customization channel (does not degrade paper effect
---   when the rubric preserves truthfulness focus).
---
--- **Unparsable judge output**: if the judge's response omits a parseable
--- `WINNER:` marker, `winner` defaults to `"A"` and a warning is emitted via
--- `alc.log("warn", ...)`. Callers relying on the verdict for downstream
--- decisions should check `rationale` for plausibility.
---
--- ## References
---
--- - Khan, A. et al. (2024). "Debating with More Persuasive LLMs Leads to
---   More Truthful Answers." ICML 2024. arXiv:2402.06782.

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "debate",
    version = "0.1.0",
    description = "Adversarial two-debater protocol with a terminal judge verdict",
    category = "synthesis",
    alc_shapes_compat = "^0.25",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                question = T.string:describe("Question under debate (required, non-empty)"),
                position_a = T.string:is_optional()
                    :describe("Debater A's assigned stance (default: affirmative placeholder; "
                        .. "Khan 2024 §3 assigns concrete opposing propositions per question, "
                        .. "so callers should inject question-specific stances)"),
                position_b = T.string:is_optional()
                    :describe("Debater B's assigned stance (default: negative placeholder; "
                        .. "same provenance note as position_a)"),
                rounds = T.number:is_optional()
                    :describe("Number of full A/B round pairs (default: 3; "
                        .. "Khan 2024 §3 Table 2 canonical setting)"),
                judge_criteria = T.string:is_optional()
                    :describe("Rubric injected into the judge prompt "
                        .. "(default: truthfulness-focused rubric — implementation choice "
                        .. "echoing Khan 2024's \"more truthful answers\" framing, "
                        .. "paper does not fix a literal rubric string)"),
            }),
            result = T.shape({
                winner = T.string:describe("Judge's verdict: \"A\" or \"B\" "
                    .. "(falls back to \"A\" with alc.log warn when unparseable)"),
                verdict = T.string:describe("One-line judge decision"),
                rationale = T.string:describe("Judge's justification for the verdict"),
                transcript = T.array_of(T.shape({
                    round = T.number:describe("1-based round index"),
                    side = T.string:describe("Debater side: \"A\" or \"B\""),
                    argument = T.string:describe("Debater's argument text for this turn"),
                })):describe("Ordered debate transcript, length = 2 * rounds_used"),
                rounds_used = T.number:describe("Number of full A/B round pairs executed"),
            }),
        },
    },
}

--- Default position placeholders (implementation choice — the paper assigns
--- concrete opposing propositions per question, but a package default cannot
--- know the question domain, so we ship generic affirmative/negative labels).
local DEFAULT_POSITION_A = "Argue YES / for the affirmative"
local DEFAULT_POSITION_B = "Argue NO / for the negative"

--- Default judge rubric (implementation choice echoing Khan 2024 framing;
--- paper describes truthfulness as the target signal but does not fix a
--- literal rubric string, so callers with a domain-specific criterion should
--- override via `ctx.judge_criteria`).
local DEFAULT_JUDGE_CRITERIA =
    "Truthfulness and factual accuracy of the arguments; strength of evidence "
    .. "cited by each side; logical coherence and responsiveness to the "
    .. "opposing side's points; absence of fallacies or unsupported claims."

--- Default rounds (Khan 2024 §3 Table 2 canonical setting).
local DEFAULT_ROUNDS = 3

--- Trim leading/trailing whitespace from a string (nil-safe).
local function trim(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Render the running transcript as a plain-text block for injection into
--- the next debater's prompt. Format is stable so debaters can reliably
--- attribute prior turns:
---   [Round 1 — A]: ...
---   [Round 1 — B]: ...
local function render_transcript(transcript)
    local parts = {}
    for i, turn in ipairs(transcript) do
        parts[i] = string.format("[Round %d — %s]: %s", turn.round, turn.side, turn.argument)
    end
    return table.concat(parts, "\n\n")
end

--- Build a debater prompt for side ("A" or "B") in `round`, given the prior
--- transcript. The debater sees its own position, the opposing side's
--- position (for adversarial framing), and the full transcript so far.
local function build_debater_prompt(question, side, position, opposing_position, round, transcript)
    local prior
    if #transcript == 0 then
        prior = "(no prior arguments — you open the debate)"
    else
        prior = render_transcript(transcript)
    end
    return string.format(
        "Question under debate: %s\n\n"
            .. "You are Debater %s. Your assigned stance: %s\n"
            .. "Opposing debater's stance: %s\n\n"
            .. "Prior transcript:\n%s\n\n"
            .. "This is round %d. Present your argument for this turn. Engage "
            .. "with specific points raised by the opposing side (when any). "
            .. "Be substantive and stay in your assigned stance. 3-5 sentences.",
        question, side, position, opposing_position, prior, round
    )
end

--- Build the judge prompt over the full transcript.
local function build_judge_prompt(question, transcript, criteria)
    return string.format(
        "Question under debate: %s\n\n"
            .. "Full debate transcript:\n%s\n\n"
            .. "Judge criteria:\n%s\n\n"
            .. "Read the full transcript and decide which side argued more "
            .. "persuasively under the criteria. Output EXACTLY this format:\n"
            .. "WINNER: A\n"
            .. "VERDICT: <one-line decision>\n"
            .. "RATIONALE: <justification, 2-4 sentences>",
        question, render_transcript(transcript), criteria
    )
end

--- Parse the judge output into `{ winner, verdict, rationale }`. Any field
--- that fails to parse returns `nil` in that slot; the caller applies the
--- fallback + warning policy.
local function parse_judge_output(text)
    local winner, verdict, rationale = nil, nil, nil
    for line in text:gmatch("[^\n]+") do
        local w = line:match("^%s*WINNER:%s*([AB])")
        if w then winner = w end
        local v = line:match("^%s*VERDICT:%s*(.+)$")
        if v then verdict = trim(v) end
        local r = line:match("^%s*RATIONALE:%s*(.+)$")
        if r then rationale = trim(r) end
    end
    return winner, verdict, rationale
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local question = ctx.question
    if type(question) ~= "string" or question:match("^%s*$") then
        error("ctx.question is required (non-empty string)")
    end
    local position_a = ctx.position_a or DEFAULT_POSITION_A
    local position_b = ctx.position_b or DEFAULT_POSITION_B
    local rounds = ctx.rounds or DEFAULT_ROUNDS
    local criteria = ctx.judge_criteria or DEFAULT_JUDGE_CRITERIA
    local debater_tokens = ctx.debater_tokens or 350
    local judge_tokens = ctx.judge_tokens or 400

    local transcript = {}

    -- Phase 1: alternating debater rounds (2R alc.llm calls, sequential).
    for r = 1, rounds do
        -- Debater A turn.
        local a_prompt = build_debater_prompt(
            question, "A", position_a, position_b, r, transcript
        )
        local a_text = alc.llm(a_prompt, {
            system = "You are Debater A in a structured debate. Stay strictly "
                .. "within your assigned stance. Be substantive, evidence-driven, "
                .. "and directly responsive to the opposing side.",
            max_tokens = debater_tokens,
        })
        transcript[#transcript + 1] = { round = r, side = "A", argument = a_text }

        -- Debater B turn (sees A's turn already).
        local b_prompt = build_debater_prompt(
            question, "B", position_b, position_a, r, transcript
        )
        local b_text = alc.llm(b_prompt, {
            system = "You are Debater B in a structured debate. Stay strictly "
                .. "within your assigned stance. Be substantive, evidence-driven, "
                .. "and directly responsive to the opposing side.",
            max_tokens = debater_tokens,
        })
        transcript[#transcript + 1] = { round = r, side = "B", argument = b_text }
    end

    if alc.log then
        alc.log("info", string.format(
            "debate: %d rounds complete (%d turns), invoking judge",
            rounds, #transcript
        ))
    end

    -- Phase 2: single judge pass over the full transcript.
    local judge_out = alc.llm(
        build_judge_prompt(question, transcript, criteria),
        {
            system = "You are an impartial judge in a structured debate. Judge "
                .. "strictly under the provided criteria. Follow the output "
                .. "format exactly.",
            max_tokens = judge_tokens,
        }
    )

    local winner, verdict, rationale = parse_judge_output(judge_out)

    -- Fallback + warning policy: unparsable WINNER defaults to "A".
    if not winner then
        if alc.log then
            alc.log("warn", "debate: judge WINNER marker unparseable; defaulting to \"A\"")
        end
        winner = "A"
    end

    ctx.result = {
        winner = winner,
        verdict = verdict or trim(judge_out),
        rationale = rationale or trim(judge_out),
        transcript = transcript,
        rounds_used = rounds,
    }
    return ctx
end

-- ─── Test hooks ───
M._internal = {
    trim = trim,
    render_transcript = render_transcript,
    build_debater_prompt = build_debater_prompt,
    build_judge_prompt = build_judge_prompt,
    parse_judge_output = parse_judge_output,
    DEFAULT_POSITION_A = DEFAULT_POSITION_A,
    DEFAULT_POSITION_B = DEFAULT_POSITION_B,
    DEFAULT_JUDGE_CRITERIA = DEFAULT_JUDGE_CRITERIA,
    DEFAULT_ROUNDS = DEFAULT_ROUNDS,
}

-- Malli-style self-decoration: wrapper asserts input/result against
-- M.spec.entries.run shapes when ALC_SHAPE_CHECK=1 (passthrough otherwise).
M.run = S.instrument(M, "run")

return M
