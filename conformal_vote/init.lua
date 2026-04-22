--- conformal_vote — Linear opinion pool + split conformal prediction
--- gate for safe multi-agent deliberation.
---
--- Implements the post-hoc decision layer from:
---   Wang, Xie, Wang, Gao, Yang, Li, Qiu, Han, Qiu, Huang, Zhu, Woo
---   "From Debate to Decision: Conformal Social Choice for Safe
---    Multi-Agent Deliberation" (arXiv:2604.07667, 2026-04-09)
---
--- Given N agents that each emit a verbalized probability distribution
--- π_i(y|x) over a fixed option set, the pkg performs:
---
---   Linear opinion pool:       P_social(y|x) = Σ_i w_i · π_i(y|x)
---   Nonconformity score:       s_nc(x, y)    = 1 - P_social(y|x)
---   Finite-sample quantile:    q̂ = sorted[⌈(n+1)(1-α)⌉]        (§4.3)
---   Prediction set:            C(x) = { y : P_social(y|x) ≥ 1 - q̂ }
---   Three-way decision (P. 3): |C|=1 ∧ p₁≥τ ∧ p₂<τ → commit
---                              |C|≥2 ∧ p₂≥τ        → escalate
---                              |C|=0 ∨ p₁<τ        → anomaly
---
--- Theorem 2 guarantees Pr[Y ∈ C(X)] ≥ 1-α in finite samples whenever
--- calibration and online rounds share the same aggregation weights and
--- the data is exchangeable. The calibrate entry therefore *pins* the
--- weights it used (defaulting to uniform 1/N) into its return value so
--- M.run can replay them, never letting online aggregation drift from
--- the calibrated weights.
---
--- Entry contract (see M.spec below):
---   calibrate   — pure, direct-args. returns { q_hat, tau, alpha, n, weights }
---   aggregate   — pure, direct-args. returns { [label] = p_social }
---   predict_set — pure, direct-args. returns { labels, top1, top1_prob, top2, top2_prob }
---   decide      — pure, direct-args. returns { action, selected }
---   run         — Strategy, ctx-threading. queries N agents via alc.llm.
---
--- Category: validation (alongside sprt, eval_guard, inverse_u).
--- The paper's informal "Governance" label describes the role; the
--- machine-readable category string follows the existing sibling pkgs.

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "conformal_vote",
    version = "0.1.0",
    description = "Linear opinion pool + split conformal prediction gate "
        .. "for multi-agent deliberation. Emits a three-way decision "
        .. "(commit / escalate / anomaly) per Proposition 3, with a "
        .. "finite-sample coverage guarantee Pr[Y ∈ C(X)] ≥ 1-α "
        .. "(Theorem 2). Calibration and online rounds share aggregation "
        .. "weights so exchangeability is preserved.",
    category = "validation",
}

-- Centralized defaults. Keep magic numbers here so no entry hard-codes
-- its own copy. `alpha = 0.05` matches the paper's primary setting
-- (Table 3); `gen_tokens = 400` matches sc's default; `max_retries = 0`
-- matches the paper's no-retry parse-fallback policy.
M._defaults = {
    alpha       = 0.05,
    gen_tokens  = 400,
    max_retries = 0,
}

-- ─── Shape definitions (local, for spec.entries) ───
--
-- pure entries (calibrate / aggregate / predict_set / decide) use
-- `args` (direct-args mode). Each accepts a single cfg table slot so
-- the public API reads like `M.calibrate({ ... })`.

local calibration_sample = T.shape({
    agent_probs = T.map_of(
        T.number,
        T.map_of(T.string, T.number)
    ):describe("{ [agent_idx] = { [label] = prob } } — per-agent verbalized distributions"),
    true_label  = T.string:describe("Ground-truth label for this calibration sample"),
}, { open = true })

local calibration_cfg = T.shape({
    calibration_samples = T.array_of(calibration_sample)
        :describe("Held-out calibration set (same distribution as online test)"),
    alpha   = T.number:is_optional()
        :describe("Miscoverage rate in (0, 1); default 0.05"),
    weights = T.table:is_optional()
        :describe("Per-agent aggregation weights (length N, Σw=1); default uniform 1/N"),
}, { open = true })

local calibration_result = T.shape({
    q_hat   = T.number:describe("Calibration quantile of nonconformity scores"),
    tau     = T.number:describe("1 - q_hat (prediction-set threshold)"),
    alpha   = T.number:describe("Miscoverage rate used at calibration time"),
    n       = T.number:describe("Calibration sample count"),
    weights = T.array_of(T.number)
        :describe("Pinned aggregation weights — run() must reuse these for exchangeability"),
}, { open = true })

