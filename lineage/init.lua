--- lineage — Pipeline-spanning claim lineage tracking
---
--- Tracks the provenance of claims across multi-step pipelines.
--- Extracts atomic claims from each step's output, traces inter-step
--- dependencies (which claim in step N derived from which claim in step N-1),
--- and detects conflicts and ungrounded claims in the final output.
---
--- Generalizes the "lineage graph governance layer" concept from
--- "From Spark to Fire: Diagnosing and Overcoming the Fragility of
--- Multi-Agent Systems" (Xie et al., AAMAS 2026), which demonstrated
--- that a provenance-tracking middleware improves pipeline defense rate
--- from 0.32 to 0.89 against cascade errors — without changing the
--- underlying model.
---
--- Also informed by MAST (Cemri et al., 2025), which found that 41.8%
--- of multi-agent system failures originate from system design rather
--- than model performance. Lineage tracking addresses the "information
--- loss at handoff" failure mode (MAST category F7).
---
--- Pipeline (~2×N LLM calls, N = number of steps):
---   Step 1: Extract atomic claims from each step output (N calls, parallel)
---   Step 2: Trace inter-step dependencies (N-1 calls, parallel per step pair)
---   Step 3: Detect conflicts and ungrounded claims (1 call)
---   Total: N + (N-1) + 1 = 2N
---
--- Usage:
---   local lineage = require("lineage")
---   return lineage.run(ctx)
---
--- ctx.task (required): Original task description
--- ctx.steps (required): Ordered table of step outputs
---     Each entry: { name = "step_name", output = "text" }
---     Example: { {name="plan", output="..."}, {name="implement", output="..."} }
--- ctx.extract_tokens: Max tokens for claim extraction (default: 600)
--- ctx.trace_tokens: Max tokens for dependency tracing (default: 500)
--- ctx.summary_tokens: Max tokens for final summary (default: 600)

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "lineage",
    version = "0.1.0",
    description = "Pipeline-spanning claim lineage tracking — extracts claims "
        .. "per step, traces inter-step dependencies, detects conflicts and "
        .. "ungrounded claims. Generalizes the lineage graph governance layer "
        .. "from 'From Spark to Fire' (Xie et al., AAMAS 2026). "
        .. "Defense rate improvement: 0.32 → 0.89.",
    category = "governance",
}

local input_step_shape = T.shape({
    name   = T.string:describe("Step name used to key claims and traces"),
    output = T.string:describe("Text output of this step"),
})

local claim_shape = T.shape({
    id   = T.number:describe("Claim number parsed from the extractor output"),
    text = T.string:describe("Atomic factual claim text"),
})

local step_claims_shape = T.shape({
    name   = T.string:describe("Step name (echo)"),
    claims = T.array_of(claim_shape):describe("Atomic claims parsed from the step's output"),
    raw    = T.string:describe("Raw LLM extractor output"),
})

local trace_entry_shape = T.shape({
    id             = T.number:describe("Current-step claim id whose provenance is being described"),
    derives_from   = T.array_of(T.any):is_optional():describe(
        "Provenance list. Element type is heterogeneous by design: "
        .. "either a list of previous-step claim numbers (number), "
        .. "or the single-string marker {\"ORIGINAL_INPUT\"}, "
        .. "or {} for NOVEL/NONE. Declared as T.array_of(T.any) because "
        .. "T.one_of only accepts literal values and T.array_of needs a "
        .. "single element type; this follows the codebase convention "
        .. "used in condorcet/shapley/kemeny/mwu/scoring_rule."),
    transformation = T.string:is_optional():describe("PRESERVED|REFINED|MERGED|INFERRED|NOVEL"),
})

local trace_shape = T.shape({
    from_step = T.string:describe("Previous step name"),
    to_step   = T.string:describe("Current step name"),
    traces    = T.array_of(trace_entry_shape):describe("Per-current-claim provenance entries"),
    raw       = T.string:describe("Raw LLM trace output"),
})

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task           = T.string:describe("Original task description passed to trace/summary prompts (required)"),
                steps          = T.array_of(input_step_shape):describe("Ordered step outputs; at least 2 entries (required)"),
                extract_tokens = T.number:is_optional():describe("Max tokens per claim extraction (default 600)"),
                trace_tokens   = T.number:is_optional():describe("Max tokens per dependency trace (default 500)"),
                summary_tokens = T.number:is_optional():describe("Max tokens for conflict/integrity summary (default 600)"),
            }),
            result = T.shape({
                step_claims     = T.array_of(step_claims_shape):describe("Per-step extracted claims"),
                traces          = T.array_of(trace_shape):describe("Consecutive-step dependency traces"),
                lineage_graph   = T.string:describe("Human-readable lineage graph text used as input to the conflict analyzer"),
                analysis        = T.string:describe("Full conflict/ungrounded/drift analyzer output"),
                integrity_score = T.number:is_optional():describe("Parsed SCORE in [0, 1]; nil when the analyzer did not emit a parseable score"),
            }),
        },
    },
}

