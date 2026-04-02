--- deliberate — structured multi-phase deliberation for complex decisions
---
--- Combinator package: orchestrates step_back, meta_prompt, triad,
--- calibrate, rank to perform principled decision-making.
---
--- Pipeline:
---   Phase 1: Abstract    — step_back: extract underlying principles and criteria
---   Phase 2: Consult     — meta_prompt: domain experts analyze the decision space
---   Phase 3: Generate    — enumerate options from expert insights (or use provided)
---   Phase 4: Debate      — triad: adversarial debate per option pair
---   Phase 5: Confidence  — calibrate: gate on debate quality
---   Phase 6: Rank        — rank: pairwise tournament to select best option
---
--- Usage:
---   local deliberate = require("deliberate")
---   return deliberate.run(ctx)
---
--- ctx.task (required): The decision question
--- ctx.options: Pre-defined options table (optional; auto-generated if absent)
--- ctx.max_options: Max options to consider (default: 4)
--- ctx.debate_rounds: Triad debate rounds per comparison (default: 2)
--- ctx.confidence_threshold: Calibrate threshold (default: 0.7)

local M = {}

---@type AlcMeta
M.meta = {
    name = "deliberate",
    version = "0.1.0",
    description = "Structured deliberation — abstract principles, expert consultation, debate, ranked decision",
    category = "combinator",
}

-- ─── Phase 1: Abstract ──────────────────────────────────

--- Extract underlying principles and decision criteria via step_back.
local function phase_abstract(task)
    alc.log("info", "deliberate: Phase 1 — Abstract (step_back)")

    local step_back = require("step_back")

    local ctx = step_back.run({
        task = string.format(
            "Decision question: %s\n\n"
                .. "What are the fundamental principles, constraints, and evaluation "
                .. "criteria that should govern this decision? What trade-offs are inherent?",
            task
        ),
        abstraction_levels = 1,
        domain_hint = "decision analysis",
    })

    local principles = ctx.result.answer or ""
    local abstractions = ctx.result.abstractions or {}

    alc.log("info", "deliberate: principles and criteria extracted")
    return principles, abstractions
end

-- ─── Phase 2: Consult ───────────────────────────────────

--- Dispatch to domain experts for multi-perspective analysis.
local function phase_consult(task, principles)
    alc.log("info", "deliberate: Phase 2 — Consult (meta_prompt)")

    local meta_prompt = require("meta_prompt")

    local ctx = meta_prompt.run({
        task = string.format(
            "Decision question: %s\n\n"
                .. "Governing principles and criteria:\n%s\n\n"
                .. "Analyze this decision from your area of expertise. "
                .. "Identify key factors, risks, and potential options.",
            task, principles
        ),
        max_experts = 3,
    })

    local expert_analysis = ctx.result.answer or ""
    local consultations = ctx.result.experts_consulted or {}

    alc.log("info", string.format(
        "deliberate: %d experts consulted", #consultations
    ))
    return expert_analysis, consultations
end

-- ─── Phase 3: Generate Options ──────────────────────────