local aggregate_cfg = T.shape({
    agent_probs = T.array_of(T.map_of(T.string, T.number))
        :describe("Array of per-agent distributions; index matches weights[i]"),
    weights = T.table:is_optional()
        :describe("Per-agent weights (length N, Σw=1); default uniform 1/N"),
}, { open = true })

local predict_set_cfg = T.shape({
    p_social = T.map_of(T.string, T.number)
        :describe("Aggregated distribution { [label] = prob }"),
    tau      = T.number:describe("Prediction-set threshold (1 - q_hat)"),
}, { open = true })

local prediction_set_result = T.shape({
    labels    = T.array_of(T.string)
        :describe("{ y : P_social(y|x) >= tau } (may be empty)"),
    top1      = T.string:is_optional()
        :describe("Argmax label (nil when p_social is empty)"),
    top1_prob = T.number:describe("Highest P_social value (0 when empty)"),
    top2      = T.string:is_optional()
        :describe("Second-ranked label (nil when |p_social| < 2)"),
    top2_prob = T.number:describe("Second-highest P_social value (0 when absent)"),
}, { open = true })

local decide_cfg = T.shape({
    prediction_set = prediction_set_result
        :describe("Output of M.predict_set"),
    tau = T.number:describe("Threshold used to build the prediction set"),
}, { open = true })

local decision_result = T.shape({
    action   = T.one_of({ "commit", "escalate", "anomaly" }),
    selected = T.string:is_optional()
        :describe("Committed label (nil unless action == 'commit')"),
}, { open = true })

-- run entry (Strategy / ctx-threading). `agents` is polymorphic
-- (string prompt | options-table) so we accept T.any at that slot; the
-- internal build_agent_prompt normalizes both shapes. `calibration` is
-- validated strictly — run() must consume the exact return struct from
-- M.calibrate, including the pinned `weights` field (exchangeability).
local run_calibration_input = T.shape({
    q_hat   = T.number,
    tau     = T.number,
    alpha   = T.number,
    n       = T.number,
    weights = T.table:describe("Pinned weights from calibrate; must be length N_agents"),
}, { open = true })

local run_input = T.shape({
    task          = T.string:describe("Task text presented to each agent"),
    options       = T.array_of(T.string):describe("Candidate label set"),
    calibration   = run_calibration_input,
    agents        = T.any:describe("Array of agent specs (prompt string or {prompt,system?,model?,temperature?,max_tokens?} table)"),
    gen_tokens    = T.number:is_optional()
        :describe("Max tokens for LLM generation (default: 400)"),
    -- Card IF (optimize pattern — optimize/init.lua:97-99)
    auto_card     = T.boolean:is_optional()
        :describe("Emit a Card on completion (default: false)"),
    card_pkg      = T.string:is_optional()
        :describe("Card pkg.name override (default: 'conformal_vote_<task_hash>')"),
    scenario_name = T.string:is_optional()
        :describe("Explicit scenario name for the emitted Card"),
}, { open = true })

---@type AlcSpec
M.spec = {
    entries = {
        calibrate = {
            args   = { calibration_cfg },
            result = calibration_result,
        },
        aggregate = {
            args   = { aggregate_cfg },
            result = T.map_of(T.string, T.number),
        },
        predict_set = {
            args   = { predict_set_cfg },
            result = prediction_set_result,
        },
        decide = {
            args   = { decide_cfg },
            result = decision_result,
        },
        run = {
            input  = run_input,
            result = "conformal_decided",
        },
    },
}

-- ─── Input validation helpers ───

local function validate_alpha(alpha, entry)
    if type(alpha) ~= "number" or alpha <= 0 or alpha >= 1 then
        error(string.format(
            "conformal_vote.%s: alpha must be a number in (0, 1), got %s",
            entry, tostring(alpha)), 3)
    end
end

-- Count 1-based dense array length for a table that may be either array
-- or map. Returns `nil` if the table has any non-integer or non-positive
-- integer key (signaling the caller passed a map instead of an array).
local function array_length(t)
    if type(t) ~= "table" then return nil end
    local n = 0
    for k, _ in pairs(t) do
        if type(k) ~= "number" or k < 1 or k ~= math.floor(k) then
            return nil
        end
        if k > n then n = k end
    end
    -- Verify density (no holes) so validate_weights treats weights
    -- sparsely-keyed with integer indices as malformed.
    for i = 1, n do
        if t[i] == nil then return nil end
    end
    return n
