--- think_prm(ThinkPRM) — verifier that thinks before judging each step
---
--- Drives an LLM as a process reward model that emits a verification
--- chain ("Let's verify step by step ... Step k: <critique> ...
--- \boxed{correct|incorrect}") and then extracts per-step verdicts plus
--- a solution-level binary verdict. Implements the training-free /
--- zero-shot path described by the paper; the finetuned ThinkPRM
--- force-decode aggregation is out of scope (see Caveats).
---
--- ## Algorithm
---
--- 1. `build_prompt` — insert `{problem}` and step-indexed `{solution}`
---    into the paper Figure 14 verifier template (verbatim by default;
---    the `early_stop_on_incorrect=false` knob substitutes the last
---    line for an explicit "critique all steps" instruction).
--- 2. `verify` — invoke the LLM once with the built prompt to obtain a
---    verification chain, then `parse_verdicts` extracts the per-step
---    `\boxed{correct|incorrect}` tokens.
--- 3. `aggregate` — collapse per-CoT verdicts to a solution-level
---    binary (`any_incorrect` default; matches Figure 14 early-stop
---    semantics).
--- 4. `run` — repeat steps 1-3 `n_parallel_cots` times (paper §4 K-CoT
---    scaling) and average the per-CoT binary verdicts into a
---    continuous score in [0, 1] (the paper's force-decode P(yes) /
---    [P(yes) + P(no)] is out of scope; see Caveats).
---
--- `M.run` and `M.verify` use **nested dispatch** so the
--- `S.instrument` wrappers fire on every sub-call:
---
---   - `M.run` calls `M.verify` (× K) and `M.aggregate` (× K)
---   - `M.verify` calls `M.build_prompt` and `M.parse_verdicts`
---
--- See `alc_shapes/README` §Producer usage "Nested dispatch".
---
--- ## Implementation choices (paper does not prescribe; spelled out)
---
--- Every default below records its source explicitly in its inline
--- comment: paper-literal citations with section refs, industry-
--- standard heuristics with source links, or implementation-choice
--- rationale spelled out. No default is implicit.
---
---  - `prompt_template` = Figure 14 verbatim — Khalifa 2025
---    Appendix A.2 / Figure 14. Override voids the paper's correctness
---    reports.
---  - `temperature` = 0.1 — Khalifa 2025 §4 sampling default
---    (also matches the official GitHub config).
---  - `max_thinking_tokens` = 4096 — Khalifa 2025 §4 upper
---    bound to avoid overthinking (paper notes max_length=4096 in the
---    implementation).
---  - `n_parallel_cots` = 1 — Khalifa 2025 §4 K-CoT averaging.
---    Default 1 reproduces the single-chain baseline; experimental
---    range 1 / 4 / 8.
---  - `early_stop_on_incorrect` = true — Figure 14 prompt
---    literally instructs the verifier to stop at the first incorrect
---    step. The paper experiments are with early-stop on; setting
---    false substitutes the final prompt line for an explicit
---    "critique all steps" instruction, voiding paper alignment.
---  - `aggregation` = "any_incorrect" — The paper §E.1
---    canonical solution score is `P(yes) / [P(yes) + P(no)]`
---    force-decoded after the verification chain, which requires
---    next-token logits access that `alc.llm` does not expose. The
---    training-free path uses the early-stop prompt's implied logic:
---    presence of any `\boxed{incorrect}` ⇒ solution incorrect. The
---    optional `all_correct` method requires every verdict to be
---    "correct" (rejects on any non-correct token, useful for stricter
---    callers).
---  - `score_majority_threshold` = 0.5 — K-CoT averaged
---    fraction of "correct" chains is binarized at 0.5 to produce the
---    `correct` field. Paper does not specify a threshold for the
---    text-level approximation; 0.5 is the natural majority cutoff.
---    Callers needing a different operating point should consult
---    `score` directly and threshold themselves.
---  - `chars_per_token` etc. — not applicable; this pkg does not
---    impose its own cumulative budget. Caller-provided
---    `max_thinking_tokens` is per-CoT.
---  - `verifier_system_prompt` — Single-line persona
---    conditioning ("You are a careful math verifier. Follow the
---    requested output format exactly."). Paper Figure 14 is a
---    user-side prompt; the system-prompt wording is impl choice.
---    Held constant across all K parallel CoTs.
---
--- ## Caveats
---
--- Two large caveats apply when using this pkg:
---
--- 1. **The verifier model matters a lot**. The paper reports that
---    smaller distilled models (e.g. R1-Distill-Qwen-1.5B) emit invalid
---    judgment formats 51%+ of the time and effectively cannot serve
---    as verifiers. The training-free path here only matches paper
---    performance when callers route to a strong reasoning model — the
---    paper baselines use R1-Distill-Qwen-14B or QwQ-32B-Preview.
---
--- 2. **The canonical ThinkPRM solution score is out of scope**. Paper
---    §E.1 produces a continuous solution score by force-decoding the
---    string "Is the solution correct?" after the verification chain
---    and using `P(yes) / (P(yes) + P(no))` from next-token logits.
---    That requires direct logits access which `alc.llm` does not
---    expose; this pkg aggregates via the `\boxed{correct|incorrect}`
---    literals only. K-CoT parallel scaling is approximated by
---    averaging per-CoT binary verdicts into a continuous score in
---    [0, 1] and binarizing at `score_majority_threshold` (default
---    0.5) for the `correct` field.
---
--- When every verification chain in a K-CoT run is invalid (no
--- `\boxed{...}` tokens parsed), `run` returns `invalid = true`,
--- `score = 0`, `correct = false`, `valid_chains = 0`. The `correct`
--- field is `false` because the solution cannot be defended as
--- correct without any valid verdict; callers should treat
--- `invalid = true` as the primary signal and not interpret
--- `correct = false` as a positive incorrect judgment.
---
--- ## References
---
--- - Khalifa, M., Agarwal, R., Logeswaran, L., Kim, J., Peng, H.,
---   Lee, M., Lee, H., Wang, L. (2025). "Process Reward Models That
---   Think (ThinkPRM)". arXiv:2504.16828 §3 (method), §4 (experiments
---   / K-CoT scaling), Appendix A.2 / Figure 14 (verifier prompt
---   template), Appendix E.1 (aggregation).
---   https://arxiv.org/abs/2504.16828
--- - Official code + models: https://github.com/mukhal/thinkprm

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "think_prm",
    version = "0.2.0",
    description = "ThinkPRM verifier — per-step thinking chain + \\boxed{correct|incorrect} verdicts (Khalifa 2025 §4 / Figure 14, training-free path).",
    category = "validation",
    alc_shapes_compat = "^0.25",
}

