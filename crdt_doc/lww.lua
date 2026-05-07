--- crdt_doc.lww — Last-Writer-Wins Register
---
--- Pure Lua implementation of LWW-Register (Shapiro et al. 2011 §3.4.1,
--- Specification 9). State-based CRDT (CvRDT). Per key, the entry with the
--- highest (lamport, agent) tuple wins; agent string serves as deterministic
--- tiebreaker when lamport timestamps collide. The agent-string lex
--- tiebreak is one valid choice — Shapiro §3.4.1 leaves the tiebreak rule
--- abstract; this implementation pins it for convergence.
---
--- CALLER CONTRACT (must hold for convergence):
---   1. Lamport monotonicity — caller MUST inject a per-replica
---      monotonically-increasing clock. Within one replica, every successive
---      `set(state, k, v, lamport, agent)` call MUST receive a strictly
---      greater `lamport` than any previous call by the same replica.
---      Two writes from the same replica with the same lamport land on
---      undefined-order behaviour (first-write-wins on the strict `>`
---      compare); cross-replica equal lamports are resolved by agent lex.
---   2. Stable agent identity — `agent` MUST be stable for one logical
---      replica across calls. Different replicas MUST use different agent
---      strings; otherwise the lex tiebreaker collapses and convergence
---      degenerates to "first replica to merge wins".
---
--- Internal data type — not exposed at crdt_doc top level. Consumers should
--- use M.op / M.merge / M.doc instead.
---
--- Reference:
---   Shapiro, M., Preguiça, N., Baquero, C., Zawirski, M.
---   "A comprehensive study of Convergent and Commutative Replicated Data
---    Types." INRIA Research Report RR-7506, 2011, §3.4.1 + Theorem 2.1.

local M = {}

--- new() -> state
--- Create an empty LWW-Register store.
function M.new()
    return { registers = {} }
end

--- clone(state) -> new_state
--- Shallow clone: each register table is freshly allocated, but `value`
--- fields are reference-shared with the source. Caller MUST treat shared
--- `value` references as immutable.
function M.clone(state)
    local out = { registers = {} }
    for k, v in pairs(state.registers) do
        out.registers[k] = {
            value = v.value, lamport = v.lamport, agent = v.agent,
        }
    end
    return out
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
--- Caller MUST honour module-level CALLER CONTRACT (lamport monotonicity +
--- stable agent identity). Violations do not raise here — they manifest as
--- non-deterministic merge across replicas.
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
--- by construction (Shapiro 2011 §3.4.1 + Theorem 2.1).
---
--- SHALLOW MERGE: register tables are aliased back to `s1` / `s2`. Callers
--- MUST NOT mutate `result.registers[k]` fields in place after merge.
--- Use `set` (which writes a fresh table) for further updates.
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
