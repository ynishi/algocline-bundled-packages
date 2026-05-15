--- reconcile — ReConcile (Chen 2023) — round-table consensus with
--- confidence-weighted voting
---
--- ## Primary citation
---
--- Chen, J. C.-Y., Saha, S., & Bansal, M. (2023). "ReConcile: Round-Table
--- Conference Improves Reasoning via Consensus among Diverse LLMs".
--- arXiv:2309.13007.
--- https://arxiv.org/abs/2309.13007
---
--- Canonical repo (used for §B.5 5-bucket confidence calibration and
--- discussion prompt structure):
--- https://github.com/dinobby/ReConcile
--- — `utils.py::trans_confidence` : 5-bucket calibrated weight mapping
--- — `utils.py::parse_output`      : answer / explanation / confidence
---                                   parser
---
--- ## Algorithm (Chen 2023 §3 / Algorithm 1)
---
--- ```
---   r ← 0
---   while r ≤ R and ¬consensus(answers):
---       for each agent A_i:
---           if r = 0:
---               (a_i, e_i, p_i) ← A_i(init_prompt(task))
---           else:
---               others_view ← format_others(answers[r-1], explanations[r-1],
---                                           confidences[r-1], convincing[r-1])
---               (a_i, e_i, p_i) ← A_i(discussion_prompt(task, others_view))
---       answers[r] ← (a_1, …, a_n)
---       team_answer[r] ← argmax_a Σ_i f(p_i) · 𝟙(a_i = a)    -- §4
---       r ← r + 1
---   return team_answer[r-1]
--- ```
---
--- Three phases (§3):
---
---   Phase 1  (Initial)        : each agent generates (answer, explanation,
---                                confidence) independently
---   Phase 2  (Discussion)     : up to R rounds; each agent revises after
---                                seeing others' (answer, explanation,
---                                confidence) + "convincing" sample set
---   Phase 3  (Vote)           : confidence-weighted argmax over current
---                                round's normalized answers
---
--- Consensus criterion: all agents agree on the same normalized answer.
--- When consensus is reached, the loop terminates early.
---
--- ## Defaults (Chen 2023 §3, §4 footnote)
---
--- | Symbol            | Value | Label | Source                                |
--- |-------------------|-------|-------|---------------------------------------|
--- | n (agents)        | 3     | (L)   | §3 main exp uses 3 diverse agents     |
--- | R (max_rounds)    | 3     | (L)   | §3 "up to three discussion rounds"    |
--- | convincing_count  | 4     | (L)   | §4 "we select a small number of       |
--- |                   |       |       | samples (4 in our experiments)"       |
--- | gen_tokens        | 600   | (X)   | Paper does not specify; infrastructure|
--- | temperature       | nil   | (X)   | Paper does not fix; API default used  |
---
--- The **5-bucket confidence calibration** is (L) verbatim from repo
--- `utils.py::trans_confidence`:
---
---   p ≤ 0.6        → 0.1
---   0.6 < p < 0.8  → 0.3
---   0.8 ≤ p < 0.9  → 0.5
---   0.9 ≤ p < 1.0  → 0.8
---   p = 1.0        → 1.0
---
--- ## Entry contract
---
--- See `M.spec` below for the formal machine-readable contract:
---
--- - `confidence_to_weight`     — pure, direct-args. f(p) per §B.5 buckets
--- - `compute_weighted_argmax`  — pure, direct-args. §4 Phase 3 formula
--- - `check_consensus`          — pure, direct-args. all-agree predicate
--- - `build_discussion_prompt`  — pure, direct-args. returns { prompt, system }
--- - `run`                      — Strategy, ctx-threading. orchestrates N to N·(R+1) LLM calls
---
--- Four pure helpers are LLM-independent and unit-testable. `run` is the
--- only LLM-mediated entry.
---
--- ## EXTENSION POINTS
---
--- ```
--- ┌──────────────────────────────────────────────────────────────────────┐
--- │ REQUIRED                                                             │
--- │   ctx.task                  (string)         problem / question      │
--- │   ctx.agents                (array, paper-faithful PATH) — list of   │
--- │       specs, each { model = string [, system = string] }             │
--- │     OR                                                               │
--- │   ctx.personas              (array, non-paper-faithful ALT PATH) —   │
--- │       array of system-prompt strings; single model + persona         │
--- │       rotation. Departs from §3 diverse-LLM guarantee.               │
--- ├──────────────────────────────────────────────────────────────────────┤
--- │ (L)-override OPTION                                                  │
--- │   ctx.max_rounds            (number ≥ 1)     override R=3 default    │
--- │   ctx.convincing_count      (number ≥ 0)     override 4 (L §4 fn)    │
--- ├──────────────────────────────────────────────────────────────────────┤
--- │ (X) infrastructure (paper does not specify)                          │
--- │   ctx.gen_tokens            (number)         max tokens per LLM call │
--- │   ctx.temperature           (number)         per-LLM temperature     │
--- │   ctx.init_prompt           (string template) override Phase 1 prompt│
--- │   ctx.discussion_prompt     (string template) override Phase 2 prompt│
--- │   ctx.system_prompt         (string)         override system prompt  │
--- │   ctx.parse_fn              (function)       custom response parser  │
--- │   ctx.confidence_buckets    (array of {threshold,weight})            │
--- │                                              override 5-bucket scale │
--- │                                              (X — invalidates §B.5)  │
--- ├──────────────────────────────────────────────────────────────────────┤
--- │ Stability tier:                                                      │
--- │   stable     : max_rounds / convincing_count / gen_tokens / temp     │
--- │   v2-opt-in  : *_prompt / system_prompt / parse_fn                   │
--- │   experimental : personas (single-model fallback) /                  │
--- │                  confidence_buckets (paper guarantee not held)       │
--- └──────────────────────────────────────────────────────────────────────┘
--- ```
---
--- ## Comparison with related packages
---
--- vs `dmad` (Du 2023): dmad does N agents × R rounds + majority vote on
--- extracted `\boxed{}` answers, no confidence weighting. reconcile adds
--- (1) confidence elicitation per agent per round, (2) §B.5 calibrated
--- weights, (3) early-stop on consensus.
---
--- vs `moa` (Wang 2024): moa uses an explicit Aggregate-and-Synthesize
--- LLM call as the ⊕ operator. reconcile aggregates by deterministic
--- confidence-weighted argmax (no aggregator LLM).
---
--- vs `dci` (Prakash 2026): dci runs 4 fixed roles through 8 typed-act
--- stages and emits a decision_packet with first-class minority_report.
--- reconcile is flatter: same-role agents converge via confidence-weighted
--- voting, simpler stop condition.

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "reconcile",
    version = "0.1.0",
    description = "ReConcile (Chen 2023) — round-table consensus with §B.5 confidence-weighted voting and early-stop",
    category = "aggregation",
}

