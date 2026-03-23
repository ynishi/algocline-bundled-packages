--- Tests for router_capability package

local describe, it, expect = lust.describe, lust.it, lust.expect

local REPO = os.getenv("PWD") or "."
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

local function mock_alc(llm_fn)
    local call_log = {}
    _G.alc = {
        llm = function(prompt, opts)
            call_log[#call_log + 1] = { prompt = prompt, opts = opts }
            return llm_fn(prompt, opts, #call_log)
        end,
        log = function() end,
        json_decode = function(s)
            -- Parse {"requirements": [...], "reasoning": "..."}
            local reason = s:match('"reasoning"%s*:%s*"([^"]*)"')
            local arr_str = s:match('"requirements"%s*:%s*%[(.-)%]')
            local reqs = {}
            if arr_str then
                for tag in arr_str:gmatch('"([^"]+)"') do
                    reqs[#reqs + 1] = tag
                end
            end
            if #reqs > 0 then
                return { requirements = reqs, reasoning = reason }
            end
            return nil
        end,
    }
    return call_log
end

local function reset()
    _G.alc = nil
    package.loaded["router_capability"] = nil
end

-- ================================================================
describe("router_capability: meta", function()
    lust.after(reset)

    it("has correct meta fields", function()
        local m = require("router_capability")
        expect(m.meta.name).to.equal("router_capability")
        expect(m.meta.category).to.equal("routing")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return '{}' end)
        package.loaded["router_capability"] = nil
        local m = require("router_capability")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)
end)

-- ================================================================
describe("router_capability: Jaccard scoring", function()
    lust.after(reset)

    it("selects debugger for debugging requirements", function()
        local log = mock_alc(function()
            return '{"requirements": ["debugging", "error_analysis"], "reasoning": "debug task"}'
        end)
        package.loaded["router_capability"] = nil
        local m = require("router_capability")
        local ctx = m.run({ task = "Debug the segfault in session cleanup" })

        expect(#log).to.equal(1) -- 1 LLM call for extraction
        expect(ctx.result.selected).to.equal("debugger")
        expect(ctx.result.method).to.equal("jaccard")
        expect(ctx.result.confidence > 0).to.equal(true)
    end)

    it("selects implementer for coding requirements", function()
        mock_alc(function()
            return '{"requirements": ["coding", "implementation", "refactoring"], "reasoning": "code task"}'
        end)
        package.loaded["router_capability"] = nil
        local m = require("router_capability")
        local ctx = m.run({ task = "Implement the new API handler" })

        expect(ctx.result.selected).to.equal("implementer")
    end)

    it("returns top N alternatives", function()
        mock_alc(function()
            return '{"requirements": ["testing", "verification"], "reasoning": "test task"}'
        end)
        package.loaded["router_capability"] = nil
        local m = require("router_capability")
        local ctx = m.run({ task = "Write tests", max_results = 2 })

        expect(#ctx.result.alternatives).to.equal(2)
    end)
end)

-- ================================================================
describe("router_capability: Jaccard unit tests", function()
    lust.after(reset)

    it("computes correct Jaccard similarity", function()
        mock_alc(function() return '{"requirements":["a"],"reasoning":""}' end)
        package.loaded["router_capability"] = nil
        local m = require("router_capability")

        -- Identical sets: J = 1.0
        local j1 = m._jaccard({"a", "b"}, {"a", "b"})
        expect(j1).to.equal(1.0)

        -- Disjoint sets: J = 0.0
        local j2 = m._jaccard({"a", "b"}, {"c", "d"})
        expect(j2).to.equal(0.0)

        -- Partial overlap: J = 1/3
        local j3 = m._jaccard({"a", "b"}, {"b", "c"})
        -- 1 intersection / 3 union
        expect(math.abs(j3 - 1/3) < 0.01).to.equal(true)

        -- Empty sets: J = 0
        local j4 = m._jaccard({}, {})
        expect(j4).to.equal(0)
    end)

    it("is case-insensitive", function()
        mock_alc(function() return '{"requirements":["a"],"reasoning":""}' end)
        package.loaded["router_capability"] = nil
        local m = require("router_capability")
        local j = m._jaccard({"Coding", "TESTING"}, {"coding", "testing"})
        expect(j).to.equal(1.0)
    end)
end)

-- ================================================================
describe("router_capability: same score uses cost tiebreaker", function()
    lust.after(reset)

    it("prefers lower cost agent on tie", function()
        mock_alc(function()
            return '{"requirements": ["shared_cap"], "reasoning": "test"}'
        end)
        package.loaded["router_capability"] = nil
        local m = require("router_capability")
        local ctx = m.run({
            task = "Test task",
            registry = {
                { name = "expensive", capabilities = { "shared_cap" }, cost = 10 },
                { name = "cheap", capabilities = { "shared_cap" }, cost = 1 },
            },
        })

        expect(ctx.result.selected).to.equal("cheap")
    end)
end)

-- ================================================================
describe("router_capability: extraction failure", function()
    lust.after(reset)

    it("returns first agent on extraction failure", function()
        mock_alc(function()
            return "I cannot extract requirements from this."
        end)
        package.loaded["router_capability"] = nil
        local m = require("router_capability")
        local ctx = m.run({ task = "Something vague" })

        -- With empty requirements, all Jaccard scores are 0; tiebreak by cost
        expect(ctx.result.confidence).to.equal(0)
        expect(ctx.result.reasoning).to.equal("Extraction failed")
    end)
end)
