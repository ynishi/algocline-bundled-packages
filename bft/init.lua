--- bft — Byzantine Fault Tolerance impossibility bounds
---
--- Pure-computation utility for BFT quorum thresholds and validation.
--- No LLM calls; used as a governance primitive by higher-level packages
--- (e.g. pbft, dissent, anti_cascade).
---
--- Theory:
---   Lamport, Shostak, Pease. "The Byzantine Generals Problem".
---   ACM TOPLAS 4(3), pp.382-401, 1982. DOI:10.1145/357172.357176
---
---   Core result (Theorem 1): With oral messages, agreement is possible
---   iff n >= 3f + 1, where n = total nodes, f = faulty nodes.
---   Required quorum: 2f + 1 (any two quorums share >= 1 honest node).
---
---   With signed messages (SM(m), section 4): n >= f + 2 suffices.
---
--- Multi-Agent / Swarm context:
---   In LLM agent swarms, "Byzantine faults" map to hallucinating,
---   adversarial, or compromised agents that may produce arbitrarily
---   wrong outputs. BFT bounds answer the governance question:
---     "Given N agents, how many can fail before consensus breaks?"
---
---   Practical applications:
---   - Panel sizing: given expected hallucination rate f/n, compute
---     minimum panel size n >= 3f+1 for reliable majority vote
---   - pbft integration: BFT bounds determine quorum thresholds
---     for the 3-phase consensus protocol
---   - Signed-message mode: when agents produce verifiable outputs
---     (e.g. code with unit tests), the weaker n >= f+2 bound applies,
---     allowing smaller panels
---
---   Related: "From Spark to Fire" (Xie et al., AAMAS 2026) shows that
---   single faulty agents can cascade through multi-agent pipelines —
---   BFT bounds quantify the structural resilience of the system.
---
--- Usage:
---   local bft = require("bft")
---   assert(bft.validate(7, 2))          -- 7 >= 3*2+1 = true
---   assert(bft.threshold(7, 2) == 5)    -- quorum = 2*2+1 = 5
---   assert(bft.max_faults(7) == 2)      -- floor((7-1)/3) = 2

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "bft",
    version = "0.1.0",
    description = "Byzantine Fault Tolerance bounds — quorum thresholds "
        .. "and impossibility validation for multi-agent governance. "
        .. "Computes minimum panel sizes and fault tolerance limits "
        .. "(Lamport-Shostak-Pease 1982, Theorem 1: n >= 3f+1).",
    category = "governance",
}

---@type AlcSpec
-- Args across entries follow the (n, f) pattern: total nodes and
-- faulty (Byzantine) node count. Per-entry :describe() restates this
-- so projection outputs do not elide the argument semantics.
local N_DESC = "Total number of nodes"
local F_DESC = "Number of faulty (Byzantine) nodes"
M.spec = {
    entries = {
        validate = {
            args   = { T.number:describe(N_DESC), T.number:describe(F_DESC) },
            result = T.boolean:describe("Whether n >= 3f+1 (oral-message agreement possible)"),
        },
        threshold = {
            args   = { T.number:describe(N_DESC), T.number:describe(F_DESC) },
            result = T.number:describe("Quorum size (2f+1) under oral-message bound"),
        },
        max_faults = {
            args   = { T.number:describe(N_DESC) },
            result = T.number:describe("Maximum f tolerable under oral-message bound"),
        },
        validate_signed = {
            args   = { T.number:describe(N_DESC), T.number:describe(F_DESC) },
            result = T.boolean:describe("Whether n >= f+2 (signed-message agreement possible)"),
        },
        signed_threshold = {
            args   = { T.number:describe(N_DESC), T.number:describe(F_DESC) },
            result = T.number:describe("Quorum size (f+1) under signed-message bound"),
        },
        max_faults_signed = {
            args   = { T.number:describe(N_DESC) },
            result = T.number:describe("Maximum f tolerable under signed-message bound"),
        },
        summary = {
            args   = { T.number:describe(N_DESC), T.number:describe(F_DESC) },
            result = T.shape({
                n             = T.number:describe("Total node count (input echo)"),
                f             = T.number:describe("Faulty node count (input echo)"),
                oral_ok       = T.boolean:describe("Whether oral-message bound (n >= 3f+1) is satisfied"),
                oral_reason   = T.string:describe("Human-readable reason for oral_ok"),
                oral_quorum   = T.number:is_optional():describe("2f+1 quorum size when oral_ok; nil otherwise"),
                signed_ok     = T.boolean:describe("Whether signed-message bound (n >= f+2) is satisfied"),
                signed_reason = T.string:describe("Human-readable reason for signed_ok"),
                signed_quorum = T.number:is_optional():describe("f+1 quorum size when signed_ok; nil otherwise"),
                max_f_oral    = T.number:describe("Max tolerable f under oral-message bound"),
                max_f_signed  = T.number:describe("Max tolerable f under signed-message bound"),
            }),
        },
    },
}

