--- Ambig — underspecification detection and clarification pipeline
---
--- Three-stage pipeline: detect ambiguity in the input, generate targeted
--- clarification questions for underspecified elements, then integrate
--- responses to produce a fully-specified task.
---
--- Based on: "Interactive Agents for Underspecified Software Engineering
--- Tasks" (ICLR 2026) — AMBIG-SWE benchmark and Clarify-Before-Code pattern
---
--- The algorithm has three phases:
---   Phase 1 (Detect): Classify input as SPECIFIED or UNDERSPECIFIED,
---           identify which elements are ambiguous
---   Phase 2 (Clarify): Generate minimal, targeted clarification questions
---           for each underspecified element
---   Phase 3 (Integrate): Merge original task + clarification responses
---           into a fully-specified task
---
--- Usage:
---   local ambig = require("ambig")
---   return ambig.run(ctx)
---
--- ctx.task (required): The task or request to analyze
--- ctx.detect_tokens: Max tokens for detection phase (default: 500)
--- ctx.clarify_tokens: Max tokens for clarification phase (default: 400)
--- ctx.integrate_tokens: Max tokens for integration phase (default: 500)

local M = {}

M.meta = {
    name = "ambig",
    version = "0.1.0",
    description = "Underspecification detection — detect-clarify-integrate pipeline for ambiguous inputs",
    category = "intent",
}

--- Parse structured elements from detection output.
--- Expects format: "- ELEMENT: description [UNDERSPECIFIED/SPECIFIED]"
local function parse_elements(raw)
    local elements = {}
    for line in raw:gmatch("[^\n]+") do
        local name, desc, status
        -- Try: "- element_name: description [STATUS]"
        name, desc = line:match("^%s*[%-*%d%.%)]+%s*(.-):%s*(.+)")
        if name and desc then
            status = "specified"
            if desc:match("%[UNDERSPECIFIED%]") or desc:match("UNDERSPECIFIED") then
                status = "underspecified"
            end
            desc = desc:gsub("%s*%[%w+%]%s*$", "")
            elements[#elements + 1] = {
                name = name:match("^%s*(.-)%s*$"),
                description = desc:match("^%s*(.-)%s*$"),
                status = status,
            }
        end
    end
    return elements
end

--- Parse numbered questions from LLM output.
local function parse_questions(raw)
    local questions = {}
    for line in raw:gmatch("[^\n]+") do
        local q = line:match("^%s*%d+[%.%)%s]+(.+)")
            or line:match("^%s*[%-*]%s+(.+)")
        if q and #q > 5 then
            questions[#questions + 1] = q:match("^%s*(.-)%s*$")
        end
    end
    return questions
end

function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local detect_tokens = ctx.detect_tokens or 500
    local clarify_tokens = ctx.clarify_tokens or 400
    local integrate_tokens = ctx.integrate_tokens or 500

    -- Phase 1: Detect — identify underspecified elements
    local detection_raw = alc.llm(
        string.format(
            "Analyze this task for underspecification:\n\"\"\"\n%s\n\"\"\"\n\n"
                .. "Identify every element that a correct implementation would need to know. "
                .. "For each element, determine if it is SPECIFIED (enough info given) "
                .. "or UNDERSPECIFIED (critical details missing that cannot be inferred).\n\n"
                .. "Categories to check:\n"
                .. "- Input format/type\n"
                .. "- Output format/type\n"
                .. "- Edge cases / boundary conditions\n"
                .. "- Constraints / requirements\n"
                .. "- Scope / what is in vs out of scope\n"
                .. "- Preferences / style / conventions\n\n"
                .. "Format each element as:\n"
                .. "- ELEMENT_NAME: description [SPECIFIED] or [UNDERSPECIFIED]\n\n"
                .. "End with a summary line:\n"
                .. "VERDICT: SPECIFIED or UNDERSPECIFIED",
            task
        ),
        {
            system = "You are a specification analyst. Identify what is missing from a task "
                .. "description that would be needed to execute it correctly. Only mark elements "
                .. "as UNDERSPECIFIED when the missing information genuinely cannot be inferred "
                .. "from context or common conventions. Do not flag obvious defaults.",
            max_tokens = detect_tokens,
        }
    )

    local elements = parse_elements(detection_raw)
    local verdict = "specified"
    if detection_raw:match("VERDICT:%s*UNDERSPECIFIED") then
        verdict = "underspecified"
    end

    alc.log("info", string.format("ambig: verdict=%s, elements=%d", verdict, #elements))

    -- If fully specified, return early
    if verdict == "specified" then
        ctx.result = {
            verdict = "specified",
            elements = elements,
            questions = {},
            specified_task = task,
            was_underspecified = false,
        }
        return ctx
    end

    -- Collect underspecified elements
    local underspec = {}
    for _, el in ipairs(elements) do
        if el.status == "underspecified" then
            underspec[#underspec + 1] = el
        end
    end

    -- Phase 2: Clarify — generate targeted questions
    local element_list = ""
    for i, el in ipairs(underspec) do
        element_list = element_list .. string.format(
            "%d. %s: %s\n", i, el.name, el.description
        )
    end

    local questions_raw = alc.llm(
        string.format(
            "Original task:\n%s\n\n"
                .. "The following elements are underspecified:\n%s\n"
                .. "Generate exactly one clarification question per element. "
                .. "Each question should:\n"
                .. "- Be specific enough to resolve the ambiguity\n"
                .. "- Suggest reasonable options when possible (e.g., 'Do you want X or Y?')\n"
                .. "- Be concise and non-technical where possible\n\n"
                .. "Format: numbered list matching the elements above.",
            task, element_list
        ),
        {
            system = "You are a requirements elicitor. Generate precise questions that "
                .. "resolve specific ambiguities. Prefer closed questions (with options) "
                .. "over open-ended ones to reduce cognitive load.",
            max_tokens = clarify_tokens,
        }
    )

    local questions = parse_questions(questions_raw)

    -- Request clarification via underspecified channel
    local combined = ""
    for i, q in ipairs(questions) do
        combined = combined .. string.format("%d. %s\n", i, q)
    end

    local user_response = alc.specify(
        string.format(
            "I found some ambiguities in your request. "
                .. "Please clarify the following:\n\n%s",
            combined
        ),
        { max_tokens = clarify_tokens }
    )

    -- Phase 3: Integrate — merge clarification into specified task
    local specified_task = alc.llm(
        string.format(
            "Original task:\n\"\"\"\n%s\n\"\"\"\n\n"
                .. "Underspecified elements:\n%s\n"
                .. "Clarification questions:\n%s\n"
                .. "User's responses:\n\"\"\"\n%s\n\"\"\"\n\n"
                .. "Rewrite the original task as a complete, unambiguous specification "
                .. "incorporating all clarified details. Output only the rewritten task.",
            task, element_list, combined, user_response
        ),
        {
            system = "You are a technical writer. Produce a clear, complete specification. "
                .. "Integrate all clarified details naturally. Do not add requirements "
                .. "beyond what the user specified.",
            max_tokens = integrate_tokens,
        }
    )

    -- Build result
    local clarifications = {}
    for i, el in ipairs(underspec) do
        clarifications[i] = {
            element = el.name,
            description = el.description,
            question = questions[i] or "",
        }
    end

    ctx.result = {
        verdict = verdict,
        elements = elements,
        questions = questions,
        clarifications = clarifications,
        user_response = user_response,
        specified_task = specified_task,
        was_underspecified = true,
    }
    return ctx
end

return M
