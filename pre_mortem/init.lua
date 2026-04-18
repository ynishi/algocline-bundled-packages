--- pre_mortem — feasibility-gated proposal filtering
---
--- Combinator package: orchestrates factscore, contrastive, calibrate
--- to validate proposals BEFORE output. Decomposes each proposal into
--- prerequisite assumptions, checks verification status, generates
--- rejection reasons pre-emptively, and demotes/filters proposals
--- with unverified prerequisites.
---
--- Problem solved: LLMs propose solutions with high confidence ratings
--- without checking feasibility (e.g., "MCP Sampling support" rated 9/10
--- when the host platform doesn't support it). This strategy forces
--- explicit prerequisite enumeration and verification-state labeling
--- before any rating is assigned.
---
--- Pipeline:
---   Step 1: factscore   — decompose each proposal into atomic prerequisites,
---                         label each as SUPPORTED/UNSUPPORTED/UNCERTAIN
---   Step 2: contrastive — for each proposal, generate "why it would be adopted"
---                         vs "why it would be rejected" reasoning pairs
---   Step 3: calibrate   — judge VERDICT (adopt/reject) with CONFIDENCE as
---                         meta-reliability gate. High confidence + adopt → accepted,
---                         high confidence + reject → rejected,
---                         low confidence → needs_investigation (escalate)
---   Step 4: rank        — pairwise tournament of accepted proposals to produce
---                         a final ordering by effectiveness
---
--- Usage:
---   local pre_mortem = require("pre_mortem")
---   return pre_mortem.run(ctx)
---
--- ctx.task (required): The original task/question that proposals address
--- ctx.proposals (required): A list of proposal strings, OR a single string
---     containing multiple proposals (will be decomposed by LLM)
--- ctx.context: Additional context for verification (e.g., known constraints)
--- ctx.threshold: Confidence threshold for acceptance (default: 0.6)
--- ctx.n_contrasts: Number of contrastive pairs per proposal (default: 1)
--- ctx.extract_tokens: Max tokens for prerequisite extraction (default: 500)
--- ctx.verify_tokens: Max tokens per prerequisite verification (default: 200)

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "pre_mortem",
    version = "0.1.0",
    description = "Feasibility-gated proposal filtering — prerequisite verification before rating",
    category = "combinator",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task           = T.string:describe("Original task/question addressed by the proposals"),
                proposals      = T.any:describe("Array of proposal strings or a single block to decompose"),
                context        = T.string:is_optional():describe("Additional verification context (e.g., known constraints)"),
                threshold      = T.number:is_optional():describe("Calibrate confidence threshold (default: 0.6)"),
                n_contrasts    = T.number:is_optional():describe("Contrastive pairs per proposal (default: 1)"),
                extract_tokens = T.number:is_optional():describe("Max tokens for prereq extraction (default: 500)"),
                verify_tokens  = T.number:is_optional():describe("Max tokens per prereq verification (default: 200)"),
            }),
            result = T.shape({
                proposals           = T.array_of(T.shape({
                    proposal           = T.string:describe("Proposal text"),
                    status             = T.string:describe("'accepted' | 'needs_investigation' | 'rejected'"),
                    verdict            = T.string:describe("'adopt' | 'reject' (calibrate judgment)"),
                    confidence         = T.number:describe("Calibrate confidence in its own judgment"),
                    prerequisites      = T.table:describe("factscore result for prerequisite decomposition"),
                    rejection_reasons  = T.array_of(T.string):describe("Rejection rationales from contrastive analysis"),
                    contrastive_answer = T.string:describe("Contrastive-derived answer text"),
                    calibrate_detail   = T.table:describe("Full calibrate result sub-record"),
                    rank               = T.number:is_optional():describe("1-based rank (only for accepted proposals)"),
                })):describe("Sorted evaluation records: ranked accepted → needs_investigation → rejected"),
                accepted            = T.number:describe("Count of accepted proposals"),
                needs_investigation = T.number:describe("Count of low-confidence proposals needing escalation"),
                rejected            = T.number:describe("Count of rejected proposals"),
                total               = T.number:describe("Total evaluated proposals"),
                ranking             = T.array_of(T.shape({
                    proposal           = T.string:describe("Proposal text"),
                    status             = T.string:describe("'accepted' (ranking only includes accepted)"),
                    verdict            = T.string:describe("'adopt'"),
                    confidence         = T.number:describe("Calibrate confidence"),
                    prerequisites      = T.table:describe("factscore result"),
                    rejection_reasons  = T.array_of(T.string):describe("Rejection rationales"),
                    contrastive_answer = T.string:describe("Contrastive-derived answer"),
                    calibrate_detail   = T.table:describe("Full calibrate result"),
                    rank               = T.number:describe("1-based rank from pairwise tournament"),
                })):describe("Accepted proposals in tournament-ranked order (empty when none accepted)"),
            }),
        },
    },
}

