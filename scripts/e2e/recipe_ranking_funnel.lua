--- E2E: recipe_ranking_funnel
---
--- Run: agent-block -s scripts/e2e/recipe_ranking_funnel.lua -p .
---
--- Flow (N=8 countries by population):
---   Stage 1 (listwise, window=20)  : 1 LLM call (single window, 8 < 20)
---   Stage 2 (scoring)              : skipped (survivors_1=3 ≤ top_k2=3)
---   Stage 3 (pairwise allpair, k=3): 6 LLM calls (3·2 with bias cancel)
---   Total                          : ~7 LLM calls, ~9-10 agent turns

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local params = {
    task = "Rank these countries by total population in 2026 "
        .. "(largest population first).",
    candidates = {
        "India",
        "Brazil",
        "Nigeria",
        "United States",
        "Bangladesh",
        "China",
        "Pakistan",
        "Indonesia",
    },
    opts = {
        top_k1 = 3,
        window_size = 20,
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
    top_k1 = %d,
    window_size = %d,
    gen_tokens = %d
  }

The recipe will issue several alc.llm() calls through:
  Stage 1 (listwise screening) → Stage 2 (scoring, likely skipped at
  this N) → Stage 3 (pairwise all-pair on the finalists).
Each call returns status "needs_response" — reply through alc_continue
with session_id + your genuine answer.

IMPORTANT: You ARE the LLM being queried. Answer based on real-world
knowledge about the 2026 population of each country.
- Listwise prompts: output the requested ordering only.
- Pairwise prompts: pick one candidate per the prompt's output format.

When the recipe completes, report:
1. Final top-1 country
2. Full ranking (top 3)
3. Total LLM calls reported by the recipe
4. Funnel shape (stage sizes: N → top_k1 → top_k2)
5. Whether funnel was bypassed (should be NO for N=8)
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
    params.opts.top_k1,
    params.opts.window_size,
    params.opts.gen_tokens
)

common.run({
    name = "recipe_ranking_funnel",
    prompt = prompt,
    params = params,
    max_iterations = 20,
    graders = {
        common.grader_agent_ok(),
        common.grader_content_contains("India", "mentions_india"),
        common.grader_content_contains("China", "mentions_china"),
        common.grader_max_turns(15),
        common.grader_max_tokens(200000),
        {
            -- India should be top-1 (~1.45B in 2026, ahead of China ~1.41B).
            -- Match "top" / "first" / "#1" / "1." within 200 chars after India.
            name = "india_top_ranked",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                local idx = c:find("India", 1, true)
                if not idx then return false, "India not mentioned" end
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
                return false, "India mentioned but not flagged as top-1"
            end,
        },
        {
            -- Recipe should NOT bypass the funnel (N=8 ≥ 6).
            name = "funnel_not_bypassed",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                -- "bypass ... yes" or "bypassed: true" would indicate bypass
                if c:find("bypass") and
                   (c:find("yes", 1, true) or c:find("true", 1, true))
                then
                    -- Only fail if "bypass" is near "yes/true", not near "no/false"
                    local bidx = c:find("bypass")
                    local win = c:sub(bidx, bidx + 60)
                    if win:find("no", 1, true) or win:find("false", 1, true) then
                        return true, nil
                    end
                    return false, "funnel appears bypassed"
                end
                return true, nil
            end,
        },
        {
            -- Content should mention multi-stage execution.
            name = "reports_stages",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                if c:find("[Ss]tage") or c:find("listwise") or c:find("pairwise") then
                    return true, nil
                end
                return false, "stage info not reported"
            end,
        },
    },
})
