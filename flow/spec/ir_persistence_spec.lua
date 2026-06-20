--- Tests for the Persistence API (Step 3 §3.2a).
---
--- Surface:
---   - flow.ir.to_json(node, opts?)   delegates to opts.alc.json_encode / _G.alc
---   - flow.ir.from_json(str, opts?)  delegates to opts.alc.json_decode / _G.alc
---
--- Phase 4 scope: injection seam contract + failure normalization.
--- The round-trip property (`from_json(to_json(n)) == n` across every
--- Node + Expr kind) is the §3.2b spec covered separately.

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

local ir = require("flow.ir")

-- ── trivial encode/decode mocks for seam testing ────────────────────
--
-- Real JSON impls live elsewhere (algocline core / pure_json). For the
-- seam contract we only need pairs that exercise success / nil-return
-- / raise paths — actual JSON shape is the §3.2b round-trip spec's
-- concern.

local function record_encode(tag)
    return function(value)
        return string.format("ENC<%s>:%s", tag, tostring(value))
    end
end

local function record_decode(tag)
    return function(json)
        return { _decoded_by = tag, _from = json }
    end
end

local function raise_decode(_) error("decoder kaboom", 0) end
local function nil_decode(_)   return nil end

-- ── opts.alc injection ──────────────────────────────────────────────

describe("flow.ir.to_json — opts.alc injection", function()
    it("uses opts.alc.json_encode when provided", function()
        local node = ir.step({ ref = "a", out = "ctx.a" })
        local got = ir.to_json(node, { alc = { json_encode = record_encode("X") } })
        expect(got:sub(1, 6)).to.equal("ENC<X>")
    end)

    it("errors when opts.alc.json_encode is missing", function()
        local prev_alc = _G.alc
        _G.alc = nil
        local ok, err = pcall(ir.to_json, ir.lit(1), { alc = {} })
        _G.alc = prev_alc
        expect(ok).to.equal(false)
        expect(tostring(err):find("alc.json_encode required")).to_not.equal(nil)
    end)

    it("propagates encoder raises", function()
        local node = ir.lit(1)
        local function blow(_) error("encoder kaboom", 0) end
        local ok, err = pcall(ir.to_json, node, { alc = { json_encode = blow } })
        expect(ok).to.equal(false)
        expect(tostring(err):find("encoder kaboom")).to_not.equal(nil)
    end)
end)

describe("flow.ir.from_json — opts.alc injection", function()
    it("uses opts.alc.json_decode when provided", function()
        local got = ir.from_json("anything",
            { alc = { json_decode = record_decode("Y") } })
        expect(got._decoded_by).to.equal("Y")
        expect(got._from).to.equal("anything")
    end)

    it("errors when opts.alc.json_decode is missing", function()
        local prev_alc = _G.alc
        _G.alc = nil
        local ok, err = pcall(ir.from_json, "{}", { alc = {} })
        _G.alc = prev_alc
        expect(ok).to.equal(false)
        expect(tostring(err):find("alc.json_decode required")).to_not.equal(nil)
    end)

    it("normalizes decoder raises into 'decode failed:'", function()
        local ok, err = pcall(ir.from_json, "{}", { alc = { json_decode = raise_decode } })
        expect(ok).to.equal(false)
        expect(tostring(err):find("flow%.ir%.from_json: decode failed:"))
            .to_not.equal(nil)
        expect(tostring(err):find("decoder kaboom")).to_not.equal(nil)
    end)

    it("normalizes nil-returning decoders into 'decode failed:'", function()
        local ok, err = pcall(ir.from_json, "{}", { alc = { json_decode = nil_decode } })
        expect(ok).to.equal(false)
        expect(tostring(err):find("flow%.ir%.from_json: decode failed:"))
            .to_not.equal(nil)
    end)
end)

-- ── _G.alc fall-through ─────────────────────────────────────────────

describe("flow.ir persistence — _G.alc fall-through", function()
    it("to_json falls through to _G.alc.json_encode when opts omitted", function()
        local prev_alc = _G.alc
        _G.alc = { json_encode = record_encode("G"), json_decode = record_decode("G") }
        local got = ir.to_json(ir.lit(1))
        _G.alc = prev_alc
        expect(got:sub(1, 6)).to.equal("ENC<G>")
    end)

    it("from_json falls through to _G.alc.json_decode when opts omitted", function()
        local prev_alc = _G.alc
        _G.alc = { json_encode = record_encode("G"), json_decode = record_decode("G") }
        local got = ir.from_json("payload")
        _G.alc = prev_alc
        expect(got._decoded_by).to.equal("G")
        expect(got._from).to.equal("payload")
    end)

    it("opts.alc overrides _G.alc when both present", function()
        local prev_alc = _G.alc
        _G.alc = { json_encode = record_encode("G") }
        local got = ir.to_json(ir.lit(1),
            { alc = { json_encode = record_encode("O") } })
        _G.alc = prev_alc
        expect(got:sub(1, 6)).to.equal("ENC<O>")
    end)

    it("errors when neither opts.alc nor _G.alc provides the fn", function()
        local prev_alc = _G.alc
        _G.alc = nil
        local ok, err = pcall(ir.to_json, ir.lit(1))
        _G.alc = prev_alc
        expect(ok).to.equal(false)
        expect(tostring(err):find("alc.json_encode required")).to_not.equal(nil)
    end)
end)
