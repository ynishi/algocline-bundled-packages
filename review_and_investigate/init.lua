--- review_and_investigate — deep code review with fact-checking and root-cause analysis
---
--- Combinator package: orchestrates reflect, calibrate, factscore, triad,
--- panel, rank to perform multi-phase investigative code review.
---
--- Key insight: alc.llm() returns to the Host (Coding Agent) via MCP Sampling.
--- The Host has Grep/Read/Bash tools, so each phase prompt can instruct the Host
--- to actually explore the codebase and return fact-based findings.
---
--- Pipeline:
---   Phase 1:   Detect         — scan code, extract issue themes (structured JSON)
---   Phase 1.5: Context Filter — early elimination of intentional-design themes based on ctx.context (lightweight LLM YES/NO)
---   Phase 2:   Verify         — fact-check each theme against actual code (confirmed/false_positive)
---   Phase 3: Explore   — comprehensive codebase search for related occurrences
---   Phase 4: Diagnose  — identify root cause (surface symptom → structural cause)
---              └─ calibrate: low confidence → Deep analysis via triad/panel
---   Phase 5: Research  — best-practice lookup, gap analysis
---   Phase 6: Prescribe — enumerate fix options, rate by policy, rank pairwise
---
--- Usage:
---   local ri = require("review_and_investigate")
---   return ri.run(ctx)
---
--- ctx.code (required): Source code or diff to review
--- ctx.context: Additional context about the codebase (free text).
---   Injected into Phase 1/2/4 prompts so the LLM understands design
---   constraints, framework requirements, known trade-offs, etc.
---   Example: "rmcp framework constraint requires Result<String,String>. Local dev tool."
--- ctx.policy: Review policy table (default: built-in)
---   { priorities = {"non_breaking", "correctness", "testability", ...} }
--- ctx.deep_threshold: Confidence threshold for deep analysis (default: 0.6)
--- ctx.max_fixes: Max fix candidates per theme (default: 3)

local S = require("alc_shapes")
local T = S.T

local M = {}

--- UTF-8 safe truncate: find last valid boundary at or before max_bytes.
local function utf8_truncate(s, max_bytes)
    if #s <= max_bytes then return s end
    local pos = max_bytes
    -- Skip continuation bytes (10xxxxxx = 0x80..0xBF)
    while pos > 0 and s:byte(pos) >= 0x80 and s:byte(pos) <= 0xBF do
        pos = pos - 1
    end
    -- pos now points to a leading byte of an incomplete char; exclude it
    if pos > 0 and s:byte(pos) >= 0x80 then
        pos = pos - 1
    end
    return s:sub(1, pos)
end

---@type AlcMeta
M.meta = {
    name = "review_and_investigate",
    version = "0.1.0",
    description = "Deep code review with investigation — detect, verify, explore, diagnose, research, prescribe",
    category = "combinator",
}

-- Shape sub-definitions. Themes accumulate fields across 6 phases,
-- so most per-theme fields are :is_optional(). Three early-return
-- paths also trim the summary; the summary shape below is a flat
-- union (everything except total_themes is optional).

local expert_consultation_shape = T.shape({
    role     = T.string:describe("Expert role label (echo of meta_prompt.experts_consulted[].role)"),
    focus    = T.string:describe("Expert focus area"),
    question = T.string:describe("Question posed to the expert"),
    response = T.string:describe("Expert's response"),
})

local contrast_shape = T.shape({
    wrong_reasoning = T.string:describe("Plausible-but-incorrect reasoning path (from contrastive.contrasts)"),
    error_analysis  = T.string:describe("Analysis of the error and its correct replacement"),
})

local deep_analysis_shape = T.shape({
    verdict = T.string:is_optional():describe("Full triad verdict text"),
    winner  = T.string:is_optional():describe("Triad winner label (proponent|opponent|unknown)"),
})

local fix_shape = T.shape({
    id       = T.string:is_optional():describe("Fix id such as 'F1', 'F2'"),
    summary  = T.string:is_optional():describe("Short fix summary"),
    approach = T.string:is_optional():describe("Concrete fix approach"),
    impact   = T.string:is_optional():describe("Impact scope"),
    risk     = T.string:is_optional():describe("Risk description"),
    avoids   = T.string:is_optional():describe("Which anti-pattern the fix explicitly avoids"),
})

