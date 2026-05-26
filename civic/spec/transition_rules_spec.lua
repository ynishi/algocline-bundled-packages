--- Tests for civic.transition_rules

local describe, it, expect = lust.describe, lust.it, lust.expect

local tr   = require("civic.transition_rules")
local civic = require("civic")

-- ─── Happy path ──────────────────────────────────────────────────────────────

describe("civic.transition_rules — happy path", function()
    it("new() returns an empty rule set", function()
        local rules = tr.new()
        expect(rules).to.exist()
        expect(rules:size()).to.equal(0)
    end)

    it("add appends a rule and increments size", function()
        local rules = tr.new()
        rules:add("alive", "dead", function() return true end)
        expect(rules:size()).to.equal(1)
    end)

    it("apply transitions state when predicate matches", function()
        local rules = tr.new()
        rules:add("alive", "dead", function(p, ctx)
            return ctx.neighbors < 2
        end)
        local out = rules:apply({ state = "alive", energy = 5 }, { neighbors = 1 })
        expect(out.state).to.equal("dead")
        expect(out.energy).to.equal(5)
    end)

    it("apply returns shallow copy with unchanged state when no rule matches", function()
        local rules = tr.new()
        rules:add("alive", "dead", function() return false end)
        local payload = { state = "alive", x = 42 }
        local out = rules:apply(payload, {})
        expect(out.state).to.equal("alive")
        expect(out.x).to.equal(42)
        expect(rawequal(out, payload)).to.equal(false)
    end)

    it("apply supports multiple rules", function()
        local rules = tr.new()
        rules:add("alive", "dead", function(p, ctx) return ctx.n < 2 end)
        rules:add("dead", "alive", function(p, ctx) return ctx.n == 3 end)

        local out1 = rules:apply({ state = "alive" }, { n = 1 })
        expect(out1.state).to.equal("dead")

        local out2 = rules:apply({ state = "dead" }, { n = 3 })
        expect(out2.state).to.equal("alive")
    end)

    it("Rules metatable is exposed", function()
        expect(tr.Rules).to.exist()
        expect(tr.Rules.__index).to.exist()
    end)
end)

-- ─── Reject ──────────────────────────────────────────────────────────────────

describe("civic.transition_rules — reject", function()
    it("add rejects empty from string", function()
        local rules = tr.new()
        local ok, err = pcall(function() rules:add("", "dead", function() return true end) end)
        expect(ok).to.equal(false)
        expect(err:find("from must be non%-empty string")).to.exist()
    end)

    it("add rejects non-string from", function()
        local rules = tr.new()
        local ok, err = pcall(function() rules:add(42, "dead", function() return true end) end)
        expect(ok).to.equal(false)
        expect(err:find("from must be non%-empty string")).to.exist()
    end)

    it("add rejects empty to string", function()
        local rules = tr.new()
        local ok, err = pcall(function() rules:add("alive", "", function() return true end) end)
        expect(ok).to.equal(false)
        expect(err:find("to must be non%-empty string")).to.exist()
    end)

    it("add rejects non-function predicate", function()
        local rules = tr.new()
        local ok, err = pcall(function() rules:add("alive", "dead", "not_fn") end)
        expect(ok).to.equal(false)
        expect(err:find("predicate must be function")).to.exist()
    end)

    it("apply rejects non-table payload", function()
        local rules = tr.new()
        local ok, err = pcall(function() rules:apply("bad", {}) end)
        expect(ok).to.equal(false)
        expect(err:find("payload must be table")).to.exist()
    end)

    it("apply rejects payload without string state", function()
        local rules = tr.new()
        local ok, err = pcall(function() rules:apply({ state = 123 }, {}) end)
        expect(ok).to.equal(false)
        expect(err:find("payload.state must be string")).to.exist()
    end)

    it("apply rejects payload with nil state", function()
        local rules = tr.new()
        local ok, err = pcall(function() rules:apply({ x = 1 }, {}) end)
        expect(ok).to.equal(false)
        expect(err:find("payload.state must be string")).to.exist()
    end)
end)

-- ─── Invariant ───────────────────────────────────────────────────────────────

describe("civic.transition_rules — invariant", function()
    it("first-match-wins: earlier rule takes priority", function()
        local rules = tr.new()
        rules:add("alive", "zombie", function() return true end)
        rules:add("alive", "dead", function() return true end)
        local out = rules:apply({ state = "alive" }, {})
        expect(out.state).to.equal("zombie")
    end)

    it("no-match returns shallow copy (original table not mutated)", function()
        local rules = tr.new()
        rules:add("x", "y", function() return true end)
        local payload = { state = "alive", data = { nested = true } }
        local out = rules:apply(payload, {})
        expect(out.state).to.equal("alive")
        expect(payload.state).to.equal("alive")
        expect(out.data).to.equal(payload.data)
    end)

    it("apply always returns a new table (never the same reference)", function()
        local rules = tr.new()
        local payload = { state = "idle" }
        local out = rules:apply(payload, {})
        expect(rawequal(out, payload)).to.equal(false)
    end)

    it("ctx is forwarded to predicate", function()
        local rules = tr.new()
        local captured_ctx
        rules:add("a", "b", function(p, ctx) captured_ctx = ctx; return true end)
        local my_ctx = { key = "val" }
        rules:apply({ state = "a" }, my_ctx)
        expect(captured_ctx).to.equal(my_ctx)
    end)

    it("new() produces independent instances", function()
        local r1 = tr.new()
        local r2 = tr.new()
        r1:add("a", "b", function() return true end)
        expect(r1:size()).to.equal(1)
        expect(r2:size()).to.equal(0)
    end)

    it("civic.transition_rules is wired from civic/init.lua", function()
        expect(civic.transition_rules).to.exist()
        expect(civic.transition_rules.new).to.exist()
    end)
end)
