--- qdaif — Quality-Diversity through AI Feedback
---
--- Maintains a MAP-Elites archive (feature-space × quality grid) using only
--- LLM calls. Generates diverse, high-quality solutions by: (1) seeding the
--- archive, (2) selecting elites, (3) mutating via LLM, (4) evaluating quality
--- and feature placement via LLM, (5) inserting into the archive if superior.
---
--- Unlike optimize (single best) or diverse (sample then pick), qdaif
--- structurally maintains a population of elite solutions across a feature
--- space, ensuring both quality AND diversity simultaneously.
---
--- Based on:
---   [1] Bradley et al. "Quality-Diversity through AI Feedback"
---       (ICLR 2024, arXiv:2310.13032)
---   [2] Lehman et al. "Evolution through Large Models"
---       (OpenELM, OpenReview)
---   [3] Mouret & Clune "Illuminating search spaces by mapping elites"
---       (2015, arXiv:1504.04909)
---
--- Pipeline (seed_count + iterations × 2 LLM calls + 1 synthesis):
---   Seed     — generate initial candidates
---   Loop:
---     Select   — pick elite from archive (empty-cell priority)
---     Mutate   — LLM generates variant of selected elite
---     Evaluate — LLM scores quality + assigns feature bin
---     Insert   — replace archive cell if new candidate is better
---   Final: return archive + best elite
---
--- Usage:
---   local qdaif = require("qdaif")
---   return qdaif.run(ctx)
---
--- ctx.task (required): The problem to solve / domain description
--- ctx.features (required): Feature axes definition
---   e.g. { { name = "style", bins = {"formal", "casual", "technical"} } }
--- ctx.iterations: Mutation-evaluation cycles (default: 20)
--- ctx.seed_count: Initial candidates to generate (default: 5)
--- ctx.elite_tokens: Max tokens for candidate generation (default: 400)

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "qdaif",
    version = "0.1.0",
    description = "Quality-Diversity through AI Feedback — MAP-Elites archive "
        .. "with LLM-driven mutation, evaluation, and feature classification. "
        .. "Produces diverse, high-quality solution populations.",
    category = "exploration",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task = T.string:describe("Problem / domain description"),
                features = T.array_of(T.shape({
                    name = T.string:describe("Feature axis name"),
                    bins = T.array_of(T.string):describe("Bin labels along this axis (≥2)"),
                })):describe("Feature axes defining the MAP-Elites grid"),
                iterations   = T.number:is_optional():describe("Mutation-evaluation cycles (default: 20)"),
                seed_count   = T.number:is_optional():describe("Initial candidates to generate (default: 5)"),
                elite_tokens = T.number:is_optional():describe("Max tokens for candidate generation (default: 400)"),
            }),
            result = T.shape({
                best       = T.string:is_optional():describe("Archive-best candidate (nil if archive empty)"),
                best_score = T.number:describe("Best score across the archive"),
                archive = T.array_of(T.shape({
                    cell      = T.string:describe("Grid key built from bin indices"),
                    features  = T.array_of(T.string):describe("Feature bin labels (e.g. 'style=formal')"),
                    score     = T.number:describe("Elite score"),
                    candidate = T.string:describe("Elite solution text"),
                })):describe("Archive elites sorted by score descending"),
                coverage = T.number:describe("filled_cells / total_cells ∈ [0,1]"),
                stats = T.shape({
                    total_cells  = T.number:describe("Total grid cells"),
                    filled_cells = T.number:describe("Cells actually populated with an elite"),
                    seed_count   = T.number:describe("Seed count used"),
                    iterations   = T.number:describe("Iteration count used"),
                }):describe("Quality-diversity statistics"),
            }),
        },
    },
}

-- ─── Archive (MAP-Elites grid) ───

