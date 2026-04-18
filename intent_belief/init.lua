--- Intent Belief — Bayesian intent estimation via hypothesis generation and update
---
--- Maintains a belief distribution over candidate intents. Generates
--- multiple intent hypotheses as prior, then iteratively updates beliefs
--- through diagnostic questions and likelihood estimation.
---
--- Based on: "Probabilistic Modeling of Intentions in Socially Intelligent
--- LLM Agents" (2025, arXiv:2510.18476)
---
--- The algorithm:
---   Phase 1 (Prior): Generate N candidate intent hypotheses from context
---   Phase 2 (Diagnose): Generate a discriminating question that maximally
---           separates the hypotheses (information gain)
---   Phase 3 (Update): Given user response, re-estimate likelihood of each
---           hypothesis and update belief distribution
---   Phase 4 (Converge): If top hypothesis has sufficient confidence,
---           or max rounds reached, output the MAP estimate
---
--- Usage:
---   local intent_belief = require("intent_belief")
---   return intent_belief.run(ctx)
---
--- ctx.task (required): The initial user request
--- ctx.n_hypotheses: Number of intent hypotheses (default: 5)
--- ctx.max_rounds: Maximum belief update rounds (default: 3)
--- ctx.confidence_threshold: Stop when top hypothesis exceeds this (default: 0.7)
--- ctx.prior_tokens: Max tokens for prior generation (default: 600)
--- ctx.diagnose_tokens: Max tokens for diagnostic question (default: 400)
--- ctx.update_tokens: Max tokens for belief update (default: 500)

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "intent_belief",
    version = "0.1.0",
    description = "Bayesian intent estimation — hypothesis generation with iterative belief updates via diagnostic questions",
    category = "intent",
}

local ranked_hypothesis_shape = T.shape({
    id          = T.number:describe("Hypothesis index in the original parse order (1-based)"),
    description = T.string:describe("Hypothesis text"),
    belief      = T.number:describe("Posterior probability after the last update round (0-1)"),
})

local update_log_entry_shape = T.shape({
    round       = T.number:describe("Round index (1-based)"),
    question    = T.string:describe("Diagnostic question asked this round"),
    answer      = T.string:describe("User's answer via alc.specify"),
    prior       = T.array_of(T.number):describe("Belief distribution before this round"),
    likelihoods = T.array_of(T.number):describe("Per-hypothesis likelihood from this round's evidence"),
    posterior   = T.array_of(T.number):describe("Belief distribution after Bayesian update"),
    entropy     = T.number:describe("Shannon entropy of posterior in bits"),
})

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task                 = T.string:describe("Initial user request (required)"),
                n_hypotheses         = T.number:is_optional():describe("Number of intent hypotheses to generate (default 5)"),
                max_rounds           = T.number:is_optional():describe("Maximum belief update rounds (default 3)"),
                confidence_threshold = T.number:is_optional():describe("Stop when top hypothesis exceeds this (default 0.7)"),
                prior_tokens         = T.number:is_optional():describe("Max tokens for prior generation (default 600)"),
                diagnose_tokens      = T.number:is_optional():describe("Max tokens per diagnostic question (default 400)"),
                update_tokens        = T.number:is_optional():describe("Max tokens per belief update (default 500)"),
            }),
            -- Result has two disjoint shapes:
            --   success path (normal): full Bayesian trace
            --   error path  (hypothesis parsing failed): { error, raw } only
            -- All fields are optional to accommodate both.
            result = T.shape({
                original_task     = T.string:is_optional():describe("Echo of input task (success path)"),
                specified_task    = T.string:is_optional():describe("LLM-rewritten task aligned to MAP hypothesis (success path)"),
                map_hypothesis    = T.string:is_optional():describe("Description of maximum-a-posteriori hypothesis (success path)"),
                map_confidence    = T.number:is_optional():describe("Posterior probability of MAP hypothesis (success path)"),
                ranked_hypotheses = T.array_of(ranked_hypothesis_shape):is_optional()
                    :describe("All hypotheses sorted by posterior desc (success path)"),
                rounds            = T.number:is_optional():describe("Number of update rounds actually executed (success path)"),
                update_log        = T.array_of(update_log_entry_shape):is_optional()
                    :describe("Per-round Bayesian update trace (success path)"),
                final_entropy     = T.number:is_optional():describe("Shannon entropy of final posterior (success path)"),
                converged         = T.boolean:is_optional():describe("Whether MAP exceeded confidence_threshold before max_rounds (success path)"),
                error             = T.string:is_optional():describe("Set only on prior-parse failure; success path omits this"),
                raw               = T.string:is_optional():describe("Raw prior LLM output; present only on error path"),
            }),
        },
    },
}

