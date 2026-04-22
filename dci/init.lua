--- dci — Deliberative Collective Intelligence (DCI-CF).
---
--- Implements the 8-stage structured deliberation algorithm from:
---   Prakash, Sunil
---   "From Debate to Deliberation: Structured Collective Reasoning
---    with Typed Epistemic Acts" (arXiv:2603.11781, 2026-03-12)
---
--- 4 reasoning archetypes × 14 typed epistemic acts (6 classes) ×
--- shared workspace (6 fields) + decision packet (5 components) +
--- convergence test + fallback cascade (outranking → minimax →
--- satisficing → Integrator arbitration). Forces the session to emit a
--- decision_packet with first-class minority_report preservation, even
--- on fallback.
---
--- 14 acts / 6 classes (issue §4.1):
---   Orienting   : frame, clarify, reframe
---   Generative  : propose, extend, spawn       (spawn skeleton-only in v1)
---   Critical    : ask, challenge
---   Integrative : bridge, synthesize, recall
---   Epistemic   : ground, update
---   Decisional  : recommend
---
--- 4 roles (fixed): framer / explorer / challenger / integrator.
---
--- DCI-CF 8 stages:
---   Stage 0 init session
---   Stage 1 independent proposals (per-role act(s))
---   Stage 2 canonicalize & cluster options
---   Stages 3-6 (loop up to Rmax=2):
---     3: collect challenges / evidence
---     4: admit new hypotheses (cutoff)
---     5: revise & compress options
---     6: score against criteria + convergence test
---        (dominance or no_blocking)
---   Stage 7 fallback cascade
---   Stage 8 finalize decision packet (5 components completeness)
---
--- Entry contract:
---   run — Strategy, ctx-threading. ctx.task required; returns
---         ctx.result :: deliberated shape (alc_shapes).
---
--- Category: synthesis (panel-family).

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "dci",
    version = "0.1.0",
    description = "Deliberative Collective Intelligence (DCI-CF). 4 "
        .. "roles (Framer/Explorer/Challenger/Integrator) × 14 typed "
        .. "epistemic acts (6 classes) × shared workspace (6 fields) × "
        .. "8-stage convergence algorithm. Emits a decision_packet with "
        .. "5 non-nil components (selected_option, residual_objections, "
        .. "minority_report, next_actions, reopen_triggers). Stage 7 "
        .. "fallback cascade (outranking → minimax → satisficing → "
        .. "Integrator arbitration) preserves minority_report even on "
        .. "forced convergence.",
    category = "synthesis",
}

-- Centralized defaults (issue §13.1). Keep magic numbers here so no
-- stage hard-codes its own copy. All knobs are injectable via ctx.
M._defaults = {
    max_rounds    = 2,     -- Rmax, paper §5 Table 1
    max_options   = 5,     -- paper Appendix A
    num_finalists = 3,     -- paper Appendix A
    gen_tokens    = 400,   -- sc / panel convention
}

-- ─── Constants ───

-- 14 acts organized by 6 classes. Flatten_acts below returns a 14-elem
-- dense array for completeness assertions.
local ACT_CLASSES = {
    orienting   = { "frame", "clarify", "reframe" },
    generative  = { "propose", "extend", "spawn" },
    critical    = { "ask", "challenge" },
    integrative = { "bridge", "synthesize", "recall" },
    epistemic   = { "ground", "update" },
    decisional  = { "recommend" },
}

-- 4 roles fixed (issue §4.2, §13.1).
local ROLES = { "framer", "explorer", "challenger", "integrator" }

-- Stage 7 fallback cascade order (issue §13.3). Test #10 asserts
-- this exact sequence.
local FALLBACK_CASCADE_ORDER = {
    "outranking",
    "minimax",
    "satisficing",
    "integrator_arbitration",
}

-- ─── Shape definitions (local, for spec.entries) ───

local run_input_shape = T.shape({
    task          = T.string:describe("Deliberation task / decision question"),
    max_rounds    = T.number:is_optional()
        :describe("Rmax per DCI-CF (default: 2, paper §5 Table 1)"),
    max_options   = T.number:is_optional()
        :describe("Max option count after canonicalize (default: 5)"),
    num_finalists = T.number:is_optional()
        :describe("Finalist count after revise (default: 3)"),
    roles         = T.array_of(T.string):is_optional()
        :describe("Role names (default: framer/explorer/challenger/integrator)"),
    gen_tokens    = T.number:is_optional()
        :describe("Max tokens per LLM generation (default: 400)"),
    auto_card     = T.boolean:is_optional()
        :describe("Emit a Card on completion (default: false)"),
    card_pkg      = T.string:is_optional()
        :describe("Card pkg.name override (default: 'dci_<task_hash>')"),
    scenario_name = T.string:is_optional()
        :describe("Explicit scenario name for the emitted Card"),
}, { open = true })

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input  = run_input_shape,
            result = "deliberated",
        },
    },
}

-- ─── Helpers (pure) ───

-- Best-effort warn helper. Prefers alc.log.warn; falls back to
-- alc.log(level, msg) call form, then stderr. Never silent-drop
-- (parse-fallback rate must be observable).
local function warn(msg)
    if type(alc) == "table" and type(alc.log) == "table"
        and type(alc.log.warn) == "function"
    then
        alc.log.warn(msg)
        return
    end
    if type(alc) == "table" and type(alc.log) == "function" then
        local ok = pcall(alc.log, "warn", msg)
        if ok then return end
    end
    io.stderr:write("[dci] " .. tostring(msg) .. "\n")
