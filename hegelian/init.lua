--- hegelian — Self-reflecting LLMs via Hegelian dialectical self-reflection
---
--- ## Primary citation
---
--- Abdali, S., Yang, J., Sundararajan, H., Rangarajan Sridhar, V. K., &
--- Liden, L. (Microsoft Research). "Self-reflecting Large Language Models:
--- A Hegelian Dialectical Approach". arXiv:2501.14917 (v3, 2025-02).
--- https://arxiv.org/abs/2501.14917
---
--- ## Algorithm (Abdali 2025 §3, Algorithm 1)
---
--- ```
---   T_0  ← bootstrap initial thesis (single LLM call at temperature τ_0)
---   for i = 0, 1, ..., N-1:
---       A_i  ← M(T_i, τ_a, p_a)                  -- antithesis,  Alg.1 L6
---       τ(i) = τ_0 · exp(-θ · i)                  -- decay,       §3.2 (annealing)
---       S_i  ← M(T_i, A_i, τ(i), p_s)             -- synthesis,   Alg.1 L8
---       T_{i+1} ← S_i                             -- update,      Alg.1 L16
---   return S_{N-1}                                -- final synthesis
--- ```
---
--- Three LLM-mediated stages per iteration:
---
---   Thesis      T_0          single bootstrap call before loop, temperature τ_0
---   Antithesis  A_i          per-iteration, temperature τ_a (fixed)
---   Synthesis   S_i          per-iteration, temperature τ(i) (annealing)
---
--- **No "rebuttal" stage exists in the paper** (verified against Abdali §3 /
--- Algorithm 1 / Table 1, 2026-05-15 WebFetch).
---
--- ## Defaults (Abdali 2025 §3 / Table 1)
---
--- | Symbol | Value | Label | Source                          |
--- |--------|-------|-------|---------------------------------|
--- | τ_0    | 0.7   | (L)   | Table 1 "Initial temperature"   |
--- | τ_a    | 0.5   | (L)   | Table 1 "Antithesis temperature"|
--- | θ      | 0.3   | (X)   | within paper-stated (L) range [0.1, 0.5] from Table 1 |
--- | N      | 5     | (L)   | Table 1 "Max iterations"        |
---
--- θ default 0.3 is the midpoint of the paper-stated range [0.1, 0.5]
--- (Table 1). 0.3 is NOT itself a literal Table 1 value — only the range is.
--- Caller is expected to tune θ for their specific model and task. The pkg
--- enforces θ ∈ [0.1, 0.5] (the paper range) at runtime; values outside
--- the range are rejected.
---
--- ## Entry contract
---
--- See `M.spec` below for the formal machine-readable contract:
---
--- - `temperature_at`         — pure math, direct-args. returns τ(i) = τ_0 · exp(-θ · i)
--- - `build_thesis_prompt`    — pure string, direct-args. returns { prompt, system }
--- - `build_antithesis_prompt`— pure string, direct-args. returns { prompt, system }
--- - `build_synthesis_prompt` — pure string, direct-args. returns { prompt, system }
--- - `run`                    — Strategy, ctx-threading. orchestrates N iterations via `alc.llm`
---
--- All four sub-entries are LLM-independent and unit-testable without `alc` mocks.
--- `run` is the only LLM-mediated entry.
---
--- ## EXTENSION POINTS
---
--- ```
--- ┌──────────────────────────────────────────────────────────────────────┐
--- │ REQUIRED                                                             │
--- │   ctx.task                  (string)         task to apply dialectic │
--- ├──────────────────────────────────────────────────────────────────────┤
--- │ (L)-override OPTION                                                  │
--- │   ctx.tau_0                 (number)         override τ_0 default    │
--- │   ctx.tau_a                 (number)         override τ_a default    │
--- │   ctx.N                     (number)         override iteration count│
--- ├──────────────────────────────────────────────────────────────────────┤
--- │ (X) caller-tunable within paper range                                │
--- │   ctx.theta                 (number ∈ [0.1, 0.5])  decay constant    │
--- ├──────────────────────────────────────────────────────────────────────┤
--- │ (X) infrastructure (paper does not specify)                          │
--- │   ctx.gen_tokens            (number)         max tokens per LLM call │
--- │   ctx.thesis_prompt         (string template) override thesis prompt │
--- │   ctx.antithesis_prompt     (string template) override antithesis    │
--- │   ctx.synthesis_prompt      (string template) override synthesis     │
--- │   ctx.system_thesis         (string)          system prompt thesis   │
--- │   ctx.system_antithesis     (string)          system prompt anti     │
--- │   ctx.system_synthesis      (string)          system prompt synth    │
--- ├──────────────────────────────────────────────────────────────────────┤
--- │ Stability tier:                                                      │
--- │   stable     : tau_0 / tau_a / theta / N / gen_tokens                │
--- │   v2-opt-in  : *_prompt / system_* (template override; format may    │
--- │                evolve in future versions)                            │
--- └──────────────────────────────────────────────────────────────────────┘
--- ```
---
--- Note: overriding any (L) default invalidates the paper's effect guarantee.
--- The pkg accepts the override and proceeds, but the docstring no longer
--- claims paper-explicit behaviour for the run.
---
--- ## Comparison with related packages
---
--- vs `dmad` (Du 2023 Multi-Agent Debate): dmad implements 3 agents debating
--- in parallel over multiple rounds with shared answer history; hegelian
--- implements a single-thread thesis/antithesis/synthesis dialectic with
--- temperature annealing. The two methodologies are from different papers
--- and are NOT variants of the same algorithm.
---
--- vs `panel` (sequential multi-role discussion): panel uses heterogeneous
--- caller-supplied roles per turn. hegelian's roles (thesis vs antithesis)
--- are paper-defined and structurally asymmetric.
---
--- vs `negation` (destruction conditions): negation explicitly tries to break
--- a candidate via failure-condition enumeration. hegelian constructs a
--- genuine counter-position and forces integration.
---
--- ## History
---
--- hegelian/ was extracted from dmad/ v0.1.0 (commit 54faaa5, 2026-03-15)
--- in 2026-05-15. The Hegelian dialectic implementation had been mixed
--- into dmad/ alongside the Du 2023 citation despite Du's paper not
--- describing a dialectic. This pkg restores the Hegelian methodology with
--- the correct paper citation (Abdali 2025) and removes the non-paper
--- "rebuttal" stage that had been inserted in dmad/ v0.1.0.

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "hegelian",
    version = "0.1.0",
    description = "Hegelian dialectical self-reflection — thesis/antithesis/synthesis with temperature annealing (Abdali 2025)",
    category = "reasoning",
}

