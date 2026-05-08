--- Tests for distill (MapReduce summarization).
---
--- Coverage (4 cases):
---   1. Happy path — 2 chunks processed, summary returned
---   2. Input validation — ctx.text missing → error
---   3. Empty chunks early return — alc.chunk returns {} → summary=""
---   4. All-filtered early return — all chunks return "NONE"

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

for _, name in ipairs({ "distill", "alc_shapes", "alc_shapes.t", "alc_shapes.check", "alc_shapes.reflect" }) do
    package.loaded[name] = nil
end

local function reset()
    package.loaded["distill"] = nil
    _G.alc = nil
end

local function make_alc_stub(opts)
    opts = opts or {}
    local fixtures = opts.fixtures or {}
    local counter = { llm_calls = 0, parallel_calls = 0, batch_calls = 0 }
    local call_idx = 0
    local chunks_override = opts.chunks_override  -- table of chunks to return from alc.chunk

    local stub = {}
    stub.llm = function(_prompt, _llm_opts)
        counter.llm_calls = counter.llm_calls + 1
        call_idx = call_idx + 1
        return fixtures[call_idx] or "extracted info"
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

    -- alc.chunk stub: returns chunks_override or splits text into lines
    stub.chunk = function(text, _chunk_opts)
        if chunks_override then
            return chunks_override
        end
        -- Default: return each line as a separate chunk
        local chunks = {}
        for line in (text .. "\n"):gmatch("(.-)\n") do
            if #line > 0 then
                chunks[#chunks + 1] = line
            end
        end
        return chunks
    end

    return stub, counter
end

-- ═══════════════════════════════════════════════════════════════════
-- Case 1: Happy path — 2 chunks, 2 extractions, summary
-- ═══════════════════════════════════════════════════════════════════

describe("distill.run happy path", function()
    lust.after(reset)

    it("processes 2 chunks and returns summary", function()
        reset()
        local stub, counter = make_alc_stub({
            chunks_override = { "chunk1 content", "chunk2 content" },
            fixtures = {
                "Extraction from chunk 1",   -- map phase chunk 1
                "Extraction from chunk 2",   -- map phase chunk 2
                "Final summary text",        -- reduce phase
            },
        })
        _G.alc = stub
        local m = require("distill")
        local ctx = m.run({
            text = "chunk1 content\nchunk2 content",
            goal = "Summarize key points",
        })
        expect(ctx.result).to_not.equal(nil)
        expect(ctx.result.summary).to.equal("Final summary text")
        expect(ctx.result.chunks_processed).to.equal(2)
        expect(ctx.result.relevant_chunks).to.equal(2)
        expect(#ctx.result.extractions).to.equal(2)
        -- 2 map calls + 1 reduce call = 3
        expect(counter.llm_calls).to.equal(3)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 2: Input validation — ctx.text missing → error
-- ═══════════════════════════════════════════════════════════════════

describe("distill.run input validation", function()
    lust.after(reset)

    it("errors when ctx.text is missing", function()
        reset()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("distill")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:find("text") ~= nil).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 3: Empty chunks early return — alc.chunk returns {}
-- ═══════════════════════════════════════════════════════════════════

describe("distill.run empty chunks", function()
    lust.after(reset)

    it("returns empty summary when chunk returns no chunks", function()
        reset()
        local stub, counter = make_alc_stub({
            chunks_override = {},  -- no chunks
        })
        _G.alc = stub
        local m = require("distill")
        local ctx = m.run({ text = "some text" })
        expect(ctx.result.summary).to.equal("")
        expect(ctx.result.chunks_processed).to.equal(0)
        -- No LLM calls when chunks is empty
        expect(counter.llm_calls).to.equal(0)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 4: All-filtered — all map returns "NONE"
-- ═══════════════════════════════════════════════════════════════════

describe("distill.run all filtered", function()
    lust.after(reset)

    it("returns no-relevant-info message when all chunks filtered", function()
        reset()
        local stub, counter = make_alc_stub({
            chunks_override = { "chunk1", "chunk2" },
            fixtures = { "NONE", "NONE" },  -- both map calls return NONE
        })
        _G.alc = stub
        local m = require("distill")
        local ctx = m.run({ text = "chunk1\nchunk2" })
        expect(ctx.result.relevant_chunks).to.equal(0)
        expect(ctx.result.summary:find("No relevant") ~= nil).to.equal(true)
        -- 2 map calls, 0 reduce calls
        expect(counter.llm_calls).to.equal(2)
    end)
end)
