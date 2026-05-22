--- Tests extracted from tests/test_exploration.lua (Phase C decomposition).

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
            if type(s) ~= "string" then return nil end
            local t = {}
            for k, v in s:gmatch('"([^"]+)"%s*:%s*([^,}]+)') do
                local num = tonumber(v)
                if num then
                    t[k] = num
                else
                    t[k] = v:match('^"(.*)"$') or v
                end
            end
            return t
        end,
        json_encode = function(t)
            if type(t) ~= "table" then return tostring(t) end
            local parts = {}
            for k, v in pairs(t) do
                if type(v) == "string" then
                    parts[#parts + 1] = string.format('"%s":"%s"', k, v)
                else
                    parts[#parts + 1] = string.format('"%s":%s', k, tostring(v))
                end
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end,
    }
    _G.alc = a
    return call_log
end

local function reset()
    _G.alc = nil
    for _, name in ipairs({ "mcts" }) do
        package.loaded[name] = nil
    end
end

describe("mcts: reflection", function()
    lust.after(reset)

    it("works without reflection (backward compatible)", function()
        local log = mock_alc(function(prompt, opts, n)
            if prompt:match("Propose") or prompt:match("next reasoning") then
                return "Step thought " .. n
            end
            if prompt:match("Continue this reasoning") then
                return "Continued reasoning"
            end
            if prompt:match("Rate this reasoning") then
                return "7"
            end
            if prompt:match("Synthesize") then
                return "Final answer"
            end
            return "mock"
        end)
        package.loaded["mcts"] = nil
        local m = require("mcts")
        local ctx = m.run({
            task = "Solve X",
            iterations = 2,
            max_depth = 2,
            -- reflection not set → default false
        })
        expect(ctx.result).to_not.equal(nil)
        expect(ctx.result.conclusion).to.equal("Final answer")
        -- No reflection calls should appear
        local reflection_calls = 0
        for _, c in ipairs(log) do
            if c.prompt:match("why this reasoning path scored poorly") then
                reflection_calls = reflection_calls + 1
            end
        end
        expect(reflection_calls).to.equal(0)
    end)

    it("generates reflections on low-score paths", function()
        local score_n = 0
        local log = mock_alc(function(prompt, opts, n)
            if prompt:match("Propose") or prompt:match("next reasoning") then
                return "Step thought"
            end
            if prompt:match("Continue") then return "Continued" end
            if prompt:match("Rate this reasoning") then
                score_n = score_n + 1
                -- First iteration: low score triggers reflection
                -- Second: high score, no reflection
                if score_n == 1 then return "2" end
                return "8"
            end
            if prompt:match("why this reasoning path scored poorly") then
                return "The approach was too vague"
            end
            if prompt:match("Synthesize") then return "Final" end
            return "mock"
        end)
        package.loaded["mcts"] = nil
        local m = require("mcts")
        local ctx = m.run({
            task = "Solve X",
            iterations = 2,
            max_depth = 2,
            reflection = true,
            reflection_threshold = 4,
        })
        -- Should have at least one reflection call
        local reflection_calls = 0
        for _, c in ipairs(log) do
            if c.prompt:match("why this reasoning path scored poorly") then
                reflection_calls = reflection_calls + 1
            end
        end
        expect(reflection_calls).to.equal(1)
    end)

    it("injects reflections into expansion prompts", function()
        local score_n = 0
        local saw_lessons = false
        mock_alc(function(prompt, opts, n)
            if prompt:match("Lessons from failed paths") then
                saw_lessons = true
            end
            if prompt:match("Propose") or prompt:match("next reasoning") then
                return "Step thought"
            end
            if prompt:match("Continue") then return "Continued" end
            if prompt:match("Rate this reasoning") then
                score_n = score_n + 1
                if score_n <= 2 then return "2" end -- low scores
                return "8"
            end
            if prompt:match("why this reasoning path scored poorly") then
                return "Wrong approach used"
            end
            if prompt:match("Synthesize") then return "Final" end
            return "mock"
        end)
        package.loaded["mcts"] = nil
        local m = require("mcts")
        m.run({
            task = "Solve X",
            iterations = 4,
            max_depth = 2,
            reflection = true,
            reflection_threshold = 4,
        })
        -- After first low-score iteration, subsequent expansions should see lessons
        expect(saw_lessons).to.equal(true)
    end)

    it("respects max_reflections buffer size", function()
        local reflection_count = 0
        mock_alc(function(prompt)
            if prompt:match("Propose") or prompt:match("next reasoning") then
                return "Step"
            end
            if prompt:match("Continue") then return "Cont" end
            if prompt:match("Rate this reasoning") then return "1" end -- always low
            if prompt:match("why this reasoning path scored poorly") then
                reflection_count = reflection_count + 1
                return "Reflection #" .. reflection_count
            end
            if prompt:match("Synthesize") then return "Final" end
            return "mock"
        end)
        package.loaded["mcts"] = nil
        local m = require("mcts")
        m.run({
            task = "Solve",
            iterations = 6,
            max_depth = 2,
            reflection = true,
            reflection_threshold = 5,
            max_reflections = 3,
        })
        -- Should generate reflections but buffer capped at 3
        -- (older ones evicted via FIFO)
        expect(reflection_count).to.equal(6) -- one per iteration
    end)
end)