-- Centralized defaults per Chen 2023 §3 / §4.
--   max_rounds       = 3    (L) §3 "up to three discussion rounds"
--   convincing_count = 4    (L) §4 footnote "4 in our experiments"
--   gen_tokens       = 600  (X) infrastructure, paper does not specify
--   temperature      = nil  (X) infrastructure, paper does not fix
M._defaults = {
    max_rounds       = 3,
    convincing_count = 4,
    gen_tokens       = 600,
    temperature      = nil,
}

-- (L) 5-bucket calibrated weight mapping, verbatim from
-- github.com/dinobby/ReConcile/utils.py::trans_confidence.
-- Bucket order: descending threshold (so the most specific bucket
-- matches first when iterating).
M.CONFIDENCE_BUCKETS = {
    -- { lo, hi_exclusive, weight }, with hi_exclusive=nil meaning "equal to threshold"
    { threshold = 1.0, weight = 1.0, exact = true },
    { threshold = 0.9, weight = 0.8 },
    { threshold = 0.8, weight = 0.5 },
    { threshold = 0.6, weight = 0.3, strict_greater = true },
    { threshold = 0.0, weight = 0.1 },  -- floor: any p ≤ 0.6 gets 0.1
}

-- (X) Default system prompt. Paper does not fix; this default frames
-- the agent as a participant in a deliberative round-table.
M.DEFAULT_SYSTEM_PROMPT = "You are participating in a round-table discussion with other reasoning agents. Provide your answer, an explanation, and your confidence on a 0.0-1.0 scale. Be honest about uncertainty."