local match_log_shape = T.shape({
    a      = T.string:describe("Left competitor fix id"),
    b      = T.string:describe("Right competitor fix id"),
    winner = T.string:describe("Winning fix id"),
    reason = T.string:describe("LLM judge's reason text"),
})

local ranking_shape = T.shape({
    best    = fix_shape:describe("The tournament winner"),
    matches = T.array_of(match_log_shape):describe("Pairwise match log of the tournament"),
})

local theme_shape = T.shape({
    -- Detect phase (always set on themes that reach downstream phases)
    id                   = T.string:is_optional():describe("Theme id parsed from detect JSON (e.g., 'T1')"),
    name                 = T.string:describe("Theme name; required because logs and prompts format with it"),
    category             = T.string:is_optional():describe("safety|logic|design|performance|style (LLM-chosen)"),
    surface_symptom      = T.string:is_optional():describe("Description of the surface symptom"),
    principle_violated   = T.string:is_optional():describe("Which design principle this theme violates"),
    locations            = T.array_of(T.string):is_optional():describe("file:line or function name references"),
    span                 = T.array_of(T.number):is_optional():describe("[start_line, end_line] 1-indexed line range"),
    -- Verify phase
    verification         = T.string:is_optional():describe("Confirmed rationale text from Phase 2"),
    -- Explore phase
    related_locations    = T.array_of(T.string):is_optional():describe("Additional locations found by Phase 3 exploration"),
    search_pattern       = T.string:is_optional():describe("Grep pattern used by Phase 3"),
    total_occurrences    = T.number:is_optional():describe("Count of related occurrences found in Phase 3"),
    -- Diagnose phase
    expert_consultations = T.array_of(expert_consultation_shape):is_optional():describe("meta_prompt consultation log"),
    root_cause           = T.string:is_optional():describe("Structural root-cause analysis text"),
    diagnosis_confidence = T.number:is_optional():describe("calibrate confidence in [0, 1]"),
    diagnosis_escalated  = T.boolean:is_optional():describe("Whether calibrate escalated to retry"),
    deep_analysis        = deep_analysis_shape:is_optional():describe("Triad debate result when confidence < threshold"),
    -- Research phase
    best_practice        = T.string:is_optional():describe("Summary of best-practice guidance"),
    current_state        = T.string:is_optional():describe("Summary of current implementation state"),
    gap                  = T.string:is_optional():describe("Gap between BP and current state"),
    references           = T.array_of(T.string):is_optional():describe("References cited in Phase 5 research"),
    -- Prescribe phase
    fix_anti_patterns    = T.array_of(contrast_shape):is_optional():describe("contrastive.contrasts capturing common fix anti-patterns"),
    fixes                = T.array_of(fix_shape):is_optional():describe("Fix candidates proposed for the theme"),
    ranking              = ranking_shape:is_optional():describe("Pairwise tournament ranking of fixes (only when >= 2 fixes)"),
})

local policy_shape = T.shape({
    priorities       = T.array_of(T.string):is_optional():describe("Ordered policy priorities (e.g., 'correctness' > 'non_breaking' > ...)"),
    severity_weights = T.map_of(T.string, T.number):is_optional():describe("severity label → numeric weight"),
})

local summary_shape = T.shape({
    total_themes            = T.number:describe("Surviving theme count; always set"),
    false_positives_removed = T.number:is_optional():describe("Count removed by Phase 2 (verify); absent on the no-themes-at-detect and context-filter-all paths"),
    by_category             = T.map_of(T.string, T.number):is_optional():describe("Distribution over theme.category; present only on the full-run path"),
    deep_analyzed           = T.number:is_optional():describe("Count of themes that went through the triad deep-analysis branch"),
    policy_applied          = T.string:is_optional():describe("Policy priorities joined with ' > '"),
    context_filtered        = T.boolean:is_optional():describe("True on the Phase-1.5 context-filter-all-themes early-return path"),
})

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                code            = T.string:describe("Source code or diff to review (required)"),
                context         = T.string:is_optional():describe("Free-text design context used in Phase 1/1.5/2/4"),
                policy          = policy_shape:is_optional():describe("Review policy (default: correctness > non_breaking > safety > testability > maintainability)"),
                deep_threshold  = T.number:is_optional():describe("Confidence threshold below which the diagnose phase escalates to triad (default 0.6)"),
                max_fixes       = T.number:is_optional():describe("Max fix candidates per theme (default 3)"),
            }),
            result = T.shape({
                themes  = T.array_of(theme_shape):describe("Surviving themes with accumulated per-phase fields; empty on any early-return path"),
                summary = summary_shape:describe("Run summary; field presence varies by early-return path (see summary_shape)"),
            }),
        },
    },
}

