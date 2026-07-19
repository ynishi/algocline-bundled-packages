---
name: debate
version: 0.1.0
category: synthesis
result_shape: "shape { rationale: string, rounds_used: number, transcript: array of shape { argument: string, round: number, side: string }, verdict: string, winner: string }"
description: "Adversarial two-debater protocol with a terminal judge verdict"
source: debate/init.lua
generated: gen_docs (V0)
---

# debate(Debate) — adversarial two-debater protocol with a judge verdict

> A multi-agent debate strategy in which two debaters argue for opposing positions on a question, alternating for a fixed number of rounds, after which a single judge reads the full transcript and issues a verdict. The protocol operationalizes the "debate as truth amplification" hypothesis: adversarial dialogue between capable arguers surfaces more truthful signals than a single-model direct answer.

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
local debate = require("debate")
return debate.run({
    question = "Is the Riemann Hypothesis proven?",
    position_a = "Argue YES / for the affirmative",
    position_b = "Argue NO / for the negative",
})
```

## Algorithm {#algorithm}

1. **Debater A opens** (round 1) — one `alc.llm` pass produces A's opening
   argument for `position_a`.
2. **Debater B responds** (round 1) — one `alc.llm` pass produces B's
   argument for `position_b`, seeing A's opening in the transcript.
3. Steps 1-2 repeat for `rounds` (R) rounds. Each debater sees the full
   prior transcript when composing its next turn (sequential dependency).
4. **Judge verdict** — one `alc.llm` pass reads the full 2R-turn transcript
   and emits `WINNER:` / `VERDICT:` / `RATIONALE:` markers under the
   `judge_criteria` rubric.

Total `alc.llm` call budget: `2R + 1` (7 calls at R=3).

## API {#api}

- `ctx.question`       — string, required. Empty / whitespace-only → error.
- `ctx.position_a`     — string, optional. Debater A's assigned stance
  (default: affirmative placeholder).
- `ctx.position_b`     — string, optional. Debater B's assigned stance
  (default: negative placeholder).
- `ctx.rounds`         — number, optional. Number of full A/B round pairs
  (default: 3, from Khan et al. 2024 §3 canonical setting).
- `ctx.judge_criteria` — string, optional. Rubric injected verbatim into
  the judge prompt (default: truthfulness-focused rubric).

Result (`ctx.result`):
- `winner`      — string, "A" or "B" (falls back to "A" if unparsable).
- `verdict`     — string, one-line judge decision.
- `rationale`   — string, judge's justification for the verdict.
- `transcript`  — array of `{ round, side, argument }` records in turn
  order.
- `rounds_used` — number, how many rounds ran (= `rounds` on success).

## Comparison with related packages {#comparison-with-related-packages}

vs `panel`: `panel` runs distinct roles (advocate / critic / pragmatist)
each contributing one turn, then a moderator synthesizes. `debate` fixes
exactly two debaters on opposing positions for `R` alternating rounds and
asks the judge to pick a winner rather than synthesize — adversarial
rather than deliberative.

vs `dissent`: `dissent` surfaces minority-view critique against a single
draft. `debate` structures a symmetric pro/con exchange over multiple
rounds with a terminal verdict rather than a critique-of-draft asymmetry.

vs `triad`: `triad` runs three mutually critical perspectives without a
fixed winner. `debate` binds two arguers to opposing positions and forces
a WINNER decision from the judge.

## Caveats {#caveats}

**Provenance of hyperparameters**: `rounds = 3` is the canonical setting
reported in Khan et al. 2024 §3 (Table 2). The `judge_criteria` default is
an implementation choice echoing the paper's truthfulness framing — the
paper describes but does not fix a literal rubric string, so callers with
a domain-specific criterion should override this. Debater personas
(position_a / position_b) are placeholder strings; the paper's setup
assigns concrete opposing propositions per question, so callers should
inject question-specific stances for faithful reproduction.

**Extension points** (override at your own risk to paper effect):
- `ctx.rounds`         — Deviating from R=3 diverges from Khan 2024 §3
  canonical settings; paper reports diminishing returns past ~3 rounds.
- `ctx.position_a` / `ctx.position_b` — Placeholder strings; production
  use should inject stance-specific propositions per the paper's setup.
- `ctx.judge_criteria` — Implementation choice default; caller override
  is the primary customization channel (does not degrade paper effect
  when the rubric preserves truthfulness focus).

**Unparsable judge output**: if the judge's response omits a parseable
`WINNER:` marker, `winner` defaults to `"A"` and a warning is emitted via
`alc.log("warn", ...)`. Callers relying on the verdict for downstream
decisions should check `rationale` for plausibility.

## References {#references}

- Khan, A. et al. (2024). "Debating with More Persuasive LLMs Leads to
  More Truthful Answers." ICML 2024. arXiv:2402.06782.

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.judge_criteria` | string | optional | Rubric injected into the judge prompt (default: truthfulness-focused rubric — implementation choice echoing Khan 2024's "more truthful answers" framing, paper does not fix a literal rubric string) |
| `ctx.position_a` | string | optional | Debater A's assigned stance (default: affirmative placeholder; Khan 2024 §3 assigns concrete opposing propositions per question, so callers should inject question-specific stances) |
| `ctx.position_b` | string | optional | Debater B's assigned stance (default: negative placeholder; same provenance note as position_a) |
| `ctx.question` | string | **required** | Question under debate (required, non-empty) |
| `ctx.rounds` | number | optional | Number of full A/B round pairs (default: 3; Khan 2024 §3 Table 2 canonical setting) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `rationale` | string | — | Judge's justification for the verdict |
| `rounds_used` | number | — | Number of full A/B round pairs executed |
| `transcript` | array of shape { argument: string, round: number, side: string } | — | Ordered debate transcript, length = 2 * rounds_used |
| `verdict` | string | — | One-line judge decision |
| `winner` | string | — | Judge's verdict: "A" or "B" (falls back to "A" with alc.log warn when unparseable) |
