--- Triad — adversarial 3-role debate with judge arbitration
---
--- Three distinct roles: Proponent (argues for), Opponent (argues against),
--- Judge (arbitrates). Multiple rounds of attack/defense, then final verdict.
---
--- Based on: Du et al., "Improving Factuality and Reasoning in Language
--- Models through Multiagent Debate" (2023, arXiv:2305.14325)
---
--- Usage:
---   local triad = require("triad")
---   return triad.run(ctx)
---
--- ctx.task (required): The question or claim to debate
--- ctx.rounds: Number of debate rounds (default: 3)
--- ctx.gen_tokens: Max tokens per argument (default: 400)
--- ctx.judge_tokens: Max tokens for final verdict (default: 500)

local M = {}

---@type AlcMeta
M.meta = {
    name = "triad",
    version = "0.1.0",
    description = "Adversarial 3-role debate — proponent/opponent/judge with multi-round argumentation",
    category = "adversarial",
}

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local rounds = ctx.rounds or 3
    local gen_tokens = ctx.gen_tokens or 400
    local judge_tokens = ctx.judge_tokens or 500

    -- Phase 1: Opening statements (parallel)
    local openings = alc.map({ "proponent", "opponent" }, function(role)
        local stance = role == "proponent" and "SUPPORT" or "OPPOSE"
        return alc.llm(
            string.format(
                "Topic: %s\n\n"
                    .. "You are the %s. Present your opening argument to %s this position.\n"
                    .. "Be specific, cite reasoning, and anticipate counterarguments.",
                task, role, stance
            ),
            {
                system = string.format(
                    "You are a skilled debater assigned the %s role. "
                        .. "Argue persuasively for your assigned position. "
                        .. "Use evidence and logical reasoning.",
                    role
                ),
                max_tokens = gen_tokens,
            }
        )
    end)

    local pro_arg = openings[1]
    local opp_arg = openings[2]
    local transcript = {
        { round = 0, proponent = pro_arg, opponent = opp_arg },
    }

    -- Phase 2: Debate rounds (sequential — each round reacts to previous)
    for r = 1, rounds do
        -- Proponent rebuts opponent's argument
        pro_arg = alc.llm(
            string.format(
                "Topic: %s\n\n"
                    .. "Opponent's latest argument:\n%s\n\n"
                    .. "Counter this argument. Identify weaknesses, logical flaws, "
                    .. "or missing evidence. Then strengthen your own position.",
                task, opp_arg
            ),
            {
                system = "You are the proponent. Dismantle the opponent's argument "
                    .. "and reinforce your position. Be precise about which claims are weak and why.",
                max_tokens = gen_tokens,
            }
        )

        -- Opponent rebuts proponent's argument
        opp_arg = alc.llm(
            string.format(
                "Topic: %s\n\n"
                    .. "Proponent's latest argument:\n%s\n\n"
                    .. "Counter this argument. Identify weaknesses, logical flaws, "
                    .. "or missing evidence. Then strengthen your own position.",
                task, pro_arg
            ),
            {
                system = "You are the opponent. Dismantle the proponent's argument "
                    .. "and reinforce your position. Be precise about which claims are weak and why.",
                max_tokens = gen_tokens,
            }
        )

        transcript[#transcript + 1] = {
            round = r,
            proponent = pro_arg,
            opponent = opp_arg,
        }

        alc.log("info", string.format("triad: round %d/%d complete", r, rounds))
    end

    -- Phase 3: Judge arbitrates
    local debate_text = ""
    for _, entry in ipairs(transcript) do
        local label = entry.round == 0 and "Opening" or string.format("Round %d", entry.round)
        debate_text = debate_text .. string.format(
            "--- %s ---\n"
                .. "PROPONENT: %s\n\n"
                .. "OPPONENT: %s\n\n",
            label, entry.proponent, entry.opponent
        )
    end

    local verdict = alc.llm(
        string.format(
            "Topic: %s\n\n"
                .. "Full debate transcript:\n\n%s\n"
                .. "As the impartial judge, evaluate:\n"
                .. "1. Which side presented stronger evidence?\n"
                .. "2. Which side had better logical reasoning?\n"
                .. "3. Which side effectively rebutted the other?\n\n"
                .. "Deliver your verdict:\n"
                .. "WINNER: [proponent|opponent|draw]\n"
                .. "REASONING: [detailed explanation]\n"
                .. "SYNTHESIS: [balanced conclusion incorporating valid points from both sides]",
            task, debate_text
        ),
        {
            system = "You are an impartial, rigorous judge. Evaluate arguments on "
                .. "evidence quality, logical soundness, and rebuttal effectiveness. "
                .. "Do not favor either side by default. If both sides have merit, "
                .. "synthesize the strongest position from both.",
            max_tokens = judge_tokens,
        }
    )

    -- Parse verdict
    local winner = verdict:match("WINNER:%s*(%S+)") or "unknown"
    winner = winner:lower()

    ctx.result = {
        verdict = verdict,
        winner = winner,
        transcript = transcript,
        total_rounds = rounds,
    }
    return ctx
end

return M
