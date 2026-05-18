--- crdt_doc — CRDT-backed shared document substrate
---
--- Frame role substrate (no M.run, no LLM). Provides Doc + Op + Merge
--- primitives that external collaboration Frames can compose to build
--- multi-agent shared state with mathematical conflict-free merge
--- (commutative / associative / idempotent).
---
--- Initial lineup (Shapiro et al. 2011, INRIA RR-7506):
---   - OR-Map  — tag-level primitive INSPIRED BY §3.3.5 Specification 15
---     (NOTE: paper's `remove(e)` is element-level; this module exposes
---     tag-level remove only — see crdt_doc/or_map.lua module docstring
---     for scope vs paper)
---   - LWW-Register (Last-Writer-Wins Register, §3.4.1 Specification 9)
---
--- Sub-modules exposed at top level:
---   M.doc        — document lifecycle (new / snapshot / clone / delta /
---                  op_diff)
---   M.op         — op factory + validator
---   M.merge      — apply single op to a doc (in-place)
---   M.merge_docs — merge two docs into a new doc
---
--- ┌─ INJECTION POINTS ────────────────────────────────────────────────┐
--- │ The substrate is intentionally minimal. The following caller-side │
--- │ choices are required for the merge invariants to hold (see paper  │
--- │ Theorem 2.1) and are NOT enforced inside the module. Violations   │
--- │ degrade convergence silently; they do not raise errors.           │
--- │                                                                   │
--- │ REQUIRED                                                          │
--- │   tag generator (OR-Map)                                          │
--- │     Caller MUST emit a globally-unique tag per `set_add`. The     │
--- │     paper assumes a fresh α from an unbounded universe U          │
--- │     (Specification 15). Convention used in tests / examples:      │
--- │       tag = agent_id .. ":" .. local_counter                      │
--- │     Reusing a tag across replicas with different (key, value)     │
--- │     yields non-deterministic merge.                               │
--- │                                                                   │
--- │   lamport clock (LWW-Register)                                    │
--- │     Caller MUST inject a per-replica monotonically-increasing     │
--- │     lamport timestamp on every `lww_set`. The paper presumes a    │
--- │     newClock() at update time (Specification 9). Equal lamports   │
--- │     across replicas are resolved by agent-string lex tiebreak.    │
--- │                                                                   │
--- │   stable agent identity                                           │
--- │     `agent` MUST be stable per replica and unique across          │
--- │     replicas (used as LWW lex tiebreak + OR-Map provenance +      │
--- │     by-convention as tag prefix).                                 │
--- │                                                                   │
--- │ OPTIONAL paper-faithful (defaults match paper)                    │
--- │   tiebreak strategy (LWW-Register)                                │
--- │     Default: lexicographic comparison of `tostring(agent)`.       │
--- │     Shapiro §3.4.1 leaves the tiebreak abstract; this default is  │
--- │     pinned to make merges deterministic. Callers needing a        │
--- │     different rule (e.g. site-id ordering) can pre-process agent  │
--- │     strings before passing them to ops.                           │
--- │                                                                   │
--- │ OPTIONAL non-paper-faithful                                       │
--- │   element-level remove (OR-Map) — NOT paper-faithful when emulated│
--- │     The paper's `remove(e)` removes every observed `(e, α)` tag.  │
--- │     This module exposes `remove(tag)` only. Callers that want     │
--- │     element-level remove enumerate `doc.or_map.entries` for the   │
--- │     target key and emit one `set_remove` per observed tag. The    │
--- │     emulation is exact in the absence of concurrent adds, but in  │
--- │     the presence of a not-yet-observed concurrent add the         │
--- │     emulated remove behaves identically to the paper's            │
--- │     observed-remove (the new add survives, by construction).      │
--- │                                                                   │
--- │   true quiescence detection                                       │
--- │     `M.doc.delta` is a SIZE proxy (see its docstring). For real   │
--- │     quiescence-window termination use `M.doc.op_diff` (counts     │
--- │     every merged op via the monotonic `doc.op_count` field).      │
--- └───────────────────────────────────────────────────────────────────┘
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
    alc_shapes_compat = "^0.25",
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
    id        = T.string:describe("Document identifier (caller-supplied)"),
    or_map    = T.table:describe("OR-Map sub-state (entries + tombstones)"),
    lww       = T.table:describe("LWW-Register sub-state (registers)"),
    op_count  = T.number:is_optional()
        :describe("Total number of merged ops since doc.new (monotonic, used "
            .. "for true quiescence detection — size-stable mutations bump "
            .. "op_count but leave size unchanged)"),
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
        id       = opts.id,
        or_map   = or_map.new(),
        lww      = lww.new(),
        op_count = 0,
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
--- Shallow clone the CRDT sub-states (delegates to or_map.clone /
--- lww.clone). Sub-state container tables are fresh, but `value` fields
--- inside entries / registers are reference-shared with the source —
--- callers MUST treat values as immutable. Useful for caller-side undo /
--- branching when values are primitive / string. `op_count` is preserved
--- so the clone can serve as `prev` for `M.doc.op_diff`.
function M.doc.clone(doc)
    return {
        id       = doc.id,
        or_map   = or_map.clone(doc.or_map),
        lww      = lww.clone(doc.lww),
        op_count = doc.op_count or 0,
    }
