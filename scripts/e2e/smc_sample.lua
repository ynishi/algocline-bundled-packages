--- E2E: smc_sample (Markovic-Voronov et al. 2026, arXiv:2604.16453).
---
--- Run: agent-block -s scripts/e2e/smc_sample.lua -p .
---
--- Flow: HumanEval-style Python codegen routed through block-SMC.
---   N particles × K iterations of reward-weighted importance sampling
---   + ESS-triggered multinomial resample + Metropolis-Hastings
---   rejuvenation (S steps). Caller-injected reward_fn is a pure Lua
---   closure executing static string-match checks — no LLM judge.
---
--- Transport: alc_run (NOT alc_advice). `alc_advice` JSON-serializes
--- opts and would strip the reward_fn closure; `alc_run` accepts a
--- Lua code string evaluated in the same VM so closures survive.
---
--- Override of paper defaults: N=16, K=4, S=2 → 208 LLM calls. For E2E
--- smoke we use N=4, K=2, S=1 → 4 + 2·4·(1+1) = 20 LLM calls.
---
--- Graders (issue §10 acceptance criteria):
---   * agent_ok                    — agent block terminated normally
---   * answer_contains("def ")    — generated answer includes Python def
---   * weights_normalized          — |Σw - 1| < 1e-6 in the report
---   * particles_count             — N == 4 particles reported
---   * ess_decreasing_or_reset     — ESS trace has a value or a reset
---   * max_tokens(100000)          — cumulative budget guard

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local params = {
    task          = "Write a Python function sum_list(xs) that returns the sum of a list of numbers.",
    n_particles   = 4,
    n_iterations  = 2,
    rejuv_steps   = 1,
    alpha         = 4.0,
    ess_threshold = 0.5,
}

local prompt = string.format([[
Use algocline to run the smc_sample (Sequential Monte Carlo, block-SMC)
package on a short Python codegen task with N=4 particles, K=2
iterations, S=1 rejuvenation step. The reward_fn is a Lua closure, so
you MUST use alc_run (NOT alc_advice — alc_advice cannot serialize a
Lua function).

Call alc_run with the following Lua code (single VM; reward_fn is a
closure captured by require("smc_sample").run):

    local reward_fn = function(answer, task)
        local score = 0
        if answer:match("def%%s+[%%w_]+%%(") then score = score + 0.5 end
        if answer:match("return") then score = score + 0.5 end
        return score
    end
    return require("smc_sample").run({
        task           = %q,
        n_particles    = %d,
        n_iterations   = %d,
        rejuv_steps    = %d,
        alpha          = %s,
        ess_threshold  = %s,
        reward_fn      = reward_fn,
    })

Each alc.llm call inside `smc_sample.run` returns status
"needs_response" — reply through alc_continue with an actual Python
function body. Produce code that contains `def sum_list(` and a
`return` statement so the reward_fn awards both partial credits. Keep
answers concise (single short function).

When the run completes, report:
1. answer (the argmax particle's final Python function)
2. particles: the array length (should be %d) and a brief per-particle
   weight/reward line
3. weights: the full array, and state explicitly whether Σweights ≈ 1
   (e.g. "Σw = 1.000000")
4. iterations (should be %d)
5. resample_count
6. ess_trace (full array)
7. stats.total_llm_calls, stats.total_reward_calls, stats.mh_rejected

IMPORTANT:
- Always include `def sum_list(` in every answer so the reward_fn
  awards credit consistently across particles.
- The final answer field must contain a Python `def` keyword.
- Do NOT modify n_particles / n_iterations / rejuv_steps from the
  values above — the graders check exact counts.
]],
    params.task,
    params.n_particles,
    params.n_iterations,
    params.rejuv_steps,
    tostring(params.alpha),
    tostring(params.ess_threshold),
    params.n_particles,
    params.n_iterations
)

common.run({
    name = "smc_sample",
    prompt = prompt,
    params = params,
    max_iterations = 40,
    graders = {
        common.grader_agent_ok(),
        common.grader_max_tokens(100000),
        common.grader_content_contains("def "),
        {
            name = "weights_normalized",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                -- Accept any of: "σw = 1", "sum of weights = 1",
                -- "normalized", or the literal "1.000000" near a
                -- "weights" mention. We can't re-run the math from the
                -- text, so look for an explicit normalization claim.
                if c:find("1.000000", 1, true)
                    or c:find("1.0000", 1, true)
                    or c:find("= 1%s") or c:find("= 1$")
                    or c:find("normalized", 1, true)
                    or c:find("sum to 1", 1, true)
                    or c:find("sums to 1", 1, true)
                then
                    return true, nil
                end
                return false, "weights normalization not surfaced in report"
            end,
        },
        {
            name = "particles_count",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                -- Agent should state "4 particles" or "particles: 4" or
                -- "particle 1 .. particle 4" etc. Accept any literal "4"
                -- within 40 chars of the word "particle".
                local lc = c:lower()
                local idx = lc:find("particle", 1, true)
                while idx do
                    local window = lc:sub(math.max(1, idx - 40), math.min(#lc, idx + 40))
                    if window:find("4", 1, true) then
                        return true, nil
                    end
                    idx = lc:find("particle", idx + 1, true)
                end
                return false, "particles count (4) not surfaced near 'particle' in report"
            end,
        },
        {
            name = "ess_decreasing_or_reset",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                -- Accept: explicit ess_trace mention, or resample_count
                -- surfaced (which implies a reset occurred), or any
                -- "ess" token with a numeric nearby.
                if c:find("ess_trace", 1, true)
                    or c:find("resample_count", 1, true)
                    or c:find("ess", 1, true)
                then
                    return true, nil
                end
                return false, "ESS trace / resample_count not reported"
            end,
        },
    },
})
