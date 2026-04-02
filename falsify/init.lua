--- falsify — Sequential Falsification for Hypothesis Exploration
---
--- Explores hypothesis space via Popper's falsificationism: generate hypotheses,
--- attempt to refute each one, prune the refuted, derive new hypotheses from
--- the refutation insights. Unlike verify_first (checks consistency) or cove
--- (verification chain), falsify actively ATTACKS hypotheses and uses refutation
--- failures as evidence of robustness, while refutation successes drive the
--- generation of improved successor hypotheses.
---
--- Based on:
---   [1] Sourati et al. "Automated Hypothesis Validation with Agentic
---       Sequential Falsifications" (2025, arXiv:2502.09858)
---   [2] Yamada et al. "AI Scientist v2: Agentic Tree Search for
---       Scientific Discovery" (2025, arXiv:2504.08066)
---   [3] Popper "The Logic of Scientific Discovery" (1959)
---
--- Pipeline (initial + max_rounds × hypotheses × 2 LLM calls + 1 synthesis):
---   Seed       — generate initial hypotheses
---   Loop (per round):
---     Falsify    — attempt to refute each active hypothesis (1 LLM call)
---     Judge      — was the refutation successful? (1 LLM call)
---     Prune      — remove refuted hypotheses
---     Derive     — generate successor hypotheses from refutation insights
---   Final: synthesize surviving hypotheses into answer
---
--- Usage:
---   local falsify = require("falsify")
---   return falsify.run(ctx)
---
--- ctx.task (required): The problem or question to investigate
--- ctx.initial_hypotheses: Number of seed hypotheses (default: 4)
--- ctx.max_rounds: Maximum falsification rounds (default: 3)
--- ctx.derive_on_refute: Generate successors from refuted hypotheses (default: true)
--- ctx.max_hypotheses: Upper bound on active hypotheses (default: 12)

local M = {}

---@type AlcMeta
M.meta = {
    name = "falsify",
    version = "0.1.0",
    description = "Sequential Falsification — Popper-style hypothesis exploration "
        .. "via active refutation, pruning, and successor derivation. "
        .. "Expands search space through refutation-driven insight.",
    category = "exploration",
}

--- Generate initial hypotheses.
local function generate_hypotheses(task, count)
    local hypotheses = {}
    for i = 1, count do
        local existing = ""
        if #hypotheses > 0 then
            local items = {}
            for j, h in ipairs(hypotheses) do
                items[#items + 1] = string.format("  H%d: %s", j, h.text)
            end
            existing = "\n\nExisting hypotheses (propose something DIFFERENT):\n"
                .. table.concat(items, "\n")
        end

        local text = alc.llm(
            string.format(
                "Task: %s\n%s\n\n"
                    .. "Propose hypothesis #%d. It should be:\n"
                    .. "- Specific and falsifiable (possible to prove wrong)\n"
                    .. "- Different from existing hypotheses\n"
                    .. "- A genuine candidate answer/explanation\n\n"
                    .. "State the hypothesis in 1-3 sentences.",
                task, existing, i
            ),
            {
                system = "You are a rigorous thinker. Propose clear, falsifiable hypotheses.",
                max_tokens = 200,
            }
        )

        hypotheses[#hypotheses + 1] = {
            id = i,
            text = text,
            status = "active",  -- active | refuted | survived
            confidence = 0.5,
            refutation_attempts = 0,
            history = {},
        }
    end
    return hypotheses
end

--- Attempt to falsify a hypothesis. Returns the refutation argument.
local function attempt_falsification(task, hypothesis, round)
    return alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Hypothesis to REFUTE:\n%s\n\n"
                .. "Your goal is to DISPROVE this hypothesis. Find:\n"
                .. "- Counterexamples that violate the hypothesis\n"
                .. "- Logical contradictions within the hypothesis\n"
                .. "- Evidence or reasoning that makes the hypothesis unlikely\n"
                .. "- Edge cases where the hypothesis fails\n\n"
                .. "Be aggressive and thorough. If you cannot find a refutation, "
                .. "explain why the hypothesis resists falsification.\n\n"
                .. "This is falsification round %d.",
            task, hypothesis.text, round
        ),
        {
            system = "You are a devil's advocate. Your SOLE purpose is to find "
                .. "flaws and counterexamples. Be relentless but intellectually honest.",
            max_tokens = 300,
        }
    )
