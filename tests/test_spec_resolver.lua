--- Tests for alc_shapes.spec_resolver.
---
--- Covers 2-branch normalization (typed / opaque), auto-assert_dev in run(),
--- is_passthrough lookup, and Schema-as-Data persistence (metatable-stripped
--- spec still resolves).

local describe, it, expect = lust.describe, lust.it, lust.expect

package.loaded["alc_shapes"] = nil
package.loaded["alc_shapes.spec_resolver"] = nil

local S  = require("alc_shapes")
local SR = S.spec_resolver
local T  = S.T

-- ── Inline fixtures ────────────────────────────────────────────────────
-- Prefer inline constructions over file fixtures: each test carries its
-- own contract, so a reader sees input+expected in one place.

-- AlcCtx 規約: M.run(ctx) は ctx を返し、実 result は ctx.result に入れる。
-- fixture もこの規約に揃える。

local function voted_fixture()
    return {
        consensus   = "X",
        answer      = "X",
        answer_norm = "x",
        paths = {
            { reasoning = "a", answer = "X" },
            { reasoning = "b", answer = "X" },
        },
        votes = { "x", "x" },
        vote_counts = { x = 2 },
        n_sampled = 2,
        total_llm_calls = 2,
    }
end

local function make_typed_pkg()
    return {
        meta = { name = "typed_fix", version = "0.0.0" },
        spec = {
            entries = {
                run = {
                    input  = T.shape({ task = T.string }, { open = true }),
                    result = T.ref("voted"),
                },
            },
        },
        run = function(ctx)
            ctx.result = voted_fixture()
            return ctx
        end,
    }
end

local function make_opaque_pkg()
    return {
        meta = { name = "opaque_fix" },
        run  = function(ctx)
            ctx.result = { whatever = "I do my own thing" }
            return ctx
        end,
    }
end

local function make_filter_pkg()
    -- voted → voted with passthrough hint (no bundled pkg declares this
    -- pattern yet; construct locally so is_passthrough() has a fixture).
    return {
        meta = { name = "filter_fix" },
        spec = {
            entries = {
                run = { input = "voted", result = "voted" },
            },
            compose = { passthrough = "voted" },
        },
        run = function(ctx)
            local v = ctx.voted
            ctx.result = {
                consensus = v.consensus,
                answer = v.answer,
                answer_norm = v.answer_norm,
                paths = { v.paths[1] },
                votes = { v.votes[1] },
                vote_counts = v.vote_counts,
                n_sampled = 1,
                total_llm_calls = v.total_llm_calls,
            }
            return ctx
        end,
    }
end

-- ── resolve ────────────────────────────────────────────────────────────

describe("spec_resolver.resolve: 2-branch normalization", function()
    it("typed pkg → kind='typed', origin='spec', entries populated", function()
        local r = SR.resolve(make_typed_pkg())
        expect(r.kind).to.equal("typed")
        expect(r.origin).to.equal("spec")
        expect(type(r.entries.run)).to.equal("table")
        expect(r.entries.run.input).to.exist()
        expect(r.entries.run.result).to.exist()
    end)

    it("opaque pkg → kind='opaque', entries empty", function()
        local r = SR.resolve(make_opaque_pkg())
        expect(r.kind).to.equal("opaque")
        expect(r.origin).to.equal("none")
        expect(next(r.entries)).to.equal(nil)
    end)

    it("coerces string shape name to T.ref", function()
        local r = SR.resolve(make_filter_pkg())
        expect(rawget(r.entries.run.input, "kind")).to.equal("ref")
        expect(rawget(r.entries.run.input, "name")).to.equal("voted")
        expect(rawget(r.entries.run.result, "kind")).to.equal("ref")
    end)

    it("inline T.shape passes through unchanged", function()
        local r = SR.resolve(make_typed_pkg())
        expect(rawget(r.entries.run.input, "kind")).to.equal("shape")
    end)

    it("preserves compose / exports when present", function()
        local r = SR.resolve(make_filter_pkg())
        expect(r.compose.passthrough).to.equal("voted")
        expect(r.exports).to.equal(nil)
    end)

    it("non-table pkg argument is a loud error", function()
        local ok, err = pcall(SR.resolve, "nope")
        expect(ok).to.equal(false)
        expect(err:match("pkg must be a table")).to.exist()
    end)

    it("bundled pkg (cot) resolves as typed with input+result", function()
        package.loaded["cot"] = nil
        local cot = require("cot")
        local r = SR.resolve(cot)
        expect(r.kind).to.equal("typed")
        expect(r.entries.run.input).to.exist()
        expect(r.entries.run.result).to.exist()
    end)

    it("bundled pkg with 2 entries (calibrate) surfaces both", function()
        package.loaded["calibrate"] = nil
        local cal = require("calibrate")
        local r = SR.resolve(cal)
        expect(r.entries.run).to.exist()
        expect(r.entries.assess).to.exist()
        expect(rawget(r.entries.run.result, "name")).to.equal("calibrated")
        expect(rawget(r.entries.assess.result, "name")).to.equal("assessed")
    end)
end)

-- ── run ────────────────────────────────────────────────────────────────

