---
name: speculative_rejection
version: 0.1.0
category: selection
result_shape: "shape { candidates_final: number, candidates_initial: number, rationale: string, rejection_history: array of shape { rejected_indices: array of number, round: number, scores: array of number, survivors_after: number, survivors_before: number }, selected: string }"
description: "Iterative reward-pruned best-of-N selection (Sun 2024 speculative rejection, adapted to alc.llm call granularity)"
source: speculative_rejection/init.lua
generated: gen_docs (V0)
---

# speculative_rejection(SpeculativeRejection) — iterative reward-pruned best-of-N

> Adapts Sun et al. NeurIPS 2024 "Fast Best-of-N Decoding via Speculative Rejection" (arXiv:2410.20290, Algorithm 1) to the `alc.llm` text-generation context. The paper's original scheme operates at token-level: N candidates share the same GPU forward pass, a reward model scores each partial at checkpoint token positions t_1, t_2, ..., and the bottom-alpha fraction is rejected between checkpoints so that at end-of-decode only the strongest candidate remains. The paper reports up to ~24x speedup vs vanilla Best-of-N on LLM alignment benchmarks (Sun 2024 §5).

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [API](#api)
- [Comparison with related packages](#comparison-with-related-packages)
- [Caveats](#caveats)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local sr = require("speculative_rejection")
return sr.run({ task = "Prove the AM-GM inequality." })
```

## Algorithm {#algorithm}

**Paper original (Sun 2024, Algorithm 1, token-level)**:

1. Start with N candidates decoding in parallel (paper uses N=1000).
2. At checkpoint token position t_1, a reward model scores every partial.
3. Reject the bottom alpha fraction (alpha=0.5 in the paper, §4.1).
4. Continue survivors to t_2, re-score, reject bottom alpha. Repeat.
5. Return the surviving candidate with the highest final reward.

**Adaptation to alc.llm (call-level)**:

1. Round 1 — `alc.llm_batch` generates N short partial completions
   (default `partial_tokens = 100` tokens each).
2. Round 1 scoring — a single `alc.llm` pass scores every partial 0-10
   against `reward_rubric`.
3. Reject the bottom `alpha` fraction of scored partials.
4. Round 2..`rounds` — `alc.llm_batch` extends each surviving partial by
   `extend_tokens` more tokens; re-score; reject bottom alpha.
5. Final — one `alc.llm` selector pass emits SELECTED + RATIONALE over
   the final survivors (may be one candidate; the call still runs to
   produce a rationale for the caller).

Call budget = rounds x (1 alc.llm_batch + 1 alc.llm) + 1 alc.llm selector
= 3 x 2 + 1 = 7 calls at defaults. This is NOT a strict win over
`verify_select`'s 2 calls — see Comparison.

## API {#api}

- `ctx.task`           — string, required. Empty / whitespace-only -> error.
- `ctx.n`              — number, optional. Initial candidate count
  (default 8).
- `ctx.alpha`          — number, optional. Rejection ratio per round in
  [0, 1] (default 0.5).
- `ctx.rounds`         — number, optional. Number of rejection stages
  (default 3).
- `ctx.reward_rubric`  — string, optional. Scoring rubric injected verbatim
  into every scoring prompt (default: generic quality rubric).
- `ctx.partial_tokens` — number, optional. Tokens per initial generation
  (default 100).
- `ctx.extend_tokens`  — number, optional. Tokens added per extension round
  (default 200).

Result (`ctx.result`):
- `selected`           — string, the winning full completion.
- `candidates_initial` — number, initial N.
- `candidates_final`   — number, how many candidates survived the final
  round.
- `rejection_history`  — array, one entry per rejection round, in order.
  Each entry is `{ round, survivors_before, survivors_after,
  rejected_indices, scores }`. `rejected_indices` are ORIGINAL 1-based
  indices into the initial batch (stable identity across rounds). `scores`
  is the dense per-survivor score array from that round's reward pass.
- `rationale`          — string, the final selector's justification.

## Comparison with related packages {#comparison-with-related-packages}

vs `verify_select`: `verify_select` generates full N candidates then picks
the best in 2 calls (1 batch + 1 verifier). `speculative_rejection`
prunes iteratively so that losers do not consume extension-round tokens,
trading MORE sequential `alc.llm` calls (7 vs 2 at defaults) for FEWER
generation tokens spent on eventual losers. It is a win when generations
are long and losers can be identified early (rounds >= 2), a loss when
generations are already short (verify_select is cheaper end-to-end). Not
a strict Pareto improvement — pick per token-vs-latency budget.

vs `sc`: `sc` (self-consistency, Wang 2023) is majority vote over
identical answers, appropriate when the task admits a single canonical
answer that convergent sampling should hit. `speculative_rejection` is
quality-based selection for divergent, reward-scorable answers — the
adaptive-cost variant of `verify_select`.

vs `mbr_select`: `mbr_select` uses inter-candidate similarity (MBR).
`speculative_rejection` uses an external reward model score, and prunes
iteratively — orthogonal signal source, orthogonal cost profile.

## Caveats {#caveats}

**Token-level to call-level adaptation (implementation choice)**. The
paper's central efficiency claim relies on token-level parallel decoding:
one shared GPU forward pass produces N partials simultaneously, so
rejecting half of them mid-decode literally halves subsequent compute.
`alc.llm` / `alc.llm_batch` are call-level primitives with no token-stream
access from the Lua host, so the adaptation collapses each "checkpoint"
into one `alc.llm_batch` + one `alc.llm` scoring pass. Consequently the
paper's headline speedup (~24x vs BoN) does NOT carry over verbatim; the
adaptation captures the pruning-early quality signal without the shared-
forward-pass compute savings. This is an unavoidable adaptation gap and
callers should understand the package as "iterative reward-pruned BoN at
LLM-call granularity", not a literal reproduction of Sun 2024.

**Diversity is host-side**. Each initial-batch item carries a distinct
system persona (candidate #i) to nudge divergence, but genuine sampling
diversity requires temperature > 0 on the host / provider side.

**Reward model quality dominates**. The rubric-based `alc.llm` scoring
pass is a soft reward model. If the reward LLM cannot reliably rank
partial responses against the rubric, aggressive alpha will prune good
candidates early. Start with alpha=0.5 (paper canonical) and tune based
on empirical retention behavior.

**Extension points (all optional, override at your own risk)**:
`ctx.n` (default 8; implementation choice — paper uses N=1000 for
token-level, at LLM-call granularity 8 is a practical starting cost),
`ctx.alpha` (default 0.5; Sun 2024 §4.1 canonical value — overriding
forfeits paper alignment), `ctx.rounds` (default 3; implementation choice
to bound `alc.llm_batch` cost), `ctx.reward_rubric` (default generic
quality rubric; override for domain-specific reward), `ctx.partial_tokens`
(default 100; implementation choice), `ctx.extend_tokens` (default 200;
implementation choice).

## References {#references}

- Sun, H., Haider, M., Zhang, R., Yang, H., Qiu, J., Yin, M., Wang, M.,
  Bartlett, P., Zanette, A. (2024). "Fast Best-of-N Decoding via
  Speculative Rejection." NeurIPS 2024. arXiv:2410.20290. Algorithm 1
  (rejection sampling schedule), §4.1 (alpha=0.5 canonical setting),
  §5 (empirical speedup).

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.alpha` | number | optional | Rejection ratio per round in [0, 1] (default: 0.5; Sun 2024 §4.1 canonical setting) |
| `ctx.extend_tokens` | number | optional | Tokens added per extension round (default: 200; implementation choice sized to typical continuation budget between rejection checkpoints) |
| `ctx.n` | number | optional | Initial candidate count (default: 8; implementation choice — paper uses N=1000 for token-level parallel decoding, but at alc.llm-call granularity 8 is a practical starting cost) |
| `ctx.partial_tokens` | number | optional | Tokens per initial generation (default: 100; implementation choice — paper checkpoints at token positions, not call boundaries) |
| `ctx.reward_rubric` | string | optional | Rubric injected verbatim into every scoring prompt (default: generic quality rubric; override for domain-specific reward) |
| `ctx.rounds` | number | optional | Number of rejection stages (default: 3; implementation choice to bound alc.llm_batch cost — paper runs until decode completes at token level) |
| `ctx.task` | string | **required** | Problem to solve (required, non-empty) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `candidates_final` | number | — | Number of candidates surviving the final rejection round |
| `candidates_initial` | number | — | Initial candidate count |
| `rationale` | string | — | Final selector's justification for the winning candidate |
| `rejection_history` | array of shape { rejected_indices: array of number, round: number, scores: array of number, survivors_after: number, survivors_before: number } | — | Ordered per-round rejection records |
| `selected` | string | — | The winning full completion |
