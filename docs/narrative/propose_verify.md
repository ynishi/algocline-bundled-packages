---
name: propose_verify
version: 0.1.0
category: validation
description: "2-call Propose→Verify Strategy: propose a candidate answer then verify it with a scored accept/reject verdict"
source: propose_verify/init.lua
generated: gen_docs (V0)
---

# propose_verify — 2-call Propose → Verify Strategy

> Generates a candidate answer (propose call), then runs an independent LLM verifier that returns an accept/reject verdict with a confidence score (verify call). Total LLM calls: exactly 2.

## Contents

- [Usage](#usage)
- [Helpers](#helpers)
- [Narrative](#narrative)
- [Entry contract](#entry-contract)
- [Caveats](#caveats)
  - [Required ctx fields](#required-ctx-fields)
  - [Optional ctx fields](#optional-ctx-fields)
  - [Why no `score_threshold` default](#why-no-score-threshold-default)
  - [Why no `swarm_frame` dependency](#why-no-swarm-frame-dependency)
- [References](#references)

## Usage {#usage}

```lua
local pv = require("propose_verify")
return pv.run(ctx)
```

## Helpers {#helpers}

```lua
-- Build the propose prompt only (pure, no LLM):
local prompt = pv.build_propose_prompt(task, proposer_hint)

-- Build the verify prompt only (pure, no LLM):
local vp = pv.build_verify_prompt(task, candidate, verifier_hint)

-- Parse verifier text into structured verdict (pure, no LLM):
local verdict = pv.parse_verify(text)
-- verdict = { accept: bool, score: number 0..1, rationale: string }
```

## Narrative {#narrative}

propose_verify implements the two-role Propose-then-Verify primitive
that underpins large-scale LLM self-improvement research. The proposer
generates a candidate answer at creative temperature; the verifier
scores it with deterministic temperature and emits an accept/reject
verdict with a numeric confidence score. The score threshold is
caller-required (no default) — the caller decides what "good enough"
means for their domain. The verdict string is compatible with
swarm_frame parse_verdict conventions for aggregation in multi-agent
pipelines, but swarm_frame is not a dependency.

## Entry contract {#entry-contract}

- `build_propose_prompt(task, proposer_hint?)` — pure, returns the
  proposer prompt string. No LLM call.
- `build_verify_prompt(task, candidate, verifier_hint?)` — pure,
  returns the verifier prompt string. No LLM call.
- `parse_verify(text)` — pure, parses verifier LLM output into
  `{ accept, score, rationale }`. No LLM call.
- `run(ctx)` — Strategy entry, ctx-threading. Issues exactly 2
  `alc.llm` calls (propose → verify) and returns the structured
  result.

## Caveats {#caveats}

### Required ctx fields {#required-ctx-fields}

- `task` (string) — the question or task to solve. The implementation
  falls back through `ctx.task → ctx.text → ctx.idea → ctx.question`
  so callers wired to any of the common field names work without
  changes.
- `score_threshold` (number, 0..1) — the minimum verifier score for
  the verdict to be "accepted". No default is provided because the
  acceptance bar is domain-specific: a math problem might need 0.95
  while a creative-writing rewrite might want 0.5. Caller must inject
  this value.

### Optional ctx fields {#optional-ctx-fields}

- `proposer_hint` (string) — extra instruction appended to the
  proposer prompt (e.g. "answer in one sentence"). Injects domain
  guidance without replacing the base template.
- `verifier_hint` (string) — extra instruction appended to the
  verifier prompt (e.g. "focus on factual accuracy"). Same shape as
  proposer_hint for the verify call.
- `propose_temperature` (number, default 0.7) — temperature for the
  propose call. The default 0.7 is the industry-standard
  creative-generation default cited by OpenAI / Anthropic
  documentation; overriding away from 0.7 removes that creative-
  diversity baseline.
- `verify_temperature` (number, default 0.0) — temperature for the
  verify call. The default 0.0 is the industry-standard deterministic
  judgment baseline used by scorers and classifiers; overriding above
  zero makes the verdict non-deterministic across re-runs.

### Why no `score_threshold` default {#why-no-score-threshold-default}

An accept/reject bar is intrinsically domain-specific (mathematical
correctness vs creative quality vs factual recall each warrant
different cutoffs). Picking a single library-wide default would
silently misclassify cases for most callers; requiring it forces the
caller to make a conscious choice.

### Why no `swarm_frame` dependency {#why-no-swarm-frame-dependency}

The verdict string `"DONE path=accepted | rejected"` is compatible
with `swarm_frame.parse_verdict` so callers that aggregate with
swarm_frame can consume it directly, but the pkg itself stays
single-shot to keep the dependency surface minimal.

## References {#references}

- Cobbe et al. (2021). "Training Verifiers to Solve Math Word
  Problems", arXiv:2110.14168 §3 — verifier prompt pattern (industry-
  standard verifier-prompt formulation).
- Zhou et al. (2023). "Language Agent Tree Search Unifies Reasoning,
  Acting, and Planning in Language Models" (LATS), arXiv:2309.08987
  §3.2 — node-scoring rationale (industry adoption of independent
  verifier scoring at planning nodes).
- ReAct-style propose/verify caller patterns — widely-cited tool-use
  convention that pairs a candidate generator with an independent
  verifier step.