-- (X) Default initial-phase prompt. Paper specifies the *information*
-- to elicit (answer + explanation + confidence) but the exact wording
-- is not fixed. We provide a reproducible default that asks for the
-- three fields in a parseable format.
M.DEFAULT_INIT_PROMPT_TEMPLATE = [[Question: %s

Provide:
1. Your answer (one line).
2. A brief explanation of your reasoning.
3. Your confidence as a decimal between 0.0 and 1.0.

Format your response as:
Answer: <your answer>
Explanation: <your explanation>
Confidence: <0.0-1.0>]]

-- (X) Default discussion-phase prompt template. The %s slots are
-- (1) the task, (2) the formatted others' responses block.
M.DEFAULT_DISCUSSION_PROMPT_TEMPLATE = [[Question: %s

Other agents' previous-round responses:

%s

Considering the other agents' answers, explanations, and confidences,
revise your own. You may either keep your original position (if you find
others' arguments unconvincing) or update it (if you find others'
arguments compelling).

Format your response as:
Answer: <your answer>
Explanation: <your explanation>
Confidence: <0.0-1.0>]]

-- ─── Shape declarations ───

local prompt_pair_shape = T.shape({
    prompt = T.string:describe("LLM user prompt"),
    system = T.string:describe("LLM system prompt"),
}, { open = true })

local agent_spec_shape = T.shape({
    model  = T.string:is_optional():describe("Caller-supplied model id"),
    system = T.string:is_optional():describe("Per-agent system prompt override"),
}, { open = true })

local agent_response_shape = T.shape({
    agent       = T.number:describe("1-based agent index"),
    round       = T.number:describe("0-based round index"),
    answer      = T.string:describe("Raw answer text (as parsed from LLM output)"),
    explanation = T.string:describe("Reasoning explanation"),
    confidence  = T.number:describe("Self-reported confidence in [0,1]"),
    normalized  = T.string:describe("Normalized answer (lowercased, trimmed) used for voting"),
    weight      = T.number:describe("Calibrated weight f(confidence) per §B.5"),
    raw_text    = T.string:is_optional():describe("Original LLM response (preserved for debugging)"),
}, { open = true })

local run_input_shape = T.shape({
    task              = T.string:describe("Problem statement (required)"),
    agents            = T.array_of(agent_spec_shape):is_optional()
        :describe("Paper-faithful PATH: array of agent specs"),
    personas          = T.array_of(T.string):is_optional()
        :describe("Non-paper-faithful ALT PATH: persona system prompts"),
    max_rounds        = T.number:is_optional()
        :describe("Max discussion rounds R (default: " .. M._defaults.max_rounds .. ", (L) Chen §3)"),
    convincing_count  = T.number:is_optional()
        :describe("Convincing-sample count (default: " .. M._defaults.convincing_count .. ", (L) Chen §4 footnote)"),
    gen_tokens        = T.number:is_optional()
        :describe("Max tokens per LLM call (default: " .. M._defaults.gen_tokens .. ", (X) infrastructure)"),
    temperature       = T.number:is_optional()
        :describe("LLM temperature (default: API default, (X) paper not fixed)"),
    init_prompt       = T.string:is_optional():describe("Override Phase 1 prompt (X)"),
    discussion_prompt = T.string:is_optional():describe("Override Phase 2 prompt (X)"),
    system_prompt     = T.string:is_optional():describe("Override system prompt (X)"),
}, { open = true })

