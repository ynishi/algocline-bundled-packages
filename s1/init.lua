--- s1(s1) — Simple test-time scaling via budget forcing
---
--- Prompt-level approximation of Muennighoff et al. 2025 §3 budget
--- forcing. The paper's mechanism is decoding-time token intervention
--- in a single generation stream; this pkg approximates it at the
--- prompt level (multiple LLM round-trips with accumulated trace text)
--- because the algocline `alc.llm` API exposes only system / user /
--- assistant roles and no token-level logit control.
---
--- ## Algorithm (paper §3, two mechanisms preserved at text level)
---
--- 1. **Minimum Token Enforcement (lengthen)** — paper §3 literal:
---    "suppress the generation of the end-of-thinking token delimiter
---    and optionally append the string 'Wait'". This pkg approximates
---    by treating the end of each LLM round-trip as the analogue of
---    the model emitting `</think>`, then appending the literal
---    `wait_literal` and re-invoking the LLM with the accumulated
---    trace. When the continuation leaks a final-answer-shaped
---    closing (paper's `</think>` logit mask sets probability 0; the
---    prompt level cannot, so leakage is non-zero), the leaked tail is
---    stripped before the trace accumulates so that the next round
---    still receives a `Wait`-cued non-finalized trace.
---
--- 2. **Maximum Token Enforcement (early exit)** — paper §3 literal:
---    "appending the end-of-thinking token delimiter and 'Final
---    Answer:' to early exit". This pkg approximates by tracking
---    cumulative thinking-trace length with a chars-per-token
---    heuristic; once `max_total_thinking_tokens` (T_max) is exceeded,
---    further `Wait` extensions are skipped and `finalize` is invoked
---    immediately with the `final_answer_suffix`. The T_max knob is
---    caller opt-in (default `nil` = disabled); see "Implementation
---    choices" below for the rationale.
---
--- Phase order:
---
--- 1. `think_initial` — first thinking pass (no Wait yet).
--- 2. `extend` × K — append `wait_literal` cue and continue the trace,
---    repeated up to `max_extensions` times or until T_max is reached.
--- 3. `finalize` — append `final_answer_suffix` and extract the answer.
---
--- `run` uses **nested dispatch** (calls `M.think_initial` /
--- `M.extend` / `M.finalize` through the `M` table, not via the local
--- closures) so the `S.instrument` wrappers fire on every sub-call;
--- this catches a bad intermediate shape before it leaks into the
--- outer result (`alc_shapes/README` §Producer usage).
---
--- ## Usage
---
--- ```lua
--- local s1 = require("s1")
--- return s1.run({
---     task = "..." ,
---     max_extensions = 4,            -- paper K (default 4; impl choice)
---     max_total_thinking_tokens = 8000, -- paper T_max (opt-in)
--- })
--- ```
---
--- ## Implementation choices (paper does not prescribe; spelled out)
---
--- Each default below records its source explicitly in its inline
--- comment: paper-literal citations with section refs, industry-
--- standard heuristics with source links, or implementation-choice
--- rationale spelled out. **No default is silently chosen**; readers
--- should be able to verify each value against the paper or a cited
--- norm.
---
---  - `wait_literal` = "Wait" — Muennighoff 2025 §3 / Table 4
---    ablation winner over "Alternatively" / "Hmm".
---  - `final_answer_suffix` = "Final Answer:" — Muennighoff
---    2025 §3 literal forced suffix for early-exit answer extraction.
---  - `max_extensions` = 4 — paper §3 reports experiments at
---    K ∈ {2, 4, 6}; 4 chosen as the mid-range default balancing
---    scaling effect vs round-trip cost. Paper does not prescribe a
---    default.
---  - `max_thinking_tokens` = 2000 — per round-trip generation
---    cap. Paper has no separate per-call cap (paper runs single-pass
---    decoding with chat-template delimiters). 2000 sized for typical
---    chain-of-thought completions; callers should override for long
---    reasoning.
---  - `final_answer_tokens` = 500 — generation cap for the
---    finalize pass. Paper has no separate cap (finalize is a
---    continuation of the thinking stream). 500 sized for concise
---    answers; override for verbose answers.
---  - `max_total_thinking_tokens` = nil (disabled) — paper's
---    Maximum Token Enforcement (T_max) knob. Paper ablates total
---    thinking budget but no canonical default literal is reported in
---    §3, so this pkg deliberately ships T_max as caller opt-in to
---    avoid imposing an arbitrary silent budget cap. When set, the
---    cumulative thinking-trace token estimate exceeding T_max
---    triggers an early finalize (Wait skip + answer extraction). Set
---    explicitly (e.g. `max_extensions * max_thinking_tokens`) for
---    paper-faithful Maximum Token Enforcement behavior.
---  - `chars_per_token` = 4 — OpenAI tokenizer rough heuristic
---    for English / ASCII text (~4 chars per token, see
---    https://platform.openai.com/tokenizer guidance). Used only for
---    the T_max cumulative estimate; `alc.llm` exposes no token count.
---    Callers in CJK-heavy domains should override (~2 for Japanese /
---    Chinese).
---  - `leak_patterns` = {"Final Answer:", "Final answer:", "The answer
---    is", "答え:", "答えは"} — prompt-level analogue of paper
---    §3 `</think>` logit suppression. Paper sets emit-delimiter
---    probability to 0 at decoding time; prompt-level cannot guarantee
---    P(leak) = 0, so each `extend` continuation is scanned for
---    these closing phrases and the leaked tail is stripped before
---    accumulating into the trace. Patterns chosen to cover common
---    English / Japanese finalization forms; not exhaustive — callers
---    with domain-specific closings should override.
---  - `system_prompt` = unified single-persona — paper
---    Qwen2.5-32B-s1 is finetuned to switch personas at chat-template
---    token boundaries (`<|im_start|>think` / `<|im_start|>answer`).
---    The OpenAI / Anthropic API exposes only system / user /
---    assistant roles, so this pkg approximates the single-coherent-
---    persona invariant by sending the same system prompt across all
---    three phases. Phase distinction is delegated entirely to the
---    user-side literal suffix (`Wait` / `Final Answer:`) so the
---    persona conditioning does not drift between phases. The literal
---    is fixed (not caller-overridable in v0.2.x); override via a
---    custom call_* helper if needed.
---
--- ## Caveats
---
--- This pkg is a **prompt-level approximation** of paper §3, not a
--- literal reimplementation. The paper performs decoding-time logit
--- intervention (delimiter suppression + in-stream "Wait" injection)
--- inside a single generation pass with a shared KV cache. The
--- algocline `alc.llm` API exposes only prompt-level access (no
--- logit mask, no in-stream continuation), so each extension is a
--- fresh round-trip that takes the accumulated trace as context.
---
--- The paper also pairs budget forcing with SFT on the s1K dataset
--- (Qwen2.5-32B-Instruct base). This pkg implements only the
--- inference-time intervention; pairing with a tuned base model is
--- the caller's responsibility.
---
--- ## References
---
--- - Muennighoff, N., Yang, Z., Shi, W., Li, X. L., Fei-Fei, L.,
---   Hajishirzi, H., Zettlemoyer, L., Liang, P., Candès, E., Hashimoto,
---   T. (2025). "s1: Simple test-time scaling". arXiv:2501.19393 §3
---   (Budget Forcing — Minimum / Maximum Token Enforcement) / §4 (s1K
---   data) / Table 4 (Wait token ablation).
---   https://arxiv.org/abs/2501.19393
--- - Official code + data: https://github.com/simplescaling/s1

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "s1",
    version = "0.2.0",
    description = "Budget forcing — prompt-level approximation of Muennighoff 2025 §3 (Minimum + Maximum Token Enforcement).",
    category = "refinement",
    alc_shapes_compat = "^0.25",
}

-- ---- Default values ----
-- Every default carries a provenance tag in its inline comment:
--   (L) paper literal       — Muennighoff 2025 reports this exact value
--   (I) industry standard   — widely cited norm with source URL / paper
--   (X) implementation choice — paper does not prescribe; rationale given
-- No tag is implicit; readers should be able to follow each comment to
-- its source. The docstring above mirrors these tags so projections
-- emit the same provenance.

-- (L) Muennighoff 2025 §3 / Table 4 ablation winner over
-- "Alternatively" / "Hmm".
local DEFAULT_WAIT_LITERAL = "Wait"

-- (X) Implementation choice — Muennighoff 2025 §3 reports wait-count
-- experiments at K ∈ {2, 4, 6}; 4 chosen as the mid-range default
-- balancing scaling effect vs API round-trip cost. Paper does not
-- prescribe a default.
local DEFAULT_MAX_EXTENSIONS = 4

-- (L) Muennighoff 2025 §3 literal forced suffix for early-exit answer
-- extraction at the budget boundary.
local DEFAULT_FINAL_ANSWER_SUFFIX = "Final Answer:"

-- (X) Implementation choice — per round-trip generation cap for each
-- thinking pass (initial + each extension). Muennighoff 2025 does not
-- specify a per-call cap (paper runs single-pass decoding with
-- chat-template delimiters). 2000 sized for typical chain-of-thought
-- completions; callers should override for long reasoning.
local DEFAULT_MAX_THINKING_TOKENS = 2000

-- (X) Implementation choice — generation cap for the finalize pass.
-- Paper has no separate cap (finalize is a continuation of the
-- thinking stream). 500 sized for concise answers.
local DEFAULT_FINAL_ANSWER_TOKENS = 500

-- (X) Implementation choice — Muennighoff 2025 §3 Maximum Token
-- Enforcement (T_max). nil = disabled = caller opt-in. Paper ablates
-- total thinking budget but no canonical literal default appears in
-- §3, so this pkg ships T_max disabled by default to avoid imposing
-- an arbitrary silent cap. When set, cumulative trace tokens
-- exceeding T_max trigger an early finalize (Wait skip + answer
-- extraction). For paper-faithful Maximum Token Enforcement, callers
-- typically set T_max = max_extensions * max_thinking_tokens or some
-- explicit cumulative cap.
local DEFAULT_MAX_TOTAL_THINKING_TOKENS = nil

-- (I) Industry-standard rough English tokenization heuristic
-- (~4 chars per token for ASCII / Latin text, see
-- https://platform.openai.com/tokenizer guidance "1 token ~= 4 chars
-- in English"). Used only for the prompt-level T_max cumulative
-- estimate; `alc.llm` exposes no token count. CJK-heavy domains
-- should override (~2 for Japanese / Chinese).
local DEFAULT_CHARS_PER_TOKEN = 4

-- (X) Implementation choice — prompt-level analogue of paper §3
-- `</think>` logit suppression. Paper sets emit-delimiter probability
-- to 0 at decoding time (physical prevent); prompt-level cannot
-- guarantee P(leak) = 0. Each extension continuation is scanned for
-- these closing phrases and the leaked tail is stripped before
-- accumulating into the trace. Patterns chosen to cover common
-- English / Japanese finalization forms; not exhaustive — callers
-- with domain-specific closings should override via the
-- `leak_patterns` entry knob.
local DEFAULT_LEAK_PATTERNS = {
    "Final Answer:",
    "Final answer:",
    "The answer is",
    "答え:",
    "答えは",
}

-- (X) Implementation choice — unified single-persona system prompt
-- across all three phases. Paper Qwen2.5-32B-s1 is finetuned to
-- switch personas at chat-template token boundaries
-- (`<|im_start|>think` / `<|im_start|>answer`); OpenAI / Anthropic
-- API exposes only system / user / assistant roles, so this pkg
-- holds the system prompt constant and delegates phase distinction
-- entirely to user-side literal suffixes. The literal text below is
-- fixed; callers needing a different reasoner persona should fork or
-- swap the `call_*` helpers.
local UNIFIED_SYSTEM_PROMPT = "You are a careful reasoner. "
    .. "Think through the problem step by step. "
    .. "When prompted to continue, extend your reasoning further before answering. "
    .. "Produce a final answer only when explicitly directed."

---@type AlcSpec
M.spec = {
    entries = {
        think_initial = {
            input = T.shape({
                task = T.string:describe("Question or task to reason about"),
                max_thinking_tokens = T.number:is_optional():describe(
                    "Token budget for the initial thinking pass (default: 2000; implementation choice — paper does not specify a per-call cap, sized for typical chain-of-thought completions)"
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
                    'Literal string appended to the trace to cue continued reasoning (default: "Wait"; Muennighoff 2025 §3 / Table 4 ablation winner over "Alternatively" / "Hmm")'
                ),
                max_thinking_tokens = T.number:is_optional():describe(
                    "Token budget for the continuation pass (default: 2000; implementation choice — see think_initial)"
                ),
                leak_patterns = T.array_of(T.string):is_optional():describe(
                    'Literal substrings that signal a premature final-answer leak (default: {"Final Answer:", "Final answer:", "The answer is", "答え:", "答えは"}; implementation choice — prompt-level analogue of paper §3 `</think>` logit suppression. Continuation is scanned for the earliest match and the leaked tail is stripped before accumulating into the trace)'
                ),
            }),
            result = T.shape({
                trace = T.string:describe("Trace extended with the wait cue and (possibly leak-stripped) continuation"),
                continuation = T.string:describe("The new continuation text appended in this extension, after any leak strip"),
                leak_stripped = T.boolean:describe("Whether a leak_pattern was detected and the tail was stripped before accumulation"),
                leak_pattern = T.string:is_optional():describe("The leak_pattern that matched (present iff leak_stripped is true)"),
            }),
        },
        finalize = {
            input = T.shape({
                task = T.string:describe("Original question or task"),
                trace = T.string:describe("Final reasoning trace before answer extraction"),
                final_answer_suffix = T.string:is_optional():describe(
                    'Suffix that forces answer extraction at budget exhaustion (default: "Final Answer:"; Muennighoff 2025 §3 literal)'
                ),
                final_answer_tokens = T.number:is_optional():describe(
                    "Token budget for the final answer extraction pass (default: 500; implementation choice — paper has no separate cap, sized for concise answers)"
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
                    "Maximum number of Wait extensions to attempt before forced finalization (default: 4; implementation choice — Muennighoff 2025 §3 reports K ∈ {2, 4, 6}, 4 chosen as mid-range default. Paper does not prescribe a default.)"
                ),
                wait_literal = T.string:is_optional():describe(
                    'Literal string appended each extension to cue continued reasoning (default: "Wait"; Muennighoff 2025 §3 / Table 4 ablation winner)'
                ),
                final_answer_suffix = T.string:is_optional():describe(
                    'Suffix that forces answer extraction (default: "Final Answer:"; Muennighoff 2025 §3 literal)'
                ),
                max_thinking_tokens = T.number:is_optional():describe(
                    "Token budget for each thinking round-trip — initial and each extension (default: 2000; implementation choice)"
                ),
                final_answer_tokens = T.number:is_optional():describe(
                    "Token budget for the final answer extraction pass (default: 500; implementation choice)"
                ),
                max_total_thinking_tokens = T.number:is_optional():describe(
                    "Cumulative thinking-trace token cap implementing Muennighoff 2025 §3 Maximum Token Enforcement (T_max). When set, exceeding this cap triggers an early finalize (Wait skip + answer extraction). Default: nil (disabled = caller opt-in; implementation choice — paper ablates total thinking budget but reports no canonical default literal in §3, so this pkg avoids imposing a silent cap). For paper-faithful Maximum Token Enforcement, set explicitly (e.g. max_extensions * max_thinking_tokens)."
                ),
                chars_per_token = T.number:is_optional():describe(
                    "Heuristic divisor for the prompt-level cumulative-trace token estimate (default: 4; industry standard — OpenAI tokenizer guidance ~4 chars/token for English; CJK-heavy domains should override to ~2)"
                ),
                leak_patterns = T.array_of(T.string):is_optional():describe(
                    'Leak-detection literal substrings forwarded to each extend call (default see extend entry; implementation choice)'
                ),
            }),
            result = T.shape({
                final_answer = T.string:describe("Final answer extracted after thinking + extensions + finalize"),
                trace = T.string:describe("Full reasoning trace including initial pass and all Wait extensions (with leaked tails stripped per leak_patterns)"),
                extensions_used = T.number:describe(
                    "Number of Wait extensions actually executed; ranges over [0, max_extensions]. Equals max_extensions when the loop completes normally; equals the count at which the cumulative T_max budget was reached when max_total_thinking_tokens is set and triggers an early exit. exit_reason distinguishes the two cases."
                ),
                exit_reason = T.one_of({ "max_extensions", "budget" }):describe(
                    "Which stop condition fired: 'max_extensions' when the K loop completed (extensions_used == max_extensions), or 'budget' when Maximum Token Enforcement triggered an early exit (extensions_used < max_extensions)."
                ),
            }),
        },
    },
}

-- ---- pure helpers ----

-- (I) Rough token estimate via chars / chars_per_token; used only for
-- the T_max cumulative budget check. See DEFAULT_CHARS_PER_TOKEN.
local function estimate_tokens(text, chars_per_token)
    return math.floor(#text / chars_per_token)
end

-- (X) Returns (leak_start_index, matched_pattern) for the earliest
-- occurrence of any pattern in `text`, or (nil, nil) if none match.
-- Plain (literal) string search so callers can supply patterns with
-- regex metacharacters without escaping.
local function detect_leak(text, patterns)
    local earliest_start = nil
    local earliest_pattern = nil
    for _, pat in ipairs(patterns) do
        local s = text:find(pat, 1, true)
        if s and (earliest_start == nil or s < earliest_start) then
            earliest_start = s
            earliest_pattern = pat
        end
    end
    return earliest_start, earliest_pattern
end

-- (X) Strip the leaked tail starting at `leak_start` (1-based) and
-- trim trailing whitespace so the next Wait inject sits cleanly after
-- the truncated trace. Returns the stripped text.
local function strip_leak(text, leak_start)
    if leak_start == nil then return text end
    local stripped = text:sub(1, leak_start - 1)
    return stripped:match("^(.-)%s*$") or stripped
end

local function call_initial_think(task, max_tokens)
    return alc.llm(
        string.format(
            "Question:\n%s\n\nBegin your reasoning. Do not produce a final answer yet — only the reasoning trace.",
            task
        ),
        { system = UNIFIED_SYSTEM_PROMPT, max_tokens = max_tokens }
    )
end

local function call_extend(task, trace, wait_literal, max_tokens)
    return alc.llm(
        string.format(
            "Question:\n%s\n\nReasoning so far:\n%s\n\n%s",
            task, trace, wait_literal
        ),
        { system = UNIFIED_SYSTEM_PROMPT, max_tokens = max_tokens }
    )
end

local function call_finalize(task, trace, final_answer_suffix, max_tokens)
    return alc.llm(
        string.format(
            "Question:\n%s\n\nFull reasoning trace:\n%s\n\n%s",
            task, trace, final_answer_suffix
        ),
        { system = UNIFIED_SYSTEM_PROMPT, max_tokens = max_tokens }
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
    local leak_patterns = ctx.leak_patterns or DEFAULT_LEAK_PATTERNS

    local continuation = call_extend(task, trace, wait_literal, max_tokens)

    -- Paper §3 Minimum Token Enforcement: at decoding time the
    -- `</think>` delimiter would be suppressed (logit mask) so the
    -- model cannot finalize; at prompt level we cannot enforce this,
    -- so we detect a final-answer-shaped leak and strip the leaked
    -- tail before accumulating into the trace. The wait_literal is
    -- still appended (preserving paper's forced-lengthen intent so
    -- the next round receives a Wait-cued non-finalized trace).
    local leak_start, leak_pat = detect_leak(continuation, leak_patterns)
    local effective_continuation = continuation
    local leak_stripped = false
    if leak_start then
        effective_continuation = strip_leak(continuation, leak_start)
        leak_stripped = true
    end

    local new_trace = trace .. "\n" .. wait_literal .. "\n" .. effective_continuation

    ctx.result = {
        trace = new_trace,
        continuation = effective_continuation,
        leak_stripped = leak_stripped,
        leak_pattern = leak_pat,
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
    local max_total = ctx.max_total_thinking_tokens or DEFAULT_MAX_TOTAL_THINKING_TOKENS
    local chars_per_token = ctx.chars_per_token or DEFAULT_CHARS_PER_TOKEN
    local leak_patterns = ctx.leak_patterns or DEFAULT_LEAK_PATTERNS

    -- Phase 1: nested dispatch via M.think_initial so the wrapped
    -- (instrumented) version fires its own input/result shape check.
    -- This matches the alc_shapes/README §Producer usage "Nested
    -- dispatch" pattern — Lua table lookup is resolved at call time,
    -- so the inner call goes through the wrapper.
    local sub = M.think_initial({
        task = task,
        max_thinking_tokens = max_thinking_tokens,
    })
    local trace = sub.result.trace

    -- Phase 2: extensions. Loop terminates on whichever of the two
    -- paper §3 stop conditions fires first:
    --   (a) extensions_used == max_extensions (paper K upper bound)
    --   (b) cumulative thinking tokens >= max_total_thinking_tokens
    --       (paper Maximum Token Enforcement; only checked when the
    --       caller opted into T_max by setting the field)
    -- extensions_used reflects only completed extensions, so it
    -- ranges over [0, max_extensions]. exit_reason records which
    -- stop fired so callers can distinguish the two cases.
    local extensions_used = 0
    local exit_reason = "max_extensions"

    for i = 1, max_extensions do
        if max_total ~= nil then
            local cumulative = estimate_tokens(trace, chars_per_token)
            if cumulative >= max_total then
                exit_reason = "budget"
                break
            end
        end

        sub = M.extend({
            task = task,
            trace = trace,
            wait_literal = wait_literal,
            max_thinking_tokens = max_thinking_tokens,
            leak_patterns = leak_patterns,
        })
        trace = sub.result.trace
        extensions_used = extensions_used + 1
        alc.log("info", string.format(
            "s1: extension %d/%d (wait_literal=%q, leak_stripped=%s)",
            i, max_extensions, wait_literal, tostring(sub.result.leak_stripped)
        ))
    end

    -- Phase 3: finalize via nested dispatch.
    sub = M.finalize({
        task = task,
        trace = trace,
        final_answer_suffix = final_answer_suffix,
        final_answer_tokens = final_answer_tokens,
    })

    ctx.result = {
        final_answer = sub.result.final_answer,
        trace = trace,
        extensions_used = extensions_used,
        exit_reason = exit_reason,
    }
    return ctx
end

-- Malli-style self-decoration (see alc_shapes/README §Producer
-- usage). Wrap each entry independently; nested dispatch in M.run
-- relies on these wrappers being installed before any call goes out.
M.think_initial = S.instrument(M, "think_initial")
M.extend = S.instrument(M, "extend")
M.finalize = S.instrument(M, "finalize")
M.run = S.instrument(M, "run")

return M
