--- aot(AoT) — Atom of Thoughts: Markov test-time scaling via DAG contraction
---
--- Decomposes a question into an atomic-state DAG, contracts the
--- independent atoms into the dependent ones to produce a smaller
--- self-contained question, and iterates until depth budget is reached.
--- Each contracted question is answerable from its predecessor alone
--- (Markov property), so the reasoning trace does not need to retain
--- earlier history.
---
--- ## Usage
---
--- ```lua
--- local aot = require("aot")
--- return aot.run(ctx)
--- ```
---
--- ## Algorithm
---
--- 1. decompose: ask the LLM to split the question into subquestions
---    with a dependency annotation (DAG `{id, text, depend: [ids]}`).
--- 2. On the first iteration, set the depth budget D from the longest
---    path through the initial DAG (`get_max_path_length`).
--- 3. split_indep_dep: separate subquestions with no incoming edges
---    (independent atoms) from those with incoming edges (dependent).
--- 4. contract: ask the LLM to fold the independent atoms into the
---    dependent ones as known conditions, producing a new self-contained
---    question for the next iteration.
--- 5. Repeat steps 1-4 until the depth budget is exhausted.
--- 6. solve: ask the LLM to answer the final contracted question
---    directly. No aggregation across history.
---
--- ## Caveats
---
--- The contraction step depends critically on the quality of the
--- **first** DAG decomposition (paper §7 limitation). When the initial
--- decomposition fails to capture parallelism / independence the
--- contracted question can drift away from the original (Appendix C.1
--- "illusions"). The `consistency_check` knob enables an optional
--- per-iteration check that asks the LLM whether the contracted
--- question still serves the original; paper §4.3 introduces this as a
--- refinement outside Algorithm 1, off by default to match the base
--- algorithm.
---
--- The depth budget D is fixed on the first iteration from
--- `GetMaxPathLength(G_0)` (Algorithm 1 line 6) and never recomputed.
--- The `max_depth` knob caps D to prevent runaway when an LLM emits a
--- long pathological decomposition; setting it to nil reproduces paper
--- behaviour.
---
--- The paper's "AoT*" variant performs N independent runs and lets the
--- LLM pick the best answer (§5). The `final_aggregation_runs` knob
--- exposes this; default `1` corresponds to the base algorithm. Set to
--- `3` for the AoT* configuration described in the paper.
---
--- The decomposition LLM call returns a JSON object that this pkg
--- parses via `alc.json_decode` with a regex-based bracket fallback
--- (sibling pattern to dci). If the LLM emits an unparseable payload,
--- iteration aborts and the current question is solved directly.
---
--- ## References
---
--- - Teng, F., Yu, Z., Shi, Q., Zhang, J., Wu, C., Luo, Y. (2025).
---   "Atom of Thoughts for Markov LLM Test-Time Scaling". NeurIPS 2025
---   / arXiv:2502.12018. §3.3 Algorithm 1, §4 decomposition / contract,
---   §4.3 consistency_check refinement, §7 limitations.
---   https://arxiv.org/abs/2502.12018
--- - Official implementation: https://github.com/qixucen/atom

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "aot",
    version = "0.1.0",
    description = "Atom of Thoughts — Markov test-time scaling via DAG decompose + contract.",
    category = "reasoning",
    alc_shapes_compat = "^0.25",
}

-- (X) Implementation choice — paper relies on `GetMaxPathLength(G_0)`
-- for depth budget and does not cap it. nil reproduces paper behaviour;
-- a finite value protects against pathological decompositions.
local DEFAULT_MAX_DEPTH = nil

-- (L) Paper §4.3 introduces consistency_check as an optional refinement
-- outside Algorithm 1; off by default to match the base algorithm.
local DEFAULT_CONSISTENCY_CHECK = false

-- (L) Paper §5 AoT* variant uses N=3 runs with an LLM selector. Default
-- 1 corresponds to the base Algorithm 1 (single run, no selection).
local DEFAULT_FINAL_AGGREGATION_RUNS = 1

-- (X) Implementation choice — token caps for each LLM phase. Paper does
-- not pin token budgets; sized for typical decompositions / answers.
local DEFAULT_DECOMPOSE_TOKENS = 800
local DEFAULT_CONTRACT_TOKENS = 600
local DEFAULT_SOLVE_TOKENS = 500