end

--- Judge whether a falsification attempt succeeded.
--- Returns: "refuted", "weakened", or "survived"
local function judge_falsification(task, hypothesis, refutation)
    local verdict_str = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Hypothesis:\n%s\n\n"
                .. "Falsification attempt:\n%s\n\n"
                .. "Judge the falsification:\n"
                .. "- REFUTED: The counterexample/argument decisively disproves the hypothesis\n"
                .. "- WEAKENED: The argument reveals a flaw but doesn't fully disprove it\n"
                .. "- SURVIVED: The hypothesis resists this falsification attempt\n\n"
                .. "Reply with EXACTLY one word: REFUTED, WEAKENED, or SURVIVED",
            task, hypothesis.text, refutation
        ),
        {
            system = "You are an impartial judge. One word only.",
            max_tokens = 10,
        }
    )

    local v = verdict_str:upper():match("REFUTED")
        or verdict_str:upper():match("WEAKENED")
        or verdict_str:upper():match("SURVIVED")

    if v == "REFUTED" then return "refuted"
    elseif v == "WEAKENED" then return "weakened"
    else return "survived"
    end
end

--- Derive a successor hypothesis from a refuted one.
local function derive_successor(task, refuted_hypothesis, refutation, next_id)
    local text = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Refuted hypothesis:\n%s\n\n"
                .. "Refutation that disproved it:\n%s\n\n"
                .. "Using the INSIGHT from this refutation, propose a NEW, IMPROVED "
                .. "hypothesis that:\n"
                .. "- Addresses the flaw that caused the refutation\n"
                .. "- Incorporates the lesson learned\n"
                .. "- Is still falsifiable\n"
                .. "- Is meaningfully different from the original\n\n"
                .. "State the new hypothesis in 1-3 sentences.",
            task, refuted_hypothesis.text, refutation
        ),
        {
            system = "You are a scientist refining hypotheses. Learn from failures.",
            max_tokens = 200,
        }
    )

    return {
        id = next_id,
        text = text,
        status = "active",
        confidence = 0.5,
        refutation_attempts = 0,
        derived_from = refuted_hypothesis.id,
        history = {},
    }
end

