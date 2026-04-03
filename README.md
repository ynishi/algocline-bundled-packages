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

## Packages (77)

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
| **[optimize](optimize/)** | Modular parameter optimization orchestrator. Pluggable search (UCB1, OPRO, EA, greedy), evaluators (evalframe, custom, LLM judge), and stopping criteria. Persists state across sessions | DSPy (2023), OPRO (2023), EvoPrompt (2024) |

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

### Exploration

| Package | Description | Based On |
|---------|-------------|----------|
| **[qdaif](qdaif/)** | Quality-Diversity through AI Feedback. MAP-Elites archive with LLM-driven mutation, evaluation, and feature classification. Produces diverse, high-quality solution populations | Bradley et al. (ICLR 2024), Mouret & Clune (2015) |
| **[falsify](falsify/)** | Sequential Falsification. Popper-style hypothesis exploration via active refutation, pruning, and successor derivation. Expands search space through refutation-driven insight | Sourati et al. (2025), Yamada et al. "AI Scientist v2" (2025) |
| **[prompt_breed](prompt_breed/)** | Self-Referential Prompt Evolution. Evolves task prompts via genetic operators with meta-mutation — the mutation operators themselves evolve. Double evolutionary loop | Fernando et al. "PromptBreeder" (2023), Guo et al. "EvoPrompt" (ICLR 2024) |
| **[coevolve](coevolve/)** | Challenger-Solver Co-evolution. Adversarial self-play where Challenger generates problems at Solver's ability boundary and Solver evolves to solve them. Automatic search space expansion | Singh et al. (2025), Faldor et al. "OMNI-EPIC" (ICLR 2025) |

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
local M = {}

M.meta = {
    name = "my-strategy",
    version = "0.1.0",
    description = "My custom strategy",
    category = "reasoning",
}

function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    -- Implement using alc.llm(), alc.map(), etc.
    ctx.result = { answer = "..." }
    return ctx
end

return M
```

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

## License

MIT OR Apache-2.0
