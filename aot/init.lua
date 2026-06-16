--- aot(AoT) — Atom of Thoughts: Markov test-time scaling via DAG contraction
---
--- Decomposes a question into an atomic-state DAG, contracts the
--- independent atoms into the dependent ones to produce a smaller
--- self-contained question, and iterates until the depth budget is
--- exhausted. Each contracted question is answerable from its
--- predecessor alone (Markov property), so the reasoning trace does
--- not need to retain earlier history.
---
--- ## Algorithm (paper §3.3, Algorithm 1 verbatim)
---
--- ```
--- Input:  Initial question Q_0
--- Output: Final answer A
---
---  1: i ← 0
---  2: D ← None
---  3: while i < D or D is None do
---  4:   G_i ← decomposeLLM(Q_i)               -- DAG decomposition
---  5:   if D is None then
---  6:     D ← GetMaxPathLength(G_i)           -- depth fixed at i=0 only
---  7:   end if
---  8:   Q_ind ← { Q_i ∈ Q | ∄ Q_j ∈ Q, (Q_j, Q_i) ∈ E }  -- indep atoms
---  9:   Q_dep ← { Q_i ∈ Q | ∃ Q_j ∈ Q, (Q_j, Q_i) ∈ E }  -- dependent
--- 10:   Q_{i+1} ← contractLLM(Q_ind, Q_dep)   -- SINGLE LLM call
--- 11:   i ← i + 1
--- 12: end while
--- 13: A ← solveLLM(Q_D)                       -- direct solve, no aggregation
--- 14: return A
--- ```
---
--- ## Phase order
---
--- 1. `decompose` — DAG decomposition (line 4). Returns subquestions
---    with `{id, text, depend}` and a `parse_ok` flag distinguishing
---    successful parses from silent empty returns.
--- 2. `get_max_path_length` — pure DAG longest-path (line 6, first
---    iteration only). Counted in nodes (paper does not specify
---    nodes-vs-edges; nodes follows the §3.3 + Appendix A "solution
---    depths" tabulation).
--- 3. `split_indep_dep` — pure partition (lines 8-9).
--- 4. `contract` — single LLM call that folds Q_ind into Q_dep as
---    known conditions (line 10, Appendix B.3 prompt literal).
--- 5. `solve` — direct answer (line 13). No history aggregation.
---
--- `M.run` uses **nested dispatch** (calls `M.decompose` /
--- `M.split_indep_dep` / `M.get_max_path_length` / `M.contract` /
--- `M.solve` through the `M` table, not internal closures) so the
--- `S.instrument` wrappers fire on every sub-call. This catches a bad
--- intermediate shape before it leaks into the outer result
--- (`alc_shapes/README` §Producer usage "Nested dispatch").
---
--- ## Implementation choices (paper does not prescribe; spelled out)
---
--- Every default below records its source explicitly in its inline
--- comment: paper-literal citations with section refs, industry-
--- standard heuristics with source links, or implementation-choice
--- rationale spelled out. No default is implicit.
---
---  - `max_depth` = nil — Paper Algorithm 1 line 6 fixes D
---    from `GetMaxPathLength(G_0)` with no upper cap. nil reproduces
---    paper behaviour; a finite value protects against runaway when
---    an LLM emits a pathologically long decomposition.
---  - `consistency_check` = false — Paper §4.3 introduces
---    consistency_check as an optional refinement outside Algorithm 1;
---    off by default to match the base algorithm. Caveat — the
---    paper §4.3 literal is "synthesized answer / Q_{i+1} result
---    consistency", i.e. checks whether the cumulative answer is
---    consistent with the next iteration's result. This pkg uses a
---    text-level equivalence proxy ("does answering the contracted
---    question imply a correct answer to the original?") which is
---    cheaper at prompt level but evaluates a slightly different
---    property; treat as an early-detection heuristic, not a literal
---    paper §4.3 reproduction.
---  - `final_aggregation_runs` = 1 — Paper §5 AoT* variant
---    runs N=3 independent runs and asks an LLM selector to pick the
---    best answer. Default 1 corresponds to base Algorithm 1; set 3
---    for the paper's AoT* configuration.
---  - `decompose_prompt_template` / `contract_prompt_template` /
---    `solve_prompt_template` — Paper Appendix B.2 / B.3 give
---    the template *intent* but no single verbatim string is fully
---    transcribed in the paper body; the defaults below are written
---    to capture the paper's instructions (JSON DAG output / known-
---    conditions framing / direct answer) without being literal
---    paper text. Callers requiring paper-exact prompts should grab
---    the official Appendix wording and pass it via override.
---  - `decompose_tokens` = 800 / `contract_tokens` = 600 /
---    `solve_tokens` = 500 — Per-call generation caps. Paper
---    does not specify (paper runs typical default OpenAI settings).
---    Sized to fit typical JSON DAGs / contracted questions / direct
---    answers; callers should override for verbose domains.
---  - `consistency_tokens` = 16 — Consistency-check answer is
---    a single yes/no word, 16 tokens is generous.
---  - `selector_tokens` = 8 — AoT* selector returns a single
---    digit (1..N). 8 tokens is generous.
---  - `consistency_yes_token` = "yes" — Plain-text token
---    that consistency_check uses to decide "keep iterating". Lower-
---    cased substring match. Override if domain language differs.
---  - sys prompts (`decompose_system_prompt`, `contract_system_prompt`,
---    `solve_system_prompt`, `consistency_system_prompt`,
---    `selector_system_prompt`) — All five system prompts are
---    impl-authored persona conditioning text. Unlike s1 (which
---    unifies sys across phases for the single-pass paper Qwen
---    persona invariant), AoT's paper *does* separate
---    decompose / contract / solve as distinct LLM calls (Algorithm 1
---    lines 4, 10, 13), so per-phase persona conditioning here matches
---    the paper's per-phase LLM call structure. The literal wording is
---    impl choice; callers needing a different persona should fork the
---    call_* helpers.
---
--- ## Caveats
---
--- The contraction step depends critically on the quality of the
--- **first** DAG decomposition (paper §7 limitation). When the initial
--- decomposition fails to capture parallelism / independence the
--- contracted question can drift away from the original (Appendix C.1
--- "illusions"). Enable `consistency_check = true` to add a per-
--- iteration text-level proxy check.
---
--- The depth budget D is fixed on the first iteration from
--- `GetMaxPathLength(G_0)` (Algorithm 1 line 6) and never recomputed.
--- `max_depth` caps D to prevent runaway; setting nil reproduces paper
--- behaviour.
---
--- The decomposition LLM call returns a JSON object that this pkg
--- parses via `alc.json_decode` with a regex-based bracket fallback.
--- When parsing fails the loop terminates gracefully and the current
--- question is solved directly; `decompose.result.parse_ok` makes the
--- distinction explicit so callers can distinguish "no subquestions
--- needed" from "LLM returned unparseable text".
---
--- ## References
---
--- - Teng, F., Yu, Z., Shi, Q., Zhang, J., Wu, C., Luo, Y. (2025).
---   "Atom of Thoughts for Markov LLM Test-Time Scaling". NeurIPS 2025
---   / arXiv:2502.12018. §3.3 Algorithm 1, §4 decomposition / contract,
---   §4.3 consistency_check refinement, §5 AoT*, §7 limitations,
---   Appendix B.2 / B.3 prompt templates.
---   https://arxiv.org/abs/2502.12018
--- - Official implementation: https://github.com/qixucen/atom

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "aot",
    version = "0.2.0",
    description = "Atom of Thoughts — Markov test-time scaling via DAG decompose + contract (Teng 2025 §3.3 Algorithm 1).",
    category = "reasoning",
    alc_shapes_compat = "^0.25",
}

