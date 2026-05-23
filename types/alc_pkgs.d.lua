---@meta

---@class AlcPkgInput_ab_mcts
---@field alpha_prior? number @Beta prior alpha for Thompson sampling (default: 1.0)
---@field beta_prior? number @Beta prior beta for Thompson sampling (default: 1.0)
---@field budget? number @Total expansion iterations (default: 8)
---@field gen_tokens? number @Max tokens for generation/refinement (default: 400)
---@field max_depth? number @Maximum tree depth (default: 3)
---@field task string @The problem to solve

---@class AlcPkgResult_ab_mcts
---@field answer string @Final synthesized answer from the best leaf
---@field best_path string[] @Thought sequence from root to best leaf
---@field best_score number @Best leaf score in [0,1]
---@field tree_stats { branching_ratio: number, budget: number, deeper_decisions: number, max_depth: number, total_nodes: number, wider_decisions: number } @AB-MCTS statistics

---@class AlcPkgInput_ab_select
---@field alpha_prior? number @Beta prior α (default: 1.0)
---@field beta_prior? number @Beta prior β (default: 1.0)
---@field budget? number @Total fidelity-cost budget (default: 18)
---@field fidelities? { cost: number, max_tokens: number, name: string, prompt: string }[] @Override the evaluator ladder (default: 3-level quick/detail/thorough)
---@field gen_tokens? number @Max tokens per candidate generation (default: 400)
---@field n? number @Number of initial candidates (default: 6)
---@field score_hi? number @Maximum raw score for normalization (default: 10)
---@field seed? number @PRNG seed for Thompson sampling (default: 1)
---@field task string @The problem to generate and select an answer for

---@class AlcPkgResult_ab_select
---@field best string @Text of the winning candidate
---@field best_index number @1-based index of the winner
---@field best_score number @Posterior mean of the winner
---@field budget number @Total fidelity-cost budget supplied
---@field budget_used number @Total fidelity cost consumed
---@field candidates string[] @All generated candidate texts
---@field ranking { alpha: number, beta: number, evaluations: table, index: number, n_evals: number, posterior_mean: number }[] @All candidates sorted by posterior mean descending
---@field rounds { alpha: number, beta: number, budget_used: number, candidate: number, cost: number, iteration: number, level: number, level_name: string, score: number, score_norm: number, theta_pick: number }[] @Per-iteration Thompson sampling trace
---@field total_llm_calls number @Generation calls + evaluation calls

---@class AlcPkgInput_aco
---@field alpha? number @Pheromone exponent α (default: 1.0)
---@field answer_tokens? number @Max tokens for final answer synthesis (default: 500)
---@field beta? number @Heuristic exponent β (default: 2.0)
---@field budget? number @Max iterations (default: 20)
---@field decompose_system? string @System prompt for the decompose LLM
---@field eval_fn? any @Optional user-supplied scorer: function(path) -> score; when absent an LLM-based scorer is used
---@field eval_system? string @System prompt for the eval LLM
---@field exec_system? string @System prompt for the exec LLM
---@field n_ants? number @Ants per iteration (default: 5)
---@field nodes? string[] @Node labels for the graph; generated via decompose LLM when omitted
---@field rho? number @Pheromone evaporation rate ρ ∈ (0,1) (default: 0.2)
---@field seed? number @RNG seed (default: 42)
---@field stagnation? number @Stagnation iteration threshold (default: 5)
---@field task string @The task to solve

---@class AlcPkgResult_aco
---@field answer string @Final answer synthesized from the best path
---@field best_path string[] @Best step sequence (excludes start/end sentinel nodes)
---@field best_score number @Best path score
---@field history { avg_score: number, best_score: number, iteration: number }[] @Per-iteration convergence history
---@field iterations number @Iterations actually performed
---@field n_ants number @Ant count used
---@field n_nodes number @Total number of graph nodes
---@field rho number @Evaporation rate used

---@class AlcPkgInput_ambig
---@field clarify_tokens? number @Max tokens for clarification phase (default 400)
---@field detect_tokens? number @Max tokens for detection phase (default 500)
---@field integrate_tokens? number @Max tokens for integration phase (default 500)
---@field task string @Task or request to analyze (required)

---@class AlcPkgResult_ambig
---@field clarifications? { description: string, element: string, question: string }[] @One entry per underspecified element; absent when verdict='specified'
---@field elements { description: string, name: string, status: "specified"|"underspecified" }[] @All parsed elements including the specified ones
---@field questions string[] @Clarification questions; empty when verdict='specified'
---@field specified_task string @Fully-specified task (equals input task when was_underspecified=false)
---@field user_response? string @Raw alc.specify response; absent when verdict='specified'
---@field verdict "specified"|"underspecified" @Overall verdict derived from the VERDICT: line
---@field was_underspecified boolean @Whether the clarify/integrate phases ran

---@class AlcPkgInput_analogical
---@field domain_hint? string @Optional domain to draw analogies from
---@field n_analogies? number @Number of analogies to generate (default: 3)
---@field task string @The problem to solve

---@class AlcPkgResult_analogical
---@field analogies { problem: string, solution: string }[] @Self-generated analogous problems and their solutions
---@field answer string @Solution to the original problem produced by applying transferred patterns
---@field patterns string @Transferable reasoning patterns extracted from the analogies
---@field total_analogies number @Count of analogies actually generated

---@class AlcPkgInput_anti_cascade
---@field compare_tokens? number @Max tokens per pipeline-vs-independent comparison (default 400)
---@field drift_threshold? number @Drift score threshold at which a step is flagged (default 0.4)
---@field rederive_tokens? number @Max tokens per independent re-derivation (default 500)
---@field steps { instruction?: string, name: string, output: string }[] @Ordered pipeline step outputs; at least 1 entry (required)
---@field summary_tokens? number @Max tokens for the final summary analysis (default 500)
---@field task string @Original task/input that the pipeline was given (required)

---@class AlcPkgResult_anti_cascade
---@field flagged_steps string[] @Names of steps whose drift_score crossed the threshold
---@field max_drift number @Highest drift_score observed across all steps
---@field step_results { cascade_risk: string, drift_score: number, drift_type: string, flagged: boolean, name: string, raw: string }[] @Per-step drift analysis in pipeline order
---@field summary string @LLM-generated cascade analysis summary text

---@class AlcPkgInput_bisect
---@field gen_tokens? number @Max tokens for chain generation (default: 800)
---@field max_repairs? number @Maximum number of bisect→repair cycles (default: 2)
---@field task string @The task/question to solve
---@field verify_tokens? number @Max tokens per verification (default: 200)

---@class AlcPkgResult_bisect
---@field answer string @Final reasoning chain after all repairs
---@field initial_chain string @Original pre-repair reasoning chain
---@field repairs { bisect_log: { correct: boolean, hi: number, lo: number, mid: number, reason: string }[], error_content: string, error_label: string, error_step: number, regenerated: string, repair_round: number }[] @Per-cycle repair records
---@field total_repairs number @Number of repair cycles applied

---@class AlcPkgInput_blind_spot
---@field correct_tokens? number @Max tokens per correction / reflection (default: 800)
---@field gen_tokens? number @Max tokens for initial generation (default: 600)
---@field rounds? number @Externalize→correct rounds (default: 1)
---@field task string @The task/question to solve
---@field wait? boolean @Enable 'Wait' reflection trigger (default: true)

---@class AlcPkgResult_blind_spot
---@field answer string @Final answer after externalize→correct (+ Wait)
---@field corrections_detected number @Count of rounds whose output matched error/correction keywords
---@field history { role: string, round: number, text: string }[] @Per-round trace including initial draft, corrections, and optional wait reflection
---@field initial_answer string @Initial answer before any correction rounds
---@field rounds number @Number of externalize→correct rounds executed
---@field wait_applied boolean @Whether 'Wait' reflection round ran

---@class AlcPkgInput_boids_abm
---@field alignment_weight? number @Alignment rule weight (default 1.0)
---@field cohesion_weight? number @Cohesion rule weight (default 1.0)
---@field max_force? number @Per-step steering force cap (default 0.3)
---@field max_speed? number @Per-step velocity cap (default 4)
---@field n_boids? number @Number of boids (default 50)
---@field perception_radius? number @Neighbor perception radius (default 50)
---@field runs? number @Monte Carlo runs (default 100)
---@field separation_weight? number @Separation rule weight (default 1.5)
---@field steps? number @Simulation steps per run (default 100)
---@field task? string @Task description (free text)
---@field world_size? number @Square-world side length (default 300)

---@class AlcPkgResult_boids_abm
---@field params { alignment_weight: number, cohesion_weight: number, max_force: number, max_speed: number, n_boids: number, perception_radius: number, separation_weight: number, steps: number, world_size: number }
---@field sensitivity { base_value: number, delta: number, factor: number, high_value: number, low_value: number, param: string, score_at_high: number, score_at_low: number }[]
---@field simulation { alignment_score_mean: number, alignment_score_median: number, alignment_score_p25: number, alignment_score_p75: number, alignment_score_std: number, avg_nearest_distance_mean: number, avg_nearest_distance_median: number, avg_nearest_distance_p25: number, avg_nearest_distance_p75: number, avg_nearest_distance_std: number, clusters_mean: number, clusters_median: number, clusters_p25: number, clusters_p75: number, clusters_std: number, cohesive_flock_ci: { lower: number, upper: number }, cohesive_flock_count: number, cohesive_flock_rate: number, runs: number, scattered_ci: { lower: number, upper: number }, scattered_count: number, scattered_rate: number }

---@class AlcPkgInput_bot
---@field gen_tokens? number @Max tokens per instantiate / verify step (default 500)
---@field task string @Problem to solve (required)
---@field templates? table<string, { name: string, pattern: string }> @Custom template_key → {name, pattern} map; defaults to built-in TEMPLATES

---@class AlcPkgResult_bot
---@field answer string @Final answer extracted from the verification LLM output (falls back to full verification text)
---@field errors_found boolean @True when verification did not emit ERRORS: NONE (or NO ERRORS) — i.e., errors were reported
---@field instantiated_reasoning string @LLM output from Step 2 (template applied to the specific task)
---@field template_key string @Selected template key; 'analytical' is used as a fallback when parsing fails
---@field template_name string @Display name of the selected template
---@field template_pattern string @Reasoning steps of the selected template
---@field verification string @Full Step-3 verification text including ERRORS: and FINAL ANSWER: sections

---@alias AlcPkgResult_calibrate AlcResultCalibrated

---@class AlcPkgInput_card_analysis
---@field card any @Full Card body (host-loaded from card_id)
---@field card_id string @Card identifier (host-provided)
---@field samples any[] @samples sidecar rows (host-loaded; may be empty)

---@class AlcPkgResult_card_analysis
---@field confidence number @0.0..=1.0 diagnostic confidence
---@field failure_count? number @Detected failure sample count (Option<u64> on host side)
---@field pattern string @One-line failure pattern summary
---@field sample_count? number @Total samples processed (Option<u64> on host side)
---@field suggested_change string @Concrete change proposal (1-3 sentences, actionable)

---@class AlcPkgInput_cascade
---@field gen_tokens? number @Max tokens per generation call (default 400)
---@field max_level? number @Maximum cascade level to attempt (default 3)
---@field task string @Problem to solve (required)
---@field threshold? number @Confidence threshold at which the cascade stops early (default 0.8)
---@field verify_tokens? number @Max tokens per verification call (default 300)

---@class AlcPkgResult_cascade
---@field answer string @Final answer from the highest level actually run
---@field confidence number @Final confidence in [0, 1]
---@field escalated boolean @True iff level_used > 1
---@field history { answer: string, confidence: number, detail: any, level: number, name: string }[] @Per-level execution trace in run order
---@field level_used number @Level at which the cascade stopped
---@field max_level number @Echo of input.max_level
---@field threshold number @Echo of input.threshold

