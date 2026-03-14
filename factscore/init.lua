--- FActScore — atomic claim decomposition and per-claim verification
---
--- Extracts atomic claims from text, then independently verifies each
--- claim in parallel. Produces a factual precision score and annotated results.
---
--- Based on: Min et al., "FActScore: Fine-grained Atomic Evaluation of
--- Factual Precision in Long Form Text Generation" (2023, arXiv:2305.14251)
---
--- Usage:
---   local factscore = require("factscore")
---   return factscore.run(ctx)
---
--- ctx.text (required): The text to fact-check
--- ctx.context: Optional reference context for verification
--- ctx.verify_tokens: Max tokens per claim verification (default: 200)
--- ctx.extract_tokens: Max tokens for claim extraction (default: 500)

local M = {}

M.meta = {
    name = "factscore",
    version = "0.1.0",
    description = "Atomic claim decomposition — per-claim factual verification with scoring",
    category = "validation",
}

--- Parse extracted claims from LLM output.
--- Expects numbered list: "1. claim\n2. claim\n..."
local function parse_claims(raw)
    local claims = {}
    for line in raw:gmatch("[^\n]+") do
        local _, claim = line:match("^%s*(%d+)[%.%)%s]+(.+)")
        if claim then
            claims[#claims + 1] = claim:match("^%s*(.-)%s*$")
        end
    end
    return claims
end

function M.run(ctx)
    local text = ctx.text or error("ctx.text is required")
    local context = ctx.context
    local verify_tokens = ctx.verify_tokens or 200
    local extract_tokens = ctx.extract_tokens or 500

    -- Phase 1: Extract atomic claims
    local extraction = alc.llm(
        string.format(
            "Text to analyze:\n\"\"\"\n%s\n\"\"\"\n\n"
                .. "Decompose this text into atomic claims. Each claim should be:\n"
                .. "- A single, verifiable factual statement\n"
                .. "- Self-contained (understandable without the original text)\n"
                .. "- As specific as possible (include names, dates, numbers)\n\n"
                .. "Output a numbered list:\n"
                .. "1. [atomic claim]\n2. [atomic claim]\n...",
            text
        ),
        {
            system = "You are a precise fact-checker. Decompose text into the smallest "
                .. "possible factual units. Each claim should be independently verifiable. "
                .. "Do not merge multiple facts into one claim. Do not include opinions "
                .. "or subjective statements — only factual claims.",
            max_tokens = extract_tokens,
        }
    )

    local claims = parse_claims(extraction)

    if #claims == 0 then
        ctx.result = {
            score = 1.0,
            claims = {},
            supported = 0,
            unsupported = 0,
            uncertain = 0,
            total = 0,
        }
        return ctx
    end

    alc.log("info", string.format("factscore: %d atomic claims extracted", #claims))

    -- Phase 2: Verify each claim in parallel
    local context_block = ""
    if context then
        context_block = string.format(
            "\n\nReference context:\n\"\"\"\n%s\n\"\"\"", context
        )
    end

    local verdicts = alc.map(claims, function(claim, i)
        return alc.llm(
            string.format(
                "Claim to verify:\n\"%s\"%s\n\n"
                    .. "Evaluate this claim's factual accuracy.\n\n"
                    .. "Answer with exactly one of:\n"
                    .. "SUPPORTED — the claim is factually correct\n"
                    .. "UNSUPPORTED — the claim is factually incorrect or misleading\n"
                    .. "UNCERTAIN — cannot determine with confidence\n\n"
                    .. "Then provide a one-sentence justification.",
                claim, context_block
            ),
            {
                system = "You are a rigorous fact-checker. Evaluate claims strictly. "
                    .. "Only mark SUPPORTED if you are confident the claim is accurate. "
                    .. "Mark UNCERTAIN if you lack sufficient knowledge to verify.",
                max_tokens = verify_tokens,
            }
        )
    end)

    -- Phase 3: Score
    local results = {}
    local supported = 0
    local unsupported = 0
    local uncertain = 0

    for i, verdict in ipairs(verdicts) do
        local status
        if verdict:match("UNSUPPORTED") then
            status = "unsupported"
            unsupported = unsupported + 1
        elseif verdict:match("UNCERTAIN") then
            status = "uncertain"
            uncertain = uncertain + 1
        else
            status = "supported"
            supported = supported + 1
        end

        local justification = verdict:match("\n(.+)") or ""
        justification = justification:match("^%s*(.-)%s*$") or ""

        results[#results + 1] = {
            claim = claims[i],
            status = status,
            justification = justification,
        }
    end

    local total = #claims
    -- Score: supported / (supported + unsupported), uncertain excluded
    local decisive = supported + unsupported
    local score = decisive > 0 and (supported / decisive) or 1.0

    alc.log("info", string.format(
        "factscore: %.2f (%d supported, %d unsupported, %d uncertain)",
        score, supported, unsupported, uncertain
    ))

    ctx.result = {
        score = score,
        claims = results,
        supported = supported,
        unsupported = unsupported,
        uncertain = uncertain,
        total = total,
    }
    return ctx
end

return M
