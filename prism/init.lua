--- Prism — cognitive-load-aware intent decomposition and logical clarification
---
--- Decomposes complex user intents into structured sub-intents, identifies
--- logical dependencies among them, and generates clarification questions
--- in dependency order to minimize user cognitive load.
---
--- Based on: "Prism: Towards Lowering User Cognitive Load in LLMs via
--- Complex Intent Understanding" (2026, arXiv:2601.08653)
---
--- The algorithm has three phases:
---   Phase 1 (Decompose): Break task into atomic sub-intents
---   Phase 2 (Dependency): Identify logical dependencies between sub-intents
---   Phase 3 (Clarify): Generate clarification questions in topological order,
---           then integrate responses into a fully-specified task
---
--- Usage:
---   local prism = require("prism")
---   return prism.run(ctx)
---
--- ctx.task (required): The task or request to analyze
--- ctx.max_sub_intents: Maximum sub-intents to extract (default: 8)
--- ctx.decompose_tokens: Max tokens for decomposition (default: 600)
--- ctx.clarify_tokens: Max tokens per clarification phase (default: 400)

local M = {}

---@type AlcMeta
M.meta = {
    name = "prism",
    version = "0.1.0",
    description = "Cognitive-load-aware intent decomposition — logical dependency ordering for minimal-friction clarification",
    category = "intent",
}

