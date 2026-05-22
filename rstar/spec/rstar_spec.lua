--- Tests for rstar.
--- Extracted from tests/test_new_packages.lua (Phase C decomposition).

local describe, it, expect = lust.describe, lust.it, lust.expect

local function repo_root_from_package_path()
    for entry in package.path:gmatch("[^;]+") do
        local prefix = entry:match("^(.-)/%?%.lua$")
        if prefix and prefix ~= "" and prefix:sub(1, 1) == "/" then
            return prefix
        end
    end
    return "."
end
local REPO = repo_root_from_package_path()
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

local function mock_alc(llm_fn)
    local call_log = {}
    local a = {
        llm = function(prompt, opts)
            call_log[#call_log + 1] = { prompt = prompt, opts = opts }
            return llm_fn(prompt, opts, #call_log)
        end,
        map = function(list, fn)
            local results = {}
            for _, item in ipairs(list) do
                results[#results + 1] = fn(item)
            end
            return results
        end,
        log = function() end,
        parse_score = function(s)
            return tonumber(s:match("%d+")) or 5
        end,
        json_decode = function(s)
            return nil
        end,
    }
    a.llm_batch = function(items)
        local results = {}
        for i, item in ipairs(items) do
            results[i] = a.llm(item.prompt, {
                system     = item.system,
                max_tokens = item.max_tokens,
            })
        end
        return results
    end
    a.parallel = function(items, prompt_fn, opts)
        opts = opts or {}
        local batch = {}
        for i, item in ipairs(items) do
            local p = prompt_fn(item, i)
            if type(p) == "string" then
                local entry = { prompt = p }
                if opts.system     then entry.system     = opts.system     end
                if opts.max_tokens then entry.max_tokens = opts.max_tokens end
                batch[i] = entry
            else
                batch[i] = p
            end
        end
        local responses = a.llm_batch(batch)
        if opts.post_fn then
            local results = {}
            for i, resp in ipairs(responses) do
                results[i] = opts.post_fn(resp, items[i], i)
            end
            return results
        end
        return responses
    end
    _G.alc = a
    return call_log
end

local function reset()
    _G.alc = nil
    package.loaded["rstar"] = nil
end

describe("rstar", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc(function() return "mock" end)
        local m = require("rstar")
        expect(m.meta).to_not.equal(nil)
        expect(m.meta.name).to.equal("rstar")
        expect(m.meta.category).to.equal("reasoning")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["rstar"] = nil
        local m = require("rstar")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)

    it("full agreement = 4 LLM calls, no resolution", function()
        local call_count = 0
        local log = mock_alc(function(prompt, _, n)
            call_count = call_count + 1
            -- Paths (called via alc.map, so n tracks global count)
            if prompt:match("first principles") then
                return "Step 1: analyze. Step 2: conclude. Conclusion: 42"
            elseif prompt:match("multiple angles") then
                return "Approach A: 42. Approach B: 42. Conclusion: 42"
            elseif prompt:match("Verify Path") then
                return "All steps are correct. VERDICT: AGREE"
            end
            return "mock"
        end)
        package.loaded["rstar"] = nil
        local m = require("rstar")
        local ctx = m.run({ task = "What is the answer?" })
        expect(ctx.result.agreement).to.equal("full")
        expect(ctx.result.resolution_needed).to.equal(false)
        -- 2 (paths) + 2 (verifications) = 4
        expect(#log).to.equal(4)
    end)

    it("mutual disagreement = 5 LLM calls with resolution", function()
        local log = mock_alc(function(prompt)
            if prompt:match("first principles") then
                return "Conclusion: 42"
            elseif prompt:match("multiple angles") then
                return "Conclusion: 99"
            elseif prompt:match("Verify Path") then
                return "The reasoning has errors. VERDICT: DISAGREE. Wrong formula."
            elseif prompt:match("Two solvers produced") then
                return "After analysis, the correct answer is 42."
            end
            return "mock"
        end)
        package.loaded["rstar"] = nil
        local m = require("rstar")
        local ctx = m.run({ task = "Solve" })
        expect(ctx.result.agreement).to.equal("none")
        expect(ctx.result.resolution_needed).to.equal(true)
        -- 2 paths + 2 verifications + 1 resolution = 5
        expect(#log).to.equal(5)
    end)

    it("partial agreement (A agrees B, B disagrees A) = uses B", function()
        local log = mock_alc(function(prompt)
            if prompt:match("first principles") then
                return "Conclusion: wrong answer"
            elseif prompt:match("multiple angles") then
                return "Conclusion: correct answer"
            elseif prompt:match("A_checks_B") or prompt:match("Path B") and prompt:match("Verify") then
                -- A checking B
                if prompt:match("Your reasoning %(Path A%)") then
                    return "Path B looks correct. VERDICT: AGREE"
                end
                -- B checking A
                return "Path A has errors. VERDICT: DISAGREE"
            end
            -- Disambiguation: first verify call = A checks B, second = B checks A
            if prompt:match("Verify Path B") then
                return "Looks correct. VERDICT: AGREE"
            elseif prompt:match("Verify Path A") then
                return "Has errors. VERDICT: DISAGREE"
            end
            return "mock"
        end)
        package.loaded["rstar"] = nil
        local m = require("rstar")
        local ctx = m.run({ task = "Solve" })
        expect(ctx.result.agreement).to.equal("partial")
        expect(ctx.result.resolution_needed).to.equal(false)
        expect(#log).to.equal(4) -- no resolution needed
    end)
end)
