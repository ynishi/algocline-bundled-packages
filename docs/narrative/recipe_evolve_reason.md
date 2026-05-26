---
name: recipe_evolve_reason
version: 0.1.0
category: recipe
result_shape: evolved_reason
description: "Multi-generation evolutionary LLM reasoning. Maintains a population of reasoning paths that compete, mutate, and evolve across generations via civic primitives. Targets hard problems where single-generation voting (recipe_quick_vote / recipe_safe_panel) cannot converge."
source: recipe_evolve_reason/init.lua
generated: gen_docs (V0)
---

# recipe_evolve_reason — multi-generation evolutionary LLM reasoning

> Maintains a population of N reasoning slots across G generations. Each generation: LLM generates reasoning, peer-evaluation scores fitness, transition rules select elites, lineage begets children via LLM-driven mutation, and knowledge channel inherits insights. Converges to a high-fitness answer through evolutionary pressure.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [Caveats](#caveats)

## Usage {#usage}

```lua
local recipe = require("recipe_evolve_reason")
return recipe.run({
    task = "Prove that sqrt(2) is irrational.",
    pop_size = 6,
    max_gen = 3,
    elite_ratio = 0.5,
    gen_tokens = 600,
})
```

## Algorithm {#algorithm}

1. Gen 0: LLM generates N independent reasoning paths (1 call each).
2. Peer evaluation: each pair (i, j) where i < j, LLM scores both
   on a 1-10 scale (1 call per pair). Scores accumulate in
   civic.scalar_pool with source="peer".
3. Transition: top `elite_ratio` fraction → "elite", rest →
   "eliminated" via civic.transition_rules.
4. Reproduction: each eliminated slot is replaced by a child of a
   random elite parent. civic.lineage.beget with mutation_op that
   calls LLM to improve the parent reasoning (1 call per child).
   civic.knowledge_channel transfers the parent's key insight to
   the child (1 call per child).
5. Repeat 2-4 for max_gen generations.
6. Return the highest-scoring reasoning from the final generation.

## Caveats {#caveats}

Peer evaluation cost is O(N^2) per generation. Keep pop_size <= 8
for practical LLM budgets. For N=6, max_gen=3: worst case ~69 LLM
calls (6 init + 15 eval × 3 gen + 3 mutate × 2 gen + 3 inherit
× 2 gen).

No canonical paper for evolutionary LLM reasoning as a recipe
pattern. Design draws on tournament selection (Goldberg 1991 §4),
self-play evaluation (Silver et al. 2017 Nature), and LLM-as-judge
(Zheng et al. 2023 arXiv:2306.05685). Implementation choice: civic
primitives provide the population / scoring / selection / lineage
infrastructure, LLM provides reasoning + evaluation + mutation.
