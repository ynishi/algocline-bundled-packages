--- E2E: dci (Prakash 2026, arXiv:2603.11781).
---
--- Run: agent-block -s scripts/e2e/dci.lua -p .
---
--- Flow: open-ended design decision task routed through DCI-CF.
---   4 roles (Framer / Explorer / Challenger / Integrator) × 14 typed
---   epistemic acts × 8-stage convergence. Forces a decision_packet
---   with first-class minority_report preservation.
---
--- Graders (issue §10 acceptance criteria):
---   * agent_ok                     — agent block terminated normally
---   * content_contains(event-sourcing) — task topic is discussed
---   * decision_packet_complete     — 5 components non-empty in report
---   * minority_report_preserved    — minority_report length >= 1
---   * convergence_recorded         — convergence ∈ {"dominance",
---                                                    "no_blocking",
---                                                    "fallback"}
---   * max_tokens(500000)           — 62× single-agent margin per §10

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

--- Search the agent's turn_history for a raw MCP tool_response that
--- carries the dci decision_packet. Returns the matched response text
--- (JSON-ish string) or nil.
---
--- Why: the agent's final `content` paraphrases pkg return values into
--- human-readable markdown ("**Selected Option**"), which forces the
--- text-match graders below into a snake_case ↔ title-case dual match
--- that is still prone to false positives (e.g. the phrase "no
--- minority report was included" would substring-match "minority
--- report"). The raw tool_response from `alc_run` / `alc_advice`
--- contains the dci shape verbatim in snake_case, which is both
--- strict and unambiguous.
---
--- Heuristic: a response that mentions `decision_packet` *and* the 5
--- required component keys is the one we want. If turn_history is
--- missing (e.g. old run) the graders fall back to the text match.
local function extract_decision_packet_raw(result)
    local hist = result and result.turn_history
    if type(hist) ~= "table" then return nil end
    local REQUIRED = {
        "decision_packet",
        "selected_option",
        "residual_objections",
        "minority_report",
        "next_actions",
        "reopen_triggers",
    }
    for _, turn in ipairs(hist) do
        local resps = turn.tool_responses
        if type(resps) == "table" then
            for _, r in ipairs(resps) do
                local text
                if type(r) == "string" then
                    text = r
                elseif type(r) == "table" then
                    text = r.content or r.text or r.body
                    -- Agent-block sometimes wraps content as a nested
                    -- list of {type="text", text=...} entries.
                    if type(text) == "table" then
                        local parts = {}
                        for _, sub in ipairs(text) do
                            if type(sub) == "table" and type(sub.text) == "string" then
                                parts[#parts + 1] = sub.text
                            elseif type(sub) == "string" then
                                parts[#parts + 1] = sub
                            end
                        end
                        text = table.concat(parts, "\n")
                    end
                end
                if type(text) == "string" then
                    local all = true
                    for _, key in ipairs(REQUIRED) do
                        if not text:find(key, 1, true) then all = false; break end
                    end
                    if all then return text end
                end
            end
        end
    end
    return nil
end

local params = {
    task = "Should our team adopt event-sourcing for the order service?",
    max_rounds    = 2,
    max_options   = 5,
    num_finalists = 3,
    gen_tokens    = 400,
}

local prompt = string.format([[
Use algocline to run the dci (Deliberative Collective Intelligence)
package on an open-ended design decision with 4 roles (Framer /
Explorer / Challenger / Integrator) and Rmax = 2.

Call alc_advice with:
- package: "dci"
- task: %q
- opts: {
    max_rounds    = %d,
    max_options   = %d,
    num_finalists = %d,
    gen_tokens    = %d,
  }

Each alc.llm call inside `dci.run` returns status "needs_response" —
reply through alc_continue with your genuine per-role reasoning.

The 8 stages you will participate in:
  Stage 1 — independent proposals (you are each role in turn)
  Stage 2 — canonicalize / cluster into options
  Stages 3-6 — loop up to Rmax = 2:
    3 challenges / evidence
    4 admit new hypotheses
    5 revise & compress
    6 convergence test (dominance / no_blocking / none)
  Stage 7 — fallback cascade (outranking → minimax → satisficing →
             integrator arbitration) if unconverged
  Stage 8 — finalize the decision packet (5 components non-nil)

When Stage 1 or Stage 3 prompts you for acts, return STRICT JSON of
the form:
  {"acts":[
    {"type":"propose","content":"<1-3 sentences>","author":"<role>"}
  ]}

When canonicalize / revise prompts you, return STRICT JSON:
  {"options":[{"id":1,"content":"<text>","author":"integrator"}]}

When Stage 6 prompts you for the convergence test, return STRICT JSON:
  {"mode":"dominance"|"no_blocking"|"none",
   "ranking":[{"option_id":1,"score":0.8,"rationale":"<text>"}],
   "blocking_objections":["<text>"]}

When Stage 8 prompts you for finalize, return STRICT JSON:
  {"answer":"<final answer>",
   "rationale":"<why>",
   "evidence":["<snippet>"],
   "residual_objections":["<text>"],
   "next_actions":["<concrete>"],
   "reopen_triggers":["<condition>"]}

When the run completes, report:
1. answer (final decision — pro or con event-sourcing)
2. decision_packet with all 5 components:
   - selected_option (answer / rationale / evidence)
   - residual_objections
   - minority_report
   - next_actions
   - reopen_triggers
3. convergence ("dominance" / "no_blocking" / "fallback")
4. workspace 6 fields (problem_view, key_frames, emerging_ideas,
   tensions, synthesis_in_progress, next_actions)
5. stats (rounds_used, total_acts, options_count, total_llm_calls)

IMPORTANT: include "event-sourcing" in your final answer text,
whether for or against. Preserve the minority_report even if one
option strongly dominates — §5.3 of the paper requires dissenting
positions to survive to the final packet.
]],
    params.task,
    params.max_rounds,
    params.max_options,
    params.num_finalists,
    params.gen_tokens
)

common.run({
    name = "dci",
    prompt = prompt,
    params = params,
    max_iterations = 60,
    graders = {
        common.grader_agent_ok(),
        common.grader_max_tokens(500000),
        common.grader_content_contains("event-sourcing"),
        {
            name = "decision_packet_complete",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                -- Primary: inspect raw MCP tool_response (snake_case,
                -- authoritative). This is the strict path — the raw
                -- dci.run return value contains every shape key
                -- verbatim, so a simple substring check against the
                -- JSON-ish payload cannot be defeated by the agent
                -- paraphrasing field names in its final summary.
                local raw = extract_decision_packet_raw(result)
                if raw then
                    for _, key in ipairs({
                        "selected_option",
                        "residual_objections",
                        "minority_report",
                        "next_actions",
                        "reopen_triggers",
                    }) do
                        if not raw:find(key, 1, true) then
                            return false, "raw decision_packet missing: " .. key
                        end
                    end
                    return true, nil
                end
                -- Fallback: text match against agent's content. Used
                -- when turn_history is unavailable (older runs / agent
                -- harness variants). Fragile against agent paraphrasing
                -- and false-positive substring matches (e.g. "no
                -- minority report was included" would still match
                -- "minority report"). Accept snake_case *or* space-
                -- separated form to absorb the most common paraphrase.
                local c = (result.content or ""):lower()
                local patterns = {
                    selected_option     = { "selected_option",     "selected option" },
                    residual_objections = { "residual_objections", "residual objections" },
                    minority_report     = { "minority_report",     "minority report" },
                    next_actions        = { "next_actions",        "next actions" },
                    reopen_triggers     = { "reopen_triggers",     "reopen triggers" },
                }
                for key, alts in pairs(patterns) do
                    local found = false
                    for _, pat in ipairs(alts) do
                        if c:find(pat, 1, true) then
                            found = true
                            break
                        end
                    end
                    if not found then
                        return false, "missing component (text fallback): " .. key
                    end
                end
                return true, nil
            end,
        },
        {
            name = "minority_report_preserved",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                -- Primary: raw tool_response. Require an actual
                -- minority_report entry with at least one non-empty
                -- member (the dci shape emits a list of {position,
                -- rationale} pairs). Substring check for the shape
                -- key + one of the expected inner field names is a
                -- tight-enough approximation without a JSON parser.
                local raw = extract_decision_packet_raw(result)
                if raw then
                    if not raw:find("minority_report", 1, true) then
                        return false, "raw minority_report absent"
                    end
                    if raw:find("position", 1, true)
                        or raw:find("rationale", 1, true)
                        or raw:find("dissent", 1, true)
                    then
                        return true, nil
                    end
                    return false, "raw minority_report empty "
                        .. "(no position/rationale/dissent)"
                end
                -- Fallback: content text. Same fragility caveat as
                -- decision_packet_complete above — "no minority
                -- report was included" would erroneously satisfy the
                -- "mentions" check. Acceptable because this path only
                -- fires when the authoritative turn_history is missing.
                local c = (result.content or ""):lower()
                local mentions = c:find("minority_report", 1, true)
                    or c:find("minority report", 1, true)
                if not mentions then
                    return false, "minority_report absent (text fallback)"
                end
                if c:find("position", 1, true)
                    or c:find("rationale", 1, true)
                    or c:find("dissent", 1, true)
                then
                    return true, nil
                end
                return false, "minority_report empty (text fallback: "
                    .. "no position/rationale/dissent)"
            end,
        },
        {
            name = "convergence_recorded",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("dominance", 1, true)
                    or c:find("no_blocking", 1, true)
                    or c:find("fallback", 1, true)
                then
                    return true, nil
                end
                return false, "convergence not in "
                    .. "{dominance, no_blocking, fallback}"
            end,
        },
    },
})
