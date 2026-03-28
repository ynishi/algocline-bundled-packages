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

## Packages (37)

### Reasoning

| Package | Description | Based On |
|---------|-------------|----------|
| **[cot](cot/)** | Chain-of-Thought. Builds a step-by-step reasoning chain and synthesizes a final answer | Wei et al. (2022) |
| **[maieutic](maieutic/)** | Recursive explanation tree with logical consistency filtering. Generates supporting/opposing arguments recursively and eliminates contradictions | Jung et al. (2022) |
| **[reflect](reflect/)** | Iterative self-critique loop. Generate, critique, and revise until convergence | Madaan et al., "Self-Refine" (2023) |
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

### Selection

| Package | Description | Based On |
|---------|-------------|----------|
| **[sc](sc/)** | Self-Consistency. Independently samples multiple reasoning paths and aggregates by majority vote | Wang et al. (2022) |
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

### Orchestration

| Package | Description | Based On |
|---------|-------------|----------|
| **[orch_fixpipe](orch_fixpipe/)** | Deterministic fixed pipeline. Phases execute in strict order with gate/retry | Lobster (OpenClaw) |
| **[orch_gatephase](orch_gatephase/)** | Gate-phase orchestration with pre/post hooks. Task-type-aware skip rules | Thin Agent / Fat Platform (Praetorian) |
| **[orch_adaptive](orch_adaptive/)** | Adaptive depth orchestration. Adjusts phase count, retry budget, and context mode by task difficulty | DAAO (arXiv:2509.11079) |
| **[orch_nver](orch_nver/)** | N-version programming. Execute N parallel variants, evaluate each, select best | Agentic SE Roadmap (arXiv:2509.06216) |
| **[orch_escalate](orch_escalate/)** | Cascade escalation from light to heavy strategies. Minimizes cost for easy tasks | Microsoft + DAAO |

### Routing

| Package | Description | Based On |
|---------|-------------|----------|
| **[router_daao](router_daao/)** | Difficulty-aware routing with injectable confidence profiles | DAAO (arXiv:2509.11079) |
| **[router_semantic](router_semantic/)** | Keyword matching with LLM fallback. 0-1 LLM calls | Microsoft Multi-Agent Reference Architecture |
| **[router_capability](router_capability/)** | Capability-based registry router. Jaccard similarity agent matching | Dynamic Agent Registry |

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

## License

MIT OR Apache-2.0