--- Generate or validate decision options based on expert analysis.
local function phase_generate(task, principles, expert_analysis, provided_options, max_options)
    alc.log("info", "deliberate: Phase 3 — Generate Options")

    if provided_options and #provided_options > 0 then
        alc.log("info", string.format(
            "deliberate: using %d provided options", #provided_options
        ))
        return provided_options
    end

    local raw = alc.llm(
        string.format(
            "Decision question: %s\n\n"
                .. "Principles and criteria:\n%s\n\n"
                .. "Expert analysis:\n%s\n\n"
                .. "Based on the above, enumerate %d distinct decision options.\n"
                .. "For each option, provide:\n"
                .. '- name: concise label\n'
                .. '- description: what this option entails\n'
                .. '- strengths: key advantages\n'
                .. '- risks: key risks or downsides\n\n'
                .. "Output as a JSON array (no other text):\n"
                .. '[{"name":"...","description":"...","strengths":"...","risks":"..."}]',
            task, principles, expert_analysis, max_options
        ),
        {
            system = "You are a decision analyst. Generate distinct, viable options. "
                .. "Each option should represent a fundamentally different approach. "
                .. "Output ONLY valid JSON array.",
            max_tokens = 600,
        }
    )

    local options = alc.json_decode(raw)
    if type(options) ~= "table" then
        local json_str = raw:match("%[.+%]")
        if json_str then options = alc.json_decode(json_str) end
    end

    if type(options) ~= "table" or #options == 0 then
        alc.log("warn", "deliberate: option generation parse failed, creating fallback")
        options = { { name = "Default", description = raw, strengths = "", risks = "" } }
    end

    alc.log("info", string.format("deliberate: %d options generated", #options))
    return options
end

-- ─── Phase 4: Debate ────────────────────────────────────

--- Adversarial debate for each option's merits via triad.
local function phase_debate(task, options, principles, debate_rounds)
    alc.log("info", "deliberate: Phase 4 — Debate (triad)")

    local triad = require("triad")
    local debates = {}

    for i, option in ipairs(options) do
        local option_text = string.format(
            "%s: %s\nStrengths: %s\nRisks: %s",
            option.name or string.format("Option %d", i),
            option.description or "",
            option.strengths or "",
            option.risks or ""
        )

        local debate_ctx = triad.run({
            task = string.format(
                "Should we adopt the following option for the decision \"%s\"?\n\n"
                    .. "Option: %s\n\n"
                    .. "Governing principles:\n%s\n\n"
                    .. "Proponent: This is the best approach\n"
                    .. "Opponent: This approach has critical flaws",
                task, option_text, principles
            ),
            rounds = debate_rounds,
        })

        debates[i] = {
            option = option,
            verdict = debate_ctx.result.verdict or "",
            winner = debate_ctx.result.winner or "unknown",
        }

        alc.log("info", string.format(
            "  [DEBATE] %s — %s",
            option.name or string.format("Option %d", i),
            debate_ctx.result.winner or "unknown"
        ))
    end

    return debates
end

-- ─── Phase 5: Confidence Gate ───────────────────────────

--- Validate debate quality via calibrate. Low confidence triggers re-analysis.
local function phase_confidence(task, debates, principles, threshold)
    alc.log("info", "deliberate: Phase 5 — Confidence (calibrate)")

    local calibrate = require("calibrate")

    local debate_summary = ""
    for i, d in ipairs(debates) do
        debate_summary = debate_summary .. string.format(
            "Option %d — %s: debate winner=%s\n",
            i, d.option.name or "?", d.winner
        )
    end

    local cal_ctx = calibrate.run({
        task = string.format(
            "Evaluate whether the following debate results provide sufficient basis "
                .. "for a well-founded decision.\n\n"
                .. "Decision: %s\n\n"
                .. "Principles:\n%s\n\n"
                .. "Debate results:\n%s\n\n"
                .. "Are the debates thorough enough? Are there critical blind spots?",
            task, principles, debate_summary
        ),
        threshold = threshold,
        fallback = "retry",
    })

    local confidence = cal_ctx.result.confidence or 0
    local escalated = cal_ctx.result.escalated or false

    alc.log("info", string.format(
        "deliberate: confidence=%.2f, escalated=%s",
        confidence, tostring(escalated)
    ))

    return confidence, escalated
end

-- ─── Phase 6: Rank ──────────────────────────────────────

--- Final pairwise ranking of options informed by debate results.
local function phase_rank(task, debates, principles)
    alc.log("info", "deliberate: Phase 6 — Rank")

    local rank = require("rank")

    -- Build candidate texts from debate-enriched options
    local candidate_texts = {}
    for i, d in ipairs(debates) do
        candidate_texts[i] = string.format(
            "Option: %s\nDescription: %s\nStrengths: %s\nRisks: %s\nDebate outcome: %s",
            d.option.name or string.format("Option %d", i),
            d.option.description or "",
            d.option.strengths or "",
            d.option.risks or "",
            d.winner
        )
    end

    -- Use rank's pairwise comparison with custom criteria from principles
    local bracket = {}
    for i, text in ipairs(candidate_texts) do
        bracket[i] = { index = i, text = text, wins = 0 }
    end

    local criteria = string.format(
        "alignment with principles (%s), feasibility, risk-adjusted value",
        principles:sub(1, 200)
    )

    local match_log = {}
    while #bracket > 1 do
        local next_round = {}
        for i = 1, #bracket, 2 do
            if i + 1 <= #bracket then
                local a = bracket[i]
                local b = bracket[i + 1]
                local verdict = alc.llm(
                    string.format(
                        "Decision: %s\n\n"
                            .. "Compare these two options:\n\n"
                            .. "--- Option A ---\n%s\n\n"
                            .. "--- Option B ---\n%s\n\n"
                            .. "Criteria: %s\n\n"
                            .. "Which option is better? Answer: WINNER: A or B, then one sentence why.",
                        task, a.text, b.text, criteria
                    ),
                    {
                        system = "You are an impartial decision analyst. Compare strictly "
                            .. "on the stated criteria. Consider debate outcomes as evidence.",
                        max_tokens = 150,
                    }
                )

                local winner
                if verdict:match("WINNER:%s*B") or verdict:match("^%s*B") then
                    winner = b
                else
                    winner = a
                end
                winner.wins = winner.wins + 1
                match_log[#match_log + 1] = {
                    a = a.index,
                    b = b.index,
                    winner = winner.index,
                    reason = verdict,
                }
                next_round[#next_round + 1] = winner
            else
                next_round[#next_round + 1] = bracket[i]
            end
        end
        bracket = next_round
    end

    local best = bracket[1]

    alc.log("info", string.format(
        "deliberate: best option = #%d (%s)",
        best.index, debates[best.index].option.name or "?"
    ))

    return best, match_log
end

-- ─── Entry Point ─────────────────────────────────────────

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local provided_options = ctx.options or nil
    local max_options = ctx.max_options or 4
    local debate_rounds = ctx.debate_rounds or 2
    local confidence_threshold = ctx.confidence_threshold or 0.7

    -- Phase 1: Abstract principles
    local principles, abstractions = phase_abstract(task)

    -- Phase 2: Expert consultation
    local expert_analysis, consultations = phase_consult(task, principles)

    -- Phase 3: Generate options
    local options = phase_generate(task, principles, expert_analysis, provided_options, max_options)

    -- Phase 4: Debate each option
    local debates = phase_debate(task, options, principles, debate_rounds)

    -- Phase 5: Confidence gate
    local confidence, escalated = phase_confidence(task, debates, principles, confidence_threshold)

    -- Phase 6: Rank
    local best, match_log = phase_rank(task, debates, principles)

    -- Build final recommendation
    local best_option = debates[best.index].option

    ctx.result = {
        recommendation = {
            name = best_option.name,
            description = best_option.description,
            debate_outcome = debates[best.index].winner,
            ranking_wins = best.wins,
        },
        principles = principles,
        abstractions = abstractions,
        expert_consultations = consultations,
        expert_analysis = expert_analysis,
        options = options,
        debates = debates,
        confidence = confidence,
        confidence_escalated = escalated,
        ranking_matches = match_log,
        total_options = #options,
    }
    return ctx
end

return M