--- Parse hypotheses from LLM output.
--- Expects: "H1: description\nH2: description\n..."
local function parse_hypotheses(raw)
    local hypotheses = {}
    for line in raw:gmatch("[^\n]+") do
        local id, desc = line:match("^%s*H(%d+)[:%.]%s*(.+)")
        if not id then
            id, desc = line:match("^%s*(%d+)[%.%)]+%s*(.+)")
        end
        if id and desc and #desc > 5 then
            hypotheses[#hypotheses + 1] = {
                id = tonumber(id),
                description = desc:match("^%s*(.-)%s*$"),
            }
        end
    end
    return hypotheses
end

--- Parse likelihood scores from LLM output.
--- Expects: "H1: 0.8\nH2: 0.2\n..." or "H1: 8/10\nH2: 2/10\n..."
local function parse_likelihoods(raw, n)
    local scores = {}
    for line in raw:gmatch("[^\n]+") do
        local id, score_str = line:match("H(%d+)[:%s]+([%d%.]+)")
        if not id then
            id, score_str = line:match("(%d+)[%.%):%s]+([%d%.]+)")
        end
        if id and score_str then
            local idx = tonumber(id)
            local score = tonumber(score_str)
            if idx and score and idx >= 1 and idx <= n then
                scores[idx] = score
            end
        end
    end

    -- Normalize to probabilities
    local total = 0
    for i = 1, n do
        scores[i] = scores[i] or 1.0 -- uniform fallback
        total = total + scores[i]
    end
    if total > 0 then
        for i = 1, n do
            scores[i] = scores[i] / total
        end
    end

    return scores
end