--- Parse VERDICT from calibrate answer text.
--- Returns "adopt" or "reject".
local function parse_verdict(answer)
    local upper = answer:upper()
    -- Explicit VERDICT tag
    local verdict = upper:match("VERDICT:%s*(%a+)")
    if verdict then
        if verdict == "ADOPT" or verdict == "ACCEPT" then return "adopt" end
        if verdict == "REJECT" or verdict == "DECLINE" then return "reject" end
    end
    -- Fallback heuristics: look for strong negative signals
    if upper:match("SHOULD NOT BE ADOPTED")
        or upper:match("RECOMMEND REJECTING")
        or upper:match("NOT FEASIBLE")
        or upper:match("INFEASIBLE")
        or upper:match("CANNOT BE IMPLEMENTED") then
        return "reject"
    end
    if upper:match("SHOULD BE ADOPTED")
        or upper:match("RECOMMEND ADOPTING")
        or upper:match("FEASIBLE AND")
        or upper:match("RECOMMEND ACCEPT") then
        return "adopt"
    end
    -- Conservative default: ambiguous → reject (require explicit positive signal)
    return "reject"
end

--- Pairwise comparison of two proposals for ranking.
--- Returns "A" or "B".
local function compare_proposals(task, a, b, context)
    local verdict = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Compare these two proposals:\n\n"
                .. "--- Proposal A ---\n%s\n\n"
                .. "--- Proposal B ---\n%s\n\n"
                .. "%s"
                .. "Which proposal is more effective for the task? "
                .. "Answer with exactly one word: A or B\n"
                .. "Then one sentence explaining why.",
            task, a, b,
            context ~= "" and ("Context:\n" .. context .. "\n\n") or ""
        ),
        {
            system = "You are an impartial judge. Compare strictly on effectiveness, "
                .. "feasibility, and relevance to the task. "
                .. "Respond with A or B first, then a brief justification.",
            max_tokens = 100,
        }
    )

    if verdict:match("^%s*B") or verdict:match("Response B") or verdict:match("Proposal B") then
        return "B", verdict
    end
    return "A", verdict
end