end

-- Validate a weights table against the expected agent count. When
-- weights is nil, returns a freshly-allocated uniform array of length
-- n_agents; otherwise validates length + Σw and returns a copy. Never
-- returns nil.
local function normalize_weights(weights, n_agents, entry)
    if n_agents <= 0 then
        error(string.format(
            "conformal_vote.%s: internal — n_agents must be positive, got %d",
            entry, n_agents), 3)
    end
    if weights == nil then
        local out = {}
        for i = 1, n_agents do out[i] = 1 / n_agents end
        return out
    end
    if type(weights) ~= "table" then
        error(string.format(
            "conformal_vote.%s: weights must be a table or nil, got %s",
            entry, type(weights)), 3)
    end
    local len = array_length(weights)
    if len == nil then
        error(string.format(
            "conformal_vote.%s: weights must be a 1-based dense array of numbers",
            entry), 3)
    end
    if len ~= n_agents then
        error(string.format(
            "conformal_vote.%s: weights length %d does not match agent count %d",
            entry, len, n_agents), 3)
    end
    local sum = 0
    for i = 1, len do
        local w = weights[i]
        if type(w) ~= "number" then
            error(string.format(
                "conformal_vote.%s: weights[%d] must be a number, got %s",
                entry, i, type(w)), 3)
        end
        if w < 0 then
            error(string.format(
                "conformal_vote.%s: weights[%d] must be non-negative, got %s",
                entry, i, tostring(w)), 3)
        end
        sum = sum + w
    end
    if math.abs(sum - 1) >= 1e-9 then
        error(string.format(
            "conformal_vote.%s: weights must sum to 1 (within 1e-9), got Σw = %s",
            entry, tostring(sum)), 3)
    end
    -- Return a defensive copy so callers cannot mutate the pinned
    -- weights we place on the calibrate return value.
    local out = {}
    for i = 1, len do out[i] = weights[i] end
    return out
end

-- Finite-sample conformal quantile. Expects a pre-sorted ascending
-- array `sorted` of nonconformity scores and a miscoverage rate
-- alpha ∈ (0, 1). Returns sorted[⌈(n+1)(1-α)⌉], or math.huge when the
-- index exceeds n (Angelopoulos & Bates, "Gentle Intro §2.3"). This
-- collapses to τ = -∞, making C(x) = full option set (safe default).
local function finite_sample_quantile(sorted, alpha)
    -- Internal invariant after sort: sorted must be a dense 1-based
    -- array of numbers. Assert (not error) because callers inside this
    -- module construct `sorted` themselves.
    assert(type(sorted) == "table",
        "internal: finite_sample_quantile sorted must be a table")
    local n = #sorted
    if n == 0 then
        error("conformal_vote.calibrate: no nonconformity scores to quantile", 3)
    end
    local idx = math.ceil((n + 1) * (1 - alpha))
    if idx > n then
        return math.huge
    end
    if idx < 1 then
        idx = 1
    end
    return sorted[idx]
end

-- ─── Public: aggregate ───

--- Linear opinion pool: P_social(y|x) = Σ_i w_i · π_i(y|x)
---
--- Takes an array of per-agent distributions (each a map { [label] =
--- prob }) plus an optional weight vector. When weights is nil, uniform
--- 1/N is used. The output union-key is the union of all input labels;
--- missing labels default to 0 in that agent's contribution.
---
---@param cfg table { agent_probs, weights? }
---@return table p_social  { [label] = number }
function M.aggregate(cfg)
    if type(cfg) ~= "table" then
        error("conformal_vote.aggregate: cfg must be a table", 2)
    end
    local agent_probs = cfg.agent_probs
    if type(agent_probs) ~= "table" then
        error("conformal_vote.aggregate: cfg.agent_probs must be a table", 2)
    end
    local n_agents = array_length(agent_probs)
    if n_agents == nil or n_agents == 0 then
        error("conformal_vote.aggregate: cfg.agent_probs must be a 1-based "
            .. "non-empty dense array", 2)
    end
    for i = 1, n_agents do
        if type(agent_probs[i]) ~= "table" then
            error(string.format(
                "conformal_vote.aggregate: agent_probs[%d] must be a map "
                    .. "{[label]=prob}, got %s",
                i, type(agent_probs[i])), 2)
        end
    end
    local weights = normalize_weights(cfg.weights, n_agents, "aggregate")

    local p_social = {}
    for i = 1, n_agents do
        local w = weights[i]
        for y, p in pairs(agent_probs[i]) do
            if type(y) ~= "string" then
                error(string.format(
                    "conformal_vote.aggregate: agent_probs[%d] key must be "
                        .. "string label, got %s",
                    i, type(y)), 2)
            end
            if type(p) ~= "number" then
                error(string.format(
                    "conformal_vote.aggregate: agent_probs[%d][%q] must be "
                        .. "number, got %s",
                    i, tostring(y), type(p)), 2)
            end
            p_social[y] = (p_social[y] or 0) + w * p
        end
    end
    return p_social
