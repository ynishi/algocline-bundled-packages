--- Tests for civic.broadcast_bus

-- ─── Test Helpers ──────────────────────────────────────────
-- Per README §"Adding a new test file": `package.path` is set by the MCP
-- harness via `search_paths=[REPO]`. Do NOT prepend os.getenv("PWD") here
-- — in worktree context PWD points at the parent repo, which silently
-- shadows the worktree's code and produces false-green pass reports.

local describe, it, expect = lust.describe, lust.it, lust.expect

local cbb   = require("civic.broadcast_bus")
local civic = require("civic")

-- ─── Happy path ──────────────────────────────────────────────────────────────

describe("civic.broadcast_bus — happy path", function()
    it("new() returns an empty bus", function()
        local bus = cbb.new()
        expect(bus).to.exist()
        expect(type(bus._msgs)).to.equal("table")
        expect(#bus._msgs).to.equal(0)
    end)

    it("publish stores a message", function()
        local bus = cbb.new()
        bus:publish(1, { value = 42 })
        expect(#bus._msgs).to.equal(1)
        expect(bus._msgs[1].src).to.equal(1)
        expect(bus._msgs[1].msg.value).to.equal(42)
    end)

    it("publish stores multiple messages in order", function()
        local bus = cbb.new()
        bus:publish(1, "alpha")
        bus:publish(2, "beta")
        bus:publish(3, "gamma")
        expect(#bus._msgs).to.equal(3)
        expect(bus._msgs[1].msg).to.equal("alpha")
        expect(bus._msgs[2].msg).to.equal("beta")
        expect(bus._msgs[3].msg).to.equal("gamma")
    end)

    it("aggregate_for sums selected messages", function()
        local bus = cbb.new()
        bus:publish(1, { v = 3 })
        bus:publish(2, { v = 7 })
        bus:publish(3, { v = 2 })

        local result = bus:aggregate_for(
            99,
            function(src) return src == 1 or src == 2 end,
            function(msgs)
                local s = 0
                for _, m in ipairs(msgs) do s = s + m.v end
                return s
            end
        )
        expect(result).to.equal(10)
    end)

    it("aggregate_for returns agg_fn({}) when no messages match", function()
        local bus = cbb.new()
        bus:publish(1, "x")

        local result = bus:aggregate_for(
            2,
            function(src) return src == 99 end,  -- no match
            function(msgs) return #msgs end
        )
        expect(result).to.equal(0)
    end)

    it("aggregate_for collects all messages when selector is always true", function()
        local bus = cbb.new()
        bus:publish(1, 10)
        bus:publish(2, 20)
        bus:publish(3, 30)

        local collected = bus:aggregate_for(
            1,
            function(_) return true end,
            function(msgs) return msgs end
        )
        expect(#collected).to.equal(3)
        expect(collected[1]).to.equal(10)
        expect(collected[2]).to.equal(20)
        expect(collected[3]).to.equal(30)
    end)

    it("reset clears all published messages", function()
        local bus = cbb.new()
        bus:publish(1, "msg1")
        bus:publish(2, "msg2")
        expect(#bus._msgs).to.equal(2)

        bus:reset()
        expect(#bus._msgs).to.equal(0)
    end)

    it("publish and aggregate_for work correctly across multiple rounds", function()
        local bus = cbb.new()

        -- Round 1
        bus:publish(1, { n = 5 })
        bus:publish(2, { n = 3 })
        local r1 = bus:aggregate_for(
            1,
            function(src) return src == 2 end,
            function(msgs)
                return msgs[1] and msgs[1].n or 0
            end
        )
        expect(r1).to.equal(3)

        bus:reset()

        -- Round 2 — fresh slate
        bus:publish(2, { n = 100 })
        local r2 = bus:aggregate_for(
            1,
            function(src) return src == 2 end,
            function(msgs)
                return msgs[1] and msgs[1].n or 0
            end
        )
        expect(r2).to.equal(100)
    end)

    it("same src publishes twice — both entries are stored (append-only)", function()
        local bus = cbb.new()
        bus:publish(1, "first")
        bus:publish(1, "second")
        expect(#bus._msgs).to.equal(2)
        local collected = bus:aggregate_for(
            99,
            function(src) return src == 1 end,
            function(msgs) return msgs end
        )
        expect(#collected).to.equal(2)
        expect(collected[1]).to.equal("first")
        expect(collected[2]).to.equal("second")
    end)

    it("msg payload is opaque — accepts any type (string, number, table, boolean)", function()
        local bus = cbb.new()
        bus:publish(1, "hello")
        bus:publish(2, 999)
        bus:publish(3, { nested = { deep = true } })
        bus:publish(4, false)
        expect(#bus._msgs).to.equal(4)
        expect(bus._msgs[2].msg).to.equal(999)
        expect(bus._msgs[4].msg).to.equal(false)
    end)

    it("M.Bus metatable is exposed", function()
        expect(cbb.Bus).to.exist()
        expect(cbb.Bus.__index).to.exist()
    end)

    it("civic.shape.broadcast_entry is exposed as a table (T.shape descriptor)", function()
        -- Shape lives on civic/init.lua, not on the component module.
        expect(civic.shape).to.exist()
        expect(civic.shape.broadcast_entry).to.exist()
        expect(type(civic.shape.broadcast_entry)).to.equal("table")
    end)
end)

-- ─── Reject (runtime assert / invariant violation) ───────────────────────────

describe("civic.broadcast_bus — reject (runtime assert)", function()
    it("publish rejects src = 0", function()
        local bus = cbb.new()
        local ok, err = pcall(function() bus:publish(0, "x") end)
        expect(ok).to.equal(false)
        expect(err:find("src must be positive integer")).to.exist()
    end)

    it("publish rejects negative src", function()
        local bus = cbb.new()
        local ok, err = pcall(function() bus:publish(-1, "x") end)
        expect(ok).to.equal(false)
        expect(err:find("src must be positive integer")).to.exist()
    end)

    it("publish rejects fractional src", function()
        local bus = cbb.new()
        local ok, err = pcall(function() bus:publish(1.5, "x") end)
        expect(ok).to.equal(false)
        expect(err:find("src must be positive integer")).to.exist()
    end)

    it("publish rejects string src", function()
        local bus = cbb.new()
        local ok, err = pcall(function() bus:publish("slot1", "x") end)
        expect(ok).to.equal(false)
        expect(err:find("src must be positive integer")).to.exist()
    end)

    it("publish rejects nil src", function()
        local bus = cbb.new()
        local ok, err = pcall(function() bus:publish(nil, "x") end)
        expect(ok).to.equal(false)
        expect(err:find("src must be positive integer")).to.exist()
    end)

    it("aggregate_for rejects target = 0", function()
        local bus = cbb.new()
        local ok, err = pcall(function()
            bus:aggregate_for(0, function() return true end, function(m) return m end)
        end)
        expect(ok).to.equal(false)
        expect(err:find("target must be positive integer")).to.exist()
    end)

    it("aggregate_for rejects non-function selector_fn", function()
        local bus = cbb.new()
        local ok, err = pcall(function()
            bus:aggregate_for(1, "not_a_fn", function(m) return m end)
        end)
        expect(ok).to.equal(false)
        expect(err:find("selector_fn must be function")).to.exist()
    end)

    it("aggregate_for rejects non-function agg_fn", function()
        local bus = cbb.new()
        local ok, err = pcall(function()
            bus:aggregate_for(1, function() return true end, 42)
        end)
        expect(ok).to.equal(false)
        expect(err:find("agg_fn must be function")).to.exist()
    end)

    it("aggregate_for rejects nil selector_fn", function()
        local bus = cbb.new()
        local ok, err = pcall(function()
            bus:aggregate_for(1, nil, function(m) return m end)
        end)
        expect(ok).to.equal(false)
        expect(err:find("selector_fn must be function")).to.exist()
    end)
end)

-- ─── Invariant ───────────────────────────────────────────────────────────────

describe("civic.broadcast_bus — invariant", function()
    it("reset yields empty bus: aggregate_for returns agg_fn({})", function()
        local bus = cbb.new()
        bus:publish(1, "x")
        bus:reset()

        local result = bus:aggregate_for(
            1,
            function(_) return true end,
            function(msgs) return #msgs end
        )
        expect(result).to.equal(0)
    end)

    it("publish is append-only within a round (order preserved)", function()
        local bus = cbb.new()
        for i = 1, 5 do
            bus:publish(i, i * 10)
        end
        local seen = bus:aggregate_for(
            99,
            function(_) return true end,
            function(msgs)
                local r = {}
                for _, m in ipairs(msgs) do r[#r + 1] = m end
                return r
            end
        )
        expect(seen[1]).to.equal(10)
        expect(seen[2]).to.equal(20)
        expect(seen[3]).to.equal(30)
        expect(seen[4]).to.equal(40)
        expect(seen[5]).to.equal(50)
    end)

    it("multiple aggregate_for calls on same round see same data", function()
        local bus = cbb.new()
        bus:publish(1, 1)
        bus:publish(2, 2)
        bus:publish(3, 3)

        local sel_all = function(_) return true end
        local count = function(msgs) return #msgs end

        local r1 = bus:aggregate_for(10, sel_all, count)
        local r2 = bus:aggregate_for(20, sel_all, count)
        expect(r1).to.equal(3)
        expect(r2).to.equal(3)
    end)

    it("reset preserves bus identity (metatable intact after reset)", function()
        local bus = cbb.new()
        bus:publish(1, "x")
        bus:reset()

        -- Bus is still usable after reset
        bus:publish(2, "y")
        local result = bus:aggregate_for(
            1,
            function(src) return src == 2 end,
            function(msgs) return msgs[1] end
        )
        expect(result).to.equal("y")
    end)

    it("new() always produces independent instances", function()
        local b1 = cbb.new()
        local b2 = cbb.new()

        b1:publish(1, "from_b1")
        -- b2 sees nothing from b1
        local count = b2:aggregate_for(
            1,
            function(_) return true end,
            function(msgs) return #msgs end
        )
        expect(count).to.equal(0)
    end)

    it("civic.meta conforms to required fields", function()
        -- civic/init.lua owns M.meta; component modules have none.
        expect(civic.meta.name).to.equal("civic")
        expect(civic.meta.version).to.equal("0.1.0")
        expect(civic.meta.category).to.equal("substrate")
        expect(type(civic.meta.description)).to.equal("string")
        expect(civic.meta.alc_shapes_compat).to.equal("^0.25")
    end)

    it("aggregate_for target value does not affect result (informational-only param)", function()
        local bus = cbb.new()
        bus:publish(1, 10)
        bus:publish(2, 20)

        local sel_all = function(_) return true end
        local sum = function(msgs)
            local s = 0
            for _, m in ipairs(msgs) do s = s + m end
            return s
        end

        local r1 = bus:aggregate_for(1, sel_all, sum)
        local r2 = bus:aggregate_for(999, sel_all, sum)
        expect(r1).to.equal(30)
        expect(r2).to.equal(30)
    end)

    it("civic.shape.broadcast_entry.fields has src and msg keys", function()
        local entry = civic.shape.broadcast_entry
        expect(entry.fields).to.exist()
        expect(entry.fields.src).to.exist()
        expect(entry.fields.msg).to.exist()
    end)

    it("civic has no legacy M.VERSION top-level field", function()
        -- W_META_LEGACY_M_VERSION lint guard: civic pkg must not expose M.VERSION
        expect(civic.VERSION).to.equal(nil)
    end)
end)
