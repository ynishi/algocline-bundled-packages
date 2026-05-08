--- Tests for review_and_investigate (deep code review with investigation).
---
--- Coverage (5 cases):
---   1. Early return — Phase 1 detects no themes → empty result
---   2. Input validation — ctx.code missing → error
---   3. Context filter all → early return with context_filtered=true
---   4. Phase 2 false positive removal → all false positives → early return
---   5. Full run (1 theme, all phases) → themes[1] has root_cause and fixes

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

for _, name in ipairs({
    "review_and_investigate",
    "alc_shapes", "alc_shapes.t", "alc_shapes.check", "alc_shapes.reflect",
    "step_back", "meta_prompt", "reflect", "calibrate", "triad", "contrastive",
}) do
    package.loaded[name] = nil
end

local function reset()
    package.loaded["review_and_investigate"] = nil
    package.loaded["step_back"] = nil
    package.loaded["meta_prompt"] = nil
    package.loaded["reflect"] = nil
    package.loaded["calibrate"] = nil
    package.loaded["triad"] = nil
    package.loaded["contrastive"] = nil
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

    stub.json_decode = function(text)
        -- Return the stored decode fixture if any, otherwise return nil
        if opts.json_decode_fn then
            return opts.json_decode_fn(text)
        end
        return nil
    end

    stub.json_encode = function(_val)
        return "[]"
    end

    stub.stats = { record = function(_key, _val) end }

    return stub, counter
end

-- Helper: install a stub for an inner required pkg
local function stub_step_back(result_override)
    package.loaded["step_back"] = {
        run = function(_ctx)
            return { result = result_override or { answer = "Design principles extracted." } }
        end,
    }
end

local function stub_meta_prompt(answer)
    package.loaded["meta_prompt"] = {
        run = function(_ctx)
            return {
                result = {
                    answer = answer or "Root cause analysis.",
                    experts_consulted = {},
                    total_experts = 1,
                },
            }
        end,
    }
end

local function stub_reflect(output)
    package.loaded["reflect"] = {
        run = function(_ctx)
            return { result = { output = output or "Structural issue confirmed." } }
        end,
    }
end

local function stub_calibrate(confidence, escalated)
    package.loaded["calibrate"] = {
        run = function(_ctx)
            return {
                result = {
                    confidence = confidence or 0.8,
                    escalated = escalated or false,
                    answer = "Calibrated answer.",
                },
            }
        end,
    }
end

local function stub_triad()
    package.loaded["triad"] = {
        run = function(_ctx)
            return { result = { verdict = "Triad verdict.", winner = "proponent", transcript = {} } }
        end,
    }
end

local function stub_contrastive()
    package.loaded["contrastive"] = {
        run = function(_ctx)
            return { result = { answer = "Anti-patterns identified.", contrasts = {} } }
        end,
    }
end

-- One theme fixture in valid JSON
local ONE_THEME_JSON = '[{"id":"T1","name":"error-handling","category":"safety","surface_symptom":"Missing error check","locations":["main.lua:10"],"span":[1,5]}]'

-- ═══════════════════════════════════════════════════════════════════
-- Case 1: Phase 1 detects no themes → empty result (early return)
-- ═══════════════════════════════════════════════════════════════════