-- ---- Default values ----
-- (L) paper literal, (I) industry standard, (X) impl choice. Every
-- default has an inline tag + rationale; readers should be able to
-- verify each value against the paper or the cited source. No
-- implicit defaults — magic numbers and magic strings are promoted
-- to named constants below.

-- (X) Paper §3.3 line 6 fixes D from GetMaxPathLength(G_0) with no
-- upper cap. nil reproduces paper behaviour; finite caps protect
-- against pathological decompositions.
local DEFAULT_MAX_DEPTH = nil

-- (L) Paper §4.3 introduces consistency_check as an optional
-- refinement outside Algorithm 1; off by default to match the base
-- algorithm.
local DEFAULT_CONSISTENCY_CHECK = false

-- (L) Paper §5 AoT* variant uses N=3 independent runs with an LLM
-- selector. Default 1 = base Algorithm 1 (single run, no selection).
local DEFAULT_FINAL_AGGREGATION_RUNS = 1

-- (X) Token caps for each phase. Paper does not pin per-call budgets
-- (paper runs default OpenAI settings). Sized for typical JSON DAGs
-- / contracted questions / direct answers; callers should override
-- for verbose / long-answer domains.
local DEFAULT_DECOMPOSE_TOKENS = 800
local DEFAULT_CONTRACT_TOKENS = 600
local DEFAULT_SOLVE_TOKENS = 500

