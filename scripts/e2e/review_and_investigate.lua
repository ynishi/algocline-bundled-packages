--- E2E: review_and_investigate (Deep code review with multi-phase investigation).
---
--- Run: agent-block -s scripts/e2e/review_and_investigate.lua -p .
---
--- Flow: Phase 1 detects issue themes (structured JSON). Phase 1.5 filters
---   intentional-design themes. Phase 2 verifies each theme against actual code.
---   Phase 3 explores related locations. Phase 4 diagnoses root cause (with
---   calibrate escalation). Phase 5 researches best practices. Phase 6
---   prescribes fix options ranked pairwise.
---   3-callsite structure: Detect/Verify/Explore are the main parallel callsites.
---
--- Graders:
---   * agent_ok                        — agent block terminated normally
---   * max_tokens(250000)              — cumulative budget guard (3 callsites, 921-line pkg)
---   * output_present                  — final output non-empty
---   * theme_count_reported            — summary.total_themes surfaced (Detect phase ran)
---   * all_three_callsites_reported    — themes[] + summary + phases 1-3 all surface
---     (3-phase complete invariant)

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local params = {
    deep_threshold = 0.6,
    max_fixes      = 2,
}

-- Short code snippet to review — small enough for a smoke E2E but with a
-- genuine detectable issue (missing input validation, no error handling).
local code_to_review = [[
function calculate_average(numbers)
    local sum = 0
    for i = 1, #numbers do
        sum = sum + numbers[i]
    end
    return sum / #numbers
end
]]

local context = "Utility function in a Lua data processing script. Called with user-provided arrays."

local prompt = string.format([[
Use algocline to run the review_and_investigate (deep code review) package.

Call alc_advice with:
- package: "review_and_investigate"
- entry: "run"
- code: %q
- opts: {
    context        = %q,
    deep_threshold = %g,
    max_fixes      = %d,
  }

Each alc.llm call inside `review_and_investigate.run` returns status
"needs_response" — reply through alc_continue with a genuine response.

Phase 1 (Detect — extract issue themes as JSON):
  Reply with JSON identifying the key issue:
  {"themes": [{"id": "T1", "name": "division_by_zero",
    "category": "logic",
    "surface_symptom": "No check for empty array before dividing by #numbers",
    "principle_violated": "defensive_programming",
    "locations": ["calculate_average:6"]}]}

Phase 1.5 (Context Filter — filter intentional-design themes):
  The issue is a genuine bug, not intentional design. Reply: "NO" (not filtered).

Phase 2 (Verify — fact-check each theme against code):
  For T1 (division_by_zero): confirm the issue exists. Reply:
  "CONFIRMED: The function does not check if #numbers == 0 before dividing,
  causing a division-by-zero error on empty input."

Phase 3 (Explore — search for related occurrences):
  Reply: "No additional related occurrences found in the provided code snippet."

Phase 4 (Diagnose — root cause with calibrate):
  For T1: reply with confidence assessment:
  "CONFIDENCE: 0.9
  ROOT_CAUSE: Missing guard clause for empty input. The function assumes
  non-empty input but has no precondition check."

Phase 5 (Research — best practice lookup):
  Reply: "Best practice: Always validate array length before division.
  Add: if #numbers == 0 then return nil, 'empty array' end"

Phase 6 (Prescribe — fix options and ranking):
  Reply with fix candidates:
  "F1: Add guard clause at function start: if #numbers == 0 then return nil end
  F2: Return 0 for empty arrays: if #numbers == 0 then return 0 end"
  For pairwise ranking: "F1 wins — returning nil with error is more correct
  than silently returning 0."

When the run completes, report DIRECTLY from the alc_advice payload:
1. summary.total_themes — count of surviving themes
2. themes — the array of theme objects with accumulated phase fields
3. summary.false_positives_removed — count removed in Phase 2 (if present)
4. The best fix recommendation from Phase 6 ranking

IMPORTANT:
- Do NOT modify opts from the values above.
- Keep responses concise — the smoke is small on purpose.
- Do NOT call alc_status, alc_log_view, or other diagnostic tools.
  After alc_advice returns its final payload (status = "ok"), extract
  the report fields DIRECTLY.
]],
    code_to_review,
    context,
    params.deep_threshold,
    params.max_fixes
)

common.run({
    name           = "review_and_investigate",
    prompt         = prompt,
    params         = params,
    max_iterations = 40,
    max_tokens_budget = 250000,
    graders = {
        common.grader_agent_ok(),
        common.grader_max_tokens(250000),
        {
            name = "output_present",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                if #c < 50 then
                    return false, "agent content too short — review_and_investigate output likely missing"
                end
                return true, nil
            end,
        },
        {
            name = "theme_count_reported",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                -- summary.total_themes surfaced = Phase 1 (Detect) completed
                if c:find("total_themes", 1, true)
                    or c:find("total themes", 1, true)
                    or c:find("themes", 1, true)
                then
                    return true, nil
                end
                return false, "total_themes / themes not surfaced — Phase 1 Detect incomplete"
            end,
        },
        {
            name = "all_three_callsites_reported",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                -- Requires evidence that all 3 callsite phases ran:
                -- Phase 1 (detect): themes / theme name present
                -- Phase 2 (verify): verification / confirmed / false_positive present
                -- Phase 3 (explore): explore / locations / related present
                local has_detect = c:find("themes", 1, true) ~= nil
                local has_verify = c:find("verif", 1, true) ~= nil
                    or c:find("confirmed", 1, true) ~= nil
                    or c:find("false_positive", 1, true) ~= nil
                local has_explore = c:find("explor", 1, true) ~= nil
                    or c:find("related", 1, true) ~= nil
                    or c:find("locations", 1, true) ~= nil
                    or c:find("root_cause", 1, true) ~= nil
                    or c:find("summary", 1, true) ~= nil
                if has_detect and has_verify and has_explore then
                    return true, nil
                end
                local missing = {}
                if not has_detect then missing[#missing + 1] = "detect" end
                if not has_verify then missing[#missing + 1] = "verify" end
                if not has_explore then missing[#missing + 1] = "explore/diagnose" end
                return false, "missing callsite phases: " .. table.concat(missing, ", ")
            end,
        },
    },
})
