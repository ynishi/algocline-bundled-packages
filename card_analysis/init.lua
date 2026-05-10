--- card_analysis(CardAnalysis) — Card failure analyzer with one-line improvement hint
---
--- Reads a Card body + its samples sidecar, detects failure samples
--- across common shape conventions, asks the LLM for one structured
--- improvement hint (pattern + suggested_change + confidence).
---
--- This is the default analyzer pkg dispatched by the host MCP tool
--- `alc_card_analyze` (algocline `DEFAULT_CARD_ANALYZE_PKG = "card_analysis"`).
--- The host loads the Card body and samples sidecar into ctx; this pkg
--- runs the LLM-based pattern analysis and writes the result back.
---
--- ## Usage
---
--- Normally invoked via the host MCP tool:
---
--- ```jsonc
--- alc_card_analyze({ card_id: "<id>", pkg: "card_analysis" })
--- ```
---
--- Direct Lua usage (testing / custom hosts):
---
--- ```lua
--- local card_analysis = require("card_analysis")
--- return card_analysis.run({
---     card_id = "...",
---     card    = <full card body>,
---     samples = { ... },  -- raw samples.jsonl rows
--- })
--- ```
---
--- ## Algorithm
---
--- Three-step single-shot analyzer:
---
--- 1. **Failure detection** — scan `ctx.samples` for failure rows using
---    a multi-heuristic OR (admission/status/passed/score), then build
---    the analysis pool (failures, or all samples on no-signal fallback).
--- 2. **Prompt build** — render the first ≤8 failures with a stable
---    field projection (`name` / `case` / `input` / `prompt` / `expected`
---    / `response` / `detail` / `score` / `grades`), each value compacted
---    to ≤400 chars, plus Card metadata (`pkg.name` / `scenario.name`
---    / `model.id`).
--- 3. **LLM + JSON parse** — single `alc.llm` call requesting STRICT JSON;
---    `alc.json_extract` parses the response. On parse failure the raw
---    output is preserved verbatim (compacted) in `_raw_llm` and a
---    sentinel result is returned with `confidence = 0.0`.
---
--- ## Failure detection
---
--- Sample shapes vary across pkgs. The analyzer recognizes any of:
---
---   * `admission == "fail"`            (flow_design / flow_refine_orch)
---   * `status   == "fail" | "error"`   (status-based pkgs)
---   * `passed   == false`              (recipe_safe_panel pattern)
---   * `score    < 0.5`                 (numeric grader)
---
--- If none of those signals are present, the pkg falls back to "all
--- samples are interesting" and lets the LLM judge.
---
--- ## Output (`ctx.result`)
---
--- ```jsonc
--- {
---   "pattern":          "<one-line failure pattern summary>",
---   "suggested_change": "<concrete prompt or Lua-level change>",
---   "confidence":       0.0–1.0,
---   "failure_count":    <int>,    // optional (always present in current impl)
---   "sample_count":     <int>     // optional (always present in current impl)
--- }
--- ```
---
--- The output shape is locked to the host-side typed struct
--- `algocline-app::service::card::CardAnalyzeResult` so the result
--- round-trips through MCP without re-encoding.
---
--- ## Caveats
---
--- - Single LLM call by design; no chain / no self-critique. Higher-quality
---   analysis loops belong in a separate pkg (e.g. recipe-style multi-step).
--- - The first 8 failures are sampled when the failure pool exceeds 8;
---   later failures are not visible to the LLM in this version.
--- - On `samples == 0`, returns a no-samples sentinel without calling the
---   LLM (cost-free guard).
---
--- ## References
---
--- - Host MCP tool contract: `algocline-mcp::service::alc_card_analyze`
---   (algocline crate, ctx contract literal in tool description).
--- - Host result struct: `algocline-app::service::card::CardAnalyzeResult`.

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name        = "card_analysis",
    version     = "0.1.0",
    description = "Card failure analyzer — single-card improvement hint generator",
    category    = "debugging",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                card_id = T.string:describe("Card identifier (host-provided)"),
                card    = T.any:describe("Full Card body (host-loaded from card_id)"),
                samples = T.array_of(T.any):describe(
                    "samples sidecar rows (host-loaded; may be empty)"),
            }),
            result = T.shape({
                pattern          = T.string:describe("One-line failure pattern summary"),
                suggested_change = T.string:describe(
                    "Concrete change proposal (1-3 sentences, actionable)"),
                confidence       = T.number:describe("0.0..=1.0 diagnostic confidence"),
                failure_count    = T.number:is_optional():describe(
                    "Detected failure sample count (Option<u64> on host side)"),
                sample_count     = T.number:is_optional():describe(
                    "Total samples processed (Option<u64> on host side)"),
            }),
        },
    },
}