-- Centralized defaults per Abdali 2025 §3 / Table 1.
--   tau_0      = 0.7  (L) Table 1 "Initial temperature"
--   tau_a      = 0.5  (L) Table 1 "Antithesis temperature"
--   N          = 5    (L) Table 1 "Max iterations"
--   theta      = 0.3  (X) midpoint of paper-stated range [0.1, 0.5] (Table 1);
--                         specific default is caller's choice within the range.
--   gen_tokens = 600  (X) infrastructure, paper does not specify token budgets.
--                         Provenance: in-repo dmad/init.lua v0.1.0 baseline
--                         (commit 54faaa5) gen_tokens = 500; raised to 600 for
--                         synthesis-stage headroom (matches dmad synth_tokens).
M._defaults = {
    tau_0      = 0.7,
    tau_a      = 0.5,
    theta      = 0.3,
    N          = 5,
    gen_tokens = 600,
}

-- (L) Abdali 2025 Table 1: θ ∈ [0.1, 0.5]. Enforced at validation time.
M._theta_range = { min = 0.1, max = 0.5 }

-- Default prompt templates (X).
--
-- Paper §3 specifies the *roles* (thesis = initial position, antithesis =
-- strongest counter, synthesis = integration with annealed temperature)
-- but does not provide literal prompt text. The templates below are
-- (X) infrastructure with provenance from in-repo dmad/init.lua v0.1.0
-- (commit 54faaa5, 2026-03-15), adapted for paper-faithful Algorithm 1:
--   - Removed rebuttal-stage prompt entirely (absent from Abdali §3)
--   - Synthesis prompt drops "do not pick a winner" framing and instead
--     emphasises integration to feed back as T_{i+1} per Alg.1 L16
--
-- Caller may override via ctx.thesis_prompt / ctx.antithesis_prompt /
-- ctx.synthesis_prompt. Template uses string.format with positional args
-- documented in each build_*_prompt entry.