describe("spec_resolver.run: unified invocation", function()
    it("typed pkg returns ctx with result set (post-check may fire in dev mode)", function()
        local pkg = make_typed_pkg()
        local returned = SR.run(pkg, { task = "test" })
        expect(returned.result.consensus).to.equal("X")
        expect(returned.result.n_sampled).to.equal(2)
    end)

    it("opaque pkg returns ctx.result straight through", function()
        local pkg = make_opaque_pkg()
        local returned = SR.run(pkg, { any = "thing" })
        expect(returned.result.whatever).to.equal("I do my own thing")
    end)

    it("missing entry function is a loud error", function()
        local pkg = make_opaque_pkg()
        local ok, err = pcall(SR.run, pkg, {}, "nonexistent")
        expect(ok).to.equal(false)
        expect(err:match("no function 'nonexistent'")).to.exist()
    end)

    it("opaque pkg skips assert_dev even in dev mode", function()
        -- Broken result is fine because resolver has no schema to check.
        local pkg = make_opaque_pkg()
        pkg.run = function(ctx)
            ctx.result = { anything = 1 }
            return ctx
        end
        local ok = pcall(SR.run, pkg, {})
        expect(ok).to.equal(true)
    end)

    it("typed pkg with broken result: dev-off passes, dev-on throws", function()
        local pkg = make_typed_pkg()
        pkg.run = function(ctx)
            ctx.result = { wrong_shape = true }
            return ctx
        end
        if not S.is_dev_mode() then
            local ok = pcall(SR.run, pkg, { task = "t" })
            expect(ok).to.equal(true)
            return
        end
        local ok, err = pcall(SR.run, pkg, { task = "t" })
        expect(ok).to.equal(false)
        expect(err).to.exist()
    end)
end)

-- ── AlcCtx convention ────────────────────────────────────────────────

describe("spec_resolver.run: AlcCtx post-check against returned.result", function()
    it("when returned is a ctx table, resolver checks returned.result", function()
        -- typed_fix declares result = T.ref("voted"). Returning ctx with
        -- ctx.result set to a valid voted shape must pass post-check even
        -- when ctx itself carries random extra fields (task, scratch, etc).
        local pkg = make_typed_pkg()
        local returned = SR.run(pkg, { task = "t", scratch = { a = 1 } })
        expect(returned.result.consensus).to.equal("X")
        expect(returned.scratch.a).to.equal(1)  -- ctx preserved
    end)

    it("when pkg returns shape directly (no .result), resolver checks returned", function()
        -- External pkg that does not follow AlcCtx convention: returns the
        -- shape directly. Resolver falls back to checking returned verbatim.
        local pkg = {
            meta = { name = "direct_return" },
            spec = { entries = { run = { result = T.ref("voted") } } },
            run  = function(_) return voted_fixture() end,
        }
        local returned = SR.run(pkg, {})
        expect(returned.consensus).to.equal("X")
    end)
end)

-- ── is_passthrough ────────────────────────────────────────────────────

describe("spec_resolver.is_passthrough", function()
    it("filter pkg → true for declared shape", function()
        expect(SR.is_passthrough(make_filter_pkg(), "voted")).to.equal(true)
    end)

    it("filter pkg → false for other shape", function()
        expect(SR.is_passthrough(make_filter_pkg(), "paneled")).to.equal(false)
    end)

    it("typed pkg without compose → false", function()
        expect(SR.is_passthrough(make_typed_pkg(), "voted")).to.equal(false)
    end)

    it("opaque pkg → always false", function()
        expect(SR.is_passthrough(make_opaque_pkg(), "voted")).to.equal(false)
    end)

    it("accepts passthrough as a string list", function()
        local pkg = {
            meta = { name = "multi" },
            spec = {
                entries = { run = { input = "voted", result = "voted" } },
                compose = { passthrough = { "voted", "paneled" } },
            },
            run = function(ctx) return ctx.voted end,
        }
        expect(SR.is_passthrough(pkg, "voted")).to.equal(true)
        expect(SR.is_passthrough(pkg, "paneled")).to.equal(true)
        expect(SR.is_passthrough(pkg, "tournament")).to.equal(false)
    end)
end)

-- ── mixed pipeline ────────────────────────────────────────────────────

describe("typed / opaque mixed pipeline", function()
    it("typed → opaque → typed chain runs end-to-end", function()
        local r1 = SR.run(make_typed_pkg(), { task = "start" })
        expect(r1.result.consensus).to.equal("X")

        local r2 = SR.run(make_opaque_pkg(), { prev = r1 })
        expect(r2.result.whatever).to.exist()

        local r3 = SR.run(make_typed_pkg(), { task = "end" })
        expect(r3.result.consensus).to.equal("X")
    end)
end)

-- ── Schema-as-Data persistence invariant ──────────────────────────────

describe("spec is metatable-strip-safe", function()
    it("typed pkg resolves identically after metatable strip", function()
        local pkg = make_typed_pkg()
        local function strip(v)
            if type(v) == "table" then
                setmetatable(v, nil)
                for _, sub in pairs(v) do strip(sub) end
            end
            return v
        end
        strip(pkg.spec)
        local r = SR.resolve(pkg)
        expect(r.kind).to.equal("typed")
        expect(r.origin).to.equal("spec")
        expect(r.entries.run).to.exist()
    end)
end)
