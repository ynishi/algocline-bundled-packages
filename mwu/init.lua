--- mwu — Multiplicative Weights Update for adversarial online learning
---
--- Maintains a weight distribution over N agents (experts/arms) and
--- updates weights multiplicatively based on observed losses. Provides
--- optimal O(√(T ln N)) regret bound against ANY adversarial loss
--- sequence — no stochastic assumption required.
---
--- Theory:
---   Littlestone, N., Warmuth, M. K. "The Weighted Majority Algorithm".
---   Information and Computation 108(2), pp.212-261, 1994.
---
---   Freund, Y., Schapire, R. E. "A Decision-Theoretic Generalization of
---   On-Line Learning and an Application to Boosting". JCSS 55(1),
---   pp.119-139, 1997.
---
---   Cesa-Bianchi, N., Lugosi, G. "Prediction, Learning, and Games".
---   Cambridge University Press, 2006. §2.1-2.3.
---
---   Update rule:
---     w_i(t+1) = w_i(t) · (1 - η · ℓ_i(t))
---
---   Normalized distribution:
---     p_i(t) = w_i(t) / Σ_j w_j(t)
---
---   Regret bound:
---     Regret_T = Σ_t p(t)·ℓ(t) - min_i Σ_t ℓ_i(t)
---              ≤ (ln N)/η + η·T
---     Optimal η = √(ln N / T) yields: Regret_T ≤ 2√(T ln N)
---
--- Multi-Agent / Swarm context:
---   MWU is the principled way to learn agent weights over time in
---   an adversarial environment (where tasks/prompts can change
---   arbitrarily between rounds). Unlike UCB1 which selects ONE arm,
---   MWU outputs a full WEIGHT DISTRIBUTION over all agents.
---
---   - Dynamic weight learning: as agents are evaluated on successive
---     tasks, MWU concentrates weight on consistently good performers
---     while maintaining exploration. No i.i.d. assumption required —
---     works even if an adversary chooses the worst possible tasks.
---   - Regret guarantee: total loss of the weighted mixture is at most
---     2√(T ln N) worse than the BEST single agent in hindsight.
---     This bound holds against any sequence of tasks.
---   - Doubling trick: when T (number of rounds) is unknown in advance,
---     the doubling trick maintains O(√(T ln N)) regret by restarting
---     with doubled epoch lengths and recalculated η.
---   - Log-space computation: weights are maintained in log-space to
---     prevent numerical underflow when agents have extreme loss
---     contrast over many rounds.
---   - Difference from UCB1 (ucb package):
---     UCB1: stochastic bandits (i.i.d. losses), selects ONE arm
---     MWU:  adversarial setting (arbitrary losses), outputs DISTRIBUTION
---   - Composable with panel/moa (weight the agent mixture), shapley
---     (post-hoc attribution), and scoring_rule (loss from calibration
---     scores as input to MWU).
---
--- Usage:
---   local mwu = require("mwu")
---
---   -- Stateful updater
---   local u = mwu.new({ n = 5, T = 100 })
---   u:update({ 0.3, 0.8, 0.1, 0.5, 0.2 })
---   local w = u:weights()
---
---   -- One-shot from loss matrix
---   local r = mwu.solve(loss_matrix)

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "mwu",
    version = "0.1.0",
    description = "Multiplicative Weights Update — adversarial online agent "
        .. "weight learning with O(√(T ln N)) regret bound. Learns optimal "
        .. "agent mixture weights over time without stochastic assumptions "
        .. "(Littlestone-Warmuth 1994, Freund-Schapire 1997).",
    category = "selection",
}

---@type AlcSpec
-- Only module-level functions are instrumented. Updater instance methods
-- (u:weights / u:update / u:stats) live on the metatable and are NOT
-- wrapped — the wrapper would lose the `self` binding via `u:method()`
-- syntactic sugar, and Lua's ":" sugar isn't compatible with direct-args
-- mode arg-shape declarations.
M.spec = {
    entries = {
        new = {
            args   = {
                T.table:describe("Constructor opts (n required, eta?, T?)"),
            },
            result = T.table:describe(
                "Opaque Updater instance (obj:update / obj:distribution)"),
        },
        solve = {
            args   = {
                T.array_of(T.array_of(T.number)):describe(
                    "Loss matrix loss[t][i] over T rounds x n agents"),
                T.table:is_optional():describe("Opts (eta?)"),
            },
            result = T.shape({
                final_weights       = T.array_of(T.number):describe(
                    "Final normalized distribution p_i(T)"),
                regret              = T.number:describe(
                    "Actual regret vs. best fixed agent in hindsight"),
                regret_bound        = T.number:describe(
                    "Theoretical bound 2*sqrt(T ln N)"),
                regret_within_bound = T.boolean:describe(
                    "regret <= regret_bound"),
                cumulative_loss     = T.number:describe(
                    "Algorithm's cumulative loss Sum_t p(t)*loss(t)"),
                best_agent          = T.number:describe(
                    "1-based index of best fixed agent in hindsight"),
                best_agent_loss     = T.number:describe(
                    "Cumulative loss of the best fixed agent"),
                weight_history      = T.array_of(T.any):describe(
                    "Per-round {round, weights} snapshots"),
                n                   = T.number:describe("Number of agents"),
                T                   = T.number:describe("Number of rounds"),
                eta                 = T.number:describe("Learning rate used"),
            }),
        },
        accuracy_to_loss = {
            args   = {
                T.array_of(T.number):describe("Accuracy values in [0,1]"),
            },
            result = T.array_of(T.number):describe("Loss = 1 - accuracy"),
        },
    },
}