---@class AlcPkgInput_claim_trace
---@field answer? string @Pre-supplied answer to attribute (auto-generated if nil)
---@field extract_tokens? number @Max tokens for claim extraction (default: 500)
---@field gen_tokens? number @Max tokens for answer generation (default: 600)
---@field sources any @Source text(s): single string or array of strings
---@field task string @The original question/task
---@field trace_tokens? number @Max tokens per claim attribution (default: 300)

---@class AlcPkgResult_claim_trace
---@field answer string @Answer whose claims were traced (auto-generated or passed in)
---@field attribution_score number @(supported + 0.5*partial) / total; 1.0 when no claims
---@field claims { claim: string, raw: string, reasoning: string, source_index?: number, span: string, status: string }[] @Per-claim attribution records (empty when no claims extracted)
---@field coverage number @(supported + partial) / total; 1.0 when no claims
---@field partial number @Count of PARTIAL claims
---@field sources_count? number @Number of source documents (omitted on empty-claims short-circuit)
---@field supported number @Count of SUPPORTED claims
---@field total number @Total extracted claims
---@field unsupported number @Count of UNSUPPORTED claims

---@class AlcPkgInput_coa
---@field gen_tokens? number @Max tokens for the abstract chain and final answer (default 600)
---@field ground_tokens? number @Max tokens per grounding call (default 300)
---@field max_depth? number @Max dependency-resolution depth (default 3)
---@field task string @Problem to solve (required)
---@field tools? table<string, string> @tool_name → description; defaults to a single 'knowledge' tool

---@class AlcPkgResult_coa
---@field abstract_chain string @Raw abstract chain with [FUNC tool("query") = yN] placeholders
---@field answer string @Final answer produced from the grounded chain
---@field grounded_chain string @Chain after placeholder substitution
---@field groundings { depth: number, query: string, result: string, tool: string, var: string }[] @Per-placeholder resolution trace in resolution order
---@field placeholders_resolved number @Count of placeholders actually resolved
---@field tools_used table<string, string> @Echo of the tools map used for this run

---@class AlcPkgInput_cod
---@field gen_tokens? number @Max tokens per round (default: 400)
---@field rounds? number @Number of densification rounds (default: 3)
---@field target_length? number @Approximate target length in words (default: auto ~1/3 of input)
---@field text string @Source text to compress (uses ctx.text, not ctx.task)

---@class AlcPkgResult_cod
---@field compression_ratio number @output_words / input_words (0 when input_words == 0)
---@field history { round: number, summary: string, word_count: number }[] @Per-round history starting with round 0 (initial sparse summary)
---@field input_words number @Word count of original source text
---@field output string @Final densified summary after all rounds
---@field output_words number @Word count of final densified summary
---@field total_rounds number @Number of densification rounds executed (excludes round 0)

---@class AlcPkgInput_coevolve
---@field difficulty_target? number @Target success rate for calibration (default 0.5)
---@field problems_per_round? number @Problems Challenger generates per round (default 3)
---@field rounds? number @Co-evolution rounds (default 4)
---@field seed_problems? string[] @Initial problem set; if nil, LLM generates problems_per_round seeds
---@field solver_tokens? number @Max tokens for Solver responses (default 400)
---@field task string @The domain / problem to explore (required)

---@class AlcPkgResult_coevolve
---@field all_results { answer: string, problem: { difficulty: string, round: number, text: string }, reason?: string, round: number, verdict: string }[] @Full trace of every solve attempt
---@field answer string @Final synthesis answer using accumulated skill from all rounds
---@field round_stats { correct: number, difficulty_hint: string, problems: number, round: number, success_rate: number }[] @Per-round statistics (length = rounds)
---@field total_correct number @Total CORRECT verdicts
---@field total_partial number @Total PARTIAL verdicts
---@field total_problems number @Total problems attempted across all rounds
---@field total_wrong number @Total WRONG verdicts

---@class AlcPkgInput_compute_alloc
---@field budget? string @Budget hint: 'low' | 'medium' | 'high' (default: 'medium')
---@field gen_tokens? number @Max tokens per LLM call (default: 400)
---@field strategies? table @Custom difficulty→strategy map (overrides DEFAULT_STRATEGIES)
---@field task string @The problem to solve

---@class AlcPkgResult_compute_alloc
---@field answer string @Final answer produced by the selected paradigm
---@field candidates? string[] @Parallel candidates (set only for parallel / hybrid paradigms)
---@field difficulty string @Classified difficulty: 'easy' | 'medium' | 'hard' | 'very_hard'
---@field paradigm string @Execution paradigm: 'single' | 'parallel' | 'sequential' | 'hybrid'
---@field strategy string @Selected strategy name (e.g., 'direct', 'parallel', 'sequential', 'hybrid')
---@field total_llm_calls number @Total LLM calls (classification + execution)

---@class AlcPkgInput_conformal_vote
---@field agents any @Array of agent specs (prompt string or {prompt,system?,model?,temperature?,max_tokens?} table)
---@field auto_card? boolean @Emit a Card on completion (default: false)
---@field calibration { alpha: number, n: number, q_hat: number, tau: number, weights: table }
---@field card_pkg? string @Card pkg.name override (default: 'conformal_vote_<task_hash>')
---@field gen_tokens? number @Max tokens for LLM generation (default: 400)
---@field options string[] @Candidate label set
---@field scenario_name? string @Explicit scenario name for the emitted Card
---@field task string @Task text presented to each agent

---@alias AlcPkgResult_conformal_vote AlcResultConformalDecided

---@class AlcPkgInput_contrastive
---@field n_contrasts? number @Number of contrast pairs (default: 2)
---@field task string @The problem to solve

---@class AlcPkgResult_contrastive
---@field answer string @Final answer informed by contrast analysis
---@field contrasts { error_analysis: string, wrong_reasoning: string }[] @Per-iteration wrong-reasoning + error-analysis pairs
---@field total_contrasts number @= #contrasts

---@class AlcPkgInput_cot
---@field depth? number @Number of reasoning steps (default: 3)
---@field task string @The question or task to reason about

---@class AlcPkgResult_cot
---@field chain string[] @Ordered insights, one per reasoning step
---@field conclusion string @Synthesized final answer

---@class AlcPkgInput_counterfactual_verify
---@field cf_tokens? number @Max tokens for counterfactual generation (default: 400)
---@field gen_tokens? number @Max tokens for solving (default: 600)
---@field n_counterfactuals? number @Number of counterfactual variants (default: 2)
---@field task string @The problem to solve