local function is_failure(sample)
    if type(sample) ~= "table" then return false end
    if sample.admission == "fail" then return true end
    if sample.status == "fail" or sample.status == "error" then return true end
    if sample.passed == false then return true end
    if type(sample.score) == "number" and sample.score < 0.5 then return true end
    return false
end

local function compact(s, max_len)
    if type(s) ~= "string" then return tostring(s) end
    if #s <= max_len then return s end
    return s:sub(1, max_len) .. "...(truncated)"
end

local function format_sample(sample, idx)
    local lines = { string.format("--- failure sample %d ---", idx) }
    for _, k in ipairs({ "name", "case", "input", "prompt", "expected", "response", "detail", "score", "grades" }) do
        local v = sample[k]
        if v ~= nil then
            local repr
            if type(v) == "table" then
                repr = compact(alc.json_encode(v), 400)
            else
                repr = compact(tostring(v), 400)
            end
            lines[#lines + 1] = string.format("%s: %s", k, repr)
        end
    end
    return table.concat(lines, "\n")
end

local function build_prompt(card, failures, total)
    local card_pkg = (card.pkg and card.pkg.name) or "<unknown>"
    local card_scenario = (card.scenario and card.scenario.name) or "<unknown>"
    local card_model = (card.model and card.model.id) or "<unknown>"

    local sections = {}
    for i, s in ipairs(failures) do
        sections[#sections + 1] = format_sample(s, i)
        if i >= 8 then break end
    end

    return string.format([[
You are a code-quality analyzer for an LLM-amplification pipeline.
A single Card represents one run of a strategy package; its samples sidecar
records per-case detail. You are given the failure samples below.

## Card metadata
pkg:      %s
scenario: %s
model:    %s

## Failure samples (%d / %d total samples)
%s

## Task
Identify **one** dominant failure pattern and propose **one** concrete change
the package author could apply (prompt-level wording, Lua control flow,
spec/grader adjustment — whichever fits the pattern best).

Output STRICT JSON, no markdown fences, no commentary:

{
  "pattern":          "<one-line failure pattern summary>",
  "suggested_change": "<one concrete change, 1-3 sentences, actionable>",
  "confidence":       <number between 0 and 1>
}
]],
        card_pkg, card_scenario, card_model, #failures, total, table.concat(sections, "\n\n")
    )
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local card = ctx.card or error("ctx.card is required (host should populate via alc_card_analyze)")
    local samples = ctx.samples or {}

    local failures = {}
    for _, s in ipairs(samples) do
        if is_failure(s) then
            failures[#failures + 1] = s
        end
    end

    local total = #samples
    local fail_count = #failures

    if total == 0 then
        ctx.result = {
            pattern = "no samples",
            suggested_change = "Card has no samples sidecar; run alc_eval with auto_card=true to populate before analyzing.",
            confidence = 1.0,
            failure_count = 0,
            sample_count = 0,
        }
        return ctx
    end

    local analysis_pool = failures
    if fail_count == 0 then
        analysis_pool = samples
    end

    local prompt = build_prompt(card, analysis_pool, total)

    local raw = alc.llm(prompt, {
        system = "You are a precise failure-pattern analyzer. "
            .. "Return STRICT JSON only. No markdown fences, no preamble.",
        max_tokens = 600,
    })

    local parsed = alc.json_extract(raw)
    if type(parsed) ~= "table" then
        ctx.result = {
            pattern = "llm output unparseable",
            suggested_change = compact(raw, 800),
            confidence = 0.0,
            failure_count = fail_count,
            sample_count = total,
            _raw_llm = compact(raw, 2000),
        }
        return ctx
    end

    ctx.result = {
        pattern          = parsed.pattern or "<missing>",
        suggested_change = parsed.suggested_change or "<missing>",
        confidence       = tonumber(parsed.confidence) or 0.0,
        failure_count    = fail_count,
        sample_count     = total,
    }
    return ctx
end

M.run = S.instrument(M, "run")

return M
