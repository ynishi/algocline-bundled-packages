--- pbft — Practical Byzantine Fault Tolerant consensus via LLM
---
--- Multi-agent 3-phase consensus protocol inspired by PBFT
--- (Castro-Liskov OSDI 1999). Uses the bft package for quorum
--- validation and threshold computation.
---
--- Protocol (adapted for LLM agents):
---   Phase 1 (Propose):  N agents independently generate answers
---   Phase 2 (Validate): Each agent reviews ALL proposals and votes
---   Phase 3 (Commit):   If quorum (2f+1) agrees, commit that answer;
---                        otherwise, a synthesizer resolves
---
--- Key safety properties from PBFT:
---   - Quorum intersection: any two quorums of size 2f+1 share >= 1
---     honest node when n >= 3f+1
---   - Initial answer preservation: the original proposal is always
---     a candidate (Red Line N2 compliance)
---
--- Usage:
---   local pbft = require("pbft")
---   return pbft.run(ctx)
---
--- ctx.task (required): The problem to solve
--- ctx.n_agents: Number of agents (default: 3, must satisfy n >= 3f+1)
--- ctx.f: Assumed Byzantine faults (default: 0)
--- ctx.gen_tokens: Max tokens per proposal (default: 400)
--- ctx.vote_tokens: Max tokens per vote (default: 200)
--- ctx.synth_tokens: Max tokens for synthesis (default: 500)

local bft = require("bft")

local M = {}

---@type AlcMeta
M.meta = {
    name = "pbft",
    version = "0.1.0",
    description = "PBFT-inspired 3-phase LLM consensus — propose, validate, "
        .. "commit with BFT quorum guarantees (Castro-Liskov 1999)",
    category = "aggregation",
}

--- Count occurrences of each vote and find the majority.
local function tally_votes(votes)
    local counts = {}
    local max_count = 0
    local max_vote = nil
    for _, v in ipairs(votes) do
        local key = tostring(v)
        counts[key] = (counts[key] or 0) + 1
        if counts[key] > max_count then
            max_count = counts[key]
            max_vote = v
        end
    end
    return max_vote, max_count, counts
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("pbft: ctx.task is required")
    local n = ctx.n_agents or 3
    local f = ctx.f or 0
    local gen_tokens = ctx.gen_tokens or 400
    local vote_tokens = ctx.vote_tokens or 200
    local synth_tokens = ctx.synth_tokens or 500

    -- Validate BFT conditions
    local ok, reason = bft.validate(n, f)
    if not ok then
        error("pbft: " .. reason)
    end
    local quorum = bft.threshold(n, f)

    -- ─── Phase 1: Propose ───
    -- N agents independently generate proposals
    local proposals = {}
    for i = 1, n do
        proposals[i] = alc.llm(
            string.format(
                "Task: %s\n\nYou are agent #%d of %d. "
                .. "Provide your independent answer. Be thorough and precise.",
                task, i, n
            ),
            {
                system = string.format(
                    "You are agent #%d in a %d-agent consensus protocol. "
                    .. "Answer independently without assuming what others might say.",
                    i, n),
                max_tokens = gen_tokens,
            }
        )
    end

    -- ─── Phase 2: Validate ───
    -- Each agent reviews ALL proposals and votes for the best one
    local listing = ""
    for i, p in ipairs(proposals) do
        listing = listing .. string.format("--- Proposal #%d ---\n%s\n\n", i, p)
    end

    local votes = {}
    for i = 1, n do
        local vote_raw = alc.llm(
            string.format(
                "Task: %s\n\nYou have received %d proposals:\n\n%s"
                .. "As agent #%d, vote for the BEST proposal number (1-%d). "
                .. "Consider accuracy, completeness, and reasoning quality. "
                .. "Reply with ONLY the number.",
                task, n, listing, i, n
            ),
            {
                system = "You are a critical reviewer. Vote for the best proposal. "
                    .. "Reply with only the proposal number.",
                max_tokens = vote_tokens,
            }
        )
        -- Parse vote number
        local vote_num = tonumber(tostring(vote_raw):match("(%d+)"))
        if vote_num and vote_num >= 1 and vote_num <= n then
            votes[i] = vote_num
        else
            votes[i] = i  -- fallback: vote for own proposal
        end
    end

    -- ─── Phase 3: Commit ───
    local winner, winner_count, vote_counts = tally_votes(votes)
    local quorum_met = winner_count >= quorum

    local result_answer
    local commit_method

    if quorum_met then
        -- Quorum reached: commit the winning proposal directly
        result_answer = proposals[winner]
        commit_method = "quorum"
    else
        -- No quorum: synthesize from all proposals
        -- N2 Red Line: initial proposals are always candidates
        result_answer = alc.llm(
            string.format(
                "Task: %s\n\nNo consensus was reached among %d agents. "
                .. "The proposals were:\n\n%s"
                .. "Synthesize the best possible answer by combining the "
                .. "strongest elements from each proposal. "
                .. "Preserve any correct reasoning found in any proposal.",
                task, n, listing
            ),
            {
                system = "You are a neutral synthesizer. Combine the best elements "
                    .. "from all proposals into a single coherent answer.",
                max_tokens = synth_tokens,
            }
        )
        commit_method = "synthesis"
    end

    -- Build vote distribution for reporting
    local vote_dist = {}
    for k, v in pairs(vote_counts) do
        vote_dist[#vote_dist + 1] = { proposal = tonumber(k), votes = v }
    end
    table.sort(vote_dist, function(a, b) return a.votes > b.votes end)

    ctx.result = {
        answer = result_answer,
        commit_method = commit_method,
        quorum_met = quorum_met,
        quorum_required = quorum,
        n_agents = n,
        f_assumed = f,
        bft_valid = true,
        votes = votes,
        vote_distribution = vote_dist,
        winner_proposal = winner,
        winner_votes = winner_count,
        proposals = proposals,
    }
    return ctx
end

return M