--- Parse a numbered list from LLM output.
local function parse_numbered_list(raw)
    local items = {}
    for line in raw:gmatch("[^\n]+") do
        local item = line:match("^%s*%d+[%.%)%s]+(.+)")
            or line:match("^%s*[%-*]%s+(.+)")
        if item and #item > 3 then
            items[#items + 1] = item:match("^%s*(.-)%s*$")
        end
    end
    return items
end

--- Parse dependency pairs from LLM output.
--- Expects lines like: "A -> B" or "1 -> 3" or "intent_a depends on intent_b"
local function parse_dependencies(raw, n_intents)
    local deps = {}
    for line in raw:gmatch("[^\n]+") do
        local from, to = line:match("(%d+)%s*%->%s*(%d+)")
        if not from then
            from, to = line:match("(%d+)%s+depends%s+on%s+(%d+)")
        end
        if from and to then
            local f = tonumber(from)
            local t = tonumber(to)
            if f and t and f >= 1 and f <= n_intents and t >= 1 and t <= n_intents and f ~= t then
                deps[#deps + 1] = { from = f, to = t }
            end
        end
    end
    return deps
end

--- Topological sort of sub-intents based on dependencies.
--- Returns ordered indices. Falls back to natural order on cycle.
local function topo_sort(n, deps)
    local adj = {}
    local in_degree = {}
    for i = 1, n do
        adj[i] = {}
        in_degree[i] = 0
    end
    for _, d in ipairs(deps) do
        adj[d.to][#adj[d.to] + 1] = d.from
        in_degree[d.from] = in_degree[d.from] + 1
    end

    local queue = {}
    for i = 1, n do
        if in_degree[i] == 0 then
            queue[#queue + 1] = i
        end
    end

    local order = {}
    local head = 1
    while head <= #queue do
        local node = queue[head]
        head = head + 1
        order[#order + 1] = node
        for _, next_node in ipairs(adj[node]) do
            in_degree[next_node] = in_degree[next_node] - 1
            if in_degree[next_node] == 0 then
                queue[#queue + 1] = next_node
            end
        end
    end

    -- Cycle detected: fall back to natural order
    if #order < n then
        order = {}
        for i = 1, n do order[i] = i end
    end

    return order
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local max_sub_intents = ctx.max_sub_intents or 8
    local decompose_tokens = ctx.decompose_tokens or 600
    local clarify_tokens = ctx.clarify_tokens or 400

    -- Phase 1: Decompose into atomic sub-intents
    local decomp_raw = alc.llm(
        string.format(
            "User request:\n\"\"\"\n%s\n\"\"\"\n\n"
                .. "Decompose this request into atomic sub-intents. Each sub-intent should be:\n"
                .. "- A single, well-defined goal or requirement\n"
                .. "- Independent enough to be addressed separately\n"
                .. "- Specific (not vague restatements of the original)\n\n"
                .. "For each sub-intent, mark its specification status:\n"
                .. "- [SPECIFIED] if the user has provided enough information\n"
                .. "- [UNDERSPECIFIED] if critical details are missing\n\n"
                .. "Output at most %d sub-intents as a numbered list:\n"
                .. "1. [STATUS] sub-intent description",
            task, max_sub_intents
        ),
        {
            system = "You are an intent analyst. Decompose user requests into the smallest "
                .. "meaningful sub-intents. Be precise about what is specified vs missing. "
                .. "Do not invent requirements the user did not express.",
            max_tokens = decompose_tokens,
        }
    )

    local sub_intents_raw = parse_numbered_list(decomp_raw)
    local sub_intents = {}
    for i, raw in ipairs(sub_intents_raw) do
        local status = "specified"
        if raw:match("%[UNDERSPECIFIED%]") then
            status = "underspecified"
        end
        local text = raw:gsub("%[%w+%]%s*", "")
        sub_intents[i] = { text = text, status = status }
    end

    alc.log("info", string.format("prism: %d sub-intents extracted", #sub_intents))

    -- Check if anything is underspecified
    local underspec_indices = {}
    for i, si in ipairs(sub_intents) do
        if si.status == "underspecified" then
            underspec_indices[#underspec_indices + 1] = i
        end
    end

    if #underspec_indices == 0 then
        ctx.result = {
            sub_intents = sub_intents,
            dependencies = {},
            clarifications = {},
            specified_task = task,
            was_underspecified = false,
        }
        return ctx
    end

    -- Phase 2: Identify logical dependencies among underspecified sub-intents
    local intent_list = ""
    for i, si in ipairs(sub_intents) do
        intent_list = intent_list .. string.format("%d. [%s] %s\n",
            i, si.status:upper(), si.text)
    end

    local dep_raw = alc.llm(
        string.format(
            "Sub-intents:\n%s\n"
                .. "Identify logical dependencies between these sub-intents. "
                .. "A dependency means that clarifying one sub-intent requires "
                .. "first knowing the answer to another.\n\n"
                .. "Format each dependency as: FROM -> TO\n"
                .. "(meaning FROM depends on TO, so TO should be clarified first)\n\n"
                .. "If there are no dependencies, write: NONE\n"
                .. "Only include dependencies between UNDERSPECIFIED sub-intents.",
            intent_list
        ),
        {
            system = "You are a dependency analyst. Identify only genuine logical "
                .. "dependencies where the answer to one question constrains "
                .. "the answer to another. Do not invent spurious dependencies.",
            max_tokens = 300,
        }
    )

    local dependencies = {}
    if not dep_raw:match("NONE") then
        dependencies = parse_dependencies(dep_raw, #sub_intents)
    end

    -- Phase 3: Generate clarification questions in topological order
    local order = topo_sort(#sub_intents, dependencies)

    -- Filter to only underspecified, in dependency order
    local ordered_underspec = {}
    for _, idx in ipairs(order) do
        if sub_intents[idx].status == "underspecified" then
            ordered_underspec[#ordered_underspec + 1] = idx
        end
    end

    -- Build ordered questions
    local questions_prompt = ""
    for rank, idx in ipairs(ordered_underspec) do
        questions_prompt = questions_prompt .. string.format(
            "%d. Sub-intent #%d: %s\n", rank, idx, sub_intents[idx].text
        )
    end

    local questions_raw = alc.llm(
        string.format(
            "Original request: %s\n\n"
                .. "The following sub-intents need clarification, listed in dependency order "
                .. "(earlier questions should be answered before later ones):\n%s\n"
                .. "Generate one clear, concise clarification question for each. "
                .. "Questions should be answerable without technical expertise. "
                .. "Format: numbered list matching the order above.",
            task, questions_prompt
        ),
        {
            system = "You are a UX specialist. Write clarification questions that are "
                .. "easy to understand, non-leading, and cover exactly what is missing. "
                .. "Minimize cognitive load: each question should be self-contained.",
            max_tokens = clarify_tokens,
        }
    )

    local questions = parse_numbered_list(questions_raw)

    -- Request clarification via underspecified channel
    local combined_questions = ""
    for i, q in ipairs(questions) do
        combined_questions = combined_questions .. string.format("%d. %s\n", i, q)
    end

    local user_response = alc.specify(
        string.format(
            "To proceed with your request, I need clarification on the following "
                .. "(ordered by dependency — earlier answers may affect later questions):\n\n%s",
            combined_questions
        ),
        { max_tokens = clarify_tokens }
    )

    -- Phase 4: Integrate clarification into fully-specified task
    local specified_task = alc.llm(
        string.format(
            "Original request:\n%s\n\n"
                .. "Clarification questions and responses:\n%s\n\nUser's answers:\n%s\n\n"
                .. "Rewrite the original request as a fully-specified task that incorporates "
                .. "all clarified details. Output only the rewritten task, nothing else.",
            task, combined_questions, user_response
        ),
        {
            system = "You are a requirements engineer. Produce a clear, complete, "
                .. "unambiguous task specification. Preserve the user's original intent "
                .. "while incorporating all clarified details.",
            max_tokens = clarify_tokens,
        }
    )

    local clarifications = {}
    for i, idx in ipairs(ordered_underspec) do
        clarifications[i] = {
            sub_intent_index = idx,
            sub_intent = sub_intents[idx].text,
            question = questions[i] or "",
        }
    end

    ctx.result = {
        sub_intents = sub_intents,
        dependencies = dependencies,
        clarifications = clarifications,
        user_response = user_response,
        specified_task = specified_task,
        was_underspecified = true,
    }
    return ctx
end

return M