-- ---- Default values ----
-- (L) paper literal, (I) industry standard, (X) impl choice. Every
-- default has an inline tag + rationale; readers should be able to
-- verify each value against the paper or the cited source.

-- (L) Paper Figure 14 sampling default for the verifier (also matches
-- the official GitHub config).
local DEFAULT_TEMPERATURE = 0.1

-- (L) Paper §4 upper bound to avoid overthinking (max_length = 4096).
local DEFAULT_MAX_THINKING_TOKENS = 4096

-- (L) Paper §4 K-CoT averaging. K = 1 reproduces the single-chain
-- behaviour; K = 4 / 8 are the parallel-scaling experimental settings.
local DEFAULT_N_PARALLEL_COTS = 1

-- (L) Paper Figure 14 prompt literally instructs the verifier to stop
-- at the first incorrect step. Setting false continues judging all
-- steps; the paper's reports are with early-stop on.
local DEFAULT_EARLY_STOP_ON_INCORRECT = true

-- (X) Aggregation default for the training-free / zero-shot path. The
-- paper's canonical score (P(yes)/(P(yes)+P(no)) force-decode) is out
-- of scope (see Caveats); "any_incorrect" is the implied logic of the
-- early-stop prompt and matches the paper's binary verdict semantics.
local DEFAULT_AGGREGATION = "any_incorrect"

-- (X) K-CoT averaged fraction is binarized at this threshold to
-- produce the run-level `correct` field. Paper does not specify; 0.5
-- is the natural majority cutoff for the text-level approximation.
local DEFAULT_SCORE_MAJORITY_THRESHOLD = 0.5