local DEFAULT_THESIS_PROMPT = [[
Task: %s

Present a well-reasoned position on this topic. Support your claims with
evidence and logic. Be thorough and confident in your analysis.]]

local DEFAULT_THESIS_SYSTEM = [[
You are a skilled advocate. Present the strongest possible position. Use
evidence, examples, and clear reasoning. Commit fully to your position —
do not hedge unnecessarily.]]

local DEFAULT_ANTITHESIS_PROMPT = [[
Task: %s

The following position has been argued:
"""
%s
"""

Construct the STRONGEST possible counter-argument. Challenge every
assumption, find logical gaps, present alternative evidence, and argue
for the opposing view. Do not simply nitpick — present a genuinely
compelling alternative position.]]

local DEFAULT_ANTITHESIS_SYSTEM = [[
You are a devil's advocate and skilled debater. Your job is to find the
strongest possible objection to the thesis. Attack the weakest points,
present counterevidence, and argue passionately for the opposing view.
Be intellectually honest but adversarial.]]

local DEFAULT_SYNTHESIS_PROMPT = [[
Task: %s

Thesis (T_%d):
"""
%s
"""

Antithesis (A_%d):
"""
%s
"""

Produce a SYNTHESIS that integrates valid points from BOTH thesis and
antithesis into a more complete position. The synthesis becomes the new
thesis (T_%d) for the next dialectical iteration.

1. Identify where both sides agree (common ground)
2. Acknowledge genuinely unresolved tensions
3. Integrate valid points from BOTH sides
4. Arrive at a more nuanced, comprehensive position]]

local DEFAULT_SYNTHESIS_SYSTEM = [[
You are a master synthesizer. Your role is NOT to pick a side, but to
create a higher-order understanding that integrates the strongest
elements of both positions. The synthesis you produce will be carried
forward as the next thesis in the dialectical loop.]]

-- ─── Shape definitions ───

local thesis_args_shape = T.shape({
    task           = T.string:describe("Task or question to apply dialectic to"),
    thesis_prompt  = T.string:is_optional()
        :describe("Override template (1 positional arg: task)"),
    system_thesis  = T.string:is_optional()
        :describe("Override system prompt"),
}, { open = true })

local antithesis_args_shape = T.shape({
    task              = T.string:describe("Task or question"),
    thesis            = T.string:describe("Current thesis T_i"),
    antithesis_prompt = T.string:is_optional()
        :describe("Override template (2 positional args: task, thesis)"),
    system_antithesis = T.string:is_optional()
        :describe("Override system prompt"),
}, { open = true })

local synthesis_args_shape = T.shape({
    task             = T.string:describe("Task or question"),
    thesis           = T.string:describe("Current thesis T_i"),
    antithesis       = T.string:describe("Current antithesis A_i"),
    iteration        = T.number:describe("0-based iteration index i (used in synthesis prompt T_i / A_i / T_{i+1} labels)"),
    synthesis_prompt = T.string:is_optional()
        :describe("Override template (6 positional args: task, i, thesis, i, antithesis, i+1)"),
    system_synthesis = T.string:is_optional()
        :describe("Override system prompt"),
}, { open = true })

local temperature_at_args_shape = T.shape({
    iteration = T.number:describe("0-based iteration index i"),
    tau_0     = T.number:describe("Initial temperature τ_0"),
    theta     = T.number:describe("Decay constant θ ∈ [0.1, 0.5]"),
}, { open = true })

local prompt_pair_shape = T.shape({
    prompt = T.string:describe("LLM user prompt"),
    system = T.string:describe("LLM system prompt"),
}, { open = true })

local iteration_entry_shape = T.shape({
    iteration   = T.number:describe("0-based iteration index i"),
    antithesis  = T.string:describe("A_i — strongest counter to T_i"),
    tau_i       = T.number:describe("τ(i) = τ_0 · exp(-θ · i)"),
    synthesis   = T.string:describe("S_i — integrated position; becomes T_{i+1}"),
}, { open = true })

