--- Tests for civic.slot_table

local describe, it, expect = lust.describe, lust.it, lust.expect

local st   = require("civic.slot_table")
local civic = require("civic")

-- ─── Happy path ──────────────────────────────────────────────────────────────

describe("civic.slot_table — happy path", function()
    it("new() creates a table of n slots", function()
        local slots = st.new(3, function(i) return { id = i } end)
        expect(slots).to.exist()
        expect(slots:size()).to.equal(3)
    end)

    it("get returns the payload at idx", function()
        local slots = st.new(2, function(i) return { val = i * 10 } end)
        expect(slots:get(1).val).to.equal(10)
        expect(slots:get(2).val).to.equal(20)
    end)

    it("set replaces payload at idx", function()
        local slots = st.new(2, function(i) return { val = 0 } end)
        slots:set(1, { val = 99 })
        expect(slots:get(1).val).to.equal(99)
    end)

    it("iter yields all (idx, payload) pairs in order", function()
        local slots = st.new(3, function(i) return { n = i } end)
        local collected = {}
        for idx, p in slots:iter() do
            collected[idx] = p.n
        end
        expect(collected[1]).to.equal(1)
        expect(collected[2]).to.equal(2)
        expect(collected[3]).to.equal(3)
    end)

    it("SlotTable metatable is exposed", function()
        expect(st.SlotTable).to.exist()
        expect(st.SlotTable.__index).to.exist()
    end)
end)

-- ─── Reject ──────────────────────────────────────────────────────────────────

describe("civic.slot_table — reject", function()
    it("new rejects n = 0", function()
        local ok, err = pcall(function() st.new(0, function(i) return {} end) end)
        expect(ok).to.equal(false)
        expect(err:find("n must be positive integer")).to.exist()
    end)

    it("new rejects negative n", function()
        local ok, err = pcall(function() st.new(-1, function(i) return {} end) end)
        expect(ok).to.equal(false)
        expect(err:find("n must be positive integer")).to.exist()
    end)

    it("new rejects fractional n", function()
        local ok, err = pcall(function() st.new(2.5, function(i) return {} end) end)
        expect(ok).to.equal(false)
        expect(err:find("n must be positive integer")).to.exist()
    end)

    it("new rejects non-function init_fn", function()
        local ok, err = pcall(function() st.new(2, "bad") end)
        expect(ok).to.equal(false)
        expect(err:find("init_fn must be function")).to.exist()
    end)

    it("new rejects init_fn returning non-table", function()
        local ok, err = pcall(function() st.new(2, function(i) return 42 end) end)
        expect(ok).to.equal(false)
        expect(err:find("init_fn%(1%) must return table")).to.exist()
    end)

    it("get rejects idx out of range (too high)", function()
        local slots = st.new(2, function(i) return {} end)
        local ok, err = pcall(function() slots:get(3) end)
        expect(ok).to.equal(false)
        expect(err:find("idx out of range")).to.exist()
    end)

    it("get rejects idx = 0", function()
        local slots = st.new(2, function(i) return {} end)
        local ok, err = pcall(function() slots:get(0) end)
        expect(ok).to.equal(false)
        expect(err:find("idx must be positive integer")).to.exist()
    end)

    it("get rejects non-integer idx", function()
        local slots = st.new(2, function(i) return {} end)
        local ok, err = pcall(function() slots:get(1.5) end)
        expect(ok).to.equal(false)
        expect(err:find("idx must be positive integer")).to.exist()
    end)

    it("set rejects non-table payload", function()
        local slots = st.new(2, function(i) return {} end)
        local ok, err = pcall(function() slots:set(1, "bad") end)
        expect(ok).to.equal(false)
        expect(err:find("payload must be table")).to.exist()
    end)

    it("set rejects idx out of range", function()
        local slots = st.new(2, function(i) return {} end)
        local ok, err = pcall(function() slots:set(3, {}) end)
        expect(ok).to.equal(false)
        expect(err:find("idx out of range")).to.exist()
    end)
end)

-- ─── Invariant ───────────────────────────────────────────────────────────────

describe("civic.slot_table — invariant", function()
    it("size is immutable after construction", function()
        local slots = st.new(5, function(i) return { i = i } end)
        expect(slots:size()).to.equal(5)
        slots:set(3, { replaced = true })
        expect(slots:size()).to.equal(5)
    end)

    it("get returns reference (mutations visible)", function()
        local slots = st.new(1, function() return { v = 1 } end)
        local p = slots:get(1)
        p.v = 999
        expect(slots:get(1).v).to.equal(999)
    end)

    it("iter count matches size", function()
        local slots = st.new(4, function(i) return {} end)
        local count = 0
        for _ in slots:iter() do count = count + 1 end
        expect(count).to.equal(4)
    end)

    it("new() produces independent instances", function()
        local s1 = st.new(1, function() return { x = 1 } end)
        local s2 = st.new(1, function() return { x = 2 } end)
        expect(s1:get(1).x).to.equal(1)
        expect(s2:get(1).x).to.equal(2)
    end)

    it("civic.slot_table is wired from civic/init.lua", function()
        expect(civic.slot_table).to.exist()
        expect(civic.slot_table.new).to.exist()
    end)

    it("civic.shape.slot_payload is exposed", function()
        expect(civic.shape.slot_payload).to.exist()
        expect(type(civic.shape.slot_payload)).to.equal("table")
    end)
end)
