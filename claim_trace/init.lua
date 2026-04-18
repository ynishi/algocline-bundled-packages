--- claim_trace — Span-level evidence attribution for LLM outputs
---
--- For each claim in an LLM-generated answer, traces it back to specific
--- spans in the source context. Unlike factscore (which only verifies
--- correctness), claim_trace provides provenance: which part of the source
--- supports each claim, enabling transparent attribution.
---
--- Based on: "Attributed QA: Evaluation and Modeling for Attributed
---            Large Language Models" (Bohnet et al., arXiv 2212.08037, 2022)
---            + "ALCE: Attributed Language Model Evaluation"
---            (Gao et al., arXiv 2305.14627, 2023)
---
--- Pipeline:
---   Step 1: decompose  — extract atomic claims from the answer
---   Step 2: attribute  — for each claim, find supporting span(s) in source
---   Step 3: score      — compute attribution coverage and precision
---
--- Usage:
---   local claim_trace = require("claim_trace")
---   return claim_trace.run(ctx)
---
--- ctx.task (required): The original question/task
--- ctx.answer: Pre-supplied answer to attribute (default: nil → auto-generate)
--- ctx.sources (required): Source text(s) to trace claims against
---     - string: single source document
---     - table of strings: multiple source documents
--- ctx.extract_tokens: Max tokens for claim extraction (default: 500)
--- ctx.trace_tokens: Max tokens per claim attribution (default: 300)
--- ctx.gen_tokens: Max tokens for answer generation (default: 600)

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "claim_trace",
    version = "0.1.0",
    description = "Span-level evidence attribution — trace each claim to supporting source spans for transparent provenance",
    category = "attribution",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task           = T.string:describe("The original question/task"),
                answer         = T.string:is_optional():describe("Pre-supplied answer to attribute (auto-generated if nil)"),
                sources        = T.any:describe("Source text(s): single string or array of strings"),
                extract_tokens = T.number:is_optional():describe("Max tokens for claim extraction (default: 500)"),
                trace_tokens   = T.number:is_optional():describe("Max tokens per claim attribution (default: 300)"),
                gen_tokens     = T.number:is_optional():describe("Max tokens for answer generation (default: 600)"),
            }),
            result = T.shape({
                answer            = T.string:describe("Answer whose claims were traced (auto-generated or passed in)"),
                claims            = T.array_of(T.shape({
                    claim        = T.string:describe("Atomic claim text"),
                    status       = T.string:describe("'supported' | 'partial' | 'unsupported'"),
                    span         = T.string:describe("Quoted supporting span (empty when unsupported)"),
                    source_index = T.number:is_optional():describe("1-based source document index (nil for single source)"),
                    reasoning    = T.string:describe("Attribution reasoning text"),
                    raw          = T.string:describe("Raw attributor output"),
                })):describe("Per-claim attribution records (empty when no claims extracted)"),
                attribution_score = T.number:describe("(supported + 0.5*partial) / total; 1.0 when no claims"),
                coverage          = T.number:describe("(supported + partial) / total; 1.0 when no claims"),
                supported         = T.number:describe("Count of SUPPORTED claims"),
                partial           = T.number:describe("Count of PARTIAL claims"),
                unsupported       = T.number:describe("Count of UNSUPPORTED claims"),
                total             = T.number:describe("Total extracted claims"),
                sources_count     = T.number:is_optional():describe("Number of source documents (omitted on empty-claims short-circuit)"),
            }),
        },
    },
}