local run_input_shape = T.shape({
    task              = T.string:describe("Task or question (required)"),
    N                 = T.number:is_optional()
        :describe("Max iterations (default: " .. M._defaults.N .. ", (L) Abdali Table 1)"),
    tau_0             = T.number:is_optional()
        :describe("Initial temperature (default: " .. M._defaults.tau_0 .. ", (L) Abdali Table 1)"),
    tau_a             = T.number:is_optional()
        :describe("Antithesis temperature (default: " .. M._defaults.tau_a .. ", (L) Abdali Table 1)"),
    theta             = T.number:is_optional()
        :describe("Decay constant θ ∈ [0.1, 0.5] (default: " .. M._defaults.theta .. ", (X) within paper range)"),
    gen_tokens        = T.number:is_optional()
        :describe("Max tokens per LLM call (default: " .. M._defaults.gen_tokens .. ", (X) infrastructure)"),
    thesis_prompt     = T.string:is_optional()
        :describe("Override thesis prompt template (X)"),
    antithesis_prompt = T.string:is_optional()
        :describe("Override antithesis prompt template (X)"),
    synthesis_prompt  = T.string:is_optional()
        :describe("Override synthesis prompt template (X)"),
    system_thesis     = T.string:is_optional():describe("Override thesis system prompt (X)"),
    system_antithesis = T.string:is_optional():describe("Override antithesis system prompt (X)"),
    system_synthesis  = T.string:is_optional():describe("Override synthesis system prompt (X)"),
}, { open = true })

local run_result_shape = T.shape({
    answer     = T.string:describe("Final synthesis S_{N-1}; alias of result.final_synthesis"),
    thesis_0   = T.string:describe("Initial thesis T_0 from bootstrap LLM call"),
    iterations = T.array_of(iteration_entry_shape)
        :describe("Per-iteration log: { i, A_i, τ(i), S_i } for i = 0..N-1"),
    final_synthesis = T.string:describe("S_{N-1} — final integrated position"),
    N          = T.number:describe("Number of iterations actually executed"),
}, { open = true })

---@type AlcSpec
M.spec = {
    entries = {
        temperature_at = {
            args   = { temperature_at_args_shape },
            result = T.number,
        },
        build_thesis_prompt = {
            args   = { thesis_args_shape },
            result = prompt_pair_shape,
        },
        build_antithesis_prompt = {
            args   = { antithesis_args_shape },
            result = prompt_pair_shape,
        },
        build_synthesis_prompt = {
            args   = { synthesis_args_shape },
            result = prompt_pair_shape,
        },
        run = {
            input  = run_input_shape,
            result = run_result_shape,
        },
    },
}

-- ─── Input validation helpers ───

local function require_string(value, field, entry)
    if type(value) ~= "string" or value == "" then
        error(string.format(
            "hegelian.%s: %s must be a non-empty string, got %s",
            entry, field, type(value)), 3)
    end
end

local function require_number(value, field, entry)
    if type(value) ~= "number" then
        error(string.format(
            "hegelian.%s: %s must be a number, got %s",
            entry, field, type(value)), 3)
    end
end

local function require_positive_temperature(value, field, entry)
    require_number(value, field, entry)
    if value <= 0 then
        error(string.format(
            "hegelian.%s: %s must be > 0, got %s",
            entry, field, tostring(value)), 3)
    end
end

local function require_theta_in_range(value, entry)
    require_number(value, "theta", entry)
    if value < M._theta_range.min or value > M._theta_range.max then
        error(string.format(
            "hegelian.%s: theta must be in [%g, %g] per Abdali 2025 Table 1, got %s",
            entry, M._theta_range.min, M._theta_range.max, tostring(value)), 3)
    end
end

local function require_positive_integer(value, field, entry)
    require_number(value, field, entry)
    if value < 1 or value ~= math.floor(value) then
        error(string.format(
            "hegelian.%s: %s must be a positive integer, got %s",
            entry, field, tostring(value)), 3)
    end
end

local function require_nonneg_integer(value, field, entry)
    require_number(value, field, entry)
    if value < 0 or value ~= math.floor(value) then
        error(string.format(
            "hegelian.%s: %s must be a non-negative integer, got %s",
            entry, field, tostring(value)), 3)
    end
end

-- ─── Pure: temperature_at ───
--
-- τ(i) = τ_0 · exp(-θ · i)
--
-- Abdali 2025 §3.2 annealing formula. Used internally by `run` to compute
-- the synthesis temperature per iteration. Exposed as a public entry so
-- callers can pre-compute the temperature schedule for budgeting and
-- can unit-test the formula without launching LLM calls.