end

--- M.doc.delta(doc, prev) -> integer
--- Returns the absolute SIZE delta between two doc snapshots (sum over both
--- sub-states). PROXY ONLY — this is *not* a faithful quiescence detector:
--- size-stable mutations (e.g. `add tag b:1` + `remove tag a:1` against the
--- same key, or an LWW write that loses the tiebreak) leave size unchanged
--- and report `delta == 0` despite real op activity. False-positive
--- quiescence is possible. For true quiescence, use `M.doc.op_diff(doc,
--- prev)` (counts every merged op including no-ops) or compare op_count
--- directly. `delta` is retained as a cheap "did the visible result grow
--- or shrink" hint for orchestrators that want a quick first-pass check.
function M.doc.delta(doc, prev)
    local d_or = math.abs(or_map.size(doc.or_map) - or_map.size(prev.or_map))
    local d_lww = math.abs(lww.size(doc.lww) - lww.size(prev.lww))
    return d_or + d_lww
end

--- M.doc.op_diff(doc, prev) -> integer
--- Returns the number of ops merged between two snapshots, derived from the
--- monotonic `op_count` field bumped on every `M.merge` call. This counts
--- every applied op including idempotent / no-op writes (e.g. an LWW set
--- that loses the tiebreak still increments). Use this — not `delta` — as
--- the basis for quiescence-window termination: caller observes
--- `op_diff == 0` across N consecutive rounds when no further ops are
--- being submitted. Tolerates the legacy doc shape (no `op_count`) by
--- falling back to 0.
function M.doc.op_diff(doc, prev)
    local cur = doc.op_count or 0
    local old = prev.op_count or 0
    return cur - old
end

-- ── Op sub-module (factory + validator) ──

M.op = {}

--- M.op.set_add(agent, key, value, tag) -> op
--- `tag` MUST be globally unique across all replicas (caller responsibility,
--- see CALLER CONTRACT in module docstring). Convention: `agent .. ":" ..
--- counter`. Reusing a tag breaks CvRDT convergence.
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
--- TAG-LEVEL primitive: tombstones exactly one tag. Element-level remove
--- (paper Specification 15 `remove(e)`) requires the caller to enumerate
--- live tags for the target key in `doc.or_map.entries` and emit one
--- `set_remove` per observed tag. See or_map module docstring.
function M.op.set_remove(agent, remove_tag)
    return {
        kind       = "set_remove",
        agent      = agent,
        remove_tag = remove_tag,
    }
end

--- M.op.lww_set(agent, key, value, lamport) -> op
--- `lamport` MUST be drawn from a per-replica monotonically-increasing
--- clock (caller responsibility, see CALLER CONTRACT). `agent` MUST be a
--- stable identifier for the originating replica — used as the lex
--- tiebreaker on equal lamport.
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
--- Bumps `doc.op_count` on every successful apply (including idempotent /
--- losing-tiebreak writes) so orchestrators can use `M.doc.op_diff` for
--- true quiescence detection.
function M.merge(doc, op)
    local ok, reason = M.op.is_valid(op)
    if not ok then
        error("crdt_doc.merge: invalid op — " .. reason, 2)
    end
    local handler = KIND_DISPATCH[op.kind]
    handler(doc, op)
    doc.op_count = (doc.op_count or 0) + 1
    return doc
end

--- M.merge_docs(d1, d2) -> new_doc
--- Pure CRDT merge of two docs. d1.id wins as the merged doc's id.
--- The merged op_count is the sum of both inputs (an upper bound on the
--- number of ops observed by the merged doc; idempotent overlap is not
--- deduplicated, matching the conservative quiescence semantics of
--- `op_diff`).
function M.merge_docs(d1, d2)
    return {
        id       = d1.id,
        or_map   = or_map.merge(d1.or_map, d2.or_map),
        lww      = lww.merge(d1.lww, d2.lww),
        op_count = (d1.op_count or 0) + (d2.op_count or 0),
    }
end

-- Producer self-decoration: assert M.spec on each call when ALC_SHAPE_CHECK=1.
M.merge      = S.instrument(M, "merge")
M.merge_docs = S.instrument(M, "merge_docs")

return M
