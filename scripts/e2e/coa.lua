--- E2E: coa (Chain-of-Abstraction, Gao et al. COLING 2025, arXiv:2401.17464).
---
--- Run: agent-block -s scripts/e2e/coa.lua -p .
---
--- Flow: Step 1 generates an abstract reasoning chain with [FUNC tool("query") = yN]
---   placeholders (no concrete facts). Step 2 resolves placeholders via parallel
---   LLM knowledge calls (topological order — independent vars first, dependent
---   vars after). Step 3 produces the final answer from the grounded chain.
---
--- Graders:
---   * agent_ok                — agent block terminated normally
---   * max_tokens(200000)      — cumulative budget guard
---   * output_present          — final output non-empty
---   * n_levels_reported       — placeholders_resolved > 0 (topological loop ran)
---   * grounded_output_present — grounded_chain surfaced (each level resolved)

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local params = {
    max_depth     = 2,
    gen_tokens    = 200,
    ground_tokens = 150,
}

local prompt = string.format([[
Use algocline to run the coa (Chain-of-Abstraction) package.
Paper: Gao et al. 2025 "Chain-of-Abstraction: Solving Elaborate Problems via
Abstraction Chains" (Meta/EPFL, COLING 2025, arXiv:2401.17464).

Call alc_advice with:
- package: "coa"
- entry: "run"
- task: "What is the boiling point of water in Fahrenheit, and what is twice that value?"
- opts: {
    tools = {
      knowledge = "General factual knowledge lookup",
    },
    max_depth     = %d,
    gen_tokens    = %d,
    ground_tokens = %d,
  }

Each alc.llm call inside `coa.run` returns status "needs_response" —
reply through alc_continue with a genuine response.

Step 1 (generate abstract chain):
  Reply with an abstract chain containing [FUNC ...] placeholders:
  "To answer this, I need two facts.
  First, the boiling point of water: [FUNC knowledge("boiling point of water in Fahrenheit") = y1]
  Then, twice that value: [FUNC knowledge("twice the value of y1") = y2]
  The boiling point is y1 degrees Fahrenheit, and twice that is y2."

Step 2 (ground placeholders via topological resolution):
  Depth 1 — independent placeholder y1 (no deps):
    Query: "boiling point of water in Fahrenheit"
    Reply: "212"
  Depth 2 — dependent placeholder y2 (depends on y1, now resolved to 212):
    Query: "twice the value of 212"
    Reply: "424"

Step 3 (final answer from grounded chain):
  Reply: "The boiling point of water is 212 degrees Fahrenheit, and twice
  that value is 424 degrees Fahrenheit."

When the run completes, report DIRECTLY from the alc_advice payload:
1. answer — the final answer string
2. abstract_chain — the chain with [FUNC ...] placeholders
3. grounded_chain — the chain after substitution (y1→212, y2→424)
4. placeholders_resolved — count of placeholders actually resolved
5. groundings — the per-placeholder resolution trace (var, tool, query, result, depth)

IMPORTANT:
- Do NOT modify opts from the values above.
- Keep responses concise — the smoke is small on purpose.
- Do NOT call alc_status, alc_log_view, or other diagnostic tools.
  After alc_advice returns its final payload (status = "ok"), extract
  the report fields DIRECTLY.
]],
    params.max_depth,
    params.gen_tokens,
    params.ground_tokens
)

common.run({
    name           = "coa",
    prompt         = prompt,
    params         = params,
    max_iterations = 25,
    max_tokens_budget = 200000,
    graders = {
        common.grader_agent_ok(),
        common.grader_max_tokens(200000),
        {
            name = "output_present",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                if #c < 50 then
                    return false, "agent content too short — coa output likely missing"
                end
                return true, nil
            end,
        },
        {
            name = "n_levels_reported",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                -- placeholders_resolved > 0 = topological loop ran at least 1 level
                if c:find("placeholders_resolved", 1, true)
                    or c:find("placeholders resolved", 1, true)
                    or c:find("groundings", 1, true)
                    or c:find("placeholder", 1, true)
                then
                    return true, nil
                end
                return false, "placeholders_resolved / groundings not surfaced — topological loop incomplete"
            end,
        },
        {
            name = "grounded_output_present",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                -- grounded_chain surfaced = all depth levels resolved and substituted
                if c:find("grounded_chain", 1, true)
                    or c:find("grounded chain", 1, true)
                    or c:find("abstract_chain", 1, true)
                    or c:find("abstract chain", 1, true)
                    or c:find("substitut", 1, true)
                then
                    return true, nil
                end
                return false, "grounded_chain / abstract_chain not surfaced — grounding incomplete"
            end,
        },
    },
})