-- (X) Consistency-check verdict is a single yes/no word, 16 tokens
-- is generous. Used only when consistency_check = true.
local DEFAULT_CONSISTENCY_TOKENS = 16

-- (X) AoT* selector reply is a single digit (1..N). 8 tokens is
-- generous. Used only when final_aggregation_runs > 1.
local DEFAULT_SELECTOR_TOKENS = 8

-- (X) Plain-text token that consistency_check looks for to decide
-- "keep iterating". Lower-cased substring match. Callers in non-
-- English domains should override via ctx.consistency_yes_token.
local DEFAULT_CONSISTENCY_YES_TOKEN = "yes"

-- (X) Decompose prompt template — captures paper §4.1 / Appendix B.2
-- intent (DAG with depend annotation, JSON output). Not literal
-- paper text; the paper does not transcribe a single verbatim
-- template in the body. Override for paper-exact prompts.
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

-- (X) Contract prompt template — captures paper §4.2 / Appendix B.3
-- intent ("integrate independent subquestions as known conditions
-- and incorporate descriptions of dependent subquestions"). Not
-- literal paper text.
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

-- (X) Solve prompt template — paper §3.3 line 13 invokes
-- solveLLM(Q_D) but does not pin the prompt wording. Plain
-- answer-extraction prompt.
local DEFAULT_SOLVE_TEMPLATE = [[
Answer the following question directly and concisely.

Question:
%s

Final answer:
]]

-- (X) Consistency-check template for the §4.3 optional refinement.
-- Paper §4.3 literal evaluates "synthesized answer / Q_{i+1} result
-- consistency"; this impl uses a text-level equivalence proxy as a
-- cheaper prompt-level approximation. See the docstring
-- "Implementation choices" section for the rationale.
local DEFAULT_CONSISTENCY_TEMPLATE = [[
Original question:
%s

Proposed contracted question for the next iteration:
%s

Does answering the contracted question correctly imply a correct
answer to the original question? Reply with just "yes" or "no".
]]

-- (X) AoT* selector prompt — paper §5 says "LLM to select the
-- optimal answer from three runs" but does not pin a verbatim
-- selector prompt. Plain candidate-pool template.
local SELECTOR_PROMPT_FORMAT =
    "Original question:\n%s\n\n%s"
    .. "Select the best candidate. Reply with just the candidate number "
    .. "(1 to %d)."

-- (X) Per-phase system prompts. AoT's paper §3.3 separates decompose
-- / contract / solve as distinct LLM calls (lines 4, 10, 13), so
-- per-phase persona conditioning here matches the paper's per-phase
-- LLM call structure (contrast with s1 which unifies sys across phases
-- for the paper's single-pass invariant). Literal wording is impl choice.
local DECOMPOSE_SYSTEM_PROMPT =
    "You are a problem decomposer. Output strictly valid JSON; do not add prose around it."
local CONTRACT_SYSTEM_PROMPT =
    "You are compressing subquestions into one self-contained question. "
    .. "Output only the new question text, no preamble."
local SOLVE_SYSTEM_PROMPT =
    "You are a careful answerer. Produce a direct, concise final answer."
local CONSISTENCY_SYSTEM_PROMPT =
    "You verify equivalence between an original question and a contracted version."
local SELECTOR_SYSTEM_PROMPT =
    "You are a careful answer selector. Reply only with a digit."

-- ---- pure helpers ----

--- Parse the decompose LLM response into a list of `{id, text, depend}`
--- subquestions. Returns the parsed list, the original raw string, and
--- a parse_ok boolean (false when JSON decode / shape extraction
--- failed). The boolean makes silent failure visible to callers; the
--- previous version returned an empty list both for "no subquestions
--- needed" and "LLM emitted garbage", which a caller could not tell
--- apart.
---
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
        return {}, raw, false
    end

    local list = payload.subquestions
    if type(list) ~= "table" then
        return {}, raw, false
    end

    local out = {}
    for _, sq in ipairs(list) do
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
    return out, raw, true
end

--- Pure split: subquestions with empty depend → indep, else dep.
--- Implements paper §3.3 lines 8-9 (Q_ind / Q_dep partition by
--- incoming edges).
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
--- Node-count vs edge-count: paper §3.3 line 6 refers to
--- `GetMaxPathLength(G_i)` without spelling out the metric; nodes is
--- consistent with the Appendix A "solution depths" tabulation.
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

---@type AlcSpec
M.spec = {
    entries = {
        decompose = {
            input = T.shape({
                question = T.string:describe("Question to decompose into a DAG of subquestions"),
                decompose_prompt_template = T.string:is_optional():describe(
                    "Override template (default captures paper Appendix B.2 intent; implementation choice — paper does not transcribe a verbatim template in-body)"
                ),
                max_tokens = T.number:is_optional():describe(
                    "Token cap for the decompose LLM call (default: 800; implementation choice — paper does not specify a per-call cap)"
                ),
            }),
            result = T.shape({
                subquestions = T.array_of(T.shape({
                    id = T.number:describe("Stable subquestion identifier"),
                    text = T.string:describe("Subquestion text"),
                    depend = T.array_of(T.number):describe("Predecessor ids (empty for independent atoms)"),
                })):describe("Decomposed DAG nodes (empty when parse failed; consult parse_ok to distinguish)"),
                raw = T.string:describe("Raw LLM response (preserved for debugging)"),
                parse_ok = T.boolean:describe(
                    "True when JSON decode + subquestions shape extraction succeeded; false when the LLM returned unparseable text. Makes silent failure visible (run loop terminates gracefully on parse_ok=false)."
                ),
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
                })):describe("Subquestions with no incoming edges (depend = []); paper §3.3 line 8 Q_ind"),
                dep = T.array_of(T.shape({
                    id = T.number,
                    text = T.string,
                    depend = T.array_of(T.number),
                })):describe("Subquestions with at least one incoming edge; paper §3.3 line 9 Q_dep"),
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
                    "Longest path length through the DAG (counted in nodes; the depth budget D in Algorithm 1 line 6). Node-count vs edge-count: paper §3.3 leaves the metric unspecified; nodes follows the Appendix A 'solution depths' tabulation."
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
                    "Override template (default captures paper Appendix B.3 intent; implementation choice — paper does not transcribe verbatim)"
                ),
                max_tokens = T.number:is_optional():describe(
                    "Token cap for the contract LLM call (default: 600; implementation choice)"
                ),
            }),
            result = T.shape({
                contracted_question = T.string:describe(
                    "New self-contained question for the next iteration (paper §3.3 line 10 Q_{i+1} = contractLLM(Q_ind, Q_dep), a SINGLE LLM call)"
                ),
            }),
        },
        solve = {
            input = T.shape({
                question = T.string:describe("Final contracted question to answer directly"),
                solve_prompt_template = T.string:is_optional():describe(
                    "Override template (default: plain answer prompt; implementation choice — paper §3.3 line 13 solveLLM does not pin a prompt)"
                ),
                max_tokens = T.number:is_optional():describe(
                    "Token cap for the solve LLM call (default: 500; implementation choice)"
                ),
            }),
            result = T.shape({
                answer = T.string:describe("Direct answer (paper §3.3 line 13 solveLLM(Q_D), no aggregation)"),
            }),
        },
        run = {
            input = T.shape({
                task = T.string:describe("Original question to solve (paper §3.3 input Q_0)"),
                max_depth = T.number:is_optional():describe(
                    "Hard cap on depth budget D (default: nil = paper behaviour, no cap; implementation choice — runaway protection for pathological decompositions)"
                ),
                consistency_check = T.boolean:is_optional():describe(
                    "Enable §4.3 optional refinement (default: false; paper §4.3 introduces this outside Algorithm 1). The paper §4.3 literal evaluates 'synthesized answer / Q_{i+1} result consistency'; this impl uses a text-level equivalence proxy ('does answering the contracted question imply a correct answer to the original?') as a cheaper prompt-level approximation."
                ),
                consistency_yes_token = T.string:is_optional():describe(
                    'Plain-text token consistency_check looks for to keep iterating (default: "yes"; implementation choice — lower-cased substring match)'
                ),
                final_aggregation_runs = T.number:is_optional():describe(
                    "Independent runs whose answers are pooled by an LLM selector (default: 1 = base Algorithm 1; paper §5 AoT* variant uses N=3, set 3 to reproduce)"
                ),
                decompose_prompt_template = T.string:is_optional():describe(
                    "Override template for the decompose phase (default captures paper Appendix B.2 intent; implementation choice)"
                ),
                contract_prompt_template = T.string:is_optional():describe(
                    "Override template for the contract phase (default captures paper Appendix B.3 intent; implementation choice)"
                ),
                solve_prompt_template = T.string:is_optional():describe(
                    "Override template for the solve phase (default: plain answer prompt; implementation choice)"
                ),
                decompose_tokens = T.number:is_optional():describe(
                    "Token cap for each decompose LLM call (default: 800; implementation choice)"
                ),
                contract_tokens = T.number:is_optional():describe(
                    "Token cap for each contract LLM call (default: 600; implementation choice)"
                ),
                solve_tokens = T.number:is_optional():describe(
                    "Token cap for the final solve LLM call (default: 500; implementation choice)"
                ),
                consistency_tokens = T.number:is_optional():describe(
                    "Token cap for the consistency_check LLM call (default: 16;— verdict is a single yes/no word)"
                ),
                selector_tokens = T.number:is_optional():describe(
                    "Token cap for the AoT* selector LLM call (default: 8;— reply is a single digit)"
                ),
            }),
            result = T.shape({
                final_answer = T.string:describe("Direct answer to the final contracted question (paper §3.3 line 13)"),
                depth_used = T.number:describe(
                    "Number of contraction iterations actually executed. Ranges over [0, depth_budget]; equals depth_budget when the loop completes the full D iterations, < depth_budget when an early termination fires (parse failure / all-independent / consistency rejection)."
                ),
                initial_depth_budget = T.number:describe(
                    "Depth D fixed on the first iteration from GetMaxPathLength(G_0), before max_depth cap (paper §3.3 line 6)"
                ),
                final_question = T.string:describe("Final contracted question that solve was applied to"),
            }),
        },
    },
}

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
            system = DECOMPOSE_SYSTEM_PROMPT,
            max_tokens = max_tokens,
        }
    )

    local subquestions, raw_back, parse_ok = parse_subquestions(raw)
    ctx.result = { subquestions = subquestions, raw = raw_back, parse_ok = parse_ok }
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
            system = CONTRACT_SYSTEM_PROMPT,
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
            system = SOLVE_SYSTEM_PROMPT,
            max_tokens = max_tokens,
        }
    )
    ctx.result = { answer = answer }
    return ctx
