--- moa — Mixture-of-Agents (Wang 2024) — L-layer, n-proposer aggregation
---
--- ## Primary citation
---
--- Wang, J., Wang, J., Athiwaratkun, B., Zhang, C., & Zou, J. (2024).
--- "Mixture-of-Agents Enhances Large Language Model Capabilities".
--- arXiv:2406.04692.
--- https://arxiv.org/abs/2406.04692
---
--- ## Algorithm (Wang 2024 §2.2)
---
--- Layered aggregation. For each layer i, n proposer agents A_{i,1..n}
--- generate responses to the current input x_i, and an aggregator ⊕
--- synthesizes them into y_i, which becomes the next layer's input:
---
--- ```
---   y_i     = ⊕_{j=1}^{n}[A_{i,j}(x_i)] + x_1
---   x_{i+1} = y_i
--- ```
---
--- where ⊕ denotes applying the **Aggregate-and-Synthesize** prompt
--- (Table 1) to the n proposer outputs, and `+` is text concatenation.
---
--- The default MoA configuration runs **L=3 layers** with **n=6 proposers
--- per layer** (Wang 2024 §3 main experiment). MoA-Lite uses **L=2** for
--- cost efficiency. The final layer's aggregator output is the answer.
---
--- ## Defaults (Wang 2024 §3)
---
--- | Symbol     | Value | Source                                              |
--- |------------|-------|-----------------------------------------------------|
--- | L          | 3     | Wang §3 "We use 3 MoA layers"                       |
--- | n          | 6     | Wang §3 main exp uses 6 open-source proposers       |
--- | temp       | 0.7   | Wang §3 main config does not state a temperature    |
--- |            |       | for the layered MoA run. 0.7 is the only numeric    |
--- |            |       | value §3 names (single-proposer ablation row); pkg  |
--- |            |       | uses 0.7 to anchor the default to that one named    |
--- |            |       | value rather than an implementer-chosen number.     |
--- | max_tokens | 2048  | implementation choice — paper does not specify.     |
--- |            |       | Provenance: AS_PROMPT requires synthesizing all     |
--- |            |       | proposer outputs, so a larger budget than           |
--- |            |       | per-proposer is required by construction.           |
---
--- The **AS_PROMPT_TEMPLATE** (Aggregate-and-Synthesize) is a Lua string
--- literal identical to Wang 2024 Table 1's English text (punctuation /
--- capitalization / line breaks all match; the only transformation is
--- the Python `{}` placeholder rendered as Lua `%s`).
---
--- ## Proposer models (paper main experiment, Wang 2024 §3)
---
--- The main MoA experiment uses these 6 open-source proposers (all
--- accessible via Together AI):
---
---   - Qwen1.5-110B-Chat
---   - Qwen1.5-72B-Chat
---   - WizardLM-8x22B
---   - LLaMA-3-70B-Instruct
---   - Mixtral-8x22B-v0.1
---   - dbrx-instruct
---
--- These models are paper-explicit choices for reproducing Wang 2024
--- results, but they are NOT hard-coded by this pkg — the caller MUST
--- supply `proposers` (REQUIRED extension point). Hard-coding 6 specific
--- Together AI model IDs would bind the pkg to a specific API tier and
--- exclude OSS / local-model callers.
---
--- ## Entry contract
---
--- See `M.spec` below for the formal machine-readable contract:
---
--- - `build_proposer_prompt`   — pure, direct-args. returns { prompt, system }
--- - `build_aggregator_prompt` — pure, direct-args. returns { prompt, system }
--- - `run`                     — Strategy, ctx-threading. orchestrates L · n + L LLM calls
---
--- Two pure helpers are LLM-independent and unit-testable. `run` is the
--- only LLM-mediated entry.
---
--- ## Caveats
---
--- ### Required ctx fields
---
--- - `ctx.task` (string) — the user query or problem statement.
--- - One of `ctx.proposers` or `ctx.personas`:
---   - `ctx.proposers` (array) follows Wang §3's multi-model main
---     config: each entry is `{ model = string [, system = string] }`.
---     One LLM call is issued per proposer per layer.
---   - `ctx.personas` (array of strings) is a single-model rotation
---     path outside Wang §3's setup; one model is reused while only
---     the system prompt rotates per proposer. Convenient for OSS
---     callers without 6 distinct models, but sacrifices the paper's
---     distinct-model diversity property.
---
--- ### Knobs that affect the paper's effect guarantee
---
--- Overriding the layered structure or the Aggregate-and-Synthesize
--- prompt template moves away from Wang §3's main configuration, so the
--- paper's claim no longer transfers directly:
---
--- - `ctx.n_layers` (number ≥ 1) — overrides L = 3 (Wang §3 "We use
---   3 MoA layers").
--- - `ctx.aggregator_prompt` (string template) — overrides
---   `AS_PROMPT_TEMPLATE`; once replaced the caller is responsible for
---   keeping ⊕ semantics consistent with Wang Table 1.
---
--- ### Optional caller knobs (implementation choices)
---
--- These knobs are implementation choices because the paper does not
--- specify them or specifies only an ablation value; tuning them does
--- not invalidate the paper's claim:
---
--- - `ctx.temperature` (number) — per-LLM temperature.
--- - `ctx.proposer_tokens` (number) — max tokens per proposer.
--- - `ctx.aggregator_tokens` (number) — max tokens per aggregator.
--- - `ctx.proposer_prompt` (string template) — overrides the proposer
---   body wording.
--- - `ctx.system_prompt` (string) — overrides the proposer system
---   prompt.
---
--- ### Stability tier
---
--- - stable: `n_layers`, `temperature`, `proposer_tokens`,
---   `aggregator_tokens`.
--- - v2-opt-in: `proposer_prompt`, `aggregator_prompt`, `system_prompt`
---   (template format may evolve in future versions).
--- - experimental: `personas` (single-model fallback; paper guarantee
---   not held).
---
--- ## Comparison with related packages
---
--- vs `panel` (sequential multi-role discussion): panel uses heterogeneous
--- caller-supplied roles per turn; one model per turn. moa runs n
--- proposers in parallel and applies an explicit Aggregate-and-Synthesize
--- step.
---
--- vs `dmad` (Du 2023 Multi-Agent Debate): dmad has N agents debating
--- (each agent sees others' previous-round answers) for R rounds and
--- aggregates by majority vote. moa is layered hierarchical aggregation
--- with an explicit synthesizer prompt at each layer boundary.
---
--- vs `sc` (Self-Consistency, Wang 2022): sc samples N independent paths
--- from one model with majority voting. moa uses N distinct models /
--- personas and an LLM-as-judge aggregator at each layer.

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "moa",
    version = "0.2.0",
    description = "Mixture-of-Agents (Wang 2024) — L-layer × n-proposer aggregation with Aggregate-and-Synthesize",
    category = "aggregation",
    alc_shapes_compat = "^0.25",
}

-- Centralized defaults per Wang 2024 §3.
--   n_layers          = 3     (L) "We use 3 MoA layers" (§3 main config)
--   n_proposers       = 6     (L) main exp uses 6 open-source proposers
--                                 (caller must supply; this number is
--                                 reference-only, REQUIRED extension point)
--   temperature       = 0.7   (X) paper §3 reports 0.7 only for single-
--                                 proposer ablation; main exp not stated.
--                                 Default chosen to match the one
--                                 stated paper value.
--   proposer_tokens   = 512   (X) infrastructure, paper not specified.
--   aggregator_tokens = 2048  (X) infrastructure, larger to accommodate
--                                 synthesizing n proposer outputs.
M._defaults = {
    n_layers          = 3,
    n_proposers       = 6,
    temperature       = 0.7,
    proposer_tokens   = 512,
    aggregator_tokens = 2048,
}

-- (L) Aggregate-and-Synthesize prompt — string literal identical to
-- Wang 2024 Table 1 (only `%s` substitutes the Python `{}` placeholder).
M.AS_PROMPT_TEMPLATE = "You have been provided with a set of responses from various open-source models to the latest user query. Your task is to synthesize these responses into a single, high-quality response. It is crucial to critically evaluate the information provided in these responses, recognizing that some of it may be biased or incorrect. Your response should not simply replicate the given answers but should offer a refined, accurate, and comprehensive reply to the instruction. Ensure your response is well-structured, coherent, and adheres to the highest standards of accuracy and reliability.\n\nResponses from models:\n%s"

-- (X) Default proposer system prompt. Paper does not specify a system
-- prompt for proposers (each proposer is a separate model with its own
-- system style). When a single-model `personas` fallback is used, the
-- per-persona string overrides this default.
M.DEFAULT_PROPOSER_SYSTEM = "You are a helpful, accurate assistant. Respond to the user's query thoroughly."

-- ─── Shape declarations ───

local prompt_pair_shape = T.shape({
    prompt = T.string:describe("LLM user prompt"),
    system = T.string:describe("LLM system prompt"),
}, { open = true })

local proposer_spec_shape = T.shape({
    model  = T.string:is_optional()
        :describe("Caller-supplied model identifier (semantic, opaque to pkg)"),
    system = T.string:is_optional()
        :describe("Per-proposer system prompt override"),
}, { open = true })

local proposer_response_shape = T.shape({
    proposer = T.number:describe("1-based proposer index j"),
    model    = T.string:is_optional():describe("Echo of caller-supplied model id"),
    text     = T.string:describe("LLM output"),
}, { open = true })

local layer_record_shape = T.shape({
    layer        = T.number:describe("1-based layer index i"),
    proposers    = T.array_of(proposer_response_shape)
        :describe("Per-proposer outputs at this layer"),
    aggregated   = T.string:describe("Aggregator (⊕) output for this layer"),
}, { open = true })

local proposer_input_shape = T.shape({
    task            = T.string:describe("Problem statement (required)"),
    aggregated_prev = T.string:is_optional()
        :describe("Aggregated output from previous layer (omit at layer 1)"),
    proposer_prompt = T.string:is_optional():describe("Override proposer template (implementation choice)"),
    system_prompt   = T.string:is_optional():describe("Override proposer system prompt (implementation choice)"),
}, { open = true })

local aggregator_input_shape = T.shape({
    proposer_responses = T.array_of(T.string)
        :describe("This layer's n proposer outputs (non-empty)"),
    aggregator_prompt  = T.string:is_optional()
        :describe("Override AS_PROMPT_TEMPLATE; replacing it drops the paper's effect guarantee"),
}, { open = true })

local run_input_shape = T.shape({
    task              = T.string:describe("Problem statement (required)"),
    proposers         = T.array_of(proposer_spec_shape):is_optional()
        :describe("Multi-model PATH (Wang §3 main config): array of proposer specs; each layer reuses the same list"),
    personas          = T.array_of(T.string):is_optional()
        :describe("Single-model rotation PATH (outside Wang §3 main config): array of system-prompt strings"),
    n_layers          = T.number:is_optional()
        :describe("Number of layers L (default: " .. M._defaults.n_layers .. " per Wang §3 \"We use 3 MoA layers\")"),
    temperature       = T.number:is_optional()
        :describe("LLM temperature (default: " .. M._defaults.temperature .. "; implementation choice — Wang §3 main config does not state a value, 0.7 is the only numeric value §3 names in the single-proposer ablation row)"),
    proposer_tokens   = T.number:is_optional()
        :describe("Max tokens per proposer (default: " .. M._defaults.proposer_tokens .. "; implementation choice — paper does not specify)"),
    aggregator_tokens = T.number:is_optional()
        :describe("Max tokens per aggregator (default: " .. M._defaults.aggregator_tokens .. "; implementation choice — sized larger than per-proposer to accommodate synthesizing n outputs)"),
    proposer_prompt   = T.string:is_optional():describe("Override proposer prompt (implementation choice — paper does not specify wording)"),
    aggregator_prompt = T.string:is_optional():describe("Override AS_PROMPT_TEMPLATE; replacing it drops the paper's effect guarantee"),
    system_prompt     = T.string:is_optional():describe("Override proposer system prompt (implementation choice — paper does not specify)"),
}, { open = true })

local run_result_shape = T.shape({
    answer          = T.string:describe("Final aggregator output from layer L"),
    n_layers        = T.number:describe("L actually executed"),
    n_proposers     = T.number:describe("n actually used (from proposers / personas length)"),
    layers          = T.array_of(layer_record_shape)
        :describe("Per-layer records: proposer outputs + aggregator output"),
    total_llm_calls = T.number:describe("Total LLM calls (= L · (n + 1))"),
}, { open = true })

-- ─── Validation helpers ───

local function require_string(value, name, entry)
    if type(value) ~= "string" or value == "" then
        error(string.format("moa.%s: %s must be a non-empty string", entry, name), 3)
    end
end

local function require_table(value, name, entry)
    if type(value) ~= "table" then
        error(string.format("moa.%s: %s must be a table", entry, name), 3)
    end
end

local function require_non_empty_array(value, name, entry)
    require_table(value, name, entry)
    if #value == 0 then
        error(string.format("moa.%s: %s must be a non-empty array", entry, name), 3)
    end
end

local function require_positive_int(value, name, entry, minval)
    minval = minval or 1
    if type(value) ~= "number" or value < minval or math.floor(value) ~= value then
        error(string.format(
            "moa.%s: %s must be an integer >= %d, got %s",
            entry, name, minval, tostring(value)), 3)
    end
end

-- ─── Internal helpers (not in spec, exposed via M._internal for tests) ───

--- Format proposer responses into the body that fills AS_PROMPT_TEMPLATE.
--- Paper Table 1 shows the responses are listed; this pkg numbers them
--- "1.", "2.", … for unambiguous reference.
local function format_responses_for_aggregator(responses)
    local lines = {}
    for i, resp in ipairs(responses) do
        lines[#lines + 1] = string.format("%d. %s", i, resp)
    end
    return table.concat(lines, "\n\n")
end

--- Resolve proposer list:
---   - if ctx.proposers given (multi-model path), use it as-is
---   - else if ctx.personas given (single-model rotation path), wrap
---     each persona as {system=persona}
---   - else error (one of the two REQUIRED extension points)
local function resolve_proposers(ctx)
    if ctx.proposers ~= nil then
        require_non_empty_array(ctx.proposers, "proposers", "run")
        return ctx.proposers, "proposers"
    end
    if ctx.personas ~= nil then
        require_non_empty_array(ctx.personas, "personas", "run")
        local specs = {}
        for i, persona in ipairs(ctx.personas) do
            if type(persona) ~= "string" or persona == "" then
                error(string.format(
                    "moa.run: personas[%d] must be a non-empty string", i), 3)
            end
            specs[i] = { system = persona }
        end
        return specs, "personas"
    end
    error("moa.run: one of ctx.proposers (multi-model PATH; Wang §3 main config) or ctx.personas (single-model rotation PATH) is REQUIRED", 3)
end

-- ─── Pure entries ───

--- Build the user prompt for a proposer at any layer.
---
--- At layer 1: only the task is shown.
--- At layer 2+: the previous layer's aggregated output is included as
--- prior context so the proposer can build on it (the paper feeds the
--- aggregated y_{i-1} back as x_i for the next layer).
---@param args table { task, aggregated_prev?, proposer_prompt?, system_prompt? }
---@return table { prompt, system }
function M.build_proposer_prompt(args)
    require_table(args, "args", "build_proposer_prompt")
    require_string(args.task, "task", "build_proposer_prompt")

    local system = args.system_prompt or M.DEFAULT_PROPOSER_SYSTEM

    if args.proposer_prompt then
        local prompt
        if args.aggregated_prev and args.aggregated_prev ~= "" then
            prompt = string.format(args.proposer_prompt, args.task, args.aggregated_prev)
        else
            prompt = string.format(args.proposer_prompt, args.task, "")
        end
        return { prompt = prompt, system = system }
    end

    if args.aggregated_prev and args.aggregated_prev ~= "" then
        return {
            prompt = string.format(
                "Query: %s\n\nA prior aggregated response is provided below as additional context:\n\n%s\n\nProduce your best answer to the query.",
                args.task, args.aggregated_prev),
            system = system,
        }
    end
    return {
        prompt = string.format("Query: %s\n\nProduce your best answer.", args.task),
        system = system,
    }
end

--- Build the aggregator prompt = AS_PROMPT_TEMPLATE applied to the n
--- proposer responses for one layer. This is the ⊕ operator in §2.2.
---@param args table { proposer_responses, aggregator_prompt? }
---@return table { prompt, system }
function M.build_aggregator_prompt(args)
    require_table(args, "args", "build_aggregator_prompt")
    require_non_empty_array(args.proposer_responses, "proposer_responses", "build_aggregator_prompt")

    local responses_text = format_responses_for_aggregator(args.proposer_responses)
    local template = args.aggregator_prompt or M.AS_PROMPT_TEMPLATE
    return {
        prompt = string.format(template, responses_text),
        -- AS_PROMPT-style aggregators don't need a separate system message
        -- (the instruction is in the user prompt). We send an empty
        -- system; callers can override at run level.
        system = "",
    }
end

-- ─── Strategy entry ───

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    if type(ctx) ~= "table" then
        error("moa.run: ctx must be a table", 2)
    end
    if alc == nil then
        error("moa.run: alc host is not available", 2)
    end
    require_string(ctx.task, "task", "run")

    local proposer_specs, path_kind = resolve_proposers(ctx)
    local n_proposers = #proposer_specs
    local n_layers = ctx.n_layers or M._defaults.n_layers
    local temperature = ctx.temperature or M._defaults.temperature
    local proposer_tokens = ctx.proposer_tokens or M._defaults.proposer_tokens
    local aggregator_tokens = ctx.aggregator_tokens or M._defaults.aggregator_tokens
    require_positive_int(n_layers, "n_layers", "run", 1)
    require_positive_int(proposer_tokens, "proposer_tokens", "run", 1)
    require_positive_int(aggregator_tokens, "aggregator_tokens", "run", 1)

    local layers = {}
    local total_llm_calls = 0
    local prev_aggregated = nil

    alc.log("info", string.format(
        "moa: L=%d × n=%d (%s path)", n_layers, n_proposers, path_kind))

    for layer_i = 1, n_layers do
        -- ─── Layer i: n proposers in parallel ───
        local layer_responses = {}
        for j = 1, n_proposers do
            local spec = proposer_specs[j]
            local pair = M.build_proposer_prompt({
                task            = ctx.task,
                aggregated_prev = prev_aggregated,
                proposer_prompt = ctx.proposer_prompt,
                system_prompt   = spec.system or ctx.system_prompt,
            })
            local llm_opts = {
                max_tokens  = proposer_tokens,
                temperature = temperature,
            }
            if pair.system and pair.system ~= "" then
                llm_opts.system = pair.system
            end
            if spec.model then llm_opts.model = spec.model end
            local resp = alc.llm(pair.prompt, llm_opts)
            require_string(resp, string.format("proposer[%d] response", j), "run")
            layer_responses[j] = {
                proposer = j,
                model = spec.model,
                text = resp,
            }
            total_llm_calls = total_llm_calls + 1
        end

        -- ─── Aggregator (⊕) ───
        local response_texts = {}
        for j = 1, n_proposers do
            response_texts[j] = layer_responses[j].text
        end
        local agg_pair = M.build_aggregator_prompt({
            proposer_responses = response_texts,
            aggregator_prompt  = ctx.aggregator_prompt,
        })
        local agg_opts = {
            max_tokens  = aggregator_tokens,
            temperature = temperature,
        }
        if agg_pair.system and agg_pair.system ~= "" then
            agg_opts.system = agg_pair.system
        end
        local aggregated = alc.llm(agg_pair.prompt, agg_opts)
        require_string(aggregated, string.format("layer[%d] aggregator", layer_i), "run")
        total_llm_calls = total_llm_calls + 1

        layers[layer_i] = {
            layer = layer_i,
            proposers = layer_responses,
            aggregated = aggregated,
        }
        prev_aggregated = aggregated
    end

    alc.log("info", string.format(
        "moa: complete — L=%d, n=%d, %d LLM calls",
        n_layers, n_proposers, total_llm_calls))

    ctx.result = {
        answer          = prev_aggregated,
        n_layers        = n_layers,
        n_proposers     = n_proposers,
        layers          = layers,
        total_llm_calls = total_llm_calls,
    }
    return ctx
end

---@type AlcSpec
M.spec = {
    entries = {
        build_proposer_prompt = {
            args   = proposer_input_shape,
            result = prompt_pair_shape,
        },
        build_aggregator_prompt = {
            args   = aggregator_input_shape,
            result = prompt_pair_shape,
        },
        run = {
            input  = run_input_shape,
            result = run_result_shape,
        },
    },
}

-- Test hooks (not part of public spec contract)
M._internal = {
    format_responses_for_aggregator = format_responses_for_aggregator,
    resolve_proposers = resolve_proposers,
}

-- Self-decoration for ALC_SHAPE_CHECK=1 dev mode.
M.run                   = S.instrument(M, "run")
M.build_proposer_prompt = S.instrument(M, "build_proposer_prompt")
M.build_aggregator_prompt = S.instrument(M, "build_aggregator_prompt")

return M