---@param args {iteration:number, tau_0:number, theta:number}
---@return number
function M.temperature_at(args)
    if type(args) ~= "table" then
        error("hegelian.temperature_at: args must be a table", 2)
    end
    require_nonneg_integer(args.iteration, "iteration", "temperature_at")
    require_positive_temperature(args.tau_0, "tau_0", "temperature_at")
    require_theta_in_range(args.theta, "temperature_at")
    return args.tau_0 * math.exp(-args.theta * args.iteration)
end

-- ─── Pure: build_thesis_prompt ───
--
-- Returns { prompt, system } strings ready to pass to alc.llm. Pure string
-- ops, no LLM call. Default template (X) provenance: see DEFAULT_THESIS_PROMPT.

---@param args {task:string, thesis_prompt?:string, system_thesis?:string}
---@return {prompt:string, system:string}
function M.build_thesis_prompt(args)
    if type(args) ~= "table" then
        error("hegelian.build_thesis_prompt: args must be a table", 2)
    end
    require_string(args.task, "task", "build_thesis_prompt")
    local template = args.thesis_prompt or DEFAULT_THESIS_PROMPT
    local system   = args.system_thesis or DEFAULT_THESIS_SYSTEM
    return {
        prompt = string.format(template, args.task),
        system = system,
    }
end

-- ─── Pure: build_antithesis_prompt ───
--
-- A_i ← M(T_i, τ_a, p_a)  per Abdali Alg.1 L6.
--
-- Template positional args: (task, thesis).

---@param args {task:string, thesis:string, antithesis_prompt?:string, system_antithesis?:string}
---@return {prompt:string, system:string}
function M.build_antithesis_prompt(args)
    if type(args) ~= "table" then
        error("hegelian.build_antithesis_prompt: args must be a table", 2)
    end
    require_string(args.task, "task", "build_antithesis_prompt")
    require_string(args.thesis, "thesis", "build_antithesis_prompt")
    local template = args.antithesis_prompt or DEFAULT_ANTITHESIS_PROMPT
    local system   = args.system_antithesis or DEFAULT_ANTITHESIS_SYSTEM
    return {
        prompt = string.format(template, args.task, args.thesis),
        system = system,
    }
end

-- ─── Pure: build_synthesis_prompt ───
--
-- S_i ← M(T_i, A_i, τ(i), p_s)  per Abdali Alg.1 L8.
--
-- Template positional args: (task, i, thesis, i, antithesis, i+1).

---@param args {task:string, thesis:string, antithesis:string, iteration:number, synthesis_prompt?:string, system_synthesis?:string}
---@return {prompt:string, system:string}
function M.build_synthesis_prompt(args)
    if type(args) ~= "table" then
        error("hegelian.build_synthesis_prompt: args must be a table", 2)
    end
    require_string(args.task, "task", "build_synthesis_prompt")
    require_string(args.thesis, "thesis", "build_synthesis_prompt")
    require_string(args.antithesis, "antithesis", "build_synthesis_prompt")
    require_nonneg_integer(args.iteration, "iteration", "build_synthesis_prompt")
    local template = args.synthesis_prompt or DEFAULT_SYNTHESIS_PROMPT
    local system   = args.system_synthesis or DEFAULT_SYNTHESIS_SYSTEM
    return {
        prompt = string.format(template,
            args.task, args.iteration, args.thesis,
            args.iteration, args.antithesis, args.iteration + 1),
        system = system,
    }
end

