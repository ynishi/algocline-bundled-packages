--- dmad — Dialectical reasoning (thesis → antithesis → synthesis)
---
--- Applies the Hegelian dialectic to LLM reasoning: first generates a
--- thesis (initial position), then constructs the strongest possible
--- antithesis (opposing position), and finally produces a synthesis that
--- integrates valid points from both sides.
---
--- Unlike panel (sequential multi-role discussion) or negation (destruction
--- conditions), dmad explicitly constructs a well-argued counter-position
--- and forces genuine integration rather than simple error-correction.
---
--- Based on: "Improving Factuality and Reasoning in Language Models through
---            Multiagent Debate" (Du et al., arXiv 2305.14325, 2023)
---            + Hegelian dialectic methodology
---
--- Pipeline:
---   Step 1: thesis     — generate initial reasoned position
---   Step 2: antithesis — construct strongest opposing argument
---   Step 3: rebuttal   — thesis side responds to antithesis
---   Step 4: synthesis  — integrate valid points from both sides
---
--- Usage:
---   local dmad = require("dmad")
---   return dmad.run(ctx)
---
--- ctx.task (required): The task/question to analyze
--- ctx.rounds: Number of thesis-antithesis exchange rounds (default: 1)
--- ctx.gen_tokens: Max tokens per position (default: 500)
--- ctx.synth_tokens: Max tokens for synthesis (default: 600)

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "dmad",
    version = "0.1.0",
    description = "Dialectical reasoning — thesis, antithesis, and synthesis for deeper analysis",
    category = "reasoning",
}

