--- E2E: dci (Prakash 2026, arXiv:2603.11781).
---
--- Run: agent-block -s scripts/e2e/dci.lua -p .
---
--- Flow: open-ended design decision task routed through DCI-CF.
---   4 roles (Framer / Explorer / Challenger / Integrator) × 14 typed
---   epistemic acts × 8-stage convergence. Forces a decision_packet
---   with first-class minority_report preservation.
---
--- Graders (issue §10 acceptance criteria):
---   * agent_ok                     — agent block terminated normally
---   * content_contains(event-sourcing) — task topic is discussed
---   * decision_packet_complete     — 5 components non-empty in report
---   * minority_report_preserved    — minority_report length >= 1
---   * convergence_recorded         — convergence ∈ {"dominance",
---                                                    "no_blocking",
---                                                    "fallback"}
---   * max_tokens(500000)           — 62× single-agent margin per §10

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local params = {
    task = "Should our team adopt event-sourcing for the order service?",
    max_rounds    = 2,
    max_options   = 5,
    num_finalists = 3,
    gen_tokens    = 400,
}

local prompt = string.format([[
Use algocline to run the dci (Deliberative Collective Intelligence)
package on an open-ended design decision with 4 roles (Framer /
Explorer / Challenger / Integrator) and Rmax = 2.

Call alc_advice with:
- package: "dci"
- task: %q
- opts: {
    max_rounds    = %d,
    max_options   = %d,
    num_finalists = %d,
    gen_tokens    = %d,
  }

Each alc.llm call inside `dci.run` returns status "needs_response" —
reply through alc_continue with your genuine per-role reasoning.

The 8 stages you will participate in:
  Stage 1 — independent proposals (you are each role in turn)
  Stage 2 — canonicalize / cluster into options
  Stages 3-6 — loop up to Rmax = 2:
    3 challenges / evidence
    4 admit new hypotheses
    5 revise & compress
    6 convergence test (dominance / no_blocking / none)
  Stage 7 — fallback cascade (outranking → minimax → satisficing →
             integrator arbitration) if unconverged
  Stage 8 — finalize the decision packet (5 components non-nil)

When Stage 1 or Stage 3 prompts you for acts, return STRICT JSON of
the form:
  {"acts":[
    {"type":"propose","content":"<1-3 sentences>","author":"<role>"}
  ]}

When canonicalize / revise prompts you, return STRICT JSON:
  {"options":[{"id":1,"content":"<text>","author":"integrator"}]}

When Stage 6 prompts you for the convergence test, return STRICT JSON:
  {"mode":"dominance"|"no_blocking"|"none",
   "ranking":[{"option_id":1,"score":0.8,"rationale":"<text>"}],
   "blocking_objections":["<text>"]}

When Stage 8 prompts you for finalize, return STRICT JSON:
  {"answer":"<final answer>",
   "rationale":"<why>",
   "evidence":["<snippet>"],
   "residual_objections":["<text>"],
   "next_actions":["<concrete>"],
   "reopen_triggers":["<condition>"]}

When the run completes, report:
1. answer (final decision — pro or con event-sourcing)
2. decision_packet with all 5 components:
   - selected_option (answer / rationale / evidence)
   - residual_objections
   - minority_report
   - next_actions
   - reopen_triggers
3. convergence ("dominance" / "no_blocking" / "fallback")
4. workspace 6 fields (problem_view, key_frames, emerging_ideas,
   tensions, synthesis_in_progress, next_actions)
5. stats (rounds_used, total_acts, options_count, total_llm_calls)

IMPORTANT: include "event-sourcing" in your final answer text,
whether for or against. Preserve the minority_report even if one
option strongly dominates — §5.3 of the paper requires dissenting
positions to survive to the final packet.
]],
    params.task,
    params.max_rounds,
    params.max_options,
    params.num_finalists,
    params.gen_tokens
)

common.run({
    name = "dci",
    prompt = prompt,
    params = params,
    max_iterations = 60,
    graders = {
        common.grader_agent_ok(),
        common.grader_max_tokens(500000),
        common.grader_content_contains("event-sourcing"),
        {
            name = "decision_packet_complete",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                -- Accept either snake_case (from the shape / JSON) or
                -- human-readable markdown section headers (agents tend
                -- to paraphrase field names into title-case English).
                -- Regression for E2E 2026-04-22 run_id 122845 where
                -- agent wrote "**Selected Option**" etc. and the
                -- snake_case-only grader FAIL'd a correct decision.
                local patterns = {
                    selected_option     = { "selected_option",     "selected option" },
                    residual_objections = { "residual_objections", "residual objections" },
                    minority_report     = { "minority_report",     "minority report" },
                    next_actions        = { "next_actions",        "next actions" },
                    reopen_triggers     = { "reopen_triggers",     "reopen triggers" },
                }
                for key, alts in pairs(patterns) do
                    local found = false
                    for _, pat in ipairs(alts) do
                        if c:find(pat, 1, true) then
                            found = true
                            break
                        end
                    end
                    if not found then
                        return false, "missing component: " .. key
                    end
                end
                return true, nil
            end,
        },
        {
            name = "minority_report_preserved",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                -- Heuristic: the report mentions minority_report (or
                -- its markdown-header form "minority report") AND
                -- at least one alternative position / rationale marker.
                local mentions = c:find("minority_report", 1, true)
                    or c:find("minority report", 1, true)
                if not mentions then
                    return false, "minority_report absent"
                end
                if c:find("position", 1, true)
                    or c:find("rationale", 1, true)
                    or c:find("dissent", 1, true)
                then
                    return true, nil
                end
                return false, "minority_report empty (no position/rationale/dissent)"
            end,
        },
        {
            name = "convergence_recorded",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("dominance", 1, true)
                    or c:find("no_blocking", 1, true)
                    or c:find("fallback", 1, true)
                then
                    return true, nil
                end
                return false, "convergence not in "
                    .. "{dominance, no_blocking, fallback}"
            end,
        },
    },
})