--- Parse a numbered proposal list from LLM output into a table of strings.
local function parse_proposals(raw)
    local proposals = {}
    for line in raw:gmatch("[^\n]+") do
        local _, text = line:match("^%s*(%d+)[%.%)%s]+(.+)")
        if text then
            proposals[#proposals + 1] = text:match("^%s*(.-)%s*$")
        end
    end
    return proposals
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local raw_proposals = ctx.proposals or error("ctx.proposals is required")
    local context = ctx.context or ""
    local threshold = ctx.threshold or 0.6
    local n_contrasts = ctx.n_contrasts or 1

    local factscore = require("factscore")
    local contrastive = require("contrastive")
    local calibrate = require("calibrate")

    -- Normalize proposals to a list
    local proposals
    if type(raw_proposals) == "table" then
        proposals = raw_proposals
    else
        -- Ask LLM to decompose a block of proposals into a numbered list
        local parsed = alc.llm(
            string.format(
                "Extract each distinct proposal from the following text.\n"
                    .. "Output a numbered list, one proposal per line.\n\n"
                    .. "Text:\n\"\"\"\n%s\n\"\"\"",
                raw_proposals
            ),
            { max_tokens = 500 }
        )
        proposals = parse_proposals(parsed)
        if #proposals == 0 then
            proposals = { raw_proposals }
        end
    end

    alc.log("info", string.format("pre_mortem: %d proposals to evaluate", #proposals))

    local context_block = ""
    if context ~= "" then
        context_block = string.format("\n\nKnown constraints:\n%s", context)
    end

    -- Evaluate each proposal through the 3-step pipeline
    local results = {}

    for i, proposal in ipairs(proposals) do
        alc.log("info", string.format("pre_mortem: evaluating proposal %d/%d", i, #proposals))

        -- ─── Step 1: factscore — decompose into prerequisites, verify each ───
        local fs_ctx = factscore.run({
            text = string.format(
                "Proposal: %s\n\n"
                    .. "This proposal is intended to address the following task:\n%s\n\n"
                    .. "List all prerequisites and assumptions that must be true "
                    .. "for this proposal to be feasible and implementable. "
                    .. "Include technical dependencies, platform support, "
                    .. "API availability, and design compatibility.\n\n"
                    .. "IMPORTANT: Include prerequisites about EXTERNAL dependencies "
                    .. "(e.g., host platform support, third-party API availability, "
                    .. "upstream library features). If the proposal requires action "
                    .. "or support from systems outside the implementer's control, "
                    .. "list each such dependency as a separate prerequisite.",
                proposal, task
            ),
            context = context ~= "" and context
                and (context .. "\n\nVerification criteria: "
                    .. "Mark UNSUPPORTED if the prerequisite requires action or support "
                    .. "from external systems that are known to be unavailable or unconfirmed. "
                    .. "Mark UNCERTAIN only when you lack information to judge. "
                    .. "Do NOT mark external-dependency prerequisites as UNCERTAIN "
                    .. "when the context states they are unavailable — mark UNSUPPORTED.")
                or nil,
            verify_tokens = ctx.verify_tokens or 200,
            extract_tokens = ctx.extract_tokens or 500,
        })

        local prereq_result = fs_ctx.result
        local unverified_count = prereq_result.unsupported + prereq_result.uncertain
        local total_prereqs = prereq_result.total

        alc.log("info", string.format(
            "pre_mortem: proposal %d prerequisites — %d supported, %d unsupported, %d uncertain (total %d)",
            i, prereq_result.supported, prereq_result.unsupported,
            prereq_result.uncertain, total_prereqs
        ))

        -- ─── Step 2: contrastive — adoption vs rejection reasoning ───
        local ct_ctx = contrastive.run({
            task = string.format(
                "Should this proposal be adopted?\n\n"
                    .. "Proposal: %s\n"
                    .. "Task it addresses: %s%s\n\n"
                    .. "Prerequisite verification results:\n"
                    .. "- %d/%d prerequisites verified as supported\n"
                    .. "- %d unsupported, %d uncertain",
                proposal, task, context_block,
                prereq_result.supported, total_prereqs,
                prereq_result.unsupported, prereq_result.uncertain
            ),
            n_contrasts = n_contrasts,
        })

        -- Extract rejection reasons from contrastive analysis
        local rejection_reasons = {}
        for _, contrast in ipairs(ct_ctx.result.contrasts) do
            rejection_reasons[#rejection_reasons + 1] = contrast.error_analysis
        end

        -- ─── Step 3: calibrate — assess with confidence gating ───
        --
        -- calibrate's confidence = trust in its own judgment.
        --   high confidence → trust the answer (whatever it says)
        --   low confidence  → escalate; if still low → judgment unreliable
        -- We use confidence solely to gate reliability of the judgment.
        -- The answer text is used to determine adopt/reject.
        local prereq_summary = {}
        for _, claim in ipairs(prereq_result.claims) do
            prereq_summary[#prereq_summary + 1] = string.format(
                "  [%s] %s", claim.status:upper(), claim.claim
            )
        end

        local cal_ctx = calibrate.run({
            task = string.format(
                "Assess this proposal and decide whether to ADOPT or REJECT it.\n\n"
                    .. "Proposal: %s\n"
                    .. "Task: %s%s\n\n"
                    .. "Prerequisite verification results:\n%s\n\n"
                    .. "Rejection risks identified:\n%s\n\n"
                    .. "Evaluate based on:\n"
                    .. "1. Technical feasibility — can it be implemented?\n"
                    .. "2. Task relevance — does it directly address the stated task?\n"
                    .. "3. Self-containment — can the implementer deliver it alone?\n\n"
                    .. "You MUST output both:\n"
                    .. "- VERDICT: ADOPT or REJECT (your judgment on the proposal's value)\n"
                    .. "- CONFIDENCE: 0.0-1.0 (how certain you are about YOUR judgment)\n\n"
                    .. "IMPORTANT: CONFIDENCE measures how sure you are about your VERDICT, "
                    .. "not how good the proposal is. A REJECT with CONFIDENCE 0.9 means "
                    .. "you are very sure the proposal should be rejected.",
                proposal, task, context_block,
                table.concat(prereq_summary, "\n"),
                table.concat(rejection_reasons, "\n---\n")
            ),
            threshold = threshold,
            fallback = "retry",
            gen_tokens = 400,
        })

        local confidence = cal_ctx.result.confidence
        local answer = cal_ctx.result.answer or ""
        local verdict = parse_verdict(answer)

        -- Decision matrix:
        --   confidence is meta-reliability of the judgment, NOT proposal quality.
        --   verdict is the judgment direction (adopt/reject).
        --
        --   High confidence + ADOPT  → judgment reliable, proposal is good → accepted
        --   High confidence + REJECT → judgment reliable, proposal is bad  → rejected
        --   Low confidence (any)     → judgment unreliable → needs_investigation
        --   Unsupported prereqs      → hard reject regardless (as before)
        local status
        if prereq_result.unsupported > 0 then
            status = "rejected"
        elseif confidence < threshold then
            -- Calibrate's judgment is unreliable → cannot decide
            status = "needs_investigation"
        elseif verdict == "adopt" then
            status = "accepted"
        else
            -- High confidence + REJECT → confirmed rejection
            status = "rejected"
        end

        results[#results + 1] = {
            proposal = proposal,
            status = status,
            verdict = verdict,
            confidence = confidence,
            prerequisites = prereq_result,
            rejection_reasons = rejection_reasons,
            contrastive_answer = ct_ctx.result.answer,
            calibrate_detail = cal_ctx.result,
        }

        alc.log("info", string.format(
            "pre_mortem: proposal %d → %s (verdict=%s, confidence=%.2f, unsupported_prereqs=%d)",
            i, status, verdict, confidence, prereq_result.unsupported
        ))
    end

    -- Summary counts
    local accepted_list = {}
    local needs_inv = 0
    local rejected_count = 0
    for _, r in ipairs(results) do
        if r.status == "accepted" then
            accepted_list[#accepted_list + 1] = r
        elseif r.status == "needs_investigation" then
            needs_inv = needs_inv + 1
        else
            rejected_count = rejected_count + 1
        end
    end

    -- ─── Step 4: rank accepted proposals via pairwise tournament ───
    local ranking = {}
    if #accepted_list > 1 then
        alc.log("info", string.format(
            "pre_mortem: ranking %d accepted proposals via pairwise tournament",
            #accepted_list
        ))

        -- Build bracket
        local bracket = {}
        for i, r in ipairs(accepted_list) do
            bracket[i] = { index = i, entry = r, wins = 0 }
        end

        local match_log = {}
        while #bracket > 1 do
            local next_round = {}
            for i = 1, #bracket, 2 do
                if i + 1 <= #bracket then
                    local a = bracket[i]
                    local b = bracket[i + 1]
                    local winner_label, reason = compare_proposals(
                        task, a.entry.proposal, b.entry.proposal, context
                    )
                    local winner, loser
                    if winner_label == "A" then
                        winner = a
                        loser = b
                    else
                        winner = b
                        loser = a
                    end
                    winner.wins = winner.wins + 1
                    match_log[#match_log + 1] = {
                        a = a.entry.proposal,
                        b = b.entry.proposal,
                        winner = winner.entry.proposal,
                        reason = reason,
                    }
                    -- Loser gets ranked lower
                    loser.entry.rank = #accepted_list - #ranking
                    ranking[#ranking + 1] = loser.entry
                    next_round[#next_round + 1] = winner
                else
                    next_round[#next_round + 1] = bracket[i]
                end
            end
            bracket = next_round
        end
        -- Winner is rank 1
        bracket[1].entry.rank = 1
        -- Insert remaining (winner first, then losers in reverse order)
        table.insert(ranking, 1, bracket[1].entry)
        -- Re-assign ranks sequentially
        for i, r in ipairs(ranking) do
            r.rank = i
        end

        alc.log("info", string.format(
            "pre_mortem: ranking complete — top proposal: %s",
            ranking[1].proposal:sub(1, 80)
        ))
    elseif #accepted_list == 1 then
        accepted_list[1].rank = 1
        ranking = accepted_list
    end

    -- Build final sorted results: ranked accepted → needs_investigation → rejected
    local sorted = {}
    for _, r in ipairs(ranking) do
        sorted[#sorted + 1] = r
    end
    for _, r in ipairs(results) do
        if r.status == "needs_investigation" then
            sorted[#sorted + 1] = r
        end
    end
    for _, r in ipairs(results) do
        if r.status == "rejected" then
            sorted[#sorted + 1] = r
        end
    end

    alc.log("info", string.format(
        "pre_mortem: complete — %d accepted (ranked), %d needs_investigation, %d rejected",
        #accepted_list, needs_inv, rejected_count
    ))

    ctx.result = {
        proposals = sorted,
        accepted = #accepted_list,
        needs_investigation = needs_inv,
        rejected = rejected_count,
        total = #results,
        ranking = ranking,
    }
    return ctx
end

-- Malli-style self-decoration (see alc_shapes/README). inline T.shape
-- for both input and result; wrapper validates in ALC_SHAPE_CHECK=1.
M.run = S.instrument(M, "run")

return M
