--- Tests for contrastive package (Contrastive CoT, Chia et al. 2023
--- arXiv:2311.09277). M.run() is LLM-dependent so alc.llm is stubbed
--- via a call counter that returns distinguishable strings per phase.
---
--- Run via:
---   just alc-pkg-test-file contrastive/spec/contrastive_spec.lua
--- Or via mlua-probe MCP:
---   mcp__lua-debugger__test_launch(
---     code_file    = "contrastive/spec/contrastive_spec.lua",
---     search_paths = ["."],
---   )

local describe, it, expect = lust.describe, lust.it, lust.expect

--- Build a mock _G.alc with an alc.llm that returns
--- "wrong_<n>", "error_<n>", "final_<n>" by call counter, and logs
--- every call into call_log.
local function mock_alc()
    local call_log = {}
    local counter = { wrong = 0, error_an = 0, final = 0 }
    _G.alc = {
        llm = function(prompt, opts)
            call_log[#call_log + 1] = { prompt = prompt, opts = opts }
            -- Heuristic: classify the call by a stable substring of the
            -- prompt that contrastive/init.lua writes literally.
            if prompt:find("INCORRECT reasoning path", 1, true) then
                counter.wrong = counter.wrong + 1
                return "wrong_" .. counter.wrong
            elseif prompt:find("contains an error", 1, true) then
                counter.error_an = counter.error_an + 1
                return "error_" .. counter.error_an
            else
                counter.final = counter.final + 1
                return "final_" .. counter.final
            end
        end,
    }
    return call_log
end

local function reset()
    _G.alc = nil
    package.loaded["contrastive"] = nil
end

-- ================================================================
-- meta
-- ================================================================

describe("contrastive.meta", function()
    reset()
    mock_alc()
    local contrastive = require("contrastive")

    it("has correct name", function()
        expect(contrastive.meta.name).to.equal("contrastive")
    end)

    it("has version 0.1.0", function()
        expect(contrastive.meta.version).to.equal("0.1.0")
    end)

    it("has category 'reasoning'", function()
        expect(contrastive.meta.category).to.equal("reasoning")
    end)

    it("has a non-empty description", function()
        expect(type(contrastive.meta.description)).to.equal("string")
        expect(#contrastive.meta.description > 0).to.equal(true)
    end)
end)

-- ================================================================
-- spec
-- ================================================================

describe("contrastive.spec", function()
    reset()
    mock_alc()
    local contrastive = require("contrastive")
    local run_entry = contrastive.spec.entries.run

    it("declares a run entry with input and result shapes", function()
        expect(run_entry).to_not.equal(nil)
        expect(run_entry.input).to_not.equal(nil)
        expect(run_entry.result).to_not.equal(nil)
    end)
end)

-- ================================================================
-- M.run with stubbed alc.llm
-- ================================================================

describe("contrastive.run with stubbed alc.llm", function()
    it("errors when ctx.task is missing", function()
        reset()
        mock_alc()
        local contrastive = require("contrastive")
        local ok, err = pcall(contrastive.run, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("ctx.task")).to_not.equal(nil)
    end)

    it("defaults n_contrasts to 2 (5 LLM calls)", function()
        reset()
        local log = mock_alc()
        local contrastive = require("contrastive")
        local ctx = contrastive.run({ task = "What is 2+2?" })
        expect(ctx.result.total_contrasts).to.equal(2)
        expect(#ctx.result.contrasts).to.equal(2)
        -- 2 wrong + 2 error_analysis + 1 final = 5
        expect(#log).to.equal(5)
    end)

    it("honors n_contrasts override = 3 (7 LLM calls)", function()
        reset()
        local log = mock_alc()
        local contrastive = require("contrastive")
        local ctx = contrastive.run({ task = "T", n_contrasts = 3 })
        expect(ctx.result.total_contrasts).to.equal(3)
        expect(#ctx.result.contrasts).to.equal(3)
        expect(#log).to.equal(7)
    end)

    it("honors n_contrasts = 1 (3 LLM calls)", function()
        reset()
        local log = mock_alc()
        local contrastive = require("contrastive")
        local ctx = contrastive.run({ task = "T", n_contrasts = 1 })
        expect(ctx.result.total_contrasts).to.equal(1)
        expect(#log).to.equal(3)
    end)

    it("populates each contrast with wrong_reasoning + error_analysis", function()
        reset()
        mock_alc()
        local contrastive = require("contrastive")
        local ctx = contrastive.run({ task = "T", n_contrasts = 2 })
        for i, c in ipairs(ctx.result.contrasts) do
            expect(c.wrong_reasoning).to.equal("wrong_" .. i)
            expect(c.error_analysis).to.equal("error_" .. i)
        end
    end)

    it("returns the final-answer stub value as ctx.result.answer", function()
        reset()
        mock_alc()
        local contrastive = require("contrastive")
        local ctx = contrastive.run({ task = "T", n_contrasts = 2 })
        expect(ctx.result.answer).to.equal("final_1")
    end)

    it("embeds the task text into the final-answer prompt", function()
        reset()
        local log = mock_alc()
        local contrastive = require("contrastive")
        contrastive.run({ task = "MARKER_TASK_42", n_contrasts = 1 })
        local final_call = log[#log]
        expect(final_call.prompt:find("MARKER_TASK_42", 1, true)).to_not.equal(nil)
    end)

    it("embeds prior wrong + error contents into the final-answer prompt", function()
        reset()
        local log = mock_alc()
        local contrastive = require("contrastive")
        contrastive.run({ task = "T", n_contrasts = 2 })
        local final_call = log[#log]
        expect(final_call.prompt:find("wrong_1", 1, true)).to_not.equal(nil)
        expect(final_call.prompt:find("error_1", 1, true)).to_not.equal(nil)
        expect(final_call.prompt:find("wrong_2", 1, true)).to_not.equal(nil)
        expect(final_call.prompt:find("error_2", 1, true)).to_not.equal(nil)
    end)
end)

reset()
