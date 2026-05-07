--- crdt_doc — CRDT-backed shared document substrate
---
--- Frame role substrate (no M.run, no LLM). Provides Doc + Op + Merge
--- primitives that external collaboration Frames can compose to build
--- multi-agent shared state with mathematical conflict-free merge
--- (commutative / associative / idempotent).
---
--- Initial lineup (Shapiro et al. 2011):
---   - OR-Map (Observed-Remove Map, §3.3.5)
---   - LWW-Register (Last-Writer-Wins Register, §3.4.1)
---
--- Sub-modules exposed at top level:
---   M.doc       — document lifecycle (new / snapshot / clone / delta)
---   M.op        — op factory + validator
---   M.merge     — apply single op to a doc (in-place)
---   M.merge_docs — merge two docs into a new doc
---
--- Usage (substrate-only, no LLM):
---   local crdt = require("crdt_doc")
---
---   local doc = crdt.doc.new({ id = "canvas-1" })
---   crdt.merge(doc, crdt.op.set_add("a", "themes", "rugged", "a:1"))
---   crdt.merge(doc, crdt.op.set_add("b", "themes", "minimal", "b:1"))
---   crdt.merge(doc, crdt.op.lww_set("a", "title", "draft", 1))
---   crdt.merge(doc, crdt.op.lww_set("b", "title", "final", 7))
---
---   local snap = crdt.doc.snapshot(doc)
---   -- snap.or_map.themes == { "rugged", "minimal" } (order set-like)
---   -- snap.lww.title == "final"
---
--- Design references:
---   - crdt_doc/doc/README.md — substrate design + API contract
---   - workspace/tasks/1778142792-58580-package-crdt/plan.md
---   - Shapiro et al. 2011, INRIA RR-7506

local or_map = require("crdt_doc.or_map")
local lww    = require("crdt_doc.lww")

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name        = "crdt_doc",
    version     = "0.1.0",
    description = "CRDT-backed shared document substrate — OR-Map + "
        .. "LWW-Register primitives with mathematical conflict-free merge "
        .. "(commutative / associative / idempotent). Frame role: no M.run, "
        .. "no LLM. External collaboration Frames compose this substrate "
        .. "to build multi-agent shared state. Based on Shapiro et al. "
        .. "(INRIA RR-7506, 2011).",
    category    = "collaboration",
}

-- ── Op shape (declarative, kind-tagged) ──

local op_shape = T.shape({
    kind       = T.one_of({ "set_add", "set_remove", "lww_set" })
        :describe("Op kind — declares merge semantics"),
    agent      = T.string:describe("Agent identifier (provenance + LWW tiebreak)"),
    key        = T.string:is_optional()
        :describe("Map key (set_add / lww_set only)"),
    value      = T.any:is_optional()
        :describe("Value to add / set (set_add / lww_set only)"),
    tag        = T.string:is_optional()
        :describe("Unique add tag (set_add only); reused on set_remove via remove_tag"),
    remove_tag = T.string:is_optional()
        :describe("Tag to tombstone (set_remove only)"),
    lamport    = T.number:is_optional()
        :describe("Lamport timestamp (lww_set only)"),
}, { open = false })

local doc_shape = T.shape({
    id     = T.string:describe("Document identifier (caller-supplied)"),
    or_map = T.table:describe("OR-Map sub-state (entries + tombstones)"),
    lww    = T.table:describe("LWW-Register sub-state (registers)"),
}, { open = true })

---@type AlcSpec
M.spec = {
    entries = {
        merge = {
            args   = { doc_shape, op_shape },
            result = doc_shape,
        },
        merge_docs = {
            args   = { doc_shape, doc_shape },
            result = doc_shape,
        },
    },
}

-- ── Doc sub-module ──

M.doc = {}

--- M.doc.new(opts) -> doc
--- opts.id (required): caller-supplied identifier (used by caller for
---   alc.state persistence keying or for distinguishing logical streams).
function M.doc.new(opts)
    opts = opts or {}
    if type(opts.id) ~= "string" or opts.id == "" then
        error("crdt_doc.doc.new: opts.id must be non-empty string", 2)
    end
    return {
        id     = opts.id,
        or_map = or_map.new(),
        lww    = lww.new(),
    }
end

--- M.doc.snapshot(doc) -> { or_map = {key→[values]}, lww = {key→value} }
--- Project the doc to plain Lua tables. Pure — does not mutate doc.
function M.doc.snapshot(doc)
    return {
        or_map = or_map.snapshot(doc.or_map),
        lww    = lww.snapshot(doc.lww),
    }
end

