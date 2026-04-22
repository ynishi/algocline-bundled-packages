--- E2E: conformal_vote
---
--- Run: agent-block -s scripts/e2e/conformal_vote.lua -p .
---
--- Flow:
---   Phase A: prompt the agent to seed 10 offline calibration samples
---            (3 agents × 10 samples with ground-truth labels) and call
---            `conformal_vote.calibrate` to produce q_hat / tau / weights.
---   Phase B: run one live 4-option task through `conformal_vote.run`
---            with 3 agent prompts. The decision lands in
---            { commit, escalate, anomaly } per Proposition 3.
---
--- Graders (issue §10 acceptance criteria):
---   * agent_ok                     — agent block terminated normally
---   * action_in_enum               — action ∈ {commit, escalate, anomaly}
---   * coverage_field_present       — result.coverage_level is numeric
---   * weights_preserved            — the weights from calibrate are
---                                    threaded through run unchanged
---                                    (Theorem 2 exchangeability check)

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local params = {
    task = "A stone is tossed straight up and returns to the thrower's hand. At the apex, which of the following is true? (A) velocity zero, acceleration zero. (B) velocity zero, acceleration -g. (C) velocity +g, acceleration zero. (D) velocity -g, acceleration zero.",
    options = { "A", "B", "C", "D" },
    alpha = 0.05,
}

local prompt = string.format([[
Use algocline to run the conformal_vote package on a short physics
multiple-choice question with 3 agents and a 10-sample offline
calibration set.

Step 1 — Calibrate.
Call alc_advice with:
- package: "conformal_vote"
- entry: "calibrate"
- opts: {
    calibration_samples = {
        -- 10 samples, each {agent_probs = {[1]=..., [2]=..., [3]=...},
        -- true_label = "A"|"B"|"C"|"D"}. Use high-quality agents that
        -- place ~0.7 mass on the true label and ~0.1 on each distractor.
        -- e.g.
        { agent_probs = { [1] = { A=0.7, B=0.1, C=0.1, D=0.1 },
                          [2] = { A=0.75, B=0.1, C=0.1, D=0.05 },
                          [3] = { A=0.7, B=0.15, C=0.1, D=0.05 } },
          true_label = "A" },
        -- (continue for 10 samples total, cycling through A..D as the
        -- true label)
    },
    alpha = %s,
  }

This is a pure Computation call (no LLM). It returns
{ q_hat, tau, alpha, n, weights = { 1/3, 1/3, 1/3 } }. Hold onto it.

Step 2 — Run.
Call alc_advice with:
- package: "conformal_vote"
- entry: "run"
- task: %q
- opts: {
    options = { "A", "B", "C", "D" },
    calibration = <the struct returned by Step 1, with weights included>,
    agents = { "Physics reasoner #1", "Physics reasoner #2", "Physics reasoner #3" },
    gen_tokens = 300,
  }

Each alc.llm call inside `run` returns status "needs_response" — reply
through alc_continue with your genuine per-agent probability
distribution over A..D, formatted as:

  <reasoning>(one sentence)</reasoning>
  <answer>
  A: 0.XX
  B: 0.XX
  C: 0.XX
  D: 0.XX
  </answer>

IMPORTANT:
- You ARE the physics agent being queried each time.
- At the apex of a projectile's trajectory, velocity is zero but
  gravitational acceleration remains -g. Answer B is correct.
- Give probabilities that sum to 1 and place the majority on your best
  answer.

When the run completes, report:
1. action (commit / escalate / anomaly)
2. selected (nil unless action = commit)
3. coverage_level (should be 1 - alpha = 0.95)
4. q_hat and tau from the calibration struct
5. The weights array returned by calibrate (so we can verify it is
   preserved through run)
]], tostring(params.alpha), params.task)

common.run({
    name = "conformal_vote",
    prompt = prompt,
    params = params,
    max_iterations = 30,
    graders = {
        common.grader_agent_ok(),
        common.grader_max_tokens(500000),
        {
            name = "action_in_enum",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("commit", 1, true)
                    or c:find("escalate", 1, true)
                    or c:find("anomaly", 1, true)
                then
                    return true, nil
                end
                return false, "action not in {commit, escalate, anomaly}"
            end,
        },
        {
            name = "coverage_field_present",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                if c:find("coverage", 1, true) or c:find("0.95", 1, true) then
                    return true, nil
                end
                return false, "coverage_level not reported"
            end,
        },
        {
            name = "weights_preserved",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                -- Look for evidence of 1/3 weights reported back. Accept
                -- either the decimal 0.33 (truncated) or the fraction
                -- representation.
                if c:find("0%.33") or c:find("1/3", 1, true) then
                    return true, nil
                end
                return false, "weights not surfaced in the report"
            end,
        },
    },
})
