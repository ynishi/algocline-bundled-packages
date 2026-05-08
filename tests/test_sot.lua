--- Tests for sot (Skeleton-of-Thought, Ning et al. 2023, arXiv:2307.15337).
---
--- Coverage:
---   1. generates skeleton + fills sections (happy path, 3 sections)
---   2. falls back to single section when skeleton parse fails
---   3. respects max_sections cap
---   4. counts LLM calls correctly: 1 skeleton + N fills
---   5. uses alc.parallel for fills, not alc.map (optional, spy-based)

local describe, it, expect = lust.describe, lust.it, lust.expect

-- Derive REPO from the first `?.lua` entry already prepended to
-- `package.path` by `mlua-probe-mcp`'s `search_paths` (see
-- tests/test_gen_docs.lua:23-33 and CLAUDE.md §「失敗記録 2026-04-19
-- tests/test_*.lua の REPO 解決規約」). `os.getenv("PWD")` under
-- mlua-probe-mcp points at the server's startup CWD (often the parent
-- repo) and would silently route requires to the wrong worktree.
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

-- Force fresh load so a prior test run does not cache an old version.
for _, name in ipairs({
    "sot",
    "alc_shapes",
    "alc_shapes.t",
    "alc_shapes.check",
    "alc_shapes.reflect",
}) do
    package.loaded[name] = nil
end

local function reset()
    package.loaded["sot"] = nil
    _G.alc = nil
end

-- ═══════════════════════════════════════════════════════════════════
-- Stub factory (smc_sample test と同型)
-- ═══════════════════════════════════════════════════════════════════

local function make_alc_stub(opts)
    opts = opts or {}
    local fixtures = opts.fixtures or {}
    local counter = { llm_calls = 0, parallel_calls = 0, batch_calls = 0 }
    local call_idx = 0

    local stub = {}
    stub.llm = function(prompt, llm_opts)
        counter.llm_calls = counter.llm_calls + 1
        call_idx = call_idx + 1
        return fixtures[call_idx] or ""
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
            local results = {}
            for i, resp in ipairs(responses) do
                results[i] = popts.post_fn(resp, items[i], i)
            end
            return results
        end
        return responses
    end

    stub.log = function(_level, _msg) end

    return stub, counter
end

-- ═══════════════════════════════════════════════════════════════════
-- Test 1: happy path — 3 sections
-- ═══════════════════════════════════════════════════════════════════

describe("sot.run", function()
    lust.after(reset)

    it("generates skeleton + fills sections", function()
        local stub, _ = make_alc_stub({
            fixtures = {
                -- fixture 1: skeleton raw (3 sections)
                "1. Intro\n2. Body\n3. Conclusion",
                -- fixture 2-4: section fills (consumed via alc.llm_batch inside stub.parallel)
                "Introduction content.",
                "Body content.",
                "Conclusion content.",
            },
        })
        _G.alc = stub

        local sot = require("sot")
        local ctx = sot.run({ task = "Write about testing" })

        expect(ctx.result.section_count).to.equal(3)
        expect(#ctx.result.skeleton).to.equal(3)
        expect(ctx.result.skeleton[1]).to.equal("Intro")
        expect(ctx.result.skeleton[2]).to.equal("Body")
        expect(ctx.result.skeleton[3]).to.equal("Conclusion")
        expect(#ctx.result.sections).to.equal(3)
        -- output should contain ## headings
        expect(ctx.result.output:find("## Intro") ~= nil).to.equal(true)
        expect(ctx.result.output:find("## Body") ~= nil).to.equal(true)
        expect(ctx.result.output:find("## Conclusion") ~= nil).to.equal(true)
    end)

    -- ───────────────────────────────────────────────────────────────
    -- Test 2: fallback when skeleton parse fails
    -- ───────────────────────────────────────────────────────────────

    it("falls back to single section when skeleton parse fails", function()
        local task = "Write about testing"
        local stub, _ = make_alc_stub({
            fixtures = {
                -- fixture 1: skeleton that has no numbered list
                "no numbered list here",
                -- fixture 2: single section fill
                "Fallback content.",
            },
        })
        _G.alc = stub

        local sot = require("sot")
        local ctx = sot.run({ task = task })

        expect(ctx.result.section_count).to.equal(1)
        expect(#ctx.result.skeleton).to.equal(1)
        expect(ctx.result.skeleton[1]).to.equal(task)
    end)

    -- ───────────────────────────────────────────────────────────────
    -- Test 3: max_sections cap
    -- ───────────────────────────────────────────────────────────────

    it("respects max_sections cap", function()
        local stub, _ = make_alc_stub({
            fixtures = {
                -- fixture 1: skeleton with 7 sections
                "1. A\n2. B\n3. C\n4. D\n5. E\n6. F\n7. G",
                -- fixtures 2-5: 4 section fills (max_sections = 4)
                "Fill A.", "Fill B.", "Fill C.", "Fill D.",
            },
        })
        _G.alc = stub

        local sot = require("sot")
        local ctx = sot.run({ task = "Write something", max_sections = 4 })

        expect(ctx.result.section_count).to.equal(4)
        expect(#ctx.result.skeleton).to.equal(4)
    end)

    -- ───────────────────────────────────────────────────────────────
    -- Test 4: LLM call count — 1 skeleton + N fills
    -- ───────────────────────────────────────────────────────────────

    it("counts LLM calls correctly: 1 skeleton + N fills", function()
        local stub, counter = make_alc_stub({
            fixtures = {
                "1. Intro\n2. Body\n3. Conclusion",
                "Fill 1.", "Fill 2.", "Fill 3.",
            },
        })
        _G.alc = stub

        local sot = require("sot")
        sot.run({ task = "Write about testing" })

        -- 1 skeleton call + 3 section fills = 4 total alc.llm calls
        expect(counter.llm_calls).to.equal(4)
    end)

    -- ───────────────────────────────────────────────────────────────
    -- Test 5 (optional): alc.parallel called, alc.map not called
    -- ───────────────────────────────────────────────────────────────

    it("uses alc.parallel for fills, not alc.map", function()
        local stub, counter = make_alc_stub({
            fixtures = {
                "1. Intro\n2. Body",
                "Fill 1.", "Fill 2.",
            },
        })
        -- Ensure map would raise if accidentally called
        stub.map = function()
            error("alc.map must not be called after alc.parallel migration")
        end
        _G.alc = stub

        local sot = require("sot")
        sot.run({ task = "Write about testing" })

        expect(counter.parallel_calls).to.equal(1)
    end)
end)
