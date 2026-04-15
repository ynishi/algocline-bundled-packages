# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **2 new `recipe` category packages** composing foundations into end-to-end strategies:
  - **[recipe_safe_panel](recipe_safe_panel/)**: safety-first panel QA. Composes `condorcet` (panel sizing + Anti-Jury), `sc` (self-consistency), `inverse_u` (optional scaling check), `calibrate` (confidence). Auto `M.verified.alc_eval_runs` recorded math_basic pass_rate = 1.0 (7/7) at 8 LLM calls/case under `max_n=3`.
  - **[recipe_ranking_funnel](recipe_ranking_funnel/)**: listwise → pairwise ranking funnel. Composes `listwise_rank` (coarse screening) and `pairwise_rank` (precise finalization). Verified N=8 population ranking: 7 calls vs naive all-pairs 56 (87% savings), top-1 correct.
- **`M.verified` convention**: recipe packages expose `theoretical_basis` + measured `e2e_runs` / `alc_eval_runs` only — no unverified claims. Populated empirically via agent-block E2E harness.
- **scripts/e2e/ agent-block harness** (`common.lua` + per-recipe drivers): runs full ReAct loop against real `alc.llm` / `alc_eval`, persists graded results to `workspace/e2e-results/<timestamp>/<name>.json`.
  - `recipe_safe_panel.lua`: single-case smoke (Capital of Japan)
  - `recipe_ranking_funnel.lua`: single-case smoke (Country population 2026)
  - `recipe_safe_panel_eval.lua`: multi-case `alc_eval` sweep (math_basic, 7 cases) with recipe-level budget caps (`max_n=3`, `scaling_check=false`)
- **justfile**: `just e2e <name>` / `just e2e-all` with `allow-agent` group for task-mcp exposure.
- **tests/test_recipe_ranking_funnel.lua**, **tests/test_recipe_safe_panel.lua**: structural + M.verified validation tests.
- **`calibrate.assess(ctx)`**: 1-LLM-call primitive exposing calibrate's Phase 1 (answer + self-assessed confidence) without threshold/escalation logic. `M.run` now delegates Phase 1 to `assess`, and `recipe_safe_panel` consumes it directly (replacing the earlier `calibrate.run({threshold=0, fallback="retry"})` workaround).

### Changed

