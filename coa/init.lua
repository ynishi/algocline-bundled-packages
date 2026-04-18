--- coa — Chain-of-Abstraction reasoning
---
--- Generates reasoning chains with abstract placeholders instead of concrete
--- facts, then grounds them via parallel knowledge lookups. Decouples the
--- reasoning structure from specific knowledge, enabling parallel tool calls
--- and cleaner reasoning chains.
---
--- Key difference from faithful: faithful formalizes reasoning into code/logic
--- for verification (internal consistency). CoA abstracts away concrete knowledge
--- during reasoning and injects it afterward (external knowledge integration).
--- The two are complementary: CoA grounds knowledge, faithful verifies logic.
---
--- Based on: Gao et al., "Chain-of-Abstraction: Solving Elaborate Problems
--- via Abstraction Chains" (Meta/EPFL, COLING 2025, arXiv:2401.17464)
---
--- Pipeline (2 + N LLM calls):
---   Step 1: Abstract    — generate reasoning with [FUNC ...] placeholders
---   Step 2: Ground      — resolve placeholders via LLM knowledge (parallel)
---   Step 3: Answer      — produce final answer from grounded chain
---
--- Usage:
---   local coa = require("coa")
---   return coa.run(ctx)
---
--- ctx.task (required): The problem to solve
--- ctx.tools: Tool name → description table (default: { knowledge = "..." })
--- ctx.max_depth: Max dependency resolution depth (default: 3)
--- ctx.gen_tokens: Max tokens for abstract chain (default: 600)
--- ctx.ground_tokens: Max tokens per grounding call (default: 300)

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "coa",
    version = "0.1.0",
    description = "Chain-of-Abstraction — reason with abstract placeholders, "
        .. "then ground via parallel knowledge resolution. Decouples reasoning "
        .. "structure from concrete facts.",
    category = "reasoning",
}

local grounding_entry_shape = T.shape({
    var    = T.string:describe("Placeholder variable name (e.g., 'y1', 'y2')"),
    tool   = T.string:describe("Tool name selected by the abstract chain"),
    query  = T.string:describe("Resolved query after earlier variables are substituted"),
    result = T.string:describe("LLM-resolved value for this placeholder"),
    depth  = T.number:describe("Resolution pass depth (1-based); dependent placeholders resolve at higher depths"),
})

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task          = T.string:describe("Problem to solve (required)"),
                tools         = T.map_of(T.string, T.string):is_optional()
                    :describe("tool_name → description; defaults to a single 'knowledge' tool"),
                max_depth     = T.number:is_optional():describe("Max dependency-resolution depth (default 3)"),
                gen_tokens    = T.number:is_optional():describe("Max tokens for the abstract chain and final answer (default 600)"),
                ground_tokens = T.number:is_optional():describe("Max tokens per grounding call (default 300)"),
            }),
            result = T.shape({
                answer                 = T.string:describe("Final answer produced from the grounded chain"),
                abstract_chain         = T.string:describe("Raw abstract chain with [FUNC tool(\"query\") = yN] placeholders"),
                grounded_chain         = T.string:describe("Chain after placeholder substitution"),
                groundings             = T.array_of(grounding_entry_shape)
                    :describe("Per-placeholder resolution trace in resolution order"),
                placeholders_resolved  = T.number:describe("Count of placeholders actually resolved"),
                tools_used             = T.map_of(T.string, T.string)
                    :describe("Echo of the tools map used for this run"),
            }),
        },
    },
}

--- Extract placeholders from abstract chain.
--- Pattern: [FUNC tool_name("query") = yN]
--- Returns list of { full_match, tool, query, var_name }
local function extract_placeholders(chain)
    local placeholders = {}
    local seen = {}

    for full, tool, query, var in chain:gmatch(
        "(%[FUNC%s+(%w+)%(\"(.-)\"%)?%s*=%s*(y%d+)%])"
    ) do
        if not seen[var] then
            seen[var] = true
            placeholders[#placeholders + 1] = {
                full_match = full,
                tool = tool,
                query = query,
                var_name = var,
            }
        end
    end

    return placeholders
end

--- Check if a placeholder's query references unresolved variables.
local function has_unresolved_deps(placeholder, resolved_vars)
    return placeholder.query:match("y%d+") ~= nil
        and not resolved_vars[placeholder.query:match("y%d+")]
end

