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

## Packages (16)

### Reasoning

| Package | Description | Based On |
|---------|-------------|----------|
| **[cot](cot/)** | Chain-of-Thought. Builds a step-by-step reasoning chain and synthesizes a final answer | Wei et al. (2022) |
| **[maieutic](maieutic/)** | Recursive explanation tree with logical consistency filtering. Generates supporting/opposing arguments recursively and eliminates contradictions | Jung et al. (2022) |
| **[reflect](reflect/)** | Iterative self-critique loop. Generate, critique, and revise until convergence | Madaan et al., "Self-Refine" (2023) |
| **[calibrate](calibrate/)** | Confidence-gated adaptive reasoning. Escalates to sc/panel/retry when confidence falls below threshold | CISC (ACL Findings 2025) |

### Selection

| Package | Description | Based On |
|---------|-------------|----------|
| **[sc](sc/)** | Self-Consistency. Independently samples multiple reasoning paths and aggregates by majority vote | Wang et al. (2022) |
| **[ucb](ucb/)** | UCB1 hypothesis exploration. Generates, scores, and refines hypotheses using UCB1 selection | — |
| **[rank](rank/)** | Best-of-N sampling with tournament selection. Pairwise comparison via LLM-as-Judge | Zheng et al. (2023) |
| **[triad](triad/)** | Three-role adversarial debate. Proponent, opponent, and judge engage in multi-round argumentation | Du et al. (2023) |

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

### Validation / Analysis

| Package | Description | Based On |
|---------|-------------|----------|
| **[cove](cove/)** | Chain-of-Verification. Draft, generate verification questions, answer independently, then revise to reduce hallucination | Dhuliawala et al. (2023) |
| **[factscore](factscore/)** | Atomic claim decomposition + individual fact verification. Decomposes text into minimal factual claims and scores each | Min et al. (2023) |
| **[review](review_and_investigate/)** | Multi-pass code review. Switchable between chunk mode and concerns mode | — |

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

## License

MIT OR Apache-2.0
