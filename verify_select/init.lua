--- verify_select(VerifySelect) — generate-then-verify best-of-N selection
---
--- A boost strategy aimed at 26-generation models, positioned as a successor
--- to self-consistency (`sc`, majority vote). Instead of tallying identical
--- answers, it samples `n` diverse candidates in a single parallel round-trip
--- (`alc.llm_batch`), then runs a single verifier pass (`alc.llm`) that scores
--- every candidate against a rubric and selects the best with a rationale.
---
--- ## Usage
---
--- ```lua
--- local vs = require("verify_select")
--- return vs.run(ctx)
--- ```
---
--- ## Algorithm
---
--- 1. Generate `n` candidates in one `alc.llm_batch` round-trip. Each batch
---    item carries a distinct system persona to induce diversity (temperature
---    diversity is assumed on the host side).
--- 2. Run one `alc.llm` verifier pass. The verifier receives ALL candidates
---    plus the rubric, scores each 0-10, and emits a structured verdict block
---    with `SELECTED:` and `RATIONALE:` markers.
--- 3. Parse the verdict block into per-candidate `{ index, score, verdict }`
---    records, resolve the selected candidate, and return it with the rationale.
---
--- ## API
---
--- - `ctx.task`   — string, required. Empty / whitespace-only → error.
--- - `ctx.n`      — number, optional. Candidate count (default 3).
--- - `ctx.rubric` — string, optional. Selection criteria injected verbatim
---   into the verifier prompt. Omitted → a generic accuracy/completeness rubric.
---
--- Result (`ctx.result`):
--- - `selected`   — string, the winning candidate text.
--- - `candidates` — number, how many candidates were generated.
--- - `verdicts`   — array of `{ index, score, verdict }`, one per candidate.
--- - `rationale`  — string, the verifier's justification for the selection.
---
--- ## Comparison with related packages
---
--- vs `sc`: `sc` deterministically majority-votes identical answers. This
--- picks the highest-quality answer via a rubric verifier — better when
--- candidates diverge in quality rather than converging on one answer.
---
--- vs `rank`: `rank` runs an O(n) pairwise elimination tournament (many
--- `alc.llm` calls). This uses a single verifier pass over all candidates
--- (2 round-trips total) — cheaper, at the cost of pairwise granularity.

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "verify_select",
    version = "0.1.0",
    description = "Generate-then-verify best-of-N selection via a rubric verifier",
    category = "selection",
    alc_shapes_compat = "^0.25",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task = T.string:describe("Problem to solve (required, non-empty)"),
                n = T.number:is_optional()
                    :describe("Number of candidates to generate (default: 3)"),
                rubric = T.string:is_optional()
                    :describe("Selection criteria injected into the verifier prompt "
                        .. "(default: generic accuracy/completeness rubric)"),
            }),
            result = T.shape({
                selected = T.string:describe("The winning candidate text"),
                candidates = T.number:describe("Number of candidates generated"),
                verdicts = T.array_of(T.shape({
                    index = T.number:describe("1-based candidate index"),
                    score = T.number:describe("Verifier score 0-10 (0 if unparsed)"),
                    verdict = T.string:describe("One-line verifier note for the candidate"),
                })):describe("Per-candidate verifier records"),
                rationale = T.string:describe("Verifier justification for the selection"),
            }),
        },
    },
}

--- Default rubric used when the caller omits `ctx.rubric`.
local DEFAULT_RUBRIC =
    "Correctness and factual accuracy; completeness of the answer; "
    .. "clarity and directness; absence of unsupported or fabricated claims."

