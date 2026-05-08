--- E2E: rstar (Mutual reasoning verification, Qi et al. 2024, arXiv:2408.06195).
---
--- Run: agent-block -s scripts/e2e/rstar.lua -p .
---
--- Flow: two independent reasoning paths (Phase 1+2 parallel) followed by
---   cross-verification (Phase 3 parallel) where A verifies B and B verifies A.
---   Disagreement triggers a resolution round (Phase 4).
---
--- Graders:
---   * agent_ok                — agent block terminated normally
---   * max_tokens(150000)      — cumulative budget guard
---   * output_present          — final output non-empty
---   * two_paths_present       — path_a / path_b both surfaced (Phase 1+2 complete)
---   * cross_verify_present    — a_checks_b / b_checks_a both surfaced (Phase 3 complete)

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local params = {
    task          = "If a train travels at 60 km/h for 2.5 hours, how far does it travel? Show your reasoning.",
    gen_tokens    = 200,
    verify_tokens = 150,
}

local prompt = string.format([[
Use algocline to run the rstar (mutual reasoning verification) package.
Paper: Qi et al. 2024 "Mutual Reasoning Makes Smaller LLMs Stronger Problem-Solvers"
(rStar, arXiv:2408.06195).

Call alc_advice with:
- package: "rstar"
- entry: "run"
- task: %q
- opts: {
    gen_tokens    = %d,
    verify_tokens = %d,
  }

Each alc.llm call inside `rstar.run` returns status "needs_response" —
reply through alc_continue with a genuine response.

Phase 1+2 (parallel generation of Path A and Path B):
  Path A prompt will ask for first-principles reasoning — reply with a
  step-by-step approach. End with: "Conclusion: 150 km"
  Path B prompt will ask for a multi-angle approach — reply with an
  alternative angle. End with: "Conclusion: 150 km"

Phase 3 (cross-verification, parallel):
  You will see two verification prompts (A verifies B, B verifies A).
  For each, reply that the other path's reasoning is sound. Use the marker:
  VERIFICATION: AGREE — the conclusion is correct.

When the run completes, report DIRECTLY from the alc_advice payload:
1. answer — the final answer
2. agreement — the agreement level (full/partial/none)
3. path_a.conclusion — Path A's conclusion
4. path_b.conclusion — Path B's conclusion
5. verification.a_checks_b — A's verification of B
6. verification.b_checks_a — B's verification of A

IMPORTANT:
- Do NOT modify gen_tokens / verify_tokens from the values above.
- Keep responses concise — the smoke is small on purpose.
- Do NOT call alc_status, alc_log_view, or other diagnostic tools.
  After alc_advice returns its final payload (status = "ok"), extract
  the report fields DIRECTLY.
]],
    params.task,
    params.gen_tokens,
    params.verify_tokens
)

common.run({
    name           = "rstar",
    prompt         = prompt,
    params         = params,
    max_iterations = 25,
    max_tokens_budget = 150000,
    graders = {
        common.grader_agent_ok(),
        common.grader_max_tokens(150000),
        {
            name = "output_present",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                if #c < 50 then
                    return false, "agent content too short — rstar output likely missing"
                end
                return true, nil
            end,
        },
        {
            name = "two_paths_present",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                local has_a = c:find("path_a", 1, true) or c:find("path a", 1, true)
                local has_b = c:find("path_b", 1, true) or c:find("path b", 1, true)
                if has_a and has_b then return true, nil end
                return false, "path_a / path_b not both surfaced — Phase 1+2 incomplete"
            end,
        },
        {
            name = "cross_verify_present",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                local has_ab = c:find("a_checks_b", 1, true)
                    or c:find("a checks b", 1, true)
                    or c:find("verification", 1, true)
                local has_ba = c:find("b_checks_a", 1, true)
                    or c:find("b checks a", 1, true)
                -- cross_verify surfaced: both a_checks_b and b_checks_a patterns,
                -- or the verification sub-object is present in the report
                if has_ab and has_ba then return true, nil end
                -- Accept: if "verification" key is reported as a whole, that
                -- implies both a_checks_b and b_checks_a exist inside it.
                if has_ab and c:find("b_checks", 1, true) then return true, nil end
                if c:find("a_checks_b", 1, true) and c:find("b_checks_a", 1, true) then
                    return true, nil
                end
                return false, "a_checks_b / b_checks_a not both surfaced — Phase 3 incomplete"
            end,
        },
    },
})