--- Compute entropy of a probability distribution.
local function entropy(probs)
    local h = 0
    for _, p in ipairs(probs) do
        if p > 0 then
            h = h - p * math.log(p) / math.log(2)
        end
    end
    return h
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local n_hypotheses = ctx.n_hypotheses or 5
    local max_rounds = ctx.max_rounds or 3
    local confidence_threshold = ctx.confidence_threshold or 0.7
    local prior_tokens = ctx.prior_tokens or 600
    local diagnose_tokens = ctx.diagnose_tokens or 400
    local update_tokens = ctx.update_tokens or 500

    -- Phase 1: Generate prior — candidate intent hypotheses
    local prior_raw = alc.llm(
        string.format(
            "User request:\n\"\"\"\n%s\n\"\"\"\n\n"
                .. "Generate exactly %d distinct interpretations of what the user "
                .. "might actually want. Each interpretation should represent a "
                .. "meaningfully different intent or goal.\n\n"
                .. "Cover the space of plausible intents — from the most literal "
                .. "reading to reasonable alternative interpretations.\n\n"
                .. "Format:\n"
                .. "H1: [interpretation]\n"
                .. "H2: [interpretation]\n...\n\n"
                .. "Then assign initial plausibility (0.0-1.0) to each:\n"
                .. "PRIOR: H1: 0.X, H2: 0.X, ...",
            task, n_hypotheses
        ),
        {
            system = "You are a pragmatic linguist. Generate diverse interpretations "
                .. "of user intent. Consider literal meaning, possible implications, "
                .. "common use cases, and context. Each hypothesis should be actionable "
                .. "(specific enough to execute differently from others).",
            max_tokens = prior_tokens,
        }
    )

    local hypotheses = parse_hypotheses(prior_raw)
    if #hypotheses == 0 then
        ctx.result = {
            error = "Failed to generate intent hypotheses",
            raw = prior_raw,
        }
        return ctx
    end

    -- Parse initial prior
    local beliefs = parse_likelihoods(
        prior_raw:match("PRIOR:(.+)") or "",
        #hypotheses
    )

    alc.log("info", string.format(
        "intent_belief: %d hypotheses, initial entropy=%.2f",
        #hypotheses, entropy(beliefs)
    ))

    local update_log = {}

    -- Iterative belief update loop
    for round = 1, max_rounds do
        -- Check convergence
        local max_belief = 0
        local map_idx = 1
        for i, b in ipairs(beliefs) do
            if b > max_belief then
                max_belief = b
                map_idx = i
            end
        end

        if max_belief >= confidence_threshold then
            alc.log("info", string.format(
                "intent_belief: converged at round %d, H%d=%.2f",
                round, map_idx, max_belief
            ))
            break
        end

        -- Phase 2: Diagnose — generate maximally discriminating question
        local belief_display = ""
        for i, h in ipairs(hypotheses) do
            belief_display = belief_display .. string.format(
                "H%d (%.0f%%): %s\n", i, beliefs[i] * 100, h.description
            )
        end

        local question_raw = alc.llm(
            string.format(
                "Current intent hypotheses with belief probabilities:\n%s\n"
                    .. "Design ONE diagnostic question that would maximally distinguish "
                    .. "between the hypotheses. The ideal question is one where different "
                    .. "hypotheses predict different answers.\n\n"
                    .. "The question should:\n"
                    .. "- Be easy for the user to answer\n"
                    .. "- Have answers that clearly favor some hypotheses over others\n"
                    .. "- Not be answerable the same way regardless of true intent\n\n"
                    .. "Format:\n"
                    .. "QUESTION: [your diagnostic question]\n"
                    .. "PREDICTIONS: For each hypothesis, what answer would you expect:\n"
                    .. "H1 predicts: ...\nH2 predicts: ...\n...",
                belief_display
            ),
            {
                system = "You are an information theorist. Design questions that maximize "
                    .. "expected information gain — questions where the answer strongly "
                    .. "updates the belief distribution. Avoid questions that all hypotheses "
                    .. "would answer similarly.",
                max_tokens = diagnose_tokens,
            }
        )

        local question = question_raw:match("QUESTION:%s*(.-)%s*\n")
            or question_raw:match("QUESTION:%s*(.+)")
            or "Could you clarify your intent?"

        -- Request answer via underspecified channel
        local user_answer = alc.specify(
            question,
            { max_tokens = diagnose_tokens }
        )

        -- Phase 3: Update — re-estimate likelihoods given user response
        local update_raw = alc.llm(
            string.format(
                "Intent hypotheses:\n%s\n"
                    .. "Diagnostic question: %s\n"
                    .. "User's answer: %s\n\n"
                    .. "Given the user's answer, re-estimate the likelihood of each "
                    .. "hypothesis. Score each hypothesis from 0.0 (answer contradicts "
                    .. "this intent) to 1.0 (answer strongly supports this intent).\n\n"
                    .. "Format:\n"
                    .. "H1: [score] — [brief reasoning]\n"
                    .. "H2: [score] — [brief reasoning]\n...",
                belief_display, question, user_answer
            ),
            {
                system = "You are a Bayesian reasoner. Update beliefs strictly based on "
                    .. "the evidence (user's answer). A high score means the answer is "
                    .. "highly consistent with that hypothesis. A low score means the "
                    .. "answer is inconsistent. Be precise and avoid anchoring to priors.",
                max_tokens = update_tokens,
            }
        )

        local likelihoods = parse_likelihoods(update_raw, #hypotheses)

        -- Bayesian update: posterior ∝ prior × likelihood
        local posterior = {}
        local total = 0
        for i = 1, #hypotheses do
            posterior[i] = beliefs[i] * likelihoods[i]
            total = total + posterior[i]
        end
        if total > 0 then
            for i = 1, #hypotheses do
                posterior[i] = posterior[i] / total
            end
        end

        update_log[#update_log + 1] = {
            round = round,
            question = question,
            answer = user_answer,
            prior = { table.unpack(beliefs) },
            likelihoods = likelihoods,
            posterior = { table.unpack(posterior) },
            entropy = entropy(posterior),
        }

        beliefs = posterior

        alc.log("info", string.format(
            "intent_belief: round %d, entropy=%.2f, max_belief=%.2f",
            round, entropy(beliefs), math.max(table.unpack(beliefs))
        ))
    end

    -- Select MAP (maximum a posteriori) hypothesis
    local max_belief = 0
    local map_idx = 1
    for i, b in ipairs(beliefs) do
        if b > max_belief then
            max_belief = b
            map_idx = i
        end
    end

    -- Generate final specified task based on MAP hypothesis
    local specified_task = alc.llm(
        string.format(
            "Original request: %s\n\n"
                .. "Most likely intent (%.0f%% confidence):\n%s\n\n"
                .. "Rewrite the original request as a fully-specified task "
                .. "reflecting this intent. Output only the rewritten task.",
            task, max_belief * 100, hypotheses[map_idx].description
        ),
        {
            system = "You are a requirements engineer. Produce an unambiguous "
                .. "task specification that reflects the identified intent.",
            max_tokens = update_tokens,
        }
    )

    -- Build ranked hypotheses
    local ranked = {}
    for i, h in ipairs(hypotheses) do
        ranked[#ranked + 1] = {
            id = i,
            description = h.description,
            belief = beliefs[i],
        }
    end
    table.sort(ranked, function(a, b) return a.belief > b.belief end)

    ctx.result = {
        original_task = task,
        specified_task = specified_task,
        map_hypothesis = hypotheses[map_idx].description,
        map_confidence = max_belief,
        ranked_hypotheses = ranked,
        rounds = #update_log,
        update_log = update_log,
        final_entropy = entropy(beliefs),
        converged = max_belief >= confidence_threshold,
    }
    return ctx
end

M.run = S.instrument(M, "run")

return M
