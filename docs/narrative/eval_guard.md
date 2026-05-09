---
name: eval_guard
version: 0.1.0
category: validation
description: "Multi-agent evaluation safety gates (self-critique / baseline / contamination)."
source: eval_guard/init.lua
generated: gen_docs (V0)
---

# eval_guard(EvalGuard) — multi-agent evaluation safety gates (N2/N3/N4)

> Pure-computation gate checks for evaluation safety in multi-agent systems. Each gate returns `(passed, reason)` and can be used independently or combined via `check_all`. N1 (inverse-U scaling) and N5 (Pareto dominance) live in `inverse_u` and `cost_pareto`; this package handles structural checks.

## Contents

- [Usage](#usage)
- [Theoretical foundations](#theoretical-foundations)
- [References](#references)

## Usage {#usage}

```lua
local eg = require("eval_guard")
local ok, reason = eg.self_critique({has_external_grader = false})
local report = eg.check_all({
  has_external_grader = false,
  has_baseline = true,
  metric_type = "absolute",
})
```

## Theoretical foundations {#theoretical-foundations}

The bundled gates encode three documented multi-agent evaluation
failure modes:

- N2 `self_critique` — intrinsic self-correction degrades accuracy
  without an external grader (Huang et al., ICLR 2024). The gate
  enforces that self-correction always has a ground-truth signal
  (unit test, symbolic check, cross-model verification).
- N3 `baseline` — multi-agent must run with a same-budget SC/CoT
  baseline for a fair comparison; without it, complex multi-agent
  setups often lose to single-agent + Self-Consistency.
- N4 `contamination` — absolute accuracy on standard benchmarks is
  unreliable due to data contamination. The gate requires a hold-out
  delta plus cost plus Pareto as the evaluation criterion set.

`check_all` runs all three gates and produces a combined report
suitable for automated pipeline enforcement. Composable with
`scoring_rule` (calibration measurement after gates pass) and
`cost_pareto` (N5 Pareto dominance).

## References {#references}

- Huang, J. et al. (2024). "Large Language Models Cannot Self-Correct
  Reasoning Yet". ICLR 2024.
- Wang, Q. et al. (2024). ACL 2024 Findings.
- Kapoor, S. et al. (2024). "AI Agents That Matter".
  https://arxiv.org/abs/2407.01502
- Zhu, K. et al. (2024). EMNLP 2024 (benchmark decontamination).