-- ─── Strategy: run ───
--
-- Orchestrates Abdali Alg.1:
--
--   T_0     ← LLM(thesis_prompt, temperature = τ_0)
--   for i = 0..N-1:
--       A_i  ← LLM(antithesis_prompt(T_i), temperature = τ_a)
--       τ(i) = τ_0 · exp(-θ · i)
--       S_i  ← LLM(synthesis_prompt(T_i, A_i), temperature = τ(i))
--       T_{i+1} ← S_i
--   answer = final_synthesis = S_{N-1}
--
-- Total LLM call count: 1 + 2N (1 bootstrap thesis + 2 per iteration).

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    if type(ctx) ~= "table" then
        error("hegelian.run: ctx must be a table", 2)
    end
    require_string(ctx.task, "task", "run")

    local N          = ctx.N          or M._defaults.N
    local tau_0      = ctx.tau_0      or M._defaults.tau_0
    local tau_a      = ctx.tau_a      or M._defaults.tau_a
    local theta      = ctx.theta      or M._defaults.theta
    local gen_tokens = ctx.gen_tokens or M._defaults.gen_tokens

    require_positive_integer(N, "N", "run")
    require_positive_temperature(tau_0, "tau_0", "run")
    require_positive_temperature(tau_a, "tau_a", "run")
    require_theta_in_range(theta, "run")
    require_positive_integer(gen_tokens, "gen_tokens", "run")

    -- ─── Bootstrap: T_0 ───
    alc.log("info", "hegelian: generating initial thesis T_0")
    local thesis_pp = M.build_thesis_prompt({
        task = ctx.task,
        thesis_prompt = ctx.thesis_prompt,
        system_thesis = ctx.system_thesis,
    })
    local T_0 = alc.llm(thesis_pp.prompt, {
        system      = thesis_pp.system,
        max_tokens  = gen_tokens,
        temperature = tau_0,
    })
    if type(T_0) ~= "string" or T_0 == "" then
        error("hegelian.run: bootstrap thesis LLM call returned empty string", 2)
    end

    -- ─── Iterative dialectic loop ───
    local current_thesis = T_0
    local iterations = {}

    for i = 0, N - 1 do
        alc.log("info", string.format(
            "hegelian: iteration %d/%d antithesis", i + 1, N))

        local anti_pp = M.build_antithesis_prompt({
            task = ctx.task,
            thesis = current_thesis,
            antithesis_prompt = ctx.antithesis_prompt,
            system_antithesis = ctx.system_antithesis,
        })
        local A_i = alc.llm(anti_pp.prompt, {
            system      = anti_pp.system,
            max_tokens  = gen_tokens,
            temperature = tau_a,
        })
        if type(A_i) ~= "string" or A_i == "" then
            error(string.format(
                "hegelian.run: antithesis at iteration %d returned empty string", i), 2)
        end

        local tau_i = M.temperature_at({
            iteration = i,
            tau_0     = tau_0,
            theta     = theta,
        })

        alc.log("info", string.format(
            "hegelian: iteration %d/%d synthesis (τ=%.4f)", i + 1, N, tau_i))

        local synth_pp = M.build_synthesis_prompt({
            task = ctx.task,
            thesis = current_thesis,
            antithesis = A_i,
            iteration = i,
            synthesis_prompt = ctx.synthesis_prompt,
            system_synthesis = ctx.system_synthesis,
        })
        local S_i = alc.llm(synth_pp.prompt, {
            system      = synth_pp.system,
            max_tokens  = gen_tokens,
            temperature = tau_i,
        })
        if type(S_i) ~= "string" or S_i == "" then
            error(string.format(
                "hegelian.run: synthesis at iteration %d returned empty string", i), 2)
        end

        iterations[#iterations + 1] = {
            iteration = i,
            antithesis = A_i,
            tau_i = tau_i,
            synthesis = S_i,
        }

        current_thesis = S_i  -- T_{i+1} ← S_i (Alg.1 L16)
    end

    local final_synthesis = current_thesis

    alc.log("info", string.format(
        "hegelian: complete — %d iteration(s), %d LLM calls",
        N, 1 + 2 * N))

    ctx.result = {
        answer          = final_synthesis,
        thesis_0        = T_0,
        iterations      = iterations,
        final_synthesis = final_synthesis,
        N               = N,
    }
    return ctx
end

-- ─── S.instrument decoration ───
--
-- Wraps each public entry with dev-mode shape validation. Pure entries
-- (temperature_at / build_*_prompt) get input-args + result validation;
-- run gets input + result validation against M.spec.entries.run.

M.temperature_at          = S.instrument(M, "temperature_at")
M.build_thesis_prompt     = S.instrument(M, "build_thesis_prompt")
M.build_antithesis_prompt = S.instrument(M, "build_antithesis_prompt")
M.build_synthesis_prompt  = S.instrument(M, "build_synthesis_prompt")
M.run                     = S.instrument(M, "run")

return M
