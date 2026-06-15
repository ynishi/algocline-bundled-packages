--- s1(s1) — Simple test-time scaling via budget forcing
---
--- Lengthens reasoning by appending a "Wait" continuation cue to the
--- thinking trace, prompting the model to extend its reasoning before
--- producing a final answer. Implements a prompt-level approximation of
--- the paper's decoding-time budget forcing (see Caveats).
---
--- ## Usage
---
--- ```lua
--- local s1 = require("s1")
--- return s1.run(ctx)
--- ```
---
--- ## Algorithm
---
--- 1. think_initial: run the first thinking pass on the task.
--- 2. extend: append the wait_literal cue and call the LLM to continue
---    reasoning. Repeat up to max_extensions rounds.
--- 3. finalize: append the final_answer_suffix to force answer extraction.
---
--- ## Caveats
---
--- This is a **prompt-level approximation** of the paper's budget forcing,
--- not a literal reimplementation. The paper performs decoding-time token
--- suppression (refusing to emit the end-of-thinking delimiter) plus
--- in-stream "Wait" injection during a single generation pass. The
--- algocline `alc.llm` API exposes only prompt-level access (no token
--- suppression, no in-stream continuation), so each extension is a fresh
--- LLM round trip that takes the accumulated trace as context.
---
--- Paper §3 treats "Wait" as plain text (not a special token), and the
--- Qwen chat template delimiters are themselves plain string boundaries,
--- so the prompt-level approximation preserves the paper's core intent
--- — extending the reasoning trace before answering. The trade-off is a
--- one round-trip latency per extension and that the LLM may, in its
--- continuation, generate a "Final Answer:" early; callers requiring
--- literal decoding-time control should drive the underlying provider
--- API directly rather than use this pkg.
---
--- The original paper also pairs budget forcing with SFT on the s1K
--- dataset (Qwen2.5-32B-Instruct base). This pkg only implements the
--- inference-time intervention; pairing with a tuned base model is the
--- caller's responsibility.
---
--- ## References
---
--- - Muennighoff, N., Yang, Z., Shi, W., Li, X. L., Fei-Fei, L.,
---   Hajishirzi, H., Zettlemoyer, L., Liang, P., Candès, E., Hashimoto, T.
---   (2025). "s1: Simple test-time scaling". arXiv:2501.19393 §3
---   (Budget Forcing) / §4 (s1K data) / Table 4 (Wait token ablation).
---   https://arxiv.org/abs/2501.19393
--- - Official code + data: https://github.com/simplescaling/s1

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "s1",
    version = "0.1.0",
    description = "Budget forcing — extends reasoning via 'Wait' continuation cues (prompt-level approximation of s1).",
    category = "refinement",
    alc_shapes_compat = "^0.25",
}

-- Default values exposed as module locals so spec tests and callers can
-- reference the same literals as the input shape descriptions. Each
-- default's provenance is recorded inline so future readers can verify
-- the source against Muennighoff et al. (2025) §3 / Table 4.

-- (L) Paper §3 / Table 4 ablation winner over "Alternatively" / "Hmm".
local DEFAULT_WAIT_LITERAL = "Wait"

-- (I) Paper §3 reports experiments at 2 / 4 / 6 extensions; the middle
-- value is taken as a sensible default that balances scaling vs cost.
local DEFAULT_MAX_EXTENSIONS = 4

-- (L) Paper §3 literal forced suffix used for early-exit answer
-- extraction at the budget boundary.
local DEFAULT_FINAL_ANSWER_SUFFIX = "Final Answer:"

-- (X) Implementation choice — paper does not specify a token cap (it
-- relies on chat-template delimiters during decoding). 2000 sized for
-- typical chain-of-thought completions; callers should override for
-- longer reasoning.
local DEFAULT_MAX_THINKING_TOKENS = 2000

-- (X) Implementation choice — generation budget for the final answer
-- pass after thinking is exhausted. Kept smaller than thinking budget
-- since answer is expected to be concise.
local DEFAULT_FINAL_ANSWER_TOKENS = 500