--- Trim leading/trailing whitespace from a string (nil-safe).
local function trim(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Parse the verifier output block into a per-index score/verdict map plus
--- the SELECTED index and RATIONALE text.
---
--- Expected (best-effort) format, one candidate per line:
---   Candidate <i> score: <0-10> - <one-line verdict>
---   SELECTED: <candidate number>
---   RATIONALE: <text>
---
--- Returns: parsed (map i -> {score, verdict}), selected_idx (number|nil),
--- rationale (string|nil).
local function parse_verdicts(text)
    local parsed = {}
    local selected_idx = nil
    local rationale = nil
    for line in text:gmatch("[^\n]+") do
        local ci, sc = line:match("[Cc]andidate%s+(%d+)%s+score:%s*([%d%.]+)")
        if ci and sc then
            local i = tonumber(ci)
            local vtext = line:match("score:%s*[%d%.]+%s*%-?%s*(.*)$")
            parsed[i] = { score = tonumber(sc), verdict = trim(vtext) }
        else
            local sel = line:match("SELECTED:%s*(%d+)")
            if sel then selected_idx = tonumber(sel) end
            local rat = line:match("RATIONALE:%s*(.+)")
            if rat then rationale = trim(rat) end
        end
    end
    return parsed, selected_idx, rationale
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task
    if type(task) ~= "string" or task:match("^%s*$") then
        error("ctx.task is required (non-empty string)")
    end
    local n = ctx.n or 3
    local rubric = ctx.rubric or DEFAULT_RUBRIC
    local gen_tokens = ctx.gen_tokens or 400

    -- Phase 1: generate N candidates in a single parallel round-trip.
    local batch = {}
    for i = 1, n do
        batch[i] = {
            prompt = string.format("Task: %s\n\nProvide your best, complete response.", task),
            system = string.format(
                "You are candidate generator #%d. Produce a high-quality, "
                    .. "self-contained answer. Take a distinctive approach so that "
                    .. "candidates differ from one another.",
                i
            ),
            max_tokens = gen_tokens,
        }
    end
    local candidates = alc.llm_batch(batch)

    if alc.log then
        alc.log("info", string.format("verify_select: %d candidates generated, verifying", #candidates))
    end

    -- Phase 2: single verifier pass over all candidates with the rubric.
    local listing = ""
    for i, c in ipairs(candidates) do
        listing = listing .. string.format("[Candidate %d]\n%s\n\n", i, tostring(c))
    end

    local verifier_out = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Candidates:\n%s"
                .. "Rubric (selection criteria):\n%s\n\n"
                .. "Score EACH candidate from 0 to 10 against the rubric, then select "
                .. "the single best candidate.\n"
                .. "Output EXACTLY this format (one score line per candidate):\n"
                .. "Candidate <i> score: <0-10> - <one-line verdict>\n"
                .. "SELECTED: <candidate number>\n"
                .. "RATIONALE: <why the selected candidate wins under the rubric>",
            task, listing, rubric
        ),
        {
            system = "You are a rigorous verifier. Judge strictly against the "
                .. "provided rubric. Be exact and follow the output format.",
            max_tokens = 400,
        }
    )

    -- Parse the verifier output into structured verdicts.
    local parsed, selected_idx, rationale = parse_verdicts(verifier_out)

    -- Build a dense per-candidate verdict array (length == #candidates).
    local verdicts = {}
    for i = 1, #candidates do
        local p = parsed[i]
        verdicts[i] = {
            index = i,
            score = (p and p.score) or 0,
            verdict = (p and p.verdict) or "",
        }
    end

    -- Resolve selection: prefer the verifier's SELECTED marker; otherwise fall
    -- back to the highest score; finally default to candidate 1.
    if not selected_idx or not candidates[selected_idx] then
        local best_i, best_score = nil, -math.huge
        for _, v in ipairs(verdicts) do
            if v.score > best_score then
                best_i, best_score = v.index, v.score
            end
        end
        selected_idx = best_i or 1
    end

    ctx.result = {
        selected = tostring(candidates[selected_idx] or ""),
        candidates = #candidates,
        verdicts = verdicts,
        rationale = rationale or trim(verifier_out),
    }
    return ctx
end

-- ─── Test hooks ───
M._internal = {
    parse_verdicts = parse_verdicts,
    trim = trim,
    DEFAULT_RUBRIC = DEFAULT_RUBRIC,
}

-- Malli-style self-decoration: wrapper asserts input/result against
-- M.spec.entries.run shapes when ALC_SHAPE_CHECK=1 (passthrough otherwise).
M.run = S.instrument(M, "run")

return M
