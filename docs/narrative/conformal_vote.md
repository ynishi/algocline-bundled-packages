---
name: conformal_vote
version: 0.1.0
category: validation
result_shape: conformal_decided
description: "Split conformal prediction gate for multi-agent deliberation with finite-sample coverage guarantee"
source: conformal_vote/init.lua
generated: gen_docs (V0)
---

# conformal_vote — split conformal prediction gate for multi-agent deliberation

> Linear opinion pool + split conformal prediction post-hoc decision layer. Emits a three-way decision (commit / escalate / anomaly) with a finite-sample coverage guarantee `Pr[Y ∈ C(X)] ≥ 1-α` (Theorem 2). Calibration and online rounds share aggregation weights so exchangeability is preserved.

## Contents

- [Algorithm](#algorithm)
- [Theoretical foundations](#theoretical-foundations)
- [Entry contract](#entry-contract)
- [Comparison with related packages](#comparison-with-related-packages)
- [Caveats](#caveats)
  - [Required ctx fields and runtime injection](#required-ctx-fields-and-runtime-injection)
  - [Knobs that affect the paper's coverage guarantee](#knobs-that-affect-the-paper-s-coverage-guarantee)
  - [Optional caller knobs (no paper-claim impact)](#optional-caller-knobs-no-paper-claim-impact)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Algorithm {#algorithm}

Given N agents that each emit a verbalized probability distribution
π_i(y|x) over a fixed option set, the pkg performs:

```math
P_social(y|x) = Σ_i w_i · π_i(y|x)        (linear opinion pool)
s_nc(x, y)    = 1 - P_social(y|x)         (nonconformity score)
q̂            = sorted[⌈(n+1)(1-α)⌉]       (finite-sample quantile, §4.3)
C(x)          = { y : P_social(y|x) ≥ 1 - q̂ }   (prediction set)
```

Three-way decision (Proposition 3):

```
|C|=1 ∧ p₁≥τ ∧ p₂<τ → commit
|C|≥2 ∧ p₂≥τ        → escalate
|C|=0 ∨ p₁<τ        → anomaly
```

## Theoretical foundations {#theoretical-foundations}

Theorem 2 guarantees `Pr[Y ∈ C(X)] ≥ 1-α` in finite samples whenever
calibration and online rounds share the same aggregation weights and
the data is exchangeable. The `calibrate` entry therefore *pins* the
weights it used (defaulting to uniform `1/N`) into its return value so
`M.run` can replay them, never letting online aggregation drift from
the calibrated weights.

## Entry contract {#entry-contract}

See `M.spec` below for the formal machine-readable contract:

- `calibrate`   — pure, direct-args. returns `{ q_hat, tau, alpha, n, weights }`
- `aggregate`   — pure, direct-args. returns `{ [label] = p_social }`
- `predict_set` — pure, direct-args. returns `{ labels, top1, top1_prob, top2, top2_prob }`
- `decide`      — pure, direct-args. returns `{ action, selected }`
- `run`         — Strategy, ctx-threading. queries N agents via `alc.llm`

## Comparison with related packages {#comparison-with-related-packages}

Category: `validation` (alongside `sprt`, `eval_guard`, `inverse_u`).
The paper's informal "Governance" label describes the role; the
machine-readable category string follows the existing sibling pkgs.

## Caveats {#caveats}

### Required ctx fields and runtime injection {#required-ctx-fields-and-runtime-injection}

`ctx.calibration_samples` must be supplied as an array of
`{agent_probs, true_label}` drawn i.i.d. from the same distribution as
the online test (paper Theorem 2 exchangeability requirement). Without
this, `run()` cannot produce a coverage-bounded prediction set.

`ctx.agents` must be supplied as an array of agent specs (per-agent
`system` / `model` / `temperature` overrides); `run()` issues exactly
`#agents` LLM calls per invocation.

The strategy is Pure Lua and depends on the host providing `alc.llm`
at execution time (runtime injection).

### Knobs that affect the paper's coverage guarantee {#knobs-that-affect-the-paper-s-coverage-guarantee}

`alpha` (default 0.05; paper §Table 3 primary setting) is the
miscoverage rate. `Pr[Y ∈ C(X)] ≥ 1 - alpha` (Theorem 2) is the
literal paper claim only when the caller does not override `alpha`
post-calibration. Re-running `calibrate()` with a new `alpha` is
paper-compatible; mutating `alpha` at `run()` time is not.

`weights` (per-agent aggregation weights) is pinned by `calibrate()`
so online runs preserve exchangeability. Overriding `weights` at
`run()` time invalidates the finite-sample quantile guarantee.

### Optional caller knobs (no paper-claim impact) {#optional-caller-knobs-no-paper-claim-impact}

`gen_tokens` (default 400) follows the sibling-pkg convention from
`sc` rather than the paper's Appendix C `max_tokens=4096` because
typical verbalized-probability replies are short and the sibling
default keeps latency manageable; raising it is safe for richer
responses.

`max_retries` (default 0) follows the paper's no-retry parse-fallback
policy. Raising it is an implementation choice; the paper does not
specify retry behaviour.

`agents[i].system` / `agents[i].model` / `agents[i].temperature`
override the underlying `alc.llm` call per agent. None of these
affect the calibration/coverage guarantee directly but they change
the distributions used at inference time.

`auto_card` (default false), `card_pkg` (default
`conformal_vote_<task_hash>`), and `scenario_name` control optional
Card emission on completion. These are implementation-side
observability knobs with no paper-side semantics.

## References {#references}

Wang, Xie, Wang, Gao, Yang, Li, Qiu, Han, Qiu, Huang, Zhu, Woo (2026).
"From Debate to Decision: Conformal Social Choice for Safe Multi-Agent
Deliberation". arXiv:2604.07667.

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.agents` | any | **required** | Array of agent specs (prompt string or {prompt,system?,model?,temperature?,max_tokens?} table) |
| `ctx.auto_card` | boolean | optional | Emit a Card on completion (default: false) |
| `ctx.calibration` | shape { alpha: number, n: number, q_hat: number, tau: number, weights: table } | **required** |  |
| `ctx.card_pkg` | string | optional | Card pkg.name override (default: 'conformal_vote_<task_hash>') |
| `ctx.gen_tokens` | number | optional | Max tokens for LLM generation (default: 400) |
| `ctx.options` | array of string | **required** | Candidate label set |
| `ctx.scenario_name` | string | optional | Explicit scenario name for the emitted Card |
| `ctx.task` | string | **required** | Task text presented to each agent |

## Result {#result}

Returns `conformal_decided` shape:

| key | type | optional | description |
|---|---|---|---|
| `action` | one_of("commit", "escalate", "anomaly") | — | Three-way decision per Proposition 3 |
| `card_id` | string | optional | Emitted Card id (only when auto_card=true) |
| `coverage_level` | number | — | 1 - alpha (finite-sample guarantee) |
| `p_social` | map of string to number | — | Linear opinion pool output { [label] = prob } |
| `prediction_set` | array of string | — | Labels y with P_social(y\|x) >= tau |
| `q_hat` | number | — | Calibration quantile of nonconformity scores |
| `selected` | string | optional | Committed label (nil when action != 'commit') |
| `tau` | number | — | 1 - q_hat (prediction-set threshold) |
