--- SoT — Skeleton-of-Thought parallel generation
---
--- Generates a structural outline first, then fills each section
--- in parallel via alc.map. Produces structurally coherent long-form output.
---
--- Based on: Ning et al., "Skeleton-of-Thought: LLMs Can Do Parallel
--- Decoding" (2023, arXiv:2307.15337)
---
--- Usage:
---   local sot = require("sot")
---   return sot.run(ctx)
---
--- ctx.task (required): The task requiring long-form output
--- ctx.max_sections: Maximum outline sections (default: 6)
--- ctx.section_tokens: Max tokens per section fill (default: 400)
--- ctx.skeleton_tokens: Max tokens for skeleton generation (default: 300)

local M = {}

M.meta = {
    name = "sot",
    version = "0.1.0",
    description = "Skeleton-of-Thought — outline-first parallel section generation",
    category = "generation",
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

    -- Phase 2: Fill sections in parallel
    local fills = alc.map(sections, function(section, i)
        return alc.llm(
            string.format(
                "You are writing section %d of %d for the following task.\n\n"
                    .. "Overall task: %s\n\n"
                    .. "Full outline:\n%s\n\n"
                    .. "Write ONLY section %d: \"%s\"\n\n"
                    .. "Be thorough and detailed. Do not repeat content "
                    .. "that belongs in other sections.",
                i, #sections, task,
                (function()
                    local outline = ""
                    for j, s in ipairs(sections) do
                        local marker = j == i and ">>> " or "    "
                        outline = outline .. string.format("%s%d. %s\n", marker, j, s)
                    end
                    return outline
                end)(),
                i, section
            ),
            {
                system = "You are an expert writer. Write only the assigned section. "
                    .. "Be aware of the full outline to avoid overlap with other sections. "
                    .. "Maintain consistent tone and depth.",
                max_tokens = section_tokens,
            }
        )
    end)

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

return M