-- ─── Prompts ───

local EXTRACT_SYSTEM = [[You are a precise claim extractor. Extract every atomic factual claim from the given text. Each claim should be self-contained and verifiable.

Rules:
- One claim per line, numbered sequentially
- Each claim must be a single, atomic assertion
- Include implicit claims (assumptions, preconditions)
- Preserve the original meaning precisely
- Do NOT add interpretation or inference]]

local EXTRACT_PROMPT = [[Step: {name}

Text:
{output}

Extract all atomic claims from this text. Number each claim.]]

local TRACE_SYSTEM = [[You are a provenance analyst. For each claim in the CURRENT step, determine which claim(s) in the PREVIOUS step it derives from.

Respond in this exact format for each current claim:
CLAIM <current_num>: <brief claim text>
DERIVES_FROM: <comma-separated previous claim numbers, or "NONE" if novel, or "ORIGINAL_INPUT" if from the task itself>
TRANSFORMATION: <how the claim was derived: PRESERVED | REFINED | MERGED | INFERRED | NOVEL>

Rules:
- PRESERVED: claim carried forward unchanged
- REFINED: claim narrowed or made more specific
- MERGED: claim combines multiple previous claims
- INFERRED: claim logically follows but was not explicitly stated
- NOVEL: claim has no traceable origin in previous step]]