- **sc** `ctx.result`: bridge API gap for recipe consumption. Added `answer_norm`, `votes` (normalized), `vote_counts`, `n_sampled`, `total_llm_calls` alongside existing `consensus` / `answer` / `paths`. `total_llm_calls` is now counted during execution (previously hardcoded `2n+1`). Representative `answer` is trimmed + trailing-punctuation-stripped so downstream prompts see "Tokyo" rather than "Tokyo." or "tokyo" depending on sampling order. Normalization = lowercase + whitespace collapse + trailing punctuation strip.
- **calibrate** `ctx.result`: added `total_llm_calls` on every return path — direct = 1, retry = 2, panel = 1 + roles + 1, ensemble = 1 + sc.total_llm_calls. Downstream consumers (e.g. recipe_safe_panel) can now read the accurate count instead of hardcoding.
- **recipe_safe_panel**: reads `cal_result.result.total_llm_calls` when present, with the previous `escalated ? 2 : 1` heuristic as backward-compat fallback.
- **recipe_safe_panel** Stage 3: renamed `inverse_u` → `vote_prefix_stability`. The stage uses a single-run vote prefix as an accuracy proxy, which is NOT the independent-panel inverse-U scenario from Chen et al. NeurIPS 2024; log messages, stage names, and caveats now state this explicitly.
- **recipe_ranking_funnel**: added `ctx.judge_gen_tokens` (default 20) — pairwise judgement calls in Stage 3 (and the N<6 bypass) no longer silently override `ctx.gen_tokens`; short-verdict token cap is now an explicit knob.
- **recipe_ranking_funnel**: `funnel_shape` is now always a 3-element array and documented with explicit semantics (`[S1-input, S2-input, S3-input]`). The N<6 bypass path emits `{N, N, N}` with the same convention so downstream consumers don't need to special-case array length. Bypass path also now reports `naive_baseline_calls` / `naive_baseline_kind` / `savings_percent` fields (previously missing).
- **recipe_ranking_funnel** `ctx.result`: added `naive_baseline_kind = "pairwise_rank_allpair_bidirectional"` so the `savings_percent` denominator is self-documenting; clarified in comments that this over-reports vs single-pass or listwise-only baselines.
- **recipe_ranking_funnel**: documented the `min_window = ceil(N/2)` rule (listwise stride = ceil(window/2), so window ≥ N/2 is needed to keep top items reachable in the final head window) and that Stage 2 intentionally discards Stage 1's ordinal ranking except as a tie-break.
- **recipe_safe_panel**: `1.5x` correlation-adjustment multiplier is now documented as a recipe-level HEURISTIC (not a theorem) corresponding to intra-panel correlation ρ ≈ 0.2–0.3 under the effective-sample-size formula `N_eff = N / (1 + (N-1)·ρ)`.
- **recipe_safe_panel**: odd-enforcement downgrade (when rounding the recommended panel size up would exceed `max_n`, the recipe rounds DOWN by 2 instead) now emits an explicit warn log identifying the downgrade and the `max_n` value needed to avoid it. Previously silent.
- **recipe_safe_panel** caveats: replaced "inverse_u needs ≥ 5 data points" (incorrect) with the accurate statement that Stage 3 requires panel `n ≥ 7` in practice, because the prefix series is sampled only at odd k ≥ 3 (so n=3 gives 1 point, n=5 gives 2 points — both below inverse_u's 3-point threshold).
- **hub_index.json**: regenerated to 105 packages (adds `recipe_ranking_funnel`, `recipe_safe_panel`).
- **README**: package count 103 → 105, added `### Recipes` section under package catalog.

### Fixed

- **recipe_safe_panel**: guarded `condorcet.optimal_n()` returning nil (unreachable target or p == 0.5 edge). Previously the next line (`ceil(recommended_n * 1.5)`) would crash with a nil-arithmetic error. Falls back to `max_n` with a warning log instead.
- **recipe_safe_panel**: validates `ctx.max_n` at entry — errors clearly on `max_n < 3` or non-numeric, eliminating the corner case where the odd-enforcement floor of 3 could silently exceed the configured cap.

## [0.12.0] - 2026-04-13

### Added

- **12 new packages** for multi-agent/Swarm foundations:
  - **[shapley](shapley/)**: Shapley Value — axiomatically unique agent contribution attribution via exact O(2^n) computation or Monte Carlo permutation sampling (Shapley 1953, Ghorbani-Zou AISTATS 2019)
  - **[mwu](mwu/)**: Multiplicative Weights Update — adversarial online agent weight learning with O(√(T ln N)) regret bound, doubling trick, log-space stability (Littlestone-Warmuth 1994, Freund-Schapire 1997)
  - **[kemeny](kemeny/)**: Kemeny-Young rank aggregation — axiomatically unique consensus ranking minimizing total Kendall tau distance. Exact for m ≤ 8, Borda fallback (Kemeny 1959, Young-Levenglick 1978)
  - **[scoring_rule](scoring_rule/)**: Proper Scoring Rules — Brier, logarithmic, spherical scores + ECE calibration measurement for agent prediction quality audit (Brier 1950, Gneiting-Raftery JASA 2007)
  - **[bft](bft/)**: Byzantine Fault Tolerance bounds — quorum thresholds and impossibility validation (Lamport-Shostak-Pease 1982)
  - **[pbft](pbft/)**: Practical BFT — 3-phase LLM consensus with BFT quorum guarantees (Castro-Liskov OSDI 1999)
  - **[condorcet](condorcet/)**: Condorcet Jury Theorem — majority-vote probability, Anti-Jury detection, optimal panel sizing (Condorcet 1785)
  - **[ensemble_div](ensemble_div/)**: Ambiguity Decomposition — Krogh-Vedelsby identity E = Ē − Ā for ensemble diversity measurement (NeurIPS 1995, Hong-Page PNAS 2004)
  - **[aco](aco/)**: Ant Colony Optimization — discrete path search with pheromone update and convergence detection (Dorigo 1996, Gutjahr 2000)
  - **[inverse_u](inverse_u/)**: Inverse-U scaling detection — non-monotonic accuracy-vs-N safety gate (Chen et al. NeurIPS 2024)
  - **[cost_pareto](cost_pareto/)**: Multi-objective Pareto dominance — frontier extraction and strategy selection (Kapoor et al. 2024)
  - **[eval_guard](eval_guard/)**: Evaluation safety gates — self-critique (N2), baseline enforcement (N3), contamination shield (N4)
- **tests/test_foundations.lua**: 79 tests for bft, condorcet, ensemble_div, inverse_u, cost_pareto, eval_guard
- **tests/test_foundations_phase2.lua**: 19 tests for pbft, aco
- **tests/test_shapley.lua**: 38 tests including axiom verification
- **tests/test_mwu.lua**: 24 tests including regret bound verification
- **tests/test_kemeny.lua**: 35 tests including Condorcet consistency axiom
- **tests/test_scoring_rule.lua**: 37 tests including properness verification

### Changed

- **Category recategorization**: removed "foundation" catch-all category. All 12 packages now use purpose-aligned categories: governance (bft), aggregation (condorcet, ensemble_div, kemeny, pbft), validation (inverse_u, eval_guard), selection (cost_pareto, mwu), attribution (shapley), evaluation (scoring_rule), exploration (aco)
- **Documentation enrichment**: all 12 packages' Lua doc headers and meta.description updated with detailed theory references, multi-agent/Swarm usage context, and cross-package composability notes
- **README**: updated package count (91 → 103), added all 12 packages to appropriate sections, added new Aggregation and Attribution sections

## [0.11.2] - 2026-04-12

### Added

- **hub_index.json**: Machine-readable package index for Hub search. Generated by `alc_hub_reindex --source_dir`. Contains 91 packages with name, version, description, and category metadata.

## [0.11.1] - 2026-04-12

### Changed

- **optimize** v0.2.0 → v0.3.0: auto_card support — emits a Card on optimization completion with two-tier content policy (Tier 1 body: config + best_params + best_score + top_k ranking; Tier 2 samples.jsonl: per-round history). Opt-in via `ctx.auto_card = true`
- **tests/test_optimize.lua**: added 4 auto_card tests (basic emit, card_pkg override, opt-out default, samples sidecar)

## [0.11.0] - 2026-04-08

### Added

- **6 new selection / ranking / partial-data pruning packages**:
  - **[ab_select](ab_select/)**: Adaptive Branching Selection — multi-fidelity Thompson sampling over a fixed candidate pool; cheap→expensive evaluator cascade allocates expensive evaluations only to promising candidates (Inoue et al., "AB-MCTS", NeurIPS 2025 Spotlight)
  - **[listwise_rank](listwise_rank/)**: Zero-shot listwise reranking — single-LLM-call permutation generation with sliding window for large N. Resolves the calibration problem of pointwise scoring (Sun et al., "RankGPT", EMNLP 2023; Pradeep et al., "RankZephyr", 2023)
  - **[pairwise_rank](pairwise_rank/)**: Pairwise Ranking Prompting (PRP) — bidirectional pairwise comparisons (A,B and B,A to cancel position bias) with Copeland-style aggregation. Modes: allpair O(N²) or sorting O(N log N) (Qin et al., NAACL 2024 Findings)
  - **[setwise_rank](setwise_rank/)**: Setwise tournament reranking — LLM picks the single best from small sets (size k); winners advance through tournament rounds. Mid-cost/mid-accuracy sweet spot between listwise and pairwise (Zhuang et al., SIGIR 2024)
  - **[cs_pruner](cs_pruner/)**: Confidence-sequence partial-data pruner — anytime-valid per-candidate kill via Empirical-Bernstein CS over a multi-dimensional rubric. Four variants: `polynomial_stitched`, `hoeffding`, `betting` (W-S&R 2024 predictable plug-in), and `kl` (Kaufmann-Cappé KL-LUCB). Optional layer-2 Successive Halving with gap guard for small-N×D regimes where the CS floor cannot fire (Howard et al., Ann. Stat. 2021; Waudby-Smith & Ramdas, JRSS-B 2024; Kaufmann & Cappé, JMLR 2013)
  - **[f_race](f_race/)**: Friedman race partial-data pruner — block-wise rank assignment over rubric dimensions; eliminates candidates whose mean rank is significantly worse than the best by a Friedman χ² + Conover post-hoc test. Designed for small N (≤10) × D (≤30) where EB-CS cannot fire (Friedman, JASA 1937; Birattari et al., GECCO 2002; Conover, 1999)
- **tests/test_cs_pruner.lua**: 24 tests covering all four CS variants, layer-2 halving, gap guard, eval_order modes, and validation
- **tests/test_f_race.lua**: Friedman race coverage
- **tests/test_ranking_packages.lua**: shared tests for ab_select / listwise_rank / pairwise_rank / setwise_rank

### Changed

- **cs_pruner**: dropped the reserved `independent_bonferroni` aggregation mode from docstring and error message. Numerical analysis (N=6, D=20, δ=0.05, t=1/dim → `radius_floor ≈ 16.78`) showed the construction is structurally incompatible with the round-robin evaluation schedule, so the v0.2 placeholder has been removed rather than carried forward. `ctx.aggregation` now documents `scalarize` as the only supported value.
- **README**: updated package count (85 → 91), added ranking/pruning packages to the Selection table and their LLM-call profiles to the table, added Testing section documenting the mlua-probe-mcp runner workflow

## [0.10.0] - 2026-04-04

### Added

- **New "Simulation" category** — Agent-Based Model framework + 7 model packages:
  - **[abm](abm/)**: Core ABM framework — Agent/Model/Scheduler (Frame layer) + Monte Carlo runner + sensitivity sweep + statistics (Analysis layer). Two-layer architecture with combinator-pattern schedulers
  - **[hybrid_abm](hybrid_abm/)**: LLM-as-Parameterizer ABM — LLM extracts simulation parameters (Phase A), Pure Lua ABM runs Monte Carlo (Phase B+C), sensitivity sweep (Phase D). Based on FCLAgent (arXiv:2510.12189)
  - **[epidemic_abm](epidemic_abm/)**: SIR Agent-Based epidemic model — stochastic individual-level disease transmission with tunable R0, herd immunity thresholds (Kermack & McKendrick 1927, Epstein 2006)
  - **[opinion_abm](opinion_abm/)**: Hegselmann-Krause Bounded Confidence opinion dynamics — emergent consensus, polarization, or fragmentation determined by ε threshold (Hegselmann & Krause, JASSS 2002)
  - **[evogame_abm](evogame_abm/)**: Evolutionary Game Theory ABM — iterated Prisoner's Dilemma / Hawk-Dove with fitness-proportionate selection and mutation. 6 classic strategies including Tit-for-Tat, Pavlov, Grudger (Axelrod 1984, Nowak & May 1992)
  - **[schelling_abm](schelling_abm/)**: Schelling Segregation model — agents on a 2D toroidal grid relocate when local same-type fraction falls below tolerance threshold (Schelling 1971, 1978)
  - **[sugarscape_abm](sugarscape_abm/)**: Sugarscape model — agents forage on a sugar landscape with heterogeneous metabolism/vision, emergent wealth inequality and Gini coefficient tracking (Epstein & Axtell 1996)
  - **[boids_abm](boids_abm/)**: Boids flocking model — separation, alignment, cohesion produce emergent flocking behavior. Tunable weights for Hybrid LLM parameter optimization (Reynolds, SIGGRAPH 1987)
- **tests/test_abm.lua**: 43 tests covering ABM framework + hybrid_abm
- **tests/test_abm_models.lua**: 20 tests covering epidemic, opinion, evogame, schelling models
- **tests/test_abm_new_models.lua**: 10 tests covering sugarscape and boids models

### Fixed

- **evogame_abm**: replaced IIFE with plain for-loop for strategy count (readability)
- **abm/frame/model**: changed 3-pass stepping (all before → all step → all after) to per-agent stepping (before → step → after per agent) — standard ABM activation semantics
- **schelling_abm**: added guard for already-vacated cells during agent movement phase
- **opinion_abm**: H-K bounded confidence comparison changed from `<` to `<=` (paper-compliant: |x_i - x_j| ≤ ε)
- **abm/sweep**: tier escalation threshold changed from `> 0` to `> 0.001` (avoids floating-point false negatives)
- **epidemic_abm, evogame_abm, opinion_abm, schelling_abm**: removed unnecessary `ctx.task` required check — task is not used in pure simulation models (available via comment for hybrid_abm integration)

### Changed

- **README**: updated package count (77 → 85), added Simulation section with 8 packages

## [0.9.0] - 2026-04-03

### Added

- **6 new packages** based on 2024-2026 test-time compute scaling and selection research:
  - **[usc](usc/)**: Universal Self-Consistency — extends SC to free-form tasks by having LLM select the most consistent response instead of majority voting. Works on open-ended QA, summarization, code generation where SC fails (Chen et al., ICML 2024, Google DeepMind)
  - **[step_verify](step_verify/)**: Step-Level Verification (PRM-style) — scores each intermediate reasoning step for logical correctness, identifies the first point of failure, and re-derives from the last correct step. Targets logical validity unlike cove (fact-checking) or factscore (claim verification) (PRM Survey 2025, ThinkPRM 2025, DiVeRSe)
  - **[compute_alloc](compute_alloc/)**: Compute-Optimal Test-Time Scaling Allocation — dynamically selects reasoning paradigm (single/parallel/sequential/hybrid) and budget based on problem difficulty. Key insight: optimal method changes with difficulty (Snell et al., ICLR 2025)
  - **[gumbel_search](gumbel_search/)**: Budget-optimal tree search — Sequential Halving for provably optimal budget allocation + Gumbel Top-k for unbiased candidate sampling. Complementary to ab_mcts: excels under fixed budget constraints (Karnin et al., ICML 2013; "Revisiting Tree Search for LLMs" 2026)
  - **[mbr_select](mbr_select/)**: Minimum Bayes Risk selection — computes pairwise similarity for all candidate pairs and selects the one with highest expected agreement. Bayes-optimal under decision theory, no bracket luck unlike tournament-based rank (MBR, NAACL 2025; Eikema & Aziz 2020)
  - **[reflexion](reflexion/)**: Episodic Memory Self-Improvement — multiple independent attempts where failures are reflected on and stored as lessons. Each new attempt references accumulated reflections. HumanEval 67%→91% (Shinn et al., NeurIPS 2023)
- **tests/test_tier1_2.lua**: 45 tests covering all 6 new packages (meta, validation, LLM call counts, index extraction, similarity matrix, episodic memory propagation)

### Changed

- **README**: updated package count (71 → 77), added new packages to Reasoning/Selection/Validation/Orchestration tables and LLM call counts table
- **README**: added 26 previously unlisted packages (v0.1.0–v0.4.0 era) to category tables and LLM Call Counts — all 77 packages now listed. New sections: Intent Understanding, Planning, Combinators
- **sc**: clarified description — "Best for tasks with canonical answer formats (numbers, options)" to distinguish from usc
- **reflect**: clarified description — "within a single attempt" to distinguish from reflexion

## [0.8.0] - 2026-04-03

### Added

- **New "Exploration" category** for population-based and adversarial search strategies:
  - **[qdaif](qdaif/)**: Quality-Diversity through AI Feedback — MAP-Elites archive with LLM-driven mutation, evaluation, and feature classification (Bradley et al., ICLR 2024)
  - **[falsify](falsify/)**: Sequential Falsification — Popper-style hypothesis exploration via active refutation, pruning, and successor derivation (Sourati et al., 2025; Yamada et al. "AI Scientist v2", 2025)
  - **[prompt_breed](prompt_breed/)**: Self-Referential Prompt Evolution — evolves task prompts via genetic operators with meta-mutation (mutation operators themselves evolve) (Fernando et al. "PromptBreeder", 2023)
  - **[coevolve](coevolve/)**: Challenger-Solver Co-evolution — adversarial self-play where Challenger generates problems at Solver's ability boundary (Singh et al., 2025; Faldor et al. "OMNI-EPIC", ICLR 2025)
- **mcts**: LATS-style Reflection mechanism — failure diagnosis injection into expansion prompts
- **optimize/search**: `breed` strategy — PromptBreeder-style meta-evolution for parameter optimization
- **LuaLS LuaCats type annotations** for all 71 packages:
  - `.luarc.json`: workspace.library configuration for `~/.algocline/types` + local `types/`
  - `types/alc_pkg.d.lua`: AlcCtx, AlcMeta type definitions — module interface contract
  - `*/init.lua`: `---@type AlcMeta`, `---@param ctx AlcCtx`, `---@return AlcCtx` annotations
- **tests/test_exploration.lua**: 38 tests covering all 4 new exploration packages + 2 extensions

### Fixed

- **types/alc_pkg.d.lua**: removed unused `AlcModule` class (LuaLS inject-field warning)

### Changed

- **README**: updated package count (67 → 71), added Exploration section, updated LLM call counts table

## [0.7.0] - 2026-03-30

### Added

- **New "Governance" category** for multi-agent pipeline robustness, based on "From Spark to Fire" (Xie et al., AAMAS 2026) and MAST (Cemri et al., 2025):
  - **[lineage](lineage/)**: Pipeline-spanning claim lineage tracking — extracts atomic claims per step, traces inter-step dependencies, detects conflicts and ungrounded claims. Defense rate improvement 0.32 → 0.89
  - **[dissent](dissent/)**: Consensus inertia prevention — forces adversarial challenge before finalizing multi-agent agreement. Composable with moa, panel, sc
  - **[anti_cascade](anti_cascade/)**: Pipeline error cascade detection — independently re-derives from original inputs at each step and compares with pipeline output to detect error amplification
- **1 new routing package**:
  - **[topo_route](topo_route/)**: Topology-aware meta-router — analyzes task characteristics and recommends optimal topology (linear/star/DAG/mesh/debate/ensemble) with concrete package mappings. Same agents, different topology → up to 40% reliability variation
- **tests/test_governance.lua**: 33 tests covering all 4 new packages (meta, validation, LLM call counts, parse logic, threshold gating)

### Changed

- **README**: updated package count (37 → 67), added Governance section and topo_route to Routing table, updated LLM call counts table

## [0.6.0] - 2026-03-29

### Added

- **6 new packages** based on 2024-2026 research:
  - **[got](got/)**: Graph of Thoughts — DAG-structured reasoning with aggregation (many-to-one merge), refinement loops, and multi-path synthesis (Besta et al., AAAI 2024)
  - **[model_first](model_first/)**: Model-First Reasoning — constructs explicit problem model (entities, states, actions, constraints) before solving (Rana & Kumar, 2025)
  - **[sketch](sketch/)**: Sketch-of-Thought — cognitive-inspired efficient reasoning via 3 paradigms with adaptive routing, 60-84% token reduction (Aytes et al., EMNLP 2025)
  - **[coa](coa/)**: Chain-of-Abstraction — reasons with abstract placeholders, then grounds via parallel knowledge resolution (Gao et al., Meta/EPFL, COLING 2025)
  - **[ab_mcts](ab_mcts/)**: Adaptive Branching MCTS — Thompson Sampling with GEN node mechanism for dynamic wider/deeper decisions (Inoue et al., NeurIPS 2025 Spotlight)
  - **[counterfactual_verify](counterfactual_verify/)**: Counterfactual faithfulness verification — tests causal dependence between premises and conclusions (Hase et al., 2026)

### Fixed

- **counterfactual_verify**: `parse_counterfactuals()` now correctly extracts all blocks including the last one (previously missed due to delimiter-based regex)

### Changed

- **README**: updated package count (31 → 37), added new packages to Reasoning and Validation tables and LLM call counts

## [0.5.0] - 2026-03-24

### Added

- **5 orchestration packages**:
  - **[orch_fixpipe](orch_fixpipe/)**: Deterministic fixed pipeline with gate/retry (Lobster/OpenClaw pattern)
  - **[orch_gatephase](orch_gatephase/)**: Phase orchestration with pre/post hooks and skip rules (Thin Agent/Fat Platform, Praetorian)
  - **[orch_adaptive](orch_adaptive/)**: Adaptive depth orchestration based on task difficulty (DAAO, arXiv:2509.11079)
  - **[orch_nver](orch_nver/)**: N-version programming with score/vote selection (Agentic SE Roadmap, arXiv:2509.06216)
  - **[orch_escalate](orch_escalate/)**: Cascade escalation from light to heavy strategies (Microsoft + DAAO cost optimization)
- **3 router packages**:
  - **[router_daao](router_daao/)**: Difficulty-aware routing with injectable confidence profiles (DAAO, arXiv:2509.11079)
  - **[router_semantic](router_semantic/)**: Keyword matching with LLM fallback, 0-1 LLM calls (Microsoft Multi-Agent Reference Architecture)
  - **[router_capability](router_capability/)**: Jaccard similarity agent registry matching (Dynamic Agent Registry pattern)
- **[optimize](optimize/)**: Modular parameter optimization orchestrator (v0.2.0)
  - 4-component architecture: search, eval, stop, orchestrator
  - **Search strategies**: UCB1 (Auer et al. 2002), random, OPRO (Yang et al. 2023), EA/GA (Guo et al. 2024), epsilon-greedy
  - **Evaluators**: evalframe integration, custom function, LLM-as-judge
  - **Stopping criteria**: variance convergence, patience (early stopping), threshold, improvement rate, composite
  - State persistence via `alc.state` for incremental optimization across sessions
  - `alc.tuning` integration for parameter merging
- **tests/**: test suites for all 9 new packages (39 tests for optimize, 8 suites for orch/router)

### Changed

- **README**: updated package count (22 → 31), added Orchestration, Routing sections and optimize to Extraction/Optimization table

## [0.4.0] - 2026-03-19

### Added

- **6 reasoning strategy packages**:
  - **[s2a](s2a/)**: System 2 Attention — strips irrelevant/biasing context before reasoning (Weston & Sukhbaatar, 2023)
  - **[plan_solve](plan_solve/)**: Plan-and-Solve — devises step-by-step plan then executes sequentially (Wang et al., 2023)
  - **[rstar](rstar/)**: Mutual reasoning verification — two independent paths cross-verify each other (Qi et al., 2024)
  - **[faithful](faithful/)**: Faithful CoT — translates reasoning into formal representation for verification (Lyu et al., 2023)
  - **[moa](moa/)**: Mixture of Agents — layered multi-agent aggregation with cross-pollination (Wang et al., 2024)
  - **[bot](bot/)**: Buffer of Thoughts — meta-reasoning with reusable structured thought templates (Yang et al., 2024)
- **tests/test_new_packages.lua**: test suite for the 6 new packages

### Changed

- **reflect**: added `ctx.initial_draft` parameter to skip initial LLM generation when caller provides a pre-generated draft
- **README**: updated package count (16 → 22), added new packages to tables and LLM call counts

## [0.3.0] - 2026-03-18

### Added

- **9 reasoning strategy packages**: bisect, blind_spot, cascade, claim_trace, critic, dmad, negation, p_tts, verify_first
- **robust_qa**: composite pipeline combining p_tts, negation, and critic
- **3 bundled eval scenarios** (`scenarios/` directory):
  - **math_basic**: arithmetic and number theory (7 cases, contains + exact_match)
  - **reasoning_basic**: logical reasoning and common knowledge (5 cases, contains)
  - **factual_basic**: factual knowledge with verifiable answers (5 cases, contains)

## [0.2.0] - 2026-03-15

### Added

- **10 reasoning strategy packages**: ucb, panel, cot, sc, reflect, calibrate, contrastive, meta_prompt, factscore, cove
- **deliberate**: structured decision-making combinator (decompose → branch reasoning → synthesize)
- **pre_mortem**: feasibility-gated proposal filtering (factscore → contrastive → calibrate → pairwise ranking)
- **4 intent understanding packages**:
  - **ambig**: AMBIG-SWE detect-clarify-integrate pipeline (ICLR 2026)
  - **prism**: cognitive-load-aware intent decomposition with topological sort (arXiv:2601.08653)
  - **intent_discovery**: exploratory intent formation via DiscoverLLM (arXiv:2602.03429)
  - **intent_belief**: Bayesian intent estimation with diagnostic questions (arXiv:2510.18476)

### Changed

- **review_and_investigate**: enhanced pipeline with span-based code slicing, migrated to alc.parse_score
- **cove, factscore, review_and_investigate**: added `grounded = true` to verification phases
- **README**: added alc-runner agent integration guide

## [0.1.0] - 2026-03-15

### Added

- Initial release
- Collection layout with `*/init.lua` convention
- **review_and_investigate**: multi-phase code review pipeline (detect → cluster → verify → diagnose → research → prescribe → report)