---@type AlcSpec
M.spec = {
    entries = {
        think_initial = {
            input = T.shape({
                task = T.string:describe("Question or task to reason about"),
                max_thinking_tokens = T.number:is_optional():describe(
                    "Token budget for the initial thinking pass (default: 2000; implementation choice — paper does not specify a token cap, sized for typical chain-of-thought completions)"
                ),
            }),
            result = T.shape({
                trace = T.string:describe("Initial reasoning trace produced by the model"),
            }),
        },
        extend = {
            input = T.shape({
                task = T.string:describe("Original question or task (used as anchor for continuation)"),
                trace = T.string:describe("Accumulated reasoning trace so far"),
                wait_literal = T.string:is_optional():describe(
                    'Literal string appended to the trace to cue continued reasoning (default: "Wait"; paper §3 / Table 4 ablation winner over "Alternatively" / "Hmm")'
                ),
                max_thinking_tokens = T.number:is_optional():describe(
                    "Token budget for the continuation pass (default: 2000; implementation choice)"
                ),
            }),
            result = T.shape({
                trace = T.string:describe("Trace extended with the wait cue and continuation"),
                continuation = T.string:describe("Just the new continuation text appended in this extension"),
            }),
        },
        finalize = {
            input = T.shape({
                task = T.string:describe("Original question or task"),
                trace = T.string:describe("Final reasoning trace before answer extraction"),
                final_answer_suffix = T.string:is_optional():describe(
                    'Suffix that forces answer extraction at budget exhaustion (default: "Final Answer:"; paper §3 literal)'
                ),
                final_answer_tokens = T.number:is_optional():describe(
                    "Token budget for the final answer extraction pass (default: 500; implementation choice — answer expected concise)"
                ),
            }),
            result = T.shape({
                final_answer = T.string:describe("Extracted final answer after applying the final_answer_suffix"),
            }),
        },
        run = {
            input = T.shape({
                task = T.string:describe("Question or task to reason about"),
                max_extensions = T.number:is_optional():describe(
                    "Maximum number of Wait extensions to attempt before forced finalization (default: 4; paper §3 experiments span 2 / 4 / 6, middle value chosen)"
                ),
                wait_literal = T.string:is_optional():describe(
                    'Literal string appended each extension to cue continued reasoning (default: "Wait"; paper §3 / Table 4 ablation winner over "Alternatively" / "Hmm")'
                ),
                final_answer_suffix = T.string:is_optional():describe(
                    'Suffix that forces answer extraction at budget exhaustion (default: "Final Answer:"; paper §3 literal)'
                ),
                max_thinking_tokens = T.number:is_optional():describe(
                    "Token budget for each thinking pass — initial and each extension (default: 2000; implementation choice — paper does not specify, sized for typical CoT)"
                ),
                final_answer_tokens = T.number:is_optional():describe(
                    "Token budget for the final answer extraction pass (default: 500; implementation choice)"
                ),
            }),
            result = T.shape({
                final_answer = T.string:describe("Final answer extracted after thinking + extensions + finalize"),
                trace = T.string:describe("Full reasoning trace including initial pass and all Wait extensions"),
                extensions_used = T.number:describe("Number of Wait extensions actually executed (0 to max_extensions)"),
            }),
        },
    },
}

-- ---- pure helper LLM calls (one round trip each) ----

local function call_initial_think(task, max_tokens)
    return alc.llm(
        string.format(
            "Question:\n%s\n\nThink through this step by step. Reason carefully before answering. "
                .. "Do not produce a final answer yet — only the reasoning trace.",
            task
        ),
        {
            system = "You are a careful reasoner. Write out your reasoning step by step. "
                .. "Stop before stating a final answer.",
            max_tokens = max_tokens,
        }
    )
end

local function call_extend(task, trace, wait_literal, max_tokens)
    return alc.llm(
        string.format(
            "Question:\n%s\n\nReasoning so far:\n%s\n\n%s",
            task, trace, wait_literal
        ),
        {
            system = "You are continuing a reasoning trace. The trace so far may be incomplete "
                .. "or may contain a tentative conclusion that deserves another look. "
                .. "Continue reasoning from where it leaves off. Do not produce a final answer yet.",
            max_tokens = max_tokens,
        }
    )
