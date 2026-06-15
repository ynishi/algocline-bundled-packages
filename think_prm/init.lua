--- think_prm(ThinkPRM) — verifier that thinks before judging each step
---
--- Drives an LLM as a process reward model that emits a verification
--- chain (Let's verify step by step ... step k: <critique> ... \boxed{
--- correct|incorrect}) and then extracts per-step verdicts plus a
--- solution-level binary verdict. Implements the training-free / zero-
--- shot path described by the paper; the finetuned ThinkPRM force-
--- decode aggregation is out of scope (see Caveats).
---
--- ## Usage
---
--- ```lua
--- local think_prm = require("think_prm")
--- return think_prm.run({
---     problem = "...",
---     solution_steps = { "Step1 ...", "Step2 ...", ... },
--- })
--- ```
---
--- ## Algorithm
---
--- 1. build_prompt: insert {problem} and {solution} (step-indexed)
---    into the verifier prompt template (Figure 14 literal).
--- 2. Call the verifier LLM n_parallel_cots times (K-CoT scaling, §4)
---    to obtain K independent verification chains.
--- 3. parse_verdicts: extract `\boxed{correct}` / `\boxed{incorrect}`
---    tokens per step from each verification chain.
--- 4. aggregate: collapse per-CoT, per-step verdicts to one
---    solution-level score. `any_incorrect` (default) returns false at
---    the first incorrect step in any CoT averaged across CoTs.
---
--- ## Caveats
---
--- Two large caveats apply when using this pkg:
---
--- 1. **The verifier model matters a lot**. The paper reports that
---    smaller distilled models (e.g. R1-Distill-Qwen-1.5B) emit invalid
---    judgment formats 51%+ of the time and effectively cannot serve as
---    verifiers. The training-free path here only matches paper
---    performance when callers route to a strong reasoning model — the
---    paper baselines use R1-Distill-Qwen-14B or QwQ-32B-Preview.
---    Callers running smaller models should expect high invalid /
---    parse-failure rates.
---
--- 2. **The canonical ThinkPRM solution score is out of scope**. Paper
---    §E.1 produces a continuous solution score by force-decoding the
---    string "Is the solution correct?" after the verification chain
---    and using `P(yes) / (P(yes) + P(no))` from next-token logits.
---    That requires direct logits access which the `alc.llm` abstraction
---    does not expose; therefore this pkg aggregates using the
---    `\boxed{correct|incorrect}` literals only. The paper's K-CoT
---    parallel scaling is approximated by averaging the per-CoT binary
---    solution verdicts into a continuous score in [0, 1].
---
--- The prompt template is taken verbatim from Figure 14 of the paper.
--- Callers can override it via `prompt_template` but doing so voids the
--- paper's correctness reports.
---
--- ## References
---
--- - Khalifa, M., Agarwal, R., Logeswaran, L., Kim, J., Peng, H.,
---   Lee, M., Lee, H., Wang, L. (2025). "Process Reward Models That
---   Think (ThinkPRM)". arXiv:2504.16828 §3 (method), §4 (experiments),
---   Figure 14 (verifier prompt template), Appendix A.2 / E.1
---   (aggregation). https://arxiv.org/abs/2504.16828
--- - Official code + models: https://github.com/mukhal/thinkprm

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "think_prm",
    version = "0.1.0",
    description = "ThinkPRM verifier — emits a per-step thinking chain and \\boxed{correct|incorrect} verdicts.",
    category = "validation",
    alc_shapes_compat = "^0.25",
}

-- (L) Paper Figure 14 literal verifier prompt template. Use raw string
-- to preserve the exact wording.
local DEFAULT_PROMPT_TEMPLATE = [[
You are given a math problem and a proposed multiple-step solution (with a step on each line):

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

Once you find an incorrect step, you should stop since you don't need to analyze the remaining steps.
]]

-- (L) Paper §4 sampling default for verifier; matches GitHub repo.
local DEFAULT_TEMPERATURE = 0.1

-- (L) Paper §4 upper bound to avoid overthinking (max_length = 4096).
local DEFAULT_MAX_THINKING_TOKENS = 4096

-- (L) Paper §4 K-CoT averaging. K = 1 reproduces the single-chain
-- behaviour; K = 4 / 8 are the parallel-scaling experimental settings.
local DEFAULT_N_PARALLEL_COTS = 1

-- (L) Paper Figure 14 prompt literally instructs the verifier to stop
-- at the first incorrect step. Setting to false continues judging all
-- steps; the paper's reports are with early-stop on.
local DEFAULT_EARLY_STOP_ON_INCORRECT = true

-- (X) Aggregation default for the training-free / zero-shot path. The
-- paper's canonical score (P(yes)/(P(yes)+P(no)) force-decode) is out
-- of scope (see Caveats); "any_incorrect" is the implied logic of the
-- early-stop prompt and matches the paper's binary verdict semantics.
local DEFAULT_AGGREGATION = "any_incorrect"

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

