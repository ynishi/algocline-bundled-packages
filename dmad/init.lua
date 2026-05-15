--- dmad — Multi-Agent Debate (Du 2023) — N parallel agents, R debate rounds
---
--- ## Primary citation
---
--- Du, Y., Li, S., Torralba, A., Tenenbaum, J. B., & Mordatch, I. (2023).
--- "Improving Factuality and Reasoning in Language Models through
--- Multiagent Debate". arXiv:2305.14325.
--- https://arxiv.org/abs/2305.14325
---
--- Canonical reference implementation (paper has no numbered Algorithm
--- block — repo is treated as the literal source for prompt templates and
--- default parameters):
--- https://github.com/composable-models/llm_multiagent_debate
--- — `gsm/gen_gsm.py`   : N=3 agents, R=2 rounds, INIT / DEBATE string
---                        literals lifted into Lua (prefix / per-agent
---                        block / suffix structure preserved; per-agent
---                        block keeps the triple-backtick wrapper)
--- — `gsm/eval_gsm.py`  : `most_frequent` first-wins majority on `\boxed{}`
---
--- ## Algorithm (Du 2023 §3)
---
--- ```
---   round 0 (init):  for each agent i = 1..N (parallel):
---                        a_{i,0} ← LLM(INIT_TEMPLATE(task))
---   for r = 1..R:
---       for each agent i = 1..N (parallel):
---           others ← { a_{j,r-1} : j ≠ i }
---           a_{i,r} ← LLM(DEBATE_TEMPLATE(task, others))
---   answers ← { extract(a_{i,R}) : i = 1..N }
---   return majority_vote(answers)         -- eval_gsm.py: most_frequent
--- ```
---
--- Three pieces compose the algorithm:
---
---   N (n_agents)  3   parallel reasoning agents (each is one LLM thread)
---   R (n_rounds)  2   debate rounds after the initial proposal
---   aggregate     majority vote, first-wins tie-break, on extracted answers
---
--- Total LLM calls: N + N·R = N·(R+1). Default 3·(2+1) = 9.
---
--- ## Defaults (Du 2023 repo `gsm/gen_gsm.py`)
---
--- | Symbol | Value | Label | Source                                                    |
--- |--------|-------|-------|-----------------------------------------------------------|
--- | N      | 3     | (L)   | `gen_gsm.py` agents=3                                     |
--- | R      | 2     | (L)   | `gen_gsm.py` rounds=2                                     |
--- | temp   | nil   | (X)   | Paper does not fix temperature; repo omits the param so   |
--- |        |       |       | OpenAI API default is used. Pkg leaves nil to mirror this |
--- | tokens | 500   | (X)   | Paper does not specify max_tokens. (X) infrastructure;    |
--- |        |       |       | provenance: prior dmad v0.1.0 baseline (commit 54faaa5)   |
---
--- The INIT and DEBATE prompt templates are (L) — Lua transcriptions of
--- the corresponding `gen_gsm.py` string literals. The DEBATE template
--- is built from `prefix + per-agent block (each wraps a response in
--- ``` triple backticks ```) + suffix`, matching repo `construct_message`
--- byte-for-byte (modulo Python f-string `{}` ↔ Lua `%s` substitution
--- and the implicit `\n` semantics). The `\boxed{answer}` sentinel that
--- `extract_boxed` reads back is preserved. Overriding the templates
--- (X-mode) invalidates the paper's effect guarantee but the pkg
--- accepts the override.
---
--- ## Entry contract
---
--- See `M.spec` below for the formal machine-readable contract:
---
--- - `build_init_prompt`   — pure, direct-args. returns { prompt, system }
--- - `build_debate_prompt` — pure, direct-args. returns { prompt, system }
--- - `extract_boxed`       — pure, direct-args. returns final-answer string
--- - `aggregate_majority`  — pure, direct-args. returns { answer, count, tally }
--- - `run`                 — Strategy, ctx-threading. orchestrates N·(R+1) LLM calls
---
--- The four sub-entries are LLM-independent and unit-testable. `run` is
--- the only LLM-mediated entry.
---
--- ## EXTENSION POINTS
---
--- ```
--- ┌──────────────────────────────────────────────────────────────────────┐
--- │ REQUIRED                                                             │
--- │   ctx.task                  (string)         problem statement       │
--- ├──────────────────────────────────────────────────────────────────────┤
--- │ (L)-override OPTION                                                  │
--- │   ctx.n_agents              (number ≥ 2)     override N default      │
--- │   ctx.n_rounds              (number ≥ 1)     override R default      │
--- ├──────────────────────────────────────────────────────────────────────┤
--- │ (X) infrastructure (paper does not specify)                          │
--- │   ctx.gen_tokens            (number)         max tokens per LLM call │
--- │   ctx.temperature           (number)         per-LLM temperature     │
--- │   ctx.init_prompt           (string template) override init prompt   │
--- │   ctx.debate_prompt         (string template) override debate prompt │
--- │   ctx.system_prompt         (string)         override system prompt  │
--- │   ctx.extract_fn            (function)       custom answer extractor │
--- │                                              (default: extract_boxed)│
--- ├──────────────────────────────────────────────────────────────────────┤
--- │ Stability tier:                                                      │
--- │   stable     : n_agents / n_rounds / gen_tokens / temperature        │
--- │   v2-opt-in  : *_prompt / system_prompt / extract_fn                 │
--- │                (template/extractor format may evolve)                │
--- └──────────────────────────────────────────────────────────────────────┘
--- ```
---
--- Overriding any (L) default invalidates the paper's effect guarantee.
---
--- ## Comparison with related packages
---
--- vs `hegelian` (Abdali 2025): hegelian is single-thread Thesis/Antithesis/
--- Synthesis with temperature annealing — a different paper, different
--- algorithm. dmad runs N agents in parallel debating each other.
---
--- vs `sc` (Self-Consistency, Wang 2022): sc samples N independent paths
--- in a single round, no inter-path interaction. dmad has R rounds of
--- explicit cross-agent visibility.
---
--- vs `moa` (Wang 2024): moa is L-layer hierarchical aggregation
--- (proposers + aggregators). dmad is flat: every agent sees every other
--- agent's previous-round response.
---
--- ## History
---
--- dmad v0.1.0 (commit 54faaa5, 2026-03-15) cited Du 2023 but implemented
--- a Hegelian dialectic with a "rebuttal" stage that has no source in
--- Du's paper. The Hegelian methodology was extracted to a separate
--- `hegelian/` pkg (Abdali 2025 paper-explicit, commit e030095 + doc
--- correction 5838927, 2026-05-15). This v0.2.0 rewrites dmad as pure
--- Du 2023 Multi-Agent Debate; the "rebuttal" stage is removed (no Du
--- paper basis); Hegelian users should switch to `require("hegelian")`.

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "dmad",
    version = "0.2.0",
    description = "Multi-Agent Debate (Du 2023) — N parallel agents, R debate rounds, majority vote",
    category = "reasoning",
}