--- Extract the code slice for a theme using its span [start, end].
--- Falls back to full code if span is missing or invalid.
local function slice_code(code, theme)
    local span = theme.span
    if type(span) ~= "table" or #span < 2 then return code end
    local s, e = tonumber(span[1]), tonumber(span[2])
    if not s or not e or s < 1 then return code end

    local lines = {}
    for line in (code .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = line
    end
    e = math.min(e, #lines)
    if s > e then return code end

    local parts = {}
    for i = s, e do
        parts[#parts + 1] = string.format("%4d: %s", i, lines[i])
    end
    return table.concat(parts, "\n")
end

-- ─── Default Policy ────────────────────────────────────────

local DEFAULT_POLICY = {
    priorities = {
        "correctness",       -- correctness first
        "non_breaking",      -- preserve existing API
        "safety",            -- memory safety & security
        "testability",       -- testability
        "maintainability",   -- maintainability
    },
    severity_weights = {
        critical = 10,
        high = 7,
        medium = 4,
        low = 1,
    },
}

-- ─── Phase 1: Detect ──────────────────────────────────────

--- Scan code and extract issue themes as structured data.
--- Uses step_back to first abstract the code's design intent, then detect
--- deviations from that intent as themes. This reduces surface-level false positives.
--- Returns a list of theme tables: { id, name, category, surface_symptom, locations }
local function phase_detect(code, context)
    alc.log("info", "review_and_investigate: Phase 1 — Detect (step_back-enhanced)")

    local step_back = require("step_back")

    local context_block = ""
    if context ~= "" then
        context_block = string.format(
            "\n\n[Design Context]\n%s\nGiven the above, exclude issues that stem from known constraints or intentional design.\n",
            context
        )
    end

    -- Step 1a: step_back — abstract the code's design intent and principles
    local abstraction_ctx = step_back.run({
        task = string.format(
            "Analyze this code and identify its design intent, architectural principles, "
                .. "and key invariants.\n\n```\n%s\n```\n%s\n"
                .. "What are the underlying design principles this code is trying to follow?",
            code, context_block
        ),
        abstraction_levels = 1,
        domain_hint = "software engineering / code review",
    })

    local design_principles = abstraction_ctx.result.answer or ""
    alc.log("info", "review_and_investigate: step_back — design principles extracted")

    -- Step 1b: detect themes as deviations from the abstracted principles
    local raw = alc.llm(
        string.format(
            "You have analyzed the following code and identified its design principles.\n\n"
                .. "Design principles:\n%s\n\n"
                .. "Code:\n```\n%s\n```\n%s\n"
                .. "Now identify issue themes — places where the implementation DEVIATES from "
                .. "or VIOLATES these design principles.\n\n"
                .. "For each theme, output in the following JSON array format (no other text):\n"
                .. '[\n'
                .. '  {\n'
                .. '    "id": "T1",\n'
                .. '    "name": "theme-name (e.g. error-handling-design)",\n'
                .. '    "category": "safety|logic|design|performance|style",\n'
                .. '    "surface_symptom": "description of the surface symptom",\n'
                .. '    "principle_violated": "which design principle this violates",\n'
                .. '    "locations": ["file:line or function name"],\n'
                .. '    "span": [start_line, end_line]\n'
                .. '  }\n'
                .. ']\n\n'
                .. "IMPORTANT: \"span\" is the line range [start, end] (1-indexed) of the "
                .. "relevant code region for this theme. Include enough context to understand "
                .. "the issue but no more.\n\n"
                .. "Do not stop at surface-level observations (e.g. unwrap→expect).\n"
                .. "Prioritize structural deviations from the identified design principles.",
            design_principles, code, context_block
        ),
        {
            system = "You are a senior code analyst. You detect deviations from design intent, "
                .. "not just surface-level lint. Output ONLY valid JSON array.",
            max_tokens = 800,
        }
    )

    -- Parse JSON
    local themes = alc.json_decode(raw)
    if type(themes) ~= "table" then
        alc.log("warn", "review_and_investigate: Phase 1 parse failed, retrying with stricter prompt")
        -- Fallback: try to extract JSON from mixed output
        local json_str = raw:match("%[.+%]")
        if json_str then
            themes = alc.json_decode(json_str)
        end
    end

    if type(themes) ~= "table" or #themes == 0 then
        return {}
    end

    alc.log("info", string.format("review_and_investigate: %d themes detected", #themes))
    return themes
end

-- ─── Phase 1.5: Context Filter ──────────────────────────────

--- Early elimination of themes matching intentional design or known constraints
--- based on ctx.context. Lightweight LLM call (100-200 chars) for YES/NO per theme.
local function phase_context_filter(themes, context)
    alc.log("info", "review_and_investigate: Phase 1.5 — Context Filter")

    local filtered = {}
    local removed = 0

    for _, theme in ipairs(themes) do
        local answer = alc.llm(
            string.format(
                "Given the design context below, should this theme be ignored because it is intentional design, a known constraint, or equivalent attack surface?\n\n"
                    .. "Theme: %s\n"
                    .. "Description: %s\n\n"
                    .. "Design context:\n%s\n\n"
                    .. "Answer YES (should be ignored) or NO (should be reviewed) only. Add a one-sentence reason.",
                theme.name or "",
                theme.description or "",
                context
            ),
            { max_tokens = 200 }
        )

        if answer:upper():match("^%s*YES") then
            removed = removed + 1
            alc.log("info", string.format(
                "  [FILTERED] %s — %s", theme.name or "", utf8_truncate(answer, 80)
            ))
        else
            filtered[#filtered + 1] = theme
        end
    end

    alc.log("info", string.format(
        "review_and_investigate: context filter — %d kept, %d removed",
        #filtered, removed
    ))

    return filtered
end

-- ─── Phase 2: Verify ──────────────────────────────────────

--- Fact-check each theme against actual code.
--- Returns only confirmed themes (false_positives removed).
local function phase_verify(themes, code, context)
    alc.log("info", "review_and_investigate: Phase 2 — Verify")

    local context_block = ""
    if context ~= "" then
        context_block = string.format(
            "\n\n[Design Context]\n%s\n",
            context
        )
    end

    local verified = {}
    local false_positives = 0

    local results = alc.map(themes, function(theme)
        return alc.llm(
            string.format(
                "Verify whether the following review finding is factually correct by checking the code.\n\n"
                    .. "Theme: %s\n"
                    .. "Surface symptom: %s\n"
                    .. "Reported locations: %s\n\n"
                    .. "Code:\n```\n%s\n```\n%s\n"
                    .. "Verification checklist:\n"
                    .. "1. Does the reported location actually exist in the code?\n"
                    .. "2. Does the surface symptom match the actual code behavior?\n"
                    .. "3. Is this a false positive? (consider intentional design)\n\n"
                    .. "Answer in one of these formats (first line only):\n"
                    .. "CONFIRMED: [factual basis in one sentence]\n"
                    .. "or\n"
                    .. "FALSE_POSITIVE: [reason in one sentence]",
                theme.name,
                theme.surface_symptom or "",
                alc.json_encode(theme.locations or {}),
                code,
                context_block
            ),
            {
                system = "You are a fact-checker. Verify claims against actual code. "
                    .. "Be strict — if you cannot verify the claim with concrete code evidence, "
                    .. "mark FALSE_POSITIVE.",
                max_tokens = 200,
                grounded = true,
            }
        )
    end)

    for i, result in ipairs(results) do
        if result:match("^%s*FALSE_POSITIVE") or result:match("FALSE_POSITIVE") then
            false_positives = false_positives + 1
            alc.log("info", string.format("  [FP] %s", themes[i].name))
        else
            themes[i].verification = result:match("CONFIRMED:%s*(.+)") or result
            verified[#verified + 1] = themes[i]
            alc.log("info", string.format("  [OK] %s", themes[i].name))
        end
    end

    alc.log("info", string.format(
        "review_and_investigate: %d confirmed, %d false positives removed",
        #verified, false_positives
    ))

    return verified, false_positives
end

-- ─── Phase 3: Explore ─────────────────────────────────────

--- For each confirmed theme, search the entire codebase for related occurrences.
local function phase_explore(themes, code)
    alc.log("info", "review_and_investigate: Phase 3 — Explore")

    local results = alc.map(themes, function(theme)
        local exploration = alc.llm(
            string.format(
                "For the theme \"%s\", comprehensively investigate the entire codebase for related occurrences.\n\n"
                    .. "Surface symptom: %s\n"
                    .. "Known locations: %s\n\n"
                    .. "Target code:\n```\n%s\n```\n\n"
                    .. "Steps:\n"
                    .. "1. Search for related patterns using Grep\n"
                    .. "2. Confirm each found location by reading context with Read\n"
                    .. "3. List all locations sharing the same structural issue\n\n"
                    .. "Output format (JSON):\n"
                    .. '{"related_locations": ["file:line — description"], "pattern": "search pattern used", "total_occurrences": N}',
                theme.name,
                theme.surface_symptom or "",
                alc.json_encode(theme.locations or {}),
                code
            ),
            {
                system = "You are a codebase investigator. Use Grep and Read tools to "
                    .. "find ALL related occurrences, not just the initially reported one. "
                    .. "Be thorough. Output ONLY valid JSON.",
                max_tokens = 500,
            }
        )

        -- Parse exploration result
        local data = alc.json_decode(exploration)
        if type(data) ~= "table" then
            local json_str = exploration:match("%{.+%}")
            if json_str then data = alc.json_decode(json_str) end
        end

        return {
            theme = theme,
            related = data and data.related_locations or {},
            pattern = data and data.pattern or "",
            total = data and data.total_occurrences or 0,
        }
    end)

    -- Merge exploration results back into themes
    for _, r in ipairs(results) do
        r.theme.related_locations = r.related
        r.theme.search_pattern = r.pattern
        r.theme.total_occurrences = r.total
    end

    return themes
end

-- ─── Phase 4: Diagnose ────────────────────────────────────

--- Identify root cause for each theme.
--- 1. meta_prompt: dispatch to domain-specific experts based on theme category
--- 2. reflect: self-critique the expert diagnosis for intentional design
--- 3. calibrate: confidence gating
--- 4. triad: if low confidence, debate with related data
--- Themes diagnosed as intentional design are removed from the pipeline.
local function phase_diagnose(themes, code, deep_threshold, context)
    alc.log("info", "review_and_investigate: Phase 4 — Diagnose (meta_prompt-enhanced)")

    local meta_prompt = require("meta_prompt")
    local reflect = require("reflect")
    local calibrate = require("calibrate")
    local triad = require("triad")

    local context_block = ""
    if context ~= "" then
        context_block = string.format(
            "\n\n[Design Context]\n%s\n",
            context
        )
    end

    local confirmed = {}
    local reclassified = 0

    for i, theme in ipairs(themes) do
        local snippet = slice_code(code, theme)

        -- Step 1: meta_prompt — dispatch to domain-specific experts
        local expert_ctx = meta_prompt.run({
            task = string.format(
                "Diagnose the root cause of the following code issue.\n\n"
                    .. "Theme: %s (category: %s)\n"
                    .. "Surface symptom: %s\n"
                    .. "Related locations (%d occurrences): %s\n\n"
                    .. "Code:\n```\n%s\n```\n%s\n"
                    .. "Identify the structural root cause, not just the surface symptom.",
                theme.name,
                theme.category or "unknown",
                theme.surface_symptom or "",
                theme.total_occurrences or 0,
                alc.json_encode(theme.related_locations or {}),
                snippet,
                context_block
            ),
            max_experts = 3,
        })

        local expert_diagnosis = expert_ctx.result.answer or ""
        theme.expert_consultations = expert_ctx.result.experts_consulted

        alc.log("info", string.format(
            "  [META] %s — %d experts consulted",
            theme.name, expert_ctx.result.total_experts or 0
        ))

        -- Step 2: reflect — self-critique the expert diagnosis for intentional design
        local reflect_ctx = reflect.run({
            task = string.format(
                "Review the following expert diagnosis and determine if the issue is "
                    .. "a genuine problem or intentional design.\n\n"
                    .. "Theme: \"%s\"\n"
                    .. "Expert diagnosis:\n%s\n\n"
                    .. "Code:\n```\n%s\n```\n%s\n"
                    .. "Decision procedure:\n"
                    .. "1. Does the expert diagnosis identify a real structural problem?\n"
                    .. "2. Could this be intentional design (deliberate trade-off, safe-side fallback)?\n"
                    .. "3. If intentional design, start with INTENTIONAL_DESIGN: and state the reason\n"
                    .. "4. If a genuine problem, summarize the structural root cause",
                theme.name,
                expert_diagnosis,
                snippet,
                context_block
            ),
            max_rounds = 2,
            stop_when = "no_major_issues",
        })

        local answer = reflect_ctx.result.output or ""

        -- Gate: intentional design → remove from pipeline
        if answer:match("INTENTIONAL_DESIGN") then
            reclassified = reclassified + 1
            alc.log("info", string.format(
                "  [INTENTIONAL] %s — removed from pipeline",
                theme.name
            ))
        else
            -- Step 2: calibrate — confidence gating on root cause
            local diagnosis_ctx = calibrate.run({
                task = string.format(
                    "Evaluate the validity of the following root cause analysis.\n\n"
                        .. "Theme: %s\n"
                        .. "Analysis result:\n%s\n\n"
                        .. "Is this analysis accurate? Is the evidence sufficient?",
                    theme.name, answer
                ),
                threshold = deep_threshold,
                fallback = "retry",
            })

            theme.root_cause = answer
            theme.diagnosis_confidence = diagnosis_ctx.result.confidence
            theme.diagnosis_escalated = diagnosis_ctx.result.escalated

            -- Step 3: triad — if low confidence, debate with related data
            if diagnosis_ctx.result.confidence < deep_threshold then
                alc.log("info", string.format(
                    "  [DEEP] %s (confidence=%.2f < %.2f)",
                    theme.name, diagnosis_ctx.result.confidence, deep_threshold
                ))

                local debate_ctx = triad.run({
                    task = string.format(
                        "Debate the root cause of the theme \"%s\".\n\n"
                            .. "Initial diagnosis: %s\n"
                            .. "Surface symptom: %s\n"
                            .. "Related locations (%d occurrences): %s\n\n"
                            .. "Code:\n```\n%s\n```\n\n"
                            .. "Proponent: This diagnosis is correct and a structural fix is needed\n"
                            .. "Opponent: This diagnosis is excessive and a local fix is sufficient",
                        theme.name,
                        theme.root_cause or "",
                        theme.surface_symptom or "",
                        theme.total_occurrences or 0,
                        alc.json_encode(theme.related_locations or {}),
                        snippet
                    ),
                    rounds = 2,
                })

                theme.deep_analysis = {
                    verdict = debate_ctx.result.verdict,
                    winner = debate_ctx.result.winner,
                }
            end

            confirmed[#confirmed + 1] = theme
            alc.log("info", string.format("  [OK] %s", theme.name))
        end
    end

    alc.log("info", string.format(
        "review_and_investigate: %d confirmed, %d reclassified as intentional design",
        #confirmed, reclassified
    ))

    return confirmed
end

-- ─── Phase 5: Research ────────────────────────────────────

--- Look up best practices for each theme and perform gap analysis.
local function phase_research(themes, code)
    alc.log("info", "review_and_investigate: Phase 5 — Research")

    local results = alc.map(themes, function(theme)
        return alc.llm(
            string.format(
                "For the theme \"%s\", research best practices and analyze the gap with the current implementation.\n\n"
                    .. "Root cause: %s\n"
                    .. "Related locations: %d occurrences\n\n"
                    .. "Code:\n```\n%s\n```\n\n"
                    .. "Output format (JSON):\n"
                    .. '{\n'
                    .. '  "best_practice": "summary of BP (with sources)",\n'
                    .. '  "current_state": "summary of current state",\n'
                    .. '  "gap": "gap between BP and current state",\n'
                    .. '  "references": ["source 1", "source 2"]\n'
                    .. '}',
                theme.name,
                theme.root_cause or "",
                theme.total_occurrences or 0,
                slice_code(code, theme)
            ),
            {
                system = "You are a best-practice researcher. Cite specific sources: "
                    .. "Effective Rust, Rust API Guidelines, OWASP, relevant RFCs, "
                    .. "seminal papers. Output ONLY valid JSON.",
                max_tokens = 400,
                grounded = true,
            }
        )
    end)

    for i, raw in ipairs(results) do
        local data = alc.json_decode(raw)
        if type(data) ~= "table" then
            local json_str = raw:match("%{.+%}")
            if json_str then data = alc.json_decode(json_str) end
        end
        themes[i].best_practice = data and data.best_practice or ""
        themes[i].current_state = data and data.current_state or ""
        themes[i].gap = data and data.gap or ""
        themes[i].references = data and data.references or {}
    end

    return themes
end

-- ─── Phase 6: Prescribe ───────────────────────────────────

--- Compare two fix candidates via LLM-as-Judge pairwise comparison.
local function compare_fixes(theme_name, fix_a, fix_b, policy_text)
    local verdict = alc.llm(
        string.format(
            "Compare two fix proposals for the theme \"%s\".\n\n"
                .. "Policy priorities: %s\n\n"
                .. "--- Fix A ---\n%s: %s\nApproach: %s\nImpact: %s\nRisk: %s\n\n"
                .. "--- Fix B ---\n%s: %s\nApproach: %s\nImpact: %s\nRisk: %s\n\n"
                .. "Which is better according to the policy priorities?\n"
                .. "Answer: WINNER: A or B (one word), followed by a one-sentence reason.",
            theme_name, policy_text,
            fix_a.id or "A", fix_a.summary or "", fix_a.approach or "",
            fix_a.impact or "", fix_a.risk or "",
            fix_b.id or "B", fix_b.summary or "", fix_b.approach or "",
            fix_b.impact or "", fix_b.risk or ""
        ),
        {
            system = "You are an impartial judge comparing fix proposals. "
                .. "Evaluate strictly by the stated policy priorities.",
            max_tokens = 150,
        }
    )

    local winner = "A"
    if verdict:match("WINNER:%s*B") or verdict:match("^%s*B") then
        winner = "B"
    end
    return winner, verdict
end

--- Enumerate fix candidates, rate by policy, rank pairwise.
--- Uses contrastive to first identify common fix anti-patterns, then generate
--- fixes that explicitly avoid those pitfalls.
local function phase_prescribe(themes, code, policy, max_fixes)
    alc.log("info", "review_and_investigate: Phase 6 — Prescribe (contrastive-enhanced)")

    local contrastive = require("contrastive")
    local policy_text = table.concat(policy.priorities, " > ")

    for _, theme in ipairs(themes) do
        -- Step 6a: contrastive — identify common fix anti-patterns for this theme
        local anti_ctx = contrastive.run({
            task = string.format(
                "What are common WRONG approaches to fixing the issue \"%s\"?\n\n"
                    .. "Root cause: %s\n"
                    .. "Best practice: %s\n"
                    .. "Gap: %s\n\n"
                    .. "Identify subtle mistakes developers commonly make when attempting to fix "
                    .. "this type of issue (e.g. surface-level patches that don't address root cause, "
                    .. "over-engineering, breaking API compatibility, etc.)",
                theme.name,
                theme.root_cause or "",
                theme.best_practice or "",
                theme.gap or ""
            ),
            n_contrasts = 1,
        })

        local anti_patterns = anti_ctx.result.answer or ""
        theme.fix_anti_patterns = anti_ctx.result.contrasts

        alc.log("info", string.format(
            "  [CONTRASTIVE] %s — anti-patterns identified", theme.name
        ))

        -- Step 6b: generate fix candidates, informed by anti-patterns
        local raw = alc.llm(
            string.format(
                "Propose %d fix candidates for the theme \"%s\".\n\n"
                    .. "Root cause: %s\n"
                    .. "BP: %s\n"
                    .. "Gap: %s\n\n"
                    .. "CRITICAL — Avoid these common fix anti-patterns:\n%s\n\n"
                    .. "Code:\n```\n%s\n```\n\n"
                    .. "Output each fix as a JSON array:\n"
                    .. '[\n'
                    .. '  {\n'
                    .. '    "id": "F1",\n'
                    .. '    "summary": "fix summary",\n'
                    .. '    "approach": "concrete approach",\n'
                    .. '    "impact": "impact scope",\n'
                    .. '    "risk": "risk",\n'
                    .. '    "avoids": "which anti-pattern this explicitly avoids"\n'
                    .. '  }\n'
                    .. ']\n\n'
                    .. "Policy priorities: %s",
                max_fixes,
                theme.name,
                theme.root_cause or "",
                theme.best_practice or "",
                theme.gap or "",
                anti_patterns,
                slice_code(code, theme),
                policy_text
            ),
            {
                system = "You are a solution architect. Propose concrete, actionable fixes. "
                    .. "Each fix must respect the policy priorities and EXPLICITLY avoid "
                    .. "the identified anti-patterns. Output ONLY valid JSON array.",
                max_tokens = 600,
            }
        )

        local fixes = alc.json_decode(raw)
        if type(fixes) ~= "table" then
            local json_str = raw:match("%[.+%]")
            if json_str then fixes = alc.json_decode(json_str) end
        end

        if type(fixes) == "table" and #fixes > 1 then
            -- Pairwise tournament to find best fix
            local bracket = {}
            for i, fix in ipairs(fixes) do
                bracket[i] = { fix = fix, wins = 0 }
            end

            local match_log = {}
            while #bracket > 1 do
                local next_round = {}
                for i = 1, #bracket, 2 do
                    if i + 1 <= #bracket then
                        local a = bracket[i]
                        local b = bracket[i + 1]
                        local winner_label, reason = compare_fixes(
                            theme.name, a.fix, b.fix, policy_text
                        )
                        local winner
                        if winner_label == "A" then
                            winner = a
                        else
                            winner = b
                        end
                        winner.wins = winner.wins + 1
                        match_log[#match_log + 1] = {
                            a = a.fix.id or "?",
                            b = b.fix.id or "?",
                            winner = winner.fix.id or "?",
                            reason = reason,
                        }
                        next_round[#next_round + 1] = winner
                    else
                        next_round[#next_round + 1] = bracket[i]
                    end
                end
                bracket = next_round
            end

            theme.fixes = fixes
            theme.ranking = {
                best = bracket[1].fix,
                matches = match_log,
            }
        else
            theme.fixes = fixes or {}
            theme.ranking = nil
        end
    end

    return themes
end

-- ─── Summary Builder ──────────────────────────────────────

local function build_summary(themes, false_positives, policy)
    local by_category = {}
    for _, theme in ipairs(themes) do
        local cat = theme.category or "unknown"
        by_category[cat] = (by_category[cat] or 0) + 1
    end

    return {
        total_themes = #themes,
        false_positives_removed = false_positives,
        by_category = by_category,
        deep_analyzed = (function()
            local count = 0
            for _, t in ipairs(themes) do
                if t.deep_analysis then count = count + 1 end
            end
            return count
        end)(),
        policy_applied = table.concat(policy.priorities, " > "),
    }
end

-- ─── Entry Point ──────────────────────────────────────────

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local code = ctx.code or error("ctx.code is required")
    local context = ctx.context or ""
    local policy = ctx.policy or DEFAULT_POLICY
    local deep_threshold = ctx.deep_threshold or 0.6
    local max_fixes = ctx.max_fixes or 3
    -- Phase 1: Detect
    local themes = phase_detect(code, context)
    if #themes == 0 then
        ctx.result = {
            themes = {},
            summary = { total_themes = 0, false_positives_removed = 0 },
        }
        return ctx
    end

    -- Phase 1.5: Context Filter — early elimination of intentional-design themes based on ctx.context
    if context ~= "" then
        themes = phase_context_filter(themes, context)
        if #themes == 0 then
            ctx.result = {
                themes = {},
                summary = { total_themes = 0, context_filtered = true },
            }
            return ctx
        end
    end

    -- Phase 2: Verify (gate: remove false positives)
    local themes, false_positives = phase_verify(themes, code, context)
    if #themes == 0 then
        ctx.result = {
            themes = {},
            summary = {
                total_themes = 0,
                false_positives_removed = false_positives,
            },
        }
        return ctx
    end

    -- Phase 3: Explore
    themes = phase_explore(themes, code)

    -- Phase 4: Diagnose (with calibrate → deep analysis gate)
    themes = phase_diagnose(themes, code, deep_threshold, context)

    -- Phase 5: Research
    themes = phase_research(themes, code)

    -- Phase 6: Prescribe (with rank)
    themes = phase_prescribe(themes, code, policy, max_fixes)

    ctx.result = {
        themes = themes,
        summary = build_summary(themes, false_positives, policy),
    }
    return ctx
end

M.run = S.instrument(M, "run")

return M