-- Prompt templates derived from paper Appendix B.2 / B.3. Exposed as
-- defaults so callers can override; not literal verbatim from the
-- paper but faithful to its intent.
local DEFAULT_DECOMPOSE_TEMPLATE = [[
You will decompose a question into smaller subquestions arranged as a
directed acyclic graph (DAG). Each subquestion has an integer id, a
text, and a list of predecessor ids it depends on (depend = [] for an
independent subquestion).

A subquestion is independent (depend = []) when its information comes
directly from the original question. A subquestion is dependent when
its description requires answering one or more earlier subquestions.

Return ONLY valid JSON in the following shape:

{
  "subquestions": [
    {"id": 1, "text": "...", "depend": []},
    {"id": 2, "text": "...", "depend": [1]}
  ]
}

Original question:
%s
]]

local DEFAULT_CONTRACT_TEMPLATE = [[
You will compress a set of subquestions into one self-contained
question that can be answered without external context.

The independent subquestions below act as known conditions; treat
their content as established facts. The dependent subquestions
contain the remaining work that must be expressed in the new
question.

Independent subquestions (known conditions):
%s

Dependent subquestions (remaining work):
%s

Original question:
%s

Produce ONE new question that:
- absorbs the independent subquestions as known conditions
- carries the dependent subquestions as the new work to perform
- is solvable independently of the original question

Return only the new question text.
]]

local DEFAULT_SOLVE_TEMPLATE = [[
Answer the following question directly and concisely.

Question:
%s

Final answer:
]]

local DEFAULT_CONSISTENCY_TEMPLATE = [[
Original question:
%s

Proposed contracted question for the next iteration:
%s

Does answering the contracted question correctly imply a correct
answer to the original question? Reply with just "yes" or "no".
]]

---@type AlcSpec
M.spec = {
    entries = {
        decompose = {
            input = T.shape({
                question = T.string:describe("Question to decompose into a DAG of subquestions"),
                decompose_prompt_template = T.string:is_optional():describe(
                    "Override template (default uses paper Appendix B.2 wording; implementation choice — paper does not pin verbatim)"
                ),
                max_tokens = T.number:is_optional():describe(
                    "Token cap for the decompose LLM call (default: 800; implementation choice — paper does not specify)"
                ),
            }),
            result = T.shape({
                subquestions = T.array_of(T.shape({
                    id = T.number:describe("Stable subquestion identifier"),
                    text = T.string:describe("Subquestion text"),
                    depend = T.array_of(T.number):describe("Predecessor ids (empty for independent atoms)"),
                })):describe("Decomposed DAG nodes"),
                raw = T.string:describe("Raw LLM response (preserved for debugging when JSON parse succeeds or fails)"),
            }),
        },
        split_indep_dep = {
            input = T.shape({
                subquestions = T.array_of(T.shape({
                    id = T.number,
                    text = T.string,
                    depend = T.array_of(T.number),
                })):describe("DAG nodes produced by decompose"),
            }),
            result = T.shape({
                indep = T.array_of(T.shape({
                    id = T.number,
                    text = T.string,
                    depend = T.array_of(T.number),
                })):describe("Subquestions with no incoming edges (depend = [])"),
                dep = T.array_of(T.shape({
                    id = T.number,
                    text = T.string,
                    depend = T.array_of(T.number),
                })):describe("Subquestions with at least one incoming edge"),
            }),
        },
        get_max_path_length = {
            input = T.shape({
                subquestions = T.array_of(T.shape({
                    id = T.number,
                    text = T.string,
                    depend = T.array_of(T.number),
                })):describe("DAG nodes"),
            }),
            result = T.shape({
                max_path_length = T.number:describe(
                    "Longest path length through the DAG (counted in nodes; the depth budget D in Algorithm 1 line 6)"
                ),
            }),
        },
        contract = {
            input = T.shape({
                question = T.string:describe("Current question being contracted"),
                indep = T.array_of(T.shape({
                    id = T.number,
                    text = T.string,
                    depend = T.array_of(T.number),
                })):describe("Independent subquestions to fold in as known conditions"),
                dep = T.array_of(T.shape({
                    id = T.number,
                    text = T.string,
                    depend = T.array_of(T.number),
                })):describe("Dependent subquestions describing the remaining work"),
                contract_prompt_template = T.string:is_optional():describe(
                    "Override template (default derives from paper Appendix B.3; implementation choice — paper does not pin verbatim)"
                ),
                max_tokens = T.number:is_optional():describe(
                    "Token cap for the contract LLM call (default: 600; implementation choice)"
                ),
            }),
            result = T.shape({
                contracted_question = T.string:describe("New self-contained question for the next iteration"),
            }),
        },
        solve = {
            input = T.shape({
                question = T.string:describe("Final contracted question to answer directly"),
                solve_prompt_template = T.string:is_optional():describe(
                    "Override template (default: plain answer prompt; implementation choice)"
                ),
                max_tokens = T.number:is_optional():describe(
                    "Token cap for the solve LLM call (default: 500; implementation choice)"
                ),
            }),
            result = T.shape({
                answer = T.string:describe("Direct answer to the contracted question"),
            }),
        },
        run = {
            input = T.shape({
                task = T.string:describe("Original question to solve"),
                max_depth = T.number:is_optional():describe(
                    "Hard cap on the depth budget D (default: nil = paper behaviour, no cap; implementation choice — runaway protection)"
                ),
                consistency_check = T.boolean:is_optional():describe(
                    "Enable the §4.3 optional refinement that verifies contraction quality each iteration (default: false; paper §4.3 introduces this outside Algorithm 1)"
                ),
                final_aggregation_runs = T.number:is_optional():describe(
                    "Number of independent runs whose answers are pooled by an LLM selector — paper §5 AoT* variant (default: 1 = base algorithm, set to 3 for AoT*)"
                ),
                decompose_prompt_template = T.string:is_optional():describe(
                    "Override template for the decompose phase (default derives from paper Appendix B.2)"
                ),
                contract_prompt_template = T.string:is_optional():describe(
                    "Override template for the contract phase (default derives from paper Appendix B.3)"
                ),
                solve_prompt_template = T.string:is_optional():describe(
                    "Override template for the solve phase (default: plain answer prompt)"
                ),
                decompose_tokens = T.number:is_optional():describe(
                    "Token cap for each decompose LLM call (default: 800)"
                ),
                contract_tokens = T.number:is_optional():describe(
                    "Token cap for each contract LLM call (default: 600)"
                ),
                solve_tokens = T.number:is_optional():describe(
                    "Token cap for the final solve LLM call (default: 500)"
                ),
            }),
            result = T.shape({
                final_answer = T.string:describe("Direct answer to the final contracted question"),
                depth_used = T.number:describe("Number of contraction iterations actually executed"),
                initial_depth_budget = T.number:describe(
                    "Depth D fixed on the first iteration from GetMaxPathLength(G_0), before max_depth cap"
                ),
                final_question = T.string:describe("Final contracted question that solve was applied to"),
            }),
        },
    },
}

