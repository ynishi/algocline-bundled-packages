--- crdt_doc.lww — Last-Writer-Wins Register
---
--- Pure Lua implementation of LWW-Register (Shapiro et al. 2011 §3.4.1).
--- State-based CRDT (CvRDT). Per key, the entry with the highest (lamport,
--- agent) timestamp wins; agent string serves as deterministic tiebreaker
--- when lamport timestamps collide.
---
--- Internal data type — not exposed at crdt_doc top level. Consumers should
--- use M.op / M.merge / M.doc instead.
---
--- Reference:
---   Shapiro, M., Preguiça, N., Baquero, C., Zawirski, M.
---   "A comprehensive study of Convergent and Commutative Replicated Data
---    Types." INRIA Research Report RR-7506, 2011, §3.4.1.

local M = {}

--- new() -> state
--- Create an empty LWW-Register store.
function M.new()
    return { registers = {} }
end

--- _gt(l1, a1, l2, a2) -> boolean
--- (lamport, agent) > comparator. Lamport higher wins; agent lex tiebreak.
local function _gt(l1, a1, l2, a2)
    if l1 ~= l2 then return l1 > l2 end
    return tostring(a1) > tostring(a2)
end

--- set(state, key, value, lamport, agent) -> state (mutated)
--- Insert / overwrite the register for key when (lamport, agent) wins.
--- Idempotent: re-applying the same op yields identical state.
function M.set(state, key, value, lamport, agent)
    if type(lamport) ~= "number" then
        error("lww.set: lamport must be a number", 2)
    end
    local cur = state.registers[key]
    if not cur or _gt(lamport, agent, cur.lamport, cur.agent) then
        state.registers[key] = {
            value   = value,
            lamport = lamport,
            agent   = agent,
        }
    end
    return state
end

--- merge(s1, s2) -> new_state
--- Per-key max by (lamport, agent). Commutative / associative / idempotent
--- by construction (Shapiro 2011 §3.4.1).
function M.merge(s1, s2)
    local out = { registers = {} }
    for k, v in pairs(s1.registers) do out.registers[k] = v end
    for k, v in pairs(s2.registers) do
        local cur = out.registers[k]
        if not cur or _gt(v.lamport, v.agent, cur.lamport, cur.agent) then
            out.registers[k] = v
        end
    end
    return out
end

--- snapshot(state) -> { [key] = value }
--- Project to flat key → value (no metadata).
function M.snapshot(state)
    local result = {}
    for k, v in pairs(state.registers) do
        result[k] = v.value
    end
    return result
end

--- size(state) -> number
--- Count of populated registers. Used by doc.delta for quiescence detection.
function M.size(state)
    local n = 0
    for _ in pairs(state.registers) do n = n + 1 end
    return n
end

return M
