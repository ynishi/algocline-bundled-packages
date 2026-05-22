--- Tests for bot.
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
    package.loaded["bot"] = nil
end

describe("bot", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc(function() return "mock" end)
        local m = require("bot")
        expect(m.meta).to_not.equal(nil)
        expect(m.meta.name).to.equal("bot")
        expect(m.meta.category).to.equal("reasoning")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["bot"] = nil
        local m = require("bot")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)

    it("classifies and uses arithmetic template", function()
        local log = mock_alc(function(_, _, n)
            if n == 1 then return "arithmetic" end
            if n == 2 then return "Step 1: x=5. Step 2: 5*3=15" end
            if n == 3 then return "ERRORS: NONE\nFINAL ANSWER: The result is 15." end
            return "mock"
        end)
        package.loaded["bot"] = nil
        local m = require("bot")
        local ctx = m.run({ task = "Calculate 5*3" })
        expect(ctx.result.template_key).to.equal("arithmetic")
        expect(ctx.result.errors_found).to.equal(false)
        expect(ctx.result.answer).to.equal("The result is 15.")
        expect(#log).to.equal(3)
    end)

    it("classifies logic template", function()
        mock_alc(function(_, _, n)
            if n == 1 then return "logic" end
            if n == 2 then return "Premises identified..." end
            return "ERRORS: NONE\nFINAL ANSWER: Valid syllogism."
        end)
        package.loaded["bot"] = nil
        local m = require("bot")
        local ctx = m.run({ task = "Is this syllogism valid?" })
        expect(ctx.result.template_key).to.equal("logic")
    end)

    it("falls back to analytical for unrecognized classification", function()
        mock_alc(function(_, _, n)
            if n == 1 then return "xyzzy_unknown_type" end
            if n == 2 then return "analysis..." end
            return "ERRORS: NONE\nFINAL ANSWER: Done."
        end)
        package.loaded["bot"] = nil
        local m = require("bot")
        local ctx = m.run({ task = "Something unusual" })
        expect(ctx.result.template_key).to.equal("analytical")
    end)

    it("detects errors in verification", function()
        mock_alc(function(_, _, n)
            if n == 1 then return "arithmetic" end
            if n == 2 then return "wrong calculation" end
            return "ERRORS: Step 2 used wrong formula\nFINAL ANSWER: Corrected to 42."
        end)
        package.loaded["bot"] = nil
        local m = require("bot")
        local ctx = m.run({ task = "Calculate" })
        expect(ctx.result.errors_found).to.equal(true)
        expect(ctx.result.answer).to.equal("Corrected to 42.")
    end)

    it("accepts custom templates", function()
        mock_alc(function(_, _, n)
            if n == 1 then return "custom" end
            if n == 2 then return "custom reasoning" end
            return "ERRORS: NONE\nFINAL ANSWER: Custom result."
        end)
        package.loaded["bot"] = nil
        local m = require("bot")
        local ctx = m.run({
            task = "Do custom thing",
            templates = {
                custom = {
                    name = "Custom Template",
                    pattern = "1. Custom step\n2. Custom step 2",
                },
            },
        })
        expect(ctx.result.template_key).to.equal("custom")
        expect(ctx.result.template_name).to.equal("Custom Template")
    end)
end)