end

local function info(msg)
    if type(alc) == "table" and type(alc.log) == "table"
        and type(alc.log.info) == "function"
    then
        alc.log.info(msg)
        return
    end
    if type(alc) == "table" and type(alc.log) == "function" then
        pcall(alc.log, "info", msg)
    end
end

-- Flatten 14-act table into a dense array.
local function flatten_acts(act_classes)
    local flat = {}
    local order = { "orienting", "generative", "critical",
                    "integrative", "epistemic", "decisional" }
    for _, class in ipairs(order) do
        local list = act_classes[class]
        if type(list) == "table" then
            for _, name in ipairs(list) do
                flat[#flat + 1] = name
            end
        end
    end
    return flat
end

-- Map an act name to its owning class. Returns nil for unknown acts.
local function classify_act(act_type)
    for class, list in pairs(ACT_CLASSES) do
        for _, name in ipairs(list) do
            if name == act_type then return class end
        end
    end
    return nil
end

-- Return a role persona prompt. Kept concise (1-3 sentences) per
-- paper §4.2 — the LLM only needs directional steering.
local function role_persona(role)
    if role == "framer" then
        return "You are the Framer. Define the problem view, "
            .. "disambiguate terms, and surface the implicit question. "
            .. "Prefer frame / clarify / reframe acts."
    elseif role == "explorer" then
        return "You are the Explorer. Generate novel possibilities and "
            .. "candidate solutions. Prefer propose / extend acts."
    elseif role == "challenger" then
        return "You are the Challenger. Pressure-test risks, "
            .. "assumptions, and hidden trade-offs. Prefer ask / "
            .. "challenge acts and ground claims in evidence."
    elseif role == "integrator" then
        return "You are the Integrator. Synthesize positions across "
            .. "perspectives, bridge tensions, and recommend. Prefer "
            .. "bridge / synthesize / recall / recommend acts."
    end
    -- Unknown role: return a generic neutral persona (silent drop
    -- would hide typos).
    warn("dci.role_persona: unknown role " .. tostring(role)
        .. ", returning neutral persona")
    return "You are a deliberation participant. Reason carefully about "
        .. "the task."
end

-- Robust parse of LLM output into a list of acts. 3-stage fallback
-- (silent-drop禁止 — each stage warns).
--
--   1. alc.json_decode(raw) → { acts = [...] } or { [...] }
--   2. raw:match("%[.-%]") → re-decode the bracket region
--   3. single propose-act wrap over raw
--
-- Returns an array of acts, never nil.
local function parse_acts_json(raw, fallback_role)
    if type(raw) ~= "string" or raw == "" then
        warn("dci.parse_acts_json: empty raw, falling back to single act")
        return {
            { type = "propose", content = "",
              author = fallback_role or "unknown" },
        }
    end

    -- Stage 1: try alc.json_decode on the whole body.
    if type(alc) == "table" and type(alc.json_decode) == "function" then
        local ok, parsed = pcall(alc.json_decode, raw)
        if ok and type(parsed) == "table" then
            -- Accept { acts = [...] } or a bare array.
            local acts = parsed.acts or parsed
            if type(acts) == "table" and type(acts[1]) == "table" then
                return acts
            end
        end
    end
    warn("dci.parse_acts_json: stage1 (full JSON decode) failed, trying bracket match")

    -- Stage 2: match a JSON array region.
    local bracket = raw:match("(%b[])")
    if bracket and type(alc) == "table"
        and type(alc.json_decode) == "function"
    then
        local ok, parsed = pcall(alc.json_decode, bracket)
        if ok and type(parsed) == "table" and type(parsed[1]) == "table" then
            return parsed
        end
    end
    warn("dci.parse_acts_json: stage2 (bracket extract) failed, "
        .. "wrapping raw as single propose act")

    -- Stage 3: single propose act wrap.
    return {
        { type = "propose", content = raw,
          author = fallback_role or "unknown" },
    }
end

-- Pure helper: cluster propose-acts into options by naive prefix
-- match. LLM-based re-canonicalize happens in stage2 proper — this
-- helper is a deterministic fallback used when Stage 2 parse fails
-- and for tests.
local function canonicalize_options(acts, max_options)
    if type(acts) ~= "table" then return {} end
    local out = {}
    local seen = {}
    for _, a in ipairs(acts) do
        if type(a) == "table" and a.type == "propose" then
            local content = tostring(a.content or "")
            -- Crude cluster key: lowercase + first 40 chars.
            local key = content:sub(1, 40):lower()
            if key ~= "" and not seen[key] then
                seen[key] = true
                out[#out + 1] = {
                    id      = #out + 1,
                    content = content,
                    author  = a.author or "unknown",
                }
                if max_options and #out >= max_options then break end
            end
        end
    end
    return out
end

-- Truncate long strings for Card Tier-2 samples. Silent truncation is
-- acceptable here (summaries, not the canonical record).
local function truncate(s, n)
    s = tostring(s or "")
    if #s <= n then return s end
    return s:sub(1, n) .. "..."
end

-- Ensure nil-guard for decision_packet invariant.
local function ensure_nonnil(v, default)
    if v == nil then return default end
    return v
end

-- ─── LLM wrapper ───

local function call_llm(prompt, gen_tokens, system)
    if type(alc) ~= "table" or type(alc.llm) ~= "function" then
        error("dci.run: alc.llm is required at runtime", 3)
    end
    local opts = {
        max_tokens = gen_tokens,
        system = system
            or "You are participating in a structured deliberation. "
            .. "Output valid JSON when asked; otherwise concise prose.",
    }
    return alc.llm(prompt, opts)
end

-- ─── Stage 0: init session ───

local function stage0_init(task)
    return {
        problem_view          = tostring(task or ""),
        key_frames            = {},
        emerging_ideas        = {},
        tensions              = {},
        synthesis_in_progress = "",
        next_actions          = {},
    }
end

-- ─── Stage 1: independent proposals (4 roles × 1 call) ───

local function stage1_propose(task, workspace, gen_tokens)
    local all_acts = {}
    for _, role in ipairs(ROLES) do
        local persona = role_persona(role)
        local prompt = string.format(
[[%s

Task: %s

Produce 1-3 epistemic acts that advance the shared deliberation.
Choose act types from: frame, clarify, reframe, propose, extend,
ask, challenge, bridge, synthesize, recall, ground, update, recommend.

Return STRICT JSON (no prose outside) of the form:
{"acts":[
  {"type":"<act_type>","content":"<1-3 sentences>","author":"%s"}
]}
]], persona, tostring(task), role)
        local raw = call_llm(prompt, gen_tokens, persona)
        local acts = parse_acts_json(raw, role)
        -- Tag author defensively (LLM may forget).
        for _, a in ipairs(acts) do
            if a.author == nil then a.author = role end
            if a.type == nil then a.type = "propose" end
        end
        -- Guarantee at least one act per role (test #5).
        if #acts == 0 then
            acts = {
                { type = "propose", content = tostring(raw or ""),
                  author = role },
            }
        end
        for _, a in ipairs(acts) do all_acts[#all_acts + 1] = a end
        -- Update workspace: key_frames accumulates frame/reframe,
        -- emerging_ideas accumulates propose/extend.
        for _, a in ipairs(acts) do
            local content = tostring(a.content or "")
            if a.type == "frame" or a.type == "reframe" then
                workspace.key_frames[#workspace.key_frames + 1] = content
            elseif a.type == "propose" or a.type == "extend" then
                workspace.emerging_ideas[#workspace.emerging_ideas + 1] = content
            end
        end
    end
    return all_acts
end

-- ─── Stage 2: canonicalize & cluster options ───

local function stage2_canonicalize(acts, max_options)
    -- LLM-based canonicalize: ask for an explicit option list. If the
    -- parse fails, fall back to the pure canonicalize_options helper.
    local propose_texts = {}
    for _, a in ipairs(acts) do
        if type(a) == "table" and
            (a.type == "propose" or a.type == "extend")
        then
            propose_texts[#propose_texts + 1] = tostring(a.content or "")
        end
    end
    if #propose_texts == 0 then return {} end

    local joined = table.concat(propose_texts, "\n- ")
    local prompt = string.format(
[[You are the Integrator. Canonicalize and cluster the following
proposals into at most %d distinct options. Merge duplicates and
near-duplicates. Preserve the substance of each proposal.

Proposals:
- %s

Return STRICT JSON (no prose outside) of the form:
{"options":[
  {"id":1,"content":"<option text>","author":"integrator"}
]}
]], max_options, joined)

    local raw = call_llm(prompt, 400, nil)
    local options
    if type(alc) == "table" and type(alc.json_decode) == "function" then
        local ok, parsed = pcall(alc.json_decode, raw)
        if ok and type(parsed) == "table"
            and type(parsed.options) == "table"
        then
            options = parsed.options
        end
    end
    if options == nil then
        -- Regex extract
        local bracket = raw and raw:match("(%b[])")
        if bracket and type(alc) == "table"
            and type(alc.json_decode) == "function"
        then
            local ok, parsed = pcall(alc.json_decode, bracket)
            if ok and type(parsed) == "table" then options = parsed end
        end
    end
    if type(options) ~= "table" or #options == 0 then
        warn("dci.stage2_canonicalize: LLM parse failed, "
            .. "falling back to deterministic clustering")
        options = canonicalize_options(acts, max_options)
    end

    -- Normalize + cap at max_options
    local normalized = {}
    for i, o in ipairs(options) do
        if i > max_options then break end
        normalized[#normalized + 1] = {
            id      = i,
            content = tostring(o.content or o.text or ""),
            author  = tostring(o.author or "integrator"),
        }
    end
    return normalized
end

-- ─── Stage 3: collect challenges / evidence ───

local function stage3_challenge(task, workspace, options, gen_tokens)
    local opts_text = {}
    for _, o in ipairs(options) do
        opts_text[#opts_text + 1] = string.format("- [%d] %s", o.id,
            tostring(o.content))
    end
    local options_str = table.concat(opts_text, "\n")
    local acts = {}
    for _, role in ipairs(ROLES) do
        local persona = role_persona(role)
        local prompt = string.format(
[[%s

Task: %s

Current options:
%s

Stage 3 — collect challenges. Emit 1-3 `ask` / `challenge` / `ground`
acts against these options. Each act should target a specific option
id and cite evidence where applicable.

Return STRICT JSON (no prose outside) of the form:
{"acts":[
  {"type":"challenge","content":"<text>","author":"%s",
   "targets":[<option_id>],"evidence":["<snippet>"]}
]}
]], persona, tostring(task), options_str, role)
        local raw = call_llm(prompt, gen_tokens, persona)
        local role_acts = parse_acts_json(raw, role)
        for _, a in ipairs(role_acts) do
            if a.author == nil then a.author = role end
            if a.type == nil then a.type = "challenge" end
            acts[#acts + 1] = a
            -- Record tensions in workspace
            local content = tostring(a.content or "")
            if a.type == "challenge" or a.type == "ask" then
                workspace.tensions[#workspace.tensions + 1] = content
            end
        end
    end
    return acts
end

-- ─── Stage 4: admit new hypotheses (cutoff) ───

local function stage4_admit(task, workspace, challenges, gen_tokens)
    local chal_text = {}
    for i, c in ipairs(challenges) do
        chal_text[#chal_text + 1] = string.format("- [%d] (%s) %s",
            i, tostring(c.type or "?"), tostring(c.content or ""))
    end
    local joined = table.concat(chal_text, "\n")
    local acts = {}
    for _, role in ipairs(ROLES) do
        local persona = role_persona(role)
        local prompt = string.format(
[[%s

Task: %s

Outstanding challenges:
%s

Stage 4 — admit new hypotheses. Produce 0-2 `propose` / `extend` /
`update` acts that respond to the challenges. Be surgical: only admit
when the evidence warrants it.

Return STRICT JSON (no prose outside) of the form:
{"acts":[
  {"type":"extend","content":"<text>","author":"%s"}
]}
]], persona, tostring(task), joined, role)
        local raw = call_llm(prompt, gen_tokens, persona)
        local role_acts = parse_acts_json(raw, role)
        for _, a in ipairs(role_acts) do
            if a.author == nil then a.author = role end
            if a.type == nil then a.type = "extend" end
            acts[#acts + 1] = a
        end
    end
    return acts
end

-- ─── Stage 5: revise & compress options ───

local function stage5_revise(task, workspace, options, num_finalists,
                              gen_tokens)
    local opts_text = {}
    for _, o in ipairs(options) do
        opts_text[#opts_text + 1] = string.format("- [%d] %s", o.id,
            tostring(o.content))
    end
    local options_str = table.concat(opts_text, "\n")

    -- Multi-role revision: each role proposes a revision; Integrator
    -- consolidates below (1 call per role for transparency; the
    -- revision vote is a single final Integrator call).
    local proposals = {}
    for _, role in ipairs(ROLES) do
        local persona = role_persona(role)
        local prompt = string.format(
[[%s

Task: %s

Current options:
%s

Stage 5 — revise and compress to AT MOST %d finalists. Eliminate
duplicates, merge adjacent ideas, and drop dominated options.

Return STRICT JSON (no prose outside) of the form:
{"options":[{"id":1,"content":"<text>","author":"%s"}]}
]], persona, tostring(task), options_str, num_finalists, role)
        local raw = call_llm(prompt, gen_tokens, persona)
        if type(alc) == "table"
            and type(alc.json_decode) == "function"
        then
            local ok, parsed = pcall(alc.json_decode, raw)
            if ok and type(parsed) == "table"
                and type(parsed.options) == "table"
            then
                for _, o in ipairs(parsed.options) do
                    proposals[#proposals + 1] = {
                        content = tostring(o.content or ""),
                        author  = role,
                    }
                end
            end
        end
    end

    -- Deterministic fallback cluster / cap
    local revised = {}
    local seen = {}
    for _, p in ipairs(proposals) do
        local key = p.content:sub(1, 40):lower()
        if key ~= "" and not seen[key] then
            seen[key] = true
            revised[#revised + 1] = {
                id      = #revised + 1,
                content = p.content,
                author  = p.author,
            }
            if #revised >= num_finalists then break end
        end
    end
    if #revised == 0 then
        -- Keep the original options if all role proposals failed to parse.
        for i = 1, math.min(num_finalists, #options) do
            revised[#revised + 1] = {
                id      = i,
                content = options[i].content,
                author  = options[i].author,
            }
        end
    end
    return revised
end

-- ─── Stage 6: convergence test ───

-- Output invariant (issue §13.3):
--   { converged: bool, mode: "dominance"|"no_blocking"|nil,
--     ranking: [{option_id, score, rationale}],
--     blocking_objections: [string] }
local function stage6_converge(task, workspace, options, criteria, gen_tokens)
    local opts_text = {}
    for _, o in ipairs(options) do
        opts_text[#opts_text + 1] = string.format("- [%d] %s", o.id,
            tostring(o.content))
    end
    local options_str = table.concat(opts_text, "\n")
    local criteria_str = criteria
        and table.concat(criteria, ", ")
        or "clarity, feasibility, evidence, tradeoffs"

    local prompt = string.format(
[[You are the Integrator. Stage 6 — convergence test.

Task: %s

Options:
%s

Criteria: %s

Definitions:
- dominance: one option is strictly better than ALL others on ALL criteria.
- no_blocking: no blocking objection remains unresolved against the
  current top-ranked option.
- none: neither of the above holds.

Return STRICT JSON (no prose outside):
{"mode":"dominance"|"no_blocking"|"none",
 "ranking":[{"option_id":1,"score":0.8,"rationale":"<text>"}],
 "blocking_objections":["<text>"]}
]], tostring(task), options_str, criteria_str)

    local raw = call_llm(prompt, gen_tokens, nil)

    local parsed
    if type(alc) == "table" and type(alc.json_decode) == "function" then
        local ok, p = pcall(alc.json_decode, raw)
        if ok and type(p) == "table" then parsed = p end
    end
    if parsed == nil then
        -- Try bracket extract first
        local bracket = raw and raw:match("(%b{})")
        if bracket and type(alc) == "table"
            and type(alc.json_decode) == "function"
        then
            local ok, p = pcall(alc.json_decode, bracket)
            if ok and type(p) == "table" then parsed = p end
        end
    end

    -- Parse mode
    local mode_raw
    if parsed and type(parsed.mode) == "string" then
        mode_raw = parsed.mode:lower()
    else
        if type(raw) == "string" then
            local m = raw:lower():match("\"mode\"%s*:%s*\"([%w_]+)\"")
            mode_raw = m
        end
    end

    local mode
    if mode_raw == "dominance" then
        mode = "dominance"
    elseif mode_raw == "no_blocking" then
        mode = "no_blocking"
    else
        mode = nil
    end

    local converged = (mode == "dominance" or mode == "no_blocking")

    -- Parse ranking; fall back to a uniform ranking over options.
    local ranking = {}
    if parsed and type(parsed.ranking) == "table" then
        for _, r in ipairs(parsed.ranking) do
            if type(r) == "table" then
                ranking[#ranking + 1] = {
                    option_id = r.option_id or r.id or (#ranking + 1),
                    score     = tonumber(r.score) or 0,
                    rationale = tostring(r.rationale or ""),
                }
            end
        end
    end
    if #ranking == 0 then
        for i, o in ipairs(options) do
            ranking[#ranking + 1] = {
                option_id = o.id or i,
                score     = 1 / math.max(i, 1),
                rationale = "",
            }
        end
    end

    local blocking = {}
    if parsed and type(parsed.blocking_objections) == "table" then
        for _, b in ipairs(parsed.blocking_objections) do
            blocking[#blocking + 1] = tostring(b)
        end
    end

    if parsed == nil then
        warn("dci.stage6_converge: parse failed, treating as unconverged")
    end

    return {
        converged           = converged,
        mode                = mode,
        ranking             = ranking,
        blocking_objections = blocking,
    }
end

-- ─── Stage 7: fallback cascade (4 stages, shared I/O shape) ───
--
-- Each stage takes (task, workspace, ranking, gen_tokens) where
--   ranking = { options = [{id, content}], ranking = [{option_id,
--               score, rationale}], converged? = bool }
-- and returns the same shape, possibly with refined ranking / options
-- and `converged = true` to halt cascade.

local function ranking_prompt(stage_name, task, ranking)
    local opts_text = {}
    for _, o in ipairs(ranking.options or {}) do
        opts_text[#opts_text + 1] = string.format("- [%s] %s",
            tostring(o.id), tostring(o.content or ""))
    end
    local rank_text = {}
    for _, r in ipairs(ranking.ranking or {}) do
        rank_text[#rank_text + 1] = string.format(
            "- option_id=%s score=%s rationale=%q",
            tostring(r.option_id), tostring(r.score),
            tostring(r.rationale or ""))
    end
    local descriptions = {
        outranking =
            "You are performing outranking analysis. For each pair of "
            .. "options, determine whether one outranks the other on a "
            .. "majority of criteria without being strongly opposed on "
            .. "any. Refine the ranking accordingly.",
        minimax =
            "You are performing minimax analysis. For each option, "
            .. "evaluate its worst-case outcome across criteria. "
            .. "Prefer the option whose worst-case is best.",
        satisficing =
            "You are performing satisficing analysis. For each option, "
            .. "determine whether it meets an acceptable threshold on "
            .. "ALL criteria. Return the best option that satisfices.",
        integrator_arbitration =
            "You are performing integrator arbitration — final "
            .. "judgment. Break remaining ties using synthesis across "
            .. "all prior stages.",
    }
    local desc = descriptions[stage_name] or descriptions.integrator_arbitration

    return string.format(
[[%s

Task: %s

Options:
%s

Current ranking:
%s

Return STRICT JSON (no prose outside):
{"options":[{"id":1,"content":"<text>"}],
 "ranking":[{"option_id":1,"score":0.8,"rationale":"<text>"}],
 "converged": true|false}

Set "converged":true only if this stage's rule yields a clear winner.
]], desc, tostring(task), table.concat(opts_text, "\n"),
        table.concat(rank_text, "\n"))
end

local function parse_ranking_result(raw, prior_ranking)
    local parsed
    if type(alc) == "table" and type(alc.json_decode) == "function" then
        local ok, p = pcall(alc.json_decode, raw)
        if ok and type(p) == "table" then parsed = p end
    end
    if parsed == nil and type(raw) == "string" then
        local bracket = raw:match("(%b{})")
        if bracket and type(alc) == "table"
            and type(alc.json_decode) == "function"
        then
            local ok, p = pcall(alc.json_decode, bracket)
            if ok and type(p) == "table" then parsed = p end
        end
    end

    -- Options default to prior options
    local options = prior_ranking.options or {}
    if parsed and type(parsed.options) == "table" and #parsed.options > 0 then
        local normalized = {}
        for i, o in ipairs(parsed.options) do
            normalized[#normalized + 1] = {
                id      = o.id or i,
                content = tostring(o.content or o.text or ""),
            }
        end
        options = normalized
    end

    local ranking = {}
    if parsed and type(parsed.ranking) == "table" then
        for _, r in ipairs(parsed.ranking) do
            if type(r) == "table" then
                ranking[#ranking + 1] = {
                    option_id = r.option_id or r.id or (#ranking + 1),
                    score     = tonumber(r.score) or 0,
                    rationale = tostring(r.rationale or ""),
                }
            end
        end
    end
    if #ranking == 0 then
        -- Preserve prior ranking
        for _, r in ipairs(prior_ranking.ranking or {}) do
            ranking[#ranking + 1] = {
                option_id = r.option_id,
                score     = r.score,
                rationale = r.rationale,
            }
        end
    end

    local converged = false
    if parsed and parsed.converged == true then converged = true end

    return {
        options   = options,
        ranking   = ranking,
        converged = converged,
    }
end

local function fallback_outranking(task, workspace, ranking, gen_tokens)
    local prompt = ranking_prompt("outranking", task, ranking)
    local raw = call_llm(prompt, gen_tokens, nil)
    return parse_ranking_result(raw, ranking)
end

local function fallback_minimax(task, workspace, ranking, gen_tokens)
    local prompt = ranking_prompt("minimax", task, ranking)
    local raw = call_llm(prompt, gen_tokens, nil)
    return parse_ranking_result(raw, ranking)
end

local function fallback_satisficing(task, workspace, ranking, gen_tokens)
    local prompt = ranking_prompt("satisficing", task, ranking)
    local raw = call_llm(prompt, gen_tokens, nil)
    return parse_ranking_result(raw, ranking)
end

local function fallback_integrator_arbitration(task, workspace, ranking,
                                                gen_tokens)
    local prompt = ranking_prompt("integrator_arbitration", task, ranking)
    local raw = call_llm(prompt, gen_tokens, nil)
    local out = parse_ranking_result(raw, ranking)
    -- Integrator arbitration is terminal: force converged=true.
    out.converged = true
    return out
end

local FALLBACK_FN = {
    outranking              = fallback_outranking,
    minimax                 = fallback_minimax,
    satisficing             = fallback_satisficing,
    integrator_arbitration  = fallback_integrator_arbitration,
}

local function initial_ranking_from_options(options)
    local opts = {}
    local rank = {}
    for i, o in ipairs(options) do
        opts[#opts + 1] = {
            id      = o.id or i,
            content = tostring(o.content or ""),
        }
        rank[#rank + 1] = {
            option_id = o.id or i,
            score     = 0,
            rationale = "",
        }
    end
    return { options = opts, ranking = rank }
end

local function stage7_fallback(task, workspace, options, gen_tokens)
    local ranking = initial_ranking_from_options(options)
    local calls_used = 0
    local stage_fired = nil
    for _, stage_name in ipairs(FALLBACK_CASCADE_ORDER) do
        local fn = FALLBACK_FN[stage_name]
        if type(fn) == "function" then
            local refined = fn(task, workspace, ranking, gen_tokens)
            calls_used = calls_used + 1
            ranking = refined
            stage_fired = stage_name
            if refined.converged then break end
        end
    end
    return {
        ranking     = ranking,
        calls_used  = calls_used,
        stage_fired = stage_fired,
    }
end

-- ─── Stage 8: finalize decision_packet (5 components, all non-nil) ───

local function stage8_finalize(task, workspace, selected_option, options,
                                 history, gen_tokens)
    -- Build the minority_report candidates from options not selected
    -- + from challenge / ask acts in history.
    local selected_id = selected_option and selected_option.option_id
    local minority_collected = {}
    for _, o in ipairs(options) do
        local oid = o.id
        if oid ~= selected_id then
            minority_collected[#minority_collected + 1] = {
                position   = tostring(o.content or ""),
                rationale  = "Not selected; alternative position "
                    .. "preserved per DCI-CF §5.3",
                confidence = 0.5,
            }
        end
    end
    -- Dissenting challenge acts (per §5.3)
    for _, h in ipairs(history or {}) do
        local a = h.act or h
        if type(a) == "table"
            and (a.type == "challenge" or a.type == "ask")
        then
            local author = a.author or "unknown"
            if author ~= "integrator" then
                minority_collected[#minority_collected + 1] = {
                    position   = tostring(a.content or ""),
                    rationale  = "Dissent from " .. tostring(author)
                        .. " during deliberation",
                    confidence = 0.4,
                }
            end
        end
    end

    local sel_text = ""
    if selected_option then
        -- Resolve the selected option content from the options list.
        for _, o in ipairs(options) do
            if o.id == selected_option.option_id then
                sel_text = tostring(o.content or "")
                break
            end
        end
        if sel_text == "" then
            sel_text = tostring(selected_option.rationale or "")
        end
    end

    local prompt = string.format(
[[You are the Integrator. Stage 8 — finalize the decision packet.

Task: %s

Selected option: %s

Stage 8 must emit a JSON decision packet with ALL 5 fields non-nil
(empty arrays / empty strings are allowed; nil is forbidden):

{"answer":"<final answer text>",
 "rationale":"<why this option>",
 "evidence":["<cited snippet>"],
 "residual_objections":["<objection>"],
 "next_actions":["<concrete follow-up>"],
 "reopen_triggers":["<condition>"]}

Return STRICT JSON only (no prose outside).
]], tostring(task), sel_text)

    local raw = call_llm(prompt, gen_tokens, nil)

    local parsed = {}
    if type(alc) == "table" and type(alc.json_decode) == "function" then
        local ok, p = pcall(alc.json_decode, raw)
        if ok and type(p) == "table" then parsed = p end
    end
    if parsed.answer == nil and type(raw) == "string" then
        local bracket = raw:match("(%b{})")
        if bracket and type(alc) == "table"
            and type(alc.json_decode) == "function"
        then
            local ok, p = pcall(alc.json_decode, bracket)
            if ok and type(p) == "table" then parsed = p end
        end
    end

    -- Completeness invariant: every field non-nil.
    local selected = {
        answer    = ensure_nonnil(parsed.answer, sel_text),
        rationale = ensure_nonnil(parsed.rationale, ""),
        evidence  = ensure_nonnil(parsed.evidence, {}),
    }
    if type(selected.evidence) ~= "table" then
        selected.evidence = { tostring(selected.evidence) }
    end

    local packet = {
        selected_option     = selected,
        residual_objections = ensure_nonnil(parsed.residual_objections, {}),
        minority_report     = minority_collected,
        next_actions        = ensure_nonnil(parsed.next_actions, {}),
        reopen_triggers     = ensure_nonnil(parsed.reopen_triggers, {}),
    }
    if type(packet.residual_objections) ~= "table" then
        packet.residual_objections = {}
    end
    if type(packet.next_actions) ~= "table" then
        packet.next_actions = {}
    end
    if type(packet.reopen_triggers) ~= "table" then
        packet.reopen_triggers = {}
    end

    -- Also update workspace.synthesis_in_progress / next_actions
    workspace.synthesis_in_progress = selected.answer
    for _, a in ipairs(packet.next_actions) do
        workspace.next_actions[#workspace.next_actions + 1] = tostring(a)
    end

    return packet
end

-- ─── Card IF (Two-Tier, optimize / conformal_vote pattern) ───

local function emit_card(ctx, result, history)
    if type(alc) ~= "table" or type(alc.card) ~= "table"
        or type(alc.card.create) ~= "function"
    then
        warn("dci: alc.card unavailable, card_id=nil")
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
    local pkg_name = ctx.card_pkg or ("dci_" .. task_hash)

    local dp = result.decision_packet or {}
    local card = alc.card.create({
        pkg      = { name = pkg_name },
        scenario = { name = ctx.scenario_name or "unknown" },
        params   = {
            max_rounds    = ctx.max_rounds or M._defaults.max_rounds,
            max_options   = ctx.max_options or M._defaults.max_options,
            num_finalists = ctx.num_finalists or M._defaults.num_finalists,
            gen_tokens    = ctx.gen_tokens or M._defaults.gen_tokens,
            n_roles       = #ROLES,
        },
        stats    = {
            action_equivalent = result.convergence,
            rounds_used       = (result.stats or {}).rounds_used,
            total_llm_calls   = (result.stats or {}).total_llm_calls,
        },
        dci      = {
            answer                    = result.answer,
            convergence               = result.convergence,
            selected_option           = dp.selected_option,
            residual_objections_count = #(dp.residual_objections or {}),
            minority_count            = #(dp.minority_report or {}),
            next_actions_count        = #(dp.next_actions or {}),
            reopen_triggers_count     = #(dp.reopen_triggers or {}),
            rounds_used               = (result.stats or {}).rounds_used,
            total_llm_calls           = (result.stats or {}).total_llm_calls,
            total_acts                = (result.stats or {}).total_acts,
            options_count             = (result.stats or {}).options_count,
        },
    })

    if type(card) ~= "table" or card.card_id == nil then
        warn("dci.emit_card: alc.card.create returned no card_id")
        return nil
    end

    -- Tier 2 samples: per-round per-role acts history.
    if history and #history > 0
        and type(alc.card.write_samples) == "function"
    then
        local samples = {}
        for _, h in ipairs(history) do
            local a = h.act or {}
            samples[#samples + 1] = {
                round           = h.round or 0,
                stage           = h.stage or 0,
                role            = a.author or "unknown",
                act_type        = a.type or "unknown",
                content_summary = truncate(a.content, 80),
                author          = a.author or "unknown",
            }
        end
        local ok, err = pcall(alc.card.write_samples, card.card_id, samples)
        if not ok then
            warn("dci.emit_card: alc.card.write_samples failed: "
                .. tostring(err))
        end
    end

    return card.card_id
end

-- ─── Public: run ───

function M.run(ctx)
    if type(ctx) ~= "table" then
        error("dci.run: ctx must be a table", 2)
    end
    if type(ctx.task) ~= "string" or ctx.task == "" then
        error("dci.run: ctx.task is required", 2)
    end

    local max_rounds    = ctx.max_rounds    or M._defaults.max_rounds
    local max_options   = ctx.max_options   or M._defaults.max_options
    local num_finalists = ctx.num_finalists or M._defaults.num_finalists
    local gen_tokens    = ctx.gen_tokens    or M._defaults.gen_tokens
    local roles         = ctx.roles         or ROLES

    local workspace = stage0_init(ctx.task)
    local total_llm_calls = 0
    local history = {}

    -- Stage 1: 4 × alc.llm
    local acts1 = stage1_propose(ctx.task, workspace, gen_tokens)
    total_llm_calls = total_llm_calls + #roles
    for _, a in ipairs(acts1) do
        history[#history + 1] = { stage = 1, round = 0, act = a }
    end

    -- Stage 2: 1 × alc.llm
    local options = stage2_canonicalize(acts1, max_options)
    total_llm_calls = total_llm_calls + 1

    -- Stages 3-6 loop (Rmax)
    local converged, mode = false, nil
    local rounds_used = 0
    local ranking_from_stage6 = nil

    for round = 1, max_rounds do
        rounds_used = round
        -- Stage 3: 4 × alc.llm
        local challenges = stage3_challenge(ctx.task, workspace, options,
            gen_tokens)
        total_llm_calls = total_llm_calls + #roles
        for _, a in ipairs(challenges) do
            history[#history + 1] = { stage = 3, round = round, act = a }
        end

        -- Stage 4: 4 × alc.llm
        local admits = stage4_admit(ctx.task, workspace, challenges,
            gen_tokens)
        total_llm_calls = total_llm_calls + #roles
        for _, a in ipairs(admits) do
            history[#history + 1] = { stage = 4, round = round, act = a }
        end

        -- Stage 5: 4 × alc.llm
        options = stage5_revise(ctx.task, workspace, options, num_finalists,
            gen_tokens)
        total_llm_calls = total_llm_calls + #roles

        -- Stage 6: 1 × alc.llm
        local conv = stage6_converge(ctx.task, workspace, options, nil,
            gen_tokens)
        total_llm_calls = total_llm_calls + 1
        if conv.converged then
            converged = true
            mode = conv.mode
            -- plan-gate v3 IMP: match fallback path type
            ranking_from_stage6 = {
                options = (function()
                    local opts = {}
                    for i, o in ipairs(options) do
                        opts[#opts + 1] = {
                            id      = o.id or i,
                            content = o.content,
                        }
                    end
                    return opts
                end)(),
                ranking = conv.ranking,
            }
            break
        end
    end

    -- Stage 7 fallback (unconverged case)
    local selected_option
    local final_ranking
    if not converged then
        local fallback_result = stage7_fallback(ctx.task, workspace,
            options, gen_tokens)
        final_ranking = fallback_result.ranking
        total_llm_calls = total_llm_calls + fallback_result.calls_used
        selected_option = final_ranking.ranking[1]
        mode = "fallback"
    else
        final_ranking = ranking_from_stage6
        selected_option = final_ranking.ranking[1]
    end

    -- Use the authoritative options list for Stage 8's minority report.
    local options_for_stage8 = final_ranking.options or options

    -- Stage 8: 1 × alc.llm + completeness invariant.
    local decision_packet = stage8_finalize(ctx.task, workspace,
        selected_option, options_for_stage8, history, gen_tokens)
    total_llm_calls = total_llm_calls + 1

    ctx.result = {
        answer          = decision_packet.selected_option.answer,
        decision_packet = decision_packet,
        workspace       = workspace,
        history         = history,
        convergence     = mode or "fallback",
        stats           = {
            rounds_used     = rounds_used,
            total_acts      = #history,
            options_count   = #options_for_stage8,
            total_llm_calls = total_llm_calls,
        },
    }

    if ctx.auto_card then
        local card_id = emit_card(ctx, ctx.result, history)
        if card_id ~= nil then
            ctx.result.card_id = card_id
            info("dci: card emitted — " .. tostring(card_id))
        end
    end

    return ctx
end

-- ─── Test hooks ───
M._internal = {
    ACT_CLASSES                    = ACT_CLASSES,
    ROLES                          = ROLES,
    FALLBACK_CASCADE_ORDER         = FALLBACK_CASCADE_ORDER,
    flatten_acts                   = flatten_acts,
    classify_act                   = classify_act,
    role_persona                   = role_persona,
    parse_acts_json                = parse_acts_json,
    canonicalize_options           = canonicalize_options,
    stage0_init                    = stage0_init,
    stage1_propose                 = stage1_propose,
    stage2_canonicalize            = stage2_canonicalize,
    stage3_challenge               = stage3_challenge,
    stage4_admit                   = stage4_admit,
    stage5_revise                  = stage5_revise,
    stage6_converge                = stage6_converge,
    stage7_fallback                = stage7_fallback,
    stage8_finalize                = stage8_finalize,
    fallback_outranking            = fallback_outranking,
    fallback_minimax               = fallback_minimax,
    fallback_satisficing           = fallback_satisficing,
    fallback_integrator_arbitration = fallback_integrator_arbitration,
    initial_ranking_from_options   = initial_ranking_from_options,
    emit_card                      = emit_card,
}

-- Malli-style self-decoration (see alc_shapes/instrument.lua).
M.run = S.instrument(M, "run")

return M