local run_result_shape = T.shape({
    answer          = T.string:describe("Final team answer (normalized form of winning bucket)"),
    n_agents        = T.number:describe("N actually used"),
    rounds_used     = T.number:describe("Number of rounds completed (1..R+1; 1 = consensus at init phase)"),
    consensus       = T.boolean:describe("true if all agents agreed at termination round; false if R+1 rounds exhausted"),
    history         = T.array_of(T.array_of(agent_response_shape))
        :describe("history[r+1][i] = agent i's response at round r"),
    tally           = T.array_of(T.shape({
        answer = T.string:describe("Distinct normalized answer"),
        weight = T.number:describe("Sum of calibrated weights for this answer"),
        count  = T.number:describe("Raw agent count for this answer"),
    }, { open = true })):describe("Vote tally at termination round"),
    total_llm_calls = T.number:describe("Total LLM calls actually made"),
}, { open = true })

-- ─── Validation helpers ───

local function require_string(value, name, entry)
    if type(value) ~= "string" or value == "" then
        error(string.format("reconcile.%s: %s must be a non-empty string", entry, name), 3)
    end
end

local function require_table(value, name, entry)
    if type(value) ~= "table" then
        error(string.format("reconcile.%s: %s must be a table", entry, name), 3)
    end
end

local function require_non_empty_array(value, name, entry)
    require_table(value, name, entry)
    if #value == 0 then
        error(string.format("reconcile.%s: %s must be a non-empty array", entry, name), 3)
    end
end

local function require_positive_int(value, name, entry, minval)
    minval = minval or 1
    if type(value) ~= "number" or value < minval or math.floor(value) ~= value then
        error(string.format(
            "reconcile.%s: %s must be an integer >= %d, got %s",
            entry, name, minval, tostring(value)), 3)
    end
end

local function require_number_in_range(value, name, entry, lo, hi)
    if type(value) ~= "number" or value < lo or value > hi then
        error(string.format(
            "reconcile.%s: %s must be a number in [%g, %g], got %s",
            entry, name, lo, hi, tostring(value)), 3)
    end
end

-- ─── Internal helpers (test surface via M._internal) ───

local function normalize_answer(s)
    if type(s) ~= "string" then return "" end
    local t = s:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    return t:lower()
end

local function coerce_confidence(raw)
    if type(raw) == "number" then
        if raw < 0 then return 0
        elseif raw > 1 then return 1
        else return raw end
    end
    if type(raw) == "string" then
        -- s:gsub returns (string, count) — wrap to drop count so tonumber
        -- doesn't see it as a base argument.
        local trimmed = (raw:gsub("^%s+", ""))
        trimmed = (trimmed:gsub("%s+$", ""))
        local n = tonumber(trimmed)
        if n == nil then return 0.5 end  -- neutral fallback
        if n < 0 then return 0
        elseif n > 1 then return 1
        else return n end
    end
    return 0.5
end

local function parse_agent_response(raw)
    -- Accept either a pre-parsed table or a raw text response.
    if type(raw) == "table" then
        return {
            answer      = tostring(raw.answer or ""),
            explanation = tostring(raw.explanation or ""),
            confidence  = coerce_confidence(raw.confidence),
            raw_text    = raw.raw_text,
        }
    end
    if type(raw) ~= "string" then
        return { answer = "", explanation = "", confidence = 0.5, raw_text = nil }
    end

    local answer = raw:match("[Aa]nswer:%s*([^\n]+)") or ""
    local explanation = raw:match("[Ee]xplanation:%s*([^\n]+)") or ""
    local conf_str = raw:match("[Cc]onfidence:%s*([%d%.]+)")
    answer = answer:gsub("^%s+", ""):gsub("%s+$", "")
    explanation = explanation:gsub("^%s+", ""):gsub("%s+$", "")

    return {
        answer      = answer,
        explanation = explanation,
        confidence  = coerce_confidence(conf_str),
        raw_text    = raw,
    }
end