---@class AlcPkgResult_counterfactual_verify
---@field answer string @Final answer (original CoT when faithful, re-solved otherwise)
---@field counterfactual_results { actual: string, change: string, match: boolean, predicted: string, reason: string }[] @Per-counterfactual evaluation records
---@field faithful boolean @Whether reasoning is causally faithful to inputs (all CFs matched)
---@field match_count number @Count of counterfactuals where predicted matched actual
---@field mismatches { change: string, reason: string }[] @Subset of counterfactual_results where match=false (empty when faithful)
---@field original_cot string @Original chain-of-thought reasoning for unmodified task
---@field total_counterfactuals number @Total counterfactuals evaluated (= #counterfactual_results)

---@class AlcPkgInput_cove
---@field n_questions? number @Number of verification questions (default: 3)
---@field task string @The question/task to answer

---@class AlcPkgResult_cove
---@field draft string @Baseline draft answer
---@field final_response string @Final answer after fact-check revision
---@field verifications { answer: string, question: string }[] @Per-question verification records (may be shorter than n_questions)

---@class AlcPkgInput_critic
---@field answer? string @Pre-supplied answer to evaluate (default: nil → auto-generate)
---@field eval_tokens? number @Max tokens per dimension evaluation (default: 200)
---@field gen_tokens? number @Max tokens for initial generation (default: 600)
---@field max_revisions? number @Max revision rounds (default: 2)
---@field revise_tokens? number @Max tokens for revision (default: 600)
---@field rubric? any @List of dimensions — either string names or {name, description} tables
---@field task string @The task/question to solve
---@field threshold? number @Minimum acceptable per-dimension score (default: 7)

---@class AlcPkgResult_critic
---@field answer string @Final (possibly revised) answer
---@field avg_score number @Average of final per-dimension scores
---@field history { answer: string, avg_score: number, round: number, scores: { dimension: string, feedback: string, raw: string, score: number }[], weak_count: number }[] @Per-round evaluation trace
---@field initial_answer string @Initial answer before any revisions
---@field revisions number @Number of revision rounds actually performed
---@field rubric { description: string, name: string }[] @Normalized rubric used for evaluation
---@field scores table @Final per-dimension score map (dim_name → number)
---@field threshold number @Threshold value used (echoed from input)

---@class AlcPkgInput_cs_pruner
---@field aggregation? string @Only "scalarize" supported in v0.1
---@field betting_lambda_max? number @Betting λ truncation (default: 0.5)
---@field betting_prior_var? number @Betting σ̂² prior (default: 0.25)
---@field bootstrap_m? number @Howard 2021 eq.(10) bootstrap time (default: 1.0)
---@field cs_variant? string @"polynomial_stitched" | "hoeffding" | "betting" | "kl" (default: polynomial_stitched)
---@field delta? number @Overall error probability (default: 0.05)
---@field gen_tokens? number @Max tokens per candidate generation (default: 400)
---@field halving_checkpoints? number[] @Checkpoint n-values for layer-2 halving (default: {5,10,15})
---@field halving_keep_ratio? number @Fraction kept at each halving (default: 0.5)
---@field halving_min_gap? number @Gap guard around the median (default: 0)
---@field layer2_halving? boolean @Enable Successive Halving as primary kill mechanism (default: false)
---@field min_n_before_kill? number @Warmup minimum before kills are considered
---@field n_candidates? number @Number of candidates (default: 6)
---@field rubric? { criterion: string, name: string }[] @Rubric dimensions (default: 20-dim binary)
---@field score_domain? { max: number, min: number } @Score range (default: {min=0,max=1})
---@field stitching_eta? number @Howard 2021 eq.(10) epoch ratio (default: 2.0)
---@field stitching_s? number @Howard 2021 eq.(10) exponent (default: 1.4)
---@field task string @Problem statement
---@field weights? number[] @Per-dimension weights (default: uniform)

---@class AlcPkgResult_cs_pruner
---@field alive_count number
---@field alpha_per_side number @δ/(2N) for stitched/hoeffding/kl; δ/N for betting
---@field best string @Text of the best surviving candidate
---@field best_index number @1-based index of the winner
---@field best_score number @Empirical mean of the winner
---@field candidates string[] @All generated candidate texts
---@field cs_variant string
---@field delta number
---@field evaluations number @Per-dimension evaluations performed
---@field kill_events { candidate: number, mean: number, n: number }[] @Elimination events (open shape; CS and layer2 events share candidate/n/mean)
---@field n_candidates number
---@field n_dimensions number
---@field protect_events { candidate: number, mean: number, n: number }[] @Layer-2 gap-guard protections (open shape)
---@field ranking { alive: boolean, index: number, lcb: number, mean: number, n: number, radius: number, ucb: number, v_hat: number }[] @All candidates sorted by alive, then mean descending
---@field rounds { candidate: number, dimension: number, dimension_name: string, iteration: number, mean_after: number, n_after: number, score: number, v_hat_after: number }[] @Per-evaluation trace
---@field total_llm_calls number

---@class AlcPkgInput_cumulative
---@field max_rounds? number @Max propose-verify cycles (default: 4)
---@field propositions_per_round? number @Propositions generated per round (default: 2)
---@field task string @The problem to solve

---@class AlcPkgResult_cumulative
---@field answer string @Reporter's synthesis grounded in established facts
---@field established_facts { proposition: string, round: number }[] @Verified propositions accumulated across rounds
---@field rounds { proposed: string[], round: number, verified: { accepted: boolean, proposition: string, verification: string }[] }[] @Per-round propose/verify trace
---@field total_established number @Count of verified propositions
---@field total_rounds number @Number of rounds actually executed (may be < max_rounds due to early termination)

---@class AlcPkgInput_dci
---@field auto_card? boolean @Emit a Card on completion (default: false)
---@field card_pkg? string @Card pkg.name override (default: 'dci_<task_hash>')
---@field gen_tokens? number @Max tokens per LLM generation (default: 400)
---@field max_options? number @Max option count after canonicalize (default: 5)
---@field max_rounds? number @Rmax per DCI-CF (default: 2, paper §5 Table 1)
---@field num_finalists? number @Finalist count after revise (default: 3)
---@field roles? string[] @Role names (default: framer/explorer/challenger/integrator)
---@field scenario_name? string @Explicit scenario name for the emitted Card
---@field task string @Deliberation task / decision question

---@alias AlcPkgResult_dci AlcResultDeliberated

---@class AlcPkgInput_decompose
---@field max_subtasks? number @Maximum sub-tasks to generate (default: 5)
---@field merge_tokens? number @Max tokens for final merge (default: 600)
---@field subtask_tokens? number @Max tokens per sub-task (default: 400)
---@field task string @The complex task to decompose

---@class AlcPkgResult_decompose
---@field answer string @Unified merged answer across sub-tasks
---@field decomposition_raw string @Raw decomposition LLM output before parsing
---@field subtask_results string[] @Per-sub-task LLM outputs, same order as subtasks
---@field subtasks string[] @Parsed sub-task descriptions (fallback: single-element = original task)

---@class AlcPkgInput_deliberate
---@field confidence_threshold? number @Calibrate threshold (default: 0.7)
---@field debate_rounds? number @Triad debate rounds per option (default: 2)
---@field max_options? number @Max options to consider (default: 4)
---@field options? any[] @Pre-defined options (auto-generated if absent); each opaque {name?, description?, strengths?, risks?}
---@field task string @The decision question

---@class AlcPkgResult_deliberate
---@field abstractions any @step_back's abstractions sub-result (opaque; shape owned by step_back)
---@field confidence number @Calibrate confidence score
---@field confidence_escalated boolean @Whether the confidence gate escalated
---@field debates any[] @Per-option triad result {option, verdict, winner}; option is opaque (user-shaped)
---@field expert_analysis string @meta_prompt's aggregated analysis answer
---@field expert_consultations any @meta_prompt's experts_consulted sub-result (opaque; shape owned by meta_prompt)
---@field options any[] @Options actually considered (as supplied or auto-generated)
---@field principles string @Extracted principles and criteria (from step_back)
---@field ranking_matches { a: number, b: number, reason: string, winner: number }[] @Pairwise-tournament match log
---@field recommendation { debate_outcome: string, description?: string, name?: string, ranking_wins: number } @Final recommendation built from the tournament winner
---@field total_options number @Number of options considered

---@class AlcPkgInput_dissent
---@field consensus string @The consensus text to challenge (REQUIRED)
---@field gen_tokens? number @Max tokens per generation (default: 500)
---@field merit_threshold? number @Score threshold for revision (default: 0.6)
---@field perspectives? any[] @Individual agent outputs that formed consensus; elements are either strings or {name?, output? | text?} tables
---@field task string @Original task description

---@class AlcPkgResult_dissent
---@field consensus_held boolean @True iff the original consensus was NOT revised
---@field dissent string @Raw adversarial challenge produced in Phase 1
---@field evaluation string @Raw judge output from Phase 2
---@field key_issues string @Parsed key issues block from judge output (empty string when absent)
---@field merit_score number @Parsed merit score in [0, 1]; 0 on parse failure
---@field output string @Final output — original consensus when held, revised otherwise
---@field revised_consensus? string @Revised consensus text; nil iff no revision was triggered

---@class AlcPkgInput_distill
---@field chunk_overlap? number @Overlap lines between chunks (default 5)
---@field chunk_size? number @Lines per chunk passed to alc.chunk (default 100)
---@field goal? string @What to extract/summarize (default 'Summarize the key points')
---@field map_tokens? number @Max tokens per map call (default 300)
---@field reduce_tokens? number @Max tokens for the final reduce call (default 600)
---@field text string @Source text to process (required)

---@class AlcPkgResult_distill
---@field chunks_processed number @Number of chunks produced by alc.chunk (0 when the input did not split)
---@field extractions? string[] @Per-chunk raw map outputs in chunk order. Present only on the normal path — absent on both early-return paths.
---@field relevant_chunks? number @Count of chunks whose map output was not 'NONE'. Absent on the no-chunks early-return path; present on both the all-filtered and normal paths.
---@field summary string @Final synthesized output. Empty string on the no-chunks early-return path, a canned 'No relevant information' message when every chunk was filtered out, and the reduce-phase LLM output on the normal path.

---@class AlcPkgInput_diverse
---@field n_paths? number @Number of diverse reasoning paths (default: 3)
---@field task string @The problem to solve

---@class AlcPkgResult_diverse
---@field answer string @Final synthesized answer from the best path
---@field best_avg_score number @Average step score of the winning path
---@field best_path_id number @path_id of the highest-scoring path
---@field paths { path_id: number, reasoning: string, verification: { avg_score: number, step_scores: { score: number, step: string }[], total_score: number } }[] @All generated paths with verification details (sorted)
---@field ranking { avg_score: number, path_id: number, rank: number, steps_verified: number }[] @Paths ordered from best to worst by avg_score

---@class AlcPkgInput_dmad
---@field debate_prompt? string @Override DEBATE template (implementation choice)
---@field gen_tokens? number @Max tokens per LLM call (default: 500; implementation choice — paper does not specify)
---@field init_prompt? string @Override INIT template (implementation choice)
---@field n_agents? number @Number of parallel agents (default: 3 per Du repo gen_gsm.py agents=3)
---@field n_rounds? number @Number of debate rounds after init (default: 2 per Du repo gen_gsm.py rounds=2)
---@field system_prompt? string @Override system prompt (implementation choice)
---@field task string @Problem statement (required)
---@field temperature? number @LLM temperature (default: API default; implementation choice — paper does not fix)

---@class AlcPkgResult_dmad
---@field answer string @Final majority-vote answer
---@field debate_log { agent: number, round: number, text: string }[] @Flat chronological log of (agent, round, text) tuples
---@field last_answers string[] @Extracted answer per agent at round R
---@field n_agents number @N actually used
---@field n_rounds number @R actually used
---@field responses string[][] @responses[r+1][i] = a_{i,r} (1-based for Lua); responses[1] = init, responses[R+1] = final
---@field tally { answer: string, count: number }[] @Full vote tally
---@field total_llm_calls number @Total LLM calls made (= N·(R+1))

---@class AlcPkgInput_epidemic_abm
---@field beta? number @Transmission probability per contact (default 0.3)
---@field contacts_per_step? number @Mean contacts per agent per step (default 5)
---@field gamma? number @Recovery probability per step (default 0.1)
---@field initial_infected? number @Initial infected count (default 5)
---@field n_agents? number @Population size (default 200)
---@field runs? number @Monte Carlo runs (default 100)
---@field steps? number @Simulation steps (default 100)
---@field task? string @Task description (free text)

---@class AlcPkgResult_epidemic_abm
---@field params { beta: number, contacts_per_step: number, gamma: number, initial_infected: number, n_agents: number, steps: number }
---@field sensitivity { base_value: number, delta: number, factor: number, high_value: number, low_value: number, param: string, score_at_high: number, score_at_low: number }[]
---@field simulation { attack_rate_mean: number, attack_rate_median: number, attack_rate_p25: number, attack_rate_p75: number, attack_rate_std: number, epidemic_duration_mean: number, epidemic_duration_median: number, epidemic_duration_p25: number, epidemic_duration_p75: number, epidemic_duration_std: number, epidemic_occurred_ci: { lower: number, upper: number }, epidemic_occurred_count: number, epidemic_occurred_rate: number, herd_immunity_reached_ci: { lower: number, upper: number }, herd_immunity_reached_count: number, herd_immunity_reached_rate: number, peak_fraction_mean: number, peak_fraction_median: number, peak_fraction_p25: number, peak_fraction_p75: number, peak_fraction_std: number, runs: number }

---@class AlcPkgInput_evogame_abm
---@field generations? number @Number of generations (default 30)
---@field mutation_rate? number @Mutation rate per offspring (default 0.05)
---@field n_agents? number @Number of agents (default 50)
---@field payoff_matrix? table @Payoff matrix (CC/CD/DC/DD → {a,b} pairs)
---@field rounds_per_gen? number @Games per generation (default 10)
---@field runs? number @Monte Carlo runs (default 100)
---@field strategies? string[] @Initial strategy distribution
---@field task? string @Task description (free text)

---@class AlcPkgResult_evogame_abm
---@field params { generations: number, mutation_rate: number, n_agents: number, payoff_matrix: table, rounds_per_gen: number, strategies?: string[] }
---@field sensitivity { base_value: number, delta: number, factor: number, high_value: number, low_value: number, param: string, score_at_high: number, score_at_low: number }[]
---@field simulation { cooperation_rate_mean: number, cooperation_rate_median: number, cooperation_rate_p25: number, cooperation_rate_p75: number, cooperation_rate_std: number, dominant_fraction_mean: number, dominant_fraction_median: number, dominant_fraction_p25: number, dominant_fraction_p75: number, dominant_fraction_std: number, n_strategies_surviving_mean: number, n_strategies_surviving_median: number, n_strategies_surviving_p25: number, n_strategies_surviving_p75: number, n_strategies_surviving_std: number, runs: number, tft_survived_ci: { lower: number, upper: number }, tft_survived_count: number, tft_survived_rate: number }

---@class AlcPkgInput_f_race
---@field alpha_spending? boolean @Bonferroni sequential correction (default: false)
---@field delta? number @Significance level (default: 0.05); resolved to largest tabulated α ≤ delta
---@field gen_tokens? number @Max tokens per candidate generation (default: 400)
---@field min_blocks_before_race? number @Warmup block count before elimination (default: 5)
---@field n_candidates? number @Number of candidates (default: 6)
---@field rubric? { criterion: string, name: string }[] @Rubric dimensions (default: 20-dim binary)
---@field rubric_type? string @"binary" | "likert5" (default: "binary")
---@field score_domain? { max: number, min: number } @Score range for clipping (default: {min=0,max=1})
---@field task string @Problem statement

---@class AlcPkgResult_f_race
---@field alive_count number @Number of survivors at termination
---@field alpha_spending boolean @Whether Bonferroni sequential correction was applied
---@field best string @Text of the best surviving candidate
---@field best_index number @1-based index of the winner
---@field best_score number @Empirical mean score of the winner
---@field candidates string[] @All generated candidate texts
---@field delta number @User-requested significance level
---@field effective_delta number @Resolved tabulated α (possibly Bonferroni-tightened)
---@field evaluations number @Number of per-dimension evaluations performed
---@field kill_events { best_candidate: number, best_rank_sum: number, block: number, blocks_used: number, candidate: number, chi2_critical: number, crit_diff: number, mean: number, n: number, q: number, rank_sum: number }[] @Elimination events triggered by Friedman+Nemenyi
---@field n_candidates number
---@field n_dimensions number
---@field ranking { alive: boolean, index: number, mean: number, mean_rank?: number, n: number }[] @All candidates sorted by alive+mean_rank/mean descending
---@field rounds { candidate: number, dimension: number, dimension_name: string, iteration: number, n_after: number, score: number }[] @Per-evaluation trace
---@field total_llm_calls number @Candidate generation + evaluation calls

---@class AlcPkgInput_factscore
---@field context? string @Optional reference context for verification
---@field extract_tokens? number @Max tokens for claim extraction (default: 500)
---@field text string @The text to fact-check
---@field verify_tokens? number @Max tokens per claim verification (default: 200)

---@class AlcPkgResult_factscore
---@field claims { claim: string, justification: string, status: string }[] @Per-claim verification records (empty when extraction yields no claims)
---@field score number @Factual precision score = supported / (supported+unsupported); 1.0 when no decisive claims
---@field supported number @Count of SUPPORTED claims
---@field total number @Total number of extracted claims
---@field uncertain number @Count of UNCERTAIN claims
---@field unsupported number @Count of UNSUPPORTED claims

---@class AlcPkgInput_faithful
---@field format? string @Formal representation type: code / logic / auto (default: auto)
---@field gen_tokens? number @Max tokens per step (default: 500)
---@field task string @The problem to solve

---@class AlcPkgResult_faithful
---@field answer string @Final answer grounded in formal verification
---@field errors_found boolean @True if verification surfaced any errors in the reasoning
---@field formal string @Step 2 formal representation (code or logic derivation)
---@field format string @Formal representation actually used: code / logic
---@field nl_reasoning string @Step 1 natural-language reasoning chain
---@field verification string @Step 3 verification output

---@class AlcPkgInput_falsify
---@field derive_on_refute? boolean @Generate successor hypotheses from refuted ones (default: true)
---@field initial_hypotheses? number @Seed hypothesis count (default: 4)
---@field max_hypotheses? number @Upper bound on active hypotheses (default: 12)
---@field max_rounds? number @Maximum falsification rounds (default: 3)
---@field task string @The problem or question to investigate

---@class AlcPkgResult_falsify
---@field all_hypotheses { confidence: number, derived_from?: number, history: { refutation: string, round: number, verdict: string }[], id: number, refutation_attempts: number, status: string, text: string }[] @All hypotheses (initial + derived), survivors and refuted alike
---@field answer string @Synthesized final answer from surviving hypotheses (or post-all-refuted fallback)
---@field stats { initial_count: number, rounds: number, total_derived: number, total_generated: number, total_refuted: number, total_survived: number } @Aggregate falsification statistics
---@field survivors { confidence: number, derived_from?: number, history: { refutation: string, round: number, verdict: string }[], id: number, refutation_attempts: number, status: string, text: string }[] @Hypotheses that survived all refutation rounds

---@class AlcPkgInput_got
---@field agg_tokens? number @Max tokens for Aggregate / final synthesis (default: 500)
---@field gen_tokens? number @Max tokens for Generate step (default: 300)
---@field k_generate? number @Branches per Generate (default: 3)
---@field keep_best? number @Nodes to keep after KeepBest pruning (default: 2)
---@field max_refine? number @Max refinement rounds on kept thoughts (default: 2)
---@field refine_tokens? number @Max tokens for Refine step (default: 400)
---@field task string @The problem to solve

---@class AlcPkgResult_got
---@field aggregated_reasoning string @State of the merged node produced by the Aggregate op (after final Refine)
---@field answer string @Final synthesized answer from the aggregated reasoning
---@field graph_stats { branches_generated: number, branches_kept: number, operations: table<string, number>, refine_rounds: number, total_nodes: number } @Graph-shape diagnostics; operations is { [origin_op] = count }

---@class AlcPkgInput_gumbel_search
---@field eval_tokens? number @Max tokens for evaluation (default: 100)
---@field gen_tokens? number @Max tokens for generation (default: 400)
---@field initial_candidates? number @Number of initial candidates (default: 8)
---@field task string @The problem to solve

---@class AlcPkgResult_gumbel_search
---@field answer string @Winning candidate's response text
---@field best_index number @1-based index of the winning candidate
---@field best_score number @Final mean score of the winner in [0,1]
---@field candidates { index: number, mean_score: number, n_evals: number }[] @All candidates' final state (order preserved from generation)
---@field halving_rounds number @Number of Sequential Halving rounds executed
---@field total_evaluations number @Total per-candidate evaluations across rounds
---@field total_llm_calls number @Total LLM calls (generation + evaluations)

---@class AlcPkgInput_hegelian
---@field N? number @Max iterations (default: 5 per Abdali Table 2 "Max iterations")
---@field antithesis_prompt? string @Override antithesis prompt template (implementation choice — paper specifies role but not wording)
---@field gen_tokens? number @Max tokens per LLM call (default: 600; implementation choice — paper does not specify)
---@field synthesis_prompt? string @Override synthesis prompt template (implementation choice — paper specifies role but not wording)
---@field system_antithesis? string @Override antithesis system prompt (implementation choice)
---@field system_synthesis? string @Override synthesis system prompt (implementation choice)
---@field system_thesis? string @Override thesis system prompt (implementation choice)
---@field task string @Task or question (required)
---@field tau_0? number @Initial temperature (default: 0.7 per Abdali Table 2 "Initial temperature")
---@field tau_a? number @Antithesis/opposition temperature (default: 0.5 per Abdali Table 2 "Opposition temperature")
---@field thesis_prompt? string @Override thesis prompt template (implementation choice — paper specifies role but not wording)
---@field theta? number @Decay constant θ ∈ [0.1, 0.5] (default: 0.3; implementation choice within the paper's stated range from Table 2)

---@class AlcPkgResult_hegelian
---@field N number @Number of iterations actually executed
---@field answer string @Final synthesis S_{N-1}; alias of result.final_synthesis
---@field final_synthesis string @S_{N-1} — final integrated position
---@field iterations { antithesis: string, iteration: number, synthesis: string, tau_i: number }[] @Per-iteration log: { i, A_i, τ(i), S_i } for i = 0..N-1
---@field thesis_0 string @Initial thesis T_0 from bootstrap LLM call

---@class AlcPkgInput_intent_belief
---@field confidence_threshold? number @Stop when top hypothesis exceeds this (default 0.7)
---@field diagnose_tokens? number @Max tokens per diagnostic question (default 400)
---@field max_rounds? number @Maximum belief update rounds (default 3)
---@field n_hypotheses? number @Number of intent hypotheses to generate (default 5)
---@field prior_tokens? number @Max tokens for prior generation (default 600)
---@field task string @Initial user request (required)
---@field update_tokens? number @Max tokens per belief update (default 500)

---@class AlcPkgResult_intent_belief
---@field converged? boolean @Whether MAP exceeded confidence_threshold before max_rounds (success path)
---@field error? string @Set only on prior-parse failure; success path omits this
---@field final_entropy? number @Shannon entropy of final posterior (success path)
---@field map_confidence? number @Posterior probability of MAP hypothesis (success path)
---@field map_hypothesis? string @Description of maximum-a-posteriori hypothesis (success path)
---@field original_task? string @Echo of input task (success path)
---@field ranked_hypotheses? { belief: number, description: string, id: number }[] @All hypotheses sorted by posterior desc (success path)
---@field raw? string @Raw prior LLM output; present only on error path
---@field rounds? number @Number of update rounds actually executed (success path)
---@field specified_task? string @LLM-rewritten task aligned to MAP hypothesis (success path)
---@field update_log? { answer: string, entropy: number, likelihoods: number[], posterior: number[], prior: number[], question: string, round: number }[] @Per-round Bayesian update trace (success path)

---@class AlcPkgInput_intent_discovery
---@field concretize_tokens? number @Max tokens for concretization (default 500)
---@field max_rounds? number @Maximum exploration rounds (default 3)
---@field n_options? number @Number of options to present per round (default 3)
---@field surface_tokens? number @Max tokens for option generation (default 600)
---@field task string @Initial (possibly vague) user request (required)

---@class AlcPkgResult_intent_discovery
---@field converged boolean @Whether exploration ended early via CONVERGENCE:YES or empty remaining
---@field exploration_log { key_dimension: string, options: { description: string, label: string, title: string }[], preference: string, round: number }[] @Per-round record of options, key_dimension, and user preference
---@field intent_hierarchy { remaining: string, resolved: string, understanding: string }[] @Per-round resolved/remaining/understanding trace (round-indexed, 1-based)
---@field original_task string @Echo of input task
---@field rounds number @Number of exploration rounds actually executed
---@field specified_task string @Current understanding after final round

---@class AlcPkgInput_isp_aggregate
---@field agents? any @Array of agent specs (string prompt | {prompt,system?,model?,temperature?,max_tokens?} table). Default: diversity-hinted builder of length n.
---@field calibration? any @Output of M.calibrate. REQUIRED for method ∈ {isp, ow_l, ow_i}.
---@field gen_tokens? number @Max tokens per 1st-order LLM call (default 200).
---@field method? "isp"|"ow"|"ow_l"|"ow_i"|"meta_prompt_sp" @Aggregator. Default 'isp'. 'meta_prompt_sp' is NOT paper-faithful.
---@field n? number @Agent count when `agents` is nil (default 5).
---@field options string[] @Candidate labels
---@field second_order_gen_tokens? number @Only used with method='meta_prompt_sp' (default 400).
---@field task string @Question text presented to each agent
---@field tie_break? "first_in_options"|"uniform_random" @Score-tie rule (default 'first_in_options').
---@field x_direct? number[] @REQUIRED for method='ow'. Length = #agents; each x_i ∈ [0,1].
---@field x_eps? number @Clamp floor for σ_K⁻¹ input (default 1e-6).

---@alias AlcPkgResult_isp_aggregate AlcResultIspVoted

---@class AlcPkgInput_least_to_most
---@field max_subproblems? number @Maximum number of subproblems (default: 5)
---@field task string @The problem to solve

---@class AlcPkgResult_least_to_most
---@field answer string @Synthesized final answer
---@field subproblems { solution: string, subproblem: string }[] @Ordered subproblem/solution pairs (simplest first)
---@field total_subproblems number @Count of subproblems parsed and solved

---@class AlcPkgInput_lineage
---@field extract_tokens? number @Max tokens per claim extraction (default 600)
---@field steps { name: string, output: string }[] @Ordered step outputs; at least 2 entries (required)
---@field summary_tokens? number @Max tokens for conflict/integrity summary (default 600)
---@field task string @Original task description passed to trace/summary prompts (required)
---@field trace_tokens? number @Max tokens per dependency trace (default 500)

---@class AlcPkgResult_lineage
---@field analysis string @Full conflict/ungrounded/drift analyzer output
---@field integrity_score? number @Parsed SCORE in [0, 1]; nil when the analyzer did not emit a parseable score
---@field lineage_graph string @Human-readable lineage graph text used as input to the conflict analyzer
---@field step_claims { claims: { id: number, text: string }[], name: string, raw: string }[] @Per-step extracted claims
---@field traces { from_step: string, raw: string, to_step: string, traces: { derives_from?: any[], id: number, transformation?: string }[] }[] @Consecutive-step dependency traces

---@alias AlcPkgResult_listwise_rank AlcResultListwiseRanked

---@class AlcPkgInput_maieutic
---@field consistency_tokens? number @Max tokens per consistency check (default: 100)
---@field gen_tokens? number @Max tokens per explanation (default: 300)
---@field max_depth? number @Tree depth (default: 2)
---@field proposition string @The claim to analyze

---@class AlcPkgResult_maieutic
---@field consistency { consistent: number, contradictory: number, independent: number } @Status histogram across the whole tree
---@field evidence { oppose: string[], support: string[] } @Propositions that passed consistency check, grouped by stance
---@field synthesis string @Final LLM synthesis grounded on consistent evidence
---@field tree any @Recursive explanation tree (unvalidated in V0 due to self-referencing shape)
---@field verdict string @Extracted verdict: likely true / likely false / insufficient evidence / unknown

---@class AlcPkgInput_mbr_select
---@field criteria? string @Similarity criteria (default: substantive agreement)
---@field gen_tokens? number @Max tokens per candidate (default: 400)
---@field n? number @Number of candidates to generate (default: 5)
---@field sim_tokens? number @Max tokens per similarity judgment (default: 80)
---@field task string @The task to generate candidates for

---@class AlcPkgResult_mbr_select
---@field best string @Text of the MBR-selected candidate
---@field best_index number @1-based index of the selected candidate
---@field best_mbr_score number @Expected similarity score (0-1) of the winner
---@field candidates string[] @All generated candidate texts
---@field ranking { index: number, mbr_score: number }[] @All candidates sorted by MBR score descending
---@field similarity_matrix number[][] @Symmetric N×N pairwise similarity matrix (values in [0, 1])
---@field total_llm_calls number @Generation calls (N) + pairwise similarity calls (N(N-1)/2)

---@class AlcPkgInput_mcts
---@field exploration? number @UCB1 exploration constant C (default: √2 ≈ 1.41)
---@field iterations? number @Number of MCTS iterations (default: 6)
---@field max_depth? number @Maximum tree depth per rollout (default: 3)
---@field max_reflections? number @Maximum stored reflections (default: 5)
---@field reflection? boolean @Enable reflection on low-score paths (default: false)
---@field reflection_threshold? number @Score below which reflection triggers (default: 4)
---@field task string @The problem to solve

---@class AlcPkgResult_mcts
---@field best_path { avg_score: number, thought: string, visits: number }[] @Best path from root to leaf
---@field conclusion string @Synthesized final answer from the best path
---@field total_iterations number @Iterations actually performed
---@field tree_stats { exploration_constant: number, max_depth: number, root_children: number, root_visits: number } @Tree-level statistics

---@class AlcPkgInput_meta_prompt
---@field max_experts? number @Maximum number of expert consultations (default: 4)
---@field task string @The problem to solve

---@class AlcPkgResult_meta_prompt
---@field answer string @Orchestrator's integrated synthesis of all expert analyses
---@field experts_consulted { focus: string, question: string, response: string, role: string }[] @Sequential expert consultations with the question asked and the response received
---@field total_experts number @Count of experts actually consulted (may be < max_experts due to parsing fallback)

---@class AlcPkgInput_moa
---@field aggregator_prompt? string @Override AS_PROMPT_TEMPLATE; replacing it drops the paper's effect guarantee
---@field aggregator_tokens? number @Max tokens per aggregator (default: 2048; implementation choice — sized larger than per-proposer to accommodate synthesizing n outputs)
---@field n_layers? number @Number of layers L (default: 3 per Wang §3 "We use 3 MoA layers")
---@field personas? string[] @Single-model rotation PATH (outside Wang §3 main config): array of system-prompt strings
---@field proposer_prompt? string @Override proposer prompt (implementation choice — paper does not specify wording)
---@field proposer_tokens? number @Max tokens per proposer (default: 512; implementation choice — paper does not specify)
---@field proposers? { model?: string, system?: string }[] @Multi-model PATH (Wang §3 main config): array of proposer specs; each layer reuses the same list
---@field system_prompt? string @Override proposer system prompt (implementation choice — paper does not specify)
---@field task string @Problem statement (required)
---@field temperature? number @LLM temperature (default: 0.7; implementation choice — Wang §3 main config does not state a value, 0.7 is the only numeric value §3 names in the single-proposer ablation row)

---@class AlcPkgResult_moa
---@field answer string @Final aggregator output from layer L
---@field layers { aggregated: string, layer: number, proposers: { model?: string, proposer: number, text: string }[] }[] @Per-layer records: proposer outputs + aggregator output
---@field n_layers number @L actually executed
---@field n_proposers number @n actually used (from proposers / personas length)
---@field total_llm_calls number @Total LLM calls (= L · (n + 1))

---@class AlcPkgInput_model_first
---@field extract? boolean @Extract concise final answer (default true)
---@field model_tokens? number @Max tokens for model construction (default 500)
---@field solve_tokens? number @Max tokens for solve/verify/repair steps (default 600)
---@field task string @Problem to solve (required)
---@field verify? boolean @Run constraint-verification + repair step (default true)

---@class AlcPkgResult_model_first
---@field answer string @Final answer (concise extract when extract=true, otherwise the verified solution)
---@field model string @Raw problem model text (entities / state vars / actions / constraints)
---@field solution string @Verified solution text; equals the initial solution when verify=false or no violations
---@field verified boolean @Whether the verification step actually ran (mirrors input.verify)
---@field violations string[] @Parsed violation descriptions; empty when verify=false or no violations
---@field violations_found number @Count of constraint violations parsed from the verification LLM output (0 when verify=false)

---@class AlcPkgInput_negation
---@field answer? string @Pre-supplied answer to test (auto-generated if nil)
---@field gen_tokens? number @Max tokens for generation / condition listing (default: 600)
---@field max_conditions? number @Max destruction conditions to generate (default: 5)
---@field revise_tokens? number @Max tokens for revision (default: 600)
---@field task string @The task/question to solve
---@field verify_tokens? number @Max tokens per condition verification (default: 200)

---@class AlcPkgResult_negation
---@field answer string @Final answer (original when survived, revised when conditions held)
---@field conditions { condition: string, raw: string, reasoning: string, verdict: string }[] @Per-condition verification records (empty when no conditions parsed)
---@field holding number @Count of conditions judged to HOLD
---@field initial_answer? string @Answer tested this round (omitted when no conditions parsed)
---@field refuted number @Count of conditions judged REFUTED
---@field revised boolean @Whether revision round ran (holding > 0)
---@field survived boolean @Whether every destruction condition was refuted (holding==0)
---@field total number @Total conditions evaluated (= #conditions)

---@class AlcPkgInput_opinion_abm
---@field epsilon? number @Bounded-confidence threshold (default 0.25)
---@field initial_distribution? string @'uniform' | 'bimodal' | 'clustered' (default 'uniform')
---@field n_agents? number @Number of agents (default 50)
---@field runs? number @Monte Carlo runs (default 100)
---@field steps? number @Simulation steps (default 50)
---@field task? string @Task description (free text)

---@class AlcPkgResult_opinion_abm
---@field params { distribution: string, epsilon: number, n_agents: number, steps: number }
---@field sensitivity { base_value: number, delta: number, factor: number, high_value: number, low_value: number, param: string, score_at_high: number, score_at_low: number }[]
---@field simulation { clusters_mean: number, clusters_median: number, clusters_p25: number, clusters_p75: number, clusters_std: number, consensus_ci: { lower: number, upper: number }, consensus_count: number, consensus_rate: number, converged_ci: { lower: number, upper: number }, converged_count: number, converged_rate: number, polarized_ci: { lower: number, upper: number }, polarized_count: number, polarized_rate: number, runs: number, variance_mean: number, variance_median: number, variance_p25: number, variance_p75: number, variance_std: number }

---@class AlcPkgInput_optimize
---@field auto_card? boolean @Emit a Card on completion (default: false)
---@field card_pkg? string @Card pkg.name override (default: 'optimize_{target}')
---@field defaults? table @Base parameter defaults merged with arm params
---@field eval_fn? any @Custom evaluation function (only for evaluator='custom')
---@field evaluator? any @Evaluator — name string or config table (default: 'evalframe')
---@field name? string @Run name used as state key suffix (default: ctx.target)
---@field rounds? number @Max optimization rounds (default: 20)
---@field scenario any @Eval scenario — inline table or scenario name string
---@field scenario_name? string @Explicit scenario name for the emitted Card
---@field search? any @Search strategy — name string or config table (default: 'ucb')
---@field space table @Parameter search space (map of param_name → def {type, min, max, step, values})
---@field stop? any @Stopping criterion — name string or config table (default: 'variance')
---@field stop_config? table @Extra config for stopping criterion
---@field strategy_opts? table @Extra opts passed through to the target strategy
---@field target string @Strategy package name to optimize (e.g., 'biz_kernel')

---@class AlcPkgResult_optimize
---@field arm_count number @Number of distinct arms in history
---@field best_params table @Best-ranked parameter set
---@field best_score number @Average score of best_params
---@field card_id? string @Emitted Card id (only when auto_card=true)
---@field history_key string @alc.state key for the persisted history
---@field rounds_used number @Actual rounds executed this run
---@field status string @'converged' (stopper fired) or 'budget_exhausted'
---@field stop_reason? string @Stopper's reason string; nil when budget_exhausted
---@field top_5 { avg_score: number, params: table, pulls: number }[] @Top-5 ranked arms (may contain fewer than 5)
---@field total_evaluations number @Cumulative evaluations in history (including prior runs)

---@class AlcPkgInput_orch_adaptive
---@field depth_config? any @Custom difficulty→config mapping (opaque)
---@field difficulty? string @Pre-classified difficulty (simple|medium|complex)
---@field on_fail? string @"error" | "partial" (default: "error")
---@field phases any[] @Phase definitions (superset; trimmed by difficulty)
---@field task string @Task description

---@class AlcPkgResult_orch_adaptive
---@field active_phase_count number @Phases actually run (min(max_phases, #phases))
---@field depth_config table @Active depth config (max_phases / max_retries / context_mode / max_tokens)
---@field difficulty string @Final difficulty (pre-classified or estimated)
---@field final_output string @Last phase output (empty on failure before first phase)
---@field phases { attempts: number, gate_passed: boolean, name: string, output: string }[] @Per-phase execution record
---@field status string @"completed" / "failed" / "partial"
---@field total_llm_calls number @Total LLM invocations
---@field total_phase_count number @Original phase count

---@class AlcPkgInput_orch_escalate
---@field levels? any[] @Custom escalation chain [{name, prompt_template|multi_phase, threshold, ...}]
---@field on_fail? string @"error" | "partial" (default: "partial")
---@field task string @Task description

---@class AlcPkgResult_orch_escalate
---@field escalation_depth number @1-based index of the level that produced the selected output
---@field levels { feedback: string, name: string, output: string, passed: boolean, phase_outputs?: string[], score: number, threshold: number }[] @Per-level execution record (up to escalation_depth)
---@field output string @Final selected output text
---@field score number @Evaluator score (1-10) of the selected output
---@field selected_level string @Level name whose output was returned (best effort on exhaustion)
---@field status string @"completed" / "failed" / "partial"
---@field total_llm_calls number @Total LLM invocations

---@class AlcPkgInput_orch_fixpipe
---@field context_mode? string @"summary" | "full" (default: "summary")
---@field max_retries? number @Gate NG retry limit (default: 3)
---@field on_fail? string @"error" | "partial" (default: "error")
---@field phases any[] @Phase definitions (opaque user-supplied records)
---@field task string @Task description

---@class AlcPkgResult_orch_fixpipe
---@field final_output string @Last phase output (empty on failure before first phase)
---@field phases { attempts: number, gate_passed: boolean, name: string, output: string }[] @Per-phase execution record
---@field status string @"completed" / "failed" / "partial"
---@field total_llm_calls number @Total LLM invocations

---@class AlcPkgInput_orch_gatephase
---@field max_retries? number @Gate NG retry limit (default: 3)
---@field on_fail? string @"error" | "partial" (default: "error")
---@field phases any[] @Phase definitions [{name, prompt, gate, checks, ...}, ...]
---@field skip_rules? any @Custom skip rules table (opaque)
---@field task string @Task description
---@field task_type? string @Pre-classified type (bugfix|typo|refactor|feature|test)

---@class AlcPkgResult_orch_gatephase
---@field final_output string @Last phase output (empty on failure before first phase)
---@field phases { attempts: number, gate_passed: boolean, name: string, output: string }[] @Per-phase execution record (active only)
---@field skipped_phases string[] @Phase names skipped for this task_type
---@field status string @"completed" / "failed" / "partial"
---@field task_type string @Final task type (pre-classified or estimated)
---@field total_llm_calls number @Total LLM invocations

---@class AlcPkgInput_orch_nver
---@field n? number @Number of parallel variants (default: 3)
---@field phases? any[] @Phase definitions for each variant's pipeline
---@field selection? string @"score" | "vote" (default: "score")
---@field task string @Task description

---@class AlcPkgResult_orch_nver
---@field best_reasoning? string @Reasoning for the top-ranked variant (score-branch only)
---@field best_score? number @Highest score (score-branch only)
---@field method string @Selection method actually used ("score" | "vote")
---@field rankings? { output: string, phase_outputs?: { name: string, output: string }[], reasoning: string, score: number, variant_id: number }[] @Variants sorted by score desc (score-branch only)
---@field selected string @Selected variant's final output
---@field status string @"completed"
---@field total_llm_calls number @Total LLM invocations
---@field variants? { output: string, phase_outputs?: { name: string, output: string }[], variant_id: number }[] @Raw variants (vote-branch only)

---@class AlcPkgInput_p_tts
---@field gen_tokens? number @Max tokens for solving (default: 600)
---@field max_constraints? number @Max constraints to generate (default: 6)
---@field max_repairs? number @Max repair attempts (default: 2)
---@field plan_tokens? number @Max tokens for planning (default: 400)
---@field task string @The task/question to solve
---@field verify_tokens? number @Max tokens per constraint check (default: 150)

---@class AlcPkgResult_p_tts
---@field all_passed boolean @Whether all constraints passed
---@field answer string @Final answer after verify+repair
---@field constraints string[] @Verifiable constraints the answer must satisfy
---@field fail_count number @Number of constraints failing in the final round
---@field history { answer: string, attempt: number, fail_count: number, pass_count: number, results: { constraint: string, reason: string, verdict: "pass"|"fail" }[] }[] @Per-round repair history
---@field pass_count number @Number of constraints passing in the final round
---@field plan string @Planning phase LLM output
---@field repairs number @Number of repair rounds performed
---@field total_constraints number @Total number of constraints generated

---@alias AlcPkgResult_pairwise_rank AlcResultPairwiseRanked

---@alias AlcPkgResult_panel AlcResultPaneled

---@class AlcPkgInput_particle_infer
---@field aggregation? "product"|"min"|"last"|"model" @PRM step→scalar reduction (§3.2). Default 'product'.
---@field auto_card? boolean @Emit a Card on completion (default false)
---@field card_pkg? string @Card pkg.name override (default 'particle_infer_<task_hash>')
---@field continue_fn? any @OPTIONAL. Per-particle stop predicate. fn(partial_answer) → boolean. Default: max_steps-only termination.
---@field ess_threshold? number @0.0 (default) = every-step resample (paper-faithful). > 0 switches to ESS-triggered resample (NOT paper-faithful).
---@field final_selection? "orm"|"argmax_weight"|"weighted_vote" @Paper uses 'orm'. 'weighted_vote' is NOT paper-faithful.
---@field gen_tokens_step? number @Tokens per step LLM call (default 200)
---@field llm_temperature? number @LLM sampling temperature (default 0.8)
---@field max_steps? number @T cap (default 8)
---@field n_particles? number @N (default 8, paper §4.4)
---@field orm_fn? any @OPTIONAL. Outcome Reward Model for final selection (paper §3 end). fn(final_answer, task) → ℝ. Falls back to argmax-weight selection when nil.
---@field prm_fn any @REQUIRED. Process Reward Model. fn(partial_answer, task) → r ∈ [0, 1]. Called N × max_steps times. Runtime type-checked.
---@field scenario_name? string @Explicit scenario name for emitted Card
---@field softmax_temp? number @Softmax temperature T in softmax(w/T). Paper Alg.1 default 1.0.
---@field task string @Problem statement fed to LLM + prm_fn + orm_fn
---@field weight_scheme? "log_linear"|"logit_replace" @Per-step weight formula. 'log_linear' (default, paper-faithful): w_t = log(r̂_t), θ ∝ r̂_t (paper §3.1 Alg.1 + Theorem 1). 'logit_replace' (NOT paper-faithful, its_hub ref-impl compat): w_t = logit(r̂_t), θ ∝ r̂_t/(1-r̂_t).

---@alias AlcPkgResult_particle_infer AlcResultParticleInferred

---@class AlcPkgInput_pbft
---@field f? number @Assumed Byzantine faults (default: 0)
---@field gen_system? string @Custom system prompt for proposal phase
---@field gen_tokens? number @Max tokens per proposal (default: 400)
---@field n_agents? number @Number of agents (default: 3, must satisfy n >= 3f+1)
---@field synth_system? string @Custom system prompt for synthesis phase
---@field synth_tokens? number @Max tokens for synthesis (default: 500)
---@field task string @The problem to solve
---@field vote_system? string @Custom system prompt for voting phase
---@field vote_tokens? number @Max tokens per vote (default: 200)

---@class AlcPkgResult_pbft
---@field answer string @Committed answer (winning proposal or synthesized)
---@field bft_valid boolean @True when bft.validate(n, f) passed (always true if we reach here)
---@field commit_method string @"quorum" (2f+1 agreement) | "synthesis" (no consensus)
---@field f_assumed number @Byzantine-fault budget passed to bft
---@field n_agents number @Number of agents actually used
---@field proposals string[] @Raw proposals from Phase 1 (always preserved per N2 Red Line)
---@field quorum_met boolean @True iff winner_votes >= quorum_required
---@field quorum_required number @BFT threshold = n - f
---@field vote_distribution { proposal: number, votes: number }[] @Vote counts sorted desc by votes
---@field votes number[] @Per-agent vote (proposal index); falls back to own index on parse failure
---@field winner_proposal number @Proposal index with plurality (arbitrary tie-break order)
---@field winner_votes number @Vote count for winner_proposal

---@class AlcPkgInput_php
---@field max_rounds? number @Maximum hint-retry cycles (default: 4)
---@field task string @The problem to solve

---@class AlcPkgResult_php
---@field answer string @Final answer at convergence (or last round)
---@field conclusion string @Extracted core conclusion of the final answer
---@field converged boolean @True iff the last two rounds' conclusions match
---@field rounds { answer: string, conclusion: string, hint_used: boolean, round: number }[] @Per-round execution record
---@field total_rounds number @Total rounds actually executed

---@class AlcPkgInput_plan_solve
---@field extract? boolean @Extract concise final answer (default: true)
---@field plan_tokens? number @Max tokens for plan generation (default: 300)
---@field solve_tokens? number @Max tokens for execution (default: 500)
---@field task string @The problem to solve

---@class AlcPkgResult_plan_solve
---@field answer string @Final answer (extracted or raw execution)
---@field execution string @Full step-by-step execution trace
---@field plan string @Numbered plan devised in Step 1
---@field plan_steps number @Count of numbered steps parsed from plan

---@class AlcPkgInput_pre_mortem
---@field context? string @Additional verification context (e.g., known constraints)
---@field extract_tokens? number @Max tokens for prereq extraction (default: 500)
---@field n_contrasts? number @Contrastive pairs per proposal (default: 1)
---@field proposals any @Array of proposal strings or a single block to decompose
---@field task string @Original task/question addressed by the proposals
---@field threshold? number @Calibrate confidence threshold (default: 0.6)
---@field verify_tokens? number @Max tokens per prereq verification (default: 200)

---@class AlcPkgResult_pre_mortem
---@field accepted number @Count of accepted proposals
---@field needs_investigation number @Count of low-confidence proposals needing escalation
---@field proposals { calibrate_detail: table, confidence: number, contrastive_answer: string, prerequisites: table, proposal: string, rank?: number, rejection_reasons: string[], status: string, verdict: string }[] @Sorted evaluation records: ranked accepted → needs_investigation → rejected
---@field ranking { calibrate_detail: table, confidence: number, contrastive_answer: string, prerequisites: table, proposal: string, rank: number, rejection_reasons: string[], status: string, verdict: string }[] @Accepted proposals in tournament-ranked order (empty when none accepted)
---@field rejected number @Count of rejected proposals
---@field total number @Total evaluated proposals

---@class AlcPkgInput_prism
---@field clarify_tokens? number @Max tokens per clarification phase (default 400)
---@field decompose_tokens? number @Max tokens for decomposition phase (default 600)
---@field max_sub_intents? number @Maximum sub-intents to extract (default 8)
---@field task string @Task or request to analyze (required)

---@class AlcPkgResult_prism
---@field clarifications { question: string, sub_intent: string, sub_intent_index: number }[] @Empty when task was fully specified; otherwise one entry per underspecified sub-intent
---@field dependencies { from: number, to: number }[] @Empty when task was fully specified or no dependencies detected
---@field specified_task string @Fully-specified task (equals input task when was_underspecified=false)
---@field sub_intents { status: "specified"|"underspecified", text: string }[] @All extracted sub-intents in natural parse order
---@field user_response? string @Raw alc.specify response; present only when was_underspecified=true
---@field was_underspecified boolean @Whether any sub-intent required clarification

---@class AlcPkgInput_prompt_breed
---@field crossover_rate? number @Probability of crossover vs mutation for offspring (default 0.3)
---@field evaluator string @Evaluation criteria/prompt used by evaluate_prompt (required)
---@field generations? number @Number of evolution generations (default 8)
---@field hyper_mutation_rate? number @Per-mutation-prompt probability of meta-mutation (default 0.15)
---@field mutation_pool? number @Number of mutation meta-prompts (default 3)
---@field population_size? number @Number of task prompts in the population (default 6)
---@field task string @Task domain description used in all prompts (required)

---@class AlcPkgResult_prompt_breed
---@field best_prompt string @Highest-scoring task prompt encountered across the entire run
---@field best_score number @Score of best_prompt
---@field evolution_history { avg_score: number, best_score: number, generation: number }[] @Per-generation best/avg summary
---@field mutation_prompts string[] @Final mutation meta-prompts (after hyper-mutation)
---@field population { prompt: string, rank: number, score: number }[] @Final population sorted descending by score
---@field stats { crossover_rate: number, generations: number, hyper_mutation_rate: number, mutation_pool: number, population_size: number }

---@class AlcPkgInput_qdaif
---@field elite_tokens? number @Max tokens for candidate generation (default: 400)
---@field features { bins: string[], name: string }[] @Feature axes defining the MAP-Elites grid
---@field iterations? number @Mutation-evaluation cycles (default: 20)
---@field seed_count? number @Initial candidates to generate (default: 5)
---@field task string @Problem / domain description

---@class AlcPkgResult_qdaif
---@field archive { candidate: string, cell: string, features: string[], score: number }[] @Archive elites sorted by score descending
---@field best? string @Archive-best candidate (nil if archive empty)
---@field best_score number @Best score across the archive
---@field coverage number @filled_cells / total_cells ∈ [0,1]
---@field stats { filled_cells: number, iterations: number, seed_count: number, total_cells: number } @Quality-diversity statistics

---@alias AlcPkgResult_rank AlcResultTournament

---@alias AlcPkgResult_recipe_deep_panel AlcResultDeepPaneled

---@alias AlcPkgResult_recipe_quick_vote AlcResultQuickVoted

---@alias AlcPkgResult_recipe_ranking_funnel AlcResultFunnelRanked

---@alias AlcPkgResult_recipe_safe_panel AlcResultSafePaneled

---@class AlcPkgInput_reconcile
---@field agents? { model?: string, system?: string }[] @Diverse-LLM PATH (Chen §3 main config): array of agent specs
---@field confidence_buckets? { lo: number, lo_op?: string, weight: number }[] @Override the §B.5 5-bucket calibration; replacing it drops the paper's weighting guarantee. See M.CONFIDENCE_BUCKETS for the shape contract.
---@field convincing_count? number @Convincing-sample count (default: 4 per Chen §4 footnote "4 in our experiments")
---@field discussion_prompt? string @Override Phase 2 prompt (implementation choice — paper specifies elicited information but not exact wording)
---@field gen_tokens? number @Max tokens per LLM call (default: 600; implementation choice — paper does not specify)
---@field init_prompt? string @Override Phase 1 prompt (implementation choice — paper specifies elicited information but not exact wording)
---@field max_rounds? number @Max discussion rounds R (default: 3 per Chen §3 "up to three discussion rounds")
---@field parse_fn? any @Custom (answer, explanation, confidence) parser fn(raw) → { answer, explanation, confidence } (implementation choice)
---@field personas? string[] @Single-model rotation PATH (outside Chen §3 main config): persona system prompts
---@field system_prompt? string @Override system prompt (implementation choice — paper does not fix)
---@field task string @Problem statement (required)
---@field temperature? number @LLM temperature (default: API default; implementation choice — Chen §3 does not state a value)

---@class AlcPkgResult_reconcile
---@field answer string @Final team answer (normalized form of winning bucket)
---@field consensus boolean @true if all agents agreed at termination round; false if R+1 rounds exhausted
---@field history { agent: number, answer: string, confidence: number, explanation: string, normalized: string, raw_text?: string, round: number, weight: number }[][] @history[r+1][i] = agent i's response at round r
---@field n_agents number @N actually used
---@field rounds_used number @Number of rounds completed (1..R+1; 1 = consensus at init phase)
---@field tally { answer: string, count: number, weight: number }[] @Vote tally at termination round
---@field total_llm_calls number @Total LLM calls actually made

---@class AlcPkgInput_reflect
---@field critique_tokens? number @Max tokens for critique (default: 300)
---@field gen_tokens? number @Max tokens for generation (default: 500)
---@field initial_draft? string @Pre-generated draft to refine (skips initial LLM generation)
---@field max_rounds? number @Maximum critique-revise cycles (default: 3)
---@field stop_when? string @Stop condition: 'no_major_issues' or 'no_issues' (default: 'no_major_issues')
---@field task string @The task to perform

---@class AlcPkgResult_reflect
---@field converged boolean @Whether the last round converged
---@field output string @Final refined draft
---@field rounds { converged: boolean, critique: string, round: number }[] @Ordered critique rounds with convergence flag
---@field total_rounds number @Number of critique rounds executed

---@class AlcPkgInput_reflexion
---@field evaluator? string @Custom evaluation prompt
---@field gen_tokens? number @Max tokens per attempt (default: 500)
---@field max_trials? number @Maximum number of attempts (default: 3)
---@field reflect_tokens? number @Max tokens per reflection (default: 300)
---@field success_threshold? number @Score threshold to accept, 1-10 scale (default: 8)
---@field task string @The task to solve

---@class AlcPkgResult_reflexion
---@field answer string @Best attempt across all trials
---@field best_score number @Score of the best-scoring attempt
---@field best_trial number @1-based index of the best trial
---@field passed boolean @Whether the final trial passed the threshold
---@field reflections string[] @Accumulated episodic memory (one per failed trial except the last)
---@field total_llm_calls number @Total alc.llm invocations across trials
---@field total_trials number @Number of trials executed
---@field trials { attempt: string, feedback: string, passed: boolean, reflection?: string, score: number, trial: number }[] @Ordered trial records with score, feedback, and optional reflection

---@class AlcPkgInput_review_and_investigate
---@field code string @Source code or diff to review (required)
---@field context? string @Free-text design context used in Phase 1/1.5/2/4
---@field deep_threshold? number @Confidence threshold below which the diagnose phase escalates to triad (default 0.6)
---@field max_fixes? number @Max fix candidates per theme (default 3)
---@field policy? { priorities?: string[], severity_weights?: table<string, number> } @Review policy (default: correctness > non_breaking > safety > testability > maintainability)

---@class AlcPkgResult_review_and_investigate
---@field summary { by_category?: table<string, number>, context_filtered?: boolean, deep_analyzed?: number, false_positives_removed?: number, policy_applied?: string, total_themes: number } @Run summary; field presence varies by early-return path (see summary_shape)
---@field themes { best_practice?: string, category?: string, current_state?: string, deep_analysis?: { verdict?: string, winner?: string }, diagnosis_confidence?: number, diagnosis_escalated?: boolean, expert_consultations?: { focus: string, question: string, response: string, role: string }[], fix_anti_patterns?: { error_analysis: string, wrong_reasoning: string }[], fixes?: { approach?: string, avoids?: string, id?: string, impact?: string, risk?: string, summary?: string }[], gap?: string, id?: string, locations?: string[], name: string, principle_violated?: string, ranking?: { best: { approach?: string, avoids?: string, id?: string, impact?: string, risk?: string, summary?: string }, matches: { a: string, b: string, reason: string, winner: string }[] }, references?: string[], related_locations?: string[], root_cause?: string, search_pattern?: string, span?: number[], surface_symptom?: string, total_occurrences?: number, verification?: string }[] @Surviving themes with accumulated per-phase fields; empty on any early-return path

---@class AlcPkgInput_robust_qa
---@field gen_tokens? number @Shared generation token budget (default: 600)
---@field max_conditions? number @Phase 2 (negation): max destruction conditions (default: 4)
---@field max_constraints? number @Phase 1 (p_tts): max constraints (default: 5)
---@field max_repairs? number @Phase 1 (p_tts): max repair attempts (default: 1)
---@field max_revisions? number @Phase 3 (critic): max revision rounds (default: 1)
---@field plan_tokens? number @Phase 1 (p_tts): planning token budget (default: 400)
---@field rubric? any @Phase 3 (critic): rubric dimension list (passed through)
---@field task string @The task/question to solve
---@field threshold? number @Phase 3 (critic): min acceptable per-dimension score (default: 7)

---@class AlcPkgResult_robust_qa
---@field adversarial_survived boolean @Phase 2 survived flag (convenience)
---@field answer string @Final answer after all 3 phases
---@field constraints_passed boolean @Phase 1 all_passed flag (convenience)
---@field critic_avg_score number @Phase 3 avg score (convenience)
---@field critic_scores table @Phase 3 per-dimension score map
---@field phase1_answer string @Answer at end of Phase 1 (p_tts)
---@field phase2_answer string @Answer at end of Phase 2 (negation)
---@field phase3_answer string @Answer at end of Phase 3 (critic) — matches `answer`
---@field phases any[] @Sequential phase records (phase1 p_tts / phase2 negation / phase3 critic) — each carries per-phase fields keyed by name

---@class AlcPkgInput_router_capability
---@field max_results? number @Number of top matches to return in alternatives (default 3)
---@field registry? { capabilities: string[], cost: number, description: string, name: string }[] @Agent registry; defaults to DEFAULT_REGISTRY
---@field task string @Task description (required)

---@class AlcPkgResult_router_capability
---@field alternatives { capabilities: string[], cost: number, description: string, name: string, score: number }[] @Top N candidates sorted by score desc, cost asc
---@field confidence number @Top agent's Jaccard score (0 if no match)
---@field method string @Scoring method identifier ('jaccard')
---@field reasoning string @LLM-extracted reasoning, or failure note
---@field requirements string[] @Capability tags extracted from task
---@field selected string @Best-match agent name, or 'unknown' if registry empty

---@class AlcPkgInput_router_daao
---@field candidates? any @Candidate strategies — string[] or {name=string}[] mix accepted
---@field profiles? table<string, { confidence?: number, context_mode: string, depth: number, fallback_confidence?: number, max_retries: number, recommended_strategies: string[], skip_phases: string[] }> @Custom difficulty→profile mapping; defaults to DEFAULT_PROFILES
---@field task string @Task description (required)

---@class AlcPkgResult_router_daao
---@field alternatives string[] @profile.recommended_strategies
---@field confidence number @Profile-derived confidence (0-1)
---@field difficulty string @Classified difficulty: 'simple' | 'medium' | 'complex' (or default 'medium' on parse failure)
---@field profile { confidence?: number, context_mode: string, depth: number, fallback_confidence?: number, max_retries: number, recommended_strategies: string[], skip_phases: string[] } @Full profile record for the selected difficulty
---@field reasoning string @LLM reasoning or parse-failure note
---@field selected string @Selected strategy name

---@class AlcPkgInput_router_semantic
---@field rules? { description: string, keywords: string[], name: string }[] @Routing rules; defaults to DEFAULT_RULES
---@field task string @Task description (required)
---@field threshold? number @Minimum keyword score to skip LLM (default 0.3)

---@class AlcPkgResult_router_semantic
---@field alternatives { description: string, matched_keywords: string[], name: string, raw_matches: number, score: number }[] @All rules scored by keyword, sorted by score desc
---@field confidence number @Score in [0, 1] — keyword score or LLM-reported
---@field method "keyword"|"llm_fallback"|"keyword_forced" @Which dispatch path produced the verdict
---@field reasoning string @Keyword match list, LLM reasoning, or failure note
---@field selected string @Best-match rule name

---@class AlcPkgInput_rstar
---@field gen_tokens? number @Max tokens per reasoning path (default: 400)
---@field task string @The problem to solve
---@field verify_tokens? number @Max tokens per cross-verification (default: 300)

---@class AlcPkgResult_rstar
---@field agreement "full"|"partial"|"none" @Agreement level between path_a and path_b
---@field answer string @Final answer (from agreement or resolution)
---@field path_a { conclusion: string, reasoning: string } @Path A (first-principles approach)
---@field path_b { conclusion: string, reasoning: string } @Path B (multi-angle approach)
---@field resolution_needed boolean @Whether a resolution LLM call was issued
---@field verification { a_agrees_b: boolean, a_checks_b: string, b_agrees_a: boolean, b_checks_a: string } @Cross-verification outputs

---@class AlcPkgInput_s2a
---@field context? string @Full (potentially noisy) context to denoise; empty/absent => task itself is reformulated
---@field gen_tokens? number @Max tokens per LLM call (default: 500)
---@field task string @The question or task to answer

---@class AlcPkgResult_s2a
---@field answer string @Final answer produced from the denoised context
---@field denoised_context string @LLM-denoised context (or reformulated task when no context given)
---@field denoised_context_length number @Length in chars of the denoised_context
---@field original_context_length number @Length in chars of the original context (or task when no context given)

---@class AlcPkgInput_sc
---@field gen_tokens? number @Max tokens per reasoning path (default: 400). Truncating reasoning lowers per-agent accuracy p, which directly weakens Condorcet guarantees for downstream consumers
---@field n? number @Number of independent reasoning paths to sample (default: 5)
---@field task string @Problem to solve (required)

---@alias AlcPkgResult_sc AlcResultVoted

---@class AlcPkgInput_schelling_abm
---@field density? number @Occupancy fraction (default 0.8)
---@field grid_size? number @Square-grid side length (default 20)
---@field runs? number @Monte Carlo runs (default 100)
---@field steps? number @Max simulation steps (default 100)
---@field task? string @Task description (free text)
---@field threshold? number @Tolerance threshold (min same-type neighbor fraction, default 0.375)
---@field type_ratio? number @Fraction of type-A agents (default 0.5)

---@class AlcPkgResult_schelling_abm
---@field params { density: number, grid_size: number, steps: number, threshold: number, type_ratio: number }
---@field sensitivity { base_value: number, delta: number, factor: number, high_value: number, low_value: number, param: string, score_at_high: number, score_at_low: number }[]
---@field simulation { converged_ci: { lower: number, upper: number }, converged_count: number, converged_rate: number, final_segregation_mean: number, final_segregation_median: number, final_segregation_p25: number, final_segregation_p75: number, final_segregation_std: number, high_segregation_ci: { lower: number, upper: number }, high_segregation_count: number, high_segregation_rate: number, runs: number, segregation_increase_mean: number, segregation_increase_median: number, segregation_increase_p25: number, segregation_increase_p75: number, segregation_increase_std: number, steps_to_converge_mean: number, steps_to_converge_median: number, steps_to_converge_p25: number, steps_to_converge_p75: number, steps_to_converge_std: number, unhappy_fraction_mean: number, unhappy_fraction_median: number, unhappy_fraction_p25: number, unhappy_fraction_p75: number, unhappy_fraction_std: number }

---@class AlcPkgInput_setwise_rank
---@field candidates string[] @Candidate texts to rank (>= 2)
---@field gen_tokens? number @Max tokens per pick response (default: 20)
---@field set_size? number @Tournament group size (default: 4)
---@field task string @Ranking criterion
---@field top_k? number @How many to keep (default: N = full ranked list)

---@class AlcPkgResult_setwise_rank
---@field best string @Text of the #1 candidate
---@field best_index number @Original 1-based index of the #1 candidate
---@field killed { index: number, rank: number, text: string }[] @Unranked tail (candidates not extracted into top_k)
---@field n_candidates number @Total number of input candidates
---@field ranked { index: number, rank: number, text: string }[] @Full ranked list: top_k winners followed by unranked tail
---@field set_size number @Tournament group size actually used
---@field top_k { index: number, rank: number, text: string }[] @Winners (the top-k portion of ranked)
---@field total_llm_calls number @Count of pick_best LLM calls performed

---@class AlcPkgInput_sketch
---@field max_tokens? number @Max tokens for reasoning (default: 200)
---@field paradigm? string @Force paradigm name (conceptual_chaining / chunked_symbolism / expert_lexicons); nil => auto-route
---@field routing_threshold? number @Keyword confidence threshold for LLM fallback (default: 0.4)
---@field task string @The problem to solve

---@class AlcPkgResult_sketch
---@field answer string @Extracted final answer string
---@field paradigm string @Paradigm used in execution after routing
---@field reasoning string @Extracted <sketch>...</sketch> body (or full LLM text if parsing failed)
---@field routing { confidence: number, method: string } @Routing diagnostic: method ∈ {manual, keyword, llm}, confidence 0-1

---@alias AlcPkgResult_slm_mux AlcResultSlmMuxed

---@class AlcPkgInput_smc_sample
---@field alpha? number @Tempering strength (default: 4.0)
---@field auto_card? boolean @Emit a Card on completion (default: false)
---@field card_pkg? string @Card pkg.name override (default: 'smc_sample_<task_hash>')
---@field ess_threshold? number @ESS trigger ratio (default: 0.5)
---@field gen_tokens? number @Max tokens per LLM call (default: 600)
---@field mh_filter_fn? any @Caller override for paper §3.4 Line 17 selective-MH predicate. Signature: (idx, reward, was_duplicated, τ_R) → boolean. Default: duplicated AND reward < τ_R. Use `function() return true end` for the legacy apply-MH-to-all variant (higher LLM cost).
---@field mh_reward_threshold? number @τ_R cutoff for the default selective-MH predicate (paper §3.4 Line 17). Default: 0.5.
---@field n_iterations? number @K SMC iterations (default: 4)
---@field n_particles? number @N particles (default: 16, paper §4.1)
---@field post_mh_reweight? boolean @Opt into the legacy exp(α·Δr) post-MH reweight (NOT paper-faithful — reward-gain bias). Default: false. Kept only for pre-0.2.0 run reproduction.
---@field rejuv_steps? number @S MH rejuvenation steps (default: 2)
---@field reward_fn any @Caller-injected fn(answer, task) → number ∈ [0, +∞). unit-test / LLM judge / scoring_rule. Runtime type-checked.
---@field scenario_name? string @Explicit scenario name for the emitted Card
---@field task string @Problem statement fed to the base LLM + reward_fn

---@alias AlcPkgResult_smc_sample AlcResultSmcSampled

---@class AlcPkgInput_sot
---@field max_sections? number @Maximum outline sections (default: 6)
---@field section_tokens? number @Max tokens per section fill (default: 400)
---@field skeleton_tokens? number @Max tokens for skeleton generation (default: 300)
---@field task string @The task requiring long-form output

---@class AlcPkgResult_sot
---@field output string @Final assembled long-form output (## headings + filled sections)
---@field section_count number @Count of sections parsed and filled
---@field sections string[] @Per-section LLM fills in the same order as skeleton
---@field skeleton string[] @Parsed section titles from skeleton (fallback: single-element = original task)

---@class AlcPkgInput_step_back
---@field abstraction_levels? number @Number of abstraction rounds (default: 1)
---@field domain_hint? string @Optional domain hint to guide abstraction
---@field task string @The problem to solve

---@class AlcPkgResult_step_back
---@field abstractions { level: number, principle: string, question: string }[] @Ordered step-back Q/A per abstraction level
---@field answer string @Final answer (post-verification / post-revision)
---@field revised boolean @Whether a revision pass was triggered
---@field verification string @Verifier output
---@field verified boolean @Whether verification returned VERIFIED

---@class AlcPkgInput_step_verify
---@field gen_tokens? number @Max tokens for generation (default: 500)
---@field max_repair_rounds? number @Max re-derivation rounds (default: 2)
---@field task string @The problem to solve
---@field verify_tokens? number @Max tokens per step verification (default: 200)

---@class AlcPkgResult_step_verify
---@field answer string @Final synthesized answer from verified reasoning
---@field rounds { error_at?: number, round: number, steps: { correct: boolean, explanation: string, step: string }[], verified_count: number }[] @Per-round verification trace
---@field total_llm_calls number @Total LLM calls (generation + verification + synthesis)
---@field total_rounds number @Number of rounds actually executed (= #rounds)
---@field total_verified number @Count of verified steps (= #verified_steps)
---@field verified_steps string[] @Ordered list of verified-correct reasoning steps

---@class AlcPkgInput_sugarscape_abm
---@field grid_size? number @Square-grid side length (default 25)
---@field initial_wealth_range? number[] @[min, max] initial wealth (default {5, 25})
---@field max_sugar? number @Peak sugar capacity per cell (default 4)
---@field metabolism_range? number[] @[min, max] metabolism (default {1, 4})
---@field n_agents? number @Initial population (default 100)
---@field regrow_rate? number @Sugar regrowth per step (default 1)
---@field runs? number @Monte Carlo runs (default 100)
---@field steps? number @Simulation steps (default 100)
---@field task? string @Task description (free text)
---@field vision_range? number[] @[min, max] vision (default {1, 6})

---@class AlcPkgResult_sugarscape_abm
---@field params { grid_size: number, initial_wealth_range: number[], max_sugar: number, metabolism_range: number[], n_agents: number, regrow_rate: number, steps: number, vision_range: number[] }
---@field sensitivity { base_value: number, delta: number, factor: number, high_value: number, low_value: number, param: string, score_at_high: number, score_at_low: number }[]
---@field simulation { gini_mean: number, gini_median: number, gini_p25: number, gini_p75: number, gini_std: number, high_inequality_ci: { lower: number, upper: number }, high_inequality_count: number, high_inequality_rate: number, mean_wealth_mean: number, mean_wealth_median: number, mean_wealth_p25: number, mean_wealth_p75: number, mean_wealth_std: number, population_collapsed_ci: { lower: number, upper: number }, population_collapsed_count: number, population_collapsed_rate: number, runs: number, survival_rate_mean: number, survival_rate_median: number, survival_rate_p25: number, survival_rate_p75: number, survival_rate_std: number }

---@class AlcPkgInput_topo_route
---@field analysis_tokens? number @Max tokens for the analysis LLM call (default 600)
---@field available_packages? any @Override default package registry (reserved; not currently consumed)
---@field task string @Task description to route (required)

---@class AlcPkgResult_topo_route
---@field analysis string @Raw LLM analysis text (kept for downstream consumers)
---@field confidence number @Parsed CONFIDENCE in [0, 1] (default 0.5 on parse failure)
---@field description string @Short topology description
---@field dimensions table<string, string> @Task analysis axes; keys are complexity/decomposability/verification_need/adversarial_value/cost_sensitivity, values are LOW|MEDIUM|HIGH
---@field governance_addons string[] @Filtered governance packages from LLM suggestion (subset of {lineage, dissent, anti_cascade})
---@field mitigations string @Suggested mitigation packages for those risks
---@field packages { package: string, role: string }[] @Flattened package list covering all roles of the selected topology plus governance addons
---@field risks string @Topology-specific risk summary
---@field topology string @Recommended topology name: linear | star | dag | debate | ensemble | escalation

---@class AlcPkgInput_tot
---@field beam_width? number @Branches kept after pruning (default: 2)
---@field breadth? number @Thoughts generated per beam node (default: 3)
---@field depth? number @Maximum tree depth (default: 3)
---@field task string @The problem to solve

---@class AlcPkgResult_tot
---@field best_path string[] @Best beam path: ordered reasoning steps
---@field best_score number @Score of the best beam (1-10)
---@field conclusion string @Synthesized final answer from the best-scored beam path
---@field explored_paths { path: string[], rank: number, score: number }[] @All surviving beams, rank-ordered by score
---@field tree_stats { beam_width: number, breadth: number, depth: number } @Configuration echo for traceability

---@class AlcPkgInput_triad
---@field gen_tokens? number @Max tokens per argument (default: 400)
---@field judge_tokens? number @Max tokens for final verdict (default: 500)
---@field rounds? number @Number of debate rounds after opening (default: 3)
---@field task string @The question or claim to debate

---@class AlcPkgResult_triad
---@field total_rounds number @Number of rebuttal rounds (excludes opening)
---@field transcript { opponent: string, proponent: string, round: number }[] @Full debate transcript including opening
---@field verdict string @Full verdict text from the judge
---@field winner string @Parsed winner token ("proponent"|"opponent"|"draw"|"unknown")

---@class AlcPkgInput_ucb
---@field n? number @Number of hypotheses to generate (default: 3)
---@field rounds? number @Number of evaluate+refine rounds (default: 2)
---@field task string @The problem to solve

---@class AlcPkgResult_ucb
---@field best string @Highest avg-scored hypothesis after rounds
---@field ranking { avg_score: number, hypothesis: string, pulls: number, rank: number }[] @Full ranking sorted by average score descending

---@class AlcPkgInput_usc
---@field gen_tokens? number @Max tokens per candidate (default: 400)
---@field n? number @Number of candidate responses to sample (default: 5)
---@field select_tokens? number @Max tokens for selection response (default: 500)
---@field task string @The problem/question to solve

---@class AlcPkgResult_usc
---@field candidates string[] @All sampled candidate responses
---@field n_sampled number @Number of candidates sampled
---@field selected_index? number @1-based index parsed from the selection (nil if unparseable)
---@field selection string @LLM's consistency-selection response (analysis + chosen answer content)

---@class AlcPkgInput_verify_first
---@field candidate? string @Pre-supplied candidate answer (default: nil => auto-generate)
---@field gen_tokens? number @Max tokens for candidate generation (default: 600)
---@field iterations? number @Number of Iter-VF rounds (default: 1)
---@field task string @The task/question to solve
---@field trivial? boolean @Use trivial candidate '1' instead of CoT (default: false)
---@field verify_tokens? number @Max tokens per verification round (default: 800)

---@class AlcPkgResult_verify_first
---@field answer string @Final verification text of the last round
---@field candidate_source string @Origin of initial candidate: provided / trivial / cot
---@field extracted_answer string @Answer extracted from the final verification
---@field history { extracted_answer: string, input_candidate: string, round: number, verification: string }[] @Per-round Markovian trace: candidate in, verification out, extracted answer
---@field iterations number @Number of Iter-VF rounds actually executed