--- Build a flat key from bin indices across all feature axes.
local function grid_key(bin_indices)
    local parts = {}
    for _, idx in ipairs(bin_indices) do
        parts[#parts + 1] = tostring(idx)
    end
    return table.concat(parts, ",")
end

--- Count total cells in the grid (product of bin counts).
local function total_cells(features)
    local n = 1
    for _, f in ipairs(features) do
        n = n * #f.bins
    end
    return n
end

--- List all possible grid keys.
local function all_keys(features)
    local keys = {}
    local function recurse(depth, indices)
        if depth > #features then
            keys[#keys + 1] = grid_key(indices)
            return
        end
        for i = 1, #features[depth].bins do
            indices[depth] = i
            recurse(depth + 1, indices)
        end
    end
    recurse(1, {})
    return keys
end

--- Format feature axes for prompt injection.
local function format_features(features)
    local lines = {}
    for _, f in ipairs(features) do
        local bins_str = table.concat(f.bins, ", ")
        lines[#lines + 1] = string.format("  %s: [%s]", f.name, bins_str)
    end
    return table.concat(lines, "\n")
end

--- Format archive summary for prompt injection.
local function format_archive(archive, features)
    local lines = {}
    local count = 0
    for key, entry in pairs(archive) do
        count = count + 1
        local bin_labels = {}
        for i, idx in ipairs(entry.bin_indices) do
            bin_labels[#bin_labels + 1] = string.format(
                "%s=%s", features[i].name, features[i].bins[idx]
            )
        end
        lines[#lines + 1] = string.format(
            "  [%s] score=%.1f: %s",
            table.concat(bin_labels, ", "),
            entry.score,
            entry.candidate:sub(1, 80) .. (#entry.candidate > 80 and "..." or "")
        )
    end
    if count == 0 then return "  (empty)" end
    return table.concat(lines, "\n")
end

-- ─── LLM operations ───

--- Generate a seed candidate.
local function generate_seed(task, features, features_text, existing, elite_tokens)
    local existing_hint = ""
    if #existing > 0 then
        local items = {}
        for i, e in ipairs(existing) do
            items[#items + 1] = string.format("  %d. %s", i, e:sub(1, 60))
        end
        existing_hint = "\n\nAlready generated (be DIFFERENT):\n" .. table.concat(items, "\n")
    end

    return alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Feature space:\n%s\n\n"
                .. "Generate a high-quality solution. Aim for a DISTINCTIVE position "
                .. "in the feature space — don't cluster around the obvious center.%s",
            task, features_text, existing_hint
        ),
        {
            system = "You are a creative problem solver. Produce a specific, "
                .. "concrete solution. Variety is as important as quality.",
            max_tokens = elite_tokens,
        }
    )
end

--- Mutate an existing elite to produce a variant.
local function mutate(task, elite, features_text, archive_summary, elite_tokens)
    return alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Feature space:\n%s\n\n"
                .. "Current archive:\n%s\n\n"
                .. "Parent solution to mutate:\n%s\n\n"
                .. "Create a VARIANT of this solution. Change its character to explore "
                .. "a different region of the feature space, while maintaining or "
                .. "improving quality. The variant should be meaningfully different, "
                .. "not a trivial rephrasing.",
            task, features_text, archive_summary, elite.candidate
        ),
        {
            system = "You are an evolutionary mutation operator. Produce a variant "
                .. "that differs from the parent in feature-space position while "
                .. "maintaining high quality.",
            max_tokens = elite_tokens,
        }
    )
end

--- Evaluate a candidate: quality score + feature bin assignment.
local function evaluate(task, candidate, features)
    local features_text = format_features(features)

    -- Build bin options for structured output
    local bin_instructions = {}
    for _, f in ipairs(features) do
        local opts = {}
        for i, b in ipairs(f.bins) do
            opts[#opts + 1] = string.format("%d=%s", i, b)
        end
        bin_instructions[#bin_instructions + 1] = string.format(
            "  %s: %s", f.name, table.concat(opts, ", ")
        )
    end

    local eval_str = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Feature space:\n%s\n\n"
                .. "Candidate solution:\n%s\n\n"
                .. "Evaluate this candidate:\n"
                .. "1. QUALITY: Rate 1-10 (correctness, usefulness, completeness)\n"
                .. "2. FEATURES: Classify into bins:\n%s\n\n"
                .. "Reply in EXACTLY this format (one line each):\n"
                .. "SCORE: <number>\n"
                .. "BINS: <comma-separated bin numbers>",
            task, features_text, candidate, table.concat(bin_instructions, "\n")
        ),
        {
            system = "You are a precise evaluator. Follow the output format exactly.",
            max_tokens = 50,
        }
    )

    -- Parse score
    local score = 5
    local score_match = eval_str:match("SCORE:%s*(%d+)")
    if score_match then
        score = math.min(10, math.max(1, tonumber(score_match)))
    else
        score = alc.parse_score(eval_str)
    end

    -- Parse bin indices
    local bin_indices = {}
    local bins_match = eval_str:match("BINS:%s*([%d%s,]+)")
    if bins_match then
        for num in bins_match:gmatch("%d+") do
            bin_indices[#bin_indices + 1] = tonumber(num)
        end
    end

    -- Validate and clamp bin indices
    for i, f in ipairs(features) do
        if not bin_indices[i] or bin_indices[i] < 1 or bin_indices[i] > #f.bins then
            bin_indices[i] = math.random(1, #f.bins)
        end
    end

    return score, bin_indices
end

-- ─── Main ───

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local features = ctx.features or error("ctx.features is required — list of {name, bins}")
    local iterations = ctx.iterations or 20
    local seed_count = ctx.seed_count or 5
    local elite_tokens = ctx.elite_tokens or 400

    -- Validate features
    for i, f in ipairs(features) do
        if not f.name or not f.bins or #f.bins < 2 then
            error(string.format("ctx.features[%d] must have name and bins (≥2)", i))
        end
    end

    local features_text = format_features(features)
    local archive = {}  -- key → { candidate, score, bin_indices }
    local total = total_cells(features)

    -- Phase 1: Seed the archive
    local existing_candidates = {}
    for i = 1, seed_count do
        local candidate = generate_seed(
            task, features, features_text, existing_candidates, elite_tokens
        )
        existing_candidates[#existing_candidates + 1] = candidate

        local score, bin_indices = evaluate(task, candidate, features)
        local key = grid_key(bin_indices)

        if not archive[key] or score > archive[key].score then
            archive[key] = {
                candidate = candidate,
                score = score,
                bin_indices = bin_indices,
            }
        end

        alc.log("info", string.format(
            "qdaif: seed %d/%d — score=%.0f, cell=%s",
            i, seed_count, score, key
        ))
    end

    -- Phase 2: Mutation-evaluation loop
    local all = all_keys(features)

    for i = 1, iterations do
        -- Select parent: prefer elites near empty cells, or random elite
        local parent
        local empty_neighbors = {}

        -- Find empty cells
        for _, key in ipairs(all) do
            if not archive[key] then
                empty_neighbors[#empty_neighbors + 1] = key
            end
        end

        -- Select a parent elite
        local elites = {}
        for _, entry in pairs(archive) do
            elites[#elites + 1] = entry
        end

        if #elites == 0 then
            alc.log("warn", "qdaif: archive empty, regenerating seed")
            break
        end

        -- If empty cells exist, pick a random elite (bias toward exploration)
        -- If archive is full, pick a random elite (bias toward quality improvement)
        parent = elites[math.random(1, #elites)]

        -- Mutate
        local archive_summary = format_archive(archive, features)
        local variant = mutate(task, parent, features_text, archive_summary, elite_tokens)

        -- Evaluate
        local score, bin_indices = evaluate(task, variant, features)
        local key = grid_key(bin_indices)

        -- Insert if better or cell is empty
        local replaced = false
        if not archive[key] then
            archive[key] = {
                candidate = variant,
                score = score,
                bin_indices = bin_indices,
            }
            replaced = true
        elseif score > archive[key].score then
            archive[key] = {
                candidate = variant,
                score = score,
                bin_indices = bin_indices,
            }
            replaced = true
        end

        -- Count filled cells
        local filled = 0
        for _ in pairs(archive) do filled = filled + 1 end

        alc.log("info", string.format(
            "qdaif: iter %d/%d — score=%.0f, cell=%s, %s, coverage=%d/%d",
            i, iterations, score, key,
            replaced and "INSERTED" or "rejected",
            filled, total
        ))
    end

    -- Phase 3: Build results
    local elites_list = {}
    local best_entry = nil
    local best_score = -1

    for key, entry in pairs(archive) do
        local bin_labels = {}
        for j, idx in ipairs(entry.bin_indices) do
            bin_labels[#bin_labels + 1] = string.format(
                "%s=%s", features[j].name, features[j].bins[idx]
            )
        end
        elites_list[#elites_list + 1] = {
            cell = key,
            features = bin_labels,
            score = entry.score,
            candidate = entry.candidate,
        }
        if entry.score > best_score then
            best_score = entry.score
            best_entry = entry
        end
    end

    table.sort(elites_list, function(a, b) return a.score > b.score end)

    local filled = 0
    for _ in pairs(archive) do filled = filled + 1 end

    alc.log("info", string.format(
        "qdaif: complete — %d/%d cells filled, best score=%.0f",
        filled, total, best_score
    ))

    ctx.result = {
        best = best_entry and best_entry.candidate or nil,
        best_score = best_score,
        archive = elites_list,
        coverage = filled / total,
        stats = {
            total_cells = total,
            filled_cells = filled,
            seed_count = seed_count,
            iterations = iterations,
        },
    }
    return ctx
end

-- Malli-style self-decoration: wrapper asserts ctx against
-- M.spec.entries.run.input and ret.result against .result when
-- ALC_SHAPE_CHECK=1.
M.run = S.instrument(M, "run")

return M
