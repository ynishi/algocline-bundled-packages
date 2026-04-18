--- bisect — Binary search for reasoning errors
---
--- Instead of verifying every step of a reasoning chain (O(n)),
--- bisects the chain to locate the first error in O(log n) steps.
--- Once found, regenerates only the erroneous step and continues.
---
--- Inspired by: Process Reward Models and step-level verification
---              (arXiv 2410.08146, "Rewarding Progress", 2024)
---              + git bisect methodology applied to reasoning chains
---
--- Pipeline:
---   Step 1: generate   — produce a full reasoning chain (numbered steps)
---   Step 2: bisect     — binary search for first incorrect step
---   Step 3: regenerate — re-derive from the last correct step
---
--- Usage:
---   local bisect = require("bisect")
---   return bisect.run(ctx)
---
--- ctx.task (required): The task/question to solve
--- ctx.max_repairs: Maximum number of bisect→repair cycles (default: 2)
--- ctx.gen_tokens: Max tokens for chain generation (default: 800)
--- ctx.verify_tokens: Max tokens per verification (default: 200)

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "bisect",
    version = "0.1.0",
    description = "Binary search for reasoning errors — locate first incorrect step in O(log n), then regenerate from that point",
    category = "debugging",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task          = T.string:describe("The task/question to solve"),
                max_repairs   = T.number:is_optional():describe("Maximum number of bisect→repair cycles (default: 2)"),
                gen_tokens    = T.number:is_optional():describe("Max tokens for chain generation (default: 800)"),
                verify_tokens = T.number:is_optional():describe("Max tokens per verification (default: 200)"),
            }),
            result = T.shape({
                answer        = T.string:describe("Final reasoning chain after all repairs"),
                initial_chain = T.string:describe("Original pre-repair reasoning chain"),
                repairs       = T.array_of(T.shape({
                    repair_round  = T.number:describe("1-based repair iteration index"),
                    error_step    = T.number:describe("Step index of the first incorrect step located"),
                    error_label   = T.string:describe("Label text of the erroneous step (e.g., 'Step 3:')"),
                    error_content = T.string:describe("Content of the erroneous step"),
                    bisect_log    = T.array_of(T.shape({
                        lo      = T.number:describe("Binary-search low bound at probe time"),
                        hi      = T.number:describe("Binary-search high bound at probe time"),
                        mid     = T.number:describe("Probed midpoint"),
                        correct = T.boolean:describe("Whether steps 1..mid were verified correct"),
                        reason  = T.string:describe("Verifier's one-sentence justification"),
                    })):describe("Per-probe binary-search log"),
                    regenerated   = T.string:describe("Regenerated suffix from the failure point"),
                })):describe("Per-cycle repair records"),
                total_repairs = T.number:describe("Number of repair cycles applied"),
            }),
        },
    },
}