describe("review_and_investigate.run no themes", function()
    lust.after(reset)

    it("returns empty themes when Phase 1 extracts nothing", function()
        reset()
        stub_step_back()
        -- Phase 1b: detect → returns non-JSON text → parse fails → themes=[]
        local stub, _ = make_alc_stub({
            fixtures = {
                "No issues found in this code.",  -- Phase 1b detect → parse failure → []
            },
            json_decode_fn = function(_text) return nil end,
        })
        _G.alc = stub
        local m = require("review_and_investigate")
        local ctx = m.run({ code = "local x = 1" })
        expect(ctx.result).to_not.equal(nil)
        expect(#ctx.result.themes).to.equal(0)
        expect(ctx.result.summary.total_themes).to.equal(0)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 2: Input validation — ctx.code missing → error
-- ═══════════════════════════════════════════════════════════════════

describe("review_and_investigate.run input validation", function()
    lust.after(reset)

    it("errors when ctx.code is missing", function()
        reset()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("review_and_investigate")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:find("code") ~= nil).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 3: Context filter all → early return with context_filtered=true
-- ═══════════════════════════════════════════════════════════════════

describe("review_and_investigate.run context filter all", function()
    lust.after(reset)

    it("returns context_filtered=true when all themes filtered by context", function()
        reset()
        stub_step_back()
        -- Phase 1b returns 1 theme; context_filter answers YES (filter out)
        local theme_json_str = ONE_THEME_JSON
        local call_n = 0
        local stub, _ = make_alc_stub({
            fixtures = {
                "",   -- Phase 1b: will be overridden by json_decode_fn
                "YES This is intentional design.",  -- Phase 1.5 context filter → filtered
            },
            json_decode_fn = function(_text)
                call_n = call_n + 1
                if call_n == 1 then
                    -- Return parsed theme table
                    return { { id = "T1", name = "error-handling", category = "safety",
                               surface_symptom = "Missing error check", locations = {}, span = {1,5} } }
                end
                return nil
            end,
        })
        _G.alc = stub
        local m = require("review_and_investigate")
        local ctx = m.run({
            code = "local x = 1",
            context = "This is a design constraint.",
        })
        expect(ctx.result.summary.total_themes).to.equal(0)
        expect(ctx.result.summary.context_filtered).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 4: Phase 2 removes all as false positives → early return
-- ═══════════════════════════════════════════════════════════════════

describe("review_and_investigate.run false positive removal", function()
    lust.after(reset)

    it("returns empty themes when Phase 2 marks all as false positives", function()
        reset()
        stub_step_back()
        local call_n = 0
        -- Phase 2 parallel → stub returns FALSE_POSITIVE
        local stub, _ = make_alc_stub({
            fixtures = {
                "",                                    -- Phase 1b detect
                "FALSE_POSITIVE: Not actually an issue.",  -- Phase 2 verify
            },
            json_decode_fn = function(_text)
                call_n = call_n + 1
                if call_n == 1 then
                    return { { id = "T1", name = "error-handling", category = "safety",
                               surface_symptom = "Missing check", locations = {}, span = {1,5} } }
                end
                return nil
            end,
        })
        _G.alc = stub
        local m = require("review_and_investigate")
        local ctx = m.run({ code = "local x = 1" })
        expect(#ctx.result.themes).to.equal(0)
        -- false_positives_removed should be 1
        expect(ctx.result.summary.false_positives_removed).to.equal(1)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 5: Full run — 1 confirmed theme goes through all phases
-- ═══════════════════════════════════════════════════════════════════

describe("review_and_investigate.run full pipeline", function()
    lust.after(reset)

    it("produces theme with root_cause and fixes after all phases", function()
        reset()
        stub_step_back()
        stub_meta_prompt("Structural root cause identified.")
        stub_reflect("Structural issue confirmed.")
        stub_calibrate(0.85, false)  -- high confidence, no deep analysis
        stub_contrastive()
        local call_n = 0
        local stub, _ = make_alc_stub({
            fixtures = {
                "",             -- Phase 1b detect (overridden by json_decode_fn)
                -- Phase 2: verify → CONFIRMED
                "CONFIRMED: Error check is genuinely missing.",
                -- Phase 3: explore → JSON with related locations
                "",             -- will be overridden for explore
                -- Phase 5: research → JSON with best_practice
                "",             -- will be overridden for research
                -- Phase 6: generate fixes → single fix (no tournament)
                "",             -- will be overridden for fixes
            },
            json_decode_fn = function(_text)
                call_n = call_n + 1
                if call_n == 1 then
                    -- Phase 1: themes
                    return { { id = "T1", name = "error-handling", category = "safety",
                               surface_symptom = "Missing check", locations = {}, span = {1,5} } }
                elseif call_n == 2 then
                    -- Phase 3: explore result
                    return { related_locations = {"main.lua:10"}, pattern = "error", total_occurrences = 1 }
                elseif call_n == 3 then
                    -- Phase 5: research result
                    return { best_practice = "Always check errors.", current_state = "Missing.",
                             gap = "No error handling.", references = {} }
                elseif call_n == 4 then
                    -- Phase 6: fixes (single fix, no tournament)
                    return { { id = "F1", summary = "Add error check", approach = "Use pcall",
                               impact = "Local", risk = "Low", avoids = "Swallowing errors" } }
                end
                return nil
            end,
        })
        _G.alc = stub
        local m = require("review_and_investigate")
        local ctx = m.run({ code = "local x = 1\n-- no error handling" })
        expect(#ctx.result.themes).to.equal(1)
        local t = ctx.result.themes[1]
        expect(t.root_cause).to_not.equal(nil)
        expect(t.best_practice).to_not.equal(nil)
        -- fixes should exist (1 fix, no ranking)
        expect(type(t.fixes)).to.equal("table")
        expect(ctx.result.summary.total_themes).to.equal(1)
    end)
end)