-- ─── Main ───

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local initial_count = ctx.initial_hypotheses or 4
    local max_rounds = ctx.max_rounds or 3
    local derive_on_refute = ctx.derive_on_refute
    if derive_on_refute == nil then derive_on_refute = true end
    local max_hypotheses = ctx.max_hypotheses or 12

    -- Phase 1: Generate initial hypotheses
    local hypotheses = generate_hypotheses(task, initial_count)
    local next_id = initial_count + 1

    alc.log("info", string.format(
        "falsify: generated %d initial hypotheses", #hypotheses
    ))

    -- Phase 2: Falsification rounds
    local total_refuted = 0
    local total_survived = 0
    local total_derived = 0

    for round = 1, max_rounds do
        local active = {}
        for _, h in ipairs(hypotheses) do
            if h.status == "active" then
                active[#active + 1] = h
            end
        end

        if #active == 0 then
            alc.log("warn", "falsify: no active hypotheses remain, stopping")
            break
        end

        alc.log("info", string.format(
            "falsify: round %d/%d — %d active hypotheses",
            round, max_rounds, #active
        ))

        local new_hypotheses = {}

        for _, h in ipairs(active) do
            -- Attempt falsification
            local refutation = attempt_falsification(task, h, round)
            h.refutation_attempts = h.refutation_attempts + 1

            -- Judge
            local verdict = judge_falsification(task, h, refutation)

            -- Record history
            h.history[#h.history + 1] = {
                round = round,
                refutation = refutation,
                verdict = verdict,
            }

            if verdict == "refuted" then
                h.status = "refuted"
                h.confidence = 0
                total_refuted = total_refuted + 1

                alc.log("info", string.format(
                    "falsify: H%d REFUTED in round %d", h.id, round
                ))

                -- Derive successor
                if derive_on_refute then
                    local active_count = 0
                    for _, h2 in ipairs(hypotheses) do
                        if h2.status == "active" then active_count = active_count + 1 end
                    end
                    -- Count pending new hypotheses too
                    active_count = active_count + #new_hypotheses

                    if active_count < max_hypotheses then
                        local successor = derive_successor(task, h, refutation, next_id)
                        next_id = next_id + 1
                        new_hypotheses[#new_hypotheses + 1] = successor
                        total_derived = total_derived + 1

                        alc.log("info", string.format(
                            "falsify: derived H%d from refuted H%d",
                            successor.id, h.id
                        ))
                    end
                end
            elseif verdict == "weakened" then
                h.confidence = math.max(0.1, h.confidence - 0.2)
                alc.log("info", string.format(
                    "falsify: H%d weakened (confidence=%.1f)", h.id, h.confidence
                ))
            else  -- survived
                h.confidence = math.min(1.0, h.confidence + 0.15)
                total_survived = total_survived + 1
                alc.log("info", string.format(
                    "falsify: H%d survived (confidence=%.1f)", h.id, h.confidence
                ))
            end
        end

        -- Add derived hypotheses to the pool
        for _, h in ipairs(new_hypotheses) do
            hypotheses[#hypotheses + 1] = h
        end
    end

    -- Mark remaining active hypotheses as survived
    for _, h in ipairs(hypotheses) do
        if h.status == "active" then
            h.status = "survived"
        end
    end

    -- Phase 3: Rank survivors
    local survivors = {}
    for _, h in ipairs(hypotheses) do
        if h.status == "survived" then
            survivors[#survivors + 1] = h
        end
    end
    table.sort(survivors, function(a, b) return a.confidence > b.confidence end)

    -- Phase 4: Synthesize answer from survivors
    local answer
    if #survivors > 0 then
        local survivor_text = ""
        for i, h in ipairs(survivors) do
            survivor_text = survivor_text .. string.format(
                "H%d (confidence=%.1f, attempts=%d): %s\n",
                h.id, h.confidence, h.refutation_attempts, h.text
            )
        end

        answer = alc.llm(
            string.format(
                "Task: %s\n\n"
                    .. "Surviving hypotheses after %d rounds of falsification:\n%s\n"
                    .. "Synthesize these surviving hypotheses into a comprehensive answer. "
                    .. "Weight by confidence. Acknowledge remaining uncertainties.",
                task, max_rounds, survivor_text
            ),
            {
                system = "You are an expert synthesizer. Build on the surviving, "
                    .. "battle-tested hypotheses.",
                max_tokens = 600,
            }
        )
    else
        answer = alc.llm(
            string.format(
                "Task: %s\n\n"
                    .. "All hypotheses were refuted after %d rounds of falsification.\n"
                    .. "Based on the refutation insights, provide your best answer.",
                task, max_rounds
            ),
            {
                system = "All initial hypotheses failed. Use the lessons learned to "
                    .. "provide the most defensible answer possible.",
                max_tokens = 600,
            }
        )
    end

    -- Build full results
    local all_hypotheses = {}
    for _, h in ipairs(hypotheses) do
        all_hypotheses[#all_hypotheses + 1] = {
            id = h.id,
            text = h.text,
            status = h.status,
            confidence = h.confidence,
            refutation_attempts = h.refutation_attempts,
            derived_from = h.derived_from,
            history = h.history,
        }
    end

    ctx.result = {
        answer = answer,
        survivors = survivors,
        all_hypotheses = all_hypotheses,
        stats = {
            initial_count = initial_count,
            total_generated = #hypotheses,
            total_refuted = total_refuted,
            total_survived = #survivors,
            total_derived = total_derived,
            rounds = max_rounds,
        },
    }
    return ctx
end

return M
