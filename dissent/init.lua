--- dissent — Consensus inertia prevention via forced adversarial challenge
---
--- Before finalizing any multi-agent consensus, injects a dedicated
--- adversarial agent that challenges the emerging agreement. Evaluates
--- the dissent's validity and produces a revised consensus only when
--- the challenge has merit. Prevents premature lock-in of incorrect
--- conclusions.
---
--- Generalizes the "Consensus Inertia" countermeasure from "From Spark
--- to Fire: Diagnosing and Overcoming the Fragility of Multi-Agent
--- Systems" (Xie et al., AAMAS 2026). The paper found that once a
--- multi-agent group converges on an incorrect answer, baseline systems
--- fail to recover (defense rate 0.32). Forced adversarial challenge
--- at the consensus boundary is one of the key architectural
--- interventions that raises defense to 0.89.
---
--- Also related to MAST (Cemri et al., 2025) failure mode F11:
--- "groupthink convergence" where agents reinforce each other's errors.
---
--- Composable: wrap around moa, panel, sc, or any strategy that
--- produces a consensus output.
---
--- Pipeline (3-4 LLM calls):
---   Step 1: Adversarial challenge — dedicated dissenter attacks consensus
---   Step 2: Merit evaluation — independent judge assesses dissent validity
---   Step 3: Revision (conditional) — if dissent has merit, revise consensus
---   Step 4: Final synthesis — produce final output with dissent metadata
---
--- Usage:
---   local dissent = require("dissent")
---   return dissent.run(ctx)
---
--- ctx.task (required): Original task description
--- ctx.consensus (required): The consensus text to challenge
--- ctx.perspectives (optional): Individual agent outputs that formed consensus
--- ctx.merit_threshold (optional): Score threshold for revision (default: 0.6)
--- ctx.gen_tokens: Max tokens per generation (default: 500)

local M = {}

---@type AlcMeta
M.meta = {
    name = "dissent",
    version = "0.1.0",
    description = "Consensus inertia prevention — forces adversarial challenge "
        .. "before finalizing multi-agent agreement. Prevents groupthink "
        .. "lock-in. Generalizes the Consensus Inertia countermeasure from "
        .. "'From Spark to Fire' (Xie et al., AAMAS 2026). "
        .. "Composable with moa, panel, sc.",
    category = "governance",
}

-- ─── Prompts ───

local DISSENT_SYSTEM = [[You are a rigorous adversarial analyst. Your SOLE purpose is to find weaknesses, errors, and blind spots in the given consensus. You are NOT trying to be balanced or fair — you are trying to break the consensus.

Rules:
- Challenge EVERY major claim
- Look for: logical gaps, unsupported assumptions, missing perspectives, factual errors, oversimplifications
- Be specific: quote the exact part you challenge and explain why
- Propose at least one concrete alternative interpretation or conclusion
- Do NOT hedge. Do NOT agree with any part of the consensus
- Structure your dissent with numbered challenges]]

local DISSENT_PROMPT_WITH_PERSPECTIVES = [[Original task: {task}

Individual perspectives that formed the consensus:
{perspectives}

CONSENSUS reached:
{consensus}

Attack this consensus. Find every weakness, error, and blind spot.]]

local DISSENT_PROMPT_BASIC = [[Original task: {task}

CONSENSUS:
{consensus}

Attack this consensus. Find every weakness, error, and blind spot.]]

local JUDGE_SYSTEM = [[You are an impartial evaluation judge. Assess whether the adversarial dissent raises valid concerns about the consensus.

For each challenge raised by the dissenter, evaluate:
- VALID: The challenge identifies a genuine flaw
- PARTIAL: The challenge has some merit but overstates the issue
- INVALID: The challenge is wrong or irrelevant

Then provide an overall merit score.

Respond in this format:
## Challenge Evaluations
1. <challenge summary>: VALID | PARTIAL | INVALID — <brief reasoning>
2. ...

## Overall Assessment
MERIT_SCORE: <0.0 to 1.0> (proportion of valid/partial challenges)
REVISION_NEEDED: YES | NO
KEY_ISSUES: <comma-separated list of issues that genuinely need addressing>]]

local JUDGE_PROMPT = [[Original task: {task}

CONSENSUS:
{consensus}

ADVERSARIAL DISSENT:
{dissent}

Evaluate whether the dissent raises valid concerns.]]

