--- crdt_doc.or_map — Observed-Remove Map (tag-level primitive)
---
--- Pure Lua implementation INSPIRED BY OR-Set / OR-Map (Shapiro et al. 2011
--- §3.3.5, Specification 15). State-based CRDT (CvRDT). Each add carries a
--- unique tag; remove tombstones the specific tag. Concurrent add(k,v) /
--- remove(k,old_tag) preserves the add (Observed-Remove semantics). merge is
--- set union of entries + set union of tombstones.
---
--- Scope vs paper §3.3.5
---   This module is a TAG-LEVEL primitive, not the element-level OR-Set of
---   Specification 15. The paper's `remove(e)` tombstones every observed
---   `(e, α)` tag for element `e` in one step; here `remove(tag)` tombstones
---   exactly one tag. Element-level remove must be performed by the caller
---   (enumerate `state.entries` for the target key, then call `remove` per
---   tag). The CvRDT merge invariants (commutative / associative / idempotent)
---   still hold at the tag-level granularity (Theorem 2.1).
---
--- CALLER CONTRACT (must hold for convergence):
---   1. Tag uniqueness — tag MUST be globally unique across all replicas.
---      Convention: `agent_id .. ":" .. counter` (e.g. "a:42"). Reusing a
---      tag across replicas with different (key, value) breaks convergence
---      (last-writer in the merge loop wins non-deterministically).
---   2. Add-before-remove — the caller observes a tag (sees it in `entries`)
---      before issuing `remove`. Removing an unknown tag is legal (idempotent
---      tombstone) but cannot retroactively cancel future adds reusing the
---      same tag — only contract (1) prevents that pathology.
---
--- Internal data type — not exposed at crdt_doc top level. Consumers should
--- use M.op / M.merge / M.doc instead.
---
--- Reference:
---   Shapiro, M., Preguiça, N., Baquero, C., Zawirski, M.
---   "A comprehensive study of Convergent and Commutative Replicated Data
---    Types." INRIA Research Report RR-7506, 2011, §3.3.5 + Theorem 2.1.

local M = {}

--- new() -> state
--- Create an empty OR-Map.
function M.new()
    return { entries = {}, tombstones = {} }
end

--- clone(state) -> new_state
--- Shallow clone: each entry table is freshly allocated, but `value` fields
--- are reference-shared with the source (Lua-table values are NOT deep-
--- copied). Caller MUST treat shared `value` references as immutable.
--- Sufficient for the substrate's typical workload (primitive / string
--- values, or caller-managed value lifetimes).
function M.clone(state)
    local out = { entries = {}, tombstones = {} }
    for tag, e in pairs(state.entries) do
        out.entries[tag] = { key = e.key, value = e.value, agent = e.agent }
    end
    for tag in pairs(state.tombstones) do
        out.tombstones[tag] = true
    end
    return out
end

--- add(state, tag, key, value, agent) -> state (mutated)
--- Append (key, value) under unique tag. agent recorded for provenance.
--- Caller MUST guarantee `tag` is globally unique (see module CALLER
--- CONTRACT). Tag uniqueness is NOT enforced here — duplicate tags from
--- different replicas resolve as last-write-in-merge, which is non-
--- deterministic across replicas and breaks convergence.
function M.add(state, tag, key, value, agent)
    if type(tag) ~= "string" or tag == "" then
        error("or_map.add: tag must be non-empty string", 2)
    end
    state.entries[tag] = { key = key, value = value, agent = agent }
    return state
end

--- remove(state, remove_tag) -> state (mutated)
--- Tombstone the specific tag. Idempotent — re-applying same remove is no-op.
--- TAG-LEVEL primitive: this does NOT remove all (key, value) entries for an
--- element as Shapiro 2011 Specification 15 `remove(e)` does. To remove all
--- live entries for a logical element, the caller MUST enumerate
--- `state.entries` for the target key and call `remove` for each observed
--- tag (caller responsibility — see module-level Scope note).
function M.remove(state, remove_tag)
    if type(remove_tag) ~= "string" or remove_tag == "" then
        error("or_map.remove: remove_tag must be non-empty string", 2)
    end
    state.tombstones[remove_tag] = true
    return state
end

--- merge(s1, s2) -> new_state
--- Pure merge: union of entries + union of tombstones. Commutative,
--- associative, idempotent by construction (Shapiro 2011 Theorem 2.1).
---
--- SHALLOW MERGE: entry tables (`{ key, value, agent }`) in the result are
--- the same Lua references as in `s1` / `s2`. Callers MUST NOT mutate entry
--- fields in place after merge (treat entries as immutable) — direct
--- mutation aliases back into the source states. This convention is
--- consistent with the rest of the substrate (snapshot / clone / set are
--- the supported mutation paths).
function M.merge(s1, s2)
    local out = { entries = {}, tombstones = {} }
    for tag, e in pairs(s1.entries) do out.entries[tag] = e end
    for tag, e in pairs(s2.entries) do out.entries[tag] = e end
    for tag in pairs(s1.tombstones) do out.tombstones[tag] = true end
    for tag in pairs(s2.tombstones) do out.tombstones[tag] = true end
    return out
end

--- snapshot(state) -> { [key] = { value1, value2, ... } }
--- Collapse: per key, list of all live (non-tombstoned) values. Order is not
--- guaranteed across calls (set semantics). Empty key means all values for
--- that key were removed.
function M.snapshot(state)
    local result = {}
    for tag, entry in pairs(state.entries) do
        if not state.tombstones[tag] then
            local k = entry.key
            if not result[k] then result[k] = {} end
            result[k][#result[k] + 1] = entry.value
        end
    end
    return result
end

--- size(state) -> number
--- Count of live entries (post-tombstone). Used by doc.delta for quiescence
--- detection.
function M.size(state)
    local n = 0
    for tag in pairs(state.entries) do
        if not state.tombstones[tag] then n = n + 1 end
    end
    return n
end

return M