local TRACE_PROMPT = [[Original task: {task}

PREVIOUS STEP ({prev_name}) claims:
{prev_claims}

CURRENT STEP ({curr_name}) claims:
{curr_claims}

For each current claim, identify its provenance from the previous step's claims.]]

local CONFLICT_SYSTEM = [[You are a consistency auditor. Analyze the full claim lineage graph and identify:

1. CONFLICTS: Claims that contradict each other (within or across steps)
2. UNGROUNDED: Final-step claims with no traceable origin (NOVEL chains that appear only at the end)
3. DRIFT: Claims whose meaning shifted significantly through the pipeline

Respond in this format:
## Conflicts
- CONFLICT: [step_X claim_N] vs [step_Y claim_M]: <explanation>
(or "None detected")

## Ungrounded Claims
- UNGROUNDED: [step_X claim_N]: <explanation of why it lacks provenance>
(or "None detected")

## Drift
- DRIFT: [step_X claim_N] → [step_Y claim_M]: <how meaning shifted>
(or "None detected")

## Integrity Score
SCORE: <0.0 to 1.0> (1.0 = fully traceable, no conflicts)]]

local CONFLICT_PROMPT = [[Original task: {task}

Full lineage graph:
{lineage_graph}

Analyze for conflicts, ungrounded claims, and semantic drift.]]

-- ─── Helpers ───

local function expand(template, vars)
    local result = template
    for k, v in pairs(vars) do
        local sv = tostring(v)
        result = result:gsub("{" .. k .. "}", function() return sv end)
    end
    return result
end

local function parse_claims(raw)
    local claims = {}
    for line in raw:gmatch("[^\n]+") do
        local num, text = line:match("^%s*(%d+)[%.%)%s]+(.+)")
        if text then
            text = text:match("^%s*(.-)%s*$")
            if #text > 5 then
                claims[#claims + 1] = { id = tonumber(num), text = text }
            end
        end
    end
    return claims
end

local function format_claims(claims, step_name)
    local lines = {}
    for _, c in ipairs(claims) do
        lines[#lines + 1] = string.format("[%s claim_%d] %s", step_name, c.id, c.text)
    end
    return table.concat(lines, "\n")
end

local function parse_traces(raw)
    local traces = {}
    local current = nil
    for line in raw:gmatch("[^\n]+") do
        local num = line:match("^CLAIM%s+(%d+)")
        if num then
            current = { id = tonumber(num) }
            traces[#traces + 1] = current
        end
        local derives = line:match("^DERIVES_FROM:%s*(.+)")
        if derives and current then
            derives = derives:match("^%s*(.-)%s*$")
            if derives == "NONE" or derives == "NOVEL" then
                current.derives_from = {}
            elseif derives == "ORIGINAL_INPUT" then
                current.derives_from = { "ORIGINAL_INPUT" }
            else
                current.derives_from = {}
                for n in derives:gmatch("%d+") do
                    current.derives_from[#current.derives_from + 1] = tonumber(n)
                end
            end
        end
        local trans = line:match("^TRANSFORMATION:%s*(.+)")
        if trans and current then
            current.transformation = trans:match("^%s*(.-)%s*$")
        end
    end
    return traces
end

local function parse_score(raw)
    local score = raw:match("SCORE:%s*(%d*%.?%d+)")
    if score then
        return math.max(0, math.min(1, tonumber(score)))
    end
    return nil
end

-- ─── Main ───

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local steps = ctx.steps or error("ctx.steps is required")
    if #steps < 2 then
        error("ctx.steps must contain at least 2 steps for lineage tracking")
    end

    local extract_tokens = ctx.extract_tokens or 600
    local trace_tokens = ctx.trace_tokens or 500
    local summary_tokens = ctx.summary_tokens or 600

    alc.log("info", string.format("lineage: tracking %d steps", #steps))

    -- Phase 1: Extract claims from each step (parallel)
    local step_claims = alc.map(steps, function(step)
        local prompt = expand(EXTRACT_PROMPT, {
            name = step.name,
            output = step.output,
        })
        local raw = alc.llm(prompt, {
            system = EXTRACT_SYSTEM,
            max_tokens = extract_tokens,
        })
        return {
            name = step.name,
            claims = parse_claims(raw),
            raw = raw,
        }
    end)

    alc.log("info", string.format(
        "lineage: extracted claims — %s",
        table.concat((function()
            local counts = {}
            for _, sc in ipairs(step_claims) do
                counts[#counts + 1] = string.format("%s:%d", sc.name, #sc.claims)
            end
            return counts
        end)(), ", ")
    ))

    -- Phase 2: Trace dependencies between consecutive steps (parallel)
    local trace_pairs = {}
    for i = 2, #step_claims do
        trace_pairs[#trace_pairs + 1] = { prev = step_claims[i - 1], curr = step_claims[i] }
    end

    local trace_results = alc.map(trace_pairs, function(pair)
        local prev_formatted = format_claims(pair.prev.claims, pair.prev.name)
        local curr_formatted = format_claims(pair.curr.claims, pair.curr.name)

        local prompt = expand(TRACE_PROMPT, {
            task = task,
            prev_name = pair.prev.name,
            curr_name = pair.curr.name,
            prev_claims = prev_formatted,
            curr_claims = curr_formatted,
        })
        local raw = alc.llm(prompt, {
            system = TRACE_SYSTEM,
            max_tokens = trace_tokens,
        })
        return {
            from_step = pair.prev.name,
            to_step = pair.curr.name,
            traces = parse_traces(raw),
            raw = raw,
        }
    end)

    -- Phase 3: Build lineage graph text for conflict analysis
    local graph_lines = {}
    for _, sc in ipairs(step_claims) do
        graph_lines[#graph_lines + 1] = string.format("=== %s (%d claims) ===", sc.name, #sc.claims)
        graph_lines[#graph_lines + 1] = format_claims(sc.claims, sc.name)
        graph_lines[#graph_lines + 1] = ""
    end
    for _, tr in ipairs(trace_results) do
        graph_lines[#graph_lines + 1] = string.format("--- Dependencies: %s → %s ---", tr.from_step, tr.to_step)
        for _, t in ipairs(tr.traces) do
            local derives_str
            if #t.derives_from == 0 then
                derives_str = "NOVEL"
            elseif t.derives_from[1] == "ORIGINAL_INPUT" then
                derives_str = "ORIGINAL_INPUT"
            else
                local nums = {}
                for _, n in ipairs(t.derives_from) do
                    nums[#nums + 1] = string.format("[%s claim_%d]", tr.from_step, n)
                end
                derives_str = table.concat(nums, ", ")
            end
            graph_lines[#graph_lines + 1] = string.format(
                "  [%s claim_%d] ← %s (%s)",
                tr.to_step, t.id, derives_str, t.transformation or "unknown"
            )
        end
        graph_lines[#graph_lines + 1] = ""
    end
    local lineage_graph = table.concat(graph_lines, "\n")

    -- Phase 4: Conflict and integrity analysis
    local conflict_prompt = expand(CONFLICT_PROMPT, {
        task = task,
        lineage_graph = lineage_graph,
    })
    local analysis_raw = alc.llm(conflict_prompt, {
        system = CONFLICT_SYSTEM,
        max_tokens = summary_tokens,
    })

    local integrity_score = parse_score(analysis_raw)

    alc.log("info", string.format(
        "lineage: integrity_score=%s",
        integrity_score and string.format("%.2f", integrity_score) or "N/A"
    ))
    alc.stats.record("lineage_steps", #steps)
    alc.stats.record("lineage_integrity", integrity_score or -1)

    ctx.result = {
        step_claims = step_claims,
        traces = trace_results,
        lineage_graph = lineage_graph,
        analysis = analysis_raw,
        integrity_score = integrity_score,
    }
    return ctx
end

M.run = S.instrument(M, "run")

return M