end

local function call_finalize(task, trace, final_answer_suffix, max_tokens)
    return alc.llm(
        string.format(
            "Question:\n%s\n\nFull reasoning trace:\n%s\n\n%s",
            task, trace, final_answer_suffix
        ),
        {
            system = "You are concluding a reasoning chain. Based on the trace above, "
                .. "produce a concise final answer.",
            max_tokens = max_tokens,
        }
    )
end

-- ---- entries ----

---@param ctx AlcCtx
---@return AlcCtx
function M.think_initial(ctx)
    local task = ctx.task or error("ctx.task is required")
    local max_tokens = ctx.max_thinking_tokens or DEFAULT_MAX_THINKING_TOKENS

    local trace = call_initial_think(task, max_tokens)
    ctx.result = { trace = trace }
    return ctx
end

---@param ctx AlcCtx
---@return AlcCtx
function M.extend(ctx)
    local task = ctx.task or error("ctx.task is required")
    local trace = ctx.trace or error("ctx.trace is required")
    local wait_literal = ctx.wait_literal or DEFAULT_WAIT_LITERAL
    local max_tokens = ctx.max_thinking_tokens or DEFAULT_MAX_THINKING_TOKENS

    local continuation = call_extend(task, trace, wait_literal, max_tokens)
    -- The trace grows by inserting the wait cue and the new continuation
    -- text. The wait literal goes into the trace literally so subsequent
    -- extensions see it as part of the reasoning context.
    local new_trace = trace .. "\n" .. wait_literal .. "\n" .. continuation

    ctx.result = {
        trace = new_trace,
        continuation = continuation,
    }
    return ctx
end

---@param ctx AlcCtx
---@return AlcCtx
function M.finalize(ctx)
    local task = ctx.task or error("ctx.task is required")
    local trace = ctx.trace or error("ctx.trace is required")
    local suffix = ctx.final_answer_suffix or DEFAULT_FINAL_ANSWER_SUFFIX
    local max_tokens = ctx.final_answer_tokens or DEFAULT_FINAL_ANSWER_TOKENS

    local final_answer = call_finalize(task, trace, suffix, max_tokens)
    ctx.result = { final_answer = final_answer }
    return ctx
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local max_extensions = ctx.max_extensions or DEFAULT_MAX_EXTENSIONS
    local wait_literal = ctx.wait_literal or DEFAULT_WAIT_LITERAL
    local final_answer_suffix = ctx.final_answer_suffix or DEFAULT_FINAL_ANSWER_SUFFIX
    local max_thinking_tokens = ctx.max_thinking_tokens or DEFAULT_MAX_THINKING_TOKENS
    local final_answer_tokens = ctx.final_answer_tokens or DEFAULT_FINAL_ANSWER_TOKENS

    -- Phase 1: initial thinking pass
    local trace = call_initial_think(task, max_thinking_tokens)

    -- Phase 2: Wait extensions
    local extensions_used = 0
    for i = 1, max_extensions do
        local continuation = call_extend(task, trace, wait_literal, max_thinking_tokens)
        trace = trace .. "\n" .. wait_literal .. "\n" .. continuation
        extensions_used = extensions_used + 1
        alc.log("info", string.format(
            "s1: extension %d/%d (wait_literal=%q)", i, max_extensions, wait_literal
        ))
    end

    -- Phase 3: forced finalization
    local final_answer = call_finalize(task, trace, final_answer_suffix, final_answer_tokens)

    ctx.result = {
        final_answer = final_answer,
        trace = trace,
        extensions_used = extensions_used,
    }
    return ctx
end

-- Malli-style self-decoration (see alc_shapes/README). inline T.shape
-- for both input and result; wrapper validates in ALC_SHAPE_CHECK=1.
M.think_initial = S.instrument(M, "think_initial")
M.extend = S.instrument(M, "extend")
M.finalize = S.instrument(M, "finalize")
M.run = S.instrument(M, "run")

return M