local debate_entry_shape = T.shape({
    role  = T.one_of({ "thesis", "antithesis", "rebuttal", "synthesis" })
        :describe("Dialectical role of this entry"),
    round = T.number:describe("Round index; 0 for initial thesis and rounds for synthesis, 1..N for antithesis/rebuttal"),
    text  = T.string:describe("LLM output for this dialectical turn"),
})

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task         = T.string:describe("Task or question to analyze (required)"),
                rounds       = T.number:is_optional():describe("Number of thesis–antithesis exchange rounds (default 1)"),
                gen_tokens   = T.number:is_optional():describe("Max tokens per thesis/antithesis/rebuttal (default 500)"),
                synth_tokens = T.number:is_optional():describe("Max tokens for the final synthesis (default 600)"),
            }),
            result = T.shape({
                answer     = T.string:describe("Final synthesis text; alias of result.synthesis for caller convenience"),
                thesis     = T.string:describe("Initial reasoned position (round 0)"),
                antithesis = T.string:describe("Last antithesis produced (round N)"),
                synthesis  = T.string:describe("Integrated position from the dialectic"),
                rounds     = T.number:describe("Number of rounds actually executed"),
                debate_log = T.array_of(debate_entry_shape)
                    :describe("Full dialectical transcript in chronological order (thesis → antithesis/rebuttal*rounds → synthesis)"),
            }),
        },
    },
}

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local rounds = ctx.rounds or 1
    local gen_tokens = ctx.gen_tokens or 500
    local synth_tokens = ctx.synth_tokens or 600

    local debate_log = {}

    -- ─── Step 1: Thesis ───
    alc.log("info", "dmad: generating thesis")

    local thesis = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Present a well-reasoned position on this topic. "
                .. "Support your claims with evidence and logic. "
                .. "Be thorough and confident in your analysis.",
            task
        ),
        {
            system = "You are a skilled advocate. Present the strongest possible "
                .. "position. Use evidence, examples, and clear reasoning. "
                .. "Commit fully to your position — do not hedge unnecessarily.",
            max_tokens = gen_tokens,
        }
    )

    debate_log[#debate_log + 1] = {
        role = "thesis",
        round = 0,
        text = thesis,
    }

    local current_thesis = thesis
    local current_antithesis = nil

    for round = 1, rounds do
        -- ─── Step 2: Antithesis ───
        alc.log("info", string.format(
            "dmad: generating antithesis (round %d/%d)", round, rounds
        ))

        local antithesis_context = ""
        if current_antithesis then
            antithesis_context = string.format(
                "\n\nPrevious counter-argument:\n\"\"\"\n%s\n\"\"\"\n\n"
                    .. "Build on this but go deeper.",
                current_antithesis
            )
        end

        current_antithesis = alc.llm(
            string.format(
                "Task: %s\n\n"
                    .. "The following position has been argued:\n\"\"\"\n%s\n\"\"\"\n"
                    .. "%s"
                    .. "Construct the STRONGEST possible counter-argument. "
                    .. "Challenge every assumption, find logical gaps, present "
                    .. "alternative evidence, and argue for the opposing view. "
                    .. "Do not simply nitpick — present a genuinely compelling "
                    .. "alternative position.",
                task, current_thesis, antithesis_context
            ),
            {
                system = "You are a devil's advocate and skilled debater. "
                    .. "Your job is to find the strongest possible objection "
                    .. "to the thesis. Attack the weakest points, present "
                    .. "counterevidence, and argue passionately for the "
                    .. "opposing view. Be intellectually honest but adversarial.",
                max_tokens = gen_tokens,
            }
        )

        debate_log[#debate_log + 1] = {
            role = "antithesis",
            round = round,
            text = current_antithesis,
        }

        -- ─── Step 3: Rebuttal ───
        alc.log("info", string.format(
            "dmad: generating rebuttal (round %d/%d)", round, rounds
        ))

        local rebuttal = alc.llm(
            string.format(
                "Task: %s\n\n"
                    .. "Your original position:\n\"\"\"\n%s\n\"\"\"\n\n"
                    .. "Counter-argument raised:\n\"\"\"\n%s\n\"\"\"\n\n"
                    .. "Respond to this counter-argument. Defend your position "
                    .. "where it is strong, but honestly acknowledge where the "
                    .. "counter-argument has valid points. Do not dismiss valid "
                    .. "criticisms — concede where you must, strengthen where you can.",
                task, current_thesis, current_antithesis
            ),
            {
                system = "You are defending your thesis against strong objections. "
                    .. "Be intellectually honest: concede valid points, but "
                    .. "strengthen your core argument where possible. Show that "
                    .. "you have genuinely engaged with the counter-argument.",
                max_tokens = gen_tokens,
            }
        )

        debate_log[#debate_log + 1] = {
            role = "rebuttal",
            round = round,
            text = rebuttal,
        }

        -- Update thesis for next round (if any)
        current_thesis = rebuttal
    end

    -- ─── Step 4: Synthesis ───
    alc.log("info", "dmad: generating synthesis")

    -- Build full debate transcript for synthesis
    local transcript = {}
    for _, entry in ipairs(debate_log) do
        transcript[#transcript + 1] = string.format(
            "[%s (round %d)]:\n%s",
            entry.role:upper(), entry.round, entry.text
        )
    end

    local synthesis = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "A dialectical debate has taken place:\n\n%s\n\n"
                .. "Now produce a SYNTHESIS that:\n"
                .. "1. Identifies where both sides agree (common ground)\n"
                .. "2. Acknowledges genuinely unresolved tensions\n"
                .. "3. Integrates valid points from BOTH thesis and antithesis\n"
                .. "4. Arrives at a more nuanced, comprehensive position\n"
                .. "5. Clearly states what was learned from the dialectic\n\n"
                .. "Do not simply pick a winner. Create something better than "
                .. "either position alone.",
            task, table.concat(transcript, "\n\n")
        ),
        {
            system = "You are a master synthesizer. Your role is NOT to pick "
                .. "a side, but to create a higher-order understanding that "
                .. "transcends the original debate. Integrate the strongest "
                .. "elements of both positions into a more complete analysis. "
                .. "Acknowledge remaining uncertainties honestly.",
            max_tokens = synth_tokens,
        }
    )

    debate_log[#debate_log + 1] = {
        role = "synthesis",
        round = rounds,
        text = synthesis,
    }

    alc.log("info", string.format(
        "dmad: complete — %d round(s), %d debate entries",
        rounds, #debate_log
    ))

    ctx.result = {
        answer = synthesis,
        thesis = thesis,
        antithesis = current_antithesis,
        synthesis = synthesis,
        rounds = rounds,
        debate_log = debate_log,
    }
    return ctx
end

M.run = S.instrument(M, "run")

return M
