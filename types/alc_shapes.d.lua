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

---@class AlcResultFunnelRanked
---@field best string @Top-ranked text
---@field best_index number @Top-ranked original index (1-based)
---@field bypass_reason? string @Reason for bypass (nil when not bypassed)
---@field funnel_bypassed boolean @True when N < 6 bypasses funnel stages
---@field funnel_shape number[] @Candidate counts per stage [N, s1_out, s2_out]
---@field naive_baseline_calls number @Hypothetical full-pairwise call count
---@field naive_baseline_kind string @Baseline method identifier
---@field ranking table[] @Final ranking
---@field savings_percent? number @LLM call savings vs baseline (nil on bypass)
---@field stages table[] @Per-stage detail (heterogeneous, keyed by name)
---@field total_llm_calls number
---@field warnings table[] @Diagnostic warnings

---@class AlcResultListwiseRanked
---@field best string @Top-ranked text
---@field best_index number @Top-ranked original index (1-based)
---@field killed table[] @Eliminated candidates
---@field n_candidates number
---@field ranked table[] @Full ranking
---@field top_k table[] @Top-k subset
---@field total_llm_calls number

---@class AlcResultPairwiseRanked
---@field best string @Top-ranked text
---@field best_index number @Top-ranked original index (1-based)
---@field both_tie_pairs number @Pairs that tied in both directions
---@field killed table[] @Eliminated candidates
---@field method "allpair"|"sorting" @Comparison strategy
---@field n_candidates number
---@field position_bias_splits number @Position-bias correction splits
---@field ranked table[] @Full ranking with scores
---@field score_semantics "copeland"|"rank_inverse" @Score interpretation
---@field top_k table[] @Top-k subset
---@field total_llm_calls number

---@class AlcResultPaneled
---@field arguments table[] @Per-role position statements
---@field synthesis string @Moderator synthesis

---@class AlcResultSafePaneled
---@field abort_reason? string @Abort reason (nil when not aborted)
---@field aborted boolean @True if early-abort triggered
---@field answer? string @Consensus answer (nil on abort)
---@field anti_jury boolean @Condorcet anti-jury detection
---@field confidence number @Meta-confidence estimate
---@field expected_accuracy number @Condorcet expected majority accuracy
---@field is_safe boolean @Vote-prefix stability safe flag
---@field margin_gap number @(top - runner_up) / n
---@field n_distinct_answers number @Count of unique answers
---@field needs_investigation boolean @True if meta-confidence below threshold
---@field panel_size number @Actual panel size used
---@field plurality_fraction number @Top-answer vote fraction
---@field stages table[] @Per-stage detail (heterogeneous, keyed by name)
---@field target_met boolean @Whether expected accuracy >= target
---@field total_llm_calls number
---@field unanimous boolean @All votes identical
---@field vote_counts table @{ [normalized_answer] = count } tally

---@class AlcResultTournament
---@field best string @Winner text
---@field best_index number @Winner original index (1-based)
---@field candidates string[] @Input candidate texts
---@field matches table[] @Pairwise match log
---@field total_wins number @Winner's win count

---@class AlcResultVoted
---@field answer? string @Majority answer (nil when no paths converge)
---@field answer_norm? string @Normalized vote key
---@field consensus string @LLM-synthesized majority summary
---@field n_sampled number @Number of sampled paths
---@field paths table[] @Per-path reasoning + extracted answer
---@field total_llm_calls number
---@field vote_counts table @{ [norm] = count } tally
---@field votes string[] @Normalized vote per path, 1-indexed