-- Centralized defaults per Du 2023 repo `gsm/gen_gsm.py`.
--   n_agents    = 3    (L) gen_gsm.py agents=3
--   n_rounds    = 2    (L) gen_gsm.py rounds=2
--   gen_tokens  = 500  (X) infrastructure, paper does not specify token budgets.
--                          Provenance: prior dmad v0.1.0 baseline (commit 54faaa5).
--   temperature = nil  (X) infrastructure, paper does not fix temperature;
--                          repo omits the param so OpenAI API default is used.
--                          Pkg leaves nil to mirror this.
M._defaults = {
    n_agents    = 3,
    n_rounds    = 2,
    gen_tokens  = 500,
    temperature = nil,
}

-- (L) INIT prompt template — Lua transcription of the `gen_gsm.py`
-- string literal (Python `{}` → Lua `%s`, no other transformation).
-- `%s` is the task.
-- Source: github.com/composable-models/llm_multiagent_debate/gsm/gen_gsm.py
M.DEFAULT_INIT_TEMPLATE = "Can you solve the following math problem? %s Explain your reasoning. Your final answer should be a single numerical number, in the form \\boxed{answer}, at the end of your response."

-- (L) DEBATE prompt template — Lua transcription of Du repo
-- `gen_gsm.py::construct_message`. Repo builds the body in three pieces
-- (prefix + per-agent block + suffix); we keep the same shape and the
-- same string literals. Each entry in `other_responses` is wrapped via
-- `DEFAULT_DEBATE_AGENT_BLOCK` ("One agent solution: ```{response}```",
-- triple-backtick fenced, byte-identical to the repo string). The suffix's leading
-- "\n\n" supplies the gap between consecutive agent blocks.
-- Two substitutions on the assembled body: %s = others_text (the
-- concatenated per-agent blocks), %s = task.
M.DEFAULT_DEBATE_PREFIX = "These are the solutions to the problem from other agents: "
M.DEFAULT_DEBATE_AGENT_BLOCK = "\n\n One agent solution: ```%s```"
M.DEFAULT_DEBATE_SUFFIX = "\n\n Using the solutions from other agents as additional information, can you provide your answer to the math problem? \n The original math problem is %s. Your final answer should be a single numerical number, in the form \\boxed{answer}, at the end of your response."

