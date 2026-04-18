--- moa — Mixture of Agents: layered multi-agent aggregation
---
--- Multiple agents generate responses independently, then a second layer
--- of agents improves upon those responses by referencing all of them.
--- Unlike simple panel (single-round), MoA uses iterative layers where
--- each layer's agents see ALL previous layer outputs, enabling cross-
--- pollination of ideas and progressive refinement.
---
--- Based on: Wang et al., "Mixture-of-Agents Enhances Large Language
--- Model Capabilities" (2024, arXiv:2406.04692)
--- Achieved AlpacaEval 2.0 LC win rate of 65.8% (SOTA at publication)
---
--- Pipeline (4-8 LLM calls depending on layers):
---   Layer 1: N agents generate independent responses (parallel)
---   Layer 2: N agents each see ALL Layer 1 responses + improve (parallel)
---   ...repeat for configured layers...
---   Final:   Aggregator synthesizes best answer from last layer
---
--- Usage:
---   local moa = require("moa")
---   return moa.run(ctx)
---
--- ctx.task (required): The task to solve
--- ctx.n_agents: Agents per layer (default: 3)
--- ctx.n_layers: Number of improvement layers (default: 2)
--- ctx.gen_tokens: Max tokens per agent response (default: 400)
--- ctx.agg_tokens: Max tokens for final aggregation (default: 500)

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "moa",
    version = "0.1.0",
    description = "Mixture of Agents — layered multi-agent aggregation with cross-referencing improvement",
    category = "selection",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task       = T.string:describe("Task description"),
                n_agents   = T.number:is_optional()
                    :describe("Agents per layer (default: 3, capped to #PERSONAS=5)"),
                n_layers   = T.number:is_optional()
                    :describe("Number of improvement layers (default: 2)"),
                gen_tokens = T.number:is_optional()
                    :describe("Max tokens per agent response (default: 400)"),
                agg_tokens = T.number:is_optional()
                    :describe("Max tokens for final aggregation (default: 500)"),
            }),
            result = T.shape({
                answer        = T.string:describe("Final synthesized answer"),
                n_agents      = T.number:describe("Agents per layer actually used"),
                n_layers      = T.number:describe("Layers actually executed"),
                total_calls   = T.number
                    :describe("Total LLM invocations (agents * layers + 1 aggregation)"),
                layer_outputs = T.array_of(T.array_of(T.string))
                    :describe("Per-layer agent outputs ([layer_idx][agent_idx])"),
            }),
        },
    },
}

--- Agent personas for diversity.
local PERSONAS = {
    "You are an analytical expert who prioritizes logical rigor and precision.",
    "You are a creative problem solver who considers unconventional approaches.",
    "You are a domain specialist who draws on deep practical knowledge.",
    "You are a critical thinker who tests assumptions and considers edge cases.",
    "You are a systems thinker who considers interactions and second-order effects.",
}

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local n_agents = ctx.n_agents or 3
    local n_layers = ctx.n_layers or 2
    local gen_tokens = ctx.gen_tokens or 400
    local agg_tokens = ctx.agg_tokens or 500

    -- Cap agents to available personas
    if n_agents > #PERSONAS then n_agents = #PERSONAS end

    local layer_outputs = {}

    -- ─── Layer 1: Independent generation ───
    alc.log("info", string.format(
        "moa: Layer 1 — %d agents generating independently", n_agents
    ))

    local agent_indices = {}
    for i = 1, n_agents do
        agent_indices[i] = i
    end

    local layer1 = alc.map(agent_indices, function(i)
        return alc.llm(
            string.format("Task: %s\n\nProvide a thorough, well-reasoned answer.", task),
            {
                system = PERSONAS[i],
                max_tokens = gen_tokens,
            }
        )
    end)

    layer_outputs[1] = layer1

    alc.log("info", "moa: Layer 1 complete")

    -- ─── Subsequent layers: improve with cross-reference ───
    local prev_responses = layer1

    for layer = 2, n_layers do
        alc.log("info", string.format(
            "moa: Layer %d — %d agents improving with cross-reference",
            layer, n_agents
        ))

        -- Format previous layer responses for reference
        local ref_text = ""
        for j, resp in ipairs(prev_responses) do
            ref_text = ref_text .. string.format(
                "--- Agent %d's response ---\n%s\n\n", j, resp
            )
        end

        local layer_n = alc.map(agent_indices, function(i)
            return alc.llm(
                string.format(
                    "Task: %s\n\n"
                        .. "Other agents have provided these responses:\n\n%s"
                        .. "Considering all the above responses, provide an "
                        .. "improved answer that:\n"
                        .. "- Incorporates the strongest points from each response\n"
                        .. "- Corrects any errors you identify\n"
                        .. "- Fills gaps that others missed\n"
                        .. "- Resolves contradictions between responses",
                    task, ref_text
                ),
                {
                    system = PERSONAS[i] .. " You have access to other agents' "
                        .. "work. Build upon their insights while applying your "
                        .. "unique perspective to improve the answer.",
                    max_tokens = gen_tokens,
                }
            )
        end)

        layer_outputs[layer] = layer_n
        prev_responses = layer_n

        alc.log("info", string.format("moa: Layer %d complete", layer))
    end

    -- ─── Final aggregation ───
    alc.log("info", "moa: aggregating final answer")

    local final_ref = ""
    for j, resp in ipairs(prev_responses) do
        final_ref = final_ref .. string.format(
            "--- Agent %d ---\n%s\n\n", j, resp
        )
    end

    local final_answer = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Multiple expert agents have refined their answers "
                .. "through %d layers of cross-referencing:\n\n%s"
                .. "Synthesize the definitive answer:\n"
                .. "- Where agents agree, state with confidence\n"
                .. "- Where agents disagree, determine the correct position "
                .. "by evaluating reasoning quality\n"
                .. "- Ensure completeness — no important point should be lost",
            task, n_layers, final_ref
        ),
        {
            system = "You are a master synthesizer. Produce the best possible "
                .. "answer by combining insights from all agents. Prioritize "
                .. "accuracy and completeness.",
            max_tokens = agg_tokens,
        }
    )

    -- Compute stats
    local total_calls = 0
    for _, outputs in ipairs(layer_outputs) do
        total_calls = total_calls + #outputs
    end
    total_calls = total_calls + 1  -- aggregation call

    alc.log("info", string.format(
        "moa: complete — %d layers, %d agents/layer, %d total LLM calls",
        n_layers, n_agents, total_calls
    ))

    ctx.result = {
        answer = final_answer,
        n_agents = n_agents,
        n_layers = n_layers,
        total_calls = total_calls,
        layer_outputs = layer_outputs,
    }
    return ctx
end

-- Malli-style self-decoration (see alc_shapes/README). inline T.shape
-- for both input and result; wrapper validates in ALC_SHAPE_CHECK=1.
M.run = S.instrument(M, "run")

return M
