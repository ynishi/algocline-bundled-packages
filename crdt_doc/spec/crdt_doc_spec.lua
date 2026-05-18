--- Tests for crdt_doc — CRDT-backed shared document substrate.
--- Pure computation — no LLM mocking needed (substrate is LLM-free).
---
--- Coverage:
---   1. or_map / lww unit tests (add / remove / set / merge / snapshot)
---   2. doc API (new / snapshot / clone / delta)
---   3. op factory + validator
---   4. merge invariants (commutative / associative / idempotent) — Shapiro
---      2011 Theorem 2.1, exercised across both CRDT types
---   5. error paths (boundary validation)
---   6. integration example: multi-agent op accumulation without LLM,
---      demonstrating substrate composability for external collaboration
---      Frame use cases

local describe, it, expect = lust.describe, lust.it, lust.expect

-- Per README §"Adding a new test file" and abm/spec/abm_spec.lua:7-10:
-- `package.path` is set by the MCP harness via `search_paths=[REPO]`. Do NOT
-- prepend os.getenv("PWD") here — in worktree context PWD points at the
-- parent repo, which silently shadows the worktree's code and produces
-- false-green pass reports (2026-04-19 silent-drop accident, see CLAUDE.md).

local crdt   = require("crdt_doc")
local or_map = require("crdt_doc.or_map")
local lww    = require("crdt_doc.lww")

-- ── helpers ──────────────────────────────────────────────────────────

local function or_map_state(...)
    local s = or_map.new()
    for _, op in ipairs({ ... }) do
        if op.kind == "add" then
            or_map.add(s, op.tag, op.key, op.value, op.agent or "x")
        elseif op.kind == "remove" then
            or_map.remove(s, op.tag)
        end
    end
    return s
end

