# algocline-bundled-packages

Official bundled package collection for [algocline](https://github.com/ynishi/algocline). Lua modules that run on the `alc.*` runtime API.

Each package implements a research-backed reasoning strategy in a single `init.lua`, ready to use via `require("pkg_name")`.

## Installation

```bash
# Install all bundled packages (included in alc init)
alc init

# Install directly from this repository (Collection mode)
alc pkg_install github.com/ynishi/algocline-bundled-packages
```

When the repository root has no `init.lua`, `pkg_install` treats it as a Collection and installs each subdirectory containing `*/init.lua` as a separate package.

## Architecture

Every pkg plays **one of three architectural roles**. The role is determined by what the pkg *does*, not by which functional section it appears under in *Packages* below.

| Role | What it does | Calls `alc.llm`? | I/O contract |
|---|---|---|---|
| **Strategy** | Produces an answer by orchestrating the LLM | Yes | ctx-threading — `M.spec.entries.run.input` + `M.run(ctx) → ctx.result` |
| **Frame** | Hosts the execution of other pkgs / user code (state, scheduling, composition) | No | Sub-modules exposed as fields; no single `M.run` entry |
| **Computation** | Self-contained calculation (statistics, voting theory, aggregation math). Pure functions, no LLM | No | direct-args — `M.spec.entries.*.args` (positional) per entry |

The split is formalized in [`alc_shapes/spec_resolver.lua`](alc_shapes/spec_resolver.lua): within one entry, `input` (ctx-threading) and `args` (direct-args) are **mutually exclusive** — the resolver raises when both are set. `instrument` inspects `entry.args` to choose per-ctx wrapping vs per-argument wrapping.

### Roster

- **Frames** — [flow](flow/), [abm](abm/)
- **Computation** — [bft](bft/), [condorcet](condorcet/), [conformal_vote](conformal_vote/), [cost_pareto](cost_pareto/), [ensemble_div](ensemble_div/), [eval_guard](eval_guard/), [inverse_u](inverse_u/), [kemeny](kemeny/), [mwu](mwu/), [scoring_rule](scoring_rule/), [shapley](shapley/), [sprt](sprt/)
- **Schema engine** — [alc_shapes](alc_shapes/) (the type DSL and `spec_resolver` that power the contracts above)
- **Strategy** — everything else in the *Packages* section below

### Architecture axis vs Category axis

The *Packages* section below groups pkgs by **functional category** (Reasoning / Selection / Aggregation / …), which is **orthogonal** to architectural role. A Computation pkg may live under Selection (e.g. `kemeny`, `condorcet`), Aggregation (`ensemble_div`), Attribution (`shapley`), Governance (`bft`), or Validation / Analysis (`sprt`, `scoring_rule`, `eval_guard`, `inverse_u`) — but its contract stays direct-args regardless of the section it appears in.

**Rule of thumb for new pkgs**: if the pkg calls `alc.llm`, it is a Strategy and MUST use ctx-threading. If the pkg is a pure calculation with no LLM call, it is a Computation pkg and SHOULD use direct-args. Frames are rare and require explicit design review.

## Packages (111)

### Reasoning

| Package | Description | Based On |
|---------|-------------|----------|
| **[cot](cot/)** | Chain-of-Thought. Builds a step-by-step reasoning chain and synthesizes a final answer | Wei et al. (2022) |
| **[maieutic](maieutic/)** | Recursive explanation tree with logical consistency filtering. Generates supporting/opposing arguments recursively and eliminates contradictions | Jung et al. (2022) |
| **[reflect](reflect/)** | Iterative self-critique loop. Generate, critique, and revise within a single attempt until convergence. Polishes the current draft | Madaan et al., "Self-Refine" (2023) |
| **[reflexion](reflexion/)** | Episodic memory self-improvement. Multiple independent attempts where failures are reflected on and stored as lessons. Each new attempt references accumulated reflections. reflect polishes one draft; reflexion learns across attempts. HumanEval 67%→91% | Shinn et al. (NeurIPS 2023) |
| **[calibrate](calibrate/)** | Confidence-gated adaptive reasoning. Escalates to sc/panel/retry when confidence falls below threshold | CISC (ACL Findings 2025) |
| **[plan_solve](plan_solve/)** | Plan-and-Solve. Devises an explicit step-by-step plan, then executes each step sequentially. More structured than CoT, lighter than decompose | Wang et al. (2023) |
| **[faithful](faithful/)** | Faithful CoT. Translates reasoning into formal representation (code/logic) for verification, then answers grounded in verified output | Lyu et al. (2023), Gao et al. "PAL" (2023) |
| **[rstar](rstar/)** | Mutual reasoning verification. Two independent paths cross-verify each other. MCTS-level accuracy at ~1/3 the cost | Qi et al. (2024) |
| **[bot](bot/)** | Buffer of Thoughts. Identifies problem type, applies structured thought template, then verifies. Meta-reasoning with reusable patterns | Yang et al. (2024) |
| **[got](got/)** | Graph of Thoughts. DAG-structured reasoning with aggregation (many-to-one merge), refinement loops, and multi-path synthesis. Enables thought merging impossible in tree-based ToT | Besta et al. (AAAI 2024) |
| **[model_first](model_first/)** | Model-First Reasoning. Constructs explicit problem model (entities, state variables, actions, constraints) before solving. Catches constraint violations that plan_solve misses | Rana & Kumar (2025) |
| **[sketch](sketch/)** | Sketch-of-Thought. Cognitive-inspired efficient reasoning via 3 paradigms (Conceptual Chaining, Chunked Symbolism, Expert Lexicons) with adaptive routing. 60-84% token reduction vs CoT | Aytes et al. (EMNLP 2025) |
| **[coa](coa/)** | Chain-of-Abstraction. Reasons with abstract placeholders, then grounds via parallel knowledge resolution. Decouples reasoning structure from concrete facts | Gao et al. (Meta/EPFL, COLING 2025) |
| **[ab_mcts](ab_mcts/)** | Adaptive Branching MCTS. Thompson Sampling with dynamic wider/deeper decisions via GEN node mechanism. Consistently outperforms standard MCTS and repeated sampling | Inoue et al. (NeurIPS 2025 Spotlight) |
| **[gumbel_search](gumbel_search/)** | Budget-optimal tree search. Sequential Halving for provably optimal budget allocation + Gumbel Top-k for unbiased candidate sampling. Outperforms standard decoding with just 5-15 simulations. Complementary to ab_mcts: ab_mcts excels with open budgets, gumbel_search excels under fixed budget constraints | "Revisiting Tree Search for LLMs" (2026), Karnin et al. (ICML 2013) |
| **[analogical](analogical/)** | Analogical prompting. Self-generates relevant analogies, extracts shared patterns, then applies the abstracted principle to the original problem | Yasunaga et al. (2023) |
| **[contrastive](contrastive/)** | Contrastive CoT. Generates both correct and incorrect reasoning paths, learns from the contrast to strengthen the final answer | Chia et al. (2023) |
| **[cumulative](cumulative/)** | Cumulative Reasoning. Proposer/verifier/reporter loop that accumulates verified facts incrementally until conclusion is reached | Zhang et al. (2024) |
| **[diverse](diverse/)** | DiVERSe. Generates diverse reasoning paths with step-level verification and selects the best-verified path | Li et al. (2023) |
| **[dmad](dmad/)** | Dialectical reasoning. Thesis, antithesis, and synthesis for deeper analysis through structured opposition | Du et al. (2023) |
| **[least_to_most](least_to_most/)** | Least-to-Most prompting. Decomposes into ordered subproblems, solves simplest first, each solution feeds into the next | Zhou et al. (2022) |
| **[mcts](mcts/)** | Monte Carlo Tree Search. Selection, expansion, simulation, backpropagation for systematic reasoning exploration with LATS-style reflection | RAP (2023), LATS (ICML 2024) |
| **[meta_prompt](meta_prompt/)** | Meta-Prompting. Orchestrator identifies task type and dispatches to dynamically created specialist personas | Suzgun & Kalai (2024) |
| **[php](php/)** | Progressive-Hint Prompting. Iterative re-solving where prior answers serve as progressive hints for refinement | Zheng et al. (2023) |
| **[step_back](step_back/)** | Step-Back prompting. Abstracts the underlying principle first, then solves grounded in that principle | Zheng et al. (2023) |
| **[tot](tot/)** | Tree-of-Thought. Branching reasoning with evaluation and pruning. Explores multiple reasoning paths simultaneously | Yao et al. (2023) |
| **[verify_first](verify_first/)** | Verification-First prompting. Verifies a candidate answer before generating, reducing logical errors via reverse reasoning | arXiv:2511.21734 (2025) |

### Selection

| Package | Description | Based On |
|---------|-------------|----------|
| **[sc](sc/)** | Self-Consistency. Independently samples multiple reasoning paths and aggregates by majority vote. Best for tasks with canonical answer formats (numbers, options) | Wang et al. (2022) |
| **[usc](usc/)** | Universal Self-Consistency. Extends SC to free-form tasks by having LLM select the most consistent response instead of majority voting. Works on open-ended QA, summarization, code generation where SC's answer extraction fails. Mathematically, majority vote is a special case of USC | Chen et al. (ICML 2024), Google DeepMind |
| **[mbr_select](mbr_select/)** | Minimum Bayes Risk selection. Computes pairwise similarity for all candidate pairs and selects the one with highest expected agreement. Bayes-optimal under decision theory — no bracket luck or position bias unlike tournament-based rank. O(N²/2) but theoretically optimal | MBR (NAACL 2025), Eikema & Aziz (2020) |
| **[ucb](ucb/)** | UCB1 hypothesis exploration. Generates, scores, and refines hypotheses using UCB1 selection | — |
| **[rank](rank/)** | Best-of-N sampling with tournament selection. Pairwise comparison via LLM-as-Judge | Zheng et al. (2023) |
| **[triad](triad/)** | Three-role adversarial debate. Proponent, opponent, and judge engage in multi-round argumentation | Du et al. (2023) |
| **[moa](moa/)** | Mixture of Agents. Layered multi-agent aggregation — each layer's agents see all previous layer outputs for cross-pollination and refinement | Wang et al. (2024) |
| **[ab_select](ab_select/)** | Adaptive Branching Selection. Multi-fidelity Thompson sampling over a fixed candidate pool — cheap→expensive evaluator cascade allocates expensive evaluations only to promising candidates. Unique multi-fidelity axis vs other selection packages | Inoue et al. "AB-MCTS" (NeurIPS 2025 Spotlight) |
| **[listwise_rank](listwise_rank/)** | Zero-shot listwise reranking. Single-LLM-call permutation generation with sliding window for large N. Resolves the calibration problem of pointwise scoring (LLMs cannot output well-calibrated absolute scores). SOTA on TREC-DL/BEIR | Sun et al. "RankGPT" (EMNLP 2023), Pradeep et al. "RankZephyr" (2023) |
| **[pairwise_rank](pairwise_rank/)** | Pairwise Ranking Prompting (PRP). Bidirectional pairwise comparisons (queries both A,B and B,A to cancel position bias) with Copeland-style aggregation. Highest-accuracy LLM reranker — Flan-UL2 20B with PRP matches GPT-4 on TREC-DL. Modes: allpair (O(N²)) or sorting (O(N log N)) | Qin et al. (NAACL 2024 Findings) |
| **[setwise_rank](setwise_rank/)** | Setwise tournament reranking. LLM picks the single best from small sets (size k); winners advance through tournament rounds. Mid-cost/mid-accuracy sweet spot between listwise and pairwise; matches RankGPT on TREC-DL with comparable tokens | Zhuang et al. (SIGIR 2024) |
| **[cs_pruner](cs_pruner/)** | Confidence-sequence partial-data pruner. Anytime-valid per-candidate kill via Empirical-Bernstein CS over a multi-dimensional rubric. Four variants: polynomial-stitched, hoeffding, predictable plug-in betting (W-S&R 2024), and KL-LUCB (Kaufmann-Cappé 2013). Optional layer-2 Successive Halving with gap guard for small-N×D regimes where the CS floor cannot fire | Howard, Ramdas, McAuliffe, Sekhon (Ann. Stat. 2021), Waudby-Smith & Ramdas (JRSS-B 2024), Kaufmann & Cappé (JMLR 2013), Karnin-Koren-Somekh (ICML 2013) |
| **[f_race](f_race/)** | Friedman race partial-data pruner. Block-wise rank assignment over rubric dimensions; eliminates candidates whose mean rank is significantly worse than the best by a Friedman χ² + Conover post-hoc test. Designed for small N (≤10) × D (≤30) where Empirical-Bernstein CS cannot fire — uses ranks instead of raw scores so it discriminates gaps as small as 0.3 at B=20 blocks | Friedman (JASA 1937), Birattari et al. (GECCO 2002), Conover (1999) |
| **[mwu](mwu/)** | Multiplicative Weights Update. Adversarial online agent weight learning with O(√(T ln N)) regret bound. Learns optimal agent mixture weights over time without stochastic assumptions. Doubling trick for unknown T, log-space computation for numerical stability | Littlestone & Warmuth (1994), Freund & Schapire (1997) |
| **[cost_pareto](cost_pareto/)** | Multi-objective Pareto dominance. Frontier extraction, dominance testing, and layered ranking for agent strategy selection on accuracy/cost/diversity trade-offs. HumanEval warming $2.45/93.2% dominates LATS $134.50/88.0% | Kapoor et al. "AI Agents That Matter" (2024) |

### Aggregation

| Package | Description | Based On |
|---------|-------------|----------|
| **[condorcet](condorcet/)** | Condorcet Jury Theorem. Majority-vote probability, Anti-Jury detection, optimal panel sizing, and independence verification for multi-agent voting systems. Quantifies when adding agents helps vs hurts | Condorcet (1785), Dietrich & List (2008) |
| **[ensemble_div](ensemble_div/)** | Ambiguity Decomposition. Krogh-Vedelsby identity E = Ē − Ā — the ensemble always beats the weighted average of individuals when there is any disagreement. Quantifies how much agent diversity reduces ensemble error | Krogh & Vedelsby (NeurIPS 1995), Hong & Page (PNAS 2004) |
| **[kemeny](kemeny/)** | Kemeny-Young rank aggregation. Axiomatically unique consensus ranking that minimizes total Kendall tau distance. Exact for m ≤ 8, Borda fallback for larger candidate sets. Condorcet-consistent | Kemeny (1959), Young & Levenglick (1978) |
| **[pbft](pbft/)** | Practical Byzantine Fault Tolerance. 3-phase LLM consensus (propose → prepare → commit) with BFT quorum guarantees. Tolerates f Byzantine agents given n ≥ 3f+1 | Castro & Liskov (OSDI 1999) |

### Attribution

| Package | Description | Based On |
|---------|-------------|----------|
| **[shapley](shapley/)** | Shapley Value. Axiomatically unique agent contribution attribution via exact O(2^n) computation or Monte Carlo permutation sampling. Identifies essential, redundant, and harmful agents in multi-agent ensembles | Shapley (1953), Ghorbani & Zou "Data Shapley" (AISTATS 2019) |

### Preprocessing

| Package | Description | Based On |
|---------|-------------|----------|
| **[s2a](s2a/)** | System 2 Attention. Strips irrelevant/biasing context before reasoning. Composable as a pre-filter for any other strategy | Weston & Sukhbaatar (2023, Meta) |

### Generation

| Package | Description | Based On |
|---------|-------------|----------|
| **[sot](sot/)** | Skeleton-of-Thought. Generates an outline first, then writes each section in parallel | Ning et al. (2023) |
| **[decompose](decompose/)** | Task decomposition + parallel execution + synthesis. Breaks complex tasks into subtasks | TDAG (2025), HiPlan (2025) |

### Extraction / Optimization

| Package | Description | Based On |
|---------|-------------|----------|
| **[distill](distill/)** | MapReduce summarization/extraction. Chunks large text, extracts in parallel, and synthesizes | LLM x MapReduce (2024) |
| **[cod](cod/)** | Chain-of-Density iterative compression. Rewrites summaries to progressively increase information density | Adams et al. (2023) |
| **[optimize](optimize/)** | Modular parameter optimization orchestrator. Pluggable search (UCB1, OPRO, EA, greedy), evaluators (evalframe, custom, LLM judge), and stopping criteria. Auto Card emission on completion (two-tier). Persists state across sessions | DSPy (2023), OPRO (2023), EvoPrompt (2024) |

### Validation / Analysis

| Package | Description | Based On |
|---------|-------------|----------|
| **[cove](cove/)** | Chain-of-Verification. Draft, generate verification questions, answer independently, then revise to reduce hallucination | Dhuliawala et al. (2023) |
| **[factscore](factscore/)** | Atomic claim decomposition + individual fact verification. Decomposes text into minimal factual claims and scores each | Min et al. (2023) |
| **[review](review_and_investigate/)** | Multi-pass code review. Switchable between chunk mode and concerns mode | — |
| **[counterfactual_verify](counterfactual_verify/)** | Counterfactual faithfulness verification. Tests whether reasoning causally depends on inputs by simulating condition changes. Detects unfaithful CoT | Hase et al. (2026) |
| **[step_verify](step_verify/)** | Step-level reasoning verification (PRM-style). Scores each intermediate reasoning step for logical correctness, identifies the first point of failure, and re-derives from the last correct step. Unlike cove (fact-checking) or factscore (claim verification), targets logical validity of reasoning chains | PRM Survey (2025), ThinkPRM (2025), DiVeRSe |
| **[negation](negation/)** | Adversarial self-test. Generates destruction conditions (edge cases, counterexamples) and verifies the answer survives them. External challenge unlike reflect's internal critique | Huang et al. (2023) |
| **[bisect](bisect/)** | Binary search for reasoning errors. Locates the first incorrect step in O(log n), then regenerates from that point. Surgical error correction | arXiv:2410.08146 (2024) |
| **[blind_spot](blind_spot/)** | Self-Correction Blind Spot bypass. Re-presents the model's own output as an external source to trigger genuine error correction, overcoming self-correction failure modes | arXiv:2507.02778 (2025) |
| **[claim_trace](claim_trace/)** | Span-level evidence attribution. Traces each claim to supporting source spans for transparent provenance. Composable post-filter for any generation | Bohnet et al. (2022), Gao et al. (2023) |
| **[critic](critic/)** | Rubric-based structured evaluation. Per-dimension scoring with targeted revision of weak areas. More systematic than reflect's free-form critique | Zheng et al. (2023) |
| **[inverse_u](inverse_u/)** | Inverse-U scaling detection. Detects non-monotonic accuracy-vs-N curves where adding more agents degrades performance. Safety gate for multi-agent scaling — catches the peak and recommends early stopping | Chen et al. (NeurIPS 2024), Theorem 2 |
| **[eval_guard](eval_guard/)** | Evaluation safety gates. Self-critique guard (N2, Huang ICLR 2024), baseline enforcement (N3, Wang-Kapoor 2024), contamination shield (N4, Zhu EMNLP 2024). Pre-flight checks before trusting any multi-agent evaluation result | Huang (ICLR 2024), Wang (ACL 2024), Zhu (EMNLP 2024) |
| **[scoring_rule](scoring_rule/)** | Proper Scoring Rules. Brier, logarithmic, spherical scores + Expected Calibration Error (ECE) for evaluating agent prediction quality. Audits whether agent confidence matches actual accuracy. Strictly proper: honest reporting maximizes expected score | Brier (1950), Gneiting & Raftery (JASA 2007), Naeini (AAAI 2015) |
| **[sprt](sprt/)** | Wald's Sequential Probability Ratio Test primitive. Streaming Bernoulli test with declared α/β error rates; Wald–Wolfowitz optimality (minimal expected N among tests with same error bounds). Substrate for adaptive-stop recipes that need to decide accept_h0 / accept_h1 / continue per observation | Wald (1945), Wald & Wolfowitz (1948) |
| **[conformal_vote](conformal_vote/)** | Split conformal prediction gate for multi-agent deliberation. Linear opinion pool + finite-sample quantile (⌈(n+1)(1-α)⌉/n) + three-way decision (commit/escalate/anomaly) per Proposition 3. Pr[Y ∈ C(X)] ≥ 1-α (Theorem 2). Calibration pins aggregation weights so online runs preserve exchangeability | Wang et al. (arXiv:2604.07667, 2026) |

### Orchestration

| Package | Description | Based On |
|---------|-------------|----------|
| **[orch_fixpipe](orch_fixpipe/)** | Deterministic fixed pipeline. Phases execute in strict order with gate/retry | Lobster (OpenClaw) |
| **[orch_gatephase](orch_gatephase/)** | Gate-phase orchestration with pre/post hooks. Task-type-aware skip rules | Thin Agent / Fat Platform (Praetorian) |
| **[orch_adaptive](orch_adaptive/)** | Adaptive depth orchestration. Adjusts phase count, retry budget, and context mode by task difficulty | DAAO (arXiv:2509.11079) |
| **[orch_nver](orch_nver/)** | N-version programming. Execute N parallel variants, evaluate each, select best | Agentic SE Roadmap (arXiv:2509.06216) |
| **[orch_escalate](orch_escalate/)** | Cascade escalation from light to heavy strategies. Minimizes cost for easy tasks | Microsoft + DAAO |
| **[compute_alloc](compute_alloc/)** | Compute-optimal test-time scaling allocation. Dynamically selects reasoning paradigm (single/parallel/sequential/hybrid) and budget based on problem difficulty. Key insight: optimal method changes with difficulty — easy=direct, medium=SC, hard=reflect+verify. "Small model + optimal TTS > 14× larger model" | Snell et al. (ICLR 2025), TTS Survey (2025) |

### Routing

| Package | Description | Based On |
|---------|-------------|----------|
| **[router_daao](router_daao/)** | Difficulty-aware routing with injectable confidence profiles | DAAO (arXiv:2509.11079) |
| **[router_semantic](router_semantic/)** | Keyword matching with LLM fallback. 0-1 LLM calls | Microsoft Multi-Agent Reference Architecture |
| **[router_capability](router_capability/)** | Capability-based registry router. Jaccard similarity agent matching | Dynamic Agent Registry |
| **[topo_route](topo_route/)** | Topology-aware meta-router. Analyzes task characteristics and recommends optimal topology (linear/star/DAG/mesh/debate) with package mappings. Same agents, different topology → up to 40% reliability variation | "From Spark to Fire" (Xie et al., AAMAS 2026), MAST (Cemri et al., 2025) |
| **[cascade](cascade/)** | Multi-level difficulty routing. Escalates from fast to deep only when confidence is low. Cost-efficient for mixed-difficulty workloads | FrugalGPT (Chen et al., 2023), Lu et al. (2023) |

### Governance

| Package | Description | Based On |
|---------|-------------|----------|
| **[lineage](lineage/)** | Pipeline-spanning claim lineage tracking. Extracts atomic claims per step, traces inter-step dependencies, detects conflicts and ungrounded claims. Defense rate 0.32 → 0.89 | "From Spark to Fire" (Xie et al., AAMAS 2026) — lineage graph governance layer |
| **[dissent](dissent/)** | Consensus inertia prevention. Forces adversarial challenge before finalizing multi-agent agreement. Composable with moa, panel, sc | "From Spark to Fire" (Xie et al., AAMAS 2026) — Consensus Inertia countermeasure; MAST F11 |
| **[anti_cascade](anti_cascade/)** | Pipeline error cascade detection. Independently re-derives from original inputs at each step and compares with pipeline output to detect error amplification | "From Spark to Fire" (Xie et al., AAMAS 2026) — Cascade Amplification countermeasure; MAST F3/F9 |
| **[bft](bft/)** | Byzantine Fault Tolerance bounds. Quorum thresholds and impossibility validation for multi-agent governance. Computes minimum panel sizes and fault tolerance limits (Theorem 1: n ≥ 3f+1 for oral messages, n ≥ f+2 for signed messages) | Lamport, Shostak & Pease (1982) |

### Exploration

| Package | Description | Based On |
|---------|-------------|----------|
| **[qdaif](qdaif/)** | Quality-Diversity through AI Feedback. MAP-Elites archive with LLM-driven mutation, evaluation, and feature classification. Produces diverse, high-quality solution populations | Bradley et al. (ICLR 2024), Mouret & Clune (2015) |
| **[falsify](falsify/)** | Sequential Falsification. Popper-style hypothesis exploration via active refutation, pruning, and successor derivation. Expands search space through refutation-driven insight | Sourati et al. (2025), Yamada et al. "AI Scientist v2" (2025) |
| **[prompt_breed](prompt_breed/)** | Self-Referential Prompt Evolution. Evolves task prompts via genetic operators with meta-mutation — the mutation operators themselves evolve. Double evolutionary loop | Fernando et al. "PromptBreeder" (2023), Guo et al. "EvoPrompt" (ICLR 2024) |
| **[coevolve](coevolve/)** | Challenger-Solver Co-evolution. Adversarial self-play where Challenger generates problems at Solver's ability boundary and Solver evolves to solve them. Automatic search space expansion | Singh et al. (2025), Faldor et al. "OMNI-EPIC" (ICLR 2025) |
| **[aco](aco/)** | Ant Colony Optimization. Discrete path search with pheromone update, evaporation, and convergence detection. Pure computation engine + LLM-integrated mode for search space exploration | Dorigo (1996), Gutjahr (2000) |

### Intent Understanding

| Package | Description | Based On |
|---------|-------------|----------|
| **[ambig](ambig/)** | Underspecification detection. Detect-clarify-integrate pipeline for ambiguous inputs — identifies ambiguity, generates clarifying questions, integrates answers | AMBIG-SWE (ICLR 2026) |
| **[prism](prism/)** | Cognitive-load-aware intent decomposition. Logical dependency ordering for minimal-friction clarification via topological sort | arXiv:2601.08653 (2026) |
| **[intent_discovery](intent_discovery/)** | Exploratory intent formation. Discovers user goals through structured option presentation and iterative narrowing when intent is unclear | DiscoverLLM (arXiv:2602.03429, 2026) |
| **[intent_belief](intent_belief/)** | Bayesian intent estimation. Hypothesis generation with iterative belief updates via diagnostic questions | arXiv:2510.18476 (2025) |

### Planning

| Package | Description | Based On |
|---------|-------------|----------|
| **[p_tts](p_tts/)** | Plan-Test-Then-Solve. Generates constraints/test cases before solving, then verifies the solution against the specification | Zhang et al. (2023) |

### Simulation

| Package | Description | Based On |
|---------|-------------|----------|
| **[abm](abm/)** | Agent-Based Model framework — Agent/Model/Scheduler + Monte Carlo runner + sensitivity sweep | — |
| **[hybrid_abm](hybrid_abm/)** | LLM-as-Parameterizer ABM — LLM extracts simulation parameters, Pure Lua ABM runs Monte Carlo + sensitivity sweep | FCLAgent (arXiv:2510.12189), JASSS position paper (arXiv:2507.19364) |
| **[epidemic_abm](epidemic_abm/)** | SIR Agent-Based epidemic model — stochastic individual-level disease transmission with tunable R0 | Kermack & McKendrick (1927), Epstein (2006) |
| **[opinion_abm](opinion_abm/)** | Hegselmann-Krause Bounded Confidence opinion dynamics — emergent consensus, polarization, or fragmentation | Hegselmann & Krause (JASSS 2002) |
| **[evogame_abm](evogame_abm/)** | Evolutionary Game Theory ABM — iterated Prisoner's Dilemma / Hawk-Dove with selection and mutation | Axelrod (1984), Nowak & May (Nature 1992) |
| **[schelling_abm](schelling_abm/)** | Schelling Segregation model — mild preferences produce strong emergent segregation on a 2D grid | Schelling (1971, 1978) |
| **[sugarscape_abm](sugarscape_abm/)** | Sugarscape model — agents forage on a sugar landscape, emergent wealth inequality and Pareto-like distributions | Epstein & Axtell (1996) |
| **[boids_abm](boids_abm/)** | Boids flocking model — separation, alignment, cohesion produce emergent flocking. Tunable weights for Hybrid LLM parameter optimization | Reynolds (SIGGRAPH 1987) |

### Combinators

| Package | Description | Based On |
|---------|-------------|----------|
| **[deliberate](deliberate/)** | Structured deliberation. Abstracts principles, consults expert perspectives, stages debate, then produces ranked decision | — |
| **[pre_mortem](pre_mortem/)** | Feasibility-gated proposal filtering. Prerequisite verification (factscore → contrastive → calibrate) before pairwise ranking | — |
| **[robust_qa](robust_qa/)** | Three-phase QA pipeline. Constraint-first solving (p_tts), adversarial stress-test (negation), rubric evaluation (critic) | — |

### Synthesis

| Package | Description | Based On |
|---------|-------------|----------|
| **[panel](panel/)** | Multi-role deliberation. Multiple roles discuss and a moderator synthesizes | — |
| **[dci](dci/)** | Deliberative Collective Intelligence (DCI-CF). 4 roles (Framer/Explorer/Challenger/Integrator) × 14 typed epistemic acts (6 classes) × 8-stage convergence algorithm. Forces a decision_packet (5 components) with first-class minority_report preservation even on fallback | Prakash (arXiv:2603.11781, 2026) |

### Substrate

Primitives that other packages compose on top of. Substrate modules do NOT provide `M.run` — they expose low-level building blocks (state persistence, request tokens, LLM wrappers) and leave the driver loop to the caller (Functional Core / Imperative Shell).

| Package | Description | Based On |
|---------|-------------|----------|
| **[flow](flow/)** | Flow Frame. FlowState (plain table persisted via `alc.state`) + ReqToken (random nonce echoed by downstream results) substrate for composing bundled algo pkg (ab_mcts / cascade / coevolve / ...) with one persistent checkpoint and slot-level verification. Light Frame: driver loop stays in user code. v1 contract (flow/doc/contract.md) for pkg opting in to strict echo verification | AMQP `correlation_id` RPC idiom (RabbitMQ) |

### Recipes

End-to-end strategies that compose multiple packages into a single `run(ctx)` entry point, with recorded `M.verified` empirical results (measured runs only — no hand-wavy claims).

| Package | Description | Composes |
|---------|-------------|----------|
| **[recipe_safe_panel](recipe_safe_panel/)** | Safety-first panel QA. Condorcet-sized panel → self-consistency → optional inverse-U scaling check → calibrated confidence. Anti-Jury / needs_investigation safety gates. math_basic pass_rate 1.0 (7/7) at 8 LLM calls/case (max_n=3) | condorcet, sc, inverse_u, calibrate |
| **[recipe_ranking_funnel](recipe_ranking_funnel/)** | Listwise → pairwise ranking funnel. 8→3→3 funnel shape on population ranking yielded 7 LLM calls vs naive all-pairs 56 (87% savings), top-1 correct | listwise_rank, pairwise_rank |
| **[recipe_deep_panel](recipe_deep_panel/)** | Deep-reasoning diverse panel with resume. Condorcet gate → N × ab_mcts fan-out via flow (checkpoint-per-branch) → ensemble_div diversity → Condorcet expected accuracy → calibrate meta-confidence. Heavy-compute counterpart of recipe_safe_panel (≈ N × (2·budget+1) + 1 LLM calls; 52 at N=3, budget=8) | flow, condorcet, ab_mcts, ensemble_div, calibrate |
| **[recipe_quick_vote](recipe_quick_vote/)** | Adaptive-stop majority vote. Leader commits from sample 1, subsequent samples vote agree/disagree, Wald SPRT decides accept_h1 (confirmed) / accept_h0 (rejected) / continue until max_n (truncated). Fills the Quick slot between recipe_safe_panel (~8 fixed calls) and recipe_deep_panel (~52 heavy calls) with declared α/β error budget | sprt |

#### Current limitations — recipe test coverage

Recipes currently have **three** tiers of verification. Not every recipe has
every tier; see the matrix below.

| Tier | Runner | Purpose | Location |
|---|---|---|---|
| Unit tests (mocked `_G.alc`) | `lua-debugger` MCP (`mlua-probe-mcp`) | Stage transitions, index mapping, API contracts, cost accounting | `tests/test_recipe_*.lua` |
| E2E (single-case, live LLM) | `agent-block` / `just e2e <name>` | ReAct-loop + MCP + real LLM on one prompt, with custom graders | `scripts/e2e/<recipe>.lua` |
| Scenario eval (multi-case pass_rate) | `alc_eval` via `agent-block` | pass@1 over an installed scenario (e.g. `math_basic`) | `scripts/e2e/<recipe>_eval.lua` |

Coverage at time of writing:

| Recipe | Unit | E2E (single-case) | Scenario eval (multi-case) |
|---|---|---|---|
| recipe_safe_panel | ✓ (22 tests) | ✓ (`scripts/e2e/recipe_safe_panel.lua`) | ✓ (`recipe_safe_panel_eval.lua`, math_basic 7/7) |
| recipe_ranking_funnel | ✓ (19 tests) | ✓ (`scripts/e2e/recipe_ranking_funnel.lua`) | ✗ — **not yet authored** |
| recipe_deep_panel | ✓ (41 tests, mocked `ab_mcts` / `calibrate` + real `flow` / `condorcet` / `ensemble_div`) | ✗ — **not yet authored** | ✗ — **not yet authored** |
| recipe_quick_vote | ✓ (21 tests, mocked `_G.alc.llm`) | ✓ (`scripts/e2e/recipe_quick_vote.lua`, 17+25=42 → confirmed @ n=8, 16 calls, log_lr=3.29) | ✓ (`scripts/e2e/recipe_quick_vote_eval.lua` against math_basic, 7/7 pass_rate=1.0, 112 LLM calls, all confirmed @ n=8; card_id integration needs follow-up) |

Gaps:

- **recipe_ranking_funnel has no scenario-eval harness** (no
  `recipe_ranking_funnel_eval.lua`). The existing scenarios under
  `~/.algocline/scenarios/` (`factual_basic`, `reasoning_basic`, `math_basic`,
  …) are QA-style (single answer), not ranking-style (population → ordering),
  so a dedicated ranking scenario is a prerequisite.
- `M.verified.scenarios` in `recipe_ranking_funnel/init.lua` therefore reports
  the single-case E2E only; no multi-case pass_rate is available for this
  recipe.
- Scenario-eval runs are non-deterministic and billable; treat each verified
  number as one sample, not a tight confidence interval.

## Result Shape Convention

Packages declare their I/O contract under `M.spec.entries.<entry_name>.{input, result}`, validated at runtime by **[alc_shapes](alc_shapes/)**. Producers self-decorate with `S.instrument(M, "run")` at the module tail; every caller inherits the dev-mode check without writing any assert of their own.

```lua
-- Producer (bundled pkg)
M.spec = {
    entries = {
        run = { input = T.shape({ task = T.string }, { open = true }),
                result = T.ref("voted") },
    },
}
M.run = require("alc_shapes").instrument(M, "run")

-- Consumer
local sc_result = require("sc").run({ task = "...", n = 7 })
-- ctx.result is already shape-checked in dev mode — no manual assert needed.
```

Manual `S.assert(value, "voted", hint)` is still available for ad-hoc
validation of external data. Dev-mode checks activate under
`ALC_SHAPE_CHECK=1`.

11 shapes are currently registered: `voted`, `paneled`, `assessed`, `calibrated`, `tournament`, `listwise_ranked`, `pairwise_ranked`, `funnel_ranked`, `safe_paneled`, `quick_voted`, `deep_paneled`. The DSL supports primitives, arrays, enums, maps (`T.map_of`), discriminated unions (`T.discriminated`), and named references (`T.ref`).

See [alc_shapes/README.md](alc_shapes/README.md) for the full API reference (combinators, validator, `M.spec.entries`, instrument, spec_resolver, reflection, codegen).

## Usage

```lua
local reflect = require("reflect")

local result = reflect.run({
    task = "Explain the CAP theorem and its practical implications",
    max_rounds = 3,
})

print(result.result.output)
```

### Common parameters

Each package receives a `ctx` table and stores its output in `ctx.result`.

```lua
local ctx = pkg.run({
    task = "...",         -- Required by most packages
    gen_tokens = 400,     -- Max tokens for LLM generation
})
```

### Composing packages

Packages are composable. Use sc as calibrate's fallback, apply reflect to decompose's subtasks, etc.

```lua
local calibrate = require("calibrate")
local result = calibrate.run({
    task = "...",
    threshold = 0.8,
    fallback = "ensemble",  -- Uses the sc package
})
```

## Runtime API

Each package uses the following algocline runtime APIs:

| API | Description |
|-----|-------------|
| `alc.llm(prompt, opts)` | LLM call |
| `alc.map(list, fn)` | Parallel map execution |
| `alc.chunk(text, opts)` | Text chunking |
| `alc.log(level, msg)` | Logging |
| `alc.stats.record(key, val)` | Metrics recording |

## Writing your own package

A directory with an `init.lua` at its root constitutes one package.

```lua
-- init.lua
local S = require("alc_shapes")
local T = S.T

local M = {}

M.meta = {
    name = "my-strategy",
    version = "0.1.0",
    description = "My custom strategy",
    category = "reasoning",
}

-- Optional: declare the I/O contract for dev-mode shape checking.
-- `input` / `result` accept either a string (registry lookup) or
-- an inline schema. Packages without M.spec still run — they are
-- treated as opaque by spec_resolver (no type checking).
M.spec = {
    entries = {
        run = {
            input  = T.shape({ task = T.string }, { open = true }),
            result = "my_shape",  -- register in alc_shapes/init.lua first
        },
    },
}

function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    -- Implement using alc.llm(), alc.map(), etc.
    ctx.result = { answer = "..." }
    return ctx
end

-- Malli-style self-decoration: the wrapper asserts ret.result against
-- M.spec.entries.run.result when ALC_SHAPE_CHECK=1. No-op when dev is off.
M.run = S.instrument(M, "run")

return M
```

### Direct-args mode (Computation packages)

Pkgs that perform pure calculation — no `alc.llm` call, no `ctx` threading — declare **positional `args`** instead of `input` at each entry. This library-style shape (`M.new(cfg) → state`, `M.observe(state, x)`, `M.decide(state) → verdict`, …) fits streaming algorithms ([sprt](sprt/)), voting aggregators ([kemeny](kemeny/), [condorcet](condorcet/)), and scoring rules ([scoring_rule](scoring_rule/), [shapley](shapley/)).

```lua
-- init.lua  (Computation pkg)
local S = require("alc_shapes")
local T = S.T

local M = {}

M.meta = {
    name = "my_calc",
    version = "0.1.0",
    description = "Pure calculation primitive",
    category = "validation",
}

local cfg_shape   = T.shape({ alpha = T.number }, { open = true })
local state_shape = T.shape({ alpha = T.number, n = T.number }, { open = true })

M.spec = {
    entries = {
        new = {
            args   = { cfg_shape },
            result = state_shape,
        },
        observe = {
            args   = { state_shape, T.number },
            result = state_shape,
        },
    },
}

function M.new(cfg)       return { alpha = cfg.alpha, n = 0 } end
function M.observe(st, x) st.n = st.n + x; return st end

M.new     = S.instrument(M, "new")
M.observe = S.instrument(M, "observe")

return M
```

Rules:

- `args` and `input` are **mutually exclusive** per entry (enforced by `spec_resolver`).
- **Multiple entries are the norm** — a Computation pkg typically declares several (no single `run`). Each entry has its own `args` list.
- `instrument` wraps each function **per argument** when it sees `args`, instead of per-ctx.
- Canonical examples: [`sprt/init.lua`](sprt/init.lua) (streaming), [`kemeny/init.lua`](kemeny/init.lua) / [`condorcet/init.lua`](condorcet/init.lua) (voting), [`scoring_rule/init.lua`](scoring_rule/init.lua) (scoring).

### Named shape vs inline shape

`M.spec.entries.run.result` (and `input`) accept either an **inline schema** (`T.shape({...})`) or a **named reference** (`"my_shape"`, coerced to `T.ref("my_shape")` against the `alc_shapes` registry).

- **Default — inline.** A result used by only one package stays inline. No registry entry needed.
- **Register a named shape when** (a) multiple packages share the same result contract (e.g. `sc` and `recipe_safe_panel` both depend on `voted`), or (b) you want a LuaCATS type alias exposed in [`types/alc_shapes.d.lua`](types/alc_shapes.d.lua). To register: add `M.<name> = T.shape({...}, { open = true })` to [`alc_shapes/init.lua`](alc_shapes/init.lua), then run `just gen-shapes` to refresh the LuaCATS projection.
- The full DSL reference and the list of currently registered shapes live in [`alc_shapes/README.md`](alc_shapes/README.md) — see [DSL combinators](alc_shapes/README.md#dsl-combinators) and [Registered shapes](alc_shapes/README.md#registered-shapes).

A single package is one repo with one `init.lua`. To bundle multiple packages, use a subdirectory layout like this repository (Collection).

## Claude Code Integration (alc-runner Agent)

algocline packages can be executed via the `alc-runner` subagent in Claude Code. A single generic agent handles all packages — you specify which package to run and the task, and the agent drives the entire `alc_run`/`alc_continue` loop autonomously.

### Setup

The agent definition is maintained in the [algocline](https://github.com/ynishi/algocline) main repository under `agents/claude/alc-runner.md`. Copy it to your Claude Code agents directory:

```bash
cp agents/claude/alc-runner.md ~/.claude/agents/
```

### How It Works

1. **Main agent delegates** — The main Claude Code agent spawns `alc-runner` as a subagent with a prompt specifying the package name and task
2. **alc-runner drives the loop** — The subagent calls `alc_advice` (or `alc_run`), receives paused prompts from `alc.llm()`, generates responses, and feeds them back via `alc_continue` until completion
3. **Result returns to main** — Only the final result is returned to the main conversation context

### Benefits

- **Context isolation** — The main agent's context window is not consumed by the dozens of intermediate LLM calls. A pre_mortem run with 4 proposals generates ~77 LLM calls internally, but only the final summary returns to the main context
- **Session logs** — Every run is logged with a session ID. Use `alc_log_view` to inspect exactly what prompts were sent and responses generated, for full auditability
- **Any package, one agent** — No need for per-package agent definitions. `alc-runner` is generic and works with all installed packages

### Usage Examples

From the main Claude Code agent:

```
# Evaluate proposals with pre_mortem
Use the alc-runner agent to run pre_mortem on these proposals: [...]

# Multi-perspective analysis with panel
Use the alc-runner agent to run panel on this question: "Should we use async or sync for this module?"

# Self-consistency check
Use the alc-runner agent to run sc on: "What is the optimal data structure for this use case?"
```

### Typical LLM Call Counts

| Package | LLM Calls | Description |
|---|---|---|
| pre_mortem | ~19/proposal + ranking | Feasibility-gate proposals, then rank accepted ones |
| ucb | ~11 | UCB1 hypothesis exploration |
| moa | ~4-8 | Layered multi-agent aggregation |
| panel | ~5-8 | Multi-perspective deliberation |
| rstar | ~4-6 | Mutual reasoning verification (2 paths cross-verify) |
| cove | ~4-6 | Chain-of-verification |
| faithful | ~3-4 | Formal verification (code/logic) of reasoning |
| bot | ~3-4 | Template-based meta-reasoning |
| reflect | ~3-6 | Self-critique loop |
| sc | ~5 | Self-consistency (majority vote) |
| plan_solve | ~2-3 | Plan then execute step by step |
| s2a | ~2 | Context denoising (composable pre-filter) |
| optimize | ~N (rounds) | Parameter optimization (1 eval call per round) |
| orch_escalate | ~1-5 | Cascade escalation (stops early on easy tasks) |
| orch_fixpipe | ~N (phases) | Fixed pipeline (1 call per phase + retries) |
| orch_gatephase | ~N (phases) | Gate-phase orchestration with skip rules |
| orch_adaptive | ~N (phases) | Adaptive depth (phases trimmed by difficulty) |
| orch_nver | ~N×M | N variants × M phases each |
| router_daao | ~1 | Single difficulty classification call |
| router_semantic | ~0-1 | Keyword match first, LLM fallback if ambiguous |
| router_capability | ~1 | Single requirement extraction call |
| calibrate | ~1-2 | Confidence-gated reasoning |
| got | ~11 | DAG reasoning: generate + score + refine + aggregate + synthesize |
| ab_mcts | ~2×N+1 | Adaptive branching MCTS (N = budget, default 8 → ~17) |
| counterfactual_verify | ~2+3×N | Causal faithfulness test (N = counterfactuals, default 2 → ~8-9) |
| model_first | ~2-4 | Problem modeling then solving with constraint verification |
| coa | ~2+N | Abstract chain + parallel grounding (N = placeholders) |
| sketch | ~1-2 | Cognitive-inspired efficient reasoning (keyword route or LLM route) |
| lineage | ~2×N | Pipeline lineage tracking (N = steps; N extract + N-1 trace + 1 analysis = 2N) |
| dissent | ~3-4 | Adversarial challenge + merit evaluation + conditional revision |
| anti_cascade | ~1+2×N | Cascade detection (N = steps; re-derive + compare per step + summary) |
| topo_route | ~1 | Single topology analysis and recommendation call |
| qdaif | ~seed+2×iter+1 | MAP-Elites archive (seed + mutate/evaluate per iteration + synthesis) |
| falsify | ~1+rounds×hyp×2+1 | Falsification (seed + refute/judge per hypothesis per round + synthesis) |
| prompt_breed | ~pop×gen×2+hyper | Prompt evolution (evaluate+mutate per individual per generation + hyper-mutations) |
| coevolve | ~rounds×(prob×2+2) | Co-evolution (solve+judge per problem + analyze + challenge per round) |
| usc | ~N+1 | Universal Self-Consistency (N samples + 1 consistency selection, default N=5 → ~6) |
| mbr_select | ~N+N(N-1)/2 | Minimum Bayes Risk (N generation + pairwise similarity, default N=5 → ~15) |
| step_verify | ~1+N+1 per round | Step-level verification (generate + N step verifications + synthesis, with re-derive rounds) |
| compute_alloc | ~1+N | Compute-optimal allocation (1 difficulty classification + N strategy calls, varies by difficulty) |
| gumbel_search | ~N+N×log₂(N) | Gumbel+Sequential Halving (N candidates + log₂(N) halving rounds, default N=8 → ~32) |
| reflexion | ~trials×(1+1+1) | Episodic memory (attempt+evaluate+reflect per trial, default 3 trials → ~7-9) |
| analogical | ~2×N+2 | Analogical reasoning (N analogy pairs + pattern extraction + solution, default N=2 → ~6) |
| contrastive | ~2×N+1 | Contrastive CoT (N wrong-reasoning + error-analysis pairs + final answer, default N=2 → ~5) |
| cumulative | ~3×rounds+1 | Cumulative reasoning (propose+verify+conclude per round + final report) |
| diverse | ~2×N+1 | DiVERSe (N reasoning paths × score + final answer, default N=5 → ~11) |
| dmad | ~2+2×rounds | Dialectical (thesis + antithesis+rebuttal per round + synthesis, default 2 rounds → ~6) |
| least_to_most | ~N+2 | Least-to-Most (decompose + N subproblems + synthesis) |
| mcts | ~budget×2+1 | MCTS (expand+simulate per node + conclusion, default budget=8 → ~17) |
| meta_prompt | ~N+2 | Meta-Prompting (analysis + N expert consultations + synthesis, default N=3 → ~5) |
| php | ~1+2×rounds | Progressive-Hint (initial + hint+verify per round, default 3 rounds → ~7) |
| step_back | ~2×N+2-3 | Step-Back (N principle pairs + solution + verify, default N=1 → ~4-5) |
| tot | ~N×2+1 | Tree-of-Thought (N thoughts × score + conclusion, budget-dependent) |
| verify_first | ~2×rounds | Verification-First (candidate+verify per round, default 3 rounds → ~6) |
| negation | ~2+N | Adversarial test (generate + conditions + N verifications + optional revision, default N=3 → ~5-6) |
| bisect | ~1+log₂(N)+1 | Binary error search (chain + O(log n) verdicts + regeneration) |
| blind_spot | ~2-3 | Blind spot bypass (initial + external correction + optional synthesis) |
| claim_trace | ~1-2+N | Evidence attribution (optional generation + extraction + N claim attributions) |
| critic | ~1+N+1 per round | Rubric evaluation (generation + N dimension scores + revision per round) |
| cascade | ~1-5 | Difficulty escalation (1 if easy, up to 5 with perspectives+synthesis) |
| ambig | ~3 | Underspecification detection (detect + clarify + integrate) |
| prism | ~4 | Cognitive-load intent decomposition (decompose + dependencies + questions + specify) |
| intent_discovery | ~2×rounds | Intent discovery (options + concretize per round) |
| intent_belief | ~1+2×rounds+1 | Bayesian intent (prior + question+update per round + specify) |
| p_tts | ~3+N per round | Plan-Test-Solve (plan + constraints + solve + N verifications, with retry) |
| deliberate | variable | Structured deliberation (depends on number of experts and debate rounds) |
| robust_qa | variable | Composite pipeline (p_tts + negation + critic stages) |
| cot | ~N+1 | Chain-of-Thought (N reasoning steps + conclusion, default N=3 → ~4) |
| cod | ~1+N | Chain-of-Density (initial summary + N densification rounds, default N=3 → ~4) |
| decompose | ~1+N+1 | Task decomposition (decompose + N parallel subtasks + synthesis) |
| distill | ~N+1 | MapReduce extraction (N parallel chunk extractions + synthesis) |
| factscore | ~1+N | Atomic fact verification (claim extraction + N parallel claim verifications) |
| maieutic | ~2×depth+2 | Recursive explanation tree (support+oppose per depth + verdict + synthesis) |
| rank | ~N+log₂(N) | Tournament selection (N candidate generations + pairwise tournament rounds) |
| review | ~6-8 | Multi-pass code review (detect + cluster + verify + diagnose + research + prescribe + report) |
| sot | ~1+N | Skeleton-of-Thought (skeleton + N parallel section expansions) |
| triad | ~2+2×rounds+1 | Three-role debate (2 openings + pro+opp per round + judge verdict, default 2 rounds → ~7) |
| ab_select | ~N+iterations | Multi-fidelity Thompson sampling (N candidates + Thompson-allocated evaluations until budget exhausted) |
| listwise_rank | ~1 or ~⌈(N-w)/s⌉+1 | Listwise reranking (1 call if N ≤ window_size, sliding-window passes otherwise) |
| pairwise_rank | ~N(N-1) (allpair) / ~N log₂ N (sorting) | PRP bidirectional pairwise (allpair: every pair × 2 directions; sorting: binary-insertion ×2) |
| setwise_rank | ~top_k × (N − top_k/2) / (k − 1) | Setwise tournament — each of the top_k extractions runs a full ⌈log_k(N−r)⌉-round tournament. Summing the geometric series of rounds gives ~(N−r)/(k−1) LLM calls per extraction (NOT just ⌈N/k⌉; that is the first round only) |

## Testing

Tests live under `tests/` and use the [`lust`](https://github.com/bjornbytes/lust)
test framework (`describe` / `it` / `expect`). algocline itself is an MCP server,
and the canonical test runner is also an MCP server: the upstream binary
**[mlua-probe-mcp](https://crates.io/crates/mlua-probe-mcp)**, registered in
this repo's `.mcp.json` under the local alias `lua-debugger`. It ships with
`lust` pre-loaded as a global.

> The upstream `mlua-probe` workspace publishes only `mlua-probe-core` and
> `mlua-probe-mcp` — there is **no `mlua-probe` CLI**. All test invocations
> go through the MCP server.

Install:

```bash
cargo install mlua-probe-mcp
```

### Running tests via the lua-debugger MCP

From Claude Code, the Claude Code SDK, `claude -p`, or any other MCP client
that has loaded this repo's `.mcp.json`, invoke `test_launch` against a test
file:

```
mcp__lua-debugger__test_launch(
  code_file    = "tests/test_ranking_packages.lua",
  search_paths = ["."]   # repo root, so pkg/?.lua and pkg/?/init.lua resolve
)
```

The tool name follows Claude Code's `mcp__<local-alias>__<tool>` convention,
so `lua-debugger` (the alias in `.mcp.json`) becomes `mcp__lua-debugger__*`.
Returns structured JSON: `{ passed, failed, total, tests: [{ suite, name, passed, error }] }`.

> **Worktree gotcha.** mlua-probe-mcp pins its CWD to the directory the server
> was first launched in (typically the main repo root). When invoking from a
> git worktree (`.worktrees/xxx/`), a relative `code_file = "tests/..."` will
> silently resolve against the main repo, so you end up validating the *old*
> code while the green count looks fine. Pass **absolute paths** for both
> `code_file` and `search_paths` when running from a worktree:
>
> ```
> mcp__lua-debugger__test_launch(
>   code_file    = "/abs/path/to/.worktrees/xxx/tests/test_foo.lua",
>   search_paths = ["/abs/path/to/.worktrees/xxx"]
> )
> ```
>
> The local CLI path below does **not** have this pitfall — it uses the
> shell's CWD directly.

### Running tests locally (optional, opt-in)

The tests use only upstream `lust` core API (`describe / it / expect / after`,
`to.equal`, `to.exist`) — no mlua-lspec-specific extensions are required.
If you want to run a single test file outside Claude / MCP, drop
[`bjornbytes/lust`](https://github.com/bjornbytes/lust)'s `lust.lua` somewhere
on your `LUA_PATH`, then from the repo root:

```bash
LUA_PATH="./?.lua;./?/init.lua;$LUA_PATH" lua5.4 tests/test_ranking_packages.lua
```

(Lust is GitHub-only; not on Luarocks. The repo does **not** vendor it.)

### Adding a new test file

1. Create `tests/test_<package>.lua`.
2. Use the standard preamble (matches all existing test files):

   ```lua
   local describe, it, expect = lust.describe, lust.it, lust.expect
   ```

   `package.path` is set by the MCP harness via `search_paths=[REPO]`, so
   the test file itself does not need to manipulate it. (For local opt-in
   execution, set `LUA_PATH` yourself — see above.)

3. Reset `package.loaded` between suites if you mock `_G.alc`:

   ```lua
   local function reset()
       _G.alc = nil
       for _, name in ipairs(PKG_NAMES) do package.loaded[name] = nil end
   end
   lust.after(reset)
   ```

## End-to-End (E2E) Testing

The `tests/` suite exercises package internals with a mocked `_G.alc`. E2E
scenarios under `scripts/e2e/` drive the same packages **through a real LLM
and a live algocline MCP session**, using
[agent-block](https://crates.io/crates/agent-block) as the ReAct driver.

### Prerequisites

```bash
cargo install agent-block      # ReAct driver (runs the Lua scenario)
cargo install algocline        # `alc` MCP server on PATH
```

`.env` at the repo root must export `ANTHROPIC_API_KEY`. `.env` is git-ignored.

```bash
echo 'ANTHROPIC_API_KEY=sk-ant-...' > .env
```

### Running E2E scenarios

Scenarios are run via `just` recipes (the `justfile` at repo root is
`allow-agent` tagged so it is also invokable through `task-mcp`):

```bash
just e2e recipe_safe_panel      # run one scenario
just e2e recipe_ranking_funnel
just e2e-all                    # run every scripts/e2e/*.lua (except common.lua)
```

Direct invocation without `just`:

```bash
agent-block -s scripts/e2e/recipe_safe_panel.lua -p .
```

### Output

Each run persists a JSON report to
`workspace/e2e-results/<timestamp>/<scenario>.json` with agent trace (turns,
tokens, final answer) and per-grader pass/fail. stdout also prints a summary:

```
=== E2E recipe_safe_panel: PASS ===
  [PASS] agent_ok
  [PASS] answer_tokyo
  [PASS] max_turns:15
  [PASS] max_tokens:200000
  [PASS] anti_jury_not_triggered
  [PASS] reports_panel_size
```

### Authoring a new E2E

1. Create `scripts/e2e/<name>.lua`.
2. Require the shared harness and call `common.run { ... }`:

   ```lua
   local common = require("scripts.e2e.common")
   return common.run({
       name    = "my_recipe",
       prompt  = "... task for the agent ...",
       graders = {
           common.graders.agent_ok,
           common.graders.answer_contains("expected"),
           common.graders.max_turns(15),
           common.graders.custom("my_check", function(result)
               return result.agent.final_answer:match("pattern") ~= nil
           end),
       },
   })
   ```

3. Run `just e2e <name>` and iterate. See `scripts/e2e/common.lua` for the full
   grader API (`agent_ok`, `answer_contains`, `answer_excludes`, `max_turns`,
   `max_tokens`, `custom`).

### Notes

- E2E runs are **non-deterministic** (live LLM) and **billable**. Prefer the
  pure-Lua structure tests (`mcp__lua-debugger__test_launch`, see §Testing)
  for tight loops; run E2E on meaningful changes only.
- agent-block spawns the `alc` MCP server as a child process, so `alc` must be
  on `PATH` and the current working directory must contain `alc.toml` (the
  repo root already does).
- Set `ALGOCLINE_LOG_DIR` or other algocline env vars before invoking
  `agent-block` if you need verbose session logs.

## License

MIT OR Apache-2.0
