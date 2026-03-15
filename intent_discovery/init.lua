--- Intent Discovery — exploratory intent formation through action
---
--- Users often approach tasks without fully-formed goals. This strategy
--- helps users discover their intent by presenting structured options,
--- observing preferences, and progressively concretizing a hierarchy
--- of intents through iterative exploration.
---
--- Based on: "DiscoverLLM: From Executing Intents to Discovering Them"
--- (2026, arXiv:2602.03429)
---
--- Core insight from cognitive science: in open-ended problems, people
--- discover what they need by exploring possible outcomes. Understanding
--- of a problem and its solutions co-evolve.
---
--- The algorithm has three phases per round:
---   Phase 1 (Surface): Present structured options that span the solution space
---   Phase 2 (Observe): Capture user preference/reaction
---   Phase 3 (Concretize): Narrow the intent hierarchy based on feedback
---   Repeat until intent is sufficiently concrete or max rounds reached
---
--- Usage:
---   local intent_discovery = require("intent_discovery")
---   return intent_discovery.run(ctx)
---
--- ctx.task (required): The initial (possibly vague) user request
--- ctx.max_rounds: Maximum exploration rounds (default: 3)
--- ctx.n_options: Number of options to present per round (default: 3)
--- ctx.surface_tokens: Max tokens for option generation (default: 600)
--- ctx.concretize_tokens: Max tokens for concretization (default: 500)

local M = {}

M.meta = {
    name = "intent_discovery",
    version = "0.1.0",
    description = "Exploratory intent formation — discover user goals through structured option presentation and iterative narrowing",
    category = "intent",
}

--- Parse structured options from LLM output.
--- Expects format like:
---   Option A: title — description
---   Option B: title — description
local function parse_options(raw)
    local options = {}
    for line in raw:gmatch("[^\n]+") do
        local label, rest = line:match("^%s*Option%s+(%w+)[:%.]%s*(.+)")
        if not label then
            label, rest = line:match("^%s*(%w+)[%.%)]+%s*(.+)")
        end
        if label and rest and #rest > 5 then
            local title, desc = rest:match("^(.-)%s*[%—%-%-]+%s*(.+)")
            if not title then
                title = rest
                desc = ""
            end
            options[#options + 1] = {
                label = label,
                title = (title or ""):match("^%s*(.-)%s*$"),
                description = (desc or ""):match("^%s*(.-)%s*$"),
            }
        end
    end
    return options
end

function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local max_rounds = ctx.max_rounds or 3
    local n_options = ctx.n_options or 3
    local surface_tokens = ctx.surface_tokens or 600
    local concretize_tokens = ctx.concretize_tokens or 500

    local intent_hierarchy = {}
    local exploration_log = {}
    local current_understanding = task

    for round = 1, max_rounds do
        alc.log("info", string.format("intent_discovery: round %d/%d", round, max_rounds))

        -- Phase 1: Surface — generate structured options
        local history_block = ""
        if #exploration_log > 0 then
            history_block = "\n\nExploration history:\n"
            for i, entry in ipairs(exploration_log) do
                history_block = history_block .. string.format(
                    "Round %d: Presented %d options, user chose: %s\n",
                    i, #entry.options, entry.preference
                )
            end
        end

        local options_raw = alc.llm(
            string.format(
                "User's request: %s\n\n"
                    .. "Current understanding of intent:\n%s\n%s\n"
                    .. "Generate exactly %d distinct approaches/options that span "
                    .. "the solution space for this request. Each option should:\n"
                    .. "- Represent a meaningfully different direction\n"
                    .. "- Be concrete enough for the user to evaluate\n"
                    .. "- Help narrow down what the user actually wants\n\n"
                    .. "Format each as:\n"
                    .. "Option A: Title — Brief description of this approach\n"
                    .. "Option B: Title — Brief description of this approach\n...\n\n"
                    .. "After the options, add:\n"
                    .. "KEY_DIMENSION: What fundamental choice do these options represent?",
                task, current_understanding, history_block, n_options
            ),
            {
                system = "You are an intent discovery specialist. Your goal is NOT to answer "
                    .. "the user's question, but to help them discover what they actually want "
                    .. "by presenting meaningfully different options. Each option should reveal "
                    .. "a different assumption about what the user needs. Cover the space, "
                    .. "don't cluster around one interpretation.",
                max_tokens = surface_tokens,
            }
        )

        local options = parse_options(options_raw)
        local key_dimension = options_raw:match("KEY_DIMENSION:%s*(.+)") or ""

        if #options == 0 then
            alc.log("warn", "intent_discovery: failed to parse options, ending exploration")
            break
        end

        -- Phase 2: Observe — capture user preference
        local options_display = ""
        for i, opt in ipairs(options) do
            options_display = options_display .. string.format(
                "%s. %s — %s\n", opt.label, opt.title, opt.description
            )
        end

        local preference = alc.specify(
            string.format(
                "To better understand what you need, here are %d different approaches:\n\n"
                    .. "%s\n"
                    .. "Which option best matches your intent? You can also:\n"
                    .. "- Choose one and explain why\n"
                    .. "- Combine elements from multiple options\n"
                    .. "- Describe something different entirely",
                #options, options_display
            ),
            { max_tokens = concretize_tokens }
        )

        exploration_log[#exploration_log + 1] = {
            round = round,
            options = options,
            key_dimension = key_dimension,
            preference = preference,
        }

        -- Phase 3: Concretize — update intent hierarchy
        local concretized = alc.llm(
            string.format(
                "Original request: %s\n\n"
                    .. "Options presented:\n%s\n"
                    .. "User's response:\n%s\n\n"
                    .. "Based on the user's response, update the understanding of their intent.\n\n"
                    .. "Produce:\n"
                    .. "1. RESOLVED: List of aspects that are now clear\n"
                    .. "2. REMAINING: List of aspects still unclear\n"
                    .. "3. UPDATED_INTENT: Rewrite the request with all resolved details\n"
                    .. "4. CONVERGENCE: YES if the intent is sufficiently concrete to execute, NO otherwise",
                task, options_display, preference
            ),
            {
                system = "You are an intent analyst. Precisely track what has been resolved "
                    .. "and what remains ambiguous. Do not assume details the user did not confirm.",
                max_tokens = concretize_tokens,
            }
        )

        -- Extract updated understanding
        local updated = concretized:match("UPDATED_INTENT:%s*(.-)%s*\n%d")
            or concretized:match("UPDATED_INTENT:%s*(.-)%s*CONVERGENCE")
            or concretized:match("UPDATED_INTENT:%s*(.+)")
            or current_understanding
        current_understanding = updated:match("^%s*(.-)%s*$") or updated

        -- Extract resolved/remaining
        local resolved_block = concretized:match("RESOLVED:%s*(.-)%s*REMAINING") or ""
        local remaining_block = concretized:match("REMAINING:%s*(.-)%s*UPDATED_INTENT") or ""

        intent_hierarchy[round] = {
            resolved = resolved_block,
            remaining = remaining_block,
            understanding = current_understanding,
        }

        -- Check convergence
        if concretized:match("CONVERGENCE:%s*YES") then
            alc.log("info", string.format(
                "intent_discovery: converged at round %d", round))
            break
        end
    end

    ctx.result = {
        original_task = task,
        specified_task = current_understanding,
        rounds = #exploration_log,
        exploration_log = exploration_log,
        intent_hierarchy = intent_hierarchy,
        converged = #exploration_log < max_rounds
            or (intent_hierarchy[#exploration_log] or {}).remaining == "",
    }
    return ctx
end

return M