local function format_others_block(prev_responses, convincing_count)
    local lines = {}
    local limit = math.min(#prev_responses, convincing_count)
    for i = 1, limit do
        local r = prev_responses[i]
        lines[#lines + 1] = string.format(
            "Agent %d:\n  Answer: %s\n  Confidence: %.2f\n  Explanation: %s",
            r.agent, r.answer, r.confidence, r.explanation)
    end
    return table.concat(lines, "\n\n")
end

local function resolve_agents(ctx)
    if ctx.agents ~= nil then
        require_non_empty_array(ctx.agents, "agents", "run")
        return ctx.agents, "agents"
    end
    if ctx.personas ~= nil then
        require_non_empty_array(ctx.personas, "personas", "run")
        local specs = {}
        for i, persona in ipairs(ctx.personas) do
            if type(persona) ~= "string" or persona == "" then
                error(string.format(
                    "reconcile.run: personas[%d] must be a non-empty string", i), 3)
            end
            specs[i] = { system = persona }
        end
        return specs, "personas"
    end
    error("reconcile.run: one of ctx.agents (paper-faithful) or ctx.personas (alt path) is REQUIRED", 3)
end

-- ─── Pure entries ───

--- Compute the calibrated voting weight f(p) for a confidence p ∈ [0,1].
--- Implements the §B.5 5-bucket scale verbatim from repo
--- `utils.py::trans_confidence`.
---@param args table { confidence }
---@return number
function M.confidence_to_weight(args)
    require_table(args, "args", "confidence_to_weight")
    require_number_in_range(args.confidence, "confidence", "confidence_to_weight", 0, 1)
    local p = args.confidence
    if p == 1.0 then return 1.0 end
    if p >= 0.9 then return 0.8 end
    if p >= 0.8 then return 0.5 end
    if p > 0.6 then return 0.3 end
    return 0.1
end

--- Compute the confidence-weighted argmax (§4 Phase 3 formula):
---   â = arg max_a Σ_i f(p_i) · 𝟙(a_i = a)
--- Ties broken by first-occurrence order in `responses`.
---@param args table { responses : array of {normalized, weight} }
---@return table { answer, weight, count, tally }
function M.compute_weighted_argmax(args)
    require_table(args, "args", "compute_weighted_argmax")
    require_non_empty_array(args.responses, "responses", "compute_weighted_argmax")

    local weight_by = {}
    local count_by = {}
    local first_idx_by = {}
    for i, r in ipairs(args.responses) do
        if type(r) ~= "table" or type(r.normalized) ~= "string"
            or type(r.weight) ~= "number" then
            error(string.format(
                "reconcile.compute_weighted_argmax: responses[%d] must be {normalized, weight}",
                i), 3)
        end
        local a = r.normalized
        if weight_by[a] == nil then
            weight_by[a] = 0
            count_by[a] = 0
            first_idx_by[a] = i
        end
        weight_by[a] = weight_by[a] + r.weight
        count_by[a] = count_by[a] + 1
    end

    local tally = {}
    for a, w in pairs(weight_by) do
        tally[#tally + 1] = {
            answer = a, weight = w, count = count_by[a],
            _first = first_idx_by[a],
        }
    end
    table.sort(tally, function(a, b)
        if a.weight ~= b.weight then return a.weight > b.weight end
        return a._first < b._first
    end)

    local winner = tally[1]
    local clean_tally = {}
    for _, t in ipairs(tally) do
        clean_tally[#clean_tally + 1] = {
            answer = t.answer, weight = t.weight, count = t.count,
        }
    end
    return {
        answer = winner.answer,
        weight = winner.weight,
        count  = winner.count,
        tally  = clean_tally,
    }
end

--- Check whether all agents agreed on the same normalized answer.
---@param args table { responses : array of {normalized} }
---@return boolean
function M.check_consensus(args)
    require_table(args, "args", "check_consensus")
    require_non_empty_array(args.responses, "responses", "check_consensus")
    local first = args.responses[1].normalized
    if type(first) ~= "string" then
        error("reconcile.check_consensus: responses[i].normalized must be a string", 3)
    end
    for i = 2, #args.responses do
        if args.responses[i].normalized ~= first then return false end
    end
    return true
end

--- Build the Phase 2 (discussion) prompt for one agent at round r > 0.
---@param args table { task, other_responses, convincing_count?, discussion_prompt?, system_prompt? }
---@return table { prompt, system }
function M.build_discussion_prompt(args)
    require_table(args, "args", "build_discussion_prompt")
    require_string(args.task, "task", "build_discussion_prompt")
    require_non_empty_array(args.other_responses, "other_responses", "build_discussion_prompt")

    local convincing = args.convincing_count or M._defaults.convincing_count
    local template = args.discussion_prompt or M.DEFAULT_DISCUSSION_PROMPT_TEMPLATE
    local system = args.system_prompt or M.DEFAULT_SYSTEM_PROMPT

    local others_text = format_others_block(args.other_responses, convincing)
    return {
        prompt = string.format(template, args.task, others_text),
        system = system,
    }
end

-- ─── Strategy entry ───

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    if type(ctx) ~= "table" then
        error("reconcile.run: ctx must be a table", 2)
    end
    if alc == nil then
        error("reconcile.run: alc host is not available", 2)
    end
    require_string(ctx.task, "task", "run")

    local agent_specs, path_kind = resolve_agents(ctx)
    local n_agents = #agent_specs
    local max_rounds = ctx.max_rounds or M._defaults.max_rounds
    local convincing = ctx.convincing_count or M._defaults.convincing_count
    local gen_tokens = ctx.gen_tokens or M._defaults.gen_tokens
    local temperature = ctx.temperature
    require_positive_int(max_rounds, "max_rounds", "run", 1)
    if convincing < 0 or math.floor(convincing) ~= convincing then
        error(string.format(
            "reconcile.run: convincing_count must be a non-negative integer, got %s",
            tostring(convincing)), 2)
    end
    require_positive_int(gen_tokens, "gen_tokens", "run", 1)
    local parse_fn = ctx.parse_fn or parse_agent_response

    local function build_llm_opts(spec)
        local opts = { max_tokens = gen_tokens }
        if temperature ~= nil then opts.temperature = temperature end
        if spec.system then opts.system = spec.system
        elseif ctx.system_prompt then opts.system = ctx.system_prompt
        else opts.system = M.DEFAULT_SYSTEM_PROMPT end
        if spec.model then opts.model = spec.model end
        return opts
    end

    local function dispatch_agent(spec, prompt)
        local raw = alc.llm(prompt, build_llm_opts(spec))
        require_string(raw, "agent response", "run")
        local parsed = parse_fn(raw)
        return parsed, raw
    end

    local history = {}
    local total_llm_calls = 0
    local consensus_reached = false
    local rounds_used = 0
    local last_round_responses = nil

    -- ─── Phase 1: Initial (round 0) ───
    alc.log("info", string.format(
        "reconcile: Phase 1 init (n=%d, %s path)", n_agents, path_kind))
    local round0 = {}
    for i = 1, n_agents do
        local spec = agent_specs[i]
        local init_prompt = string.format(
            ctx.init_prompt or M.DEFAULT_INIT_PROMPT_TEMPLATE,
            ctx.task)
        local parsed, raw = dispatch_agent(spec, init_prompt)
        total_llm_calls = total_llm_calls + 1
        local weight = M.confidence_to_weight({ confidence = parsed.confidence })
        round0[i] = {
            agent       = i,
            round       = 0,
            answer      = parsed.answer,
            explanation = parsed.explanation,
            confidence  = parsed.confidence,
            normalized  = normalize_answer(parsed.answer),
            weight      = weight,
            raw_text    = raw,
        }
    end
    history[1] = round0
    last_round_responses = round0
    rounds_used = 1

    if M.check_consensus({ responses = round0 }) then
        consensus_reached = true
    end

    -- ─── Phase 2: Discussion (rounds 1..R) ───
    if not consensus_reached then
        for r = 1, max_rounds do
            alc.log("info", string.format(
                "reconcile: Phase 2 round %d/%d", r, max_rounds))
            local cur = {}
            for i = 1, n_agents do
                local spec = agent_specs[i]
                -- "Others" = all responses from previous round excluding self.
                local others = {}
                for j = 1, n_agents do
                    if j ~= i then others[#others + 1] = last_round_responses[j] end
                end
                local pair = M.build_discussion_prompt({
                    task              = ctx.task,
                    other_responses   = others,
                    convincing_count  = convincing,
                    discussion_prompt = ctx.discussion_prompt,
                    system_prompt     = spec.system or ctx.system_prompt,
                })
                local parsed, raw = dispatch_agent(spec, pair.prompt)
                total_llm_calls = total_llm_calls + 1
                local weight = M.confidence_to_weight({ confidence = parsed.confidence })
                cur[i] = {
                    agent       = i,
                    round       = r,
                    answer      = parsed.answer,
                    explanation = parsed.explanation,
                    confidence  = parsed.confidence,
                    normalized  = normalize_answer(parsed.answer),
                    weight      = weight,
                    raw_text    = raw,
                }
            end
            history[r + 1] = cur
            last_round_responses = cur
            rounds_used = r + 1
            if M.check_consensus({ responses = cur }) then
                consensus_reached = true
                break
            end
        end
    end

    -- ─── Phase 3: Confidence-weighted vote (§4) ───
    local maj = M.compute_weighted_argmax({ responses = last_round_responses })

    alc.log("info", string.format(
        "reconcile: complete — rounds=%d, consensus=%s, winner=%q (weight=%.3f)",
        rounds_used, tostring(consensus_reached), maj.answer, maj.weight))

    ctx.result = {
        answer          = maj.answer,
        n_agents        = n_agents,
        rounds_used     = rounds_used,
        consensus       = consensus_reached,
        history         = history,
        tally           = maj.tally,
        total_llm_calls = total_llm_calls,
    }
    return ctx
end

---@type AlcSpec
M.spec = {
    entries = {
        confidence_to_weight = {
            args   = T.shape({
                confidence = T.number:describe("Self-reported confidence in [0,1]"),
            }, { open = true }),
            result = T.number:describe("Calibrated weight from §B.5 5-bucket scale"),
        },
        compute_weighted_argmax = {
            args   = T.shape({
                responses = T.array_of(T.shape({
                    normalized = T.string,
                    weight     = T.number,
                }, { open = true })),
            }, { open = true }),
            result = T.shape({
                answer = T.string,
                weight = T.number,
                count  = T.number,
                tally  = T.array_of(T.shape({
                    answer = T.string, weight = T.number, count = T.number,
                }, { open = true })),
            }, { open = true }),
        },
        check_consensus = {
            args   = T.shape({
                responses = T.array_of(T.shape({
                    normalized = T.string,
                }, { open = true })),
            }, { open = true }),
            result = T.boolean,
        },
        build_discussion_prompt = {
            args   = T.shape({
                task              = T.string,
                other_responses   = T.array_of(agent_response_shape),
                convincing_count  = T.number:is_optional(),
                discussion_prompt = T.string:is_optional(),
                system_prompt     = T.string:is_optional(),
            }, { open = true }),
            result = prompt_pair_shape,
        },
        run = {
            input  = run_input_shape,
            result = run_result_shape,
        },
    },
}

-- Test hooks
M._internal = {
    normalize_answer    = normalize_answer,
    coerce_confidence   = coerce_confidence,
    parse_agent_response = parse_agent_response,
    format_others_block = format_others_block,
    resolve_agents      = resolve_agents,
}

-- Self-decoration for ALC_SHAPE_CHECK=1 dev mode.
M.run                     = S.instrument(M, "run")
M.confidence_to_weight    = S.instrument(M, "confidence_to_weight")
M.compute_weighted_argmax = S.instrument(M, "compute_weighted_argmax")
M.check_consensus         = S.instrument(M, "check_consensus")
M.build_discussion_prompt = S.instrument(M, "build_discussion_prompt")

return M
