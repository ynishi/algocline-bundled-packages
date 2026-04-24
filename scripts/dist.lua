--- scripts/dist.lua — headless `alc_hub_dist` driver via agent-block.
---
--- Reuses the E2E common harness to spawn a ReAct agent whose sole job
--- is to invoke the `alc_hub_dist` MCP tool once with the full publish
--- projection set (narrative / hub / llms / context7 / devin / luacats)
--- and `lint_strict=true`, then exit.
---
--- Run:
---   just dist-auto
--- or:
---   agent-block -s scripts/dist.lua -p .
---
--- Side effects in CWD:
---   - hub_index.json                  (via alc_hub_reindex)
---   - docs/narrative/*.md
---   - docs/hub/*.json
---   - docs/llms.txt, docs/llms-full.txt
---   - context7.json                    (repo root)
---   - .devin/wiki.json                 (repo root)
---   - types/alc_shapes.d.lua           (luacats projection)

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local prompt = [[
Call the algocline MCP tool `alc_hub_dist` exactly once with:
  source_dir   = "."
  output_path  = "hub_index.json"
  out_dir      = "docs"
  projections  = ["hub", "narrative", "llms", "context7", "devin", "luacats"]
  lint_strict  = true

The repo's `alc.toml` at source_dir root is auto-explored by core for
[hub] / [hub.context7] / [hub.devin] sections; no config_path arg needed.

Report the tool's response verbatim (package_count, reindex updated_at,
gendoc stdout tail, any warnings[]) and then stop. Do not call any
other tools. Do not retry on non-fatal warnings.
]]

local function grader_dist_ok()
    return {
        name = "dist_tool_invoked",
        check = function(result)
            for _, turn in ipairs(result.turn_history or {}) do
                for _, call in ipairs(turn.tool_calls or {}) do
                    local n = call.name or call.tool_name or ""
                    if n:find("alc_hub_dist", 1, true) then
                        return true, nil
                    end
                end
            end
            return false, "agent did not invoke alc_hub_dist"
        end,
    }
end

common.run({
    name     = "dist",
    prompt   = prompt,
    system   = [[You are a release automation agent. Call the requested
MCP tool exactly once with the specified arguments, then report the
response and stop. Do not improvise extra tool calls.]],
    graders  = {
        common.grader_agent_ok(),
        grader_dist_ok(),
        common.grader_max_turns(3),
    },
    max_iterations = 3,
})
