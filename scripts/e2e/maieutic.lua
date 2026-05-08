--- E2E: maieutic (Maieutic Prompting, Jung et al. arXiv:2205.11822, 2022).
---
--- Run: agent-block -s scripts/e2e/maieutic.lua -p .
---
--- Flow: recursive explanation tree with logical consistency filtering —
---   generate supporting and opposing explanations, check parent-child
---   consistency, synthesize verdict from consistent evidence.
---
--- Graders:
---   * agent_ok              — agent block terminated normally
---   * max_tokens(200000)    — cumulative budget guard (recursive tree calls)
---   * output_present        — final output non-empty
---   * verdict_reported      — verdict field surfaced in report

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local params = {
    proposition        = "Regular physical exercise improves mental health.",
    max_depth          = 1,
    gen_tokens         = 200,
    consistency_tokens = 80,
}

local prompt = string.format([[
Use algocline to run the maieutic package on a falsifiable proposition.
Paper: Jung et al. 2022 "Maieutic Prompting: Logically Consistent Reasoning
with Recursive Explanations" (arXiv:2205.11822).

Call alc_advice with:
- package: "maieutic"
- entry: "run"
- proposition: %q
- opts: {
    max_depth          = %d,
    gen_tokens         = %d,
    consistency_tokens = %d,
  }

Each alc.llm call inside the package returns status "needs_response" —
reply through alc_continue with a genuine response.

Round 1 — supporting explanation: provide a concrete factual claim that
  SUPPORTS the proposition.
Round 2 — opposing explanation: provide a concrete factual claim that
  OPPOSES the proposition.
Consistency checks: for each parent→child pair, reply with:
  VERDICT: consistent | contradictory | independent
  REASON: brief
Synthesis: provide a final verdict on the proposition based on the consistent
  evidence, using one of:
  VERDICT: likely true | likely false | insufficient evidence

When the run completes, report DIRECTLY from the alc_advice payload:
1. verdict — the extracted final verdict
2. evidence.support — count of consistent supporting sub-claims
3. evidence.oppose  — count of consistent opposing sub-claims
4. synthesis — the final synthesis text

IMPORTANT:
- Do NOT modify the opts from the values above.
- Keep responses concise.
- Do NOT call alc_status, alc_log_view, or other diagnostic tools.
]],
    params.proposition,
    params.max_depth,
    params.gen_tokens,
    params.consistency_tokens
)

common.run({
    name           = "maieutic",
    prompt         = prompt,
    params         = params,
    max_iterations = 25,
    graders = {
        common.grader_agent_ok(),
        common.grader_max_tokens(200000),
        {
            name = "output_present",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                if #c < 50 then
                    return false, "agent content too short — maieutic output likely missing"
                end
                return true, nil
            end,
        },
        {
            name = "verdict_reported",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("verdict", 1, true)
                    or c:find("likely true", 1, true)
                    or c:find("likely false", 1, true)
                    or c:find("insufficient evidence", 1, true)
                    or c:find("synthesis", 1, true)
                then
                    return true, nil
                end
                return false, "verdict / synthesis not surfaced in report"
            end,
        },
    },
})
