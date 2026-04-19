--- flow — Light Frame substrate for composing algo-based pkg
---
--- Provides two primitives:
---   FlowState — a plain table persisted via alc.state (KV primitive).
---   ReqToken  — a random nonce bound to a state, echoed by downstream
---               pkg results and verified on return.
---
--- flow is a substrate, not an orchestrator. It does not provide M.run.
--- The driver loop stays in user code (Recipe). This preserves the
--- "mechanism, not policy" discipline of a Light Frame and keeps
--- bundled algo pkg (ab_mcts, cascade, coevolve, ...) composable
--- without an Agent boundary abstraction.
---
--- Design references:
---   - workspace/tasks/flow-frame/design-full.md
---   - workspace/tasks/flow-frame/design-refine.md
---   - workspace/tasks/flow-frame/bp-research.md
---
--- Usage (minimal):
---   local flow = require("flow")
---
---   local st   = flow.state_new({ key_prefix = "my_run", id = "abc", resume = true })
---   local tok  = flow.token_issue(st)
---
---   if not flow.state_get(st, "gate_ok") then
---       local req = flow.token_wrap(tok, { slot = "gate", payload = { q = "..." } })
---       local out = some_pkg.run(req.payload)
---       assert(flow.token_verify(tok, out, req), "token/slot mismatch")
---       flow.state_set(st, "gate_ok", true)
---       flow.state_save(st)
---   end

local state = require("flow.state")
local token = require("flow.token")
local llm   = require("flow.llm")

local M = {}

---@type AlcMeta
M.meta = {
    name        = "flow",
    version     = "0.2.0",
    description = "Flow Frame — FlowState + ReqToken substrate for composing "
        .. "algo-based pkg (ab_mcts / cascade / coevolve / ...). "
        .. "Light Frame: driver loop stays in user code. v0.2 adds "
        .. "session-spanning bound APIs (wrap_bound / verify_bound / "
        .. "llm_bound) that persist verify-side state across alc.llm "
        .. "yield boundaries.",
    category    = "substrate",
}

-- Public API (flat, module-level pure fn — Neovim/Penlight/OpenResty style).
M.state_new          = state.new
M.state_key          = state.key
M.state_get          = state.get
M.state_set          = state.set
M.state_save         = state.save

M.token_issue        = token.issue
M.token_wrap         = token.wrap
M.token_verify       = token.verify
M.token_wrap_bound   = token.wrap_bound
M.token_verify_bound = token.verify_bound

M.llm                = llm.llm
M.llm_bound          = llm.llm_bound

return M