end

--- Run Algorithm 1 once: decompose → split → contract loop → solve.
--- Uses nested dispatch via M.<entry> so each sub-call fires its own
--- S.instrument shape check (see docstring "Phase order").
local function single_run(task, opts)
    local current_question = task
    local depth_budget = nil
    local initial_depth_budget = 0
    local depth_used = 0

    -- Main contraction loop — Algorithm 1 lines 3-12.
    while depth_budget == nil or depth_used < depth_budget do
        -- Line 4: decompose via nested dispatch (M.decompose).
        local sub = M.decompose({
            question = current_question,
            decompose_prompt_template = opts.decompose_template,
            max_tokens = opts.decompose_tokens,
        })
        local subquestions = sub.result.subquestions
        local parse_ok = sub.result.parse_ok

        if (not parse_ok) or #subquestions == 0 then
            alc.log("warn", "aot: empty / unparseable decomposition, terminating loop")
            break
        end

        -- Lines 5-7: fix depth budget on first iteration only.
        if depth_budget == nil then
            local mp = M.get_max_path_length({ subquestions = subquestions })
            initial_depth_budget = mp.result.max_path_length
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

        -- Lines 8-9: split via nested dispatch (M.split_indep_dep).
        local sp = M.split_indep_dep({ subquestions = subquestions })
        local indep = sp.result.indep
        local dep = sp.result.dep

        if #dep == 0 then
            -- (X) All atoms independent → no contraction left; this
            -- is impl-side graceful termination, not from Algorithm 1
            -- literal (paper assumes well-decomposed DAGs).
            alc.log("info", "aot: all subquestions independent, terminating loop")
            break
        end

        -- Line 10: contract via nested dispatch (M.contract).
        local con = M.contract({
            question = current_question,
            indep = indep,
            dep = dep,
            contract_prompt_template = opts.contract_template,
            max_tokens = opts.contract_tokens,
        })
        local contracted = con.result.contracted_question

        if opts.consistency_check then
            -- §4.3 optional refinement. Inline LLM call (no dedicated
            -- entry — this is a refinement outside Algorithm 1).
            local verdict = alc.llm(
                string.format(DEFAULT_CONSISTENCY_TEMPLATE, task, contracted),
                {
                    system = CONSISTENCY_SYSTEM_PROMPT,
                    max_tokens = opts.consistency_tokens,
                }
            )
            if not verdict:lower():find(opts.consistency_yes_token, 1, true) then
                alc.log("warn", "aot: consistency_check rejected contraction, terminating loop")
                break
            end
        end

        current_question = contracted
        depth_used = depth_used + 1
    end

    -- Line 13: solve via nested dispatch (M.solve).
    local sv = M.solve({
        question = current_question,
        solve_prompt_template = opts.solve_template,
        max_tokens = opts.solve_tokens,
    })

    return {
        final_answer = sv.result.answer,
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
        consistency_yes_token = ctx.consistency_yes_token or DEFAULT_CONSISTENCY_YES_TOKEN,
        decompose_template = ctx.decompose_prompt_template or DEFAULT_DECOMPOSE_TEMPLATE,
        contract_template = ctx.contract_prompt_template or DEFAULT_CONTRACT_TEMPLATE,
        solve_template = ctx.solve_prompt_template or DEFAULT_SOLVE_TEMPLATE,
        decompose_tokens = ctx.decompose_tokens or DEFAULT_DECOMPOSE_TOKENS,
        contract_tokens = ctx.contract_tokens or DEFAULT_CONTRACT_TOKENS,
        solve_tokens = ctx.solve_tokens or DEFAULT_SOLVE_TOKENS,
        consistency_tokens = ctx.consistency_tokens or DEFAULT_CONSISTENCY_TOKENS,
    }

    local runs = ctx.final_aggregation_runs or DEFAULT_FINAL_AGGREGATION_RUNS
    if runs <= 1 then
        ctx.result = single_run(task, opts)
        return ctx
    end

    -- AoT* variant — N independent runs, LLM selector picks the best.
    -- Paper §5; selector prompt wording is implementation choice.
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

    local selector_tokens = ctx.selector_tokens or DEFAULT_SELECTOR_TOKENS
    local selected_idx_raw = alc.llm(
        string.format(SELECTOR_PROMPT_FORMAT, task, candidates_str, runs),
        {
            system = SELECTOR_SYSTEM_PROMPT,
            max_tokens = selector_tokens,
        }
    )

    local idx = tonumber((selected_idx_raw or ""):match("(%d+)")) or 1
    if idx < 1 or idx > runs then
        idx = 1
    end
    ctx.result = results[idx]
    return ctx
end

-- Malli-style self-decoration. Wrap each entry independently;
-- nested dispatch in single_run relies on these wrappers being
-- installed before any call goes out (alc_shapes/README §Producer
-- usage "Nested dispatch").
M.decompose = S.instrument(M, "decompose")
M.split_indep_dep = S.instrument(M, "split_indep_dep")
M.get_max_path_length = S.instrument(M, "get_max_path_length")
M.contract = S.instrument(M, "contract")
M.solve = S.instrument(M, "solve")
M.run = S.instrument(M, "run")

return M