--- Validate whether BFT agreement is possible with oral messages.
--- Theorem 1: requires n >= 3f + 1.
---@param n integer total number of nodes (agents)
---@param f integer number of faulty (Byzantine) nodes
---@return boolean possible true if agreement is achievable
---@return string reason human-readable explanation
function M.validate(n, f)
    if type(n) ~= "number" or n < 1 or n ~= math.floor(n) then
        error("bft.validate: n must be a positive integer, got " .. tostring(n))
    end
    if type(f) ~= "number" or f < 0 or f ~= math.floor(f) then
        error("bft.validate: f must be a non-negative integer, got " .. tostring(f))
    end
    local required = 3 * f + 1
    if n >= required then
        return true, string.format("n=%d >= 3f+1=%d: BFT agreement possible", n, required)
    else
        return false, string.format("n=%d < 3f+1=%d: BFT agreement IMPOSSIBLE (Theorem 1)", n, required)
    end
end

--- Compute the quorum size for oral-message BFT.
--- Quorum = 2f + 1 (guarantees any two quorums overlap in >= 1 honest).
---@param n integer total number of nodes
---@param f integer number of faulty nodes
---@return integer quorum required votes for agreement
function M.threshold(n, f)
    local ok, reason = M.validate(n, f)
    if not ok then
        error("bft.threshold: " .. reason)
    end
    return 2 * f + 1
end

--- Maximum tolerable faults for a given n (oral messages).
--- max_f = floor((n - 1) / 3)
---@param n integer total number of nodes
---@return integer max_f maximum Byzantine faults tolerable
function M.max_faults(n)
    if type(n) ~= "number" or n < 1 or n ~= math.floor(n) then
        error("bft.max_faults: n must be a positive integer, got " .. tostring(n))
    end
    return math.floor((n - 1) / 3)
end

--- Validate and compute threshold for signed messages (SM(m)).
--- Section 4: with signatures, n >= f + 2 suffices.
---@param n integer total number of nodes
---@param f integer number of faulty nodes
---@return boolean possible
---@return string reason
function M.validate_signed(n, f)
    if type(n) ~= "number" or n < 1 or n ~= math.floor(n) then
        error("bft.validate_signed: n must be a positive integer, got " .. tostring(n))
    end
    if type(f) ~= "number" or f < 0 or f ~= math.floor(f) then
        error("bft.validate_signed: f must be a non-negative integer, got " .. tostring(f))
    end
    local required = f + 2
    if n >= required then
        return true, string.format("n=%d >= f+2=%d: signed BFT agreement possible", n, required)
    else
        return false, string.format("n=%d < f+2=%d: signed BFT agreement IMPOSSIBLE", n, required)
    end
end

--- Threshold for signed messages.
--- With signatures the quorum is simply f + 1 (majority of honest).
---@param n integer total number of nodes
---@param f integer number of faulty nodes
---@return integer quorum required votes
function M.signed_threshold(n, f)
    local ok, reason = M.validate_signed(n, f)
    if not ok then
        error("bft.signed_threshold: " .. reason)
    end
    return f + 1
end

--- Maximum tolerable faults with signed messages.
--- max_f = n - 2
---@param n integer total number of nodes
---@return integer max_f
function M.max_faults_signed(n)
    if type(n) ~= "number" or n < 2 or n ~= math.floor(n) then
        error("bft.max_faults_signed: n must be an integer >= 2, got " .. tostring(n))
    end
    return n - 2
end

--- Summarize BFT properties for a given (n, f) configuration.
---@param n integer total number of nodes
---@param f integer assumed number of faults
---@return table summary { n, f, oral_ok, oral_quorum, signed_ok, signed_quorum, max_f_oral, max_f_signed }
function M.summary(n, f)
    local oral_ok, oral_reason = M.validate(n, f)
    local signed_ok, signed_reason = M.validate_signed(n, f)
    return {
        n = n,
        f = f,
        oral_ok = oral_ok,
        oral_reason = oral_reason,
        oral_quorum = oral_ok and (2 * f + 1) or nil,
        signed_ok = signed_ok,
        signed_reason = signed_reason,
        signed_quorum = signed_ok and (f + 1) or nil,
        max_f_oral = M.max_faults(n),
        max_f_signed = M.max_faults_signed(math.max(n, 2)),
    }
end

-- Malli-style self-decoration (see alc_shapes/README). direct-args mode:
-- each entry is a pure function with positional args + raw return.
M.validate          = S.instrument(M, "validate")
M.threshold         = S.instrument(M, "threshold")
M.max_faults        = S.instrument(M, "max_faults")
M.validate_signed   = S.instrument(M, "validate_signed")
M.signed_threshold  = S.instrument(M, "signed_threshold")
M.max_faults_signed = S.instrument(M, "max_faults_signed")
M.summary           = S.instrument(M, "summary")

return M