--- Parse a numbered reasoning chain into a list of steps.
local function parse_steps(text)
    local steps = {}
    -- Match "Step N:" or "N." or "N)" patterns
    for num, content in text:gmatch("([Ss]tep%s*%d+[%.:%)]?)%s*(.-)%s*\n") do
        if #content > 5 then
            steps[#steps + 1] = { label = num, content = content }
        end
    end
    if #steps == 0 then
        -- Fallback: numbered list "1. ... \n 2. ..."
        for num, content in text:gmatch("(%d+)[%.%)%s]+(.-)%s*\n") do
            if #content > 5 then
                steps[#steps + 1] = { label = "Step " .. num, content = content }
            end
        end
    end
    -- Last line may not end with \n
    if #steps == 0 then
        steps[#steps + 1] = { label = "Step 1", content = text }
    end
    return steps
end

--- Verify whether steps 1..mid are correct given the task.
--- Returns true if the reasoning up to step mid is sound.
local function verify_up_to(task, steps, mid, verify_tokens)
    local chain = {}
    for i = 1, mid do
        chain[#chain + 1] = string.format("%s: %s", steps[i].label, steps[i].content)
    end

    local verdict = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Below are the first %d steps of a reasoning chain. "
                .. "Are ALL of these steps logically correct?\n\n"
                .. "%s\n\n"
                .. "Answer with exactly one word: CORRECT or INCORRECT\n"
                .. "Then one sentence explaining why.",
            task, mid, table.concat(chain, "\n")
        ),
        {
            system = "You are a rigorous step-by-step verifier. "
                .. "Check each step for logical errors, wrong calculations, "
                .. "or invalid assumptions. Answer CORRECT only if ALL steps "
                .. "shown are sound.",
            max_tokens = verify_tokens,
        }
    )

    local is_correct = not verdict:upper():match("INCORRECT")
    return is_correct, verdict
end

--- Binary search for the first incorrect step.
--- Returns the index of the first bad step, or nil if all correct.
local function find_first_error(task, steps, verify_tokens)
    local n = #steps
    if n == 0 then return nil end

    -- First check: is the entire chain correct?
    local all_ok, _ = verify_up_to(task, steps, n, verify_tokens)
    if all_ok then
        return nil  -- No errors found
    end

    -- Binary search: find smallest mid where steps[1..mid] contains an error
    local lo, hi = 1, n
    local bisect_log = {}

    while lo < hi do
        local mid = math.floor((lo + hi) / 2)

        alc.log("info", string.format(
            "bisect: checking steps 1..%d (lo=%d, hi=%d)", mid, lo, hi
        ))

        local ok, reason = verify_up_to(task, steps, mid, verify_tokens)

        bisect_log[#bisect_log + 1] = {
            lo = lo, hi = hi, mid = mid,
            correct = ok, reason = reason,
        }

        if ok then
            lo = mid + 1  -- Error is after mid
        else
            hi = mid      -- Error is at or before mid
        end
    end

    return lo, bisect_log
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local max_repairs = ctx.max_repairs or 2
    local gen_tokens = ctx.gen_tokens or 800
    local verify_tokens = ctx.verify_tokens or 200

    -- ─── Step 1: Generate full reasoning chain ───
    local chain_text = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Solve this step by step. Number each step clearly.\n"
                .. "Format:\n"
                .. "Step 1: [first reasoning step]\n"
                .. "Step 2: [second reasoning step]\n"
                .. "...\n"
                .. "Final Answer: [your answer]",
            task
        ),
        {
            system = "You are an expert problem solver. Break your reasoning "
                .. "into clearly numbered steps. Each step should contain "
                .. "exactly one logical move or calculation.",
            max_tokens = gen_tokens,
        }
    )

    alc.log("info", string.format(
        "bisect: initial chain generated (%d chars)", #chain_text
    ))

    local repairs = {}
    local current_chain = chain_text

    for repair = 1, max_repairs do
        local steps = parse_steps(current_chain)
        alc.log("info", string.format(
            "bisect: parsed %d steps, searching for errors (repair %d/%d)",
            #steps, repair, max_repairs
        ))

        if #steps <= 1 then
            alc.log("info", "bisect: chain too short to bisect, skipping")
            break
        end

        local error_idx, bisect_log = find_first_error(task, steps, verify_tokens)

        if not error_idx then
            alc.log("info", "bisect: no errors found, chain is correct")
            break
        end

        alc.log("info", string.format(
            "bisect: first error at step %d ('%s')",
            error_idx, steps[error_idx].label
        ))

        -- ─── Step 3: Regenerate from last correct step ───
        local correct_prefix = {}
        for i = 1, error_idx - 1 do
            correct_prefix[#correct_prefix + 1] = string.format(
                "%s: %s", steps[i].label, steps[i].content
            )
        end

        local prefix_text = #correct_prefix > 0
            and table.concat(correct_prefix, "\n")
            or "(no correct steps)"

        local regenerated = alc.llm(
            string.format(
                "Task: %s\n\n"
                    .. "The following steps are verified as correct:\n%s\n\n"
                    .. "Step %d was found to be INCORRECT. "
                    .. "Continue the reasoning from after the last correct step. "
                    .. "Number your steps starting from Step %d.\n"
                    .. "End with: Final Answer: [your answer]",
                task, prefix_text, error_idx, error_idx
            ),
            {
                system = "You are an expert. The previous steps are verified correct. "
                    .. "A specific step was found to contain an error. "
                    .. "Re-derive the solution from the point of failure. "
                    .. "Be extra careful at the step that previously failed.",
                max_tokens = gen_tokens,
            }
        )

        -- Merge: correct prefix + regenerated suffix
        local merged
        if #correct_prefix > 0 then
            merged = prefix_text .. "\n" .. regenerated
        else
            merged = regenerated
        end

        repairs[#repairs + 1] = {
            repair_round = repair,
            error_step = error_idx,
            error_label = steps[error_idx].label,
            error_content = steps[error_idx].content,
            bisect_log = bisect_log,
            regenerated = regenerated,
        }

        current_chain = merged
    end

    alc.log("info", string.format(
        "bisect: complete — %d repair(s) applied", #repairs
    ))

    ctx.result = {
        answer = current_chain,
        initial_chain = chain_text,
        repairs = repairs,
        total_repairs = #repairs,
    }
    return ctx
end

-- Malli-style self-decoration (see alc_shapes/README). inline T.shape
-- for both input and result; wrapper validates in ALC_SHAPE_CHECK=1.
M.run = S.instrument(M, "run")

return M