-- ─── Updater class ───

local Updater = {}
Updater.__index = Updater

--- Create a new MWU updater.
---
--- opts:
---   n:    number of agents/experts (required)
---   eta:  learning rate (default: auto from T)
---   T:    planned horizon (used for auto eta; default: nil → doubling trick)
---
---@param opts table { n, eta?, T? }
---@return table updater
function M.new(opts)
    if type(opts) ~= "table" then
        error("mwu.new: opts must be a table")
    end
    local n = opts.n
    if type(n) ~= "number" or n < 1 or n ~= math.floor(n) then
        error("mwu.new: n must be a positive integer, got " .. tostring(n))
    end

    local self = setmetatable({}, Updater)
    self.n = n
    self.T_budget = opts.T  -- may be nil (doubling trick)

    -- Learning rate
    if opts.eta then
        if opts.eta <= 0 or opts.eta >= 1 then
            error("mwu.new: eta must be in (0, 1), got " .. tostring(opts.eta))
        end
        self.eta = opts.eta
        self.use_doubling = false
    elseif opts.T then
        -- Optimal: η = √(ln N / T)
        self.eta = math.sqrt(math.log(n) / opts.T)
        -- Clamp to (0, 0.5) for stability
        if self.eta >= 0.5 then self.eta = 0.49 end
        if self.eta <= 0 then self.eta = 1e-6 end
        self.use_doubling = false
    else
        -- Doubling trick: start with epoch_len = 1
        self.use_doubling = true
        self.epoch_len = 1
        self.epoch_round = 0
        self.eta = math.sqrt(math.log(n) / 1)
        if self.eta >= 0.5 then self.eta = 0.49 end
        if self.eta <= 0 then self.eta = 1e-6 end
    end

    -- Initialize weights uniformly
    self.log_w = {}
    for i = 1, n do
        self.log_w[i] = 0  -- log(1) = 0
    end

    -- Tracking
    self.round = 0
    self.cumulative_loss = 0        -- Σ_t p(t)·ℓ(t)
    self.agent_cumulative = {}      -- Σ_t ℓ_i(t)
    for i = 1, n do
        self.agent_cumulative[i] = 0
    end

    return self
end

--- Compute normalized weight distribution from log-weights.
---@return table weights { p_1, p_2, ..., p_n }
function Updater:weights()
    -- Log-sum-exp for numerical stability
    local max_log = -math.huge
    for i = 1, self.n do
        if self.log_w[i] > max_log then max_log = self.log_w[i] end
    end

    local sum_exp = 0
    local w = {}
    for i = 1, self.n do
        w[i] = math.exp(self.log_w[i] - max_log)
        sum_exp = sum_exp + w[i]
    end

    for i = 1, self.n do
        w[i] = w[i] / sum_exp
    end
    return w
end