-- (X) System prompt. Paper does not specify a system message; repo uses
-- {"role": "user", ...} only. The default below is a neutral framing
-- chosen by this pkg; the caller may override.
M.DEFAULT_SYSTEM_PROMPT = "You are a careful mathematical reasoner. Show your work step by step."

-- ─── Shape declarations ───

local prompt_pair_shape = T.shape({
    prompt = T.string:describe("LLM user prompt"),
    system = T.string:describe("LLM system prompt"),
}, { open = true })

local majority_result_shape = T.shape({
    answer = T.string:describe("Majority answer (first-wins tie-break)"),
    count  = T.number:describe("Number of votes the majority received"),
    tally  = T.array_of(T.shape({
        answer = T.string:describe("Distinct answer string"),
        count  = T.number:describe("Vote count for this answer"),
    })):describe("Full tally, descending by count, ties broken by first-occurrence"),
}, { open = true })

local agent_round_shape = T.shape({
    agent = T.number:describe("1-based agent index i"),
    round = T.number:describe("0-based round index r (0 = init, 1..R = debate)"),
    text  = T.string:describe("LLM output of agent i at round r"),
}, { open = true })

local init_input_shape = T.shape({
    task           = T.string:describe("Problem statement (required)"),
    init_prompt    = T.string:is_optional():describe("Override INIT template (X)"),
    system_prompt  = T.string:is_optional():describe("Override system prompt (X)"),
}, { open = true })

local debate_input_shape = T.shape({
    task                = T.string:describe("Problem statement (required)"),
    other_responses     = T.array_of(T.string):describe("Previous-round responses from the OTHER N-1 agents (required, non-empty)"),
    debate_prompt       = T.string:is_optional():describe("Override DEBATE template (X)"),
    debate_prefix       = T.string:is_optional():describe("Override DEBATE prefix when not using full template (X)"),
    debate_agent_block  = T.string:is_optional():describe("Override per-agent block format when not using full template (X)"),
    debate_suffix       = T.string:is_optional():describe("Override DEBATE suffix when not using full template (X)"),
    system_prompt       = T.string:is_optional():describe("Override system prompt (X)"),
}, { open = true })

local extract_input_shape = T.shape({
    text = T.string:describe("LLM response text containing a \\boxed{...} answer"),
}, { open = true })

local aggregate_input_shape = T.shape({
    answers = T.array_of(T.string):describe("Extracted final answers from each agent (non-empty)"),
}, { open = true })

