--- Tests for decompose (task decomposition and parallel sub-task execution).
---
--- Coverage (4 cases):
---   1. Happy path — 2 sub-tasks parsed, executed in parallel, merged
---   2. Input validation — ctx.task missing → error
---   3. Fallback to single subtask — no numbered lines in decomposition
---   4. subtask_results count matches subtasks count

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

for _, name in ipairs({ "decompose", "alc_shapes", "alc_shapes.t", "alc_shapes.check", "alc_shapes.reflect" }) do
    package.loaded[name] = nil
end

local function reset()
    package.loaded["decompose"] = nil
    _G.alc = nil
end

local function make_alc_stub(opts)
    opts = opts or {}
    local fixtures = opts.fixtures or {}
    local counter = { llm_calls = 0, parallel_calls = 0, batch_calls = 0 }
    local call_idx = 0

    local stub = {}
    stub.llm = function(_prompt, _llm_opts)
        counter.llm_calls = counter.llm_calls + 1
        call_idx = call_idx + 1
        return fixtures[call_idx] or "default response"
    end

    stub.llm_batch = function(items)
        counter.batch_calls = counter.batch_calls + 1
        local results = {}
        for i, item in ipairs(items) do
            results[i] = stub.llm(item.prompt, {
                system = item.system,
                max_tokens = item.max_tokens,
            })
        end
        return results
    end

    stub.parallel = function(items, prompt_fn, popts)
        counter.parallel_calls = counter.parallel_calls + 1
        popts = popts or {}
        local batch = {}
        for i, item in ipairs(items) do
            local p = prompt_fn(item, i)
            if type(p) == "string" then
                local entry = { prompt = p }
                if popts.system then entry.system = popts.system end
                if popts.max_tokens then entry.max_tokens = popts.max_tokens end
                batch[i] = entry
            else
                batch[i] = p
            end
        end
        local responses = stub.llm_batch(batch)
        if popts.post_fn then
            local res = {}
            for i, resp in ipairs(responses) do
                res[i] = popts.post_fn(resp, items[i], i)
            end
            return res
        end
        return responses
    end

    stub.log = function(_level, _msg) end

    return stub, counter
end

-- ═══════════════════════════════════════════════════════════════════
-- Case 1: Happy path — 2 sub-tasks parsed and merged
-- ═══════════════════════════════════════════════════════════════════

describe("decompose.run happy path", function()
    lust.after(reset)

    it("decomposes into 2 sub-tasks and merges results", function()
        reset()
        -- fixture[1] = decomposition with 2 subtasks
        -- fixture[2,3] = subtask results (via parallel)
        -- fixture[4] = merged answer
        local stub, counter = make_alc_stub({
            fixtures = {
                "1. First sub-task description\n2. Second sub-task description",
                "Result for subtask 1",
                "Result for subtask 2",
                "Merged final answer",
            },
        })
        _G.alc = stub
        local m = require("decompose")
        local ctx = m.run({ task = "A complex task" })
        expect(ctx.result).to_not.equal(nil)
        expect(ctx.result.answer).to.equal("Merged final answer")
        expect(#ctx.result.subtasks).to.equal(2)
        expect(#ctx.result.subtask_results).to.equal(2)
        -- decompose call (1) + 2 parallel subtask calls + merge call (1) = 4
        expect(counter.llm_calls).to.equal(4)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 2: Input validation — ctx.task missing → error
-- ═══════════════════════════════════════════════════════════════════

describe("decompose.run input validation", function()
    lust.after(reset)

    it("errors when ctx.task is missing", function()
        reset()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("decompose")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:find("task") ~= nil).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 3: Fallback — decomposition has no numbered lines → single subtask
-- ═══════════════════════════════════════════════════════════════════

describe("decompose.run fallback to single subtask", function()
    lust.after(reset)

    it("falls back to single subtask when decomposition returns no numbered lines", function()
        reset()
        local stub, counter = make_alc_stub({
            fixtures = {
                "No numbered list here",   -- decomposition yields nothing
                "Subtask result",          -- single subtask
                "Merged answer",           -- merge
            },
        })
        _G.alc = stub
        local m = require("decompose")
        local ctx = m.run({ task = "Simple task" })
        -- When no subtasks parsed, fallback = {task} (1 element)
        expect(#ctx.result.subtasks).to.equal(1)
        expect(ctx.result.subtasks[1]).to.equal("Simple task")
        expect(#ctx.result.subtask_results).to.equal(1)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 4: subtask_results count matches subtasks
-- ═══════════════════════════════════════════════════════════════════

describe("decompose.run result count", function()
    lust.after(reset)

    it("subtask_results has same count as subtasks", function()
        reset()
        local stub, _ = make_alc_stub({
            fixtures = {
                "1. Task A\n2. Task B\n3. Task C",  -- 3 subtasks
                "R1", "R2", "R3",                   -- parallel results
                "Merged",                            -- merge
            },
        })
        _G.alc = stub
        local m = require("decompose")
        local ctx = m.run({ task = "Multi-part task", max_subtasks = 3 })
        expect(#ctx.result.subtasks).to.equal(3)
        expect(#ctx.result.subtask_results).to.equal(#ctx.result.subtasks)
    end)
end)