local function tally(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

-- A snapshot equality predicate that ignores list ordering for OR-Map keys.
local function or_map_eq(a, b)
    if tally(a) ~= tally(b) then return false end
    for k, list_a in pairs(a) do
        local list_b = b[k]
        if not list_b or #list_a ~= #list_b then return false end
        local seen = {}
        for _, v in ipairs(list_a) do seen[v] = (seen[v] or 0) + 1 end
        for _, v in ipairs(list_b) do seen[v] = (seen[v] or 0) - 1 end
        for _, n in pairs(seen) do
            if n ~= 0 then return false end
        end
    end
    return true
end

-- ═══════════════════════════════════════════════════════════════════
-- or_map (Shapiro 2011 §3.3.5)
-- ═══════════════════════════════════════════════════════════════════

describe("or_map", function()
    it("add stores entry under tag", function()
        local s = or_map.new()
        or_map.add(s, "a:1", "themes", "rugged", "a")
        expect(s.entries["a:1"].value).to.equal("rugged")
        expect(s.entries["a:1"].agent).to.equal("a")
    end)

    it("remove tombstones tag", function()
        local s = or_map_state(
            { kind = "add", tag = "a:1", key = "k", value = "v" },
            { kind = "remove", tag = "a:1" }
        )
        expect(s.tombstones["a:1"]).to.equal(true)
    end)

    it("snapshot lists live values per key", function()
        local s = or_map_state(
            { kind = "add", tag = "a:1", key = "themes", value = "rugged" },
            { kind = "add", tag = "b:1", key = "themes", value = "minimal" },
            { kind = "add", tag = "a:2", key = "voice",  value = "calm"   }
        )
        local snap = or_map.snapshot(s)
        expect(or_map_eq(snap, { themes = { "rugged", "minimal" }, voice = { "calm" } })).to.equal(true)
    end)

    it("snapshot omits tombstoned entries", function()
        local s = or_map_state(
            { kind = "add", tag = "a:1", key = "themes", value = "rugged" },
            { kind = "add", tag = "b:1", key = "themes", value = "minimal" },
            { kind = "remove", tag = "a:1" }
        )
        local snap = or_map.snapshot(s)
        expect(or_map_eq(snap, { themes = { "minimal" } })).to.equal(true)
    end)

    it("merge unions entries and tombstones", function()
        local s1 = or_map_state(
            { kind = "add", tag = "a:1", key = "k", value = "v1" }
        )
        local s2 = or_map_state(
            { kind = "add", tag = "b:1", key = "k", value = "v2" },
            { kind = "remove", tag = "a:1" }
        )
        local m = or_map.merge(s1, s2)
        expect(m.entries["a:1"].value).to.equal("v1")
        expect(m.entries["b:1"].value).to.equal("v2")
        expect(m.tombstones["a:1"]).to.equal(true)
        local snap = or_map.snapshot(m)
        expect(or_map_eq(snap, { k = { "v2" } })).to.equal(true)
    end)

    it("merge is commutative", function()
        local s1 = or_map_state({ kind = "add", tag = "a:1", key = "k", value = "v1" })
        local s2 = or_map_state({ kind = "add", tag = "b:1", key = "k", value = "v2" })
        local m12 = or_map.snapshot(or_map.merge(s1, s2))
        local m21 = or_map.snapshot(or_map.merge(s2, s1))
        expect(or_map_eq(m12, m21)).to.equal(true)
    end)

    it("merge is associative", function()
        local s1 = or_map_state({ kind = "add", tag = "a:1", key = "k", value = "v1" })
        local s2 = or_map_state({ kind = "add", tag = "b:1", key = "k", value = "v2" })
        local s3 = or_map_state({ kind = "add", tag = "c:1", key = "k", value = "v3" })
        local left  = or_map.snapshot(or_map.merge(or_map.merge(s1, s2), s3))
        local right = or_map.snapshot(or_map.merge(s1, or_map.merge(s2, s3)))
        expect(or_map_eq(left, right)).to.equal(true)
    end)

    it("merge is idempotent", function()
        local s = or_map_state({ kind = "add", tag = "a:1", key = "k", value = "v" })
        local once  = or_map.snapshot(or_map.merge(s, s))
        local twice = or_map.snapshot(or_map.merge(or_map.merge(s, s), s))
        expect(or_map_eq(once, or_map.snapshot(s))).to.equal(true)
        expect(or_map_eq(twice, once)).to.equal(true)
    end)

    it("size counts live entries only", function()
        local s = or_map_state(
            { kind = "add", tag = "a:1", key = "k1", value = "v1" },
            { kind = "add", tag = "a:2", key = "k2", value = "v2" },
            { kind = "remove", tag = "a:1" }
        )
        expect(or_map.size(s)).to.equal(1)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- lww (Shapiro 2011 §3.4.1)
-- ═══════════════════════════════════════════════════════════════════

describe("lww", function()
    it("set stores value with timestamp", function()
        local s = lww.new()
        lww.set(s, "title", "draft", 1, "a")
        expect(s.registers.title.value).to.equal("draft")
        expect(s.registers.title.lamport).to.equal(1)
    end)

    it("higher lamport wins", function()
        local s = lww.new()
        lww.set(s, "title", "draft", 1, "a")
        lww.set(s, "title", "final", 7, "b")
        expect(s.registers.title.value).to.equal("final")
    end)

    it("lower lamport ignored", function()
        local s = lww.new()
        lww.set(s, "title", "final", 7, "b")
        lww.set(s, "title", "draft", 1, "a")
        expect(s.registers.title.value).to.equal("final")
    end)

    it("agent string lex tiebreak on equal lamport", function()
        local s = lww.new()
        lww.set(s, "k", "v_a", 5, "agent_a")
        lww.set(s, "k", "v_b", 5, "agent_b")
        -- "agent_b" > "agent_a" in lex order, so v_b wins
        expect(s.registers.k.value).to.equal("v_b")
    end)

    it("merge takes per-key max", function()
        local s1 = lww.new(); lww.set(s1, "a", "v1", 3, "x")
        local s2 = lww.new(); lww.set(s2, "a", "v2", 5, "y"); lww.set(s2, "b", "vb", 1, "z")
        local m  = lww.merge(s1, s2)
        expect(m.registers.a.value).to.equal("v2")
        expect(m.registers.b.value).to.equal("vb")
    end)

    it("merge is commutative", function()
        local s1 = lww.new(); lww.set(s1, "k", "v1", 3, "a")
        local s2 = lww.new(); lww.set(s2, "k", "v2", 5, "b")
        local m12 = lww.snapshot(lww.merge(s1, s2))
        local m21 = lww.snapshot(lww.merge(s2, s1))
        expect(m12.k).to.equal(m21.k)
        expect(m12.k).to.equal("v2")
    end)

    it("merge is associative", function()
        local s1 = lww.new(); lww.set(s1, "k", "v1", 3, "a")
        local s2 = lww.new(); lww.set(s2, "k", "v2", 5, "b")
        local s3 = lww.new(); lww.set(s3, "k", "v3", 7, "c")
        local left  = lww.snapshot(lww.merge(lww.merge(s1, s2), s3))
        local right = lww.snapshot(lww.merge(s1, lww.merge(s2, s3)))
        expect(left.k).to.equal(right.k)
        expect(left.k).to.equal("v3")
    end)

    it("merge is idempotent", function()
        local s = lww.new(); lww.set(s, "k", "v", 5, "a")
        local once = lww.snapshot(lww.merge(s, s))
        expect(once.k).to.equal("v")
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- crdt_doc.doc (lifecycle)
-- ═══════════════════════════════════════════════════════════════════

describe("doc", function()
    it("new requires non-empty id", function()
        local ok = pcall(crdt.doc.new, {})
        expect(ok).to.equal(false)
        local ok2 = pcall(crdt.doc.new, { id = "" })
        expect(ok2).to.equal(false)
    end)

    it("new returns doc with empty sub-states", function()
        local d = crdt.doc.new({ id = "canvas-1" })
        expect(d.id).to.equal("canvas-1")
        expect(tally(d.or_map.entries)).to.equal(0)
        expect(tally(d.lww.registers)).to.equal(0)
    end)

    it("snapshot projects both sub-states", function()
        local d = crdt.doc.new({ id = "canvas-1" })
        crdt.merge(d, crdt.op.set_add("a", "themes", "rugged", "a:1"))
        crdt.merge(d, crdt.op.lww_set("a", "title", "draft", 1))
        local snap = crdt.doc.snapshot(d)
        expect(snap.or_map.themes[1]).to.equal("rugged")
        expect(snap.lww.title).to.equal("draft")
    end)

    it("clone produces independent state", function()
        local d = crdt.doc.new({ id = "canvas-1" })
        crdt.merge(d, crdt.op.set_add("a", "k", "v1", "a:1"))
        local d2 = crdt.doc.clone(d)
        crdt.merge(d, crdt.op.set_add("a", "k", "v_only_in_d", "a:2"))
        expect(or_map.size(d.or_map)).to.equal(2)
        expect(or_map.size(d2.or_map)).to.equal(1)
    end)

    it("delta returns 0 for identical doc", function()
        local d = crdt.doc.new({ id = "x" })
        crdt.merge(d, crdt.op.set_add("a", "k", "v", "a:1"))
        local d2 = crdt.doc.clone(d)
        expect(crdt.doc.delta(d, d2)).to.equal(0)
    end)

    it("delta increases when ops applied", function()
        local d = crdt.doc.new({ id = "x" })
        local prev = crdt.doc.clone(d)
        crdt.merge(d, crdt.op.set_add("a", "k", "v", "a:1"))
        crdt.merge(d, crdt.op.lww_set("a", "title", "v", 1))
        expect(crdt.doc.delta(d, prev)).to.equal(2)
    end)

    it("op_count starts at 0 and bumps on every merge", function()
        local d = crdt.doc.new({ id = "x" })
        expect(d.op_count).to.equal(0)
        crdt.merge(d, crdt.op.set_add("a", "k", "v", "a:1"))
        expect(d.op_count).to.equal(1)
        -- LWW write that loses the tiebreak still counts as a merged op
        -- (op_diff must catch it for true quiescence).
        crdt.merge(d, crdt.op.lww_set("a", "title", "final", 7))
        crdt.merge(d, crdt.op.lww_set("b", "title", "draft", 1))  -- loses
        expect(d.op_count).to.equal(3)
    end)

    it("op_diff detects size-stable mutations that delta misses", function()
        -- Reproduces the false-positive quiescence path called out in the
        -- M.doc.delta docstring: add tag b:1 + remove tag a:1 keeps the
        -- live count at 1 (delta == 0) but op_diff > 0.
        local d = crdt.doc.new({ id = "x" })
        crdt.merge(d, crdt.op.set_add("a", "k", "v_a", "a:1"))
        local prev = crdt.doc.clone(d)
        crdt.merge(d, crdt.op.set_add("b", "k", "v_b", "b:1"))
        crdt.merge(d, crdt.op.set_remove("c", "a:1"))
        expect(crdt.doc.delta(d, prev)).to.equal(0)   -- size proxy fooled
        expect(crdt.doc.op_diff(d, prev)).to.equal(2) -- truth
    end)

    it("clone preserves op_count for use as quiescence baseline", function()
        local d = crdt.doc.new({ id = "x" })
        crdt.merge(d, crdt.op.set_add("a", "k", "v", "a:1"))
        local snap = crdt.doc.clone(d)
        expect(snap.op_count).to.equal(1)
        -- A no-op round (same op replayed): op_count still bumps.
        crdt.merge(d, crdt.op.set_add("a", "k", "v", "a:1"))
        expect(crdt.doc.op_diff(d, snap)).to.equal(1)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- crdt_doc.op (factory + validator)
-- ═══════════════════════════════════════════════════════════════════

describe("op", function()
    it("set_add factory produces well-formed op", function()
        local op = crdt.op.set_add("a", "k", "v", "a:1")
        local ok = crdt.op.is_valid(op)
        expect(ok).to.equal(true)
    end)

    it("is_valid rejects non-table", function()
        local ok, reason = crdt.op.is_valid("oops")
        expect(ok).to.equal(false)
        expect(type(reason)).to.equal("string")
    end)

    it("is_valid rejects missing agent", function()
        local op = crdt.op.set_add("a", "k", "v", "a:1")
        op.agent = nil
        local ok, reason = crdt.op.is_valid(op)
        expect(ok).to.equal(false)
        expect(reason:match("agent")).to_not.equal(nil)
    end)

    it("is_valid rejects unknown kind", function()
        local op = { kind = "bogus", agent = "a" }
        local ok, reason = crdt.op.is_valid(op)
        expect(ok).to.equal(false)
        expect(reason:match("unknown")).to_not.equal(nil)
    end)

    it("is_valid rejects set_add without tag", function()
        local op = { kind = "set_add", agent = "a", key = "k", value = "v" }
        local ok = crdt.op.is_valid(op)
        expect(ok).to.equal(false)
    end)

    it("is_valid rejects lww_set without lamport", function()
        local op = { kind = "lww_set", agent = "a", key = "k", value = "v" }
        local ok = crdt.op.is_valid(op)
        expect(ok).to.equal(false)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- merge / merge_docs (top-level)
-- ═══════════════════════════════════════════════════════════════════

describe("merge", function()
    it("rejects invalid op at boundary", function()
        local d = crdt.doc.new({ id = "x" })
        local ok = pcall(crdt.merge, d, { kind = "bogus", agent = "a" })
        expect(ok).to.equal(false)
    end)

    it("merge_docs combines disjoint sub-states", function()
        local d1 = crdt.doc.new({ id = "x" })
        crdt.merge(d1, crdt.op.set_add("a", "k", "v_a", "a:1"))
        local d2 = crdt.doc.new({ id = "x" })
        crdt.merge(d2, crdt.op.set_add("b", "k", "v_b", "b:1"))
        local m = crdt.merge_docs(d1, d2)
        local snap = crdt.doc.snapshot(m)
        expect(or_map_eq(snap.or_map, { k = { "v_a", "v_b" } })).to.equal(true)
    end)

    it("merge_docs is commutative on doc level", function()
        local d1 = crdt.doc.new({ id = "x" })
        crdt.merge(d1, crdt.op.lww_set("a", "title", "draft", 3))
        local d2 = crdt.doc.new({ id = "x" })
        crdt.merge(d2, crdt.op.lww_set("b", "title", "final", 7))
        local m12 = crdt.doc.snapshot(crdt.merge_docs(d1, d2))
        local m21 = crdt.doc.snapshot(crdt.merge_docs(d2, d1))
        expect(m12.lww.title).to.equal(m21.lww.title)
        expect(m12.lww.title).to.equal("final")
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Integration example (no LLM): 3-agent op accumulation
-- demonstrates how an external collaboration Frame would compose this
-- substrate with N peers concurrently editing a shared canvas.
-- ═══════════════════════════════════════════════════════════════════

describe("integration: 3-agent canvas accumulation", function()
    it("converges regardless of arrival order", function()
        -- Simulate 3 agents producing ops independently.
        local ops_per_agent = {
            ["a"] = {
                crdt.op.lww_set("a", "title",  "rugged-draft",   1),
                crdt.op.set_add("a", "themes", "rugged",         "a:t1"),
            },
            ["b"] = {
                crdt.op.lww_set("b", "title",  "minimal-final",  7),
                crdt.op.set_add("b", "themes", "minimal",        "b:t1"),
            },
            ["c"] = {
                crdt.op.set_add("c", "themes", "playful",        "c:t1"),
                crdt.op.set_remove("c", "a:t1"),  -- c removes a's "rugged"
            },
        }

        -- Order 1: a → b → c
        local d1 = crdt.doc.new({ id = "canvas" })
        for _, agent in ipairs({ "a", "b", "c" }) do
            for _, op in ipairs(ops_per_agent[agent]) do
                crdt.merge(d1, op)
            end
        end

        -- Order 2: c → b → a (interleaved)
        local d2 = crdt.doc.new({ id = "canvas" })
        for _, agent in ipairs({ "c", "b", "a" }) do
            for _, op in ipairs(ops_per_agent[agent]) do
                crdt.merge(d2, op)
            end
        end

        -- Order 3: interleaved a/b/c by op index
        local d3 = crdt.doc.new({ id = "canvas" })
        for i = 1, 2 do
            for _, agent in ipairs({ "a", "b", "c" }) do
                crdt.merge(d3, ops_per_agent[agent][i])
            end
        end

        -- All three orderings converge to the same snapshot (CRDT property).
        local s1 = crdt.doc.snapshot(d1)
        local s2 = crdt.doc.snapshot(d2)
        local s3 = crdt.doc.snapshot(d3)

        expect(s1.lww.title).to.equal("minimal-final")
        expect(s2.lww.title).to.equal("minimal-final")
        expect(s3.lww.title).to.equal("minimal-final")

        expect(or_map_eq(s1.or_map, s2.or_map)).to.equal(true)
        expect(or_map_eq(s1.or_map, s3.or_map)).to.equal(true)

        -- "rugged" was removed by c, so only minimal and playful remain.
        expect(or_map_eq(s1.or_map, { themes = { "minimal", "playful" } })).to.equal(true)
    end)

    it("supports quiescence-based termination", function()
        -- External collaboration Frame uses crdt.doc.delta to detect
        -- quiescence: when delta == 0 across N rounds, terminate.
        local d = crdt.doc.new({ id = "canvas" })
        local prev = crdt.doc.clone(d)

        crdt.merge(d, crdt.op.set_add("a", "k", "v1", "a:1"))
        expect(crdt.doc.delta(d, prev)).to.equal(1)

        prev = crdt.doc.clone(d)
        -- "no-op" round: agent re-applies same op (idempotent)
        crdt.merge(d, crdt.op.set_add("a", "k", "v1", "a:1"))
        expect(crdt.doc.delta(d, prev)).to.equal(0)

        prev = crdt.doc.clone(d)
        -- LWW set with lower lamport — also idempotent (loser ignored)
        crdt.merge(d, crdt.op.lww_set("a", "title", "draft", 1))
        crdt.merge(d, crdt.op.lww_set("b", "title", "final", 7))
        prev = crdt.doc.clone(d)
        crdt.merge(d, crdt.op.lww_set("a", "title", "earlier", 2))  -- ignored
        expect(crdt.doc.delta(d, prev)).to.equal(0)
    end)
end)
