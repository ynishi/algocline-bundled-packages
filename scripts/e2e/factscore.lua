--- E2E: factscore (Min et al. arXiv:2305.14251, 2023).
---
--- Run: agent-block -s scripts/e2e/factscore.lua -p .
---
--- Flow: atomic claim decomposition — extract atomic claims from text, verify
---   each independently in parallel, compute factual precision score.
---
--- Graders:
---   * agent_ok             — agent block terminated normally
---   * max_tokens(150000)   — cumulative budget guard
---   * output_present       — final output non-empty
---   * precision_score_reported — score field surfaced in report
---   * score_in_range       — score value in [0, 1]

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local params = {
    text           = "The Eiffel Tower is located in Berlin, Germany. It was built in 1889 for the World's Fair. The tower is made of iron and stands 330 meters tall.",
    verify_tokens  = 150,
    extract_tokens = 250,
}

local prompt = string.format([[
Use algocline to run the factscore package on a short text with mixed factual claims.

Call alc_advice with:
- package: "factscore"
- entry: "run"
- text: %q
- opts: {
    verify_tokens  = %d,
    extract_tokens = %d,
  }

Each alc.llm call inside the package returns status "needs_response" —
reply through alc_continue with a genuine response.

Phase 1 (claim extraction): extract atomic claims as a numbered list.
  Example: "1. The Eiffel Tower is in Berlin. 2. It was built in 1889."

Phase 2 (parallel verification): for each claim respond with:
  VERDICT: SUPPORTED | UNSUPPORTED | UNCERTAIN
  JUSTIFICATION: one-sentence reason

When the run completes, report DIRECTLY from the alc_advice payload:
1. score — the factual precision score (0.0 to 1.0)
2. total — total claims extracted
3. supported / unsupported / uncertain — counts of each verdict

IMPORTANT:
- Do NOT modify the opts from the values above.
- Keep responses concise. Apply your real world knowledge for verification.
- Do NOT call alc_status, alc_log_view, or other diagnostic tools.
]],
    params.text,
    params.verify_tokens,
    params.extract_tokens
)

common.run({
    name           = "factscore",
    prompt         = prompt,
    params         = params,
    max_iterations = 25,
    graders = {
        common.grader_agent_ok(),
        common.grader_max_tokens(150000),
        {
            name = "output_present",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                if #c < 50 then
                    return false, "agent content too short — factscore output likely missing"
                end
                return true, nil
            end,
        },
        {
            name = "precision_score_reported",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("score", 1, true)
                    or c:find("precision", 1, true)
                    or c:find("factscore", 1, true)
                then
                    return true, nil
                end
                return false, "score / precision not surfaced in report"
            end,
        },
        {
            name = "score_in_range",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                -- Find a decimal number between 0 and 1 (e.g., 0.33, 0.5, 1.0).
                local pos = 1
                while pos <= #c do
                    local s, e, cap = c:find("(%d+%.%d+)", pos)
                    if not s then break end
                    local v = tonumber(cap)
                    if v and v >= 0.0 and v <= 1.0 then
                        return true, nil
                    end
                    pos = e + 1
                end
                -- Also accept integer 0 or 1 near "score" context.
                if c:find("score.*%b01") or c:find("score.*: [01]%f[^%d]") then
                    return true, nil
                end
                return false, "no score value in [0,1] found in report"
            end,
        },
    },
})
