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
- [ctx fields](#ctx-fields)
- [Defaults](#defaults)
- [EXTENSION POINTS](#extension-points)
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

## ctx fields {#ctx-fields}

- `task` (string, required) — the question or task to solve.
  Fallback chain: ctx.task → ctx.text → ctx.idea → ctx.question.
- `score_threshold` (number 0..1, REQUIRED — no default) — minimum
  verifier score for the verdict to be "accepted". Caller must inject
  this value. (X — domain-specific; no universal default.)
- `proposer_hint` (string, optional) — additional instruction for
  the proposer (e.g. "answer in one sentence").
- `verifier_hint` (string, optional) — additional instruction for
  the verifier (e.g. "focus on factual accuracy").

## Defaults {#defaults}

- propose_temperature = 0.7  (I — industry standard for creative
  generation; OpenAI/Anthropic recommended range for answer drafting)
- verify_temperature  = 0.0  (I — industry standard for deterministic
  judgment; zero-temperature is the de-facto standard for scorers /
  classifiers)
- score_threshold: NO DEFAULT — INJECT or pass as caller arg. (X)

## EXTENSION POINTS {#extension-points}

REQUIRED:
  ctx.score_threshold — caller MUST supply; no default (X)

(I)-override OPTION:
  propose_temperature — override propose call temperature.
    Overriding away from 0.7 removes industry-standard creative
    diversity guarantee.
  verify_temperature — override verify call temperature.
    Overriding away from 0.0 makes the verdict non-deterministic.

(I) OPTION:
  proposer_hint / verifier_hint — inject domain guidance into each
    prompt without replacing the base template.

## References {#references}

- Cobbe et al. (2021), "Training Verifiers to Solve Math Word
  Problems", arXiv:2110.14168, §3 — verifier prompt pattern (I)
- Zhou et al. (2023), "Language Agent Tree Search Unifies Reasoning,
  Acting, and Planning in Language Models" (LATS), arXiv:2309.08987,
  §3.2 — node scoring rationale (I)
- ReAct-style propose/verify caller patterns (I)
