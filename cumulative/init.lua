--- Cumulative — propose-verify-accumulate reasoning
--- Three roles (proposer, verifier, reporter) collaborate in a loop.
--- The proposer generates new propositions, the verifier checks them,
--- and verified propositions accumulate as established facts for the next round.
---
--- Based on: Zhang et al., "Cumulative Reasoning with Large Language Models"
--- (2024, arXiv:2308.04371)
---
--- Usage:
---   local cumulative = require("cumulative")
---   return cumulative.run(ctx)
---
--- ctx.task (required): The problem to solve
--- ctx.max_rounds: Maximum propose-verify cycles (default: 4)
--- ctx.propositions_per_round: Propositions to generate per round (default: 2)

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "cumulative",
    version = "0.1.0",
    description = "Cumulative Reasoning — proposer/verifier/reporter loop with fact accumulation",
    category = "reasoning",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task                   = T.string:describe("The problem to solve"),
                max_rounds             = T.number:is_optional():describe("Max propose-verify cycles (default: 4)"),
                propositions_per_round = T.number:is_optional():describe("Propositions generated per round (default: 2)"),
            }),
            result = T.shape({
                answer            = T.string:describe("Reporter's synthesis grounded in established facts"),
                established_facts = T.array_of(T.shape({
                    proposition = T.string,
                    round       = T.number,
                })):describe("Verified propositions accumulated across rounds"),
                rounds            = T.array_of(T.shape({
                    round    = T.number,
                    proposed = T.array_of(T.string),
                    verified = T.array_of(T.shape({
                        proposition  = T.string,
                        verification = T.string,
                        accepted     = T.boolean,
                    })),
                })):describe("Per-round propose/verify trace"),
                total_rounds      = T.number:describe("Number of rounds actually executed (may be < max_rounds due to early termination)"),
                total_established = T.number:describe("Count of verified propositions"),
            }),
        },
    },
}

local function format_established(established)
    if #established == 0 then return "(none yet)\n" end
    local text = ""
    for i, e in ipairs(established) do
        text = text .. string.format("  [%d] %s\n", i, e.proposition)
    end
    return text
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local max_rounds = ctx.max_rounds or 4
    local props_per_round = ctx.propositions_per_round or 2

    local established = {}  -- verified propositions
    local rounds = {}

    for round = 1, max_rounds do
        local round_data = { round = round, proposed = {}, verified = {} }
        local established_text = format_established(established)

        -- PROPOSER: Generate new propositions
        for p = 1, props_per_round do
            local proposition = alc.llm(
                string.format(
                    "Task: %s\n\n"
                        .. "Established facts so far:\n%s\n"
                        .. "As the PROPOSER, generate proposition #%d for this round.\n"
                        .. "The proposition should:\n"
                        .. "- Build on established facts\n"
                        .. "- Move toward solving the task\n"
                        .. "- Be a specific, verifiable claim or reasoning step\n\n"
                        .. "State ONE clear proposition.",
                    task, established_text, p
                ),
                {
                    system = "You are a logical proposer. Generate precise, verifiable "
                        .. "propositions that advance the reasoning. Each must be self-contained.",
                    max_tokens = 200,
                }
            )

            round_data.proposed[#round_data.proposed + 1] = proposition

            -- VERIFIER: Check the proposition
            local verification = alc.llm(
                string.format(
                    "Task: %s\n\n"
                        .. "Established facts:\n%s\n"
                        .. "New proposition to verify:\n  \"%s\"\n\n"
                        .. "As the VERIFIER, assess this proposition:\n"
                        .. "1. Is it logically sound?\n"
                        .. "2. Is it consistent with established facts?\n"
                        .. "3. Does it advance the reasoning?\n\n"
                        .. "If VALID, output: ACCEPTED\n"
                        .. "If INVALID, output: REJECTED — [reason]",
                    task, established_text, proposition
                ),
                {
                    system = "You are a rigorous verifier. Only accept propositions that are "
                        .. "logically sound and consistent. Reject anything questionable.",
                    max_tokens = 150,
                }
            )

            local accepted = verification:match("ACCEPTED") ~= nil

            round_data.verified[#round_data.verified + 1] = {
                proposition = proposition,
                verification = verification,
                accepted = accepted,
            }

            if accepted then
                established[#established + 1] = {
                    proposition = proposition,
                    round = round,
                }
            end
        end

        rounds[#rounds + 1] = round_data

        alc.log("info", string.format(
            "cumulative: round %d/%d — %d proposed, %d accepted, %d total established",
            round, max_rounds,
            #round_data.proposed,
            alc.reduce(round_data.verified, function(acc, v) return acc + (v.accepted and 1 or 0) end, 0),
            #established
        ))

        -- Early termination: check if we have enough to conclude
        if #established >= 3 and round >= 2 then
            local can_conclude = alc.llm(
                string.format(
                    "Task: %s\n\n"
                        .. "Established facts:\n%s\n"
                        .. "Can we now provide a complete answer to the task based on these "
                        .. "established facts? Reply YES or NO.",
                    task, format_established(established)
                ),
                { system = "Be strict. Only say YES if the facts are sufficient.", max_tokens = 10 }
            )
            if can_conclude:match("YES") then
                alc.log("info", string.format("cumulative: sufficient facts at round %d", round))
                break
            end
        end
    end

    -- REPORTER: Synthesize established facts into final answer
    local report = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Established and verified facts:\n%s\n"
                .. "As the REPORTER, synthesize these verified facts into a comprehensive "
                .. "final answer. Only use established facts — do not introduce new claims.",
            task, format_established(established)
        ),
        {
            system = "You are a precise reporter. Your answer must be grounded entirely "
                .. "in the established facts. Do not speculate beyond what was verified.",
            max_tokens = 600,
        }
    )

    ctx.result = {
        answer = report,
        established_facts = established,
        rounds = rounds,
        total_rounds = #rounds,
        total_established = #established,
    }
    return ctx
end

-- Malli-style self-decoration (see alc_shapes/README). inline T.shape
-- for both input and result; wrapper validates in ALC_SHAPE_CHECK=1.
M.run = S.instrument(M, "run")

return M