--- M.doc.clone(doc) -> new_doc
--- Deep clone the CRDT sub-states. Useful for caller-side undo / branching.
function M.doc.clone(doc)
    local cloned_or_map = { entries = {}, tombstones = {} }
    for tag, e in pairs(doc.or_map.entries) do
        cloned_or_map.entries[tag] = {
            key = e.key, value = e.value, agent = e.agent,
        }
    end
    for tag in pairs(doc.or_map.tombstones) do
        cloned_or_map.tombstones[tag] = true
    end
    local cloned_lww = { registers = {} }
    for k, v in pairs(doc.lww.registers) do
        cloned_lww.registers[k] = {
            value = v.value, lamport = v.lamport, agent = v.agent,
        }
    end
    return { id = doc.id, or_map = cloned_or_map, lww = cloned_lww }
end

--- M.doc.delta(doc, prev) -> integer
--- Returns the absolute size delta between two doc snapshots (sum over both
--- sub-states). 0 means quiescent (no live entry / register count change).
--- Used by external orchestrators for max_rounds + quiescence termination.
function M.doc.delta(doc, prev)
    local d_or = math.abs(or_map.size(doc.or_map) - or_map.size(prev.or_map))
    local d_lww = math.abs(lww.size(doc.lww) - lww.size(prev.lww))
    return d_or + d_lww
end

-- ── Op sub-module (factory + validator) ──

M.op = {}

--- M.op.set_add(agent, key, value, tag) -> op
function M.op.set_add(agent, key, value, tag)
    return {
        kind  = "set_add",
        agent = agent,
        key   = key,
        value = value,
        tag   = tag,
    }
end

--- M.op.set_remove(agent, remove_tag) -> op
function M.op.set_remove(agent, remove_tag)
    return {
        kind       = "set_remove",
        agent      = agent,
        remove_tag = remove_tag,
    }
end

--- M.op.lww_set(agent, key, value, lamport) -> op
function M.op.lww_set(agent, key, value, lamport)
    return {
        kind    = "lww_set",
        agent   = agent,
        key     = key,
        value   = value,
        lamport = lamport,
    }
end

--- M.op.is_valid(op) -> ok, reason
--- Declarative validation. Rejects unknown kinds, missing agent, and
--- per-kind required-field violations.
function M.op.is_valid(op)
    if type(op) ~= "table" then
        return false, "op must be table"
    end
    if type(op.agent) ~= "string" or op.agent == "" then
        return false, "op.agent must be non-empty string"
    end
    if op.kind == "set_add" then
        if type(op.key) ~= "string" or op.key == "" then
            return false, "set_add: op.key must be non-empty string"
        end
        if op.value == nil then
            return false, "set_add: op.value required"
        end
        if type(op.tag) ~= "string" or op.tag == "" then
            return false, "set_add: op.tag must be non-empty string"
        end
        return true
    elseif op.kind == "set_remove" then
        if type(op.remove_tag) ~= "string" or op.remove_tag == "" then
            return false, "set_remove: op.remove_tag must be non-empty string"
        end
        return true
    elseif op.kind == "lww_set" then
        if type(op.key) ~= "string" or op.key == "" then
            return false, "lww_set: op.key must be non-empty string"
        end
        if op.value == nil then
            return false, "lww_set: op.value required"
        end
        if type(op.lamport) ~= "number" then
            return false, "lww_set: op.lamport must be a number"
        end
        return true
    else
        return false, "unknown op.kind: " .. tostring(op.kind)
    end
end

-- ── Merge: apply op to doc (in-place) ──

local KIND_DISPATCH = {
    set_add = function(doc, op)
        or_map.add(doc.or_map, op.tag, op.key, op.value, op.agent)
    end,
    set_remove = function(doc, op)
        or_map.remove(doc.or_map, op.remove_tag)
    end,
    lww_set = function(doc, op)
        lww.set(doc.lww, op.key, op.value, op.lamport, op.agent)
    end,
}

--- M.merge(doc, op) -> doc (mutated)
--- Apply one op to the doc in-place, dispatching by kind. Validates the op
--- via M.op.is_valid first; raises on invalid input (boundary check).
function M.merge(doc, op)
    local ok, reason = M.op.is_valid(op)
    if not ok then
        error("crdt_doc.merge: invalid op — " .. reason, 2)
    end
    local handler = KIND_DISPATCH[op.kind]
    handler(doc, op)
    return doc
end

--- M.merge_docs(d1, d2) -> new_doc
--- Pure CRDT merge of two docs. d1.id wins as the merged doc's id.
function M.merge_docs(d1, d2)
    return {
        id     = d1.id,
        or_map = or_map.merge(d1.or_map, d2.or_map),
        lww    = lww.merge(d1.lww, d2.lww),
    }
end

-- Producer self-decoration: assert M.spec on each call when ALC_SHAPE_CHECK=1.
M.merge      = S.instrument(M, "merge")
M.merge_docs = S.instrument(M, "merge_docs")

return M
