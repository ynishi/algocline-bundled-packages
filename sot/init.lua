--- sot(SoT) — Skeleton-of-Thought parallel generation
---
--- Generates a structural outline first, then fills each section
--- in parallel via alc.parallel (single alc.llm_batch round-trip).
--- Produces structurally coherent long-form output.
---
--- ## Usage
---
--- ```lua
--- local sot = require("sot")
--- return sot.run(ctx)
--- ```
---
--- ## Algorithm
---
--- 1. **Skeleton generation** — prompt the LLM to produce a numbered
---    outline of up to `max_sections` section titles.
--- 2. **Parallel fill** — send all sections concurrently via
---    `alc.parallel` (single `alc.llm_batch` round-trip), each prompt
---    carrying the full outline for context so sections do not overlap.
--- 3. **Assembly** — concatenate fills under `## {title}` headings to
---    produce the final long-form output.
---
--- ## Theoretical foundations
---
--- Ning et al. (2023) demonstrate that skeleton-guided parallel decoding
--- reduces end-to-end latency by up to 2.39x on 8 of 12 tested models
--- (paper §3.1.1). The key invariant is that each section is
--- self-contained enough to be written without the other fills, which
--- the skeleton prompt enforces by asking for independently writable
--- aspects. This pkg uses `alc.parallel` (not `alc.map`) to match the
--- paper's single-batch parallel decoding claim.
---
--- ## References
---
--- - Ning, X., Lin, Z., Zhou, Z., Wang, T., Yang, H., Zhang, M., Meng, F.,
---   Zhou, J. (2023). "Skeleton-of-Thought: Prompting LLMs for Efficient
---   Parallel Generation". arXiv:2307.15337.

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "sot",
    version = "0.1.0",
    description = "Skeleton-of-Thought — outline-first parallel section generation",
    category = "generation",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task            = T.string:describe("The task requiring long-form output"),
                max_sections    = T.number:is_optional():describe("Maximum outline sections (default: 6)"),
                section_tokens  = T.number:is_optional():describe("Max tokens per section fill (default: 400)"),
                skeleton_tokens = T.number:is_optional():describe("Max tokens for skeleton generation (default: 300)"),
            }),
            result = T.shape({
                output        = T.string:describe("Final assembled long-form output (## headings + filled sections)"),
                skeleton      = T.array_of(T.string):describe("Parsed section titles from skeleton (fallback: single-element = original task)"),
                sections      = T.array_of(T.string):describe("Per-section LLM fills in the same order as skeleton"),
                section_count = T.number:describe("Count of sections parsed and filled"),
            }),
        },
    },
}

--- Parse skeleton output into section list.
--- Expects numbered headings: "1. Section Title\n2. Section Title\n..."
local function parse_skeleton(raw, max)
    local sections = {}
    for line in raw:gmatch("[^\n]+") do
        local num, title = line:match("^%s*(%d+)[%.%)%s]+(.+)")
        if title and #sections < max then
            sections[#sections + 1] = title:match("^%s*(.-)%s*$")
        end
    end
    return sections
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local max_sections = ctx.max_sections or 6
    local section_tokens = ctx.section_tokens or 400
    local skeleton_tokens = ctx.skeleton_tokens or 300

    -- Phase 1: Generate skeleton (outline)
    local skeleton_raw = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Create an outline with up to %d section headings. "
                .. "Each heading should represent a distinct, self-contained aspect. "
                .. "Order them logically.\n\n"
                .. "Output a numbered list of section titles only:\n"
                .. "1. [title]\n2. [title]\n...",
            task, max_sections
        ),
        {
            system = "You are an expert content architect. Create a clear, "
                .. "well-structured outline. Each section should be independent "
                .. "enough to be written in isolation, yet form a coherent whole.",
            max_tokens = skeleton_tokens,
        }
    )

    local sections = parse_skeleton(skeleton_raw, max_sections)

    if #sections == 0 then
        -- Fallback: single section
        sections = { task }
    end

    alc.log("info", string.format("sot: %d sections in skeleton", #sections))

    -- Phase 2: Fill sections in parallel via alc.parallel
    -- (1 round-trip via alc.llm_batch; see prelude.lua:442-515)
    local fills = alc.parallel(sections, function(section, i)
        local outline = ""
        for j, s in ipairs(sections) do
            local marker = j == i and ">>> " or "    "
            outline = outline .. string.format("%s%d. %s\n", marker, j, s)
        end
        return string.format(
            "You are writing section %d of %d for the following task.\n\n"
                .. "Overall task: %s\n\n"
                .. "Full outline:\n%s\n\n"
                .. "Write ONLY section %d: \"%s\"\n\n"
                .. "Be thorough and detailed. Do not repeat content "
                .. "that belongs in other sections.",
            i, #sections, task, outline, i, section
        )
    end, {
        system = "You are an expert writer. Write only the assigned section. "
            .. "Be aware of the full outline to avoid overlap with other sections. "
            .. "Maintain consistent tone and depth.",
        max_tokens = section_tokens,
    })

    -- Phase 3: Assemble
    local assembled = ""
    for i, section in ipairs(sections) do
        assembled = assembled .. string.format("## %s\n\n%s\n\n", section, fills[i])
    end

    ctx.result = {
        output = assembled,
        skeleton = sections,
        sections = fills,
        section_count = #sections,
    }
    return ctx
end

-- Malli-style self-decoration (see alc_shapes/README). inline T.shape
-- for both input and result; wrapper validates in ALC_SHAPE_CHECK=1.
M.run = S.instrument(M, "run")

return M