local REVISE_SYSTEM = [[You are a consensus reviser. Given the original consensus and validated criticisms, produce an improved version that addresses the legitimate issues while preserving the valid parts of the original.

Rules:
- Only change what the validated criticisms require
- Do not weaken claims that were not challenged
- Clearly note what changed and why
- If a criticism reveals missing nuance, add it
- If a criticism reveals an error, correct it

Format:
## Revised Consensus
<the improved consensus text>

## Changes Made
- <what changed and which criticism it addresses>]]

local REVISE_PROMPT = [[Original task: {task}

ORIGINAL CONSENSUS:
{consensus}

VALIDATED ISSUES:
{key_issues}

FULL DISSENT (for context):
{dissent}

Revise the consensus to address only the validated issues.]]

-- ─── Helpers ───

local function expand(template, vars)
    local result = template
    for k, v in pairs(vars) do
        local sv = tostring(v)
        result = result:gsub("{" .. k .. "}", function() return sv end)
    end
    return result
end

local function parse_merit_score(raw)
    local score = raw:match("MERIT_SCORE:%s*(%d*%.?%d+)")
    if score then
        return math.max(0, math.min(1, tonumber(score)))
    end
    return nil
end

local function parse_revision_needed(raw)
    local val = raw:match("REVISION_NEEDED:%s*(%a+)")
    if val then
        return val:upper() == "YES"
    end
    return false
end

local function parse_key_issues(raw)
    local issues = raw:match("KEY_ISSUES:%s*(.+)")
    if issues then
        return issues:match("^%s*(.-)%s*$")
    end
    return ""
end

-- ─── Main ───

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local consensus = ctx.consensus or error("ctx.consensus is required")
    local perspectives = ctx.perspectives
    local merit_threshold = ctx.merit_threshold or 0.6
    local gen_tokens = ctx.gen_tokens or 500

    alc.log("info", "dissent: generating adversarial challenge")

    -- Phase 1: Generate adversarial dissent
    local dissent_prompt
    if perspectives and #perspectives > 0 then
        local perspective_text
        if type(perspectives[1]) == "string" then
            local parts = {}
            for i, p in ipairs(perspectives) do
                parts[#parts + 1] = string.format("--- Perspective %d ---\n%s", i, p)
            end
            perspective_text = table.concat(parts, "\n\n")
        else
            local parts = {}
            for i, p in ipairs(perspectives) do
                local name = p.name or ("Agent " .. i)
                parts[#parts + 1] = string.format("--- %s ---\n%s", name, p.output or p.text or "")
            end
            perspective_text = table.concat(parts, "\n\n")
        end
        dissent_prompt = expand(DISSENT_PROMPT_WITH_PERSPECTIVES, {
            task = task,
            perspectives = perspective_text,
            consensus = consensus,
        })
    else
        dissent_prompt = expand(DISSENT_PROMPT_BASIC, {
            task = task,
            consensus = consensus,
        })
    end

    local dissent_raw = alc.llm(dissent_prompt, {
        system = DISSENT_SYSTEM,
        max_tokens = gen_tokens,
    })

    -- Phase 2: Evaluate dissent merit
    alc.log("info", "dissent: evaluating challenge merit")

    local judge_prompt = expand(JUDGE_PROMPT, {
        task = task,
        consensus = consensus,
        dissent = dissent_raw,
    })
    local judge_raw = alc.llm(judge_prompt, {
        system = JUDGE_SYSTEM,
        max_tokens = gen_tokens,
    })

    local merit_score = parse_merit_score(judge_raw) or 0
    local revision_needed = parse_revision_needed(judge_raw)
    local key_issues = parse_key_issues(judge_raw)

    alc.log("info", string.format(
        "dissent: merit_score=%.2f, revision_needed=%s",
        merit_score, tostring(revision_needed)
    ))

    -- Phase 3: Revise if warranted
    local revised = nil
    local consensus_held = true

    if revision_needed and merit_score >= merit_threshold and #key_issues > 0 then
        alc.log("info", "dissent: revising consensus")

        local revise_prompt = expand(REVISE_PROMPT, {
            task = task,
            consensus = consensus,
            key_issues = key_issues,
            dissent = dissent_raw,
        })
        revised = alc.llm(revise_prompt, {
            system = REVISE_SYSTEM,
            max_tokens = gen_tokens,
        })
        consensus_held = false
    end

    alc.stats.record("dissent_merit_score", merit_score)
    alc.stats.record("dissent_revised", consensus_held and 0 or 1)

    ctx.result = {
        dissent = dissent_raw,
        evaluation = judge_raw,
        merit_score = merit_score,
        key_issues = key_issues,
        revised_consensus = revised,
        consensus_held = consensus_held,
        output = consensus_held and consensus or revised,
    }
    return ctx
end

return M
