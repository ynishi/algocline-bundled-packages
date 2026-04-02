# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
