---
name: think_prm
version: 0.1.0
category: validation
result_shape: "shape { chains: array of shape { chain: string, correct: boolean, invalid: boolean, verdicts: array of string }, correct: boolean, invalid: boolean, score: number, valid_chains: number }"
description: "ThinkPRM verifier — emits a per-step thinking chain and \\boxed{correct|incorrect} verdicts."
source: think_prm/init.lua
generated: gen_docs (V0)
---

# think_prm(ThinkPRM) — verifier that thinks before judging each step

> Drives an LLM as a process reward model that emits a verification chain (Let's verify step by step ... step k: <critique> ... \boxed{ correct|incorrect}) and then extracts per-step verdicts plus a solution-level binary verdict. Implements the training-free / zero- shot path described by the paper; the finetuned ThinkPRM force- decode aggregation is out of scope (see Caveats).

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [Caveats](#caveats)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local think_prm = require("think_prm")
return think_prm.run({
    problem = "...",
    solution_steps = { "Step1 ...", "Step2 ...", ... },
})
```

## Algorithm {#algorithm}

1. build_prompt: insert {problem} and {solution} (step-indexed)
   into the verifier prompt template (Figure 14 literal).
2. Call the verifier LLM n_parallel_cots times (K-CoT scaling, §4)
   to obtain K independent verification chains.
3. parse_verdicts: extract `\boxed{correct}` / `\boxed{incorrect}`
   tokens per step from each verification chain.
4. aggregate: collapse per-CoT, per-step verdicts to one
   solution-level score. `any_incorrect` (default) returns false at
   the first incorrect step in any CoT averaged across CoTs.

## Caveats {#caveats}

Two large caveats apply when using this pkg:

1. **The verifier model matters a lot**. The paper reports that
   smaller distilled models (e.g. R1-Distill-Qwen-1.5B) emit invalid
   judgment formats 51%+ of the time and effectively cannot serve as
   verifiers. The training-free path here only matches paper
   performance when callers route to a strong reasoning model — the
   paper baselines use R1-Distill-Qwen-14B or QwQ-32B-Preview.
   Callers running smaller models should expect high invalid /
   parse-failure rates.

2. **The canonical ThinkPRM solution score is out of scope**. Paper
   §E.1 produces a continuous solution score by force-decoding the
   string "Is the solution correct?" after the verification chain
   and using `P(yes) / (P(yes) + P(no))` from next-token logits.
   That requires direct logits access which the `alc.llm` abstraction
   does not expose; therefore this pkg aggregates using the
   `\boxed{correct|incorrect}` literals only. The paper's K-CoT
   parallel scaling is approximated by averaging the per-CoT binary
   solution verdicts into a continuous score in [0, 1].

The prompt template is taken verbatim from Figure 14 of the paper.
Callers can override it via `prompt_template` but doing so voids the
paper's correctness reports.

## References {#references}

- Khalifa, M., Agarwal, R., Logeswaran, L., Kim, J., Peng, H.,
  Lee, M., Lee, H., Wang, L. (2025). "Process Reward Models That
  Think (ThinkPRM)". arXiv:2504.16828 §3 (method), §4 (experiments),
  Figure 14 (verifier prompt template), Appendix A.2 / E.1
  (aggregation). https://arxiv.org/abs/2504.16828
- Official code + models: https://github.com/mukhal/thinkprm

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.aggregation` | string | optional | Per-chain aggregation method (default: 'any_incorrect'; matches Figure 14 early-stop semantics. 'all_correct' requires every step verdict to be correct. The paper's canonical force-decode aggregation P(yes)/(P(yes)+P(no)) is out of scope — see Caveats) |
| `ctx.max_thinking_tokens` | number | optional | Token cap per verifier chain (default: 4096; Khalifa 2025 §4 to avoid overthinking) |
| `ctx.n_parallel_cots` | number | optional | Number of independent verification chains to sample (default: 1; paper §4 experimental range 1 / 4 / 8 for K-CoT averaging) |
| `ctx.problem` | string | **required** | Math problem statement |
| `ctx.prompt_template` | string | optional | Override verifier prompt template (default: paper Figure 14 literal; override voids paper's correctness reports) |
| `ctx.solution_steps` | array of string | **required** | Solution as an ordered list of step strings (one step per element) |
| `ctx.temperature` | number | optional | LLM sampling temperature (default: 0.1; Khalifa 2025 §4 default) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `chains` | array of shape { chain: string, correct: boolean, invalid: boolean, verdicts: array of string } | — | Per-chain records for inspection |
| `correct` | boolean | — | Solution-level majority verdict across K verification chains (score >= 0.5) |
| `invalid` | boolean | — | True when every verification chain was invalid (no \boxed tokens parsed) |
| `score` | number | — | Fraction of valid chains that judged the solution correct, in [0, 1] (paper §4 K-CoT averaging approximation; 0 when all chains invalid) |
| `valid_chains` | number | — | Number of chains whose verdicts parsed successfully |