-- (X) Single-line persona conditioning for the verifier. Paper
-- Figure 14 is a user-side prompt; the system-prompt wording is impl
-- choice. Held constant across all K parallel CoTs.
local VERIFIER_SYSTEM_PROMPT =
    "You are a careful math verifier. Follow the requested output format exactly."

-- (L) Paper Figure 14 verbatim verifier prompt template body. The
-- final "Once you find an incorrect step ..." line is split out as a
-- separate tail so the `early_stop_on_incorrect=false` knob can
-- substitute an explicit "critique all steps" instruction without
-- breaking the rest of the literal.
local FIGURE_14_BODY = [[You are given a math problem and a proposed multiple-step solution (with a step on each line):

[Math Problem]
%s

[Solution]
%s

Review and critique the proposed solution steps and determine whether each step is correct. If the solution is incomplete, only critique the steps that are provided.

Your output must be in the following format:

Let's verify step by step:
Step 1: <critique>…The step is \boxed{correct/incorrect}
Step 2: <critique>…The step is \boxed{correct/incorrect}
…
Step n: <critique>…The step is \boxed{correct/incorrect}

]]

-- (L) Paper Figure 14 last line (verbatim).
local FIGURE_14_EARLY_STOP_TAIL =
    "Once you find an incorrect step, you should stop since you don't need to analyze the remaining steps.\n"

-- (X) Substitute for the Figure 14 last line when
-- `early_stop_on_incorrect = false`. Explicit instruction to keep
-- judging all steps. Voids paper alignment (paper reports are with
-- early-stop on).
local NO_EARLY_STOP_TAIL =
    "Critique every step regardless of whether earlier steps were judged incorrect.\n"

-- (L) Default prompt template: Figure 14 verbatim (body + early-stop
-- tail). Equivalent to FIGURE_14_BODY .. FIGURE_14_EARLY_STOP_TAIL.
local DEFAULT_PROMPT_TEMPLATE = FIGURE_14_BODY .. FIGURE_14_EARLY_STOP_TAIL

-- (X) No-early-stop variant of the prompt template.
local NO_EARLY_STOP_TEMPLATE = FIGURE_14_BODY .. NO_EARLY_STOP_TAIL

-- ---- pure helpers ----

