--- E2E: recipe_ranking_funnel — N<6 bypass path
---
--- Run: agent-block -s scripts/e2e/recipe_ranking_funnel_bypass.lua -p .
---
--- Covers the bypass branch (N<6 → direct pairwise allpair), which was
--- added as P6 of the recipe-packages review. Validates:
---   - funnel_bypassed = true
---   - bypass_reason contains "N < 6"
---   - savings_percent is nil (not 0)  ← the P6 fix
---   - stages[1..3] are all emitted (listwise_skipped, scoring_skipped,
---     pairwise_direct)
---   - ranking shape matches main path: { rank, text, original_index,
---     pairwise_score }
---
--- Flow (N=4, allpair bidirectional pairwise):
---   Stage 1 (listwise)  : 0 LLM calls (skipped)
---   Stage 2 (scoring)   : 0 LLM calls (skipped)
---   Stage 3 (pairwise)  : N·(N-1) = 12 LLM calls (4·3 bidirectional)
---   Total               : ~12 LLM calls

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local params = {
    task = "Rank these programming languages by TIOBE Index rank "
        .. "(most popular first) as of 2026.",
    candidates = {
        "Rust",
        "Python",
        "JavaScript",
        "Go",
    },
    opts = {
        gen_tokens = 200,
    },
}

local prompt = string.format([[
Use algocline to rank candidates with the recipe_ranking_funnel.

Call alc_advice with:
- package: "recipe_ranking_funnel"
- task: %q
- opts: {
    candidates = { %s },
    gen_tokens = %d
  }

This is a SMALL candidate set (N=4 < 6) so the recipe will BYPASS the
3-stage funnel and run direct pairwise allpair instead. Expect ~12
pairwise LLM calls (4·3 bidirectional), no listwise or scoring.

Each call returns status "needs_response" — reply through alc_continue
with session_id + your genuine answer.

IMPORTANT: You ARE the LLM. Answer based on real-world knowledge about
TIOBE Index popularity in 2026. Pairwise prompts: pick one candidate
per the prompt's output format.

When the recipe completes, report:
1. Final top-1 language
2. Full ranking (all 4)
3. Total LLM calls reported by the recipe
4. funnel_bypassed flag (should be true)
5. bypass_reason (should mention "N < 6")
6. savings_percent (should be nil, not 0)
]],
    params.task,
    table.concat(
        (function()
            local quoted = {}
            for i, c in ipairs(params.candidates) do
                quoted[i] = string.format("%q", c)
            end
            return quoted
        end)(),
        ", "
    ),
    params.opts.gen_tokens
)

common.run({
    name = "recipe_ranking_funnel_bypass",
    prompt = prompt,
    params = params,
    max_iterations = 25,
    graders = {
        common.grader_agent_ok(),
        common.grader_content_contains("Python", "mentions_python"),
        common.grader_max_turns(20),
        common.grader_max_tokens(200000),
        {
            -- Python should dominate TIOBE 2026 (top 1 for ~2 years).
            name = "python_top_ranked",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                local idx = c:find("Python", 1, true)
                if not idx then return false, "Python not mentioned" end
                local window = c:sub(math.max(1, idx - 60), idx + 120):lower()
                if window:find("top")
                    or window:find("first")
                    or window:find("#1")
                    or window:find("1%.")
                    or window:find("1%)")
                    or window:find("rank 1")
                then
                    return true, nil
                end
                return false, "Python mentioned but not flagged as top-1"
            end,
        },
        {
            -- Bypass path MUST be taken at N=4.
            name = "funnel_bypassed_true",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                -- Look for "bypass" near "true" / "yes" / "taken" / "bypassed"
                if c:find("bypass") then
                    local bidx = c:find("bypass")
                    local win = c:sub(math.max(1, bidx - 30), bidx + 80)
                    if win:find("true", 1, true)
                        or win:find("yes", 1, true)
                        or win:find("taken", 1, true)
                    then
                        return true, nil
                    end
                    -- Sometimes the agent writes "funnel_bypassed: true" in JSON form
                    if c:find("bypassed.-true") then return true, nil end
                end
                return false, "funnel_bypassed=true not reported"
            end,
        },
        {
            -- savings_percent should be nil (P6 fix); content may contain
            -- "nil" / "n/a" / "not applicable" / "null" — accept any.
            name = "savings_percent_nil",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("savings") then
                    local sidx = c:find("savings")
                    local win = c:sub(sidx, sidx + 80)
                    if win:find("nil", 1, true)
                        or win:find("n/a", 1, true)
                        or win:find("null", 1, true)
                        or win:find("not applicable", 1, true)
                        or win:find("undefined", 1, true)
                    then
                        return true, nil
                    end
                    -- If the agent reports "savings: 0" that is the old
                    -- (buggy) behavior — fail.
                    if win:find("0%%") or win:find(": 0") or win:find("=0") then
                        return false, "savings reported as 0 (P6 regression)"
                    end
                end
                -- If the agent simply did not mention savings, that is OK
                -- as long as the bypass was reported.
                return true, nil
            end,
        },
        {
            -- Content should mention "N < 6" or "bypass reason" or similar.
            name = "reports_bypass_reason",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                if c:find("N < 6") or c:find("N<6")
                    or c:find("small") or c:find("bypass_reason")
                    or c:find("too few")
                then
                    return true, nil
                end
                return false, "bypass reason not reported"
            end,
        },
    },
})