--- Process one round of losses.
---@param losses table { ℓ_1, ℓ_2, ..., ℓ_n } each in [0, 1]
function Updater:update(losses)
    if type(losses) ~= "table" or #losses ~= self.n then
        error("mwu:update: losses must be a list of " .. self.n .. " values")
    end

    -- Validate losses
    for i = 1, self.n do
        local l = losses[i]
        if type(l) ~= "number" or l < 0 or l > 1 then
            error("mwu:update: loss[" .. i .. "] must be in [0, 1], got "
                .. tostring(l))
        end
    end

    -- Doubling trick: check if we need to start a new epoch
    if self.use_doubling then
        self.epoch_round = self.epoch_round + 1
        if self.epoch_round > self.epoch_len then
            -- Double the epoch length, recalculate eta
            self.epoch_len = self.epoch_len * 2
            self.epoch_round = 1
            self.eta = math.sqrt(math.log(self.n) / self.epoch_len)
            if self.eta >= 0.5 then self.eta = 0.49 end
            if self.eta <= 0 then self.eta = 1e-6 end
            -- Reset weights for new epoch
            for i = 1, self.n do
                self.log_w[i] = 0
            end
        end
    end

    -- Get current distribution before update
    local p = self:weights()

    -- Track cumulative weighted loss
    local round_loss = 0
    for i = 1, self.n do
        round_loss = round_loss + p[i] * losses[i]
    end
    self.cumulative_loss = self.cumulative_loss + round_loss

    -- Track per-agent cumulative loss
    for i = 1, self.n do
        self.agent_cumulative[i] = self.agent_cumulative[i] + losses[i]
    end

    -- Multiplicative update in log-space:
    -- w_i(t+1) = w_i(t) * (1 - η * ℓ_i(t))
    -- log w_i(t+1) = log w_i(t) + log(1 - η * ℓ_i(t))
    for i = 1, self.n do
        local factor = 1 - self.eta * losses[i]
        if factor <= 0 then factor = 1e-300 end  -- prevent log(0)
        self.log_w[i] = self.log_w[i] + math.log(factor)
    end

    self.round = self.round + 1
end

--- Get statistics for the current state.
---@return table stats
function Updater:stats()
    -- Find best agent (minimum cumulative loss)
    local best_agent = 1
    local best_loss = self.agent_cumulative[1]
    for i = 2, self.n do
        if self.agent_cumulative[i] < best_loss then
            best_loss = self.agent_cumulative[i]
            best_agent = i
        end
    end

    local regret = self.cumulative_loss - best_loss

    -- Theoretical bound: 2√(T ln N) for optimal fixed eta
    -- For doubling trick: slightly worse constant but same order
    local T = self.round
    local bound = 2 * math.sqrt(T * math.log(self.n))

    return {
        round = self.round,
        eta = self.eta,
        cumulative_loss = self.cumulative_loss,
        best_agent_loss = best_loss,
        best_agent = best_agent,
        regret = regret,
        regret_bound = bound,
        regret_within_bound = regret <= bound + 1e-9,
        n = self.n,
    }
end

-- ─── One-shot solver ───

--- Run MWU on a complete loss matrix and return final state.
---
---@param loss_matrix table loss_matrix[t][i] = agent i's loss at round t
---@param opts table|nil { eta? }
---@return table result { final_weights, regret, regret_bound, weight_history, ... }
function M.solve(loss_matrix, opts)
    if type(loss_matrix) ~= "table" or #loss_matrix == 0 then
        error("mwu.solve: loss_matrix must be a non-empty list of rounds")
    end
    opts = opts or {}

    local T = #loss_matrix
    local n = #loss_matrix[1]
    if n < 1 then
        error("mwu.solve: first round must have at least 1 agent")
    end

    -- Validate dimensions
    for t = 2, T do
        if #loss_matrix[t] ~= n then
            error("mwu.solve: round " .. t .. " has " .. #loss_matrix[t]
                .. " agents, expected " .. n)
        end
    end

    local updater = M.new({
        n = n,
        T = T,
        eta = opts.eta,
    })

    local weight_history = {}

    for t = 1, T do
        weight_history[t] = {
            round = t,
            weights = updater:weights(),
        }
        updater:update(loss_matrix[t])
    end

    local stats = updater:stats()

    return {
        final_weights = updater:weights(),
        regret = stats.regret,
        regret_bound = stats.regret_bound,
        regret_within_bound = stats.regret_within_bound,
        cumulative_loss = stats.cumulative_loss,
        best_agent = stats.best_agent,
        best_agent_loss = stats.best_agent_loss,
        weight_history = weight_history,
        n = n,
        T = T,
        eta = updater.eta,
    }
end

-- ─── Utility ───

--- Convert accuracy values to losses.
---@param accuracies table { acc_1, acc_2, ..., acc_n } each in [0, 1]
---@return table losses { 1-acc_1, 1-acc_2, ..., 1-acc_n }
function M.accuracy_to_loss(accuracies)
    if type(accuracies) ~= "table" then
        error("mwu.accuracy_to_loss: input must be a table")
    end
    local losses = {}
    for i, a in ipairs(accuracies) do
        if type(a) ~= "number" or a < 0 or a > 1 then
            error("mwu.accuracy_to_loss: accuracy[" .. i
                .. "] must be in [0, 1], got " .. tostring(a))
        end
        losses[i] = 1 - a
    end
    return losses
end

-- Malli-style self-decoration. Only module-level functions are wrapped;
-- Updater:weights/update/stats are instance methods (OOP), outside the
-- direct-args contract.
M.new              = S.instrument(M, "new")
M.solve            = S.instrument(M, "solve")
M.accuracy_to_loss = S.instrument(M, "accuracy_to_loss")

return M
