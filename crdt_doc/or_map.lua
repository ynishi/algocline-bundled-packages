--- crdt_doc.or_map — Observed-Remove Map
---
--- Pure Lua implementation of OR-Set / OR-Map (Shapiro et al. 2011 §3.3.5).
--- State-based CRDT (CvRDT). Each add carries a unique tag; remove tombstones
--- the specific tag. Concurrent add(k,v) / remove(k,old_tag) preserves the add
--- (Observed-Remove semantics). merge is set union of entries + tombstones.
---
--- Internal data type — not exposed at crdt_doc top level. Consumers should
--- use M.op / M.merge / M.doc instead.
---
--- Reference:
---   Shapiro, M., Preguiça, N., Baquero, C., Zawirski, M.
---   "A comprehensive study of Convergent and Commutative Replicated Data
---    Types." INRIA Research Report RR-7506, 2011, §3.3.5.

local M = {}

--- new() -> state
--- Create an empty OR-Map.
function M.new()
    return { entries = {}, tombstones = {} }
end

--- add(state, tag, key, value, agent) -> state (mutated)
--- Append (key, value) under unique tag. agent recorded for provenance.
function M.add(state, tag, key, value, agent)
    if type(tag) ~= "string" or tag == "" then
        error("or_map.add: tag must be non-empty string", 2)
    end
    state.entries[tag] = { key = key, value = value, agent = agent }
    return state
end

--- remove(state, remove_tag) -> state (mutated)
--- Tombstone the specific tag. Idempotent — re-applying same remove is no-op.
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