end

-- ─── Public: predict_set ───

--- Build the prediction set C(x) = { y : p_social[y] >= tau } and
--- surface top-1 / top-2 labels + probabilities for the decision rule.
--- Ties are broken by insertion order into a scratch array (stable
--- under table.sort's behaviour on Lua 5.4 since we compare only by
--- probability; equal probabilities preserve scan order).
---
---@param cfg table { p_social, tau }
---@return table { labels, top1, top1_prob, top2, top2_prob }
function M.predict_set(cfg)
    if type(cfg) ~= "table" then
        error("conformal_vote.predict_set: cfg must be a table", 2)
    end
    if type(cfg.p_social) ~= "table" then
        error("conformal_vote.predict_set: cfg.p_social must be a table", 2)
    end
    if type(cfg.tau) ~= "number" then
        error(string.format(
            "conformal_vote.predict_set: cfg.tau must be a number, got %s",
            type(cfg.tau)), 2)
    end

    -- Collect { label, prob } pairs, then sort by prob desc.
    local pairs_list = {}
    for y, p in pairs(cfg.p_social) do
        if type(y) ~= "string" then
            error(string.format(
                "conformal_vote.predict_set: p_social key must be string label, "
                    .. "got %s", type(y)), 2)
        end
        if type(p) ~= "number" then
            error(string.format(
                "conformal_vote.predict_set: p_social[%q] must be number, got %s",
                tostring(y), type(p)), 2)
        end
        pairs_list[#pairs_list + 1] = { y = y, p = p }
    end
    table.sort(pairs_list, function(a, b)
        if a.p ~= b.p then return a.p > b.p end
        return a.y < b.y  -- deterministic tiebreak on label
    end)

    local labels = {}
    for _, pr in ipairs(pairs_list) do
        if pr.p >= cfg.tau then
            labels[#labels + 1] = pr.y
        end
    end

    local top1, top1_prob = nil, 0
    local top2, top2_prob = nil, 0
    if pairs_list[1] ~= nil then
        top1 = pairs_list[1].y
        top1_prob = pairs_list[1].p
    end
    if pairs_list[2] ~= nil then
        top2 = pairs_list[2].y
        top2_prob = pairs_list[2].p
    end

    return {
        labels    = labels,
        top1      = top1,
        top1_prob = top1_prob,
        top2      = top2,
        top2_prob = top2_prob,
    }
end

-- ─── Public: decide ───

--- Three-way decision per Proposition 3.
---
--- |C|=1 ∧ p₁ ≥ τ ∧ p₂ < τ  → commit   (singleton automation)
--- |C| ≥ 2 ∧ p₂ ≥ τ         → escalate (ambiguous)
--- |C|=0 (p₁ < τ)           → anomaly
--- Edge: |C|=1 ∧ p₁ < τ     → anomaly (Proposition 3 edge case —
---                                     stale labels in pset vs tau)
---
---@param cfg table { prediction_set, tau }
---@return table { action, selected }
function M.decide(cfg)
    if type(cfg) ~= "table" then
        error("conformal_vote.decide: cfg must be a table", 2)
    end
    local pset = cfg.prediction_set
    if type(pset) ~= "table" or type(pset.labels) ~= "table" then
        error("conformal_vote.decide: cfg.prediction_set must be a "
            .. "predict_set_result table", 2)
    end
    if type(cfg.tau) ~= "number" then
        error(string.format(
            "conformal_vote.decide: cfg.tau must be a number, got %s",
            type(cfg.tau)), 2)
    end
    local top1_prob = pset.top1_prob or 0
    local top2_prob = pset.top2_prob or 0
    local n_labels = #pset.labels
    local tau = cfg.tau

    if n_labels == 0 then
        return { action = "anomaly", selected = nil }
    end
    if n_labels == 1 then
        -- Edge case: singleton pset can still fall below τ when the
        -- caller built it with a newer τ than the one that produced
        -- `labels`. Treat as anomaly per Proposition 3.
        if top1_prob < tau then
            return { action = "anomaly", selected = nil }
        end
        -- Commit path requires the runner-up strictly below τ so we
        -- actually have a unique singleton.
        if top2_prob < tau then
            return { action = "commit", selected = pset.top1 }
        end
        -- |C|=1 but top2_prob >= τ is a contradiction (would have
        -- produced |C|≥2). Escalate defensively.
        return { action = "escalate", selected = nil }
    end
    -- n_labels >= 2 → escalate (ambiguous)
    return { action = "escalate", selected = nil }
end

-- ─── Public: calibrate ───

--- Split conformal calibration.
---
--- For each calibration sample:
---   p_social_i = aggregate(agent_probs_i, weights)
---   s_nc_i     = 1 - p_social_i[true_label_i]
--- Then sort s_nc ascending and take sorted[⌈(n+1)(1-α)⌉] as q̂.
---
--- Returns a struct pinning the weights used so M.run can reuse them
--- verbatim (see Theorem 2 exchangeability requirement). Even when the
--- caller passes `weights = nil`, the return includes the materialized
--- uniform array — never nil.
---
---@param cfg table { calibration_samples, alpha?, weights? }
---@return table { q_hat, tau, alpha, n, weights }
function M.calibrate(cfg)
    if type(cfg) ~= "table" then
        error("conformal_vote.calibrate: cfg must be a table", 2)
    end
    local samples = cfg.calibration_samples
    if type(samples) ~= "table" then
        error("conformal_vote.calibrate: cfg.calibration_samples must be a table", 2)
    end
    local n = array_length(samples)
    if n == nil or n == 0 then
        error("conformal_vote.calibrate: cfg.calibration_samples must be a "
            .. "1-based non-empty dense array", 2)
    end
    local alpha = cfg.alpha
    if alpha == nil then alpha = M._defaults.alpha end
    validate_alpha(alpha, "calibrate")

    -- Determine N_agents from the first sample, then require subsequent
    -- samples to match. `agent_probs` is keyed by integer agent_idx so
    -- array_length on the map after normalization is used below.
    local first = samples[1]
    if type(first) ~= "table" or type(first.agent_probs) ~= "table" then
        error("conformal_vote.calibrate: calibration_samples[1].agent_probs "
            .. "must be a table", 2)
    end
    local n_agents = array_length(first.agent_probs)
    if n_agents == nil or n_agents == 0 then
        error("conformal_vote.calibrate: calibration_samples[1].agent_probs "
            .. "must be a 1-based dense array of per-agent distributions", 2)
    end
    local weights = normalize_weights(cfg.weights, n_agents, "calibrate")

    local scores = {}
    for i = 1, n do
        local sample = samples[i]
        if type(sample) ~= "table" then
            error(string.format(
                "conformal_vote.calibrate: calibration_samples[%d] must be a table",
                i), 2)
        end
        if type(sample.agent_probs) ~= "table" then
            error(string.format(
                "conformal_vote.calibrate: calibration_samples[%d].agent_probs "
                    .. "must be a table", i), 2)
        end
        if type(sample.true_label) ~= "string" then
            error(string.format(
                "conformal_vote.calibrate: calibration_samples[%d].true_label "
                    .. "must be a string, got %s", i, type(sample.true_label)), 2)
        end
        local sample_n = array_length(sample.agent_probs)
        if sample_n ~= n_agents then
            error(string.format(
                "conformal_vote.calibrate: calibration_samples[%d] has %d "
                    .. "agents, expected %d (must match sample 1)",
                i, sample_n or -1, n_agents), 2)
        end
        -- Build the positional agent_probs array expected by aggregate.
        local ap_list = {}
        for j = 1, n_agents do ap_list[j] = sample.agent_probs[j] end
        local p_social = M.aggregate({ agent_probs = ap_list, weights = weights })
        local p_true = p_social[sample.true_label] or 0
        scores[i] = 1 - p_true
    end

    table.sort(scores)
    local q_hat = finite_sample_quantile(scores, alpha)
    -- tau = 1 - q_hat. When q_hat is +∞ (index > n) we pin tau = -∞
    -- so C(x) encompasses every candidate (the correct safe fallback).
    local tau
    if q_hat == math.huge then
        tau = -math.huge
    else
        tau = 1 - q_hat
    end

    return {
        q_hat   = q_hat,
        tau     = tau,
        alpha   = alpha,
        n       = n,
        weights = weights,
    }
end

-- ─── Private helpers: run ───

-- Best-effort warn helper. Prefers alc.log.warn; falls back to
-- stderr. Never silent-drops (issue §4.6 parse-fallback rate must be
-- observable).
local function warn(msg)
    if type(alc) == "table" and type(alc.log) == "table"
        and type(alc.log.warn) == "function"
    then
        alc.log.warn(msg)
        return
    end
    -- Common alc variant: alc.log(level, msg)
    if type(alc) == "table" and type(alc.log) == "function" then
        local ok = pcall(alc.log, "warn", msg)
        if ok then return end
    end
    io.stderr:write("[conformal_vote] " .. tostring(msg) .. "\n")
end

-- Render the option list as "A, B, C, D" regardless of whether it is
-- provided as a dense array of strings.
local function render_options(options)
    local parts = {}
    for i = 1, #options do parts[i] = tostring(options[i]) end
    return table.concat(parts, ", ")
end

-- Build the per-agent prompt + LLM opts. agent_spec is either a plain
-- prompt string or a table { prompt, system?, model?, temperature?,
-- max_tokens? }. Returns the final prompt text and the opts table to
-- hand to alc.llm. Missing `max_tokens` falls back to `default_tokens`.
local function build_agent_prompt(task, options, agent_spec, default_tokens)
    if type(task) ~= "string" then
        error("conformal_vote.run: ctx.task must be a string", 3)
    end
    if type(options) ~= "table" or #options == 0 then
        error("conformal_vote.run: ctx.options must be a non-empty array", 3)
    end
    local opts_list = render_options(options)
    local agent_prompt, system, model, temperature, max_tokens
    if type(agent_spec) == "string" then
        agent_prompt = agent_spec
    elseif type(agent_spec) == "table" then
        agent_prompt = agent_spec.prompt
        system       = agent_spec.system
        model        = agent_spec.model
        temperature  = agent_spec.temperature
        max_tokens   = agent_spec.max_tokens
        if type(agent_prompt) ~= "string" then
            error("conformal_vote.run: agent table must set `prompt` string", 3)
        end
    else
        error("conformal_vote.run: agents[i] must be a string or a table", 3)
    end

    local prompt = string.format(
        [[%s

Task: %s
Options: %s

Return a probability distribution over the options reflecting your
belief. Probabilities must be non-negative and sum to 1. Use the
following strict format:

<reasoning>
(one or two short sentences of justification)
</reasoning>
<answer>
%s
</answer>

Each line inside <answer> must be of the form `LABEL: 0.XX` (one line
per option). Only the listed options are valid labels.]],
        agent_prompt,
        task,
        opts_list,
        -- Inline example rendered in the prompt for label anchoring.
        (function()
            local lines = {}
            for i = 1, #options do
                lines[i] = tostring(options[i]) .. ": 0." .. string.rep("X", 2)
            end
            return table.concat(lines, "\n")
        end)()
    )

    local llm_opts = {
        system = system
            or "You are a careful probabilistic reasoner. Output probabilities that sum to 1 over the provided options.",
        max_tokens = max_tokens or default_tokens,
    }
    if model ~= nil then llm_opts.model = model end
    if temperature ~= nil then llm_opts.temperature = temperature end
    return prompt, llm_opts
end

-- Tolerant parser for verbalized probabilities. Looks for `LABEL: 0.XX`
-- (and `LABEL = 0.XX`) lines anywhere in the raw text. Falls back to
-- uniform over `options` when nothing parses or the sum is zero.
-- Missing labels in the parse are filled with zeros; the result is then
-- L1-normalized so Σ p_i = 1. Returns (parsed_map, parse_failed_bool).
local function parse_probabilities(raw, options)
    if type(options) ~= "table" or #options == 0 then
        error("conformal_vote.run: options must be a non-empty array", 3)
    end
    local n = #options
    local option_set = {}
    for i = 1, n do option_set[options[i]] = true end

    -- Strip <answer>...</answer> if present; otherwise scan the whole
    -- string. We match "LABEL<sep>NUMBER" where NUMBER accepts 0.5 /
    -- .5 / 50% / 1 forms. Case-insensitive label match against the
    -- canonical option strings.
    local body = raw
    if type(body) == "string" then
        local s, e = body:find("<answer>(.-)</answer>")
        if s and e then body = body:sub(s, e) end
    else
        body = tostring(raw or "")
    end

    local parsed = {}
    local any = false
    -- Iterate line-by-line so the same option stated twice on different
    -- lines does not double-count (keep first).
    for line in body:gmatch("[^\n]+") do
        -- Pattern: optional leading chars, LABEL (alnum/underscore/dash),
        -- then `:` or `=`, whitespace, number (with optional decimal or %).
        local lbl, num = line:match("([%w_%-]+)%s*[:=]%s*([%d%.]+)")
        if lbl and num then
            local p = tonumber(num)
            if p ~= nil then
                -- Handle percentage form: if the number follows a `%`
                -- sign in the original line, divide by 100.
                if line:match("[:=]%s*" .. num .. "%s*%%") then
                    p = p / 100
                end
                -- Exact match against option set; fall back to
                -- case-insensitive lookup.
                local key = nil
                if option_set[lbl] then
                    key = lbl
                else
                    local lower = lbl:lower()
                    for i = 1, n do
                        if options[i]:lower() == lower then
                            key = options[i]
                            break
                        end
                    end
                end
                if key ~= nil and parsed[key] == nil and p >= 0 then
                    parsed[key] = p
                    any = true
                end
            end
        end
    end

    if not any then
        -- uniform fallback
        local out = {}
        for i = 1, n do out[options[i]] = 1 / n end
        return out, true
    end

    -- Fill missing labels with 0 and sum.
    local sum = 0
    for i = 1, n do
        if parsed[options[i]] == nil then
            parsed[options[i]] = 0
        end
        sum = sum + parsed[options[i]]
    end

    if sum <= 0 then
        local out = {}
        for i = 1, n do out[options[i]] = 1 / n end
        return out, true
    end

    -- Normalize so Σ = 1 exactly. This survives cases where the LLM
    -- emits near-sum probabilities (e.g. 0.3/0.3/0.3 totals 0.9).
    for i = 1, n do
        parsed[options[i]] = parsed[options[i]] / sum
    end
    return parsed, false
end

-- Emit a Card following the optimize pkg Two-Tier Content Policy
-- (optimize/init.lua:174-217). Tier 1 lives in the Card body, Tier 2
-- in samples.jsonl via alc.card.write_samples. Returns the card_id
-- (string) or nil when alc.card is not reachable (auto_card requested
-- but the runtime does not provide the Card API).
local function emit_card(ctx, result, per_agent_list)
    if type(alc) ~= "table" or type(alc.card) ~= "table"
        or type(alc.card.create) ~= "function"
    then
        warn("conformal_vote.run: alc.card.create unavailable; skipping Card emit")
        return nil
    end
    local task_hash
    if type(alc.hash) == "function" then
        local ok, h = pcall(alc.hash, ctx.task or "")
        if ok and type(h) == "string" and #h >= 8 then
            task_hash = h:sub(1, 8)
        end
    end
    if task_hash == nil then
        task_hash = tostring(os.time()):sub(-8)
    end
    local pkg_name = ctx.card_pkg or ("conformal_vote_" .. task_hash)

    local card = alc.card.create({
        pkg      = { name = pkg_name },
        scenario = { name = ctx.scenario_name or "unknown" },
        params   = {
            alpha   = ctx.calibration.alpha,
            weights = ctx.calibration.weights,
            n_cal   = ctx.calibration.n,
        },
        stats    = {
            action         = result.action,
            coverage_level = result.coverage_level,
            selected_label = result.selected,
        },
        conformal_vote = {
            action          = result.action,
            selected        = result.selected,
            prediction_set  = result.prediction_set,
            q_hat           = result.q_hat,
            tau             = result.tau,
            p_social        = result.p_social,
            total_llm_calls = result.total_llm_calls,
            n_agents        = #ctx.agents,
            n_options       = #ctx.options,
        },
    })

    if type(card) ~= "table" or card.card_id == nil then
        warn("conformal_vote.run: alc.card.create returned no card_id")
        return nil
    end

    if per_agent_list and #per_agent_list > 0
        and type(alc.card.write_samples) == "function"
    then
        local ok, err = pcall(alc.card.write_samples, card.card_id, per_agent_list)
        if not ok then
            warn("conformal_vote.run: alc.card.write_samples failed: " .. tostring(err))
        end
    end

    return card.card_id
end

-- ─── Public: run ───

--- Online round: query N agents, aggregate with the calibrated
--- weights, emit prediction set, three-way decide, optionally emit a
--- Card. Theorem 2 exchangeability requires the exact same weights used
--- during calibration — we read ctx.calibration.weights and pass it
--- through to M.aggregate (no uniform fallback here, even when weights
--- look uniform).
---
---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    if type(ctx) ~= "table" then
        error("conformal_vote.run: ctx must be a table", 2)
    end
    if type(ctx.task) ~= "string" then
        error("conformal_vote.run: ctx.task is required", 2)
    end
    if type(ctx.options) ~= "table" or #ctx.options == 0 then
        error("conformal_vote.run: ctx.options is required (non-empty array)", 2)
    end
    if type(ctx.calibration) ~= "table" then
        error("conformal_vote.run: ctx.calibration is required", 2)
    end
    local cal = ctx.calibration
    if type(cal.tau) ~= "number" then
        error("conformal_vote.run: ctx.calibration.tau must be a number", 2)
    end
    if type(cal.alpha) ~= "number" then
        error("conformal_vote.run: ctx.calibration.alpha must be a number", 2)
    end
    if type(cal.q_hat) ~= "number" then
        error("conformal_vote.run: ctx.calibration.q_hat must be a number", 2)
    end
    if type(cal.weights) ~= "table" then
        error("conformal_vote.run: ctx.calibration.weights is required "
            .. "(returned by M.calibrate). Do not uniform-hardcode here — "
            .. "calibration and run must share weights (Theorem 2).", 2)
    end
    if type(ctx.agents) ~= "table" or #ctx.agents == 0 then
        error("conformal_vote.run: ctx.agents is required (non-empty array)", 2)
    end

    local n_agents = #ctx.agents
    local gen_tokens = ctx.gen_tokens or M._defaults.gen_tokens
    local total_llm_calls = 0
    local parse_failures = 0

    local agent_probs = {}
    local per_agent_list = {}

    for i = 1, n_agents do
        local prompt, llm_opts = build_agent_prompt(
            ctx.task, ctx.options, ctx.agents[i], gen_tokens
        )
        if type(alc) ~= "table" or type(alc.llm) ~= "function" then
            error("conformal_vote.run: alc.llm is required at runtime", 2)
        end
        local raw = alc.llm(prompt, llm_opts)
        total_llm_calls = total_llm_calls + 1
        local probs, failed = parse_probabilities(raw, ctx.options)
        if failed then
            parse_failures = parse_failures + 1
            warn(string.format(
                "conformal_vote.run: agent %d response parse failed, using uniform fallback",
                i))
        end
        agent_probs[i] = probs
        per_agent_list[i] = {
            agent_idx     = i,
            raw_response  = raw,
            parsed_probs  = probs,
            parse_failed  = failed,
        }
    end

    -- Exchangeability: reuse pinned weights from calibrate. Never
    -- re-normalize or substitute uniform here.
    local p_social = M.aggregate({
        agent_probs = agent_probs,
        weights     = cal.weights,
    })
    local pset = M.predict_set({ p_social = p_social, tau = cal.tau })
    local decision = M.decide({ prediction_set = pset, tau = cal.tau })

    ctx.result = {
        action          = decision.action,
        selected        = decision.selected,
        prediction_set  = pset.labels,
        p_social        = p_social,
        coverage_level  = 1 - cal.alpha,
        q_hat           = cal.q_hat,
        tau             = cal.tau,
        total_llm_calls = total_llm_calls,
        parse_failures  = parse_failures,
    }

    if ctx.auto_card then
        local card_id = emit_card(ctx, ctx.result, per_agent_list)
        if card_id ~= nil then
            ctx.result.card_id = card_id
            if type(alc) == "table" and type(alc.log) == "function" then
                pcall(alc.log, "info",
                    "conformal_vote: card emitted — " .. tostring(card_id))
            end
        end
    end

    return ctx
end

-- ─── Test hooks ───
M._internal = {
    finite_sample_quantile = finite_sample_quantile,
    normalize_weights      = normalize_weights,
    array_length           = array_length,
    parse_probabilities    = parse_probabilities,
    build_agent_prompt     = build_agent_prompt,
    emit_card              = emit_card,
}

-- ─── Malli-style self-decoration (per-entry) ───
-- Order matches issue §5.1-5.5.
M.calibrate   = S.instrument(M, "calibrate")
M.aggregate   = S.instrument(M, "aggregate")
M.predict_set = S.instrument(M, "predict_set")
M.decide      = S.instrument(M, "decide")
M.run         = S.instrument(M, "run")

return M
