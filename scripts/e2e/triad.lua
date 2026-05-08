--- E2E: triad (Multiagent Debate, Du et al. arXiv:2305.14325, 2023).
---
--- Run: agent-block -s scripts/e2e/triad.lua -p .
---
--- Flow: adversarial 3-role debate — Proponent argues for, Opponent argues
---   against, Judge arbitrates through multiple rounds, then delivers verdict.
---
--- Graders:
---   * agent_ok              — agent block terminated normally
---   * max_tokens(200000)    — cumulative budget guard (rounds * 2 + judge)
---   * output_present        — final output non-empty
---   * verdict_reported      — judge verdict surfaced in report

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local params = {
    task         = "Should programming be a mandatory subject in primary school?",
    rounds       = 2,
    gen_tokens   = 200,
    judge_tokens = 300,
}

local prompt = string.format([[
Use algocline to run the triad package on a debatable question.
Paper: Du et al. 2023 "Improving Factuality and Reasoning in Language
Models through Multiagent Debate" (arXiv:2305.14325).

Call alc_advice with:
- package: "triad"
- entry: "run"
- task: %q
- opts: {
    rounds       = %d,
    gen_tokens   = %d,
    judge_tokens = %d,
  }

Each alc.llm call inside the package returns status "needs_response" —
reply through alc_continue with a genuine response.

Opening round (parallel batch):
  - As Proponent: argue why programming SHOULD be mandatory in primary school.
  - As Opponent: argue why programming should NOT be mandatory.

Rebuttal rounds (parallel batches, %d rounds):
  - Proponent: rebut opponent's argument and strengthen your position.
  - Opponent: rebut proponent's argument and strengthen your position.

Final judgment: as Judge, deliver a verdict based on the debate quality.
  State: proponent | opponent | draw
  Provide reasoning.

When the run completes, report DIRECTLY from the alc_advice payload:
1. verdict — the judge's full verdict text
2. winner — parsed winner token (proponent/opponent/draw/unknown)
3. total_rounds — number of rebuttal rounds

IMPORTANT:
- Do NOT modify the opts from the values above.
- Keep responses concise.
- Do NOT call alc_status, alc_log_view, or other diagnostic tools.
]],
    params.task,
    params.rounds,
    params.gen_tokens,
    params.judge_tokens,
    params.rounds
)

common.run({
    name           = "triad",
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
                    return false, "agent content too short — triad output likely missing"
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
                    or c:find("winner", 1, true)
                    or c:find("proponent", 1, true)
                    or c:find("opponent", 1, true)
                    or c:find("judge", 1, true)
                then
                    return true, nil
                end
                return false, "judge verdict not surfaced in report"
            end,
        },
    },
})