local run_input_shape = T.shape({
    task           = T.string:describe("Problem statement (required)"),
    n_agents       = T.number:is_optional()
        :describe("Number of parallel agents (default: " .. M._defaults.n_agents .. ", (L) Du repo gen_gsm.py)"),
    n_rounds       = T.number:is_optional()
        :describe("Number of debate rounds after init (default: " .. M._defaults.n_rounds .. ", (L) Du repo gen_gsm.py)"),
    gen_tokens     = T.number:is_optional()
        :describe("Max tokens per LLM call (default: " .. M._defaults.gen_tokens .. ", (X) infrastructure)"),
    temperature    = T.number:is_optional()
        :describe("LLM temperature (default: API default, (X) infrastructure; paper does not fix)"),
    init_prompt    = T.string:is_optional():describe("Override INIT template (X)"),
    debate_prompt  = T.string:is_optional():describe("Override DEBATE template (X)"),
    system_prompt  = T.string:is_optional():describe("Override system prompt (X)"),
}, { open = true })

local run_result_shape = T.shape({
    answer          = T.string:describe("Final majority-vote answer"),
    n_agents        = T.number:describe("N actually used"),
    n_rounds        = T.number:describe("R actually used"),
    responses       = T.array_of(T.array_of(T.string))
        :describe("responses[r+1][i] = a_{i,r} (1-based for Lua); responses[1] = init, responses[R+1] = final"),
    last_answers    = T.array_of(T.string)
        :describe("Extracted answer per agent at round R"),
    tally           = T.array_of(T.shape({
        answer = T.string,
        count  = T.number,
    }, { open = true })):describe("Full vote tally"),
    total_llm_calls = T.number:describe("Total LLM calls made (= N·(R+1))"),
    debate_log      = T.array_of(agent_round_shape)
        :describe("Flat chronological log of (agent, round, text) tuples"),
}, { open = true })

-- ─── Validation helpers ───

local function require_string(value, name, entry)
    if type(value) ~= "string" or value == "" then
        error(string.format("dmad.%s: %s must be a non-empty string", entry, name), 3)
    end
end

local function require_table(value, name, entry)
    if type(value) ~= "table" then
        error(string.format("dmad.%s: %s must be a table", entry, name), 3)
    end
end

local function require_positive_int(value, name, entry, minval)
    minval = minval or 1
    if type(value) ~= "number" or value < minval or math.floor(value) ~= value then
        error(string.format(
            "dmad.%s: %s must be an integer >= %d, got %s",
            entry, name, minval, tostring(value)), 3)
    end
end

local function require_non_empty_array(value, name, entry)
    require_table(value, name, entry)
    if #value == 0 then
        error(string.format("dmad.%s: %s must be a non-empty array", entry, name), 3)
    end
end

-- ─── Pure entries ───

--- Build the INIT prompt for a single agent.
---@param args table { task, init_prompt?, system_prompt? }
---@return table { prompt, system }
function M.build_init_prompt(args)
    require_table(args, "args", "build_init_prompt")
    require_string(args.task, "task", "build_init_prompt")

    local template = args.init_prompt or M.DEFAULT_INIT_TEMPLATE
    local system = args.system_prompt or M.DEFAULT_SYSTEM_PROMPT
    return {
        prompt = string.format(template, args.task),
        system = system,
    }
end

