---@meta

---@class AlcResultAssessed
---@field answer string
---@field confidence number @Self-assessed confidence 0.0–1.0
---@field total_llm_calls number

---@class AlcResultCalibrated
---@field answer string
---@field confidence number @Initial self-assessed confidence
---@field escalated boolean @Whether fallback was triggered
---@field fallback_detail? table @Fallback strategy result (voted/paneled)
---@field strategy "direct"|"retry"|"panel"|"ensemble"
---@field total_llm_calls number

---@class AlcResultPaneled
---@field arguments table[] @Per-role { role, text } records
---@field synthesis string @Moderator synthesis

---@class AlcResultVoted
---@field answer? string @Majority answer (nil when no paths converge)
---@field answer_norm? string @Normalized vote key
---@field consensus string @LLM-synthesized majority summary
---@field n_sampled number @Number of sampled paths
---@field paths table[] @Per-path { reasoning, answer } records
---@field total_llm_calls number
---@field vote_counts table @{ [norm] = count } tally
---@field votes string[] @Normalized vote per path, 1-indexed