--- Parse numbered claims from extraction output.
local function parse_claims(raw)
    local claims = {}
    for line in raw:gmatch("[^\n]+") do
        local _, claim = line:match("^%s*(%d+)[%.%)%s]+(.+)")
        if claim then
            claim = claim:match("^%s*(.-)%s*$")
            if #claim > 5 then
                claims[#claims + 1] = claim
            end
        end
    end
    return claims
end

--- Parse attribution result into structured form.
--- Expected format:
---   ATTRIBUTION: SUPPORTED | PARTIAL | UNSUPPORTED
---   SPAN: "quoted text from source"
---   SOURCE: N (if multiple sources)
---   REASONING: explanation
local function parse_attribution(raw)
    local attr = raw:upper():match("ATTRIBUTION:%s*(%a+)")
    local status
    if attr then
        if attr:match("SUPPORT") then
            status = "supported"
        elseif attr:match("PARTIAL") then
            status = "partial"
        else
            status = "unsupported"
        end
    else
        -- Fallback heuristics
        local upper = raw:upper()
        if upper:match("UNSUPPORTED") or upper:match("NOT FOUND") or upper:match("NO EVIDENCE") then
            status = "unsupported"
        elseif upper:match("PARTIAL") then
            status = "partial"
        else
            status = "supported"
        end
    end

    -- Extract quoted span
    local span = raw:match('SPAN:%s*"(.-)"')
        or raw:match('SPAN:%s*(.-)%s*\n')
        or ""

    -- Extract source index (for multi-source)
    local source_idx = tonumber(raw:match("SOURCE:%s*(%d+)"))

    -- Extract reasoning
    local reasoning = raw:match("REASONING:%s*(.-)$")
        or raw:match("\n([^\n]+)$")
        or ""
    reasoning = reasoning:match("^%s*(.-)%s*$") or ""

    return {
        status = status,
        span = span,
        source_index = source_idx,
        reasoning = reasoning,
    }
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local sources = ctx.sources or error("ctx.sources is required")
    local extract_tokens = ctx.extract_tokens or 500
    local trace_tokens = ctx.trace_tokens or 300
    local gen_tokens = ctx.gen_tokens or 600

    -- Normalize sources to table
    if type(sources) == "string" then
        sources = { sources }
    end

    -- ─── Step 0 (optional): Generate answer if not provided ───
    local answer = ctx.answer
    if not answer then
        local source_block = {}
        for i, src in ipairs(sources) do
            source_block[#source_block + 1] = string.format(
                "Source %d:\n\"\"\"\n%s\n\"\"\"", i, src
            )
        end

        answer = alc.llm(
            string.format(
                "Task: %s\n\n%s\n\n"
                    .. "Answer the task based on the provided sources. "
                    .. "Be specific and reference information from the sources.",
                task, table.concat(source_block, "\n\n")
            ),
            {
                system = "You are an expert. Answer based on the provided sources. "
                    .. "Be accurate and specific.",
                max_tokens = gen_tokens,
            }
        )
        alc.log("info", string.format(
            "claim_trace: generated answer (%d chars)", #answer
        ))
    end

    -- ─── Step 1: Decompose answer into atomic claims ───
    local extraction = alc.llm(
        string.format(
            "Answer to decompose:\n\"\"\"\n%s\n\"\"\"\n\n"
                .. "Decompose this answer into atomic claims. Each claim should be:\n"
                .. "- A single, verifiable factual statement\n"
                .. "- Self-contained (understandable without context)\n"
                .. "- As specific as possible (names, dates, numbers)\n\n"
                .. "Output a numbered list:\n"
                .. "1. [atomic claim]\n2. [atomic claim]\n...",
            answer
        ),
        {
            system = "You are a precise analyst. Decompose text into the smallest "
                .. "possible factual units. Each claim should be independently "
                .. "verifiable against source material.",
            max_tokens = extract_tokens,
        }
    )

    local claims = parse_claims(extraction)

    if #claims == 0 then
        alc.log("warn", "claim_trace: no claims extracted from answer")
        ctx.result = {
            answer = answer,
            claims = {},
            attribution_score = 1.0,
            coverage = 1.0,
            supported = 0,
            partial = 0,
            unsupported = 0,
            total = 0,
        }
        return ctx
    end

    alc.log("info", string.format(
        "claim_trace: %d atomic claims extracted", #claims
    ))

    -- ─── Step 2: Attribute each claim to source spans ───
    local source_block = {}
    for i, src in ipairs(sources) do
        source_block[#source_block + 1] = string.format(
            "Source %d:\n\"\"\"\n%s\n\"\"\"", i, src
        )
    end
    local sources_text = table.concat(source_block, "\n\n")

    local attributions = alc.map(claims, function(claim)
        return alc.llm(
            string.format(
                "Claim to trace:\n\"%s\"\n\n"
                    .. "%s\n\n"
                    .. "Find the specific span in the source(s) that supports this claim.\n\n"
                    .. "Respond in this exact format:\n"
                    .. "ATTRIBUTION: SUPPORTED | PARTIAL | UNSUPPORTED\n"
                    .. "SPAN: \"exact quoted text from source\"\n"
                    .. "SOURCE: [source number]\n"
                    .. "REASONING: [why this span supports/doesn't support the claim]",
                claim, sources_text
            ),
            {
                system = "You are an evidence tracer. For each claim, find the specific "
                    .. "text span in the source that supports it. SUPPORTED = claim is "
                    .. "fully backed by a source span. PARTIAL = claim is partially backed "
                    .. "or requires inference. UNSUPPORTED = no source evidence found. "
                    .. "Quote the exact supporting text.",
                max_tokens = trace_tokens,
            }
        )
    end)

    -- ─── Step 3: Score attribution ───
    local results = {}
    local supported = 0
    local partial = 0
    local unsupported = 0

    for i, raw_attr in ipairs(attributions) do
        local parsed = parse_attribution(raw_attr)
        parsed.claim = claims[i]
        parsed.raw = raw_attr

        if parsed.status == "supported" then
            supported = supported + 1
        elseif parsed.status == "partial" then
            partial = partial + 1
        else
            unsupported = unsupported + 1
        end

        results[#results + 1] = parsed
    end

    local total = #claims
    -- Attribution score: (supported + 0.5*partial) / total
    local attribution_score = total > 0
        and (supported + 0.5 * partial) / total
        or 1.0

    -- Coverage: fraction of claims with any source evidence
    local coverage = total > 0
        and (supported + partial) / total
        or 1.0

    alc.log("info", string.format(
        "claim_trace: attribution=%.2f, coverage=%.2f (%d supported, %d partial, %d unsupported)",
        attribution_score, coverage, supported, partial, unsupported
    ))

    ctx.result = {
        answer = answer,
        claims = results,
        attribution_score = attribution_score,
        coverage = coverage,
        supported = supported,
        partial = partial,
        unsupported = unsupported,
        total = total,
        sources_count = #sources,
    }
    return ctx
end

-- Malli-style self-decoration (see alc_shapes/README). inline T.shape
-- for both input and result; wrapper validates in ALC_SHAPE_CHECK=1.
M.run = S.instrument(M, "run")

return M
