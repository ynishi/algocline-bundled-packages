--- Tests for s2a.
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
    package.loaded["s2a"] = nil
end

describe("s2a", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc(function() return "mock" end)
        local m = require("s2a")
        expect(m.meta).to_not.equal(nil)
        expect(m.meta.name).to.equal("s2a")
        expect(m.meta.category).to.equal("preprocessing")
        expect(type(m.run)).to.equal("function")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["s2a"] = nil
        local m = require("s2a")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)

    it("uses 2 LLM calls with context", function()
        local log = mock_alc(function(_, _, n)
            if n == 1 then return "denoised relevant facts only" end
            return "answer based on clean context"
        end)
        package.loaded["s2a"] = nil
        local m = require("s2a")
        local ctx = m.run({ task = "What is X?", context = "Noisy irrelevant text about X" })
        expect(#log).to.equal(2)
        expect(ctx.result.denoised_context).to.equal("denoised relevant facts only")
        expect(ctx.result.answer).to.equal("answer based on clean context")
    end)

    it("uses 2 LLM calls without context (denoises task itself)", function()
        local log = mock_alc(function(_, _, n)
            if n == 1 then return "reformulated question" end
            return "clean answer"
        end)
        package.loaded["s2a"] = nil
        local m = require("s2a")
        local ctx = m.run({ task = "Don't you think X is great?" })
        expect(#log).to.equal(2)
        expect(ctx.result.denoised_context).to.equal("reformulated question")
    end)
end)
