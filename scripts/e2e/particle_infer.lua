--- E2E: particle_infer (Puri et al. 2025, arXiv:2502.01618).
---
--- Run: agent-block -s scripts/e2e/particle_infer.lua -p .
---
--- Flow: short arithmetic CoT routed through step-wise Particle Filter
---   inference-time scaling. N particles advance one reasoning step at
---   a time; caller-injected Process Reward Model (PRM) scores each
---   partial for Bernoulli posterior weight updates; every step
---   triggers a softmax multinomial resample (paper §3.1 Algorithm 1);
---   the caller-injected Outcome Reward Model (ORM) picks the final
---   answer among the surviving particles (paper §3 end).
---
--- Transport: alc_run (NOT alc_advice). `alc_advice` JSON-serializes
--- opts and would strip the prm_fn / orm_fn closures; `alc_run`
--- accepts a Lua code string evaluated in the same VM so closures
--- survive. Same constraint as smc_sample E2E.
---
--- PRM / ORM are pure-Lua string-match heuristics (no LLM judge) so
--- the graders stay deterministic across runs. PRM returns a
--- Bernoulli parameter ∈ [0, 1] (paper §2 emission model contract).
---
--- Override of paper defaults: paper ablates N=4/8/32/64/128 with
--- max_steps ≈ 8–16. For E2E smoke we use N=3, max_steps=2 → up to
--- 6 LLM calls + 6 PRM + 3 ORM, well under any per-run budget.
---
--- Graders (paper-faithful path acceptance):
---   * agent_ok                    — agent block terminated normally
---   * answer_contains("70")      — final answer contains 23+47=70
---   * particles_count(3)          — N=3 particles reported
---   * steps_executed_reported     — steps_executed or resample_count
---                                    surfaced in report
---   * prm_or_orm_reported         — total_prm_calls / total_orm_calls
---                                    or the words "PRM" / "ORM"
---                                    surfaced in the report
---   * max_tokens(100000)          — cumulative budget guard

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local params = {
    task        = "What is 23 + 47? Think step by step and state the final numeric answer on the last line.",
    n_particles = 3,
    max_steps   = 2,
    expected    = "70",
}

local prompt = string.format([[
Use algocline to run the particle_infer (step-wise Particle Filter
inference-time scaling, Puri et al. 2025) package on a short
arithmetic CoT task with N=3 particles and max_steps=2. The prm_fn
and orm_fn are Lua closures, so you MUST use alc_run (NOT alc_advice
— alc_advice cannot serialize a Lua function).

Call alc_run with the following Lua code (single VM; prm_fn / orm_fn
are closures captured by require("particle_infer").run):

    -- PRM: Bernoulli parameter ∈ [0, 1] per paper §2 emission model.
    -- Rewards numeric content progressively: digits > multi-digit
    -- number > contains the expected answer "70".
    local prm_fn = function(partial, _task)
        local score = 0.0
        if partial and partial ~= "" then
            score = score + 0.2
            if partial:match("%%d") then score = score + 0.2 end
            if partial:match("%%d%%d") then score = score + 0.2 end
            if partial:find("70", 1, true) then score = score + 0.4 end
        end
        if score > 1.0 then score = 1.0 end
        return score
    end

    -- ORM: final-answer scalar score (paper §3 end). 1.0 if the
    -- expected answer appears in the final partial, 0.3 if any
    -- numeric content is present, 0.0 otherwise.
    local orm_fn = function(final, _task)
        if not final or final == "" then return 0.0 end
        if final:find(%q, 1, true) then return 1.0 end
        if final:match("%%d") then return 0.3 end
        return 0.0
    end

    return require("particle_infer").run({
        task            = %q,
        n_particles     = %d,
        max_steps       = %d,
        prm_fn          = prm_fn,
        orm_fn          = orm_fn,
        final_selection = "orm",
    })

Each alc.llm call inside `particle_infer.run` returns status
"needs_response" — reply through alc_continue with an actual next
reasoning step. The task is "What is 23 + 47?" — produce reasoning
steps that lead to "70" (e.g., first step identifies the operation,
second step computes and states the answer). Keep each step concise.

When the run completes, report:
1. answer (the ORM-argmax particle's final reasoning+answer text)
2. selected_idx (1-based index of the chosen particle)
3. particles: the array length (should be %d) and a brief per-particle
   weight / aggregated-PRM / ORM-score line
4. weights: full array, state explicitly whether Σweights ≈ 1
5. steps_executed (should be ≤ %d)
6. resample_count (paper-faithful every-step path → equal to
   steps_executed)
7. aggregation (should be "product") and final_selection
   (should be "orm")
8. stats.total_llm_calls, stats.total_prm_calls, stats.total_orm_calls

IMPORTANT:
- Your final-answer reasoning step MUST mention "70" so the ORM
  returns 1.0 for at least one particle (otherwise the PRM product
  collapses all weights and the run is uninformative).
- Do NOT modify n_particles / max_steps from the values above — the
  graders check those counts.
- Use alc_continue consistently for each pause — do not try to batch
  responses across multiple alc.llm calls.
]],
    params.expected,
    params.task,
    params.n_particles,
    params.max_steps,
    params.n_particles,
    params.max_steps
)

common.run({
    name           = "particle_infer",
    prompt         = prompt,
    params         = params,
    max_iterations = 40,
    graders = {
        common.grader_agent_ok(),
        common.grader_max_tokens(100000),
        common.grader_content_contains(params.expected),
        {
            name = "particles_count",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                -- Agent should state "3 particles" or "particles: 3"
                -- or enumerate particle 1..particle 3. Accept any
                -- literal "3" within 40 chars of the word "particle".
                local lc = c:lower()
                local idx = lc:find("particle", 1, true)
                while idx do
                    local window = lc:sub(
                        math.max(1, idx - 40),
                        math.min(#lc, idx + 40))
                    if window:find("3", 1, true) then
                        return true, nil
                    end
                    idx = lc:find("particle", idx + 1, true)
                end
                return false, "particles count (3) not surfaced near 'particle' in report"
            end,
        },
        {
            name = "steps_executed_reported",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                -- Accept: explicit steps_executed / resample_count
                -- mention, or the word "step" adjacent to a small
                -- integer.
                if c:find("steps_executed", 1, true)
                    or c:find("resample_count", 1, true)
                    or c:find("steps executed", 1, true)
                then
                    return true, nil
                end
                return false, "steps_executed / resample_count not reported"
            end,
        },
        {
            name = "prm_or_orm_reported",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("total_prm_calls", 1, true)
                    or c:find("total_orm_calls", 1, true)
                    or c:find("prm", 1, true)
                    or c:find("orm", 1, true)
                then
                    return true, nil
                end
                return false, "PRM / ORM call counts not surfaced in report"
            end,
        },
    },
})