--- Parse a verifier chain into an ordered list of per-step verdicts.
--- Returns `{verdicts = [...], invalid = bool}`. Each verdict is
--- "correct" or "incorrect". When no \boxed token is found at all, the
--- chain is marked invalid (= judgment cannot be extracted).
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
--- pick a majority binary. Invalid chains are excluded from the
--- numerator; if every chain is invalid the result is invalid.
local function pure_aggregate_k(per_chain)
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
        correct = score >= 0.5,
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
                    "Override template (default: paper Figure 14 literal; override voids paper's correctness reports)"
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
                    "Ordered per-step verdicts ('correct' / 'incorrect')"
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
                    "'any_incorrect' (default; matches Figure 14 early-stop semantics) or 'all_correct'"
                ),
            }),
            result = T.shape({
                correct = T.boolean:describe("Solution-level binary verdict"),
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
                    "Override template (default: paper Figure 14 literal)"
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
                    "Number of independent verification chains to sample (default: 1; paper §4 experimental range 1 / 4 / 8 for K-CoT averaging)"
                ),
                prompt_template = T.string:is_optional():describe(
                    "Override verifier prompt template (default: paper Figure 14 literal; override voids paper's correctness reports)"
                ),
                temperature = T.number:is_optional():describe(
                    "LLM sampling temperature (default: 0.1; Khalifa 2025 §4 default)"
                ),
                max_thinking_tokens = T.number:is_optional():describe(
                    "Token cap per verifier chain (default: 4096; Khalifa 2025 §4 to avoid overthinking)"
                ),
                aggregation = T.string:is_optional():describe(
                    "Per-chain aggregation method (default: 'any_incorrect'; matches Figure 14 early-stop semantics. 'all_correct' requires every step verdict to be correct. The paper's canonical force-decode aggregation P(yes)/(P(yes)+P(no)) is out of scope — see Caveats)"
                ),
            }),
            result = T.shape({
                correct = T.boolean:describe(
                    "Solution-level majority verdict across K verification chains (score >= 0.5)"
                ),
                score = T.number:describe(
                    "Fraction of valid chains that judged the solution correct, in [0, 1] (paper §4 K-CoT averaging approximation; 0 when all chains invalid)"
                ),
                invalid = T.boolean:describe(
                    "True when every verification chain was invalid (no \\boxed tokens parsed)"
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
    local template = ctx.prompt_template or DEFAULT_PROMPT_TEMPLATE
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
    local template = ctx.prompt_template or DEFAULT_PROMPT_TEMPLATE
    local temperature = ctx.temperature or DEFAULT_TEMPERATURE
    local max_tokens = ctx.max_thinking_tokens or DEFAULT_MAX_THINKING_TOKENS

    local prompt = pure_build_prompt(problem, solution_steps, template)
    local chain = alc.llm(prompt, {
        system = "You are a careful math verifier. Follow the requested output format exactly.",
        max_tokens = max_tokens,
        temperature = temperature,
    })

    local parsed = pure_parse_verdicts(chain)
    ctx.result = {
        chain = chain,
        verdicts = parsed.verdicts,
        invalid = parsed.invalid,
    }
    return ctx
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local problem = ctx.problem or error("ctx.problem is required")
    local solution_steps = ctx.solution_steps or error("ctx.solution_steps is required")
    local n = ctx.n_parallel_cots or DEFAULT_N_PARALLEL_COTS
    local template = ctx.prompt_template or DEFAULT_PROMPT_TEMPLATE
    local temperature = ctx.temperature or DEFAULT_TEMPERATURE
    local max_tokens = ctx.max_thinking_tokens or DEFAULT_MAX_THINKING_TOKENS
    local aggregation = ctx.aggregation or DEFAULT_AGGREGATION

    if n < 1 then n = 1 end

    local prompt = pure_build_prompt(problem, solution_steps, template)
    local chains = {}

    for i = 1, n do
        local chain = alc.llm(prompt, {
            system = "You are a careful math verifier. Follow the requested output format exactly.",
            max_tokens = max_tokens,
            temperature = temperature,
        })
        local parsed = pure_parse_verdicts(chain)
        local per_chain = pure_aggregate_one(parsed.verdicts, aggregation)
        chains[i] = {
            chain = chain,
            verdicts = parsed.verdicts,
            correct = per_chain.correct,
            invalid = parsed.invalid or per_chain.invalid,
        }
        alc.log("info", string.format(
            "think_prm: chain %d/%d (valid=%s, correct=%s)",
            i, n, tostring(not chains[i].invalid), tostring(per_chain.correct)
        ))
    end

    local agg = pure_aggregate_k(chains)
    ctx.result = {
        correct = agg.correct,
        score = agg.score,
        invalid = agg.invalid,
        valid_chains = agg.valid_chains,
        chains = chains,
    }
    return ctx
end

-- Malli-style self-decoration (see alc_shapes/README). inline T.shape
-- for both input and result; wrapper validates in ALC_SHAPE_CHECK=1.
M.build_prompt = S.instrument(M, "build_prompt")
M.parse_verdicts = S.instrument(M, "parse_verdicts")
M.aggregate = S.instrument(M, "aggregate")
M.verify = S.instrument(M, "verify")
M.run = S.instrument(M, "run")

return M