local function format_solution(solution_steps)
    if type(solution_steps) ~= "table" then return "" end
    local lines = {}
    for i, step in ipairs(solution_steps) do
        lines[#lines + 1] = string.format("Step %d: %s", i, step)
    end
    return table.concat(lines, "\n")
end

local function pure_build_prompt(problem, solution_steps, template)
    return string.format(template, problem, format_solution(solution_steps))
end

--- Resolve the prompt template, preferring (in order): a caller-
--- supplied custom template, the early-stop variant when
--- early_stop_on_incorrect is true (Figure 14 verbatim), the
--- no-early-stop variant otherwise.
local function resolve_template(custom_template, early_stop)
    if custom_template ~= nil then return custom_template end
    if early_stop then return DEFAULT_PROMPT_TEMPLATE end
    return NO_EARLY_STOP_TEMPLATE
end

--- Parse a verifier chain into an ordered list of per-step verdicts.
--- Returns `{verdicts = [...], invalid = bool}`. Each verdict is
--- "correct" or "incorrect". When no `\boxed{correct|incorrect}` token
--- is found at all, the chain is marked invalid (= judgment cannot be
--- extracted). Other `\boxed{...}` tokens (e.g. `\boxed{maybe}`) are
--- ignored.
local function pure_parse_verdicts(chain)
    local verdicts = {}
    for token in chain:gmatch("\\boxed{(%w+)}") do
        local lc = token:lower()
        if lc == "correct" or lc == "incorrect" then
            verdicts[#verdicts + 1] = lc
        end
    end
    return {
        verdicts = verdicts,
        invalid = #verdicts == 0,
    }
end

--- Collapse one chain's per-step verdicts into a solution-level boolean.
--- `any_incorrect`: solution incorrect iff any step is incorrect.
--- `all_correct`: solution correct iff every step is correct AND there
---   was at least one verdict (chain not invalid).
local function pure_aggregate_one(verdicts, method)
    if not verdicts or #verdicts == 0 then
        return { correct = false, invalid = true }
    end
    if method == "all_correct" then
        for _, v in ipairs(verdicts) do
            if v ~= "correct" then
                return { correct = false, invalid = false }
            end
        end
        return { correct = true, invalid = false }
    end
    -- default any_incorrect
    for _, v in ipairs(verdicts) do
        if v == "incorrect" then
            return { correct = false, invalid = false }
        end
    end
    return { correct = true, invalid = false }
end

--- Average per-CoT binary verdicts into a [0, 1] solution score and
--- pick a majority binary at `threshold` (default 0.5). Invalid chains
--- are excluded from the denominator; if every chain is invalid the
--- result is `invalid = true`, `score = 0`, `correct = false`.
local function pure_aggregate_k(per_chain, threshold)
    threshold = threshold or DEFAULT_SCORE_MAJORITY_THRESHOLD
    local valid = 0
    local correct = 0
    for _, c in ipairs(per_chain) do
        if not c.invalid then
            valid = valid + 1
            if c.correct then correct = correct + 1 end
        end
    end
    if valid == 0 then
        return {
            score = 0,
            correct = false,
            invalid = true,
            valid_chains = 0,
        }
    end
    local score = correct / valid
    return {
        score = score,
        correct = score >= threshold,
        invalid = false,
        valid_chains = valid,
    }
end

---@type AlcSpec
M.spec = {
    entries = {
        build_prompt = {
            input = T.shape({
                problem = T.string:describe("Math problem statement"),
                solution_steps = T.array_of(T.string):describe(
                    "Solution as an ordered list of step strings (one step per element)"
                ),
                prompt_template = T.string:is_optional():describe(
                    "Override template (default: paper Figure 14 verbatim — Khalifa 2025 literal. Override voids paper's correctness reports.)"
                ),
                early_stop_on_incorrect = T.boolean:is_optional():describe(
                    "When true (default; Figure 14 literal) the template instructs the verifier to stop at the first incorrect step. When false, substitutes the Figure 14 last line for an explicit 'critique every step' instruction (voids paper alignment). Ignored when prompt_template is supplied."
                ),
            }),
            result = T.shape({
                prompt = T.string:describe("Rendered verifier prompt with problem and step-indexed solution"),
            }),
        },
        parse_verdicts = {
            input = T.shape({
                chain = T.string:describe("Verifier chain text containing per-step \\boxed{correct|incorrect} tokens"),
            }),
            result = T.shape({
                verdicts = T.array_of(T.string):describe(
                    "Ordered per-step verdicts ('correct' / 'incorrect'). Unknown \\boxed tokens (e.g. \\boxed{maybe}) are skipped."
                ),
                invalid = T.boolean:describe(
                    "True when no \\boxed{correct|incorrect} token is present; judgment is unusable"
                ),
            }),
        },
        aggregate = {
            input = T.shape({
                verdicts = T.array_of(T.string):describe(
                    "Per-step verdicts from one verification chain"
                ),
                method = T.string:is_optional():describe(
                    "'any_incorrect' (default; matches Figure 14 early-stop semantics) or 'all_correct' (rejects on any non-correct token)"
                ),
            }),
            result = T.shape({
                correct = T.boolean:describe("Solution-level binary verdict for one chain"),
                invalid = T.boolean:describe("True when verdicts list is empty"),
            }),
        },
        verify = {
            input = T.shape({
                problem = T.string:describe("Math problem statement"),
                solution_steps = T.array_of(T.string):describe(
                    "Solution as an ordered list of step strings"
                ),
                prompt_template = T.string:is_optional():describe(
                    "Override template (default: paper Figure 14 verbatim — Khalifa 2025 literal)"
                ),
                early_stop_on_incorrect = T.boolean:is_optional():describe(
                    "Toggle the Figure 14 early-stop instruction (default: true — Khalifa 2025 Figure 14 literal). Ignored when prompt_template is supplied."
                ),
                temperature = T.number:is_optional():describe(
                    "LLM sampling temperature (default: 0.1; Khalifa 2025 §4)"
                ),
                max_thinking_tokens = T.number:is_optional():describe(
                    "Token cap for the verifier chain (default: 4096; Khalifa 2025 §4 to avoid overthinking)"
                ),
            }),
            result = T.shape({
                chain = T.string:describe("Raw verifier chain text"),
                verdicts = T.array_of(T.string):describe("Per-step extracted verdicts"),
                invalid = T.boolean:describe("True when parsing failed (no \\boxed tokens found)"),
            }),
        },
        run = {
            input = T.shape({
                problem = T.string:describe("Math problem statement"),
                solution_steps = T.array_of(T.string):describe(
                    "Solution as an ordered list of step strings (one step per element)"
                ),
                n_parallel_cots = T.number:is_optional():describe(
                    "Independent verification chains to sample (default: 1; paper §4 K-CoT averaging, experimental range 1 / 4 / 8)"
                ),
                prompt_template = T.string:is_optional():describe(
                    "Override verifier prompt template (default: paper Figure 14 verbatim — Khalifa 2025 literal. Override voids paper's correctness reports.)"
                ),
                early_stop_on_incorrect = T.boolean:is_optional():describe(
                    "Toggle the Figure 14 early-stop instruction (default: true — Khalifa 2025 Figure 14 literal). Ignored when prompt_template is supplied."
                ),
                temperature = T.number:is_optional():describe(
                    "LLM sampling temperature (default: 0.1; Khalifa 2025 §4 default)"
                ),
                max_thinking_tokens = T.number:is_optional():describe(
                    "Token cap per verifier chain (default: 4096; Khalifa 2025 §4 to avoid overthinking)"
                ),
                aggregation = T.string:is_optional():describe(
                    "Per-chain aggregation method (default: 'any_incorrect'; matches Figure 14 early-stop semantics. 'all_correct' requires every step verdict to be correct. The paper's canonical force-decode P(yes)/(P(yes)+P(no)) is out of scope — see Caveats.)"
                ),
                score_majority_threshold = T.number:is_optional():describe(
                    "Threshold used to binarize the K-CoT averaged score into the `correct` field (default: 0.5;— paper does not specify, 0.5 is the natural majority cutoff)"
                ),
            }),
            result = T.shape({
                correct = T.boolean:describe(
                    "Solution-level binary: K-CoT averaged score >= score_majority_threshold (implementation choice — see Caveats for the paper's force-decode alternative)."
                ),
                score = T.number:describe(
                    "Fraction of valid chains that judged the solution correct, in [0, 1] (paper §4 K-CoT averaging approximation; 0 when all chains invalid)"
                ),
                invalid = T.boolean:describe(
                    "True when every verification chain was invalid (no \\boxed tokens parsed). Treat as the primary signal; correct=false alongside invalid=true is not a positive incorrect judgment."
                ),
                valid_chains = T.number:describe("Number of chains whose verdicts parsed successfully"),
                chains = T.array_of(T.shape({
                    chain = T.string:describe("Raw verifier chain text"),
                    verdicts = T.array_of(T.string):describe("Per-step verdicts extracted from this chain"),
                    correct = T.boolean:describe("Per-chain solution-level binary verdict"),
                    invalid = T.boolean:describe("True when this chain had no parseable verdicts"),
                })):describe("Per-chain records for inspection"),
            }),
        },
    },
}

-- ---- entries ----

---@param ctx AlcCtx
---@return AlcCtx
function M.build_prompt(ctx)
    local problem = ctx.problem or error("ctx.problem is required")
    local solution_steps = ctx.solution_steps or error("ctx.solution_steps is required")
    local early_stop
    if ctx.early_stop_on_incorrect ~= nil then
        early_stop = ctx.early_stop_on_incorrect
    else
        early_stop = DEFAULT_EARLY_STOP_ON_INCORRECT
    end
    local template = resolve_template(ctx.prompt_template, early_stop)
    ctx.result = { prompt = pure_build_prompt(problem, solution_steps, template) }
    return ctx
end

---@param ctx AlcCtx
---@return AlcCtx
function M.parse_verdicts(ctx)
    local chain = ctx.chain or error("ctx.chain is required")
    ctx.result = pure_parse_verdicts(chain)
    return ctx
end

---@param ctx AlcCtx
---@return AlcCtx
function M.aggregate(ctx)
    local verdicts = ctx.verdicts or error("ctx.verdicts is required")
    local method = ctx.method or DEFAULT_AGGREGATION
    ctx.result = pure_aggregate_one(verdicts, method)
    return ctx
end

---@param ctx AlcCtx
---@return AlcCtx
function M.verify(ctx)
    local problem = ctx.problem or error("ctx.problem is required")
    local solution_steps = ctx.solution_steps or error("ctx.solution_steps is required")
    local temperature = ctx.temperature or DEFAULT_TEMPERATURE
    local max_tokens = ctx.max_thinking_tokens or DEFAULT_MAX_THINKING_TOKENS

    -- Phase: nested dispatch via M.build_prompt so the wrapped
    -- (instrumented) version fires its own input/result shape check.
    local bp = M.build_prompt({
        problem = problem,
        solution_steps = solution_steps,
        prompt_template = ctx.prompt_template,
        early_stop_on_incorrect = ctx.early_stop_on_incorrect,
    })
    local prompt = bp.result.prompt

    local chain = alc.llm(prompt, {
        system = VERIFIER_SYSTEM_PROMPT,
        max_tokens = max_tokens,
        temperature = temperature,
    })

    -- Phase: nested dispatch via M.parse_verdicts.
    local pv = M.parse_verdicts({ chain = chain })
    ctx.result = {
        chain = chain,
        verdicts = pv.result.verdicts,
        invalid = pv.result.invalid,
    }
    return ctx
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local problem = ctx.problem or error("ctx.problem is required")
    local solution_steps = ctx.solution_steps or error("ctx.solution_steps is required")
    local n = ctx.n_parallel_cots or DEFAULT_N_PARALLEL_COTS
    local aggregation = ctx.aggregation or DEFAULT_AGGREGATION
    local threshold = ctx.score_majority_threshold or DEFAULT_SCORE_MAJORITY_THRESHOLD

    if n < 1 then n = 1 end

    local chains = {}
    for i = 1, n do
        -- Phase: nested dispatch via M.verify (each call goes through
        -- M.build_prompt + M.parse_verdicts internally).
        local v = M.verify({
            problem = problem,
            solution_steps = solution_steps,
            prompt_template = ctx.prompt_template,
            early_stop_on_incorrect = ctx.early_stop_on_incorrect,
            temperature = ctx.temperature,
            max_thinking_tokens = ctx.max_thinking_tokens,
        })

        local per_chain
        if v.result.invalid then
            per_chain = { correct = false, invalid = true }
        else
            -- Phase: nested dispatch via M.aggregate.
            local ag = M.aggregate({
                verdicts = v.result.verdicts,
                method = aggregation,
            })
            per_chain = ag.result
        end

        chains[i] = {
            chain = v.result.chain,
            verdicts = v.result.verdicts,
            correct = per_chain.correct,
            invalid = v.result.invalid or per_chain.invalid,
        }
        alc.log("info", string.format(
            "think_prm: chain %d/%d (valid=%s, correct=%s)",
            i, n, tostring(not chains[i].invalid), tostring(per_chain.correct)
        ))
    end

    local agg = pure_aggregate_k(chains, threshold)
    ctx.result = {
        correct = agg.correct,
        score = agg.score,
        invalid = agg.invalid,
        valid_chains = agg.valid_chains,
        chains = chains,
    }
    return ctx
end

-- Malli-style self-decoration. Wrap each entry independently; nested
-- dispatch in M.run / M.verify relies on these wrappers being
-- installed before any call goes out (alc_shapes/README §Producer
-- usage "Nested dispatch").
M.build_prompt = S.instrument(M, "build_prompt")
M.parse_verdicts = S.instrument(M, "parse_verdicts")
M.aggregate = S.instrument(M, "aggregate")
M.verify = S.instrument(M, "verify")
M.run = S.instrument(M, "run")

return M