--- Filter placeholders into independent (resolvable now) and dependent.
local function partition_placeholders(placeholders, resolved_vars)
    local independent = {}
    local dependent = {}

    for _, ph in ipairs(placeholders) do
        -- Check if query contains any unresolved yN references
        local has_dep = false
        for var in ph.query:gmatch("y%d+") do
            if not resolved_vars[var] then
                has_dep = true
                break
            end
        end

        if has_dep then
            dependent[#dependent + 1] = ph
        else
            independent[#independent + 1] = ph
        end
    end

    return independent, dependent
end

--- Substitute resolved values into the chain text.
local function substitute(chain, var_name, value)
    -- Replace the placeholder variable reference with its value
    return chain:gsub(var_name, value)
end

--- Build tool description string for the prompt.
local function format_tools(tools)
    local parts = {}
    for name, desc in pairs(tools) do
        parts[#parts + 1] = string.format("- %s: %s", name, desc)
    end
    return table.concat(parts, "\n")
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local tools = ctx.tools or {
        knowledge = "general knowledge lookup — facts, definitions, data",
    }
    local max_depth = ctx.max_depth or 3
    local gen_tokens = ctx.gen_tokens or 600
    local ground_tokens = ctx.ground_tokens or 300

    local tool_desc = format_tools(tools)

    -- ─── Step 1: Generate abstract reasoning chain ───
    alc.log("info", "coa: Step 1 — generating abstract reasoning chain")

    local abstract_chain = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Available knowledge tools:\n%s\n\n"
                .. "Generate a reasoning chain to solve this task. When you need "
                .. "a specific fact, calculation, or piece of knowledge, insert "
                .. "a placeholder instead of guessing.\n\n"
                .. "Placeholder format: [FUNC tool_name(\"query\") = yN]\n\n"
                .. "Rules:\n"
                .. "- Use y1, y2, y3... for each distinct piece of knowledge needed\n"
                .. "- Reuse the same yN if the same fact is needed again\n"
                .. "- Later placeholders can reference earlier ones: "
                .. "[FUNC knowledge(\"population of y1\") = y3]\n"
                .. "- Focus on the REASONING STRUCTURE — the placeholders will be "
                .. "filled in later\n\n"
                .. "Example:\n"
                .. "To find the GDP per capita of the country with the longest river:\n"
                .. "[FUNC knowledge(\"which country has the longest river\") = y1]\n"
                .. "[FUNC knowledge(\"GDP of y1\") = y2]\n"
                .. "[FUNC knowledge(\"population of y1\") = y3]\n"
                .. "GDP per capita = y2 / y3",
            task, tool_desc
        ),
        {
            system = "You are a reasoning architect. Build the reasoning structure "
                .. "using abstract placeholders for any concrete knowledge. Focus on "
                .. "the logical flow, not the specific facts. Use [FUNC tool(\"query\") = yN] "
                .. "for every fact or computation you need.",
            max_tokens = gen_tokens,
        }
    )

    -- ─── Step 2: Ground placeholders (topological order, parallel batches) ───
    alc.log("info", "coa: Step 2 — grounding placeholders")

    local grounded_chain = abstract_chain
    local resolved_vars = {}
    local grounding_log = {}
    local total_grounded = 0

    for depth = 1, max_depth do
        local all_placeholders = extract_placeholders(grounded_chain)

        -- Filter out already resolved
        local unresolved = {}
        for _, ph in ipairs(all_placeholders) do
            if not resolved_vars[ph.var_name] then
                unresolved[#unresolved + 1] = ph
            end
        end

        if #unresolved == 0 then
            alc.log("info", string.format(
                "coa: all placeholders resolved at depth %d", depth
            ))
            break
        end

        local independent, dependent = partition_placeholders(unresolved, resolved_vars)

        if #independent == 0 then
            alc.log("warn", "coa: circular dependency detected, forcing resolution")
            independent = { unresolved[1] }
        end

        alc.log("info", string.format(
            "coa: depth %d — resolving %d independent placeholders (%d dependent remaining)",
            depth, #independent, #dependent
        ))

        -- Resolve independent placeholders in parallel
        local results = alc.map(independent, function(ph)
            -- Substitute any already-resolved variables in the query
            local resolved_query = ph.query
            for var, val in pairs(resolved_vars) do
                resolved_query = resolved_query:gsub(var, val)
            end

            return alc.llm(
                string.format(
                    "Answer the following query concisely and factually:\n\n%s\n\n"
                        .. "Provide only the answer — no explanation, no preamble.",
                    resolved_query
                ),
                {
                    system = "You are a precise knowledge source. Answer with just "
                        .. "the fact requested. Be concise and accurate.",
                    max_tokens = ground_tokens,
                }
            )
        end)

        -- Apply results
        for i, ph in ipairs(independent) do
            local value = results[i] or "UNKNOWN"
            -- Clean up — take first line, trim
            value = value:match("^%s*(.-)%s*$") or value
            local first_line = value:match("([^\n]+)")
            if first_line and #first_line < #value and #first_line > 5 then
                value = first_line
            end

            resolved_vars[ph.var_name] = value
            total_grounded = total_grounded + 1

            grounding_log[#grounding_log + 1] = {
                var = ph.var_name,
                tool = ph.tool,
                query = ph.query,
                result = value,
                depth = depth,
            }

            -- Replace the full placeholder expression with the resolved value
            grounded_chain = grounded_chain:gsub(
                "%[FUNC%s+" .. ph.tool .. "%(\"" .. ph.query:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1") .. "\"%)?%s*=%s*" .. ph.var_name .. "%]",
                value
            )
            -- Also replace standalone variable references
            grounded_chain = grounded_chain:gsub(ph.var_name, value)
        end
    end

    alc.log("info", string.format(
        "coa: grounding complete — %d placeholders resolved", total_grounded
    ))

    -- ─── Step 3: Produce final answer from grounded chain ───
    alc.log("info", "coa: Step 3 — producing final answer")

    local answer = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Reasoning chain (with all knowledge filled in):\n\"\"\"\n%s\n\"\"\"\n\n"
                .. "Based on this grounded reasoning, provide a clear and "
                .. "comprehensive final answer.",
            task, grounded_chain
        ),
        {
            system = "You are an expert. The reasoning chain has been grounded "
                .. "with verified knowledge. Produce a final answer that follows "
                .. "from the chain. Be clear and thorough.",
            max_tokens = gen_tokens,
        }
    )

    ctx.result = {
        answer = answer,
        abstract_chain = abstract_chain,
        grounded_chain = grounded_chain,
        groundings = grounding_log,
        placeholders_resolved = total_grounded,
        tools_used = tools,
    }
    return ctx
end

M.run = S.instrument(M, "run")

return M
