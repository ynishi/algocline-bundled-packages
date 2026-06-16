---
name: think_prm
version: 0.2.0
category: validation
result_shape: "shape { chains: array of shape { chain: string, correct: boolean, invalid: boolean, verdicts: array of string }, correct: boolean, invalid: boolean, score: number, valid_chains: number }"
description: "ThinkPRM verifier — per-step thinking chain + \\boxed{correct|incorrect} verdicts (Khalifa 2025 §4 / Figure 21, training-free path)."
source: think_prm/init.lua
generated: gen_docs (V0)
---

# think_prm(ThinkPRM) — verifier that thinks before judging each step

> Drives an LLM as a process reward model that emits a verification chain ("Let's verify step by step ... Step k: <critique> ... \boxed{correct|incorrect}") and then extracts per-step verdicts plus a solution-level binary verdict. Implements the training-free / zero-shot path described by the paper; the finetuned ThinkPRM force-decode aggregation is out of scope (see Caveats).

## Contents

- [Algorithm](#algorithm)
- [Implementation choices (paper does not prescribe; spelled out)](#implementation-choices-paper-does-not-prescribe-spelled-out)
- [Caveats](#caveats)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Algorithm {#algorithm}

1. `build_prompt` — insert `{problem}` and step-indexed `{solution}`
   into the paper Figure 21 verifier template (verbatim by default;
   the `early_stop_on_incorrect=false` knob substitutes the last
   line for an explicit "critique all steps" instruction).
2. `verify` — invoke the LLM once with the built prompt to obtain a
   verification chain, then `parse_verdicts` extracts the per-step
   `\boxed{correct|incorrect}` tokens.
3. `aggregate` — collapse per-CoT verdicts to a solution-level
   binary (`any_incorrect` default; matches Figure 21 early-stop
   semantics).
4. `run` — repeat steps 1-3 `n_parallel_cots` times (paper §4 K-CoT
   scaling) and average the per-CoT binary verdicts into a
   continuous score in [0, 1] (the paper's force-decode P(yes) /
   [P(yes) + P(no)] is out of scope; see Caveats).

`M.run` and `M.verify` use **nested dispatch** so the
`S.instrument` wrappers fire on every sub-call:

  - `M.run` calls `M.verify` (× K) and `M.aggregate` (× K)
  - `M.verify` calls `M.build_prompt` and `M.parse_verdicts`

See `alc_shapes/README` §Producer usage "Nested dispatch".

## Implementation choices (paper does not prescribe; spelled out) {#implementation-choices-paper-does-not-prescribe-spelled-out}

Every default below records its source explicitly in its inline
comment: paper-literal citations with section refs, industry-
standard heuristics with source links, or implementation-choice
rationale spelled out. No default is implicit.

 - `prompt_template` = Figure 21 verbatim — Khalifa 2025
   Appendix A.2 / Figure 21. Override voids the paper's correctness
   reports.
 - `temperature` = 0.1 — (I) conservative default taken
   from the official ThinkPRM repo README basic usage example.
   Khalifa 2025 §4 / §E.2 actually report per-model sampling
   defaults T=0.4 (Qwen-2.5-14B) / T=0.8 (Llama-3.2-3B-
   Instruct); 0.1 is the implementation default, not a
   paper-prescribed value.
 - `max_thinking_tokens` = 4096 — (I) value taken from the
   official ThinkPRM repo init example (`max_length=4096`).
   Khalifa 2025 §4 actually generates up to a maximum of 8192
   tokens; 4096 is the more conservative implementation default
   the pkg inherits, not a paper-prescribed cap.
 - `n_parallel_cots` = 1 — Khalifa 2025 §4 K-CoT averaging.
   Default 1 reproduces the single-chain baseline; experimental
   range 1 / 4 / 8.
 - `early_stop_on_incorrect` = true — Figure 21 prompt
   literally instructs the verifier to stop at the first incorrect
   step. The paper experiments are with early-stop on; setting
   false substitutes the final prompt line for an explicit
   "critique all steps" instruction, voiding paper alignment.
 - `aggregation` = "any_incorrect" — The paper §E.1
   canonical solution score is `P(yes) / [P(yes) + P(no)]`
   force-decoded after the verification chain, which requires
   next-token logits access that `alc.llm` does not expose. The
   training-free path uses the early-stop prompt's implied logic:
   presence of any `\boxed{incorrect}` ⇒ solution incorrect. The
   optional `all_correct` method requires every verdict to be
   "correct" (rejects on any non-correct token, useful for stricter
   callers).
 - `score_majority_threshold` = 0.5 — K-CoT averaged
   fraction of "correct" chains is binarized at 0.5 to produce the
   `correct` field. Paper does not specify a threshold for the
   text-level approximation; 0.5 is the natural majority cutoff.
   Callers needing a different operating point should consult
   `score` directly and threshold themselves.
 - `chars_per_token` etc. — not applicable; this pkg does not
   impose its own cumulative budget. Caller-provided
   `max_thinking_tokens` is per-CoT.
 - `verifier_system_prompt` — Single-line persona
   conditioning ("You are a careful math verifier. Follow the
   requested output format exactly."). Paper Figure 21 is a
   user-side prompt; the system-prompt wording is impl choice.
   Held constant across all K parallel CoTs.

## Caveats {#caveats}

Two large caveats apply when using this pkg:

1. **The verifier model matters a lot**. The paper reports that
   smaller distilled models (e.g. R1-Distill-Qwen-1.5B) emit invalid
   judgment formats 51%+ of the time and effectively cannot serve
   as verifiers. The training-free path here only matches paper
   performance when callers route to a strong reasoning model — the
   paper baselines use R1-Distill-Qwen-14B or QwQ-32B-Preview.

2. **The canonical ThinkPRM solution score is out of scope**. Paper
   §E.1 produces a continuous solution score by force-decoding the
   string "Is the solution correct?" after the verification chain
   and using `P(yes) / (P(yes) + P(no))` from next-token logits.
   That requires direct logits access which `alc.llm` does not
   expose; this pkg aggregates via the `\boxed{correct|incorrect}`
   literals only. K-CoT parallel scaling is approximated by
   averaging per-CoT binary verdicts into a continuous score in
   [0, 1] and binarizing at `score_majority_threshold` (default
   0.5) for the `correct` field.

When every verification chain in a K-CoT run is invalid (no
`\boxed{...}` tokens parsed), `run` returns `invalid = true`,
`score = 0`, `correct = false`, `valid_chains = 0`. The `correct`
field is `false` because the solution cannot be defended as
correct without any valid verdict; callers should treat
`invalid = true` as the primary signal and not interpret
`correct = false` as a positive incorrect judgment.

## References {#references}

- Khalifa, M., Agarwal, R., Logeswaran, L., Kim, J., Peng, H.,
  Lee, M., Lee, H., Wang, L. (2025). "Process Reward Models That
  Think (ThinkPRM)". arXiv:2504.16828 §3 (method), §4 (experiments
  / K-CoT scaling), Appendix A.2 / Figure 21 (verifier prompt
  template), Appendix E.1 (aggregation).
  https://arxiv.org/abs/2504.16828
- Official code + models: https://github.com/mukhal/thinkprm

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.aggregation` | string | optional | Per-chain aggregation method (default: 'any_incorrect'; matches Figure 21 early-stop semantics. 'all_correct' requires every step verdict to be correct. The paper's canonical force-decode P(yes)/(P(yes)+P(no)) is out of scope — see Caveats.) |
| `ctx.early_stop_on_incorrect` | boolean | optional | Toggle the Figure 21 early-stop instruction (default: true — Khalifa 2025 Figure 21 literal). Ignored when prompt_template is supplied. |
| `ctx.max_thinking_tokens` | number | optional | Token cap per verifier chain (default: 4096; value from the official ThinkPRM repo init example — Khalifa 2025 §4 actually generates up to 8192 tokens, so 4096 is the more conservative implementation default, not a paper-prescribed cap) |
| `ctx.n_parallel_cots` | number | optional | Independent verification chains to sample (default: 1; paper §4 K-CoT averaging, experimental range 1 / 4 / 8) |
| `ctx.problem` | string | **required** | Math problem statement |
| `ctx.prompt_template` | string | optional | Override verifier prompt template (default: paper Figure 21 verbatim — Khalifa 2025 literal. Override voids paper's correctness reports.) |
| `ctx.score_majority_threshold` | number | optional | Threshold used to binarize the K-CoT averaged score into the `correct` field (default: 0.5;— paper does not specify, 0.5 is the natural majority cutoff) |
| `ctx.solution_steps` | array of string | **required** | Solution as an ordered list of step strings (one step per element) |
| `ctx.temperature` | number | optional | LLM sampling temperature (default: 0.1; conservative default from the official ThinkPRM repo README — Khalifa 2025 §4 / §E.2 report per-model sampling T=0.4 (Qwen-2.5-14B) / T=0.8 (Llama-3.2-3B-Instruct), so 0.1 is the implementation default, not a paper-prescribed value) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `chains` | array of shape { chain: string, correct: boolean, invalid: boolean, verdicts: array of string } | — | Per-chain records for inspection |
| `correct` | boolean | — | Solution-level binary: K-CoT averaged score >= score_majority_threshold (implementation choice — see Caveats for the paper's force-decode alternative). |
| `invalid` | boolean | — | True when every verification chain was invalid (no \boxed tokens parsed). Treat as the primary signal; correct=false alongside invalid=true is not a positive incorrect judgment. |
| `score` | number | — | Fraction of valid chains that judged the solution correct, in [0, 1] (paper §4 K-CoT averaging approximation; 0 when all chains invalid) |
| `valid_chains` | number | — | Number of chains whose verdicts parsed successfully |