--- Build the DEBATE prompt for one agent at round r > 0.
---
--- Two construction modes:
--- 1. `debate_prompt` (X) — full custom template with two `%s`
---    placeholders: first = concatenated other-agents block,
---    second = task. Caller pre-formats the agent block as desired.
--- 2. Default (no `debate_prompt`) — uses prefix + per-agent block +
---    suffix, matching Du repo `construct_message`. Each entry in
---    `other_responses` is wrapped via `debate_agent_block` (also
---    overridable as X).
---@param args table { task, other_responses, debate_prompt?, debate_prefix?, debate_agent_block?, debate_suffix?, system_prompt? }
---@return table { prompt, system }
function M.build_debate_prompt(args)
    require_table(args, "args", "build_debate_prompt")
    require_string(args.task, "task", "build_debate_prompt")
    require_non_empty_array(args.other_responses, "other_responses", "build_debate_prompt")

    local system = args.system_prompt or M.DEFAULT_SYSTEM_PROMPT

    -- Concatenate other-agent responses (paper repo structure).
    local agent_block_tpl = args.debate_agent_block or M.DEFAULT_DEBATE_AGENT_BLOCK
    local concat = {}
    for _, response in ipairs(args.other_responses) do
        concat[#concat + 1] = string.format(agent_block_tpl, response)
    end
    local others_text = table.concat(concat, "")

    local prompt
    if args.debate_prompt then
        prompt = string.format(args.debate_prompt, others_text, args.task)
    else
        local prefix = args.debate_prefix or M.DEFAULT_DEBATE_PREFIX
        local suffix = args.debate_suffix or M.DEFAULT_DEBATE_SUFFIX
        prompt = prefix .. others_text .. string.format(suffix, args.task)
    end

    return { prompt = prompt, system = system }
end

--- Extract a final answer enclosed in `\boxed{...}` from an LLM response.
---
--- Matches Du repo `eval_gsm.py:parse_answer` semantics: takes the LAST
--- `\boxed{...}` match if multiple exist (LLMs sometimes show working
--- examples before the final boxed answer). When no `\boxed{...}` is
--- present, returns the trimmed text as a graceful fallback so downstream
--- majority vote can still proceed.
---@param args table { text }
---@return string
function M.extract_boxed(args)
    require_table(args, "args", "extract_boxed")
    require_string(args.text, "text", "extract_boxed")

    local last_match
    for content in args.text:gmatch("\\boxed%s*{([^{}]*)}") do
        last_match = content
    end
    if last_match then
        return (last_match:gsub("^%s+", ""):gsub("%s+$", ""))
    end
    return (args.text:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Compute the majority-vote answer with first-wins tie-break.
---
--- Matches Du repo `eval_gsm.py:most_frequent` semantics: highest count
--- wins; ties broken by earliest occurrence in `answers`. Comparison uses
--- the answer string as-is (the caller is expected to normalize, e.g.
--- via `extract_boxed`, before invoking).
---@param args table { answers }
---@return table { answer, count, tally }
function M.aggregate_majority(args)
    require_table(args, "args", "aggregate_majority")
    require_non_empty_array(args.answers, "answers", "aggregate_majority")

    local count_by_answer = {}
    local first_index_by_answer = {}
    for i, ans in ipairs(args.answers) do
        if type(ans) ~= "string" then
            error(string.format(
                "dmad.aggregate_majority: answers[%d] must be a string, got %s",
                i, type(ans)), 3)
        end
        if count_by_answer[ans] == nil then
            count_by_answer[ans] = 0
            first_index_by_answer[ans] = i
        end
        count_by_answer[ans] = count_by_answer[ans] + 1
    end

    -- Build tally array, sorted by (count desc, first-occurrence asc).
    local tally = {}
    for ans, c in pairs(count_by_answer) do
        tally[#tally + 1] = { answer = ans, count = c, _first = first_index_by_answer[ans] }
    end
    table.sort(tally, function(a, b)
        if a.count ~= b.count then
            return a.count > b.count
        end
        return a._first < b._first
    end)

    local winner = tally[1]
    local clean_tally = {}
    for _, t in ipairs(tally) do
        clean_tally[#clean_tally + 1] = { answer = t.answer, count = t.count }
    end

    return {
        answer = winner.answer,
        count  = winner.count,
        tally  = clean_tally,
    }
end

-- ─── Strategy entry ───

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    if type(ctx) ~= "table" then
        error("dmad.run: ctx must be a table", 2)
    end
    if alc == nil then
        error("dmad.run: alc host is not available", 2)
    end
    require_string(ctx.task, "task", "run")

    local n_agents = ctx.n_agents or M._defaults.n_agents
    local n_rounds = ctx.n_rounds or M._defaults.n_rounds
    local gen_tokens = ctx.gen_tokens or M._defaults.gen_tokens
    local temperature = ctx.temperature  -- nil allowed
    require_positive_int(n_agents, "n_agents", "run", 2)
    require_positive_int(n_rounds, "n_rounds", "run", 1)
    require_positive_int(gen_tokens, "gen_tokens", "run", 1)
    if temperature ~= nil and type(temperature) ~= "number" then
        error("dmad.run: temperature must be a number or nil", 2)
    end

    local extract_fn = ctx.extract_fn or function(text)
        return M.extract_boxed({ text = text })
    end

    -- responses[r+1][i] = a_{i,r}; debate_log = flat chronological list.
    local responses = {}
    local debate_log = {}
    local total_llm_calls = 0

    local function llm_opts()
        local o = { max_tokens = gen_tokens }
        if temperature ~= nil then o.temperature = temperature end
        if ctx.system_prompt then o.system = ctx.system_prompt
        else o.system = M.DEFAULT_SYSTEM_PROMPT end
        return o
    end

    -- ─── Round 0: init (N parallel proposals) ───
    alc.log("info", string.format("dmad: init round (N=%d agents)", n_agents))
    local init = {}
    for i = 1, n_agents do
        local pair = M.build_init_prompt({
            task          = ctx.task,
            init_prompt   = ctx.init_prompt,
            system_prompt = ctx.system_prompt,
        })
        local resp = alc.llm(pair.prompt, llm_opts())
        require_string(resp, "init response", "run")
        init[i] = resp
        total_llm_calls = total_llm_calls + 1
        debate_log[#debate_log + 1] = { agent = i, round = 0, text = resp }
    end
    responses[1] = init

    -- ─── Rounds 1..R: debate ───
    for r = 1, n_rounds do
        alc.log("info", string.format("dmad: debate round %d/%d", r, n_rounds))
        local prev = responses[r]  -- previous round's responses
        local cur = {}
        for i = 1, n_agents do
            -- Others = prev minus agent i
            local others = {}
            for j = 1, n_agents do
                if j ~= i then others[#others + 1] = prev[j] end
            end
            local pair = M.build_debate_prompt({
                task            = ctx.task,
                other_responses = others,
                debate_prompt   = ctx.debate_prompt,
                system_prompt   = ctx.system_prompt,
            })
            local resp = alc.llm(pair.prompt, llm_opts())
            require_string(resp, "debate response", "run")
            cur[i] = resp
            total_llm_calls = total_llm_calls + 1
            debate_log[#debate_log + 1] = { agent = i, round = r, text = resp }
        end
        responses[r + 1] = cur
    end

    -- ─── Aggregate: extract per agent at round R, then majority vote ───
    local final_round = responses[n_rounds + 1]
    local last_answers = {}
    for i = 1, n_agents do
        last_answers[i] = extract_fn(final_round[i])
    end
    local maj = M.aggregate_majority({ answers = last_answers })

    alc.log("info", string.format(
        "dmad: complete — N=%d agents, R=%d rounds, %d LLM calls, winner=%q (%d/%d votes)",
        n_agents, n_rounds, total_llm_calls,
        maj.answer, maj.count, n_agents))

    ctx.result = {
        answer          = maj.answer,
        n_agents        = n_agents,
        n_rounds        = n_rounds,
        responses       = responses,
        last_answers    = last_answers,
        tally           = maj.tally,
        total_llm_calls = total_llm_calls,
        debate_log      = debate_log,
    }
    return ctx
end

---@type AlcSpec
M.spec = {
    entries = {
        build_init_prompt = {
            args   = init_input_shape,
            result = prompt_pair_shape,
        },
        build_debate_prompt = {
            args   = debate_input_shape,
            result = prompt_pair_shape,
        },
        extract_boxed = {
            args   = extract_input_shape,
            result = T.string:describe("Extracted answer string"),
        },
        aggregate_majority = {
            args   = aggregate_input_shape,
            result = majority_result_shape,
        },
        run = {
            input  = run_input_shape,
            result = run_result_shape,
        },
    },
}

-- Self-decoration for ALC_SHAPE_CHECK=1 dev mode.
M.run                 = S.instrument(M, "run")
M.build_init_prompt   = S.instrument(M, "build_init_prompt")
M.build_debate_prompt = S.instrument(M, "build_debate_prompt")
M.extract_boxed       = S.instrument(M, "extract_boxed")
M.aggregate_majority  = S.instrument(M, "aggregate_majority")

return M