-- ---- pure helpers ----

--- Parse the decompose LLM response into a list of `{id, text, depend}`
--- subquestions. Returns the parsed list and the original raw string.
--- Robust against minor LLM JSON noise: first tries `alc.json_decode`
--- on the full body, then falls back to slicing the first balanced
--- `{...}` region and decoding that.
local function parse_subquestions(raw)
    local payload
    if type(alc) == "table" and type(alc.json_decode) == "function" then
        local ok, parsed = pcall(alc.json_decode, raw)
        if ok and type(parsed) == "table" then
            payload = parsed
        else
            -- Bracket fallback: find first balanced { ... } region.
            local first = raw:find("{", 1, true)
            local last = raw:find("}[^}]*$")
            if first and last and last > first then
                local fragment = raw:sub(first, last)
                local ok2, parsed2 = pcall(alc.json_decode, fragment)
                if ok2 and type(parsed2) == "table" then
                    payload = parsed2
                end
            end
        end
    end

    if type(payload) ~= "table" then
        return {}, raw
    end

    local list = payload.subquestions
    if type(list) ~= "table" then
        return {}, raw
    end

    local out = {}
    for i, sq in ipairs(list) do
        if type(sq) == "table" and type(sq.id) == "number" and type(sq.text) == "string" then
            local depend = {}
            if type(sq.depend) == "table" then
                for _, d in ipairs(sq.depend) do
                    if type(d) == "number" then
                        depend[#depend + 1] = d
                    end
                end
            end
            out[#out + 1] = { id = sq.id, text = sq.text, depend = depend }
        end
    end
    return out, raw
end

--- Pure split: subquestions with empty depend → indep, else dep.
local function pure_split_indep_dep(subquestions)
    local indep, dep = {}, {}
    for _, sq in ipairs(subquestions or {}) do
        if type(sq.depend) ~= "table" or #sq.depend == 0 then
            indep[#indep + 1] = sq
        else
            dep[#dep + 1] = sq
        end
    end
    return indep, dep
end

--- Pure longest-path length through the DAG (counted in nodes).
--- Memoized DFS over predecessor edges. Returns 0 for an empty list.
local function pure_max_path_length(subquestions)
    if not subquestions or #subquestions == 0 then return 0 end
    local id_to_idx = {}
    for i, sq in ipairs(subquestions) do
        id_to_idx[sq.id] = i
    end
    local memo = {}
    local function depth(i)
        if memo[i] then return memo[i] end
        local max_pred = 0
        local sq = subquestions[i]
        if type(sq.depend) == "table" then
            for _, dep_id in ipairs(sq.depend) do
                local pred_idx = id_to_idx[dep_id]
                if pred_idx then
                    local d = depth(pred_idx)
                    if d > max_pred then max_pred = d end
                end
            end
        end
        memo[i] = 1 + max_pred
        return memo[i]
    end
    local max_d = 0
    for i = 1, #subquestions do
        local d = depth(i)
        if d > max_d then max_d = d end
    end
    return max_d
end

local function format_subquestions(subs)
    if not subs or #subs == 0 then return "(none)" end
    local parts = {}
    for _, sq in ipairs(subs) do
        parts[#parts + 1] = string.format("- [id=%d] %s", sq.id, sq.text)
    end
    return table.concat(parts, "\n")
end

-- ---- entries ----

---@param ctx AlcCtx
---@return AlcCtx
function M.decompose(ctx)
    local question = ctx.question or error("ctx.question is required")
    local template = ctx.decompose_prompt_template or DEFAULT_DECOMPOSE_TEMPLATE
    local max_tokens = ctx.max_tokens or DEFAULT_DECOMPOSE_TOKENS

    local raw = alc.llm(
        string.format(template, question),
        {
            system = "You are a problem decomposer. Output strictly valid JSON; do not add prose around it.",
            max_tokens = max_tokens,
        }
    )

    local subquestions, _ = parse_subquestions(raw)
    ctx.result = { subquestions = subquestions, raw = raw }
    return ctx
end

---@param ctx AlcCtx
---@return AlcCtx
function M.split_indep_dep(ctx)
    local subquestions = ctx.subquestions or error("ctx.subquestions is required")
    local indep, dep = pure_split_indep_dep(subquestions)
    ctx.result = { indep = indep, dep = dep }
    return ctx
end

---@param ctx AlcCtx
---@return AlcCtx
function M.get_max_path_length(ctx)
    local subquestions = ctx.subquestions or error("ctx.subquestions is required")
    ctx.result = { max_path_length = pure_max_path_length(subquestions) }
    return ctx
end

---@param ctx AlcCtx
---@return AlcCtx
function M.contract(ctx)
    local question = ctx.question or error("ctx.question is required")
    local indep = ctx.indep or error("ctx.indep is required")
    local dep = ctx.dep or error("ctx.dep is required")
    local template = ctx.contract_prompt_template or DEFAULT_CONTRACT_TEMPLATE
    local max_tokens = ctx.max_tokens or DEFAULT_CONTRACT_TOKENS

    local contracted_question = alc.llm(
        string.format(
            template,
            format_subquestions(indep),
            format_subquestions(dep),
            question
        ),
        {
            system = "You are compressing subquestions into one self-contained question. "
                .. "Output only the new question text, no preamble.",
            max_tokens = max_tokens,
        }
    )

    ctx.result = { contracted_question = contracted_question }
    return ctx
end

---@param ctx AlcCtx
---@return AlcCtx
function M.solve(ctx)
    local question = ctx.question or error("ctx.question is required")
    local template = ctx.solve_prompt_template or DEFAULT_SOLVE_TEMPLATE
    local max_tokens = ctx.max_tokens or DEFAULT_SOLVE_TOKENS

    local answer = alc.llm(
        string.format(template, question),
        {
            system = "You are a careful answerer. Produce a direct, concise final answer.",
            max_tokens = max_tokens,
        }
    )
    ctx.result = { answer = answer }
    return ctx
end

local function single_run(task, opts)
    local current_question = task
    local depth_budget = nil
    local initial_depth_budget = 0
    local depth_used = 0

    -- Main contraction loop — Algorithm 1 lines 2-12.
    while depth_budget == nil or depth_used < depth_budget do
        -- decomposeLLM
        local raw = alc.llm(
            string.format(opts.decompose_template, current_question),
            {
                system = "You are a problem decomposer. Output strictly valid JSON; do not add prose around it.",
                max_tokens = opts.decompose_tokens,
            }
        )
        local subquestions = parse_subquestions(raw)

        if #subquestions == 0 then
            -- Unparseable / empty decomposition → abort the loop and
            -- solve the current question directly (graceful degradation).
            alc.log("warn", "aot: empty / unparseable decomposition, terminating loop")
            break
        end

        -- Fix depth budget on first iteration only.
        if depth_budget == nil then
            initial_depth_budget = pure_max_path_length(subquestions)
            depth_budget = initial_depth_budget
            if opts.max_depth and opts.max_depth < depth_budget then
                depth_budget = opts.max_depth
            end
            alc.log("info", string.format(
                "aot: initial depth budget D=%d (capped to %d)",
                initial_depth_budget, depth_budget
            ))
            if depth_budget <= 0 then
                break
            end
        end

        local indep, dep = pure_split_indep_dep(subquestions)
        if #dep == 0 then
            -- All atoms independent → no contraction left to do.
            alc.log("info", "aot: all subquestions independent, terminating loop")
            break
        end

        -- contractLLM
        local contracted = alc.llm(
            string.format(
                opts.contract_template,
                format_subquestions(indep),
                format_subquestions(dep),
                current_question
            ),
            {
                system = "You are compressing subquestions into one self-contained question. "
                    .. "Output only the new question text, no preamble.",
                max_tokens = opts.contract_tokens,
            }
        )

        if opts.consistency_check then
            local verdict = alc.llm(
                string.format(DEFAULT_CONSISTENCY_TEMPLATE, task, contracted),
                {
                    system = "You verify equivalence between an original question and a contracted version.",
                    max_tokens = 16,
                }
            )
            if not verdict:lower():find("yes", 1, true) then
                alc.log("warn", "aot: consistency_check rejected contraction, terminating loop")
                break
            end
        end

        current_question = contracted
        depth_used = depth_used + 1
    end

    -- solveLLM on the final contracted question
    local answer = alc.llm(
        string.format(opts.solve_template, current_question),
        {
            system = "You are a careful answerer. Produce a direct, concise final answer.",
            max_tokens = opts.solve_tokens,
        }
    )

    return {
        final_answer = answer,
        depth_used = depth_used,
        initial_depth_budget = initial_depth_budget,
        final_question = current_question,
    }
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")

    local opts = {
        max_depth = ctx.max_depth or DEFAULT_MAX_DEPTH,
        consistency_check = ctx.consistency_check ~= nil and ctx.consistency_check or DEFAULT_CONSISTENCY_CHECK,
        decompose_template = ctx.decompose_prompt_template or DEFAULT_DECOMPOSE_TEMPLATE,
        contract_template = ctx.contract_prompt_template or DEFAULT_CONTRACT_TEMPLATE,
        solve_template = ctx.solve_prompt_template or DEFAULT_SOLVE_TEMPLATE,
        decompose_tokens = ctx.decompose_tokens or DEFAULT_DECOMPOSE_TOKENS,
        contract_tokens = ctx.contract_tokens or DEFAULT_CONTRACT_TOKENS,
        solve_tokens = ctx.solve_tokens or DEFAULT_SOLVE_TOKENS,
    }

    local runs = ctx.final_aggregation_runs or DEFAULT_FINAL_AGGREGATION_RUNS
    if runs <= 1 then
        ctx.result = single_run(task, opts)
        return ctx
    end

    -- AoT* variant — N independent runs, LLM picks the best answer
    -- (paper §5). Implementation choice: the selector prompt pools all
    -- N answers as numbered candidates.
    local results = {}
    for i = 1, runs do
        results[i] = single_run(task, opts)
        alc.log("info", string.format("aot: AoT* run %d/%d", i, runs))
    end

    local candidates_str = ""
    for i, r in ipairs(results) do
        candidates_str = candidates_str
            .. string.format("Candidate %d:\n%s\n\n", i, r.final_answer)
    end

    local selected_idx_raw = alc.llm(
        string.format(
            "Original question:\n%s\n\n%s"
                .. "Select the best candidate. Reply with just the candidate number "
                .. "(1 to %d).",
            task, candidates_str, runs
        ),
        {
            system = "You are a careful answer selector. Reply only with a digit.",
            max_tokens = 8,
        }
    )

    local idx = tonumber((selected_idx_raw or ""):match("(%d+)")) or 1
    if idx < 1 or idx > runs then
        idx = 1
    end
    local chosen = results[idx]
    chosen.final_answer = chosen.final_answer  -- pass through
    ctx.result = chosen
    return ctx
end

-- Malli-style self-decoration (see alc_shapes/README). inline T.shape
-- for both input and result; wrapper validates in ALC_SHAPE_CHECK=1.
M.decompose = S.instrument(M, "decompose")
M.split_indep_dep = S.instrument(M, "split_indep_dep")
M.get_max_path_length = S.instrument(M, "get_max_path_length")
M.contract = S.instrument(M, "contract")
M.solve = S.instrument(M, "solve")
M.run = S.instrument(M, "run")

return M
