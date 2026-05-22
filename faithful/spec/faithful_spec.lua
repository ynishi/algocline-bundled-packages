--- Tests for faithful.
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
    package.loaded["faithful"] = nil
end

describe("faithful", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc(function() return "mock" end)
        local m = require("faithful")
        expect(m.meta).to_not.equal(nil)
        expect(m.meta.name).to.equal("faithful")
        expect(m.meta.category).to.equal("reasoning")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["faithful"] = nil
        local m = require("faithful")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)

    it("auto-detects 'code' format for math tasks", function()
        local log = mock_alc(function(prompt, _, n)
            if n == 1 then return "Step 1: 5+3=8" end
            if n == 2 then return "print(5+3)" end
            if n == 3 then return "EXPECTED OUTPUT: 8\nERRORS FOUND: NONE\nCORRECTED ANSWER: 8" end
            return "The answer is 8."
        end)
        package.loaded["faithful"] = nil
        local m = require("faithful")
        local ctx = m.run({ task = "Calculate 5+3" })
        expect(ctx.result.format).to.equal("code")
        expect(ctx.result.errors_found).to.equal(false)
        expect(#log).to.equal(4)
    end)

    it("auto-detects 'logic' format for logical tasks", function()
        local log = mock_alc(function(_, _, n)
            if n == 1 then return "All A are B. X is A. Therefore X is B." end
            if n == 2 then return "P1: All A are B\nP2: X is A\nCONCLUSION: X is B\nVALIDITY: VALID" end
            if n == 3 then return "VALIDITY: VALID\nERRORS FOUND: NONE\nCORRECTED CONCLUSION: X is B" end
            return "X is B."
        end)
        package.loaded["faithful"] = nil
        local m = require("faithful")
        local ctx = m.run({ task = "If all cats are animals and Whiskers is a cat, is Whiskers an animal?" })
        expect(ctx.result.format).to.equal("logic")
    end)

    it("detects errors when verification finds issues", function()
        local log = mock_alc(function(_, _, n)
            if n == 1 then return "reasoning" end
            if n == 2 then return "code" end
            if n == 3 then return "ERRORS FOUND: Off-by-one in loop\nCORRECTED ANSWER: 7" end
            return "Corrected: 7"
        end)
        package.loaded["faithful"] = nil
        local m = require("faithful")
        local ctx = m.run({ task = "Calculate something", format = "code" })
        expect(ctx.result.errors_found).to.equal(true)
    end)

    it("respects explicit format override", function()
        local log = mock_alc(function() return "mock\nERRORS FOUND: NONE" end)
        package.loaded["faithful"] = nil
        local m = require("faithful")
        local ctx = m.run({ task = "generic task", format = "logic" })
        expect(ctx.result.format).to.equal("logic")
    end)
end)
