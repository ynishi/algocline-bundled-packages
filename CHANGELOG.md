# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.29.0] - 2026-05-27

### Added

- **124th pkg `recipe_trace`** — generic LLM call tracer for recipe
  execution. Wraps `alc.llm` to collect per-call prompt/response/timing
  without modifying the recipe itself. Entries: `run` (traced execution),
  `extract` (flat summary), `card_row` (Card samples row builder with
  prompt truncation), `civic_merge` (civic primitive state merger for
  slot_table / scalar_pool / lineage / ledger). Examples for all 5
  recipe_* packages. 17/17 spec PASS, E2E PASS (7/7 graders, 16 traced
  LLM calls via recipe_quick_vote, agent-block + claude-haiku-4-5).

## [0.28.0] - 2026-05-27

### Added

- **123rd pkg `recipe_evolve_reason`** — multi-generation evolutionary LLM
  reasoning recipe. Maintains a population of reasoning paths across
  generations using civic primitives (slot_table / scalar_pool /
  transition_rules / lineage / knowledge_channel). Peer evaluation with
  A/B position-bias mitigation, deterministic elite selection, LLM-driven
  mutation + knowledge inheritance. 19/19 spec PASS, E2E PASS (7/7 graders,
  agent-block + claude-haiku-4-5).

- **122nd pkg `civic`** — civic-frame primitives for swarm simulations
  (ABM-pattern single pkg + 7 component modules). Components:
  `broadcast_bus`, `transition_rules`, `slot_table`, `knowledge_channel`,
  `lineage`, `ledger`, `scalar_pool`. Pure in-memory, no LLM dependency,
  no cross-pkg require. 166/166 spec PASS.

## [0.27.0] - 2026-05-23

### Added

- **121st pkg `propose_verify`** — universal 2-call Propose→Verify
  primitive (Cobbe 2021 §3 verifier-as-judge framing + LATS §3.2
  generate-then-evaluate framing). Issues exactly 2 `alc.llm` calls
  (propose → verify) and returns a binary `accepted` verdict with a
  caller-injected `score_threshold`. Exposes 4 pure helpers
  (`build_propose_prompt` / `build_verify_prompt` / `parse_verify` /
  `run`) all LLM-independent and unit-testable. 17/17 spec PASS.

### Fixed

- **paper pkg public-doc layer-separation sweep** — six paper-explicit
  pkgs (`reconcile` / `moa` / `dmad` / `hegelian` / `conformal_vote` /
  `propose_verify` per-pkg post-ship fix) carried local-rule lint
  labels (`(L)` / `(I)` / `(X)` short markers + `## EXTENSION POINTS`
  ASCII headers) in their public docstrings and `:describe("...")`
  text. These labels are internal AI provenance trail defined in this
  repo's `.claude/CLAUDE.md` §3, NOT part of the OSS user contract.
  Public docs now follow the official format defined in
  `algocline/docs/pkg-author-conventions.md` (§4.3 two-tier rule +
  §3.2 `## Caveats` H2 section with subheadings `### Required ctx
  fields` / `### Knobs that affect the paper's effect guarantee` /
  `### Optional caller knobs (implementation choices)` / `### Stability
  tier`). Provenance is written in prose ("per Chen §3 ...",
  "implementation choice — paper does not specify, ...") rather than
  abbreviated label markers. In-function `--` comment lines (outside
  the `---` docstring) remain as the internal AI provenance trail per
  CLAUDE.md §3 last paragraph. 202/202 spec PASS across the 4 paper
  pkgs swept in this release; cumulative 219/219 with the prior-commit
  `propose_verify` / `conformal_vote` sweep.
- **D1/D2/D3 audit Phase 1** (`dci` / `slm_mux` / `conformal_vote`) —
  high-priority sweep from issue #1778832121 for paper-citation
  precision, default-value provenance, and §B.x reference accuracy.

### Verified

- `alc_hub_dist` — 121 generated / 0 failed / lint 0 errors / 0
  warnings (one additional pkg vs v0.26.0 from `propose_verify`
  install).
- All affected pkg specs pass via `mcp__algocline__alc_pkg_test`:
  `propose_verify` 17/17, `reconcile` 57/57, `moa` 36/36, `dmad`
  52/52, `hegelian` 57/57, `conformal_vote` 34/34, `dci` / `slm_mux`
  unchanged from v0.26.0.

## [0.26.0] - 2026-05-22

### Added

- **Per-package spec coverage at 100%** (Phase B). 24 previously
  cross-test-only packages now have their own `<pkg>/spec/<pkg>_spec.lua`
  with `lust`-based suites (meta / spec / error path + run-mode tests):
  `contrastive` / `meta_prompt` / `step_back` / `reflect` / `analogical` /
  `ab_mcts` / `cod` / `blind_spot` / `bisect` / `cove` / `tot` /
  `least_to_most` / `verify_first` / `cumulative` / `diverse` /
  `model_first` / `intent_discovery` / `intent_belief` / `php` /
  `sketch` / `prism` / `ucb` / `panel` / `ambig` / `deliberate` /
  `robust_qa` / `pre_mortem`. After this change, every bundled pkg is
  discoverable via `alc_pkg_test pkg=<name>` (algocline MCP).
- **Cross-cutting test decomposition** (Phase C). Seven cross-package
  `tests/test_*.lua` files (3,361 lines total) were decomposed into
  per-pkg specs across 30 packages:
  - `test_foundations_phase2` → `pbft` / `aco`
  - `test_governance` → `dissent` / `topo_route`
    (`lineage` / `anti_cascade` extracted in Phase B)
  - `test_ranking_packages` → `ab_select` / `listwise_rank` /
    `pairwise_rank` / `setwise_rank`
  - `test_foundations` → `bft` / `condorcet` / `ensemble_div` /
    `inverse_u` / `cost_pareto` / `eval_guard`
  - `test_new_packages` → `s2a` / `plan_solve` / `rstar` / `faithful` /
    `bot` (`moa` / `hegelian` extracted in Phase B)
  - `test_exploration` → `qdaif` / `falsify` / `prompt_breed` /
    `coevolve` / `mcts` (+ `optimize.search:breed` strategy appended
    to existing `optimize_spec.lua`)
  - `test_tier1_2` → `usc` / `step_verify` / `compute_alloc` /
    `gumbel_search` / `mbr_select` / `reflexion`
- **`tools/test_audit.lua` + `just test-audit` recipes** (Phase A). A
  coverage matrix tool that joins `<pkg>/spec/` presence with
  `tests/test_*.lua` `require("<pkg>")` mentions, surfacing per-pkg test
  coverage with priority sort (paper-explicit weighting). Used to drive
  Phase B/C planning.

### Removed

- Seven cross-package test files (`tests/test_foundations_phase2.lua` /
  `test_governance.lua` / `test_ranking_packages.lua` /
  `test_foundations.lua` / `test_new_packages.lua` / `test_exploration.lua` /
  `test_tier1_2.lua`). All content migrated to per-pkg specs. Remaining
  `tests/test_*.lua` (entity_schemas / spec_resolver / shapes_conformance)
  and `tests/flow/test_integ_*.lua` are cross-cutting by design and stay
  in `tests/`.

### Verified

- `alc_hub_dist` — 120 generated / 0 failed / lint 0 errors / 0 warnings.
- All new specs pass via `just alc-pkg-test-file <path>` smoke and
  `mcp__algocline__alc_pkg_test pkg=<name>` discovery.

## [0.25.0] - 2026-05-18

### Added

- **`<pkg>/spec/<pkg>_spec.lua` per-package test layout**. Each bundled
  package that previously had a `tests/test_<pkg>.lua` file now hosts
  its test under its own `spec/` directory. This unlocks
  `alc_pkg_test pkg=<name>` discovery (algocline MCP) in addition to the
  existing `mlua-probe-mcp test_launch code_file=<path>` runner — both
  paths execute the same `lust`-based suites. Cross-package test files
  (foundations_phase2, ranking_packages, entity_schemas, etc., 10 files)
  remain in `tests/` since they don't map to a single package.
- **`M.meta.alc_shapes_compat = "^0.25"` declaration on every bundled
  package** (plus a self-compat marker on `alc_shapes` itself). After
  this change, `alc_hub_dist` runs warning-free against algocline core
  ≥ 0.26 (was 117 "alc_shapes_compat not declared" warnings, now 0).
  `"^0.25"` = `>=0.25.0, <0.26.0`; the next alc_shapes major bump will
  surface as a hard dist error, prompting an explicit re-pin per pkg.

### Verified

- `alc_hub_dist` — 120 generated / 0 failed / lint 0 errors / 0 warnings.
- `alc_pkg_doctor` — `spec_missing: []` for all 105 bundled packages.
- `alc_pkg_test pkg=<name>` — sample smoke (sc 11/11, dmad 52/52,
  abm 79/79, moa 36/36, reconcile 57/57, card_analysis 6/6).

## [0.24.0] - 2026-05-16

### Fixed

- **`dmad.DEFAULT_DEBATE_AGENT_BLOCK` — per-agent block triple-backtick
  wrapper restored**: v0.2.0 ship value was
  `"\n\n One agent solution: \n\n %s \n\n"`, missing the triple-backtick
  fence that Du repo `gsm/gen_gsm.py::construct_message` uses to wrap
  each other-agent response (`"\n\n One agent solution: \`\`\`{}\`\`\`"`).
  The docstring claimed the value was lifted from `gen_gsm.py` while the
  literal had been altered — a §7 violation (claiming (L) status while
  the value diverges from the cited source). The Lua string literal is
  now byte-identical to the Python source modulo the `{}` ↔ `%s`
  substitution. Runtime impact was minor (LLMs still parsed prior-round
  answers either way) but the (L) provenance assertion was wrong.

### Changed

- **`reconcile.confidence_to_weight` — override path actually wired in**.
  v0.1.0 docstring listed `ctx.confidence_buckets` as an (X) extension
  point and exported `M.CONFIDENCE_BUCKETS` as the §B.5 reference table,
  but the implementation used a hardcoded if/elif chain that consulted
  neither. The function now iterates `M.CONFIDENCE_BUCKETS`
  (or `args.buckets` / `ctx.confidence_buckets` when provided)
  top-to-bottom and returns the weight of the first matching bucket.
  `M.CONFIDENCE_BUCKETS` shape changed (still §B.5-equivalent): each
  entry is `{ lo, lo_op?, weight }` with `lo_op ∈ {"ge","gt"}`; the
  list is evaluated top-to-bottom with first-match-wins semantics.
  `run` forwards `ctx.confidence_buckets` per-call. `M.spec.entries.
  confidence_to_weight` and `M.spec.entries.run.input` carry the new
  optional `buckets` / `confidence_buckets` fields. Default behaviour
  (no override) is bit-for-bit equivalent to the previous v0.1.0
  hardcoded chain on every confidence value. Test coverage adds 9
  cases: SoT-via-table consumption, override no-mutation, top-down
  first-match, malformed-bucket rejection, unknown-lo_op rejection,
  empty override rejection, missing-catch-all rejection, lo_op="gt"
  strict semantics, plus an `m.run` end-to-end test that
  `ctx.confidence_buckets` propagates into per-agent weights.

### Vocabulary

Removed `paper-faithful` / `non-paper-faithful` / `verbatim` / `paper
not fixed` as bare provenance labels from `dmad/init.lua`,
`moa/init.lua`, `reconcile/init.lua`, and the `[Unreleased]` CHANGELOG
entries below, per `CLAUDE.md` "論文実装 pkg の実装規律" §8 (banned
default vocabulary). Replacement phrasing names the structural
property concretely — e.g. `multi-model PATH (Wang §3 main config)` /
`single-model rotation PATH (outside Wang §3's multi-model setup)` /
`Lua transcription of Table 1 with `%s` substituting `{}`` — so that
provenance and divergence are auditable from the docstring alone.
Behaviour is unchanged.

### Added

- **`hegelian` package** (new, category=`reasoning`, 119th package): Self-
  reflecting LLM via Hegelian dialectical self-reflection. Primary citation:
  Abdali et al. (Microsoft Research), "Self-reflecting Large Language
  Models: A Hegelian Dialectical Approach" (arXiv:2501.14917, 2025).
  Implements Algorithm 1 §3 — bootstrap thesis T_0 at temperature τ_0,
  then iterate `for i = 0..N-1: A_i ← M(T_i, τ_a); τ(i) = τ_0·exp(-θ·i);
  S_i ← M(T_i, A_i, τ(i)); T_{i+1} ← S_i`. Three LLM stages per iteration:
  thesis bootstrap (single, τ_0 = 0.7), antithesis (per-iter, τ_a = 0.5),
  synthesis (per-iter, annealed τ(i)). Defaults follow Abdali Table 1:
  τ_0 = 0.7 (L), τ_a = 0.5 (L), N = 5 (L), θ = 0.3 (X within paper-stated
  (L) range [0.1, 0.5]). 5 spec entries: pure helpers `temperature_at` /
  `build_thesis_prompt` / `build_antithesis_prompt` /
  `build_synthesis_prompt` (LLM-independent, unit-testable) +
  `run` (Strategy, ctx-threading orchestration, 1 + 2N LLM calls). Each
  pure entry uses `args` direct-args mode with shape validation via
  `S.instrument`. EXTENSION POINTS expose (L)-override knobs (tau_0 /
  tau_a / N) and (X) infrastructure knobs (gen_tokens / prompt templates
  / system prompts) with stability tier annotation. Replaces the
  "rebuttal" stage (not present in Du 2023) previously mixed into `dmad/`
  v0.1.0 (commit `54faaa5`, 2026-03-15) — the Hegelian methodology had
  been implemented in dmad/ alongside the Du 2023 citation despite Du's
  paper not describing a dialectic. dmad/ rewrite to pure Du 2023
  paper-explicit Multi-Agent Debate is scoped to a separate Issue. Test
  coverage: `tests/test_hegelian.lua` (57/57 PASS) covers meta / spec /
  defaults / theta range enforcement / temperature_at paper formula /
  prompt builders (default + override + validation) / run end-to-end
  with mock alc (LLM call count, iteration log shape, temperature
  schedule, thesis-carry-forward invariant, error paths).
  `tests/test_new_packages.lua` adds minimal meta section (2 tests, 34
  total PASS).

### Added

- **`reconcile` package** (new, category=`aggregation`, 120th package).
  Round-table consensus with confidence-weighted voting (Chen, Saha &
  Bansal 2023, arXiv:2309.13007 "ReConcile: Round-Table Conference
  Improves Reasoning via Consensus among Diverse LLMs"). Implements
  §3 / Algorithm 1 in 3 phases: Phase 1 (init — each agent emits answer
  + explanation + confidence p ∈ [0,1]); Phase 2 (discussion — up to R
  rounds, each agent sees others' triples and may revise); Phase 3 (vote
  — confidence-weighted argmax per §4: `â = arg max_a Σ_i f(p_i)·𝟙(a_i=a)`).
  Consensus check after each round triggers early stop. Defaults follow
  Chen §3: N = 3 agents (L), R = 3 max rounds (L), convincing_count = 4
  (L §4 footnote "4 in our experiments"). The confidence calibration
  f(·) uses the §B.5 5-bucket scale, a Lua transcription of repo
  `dinobby/ReConcile/utils.py::trans_confidence` (same boundary
  values, same weights):
  `p ≤ 0.6 → 0.1`, `0.6 < p < 0.8 → 0.3`, `0.8 ≤ p < 0.9 → 0.5`,
  `0.9 ≤ p < 1.0 → 0.8`, `p = 1.0 → 1.0`. Spec entries (5, all
  S.instrument-decorated): pure helpers `confidence_to_weight` /
  `compute_weighted_argmax` / `check_consensus` / `build_discussion_prompt`
  + `run` (Strategy). All pure entries use `args` direct-args mode.
  EXTENSION POINTS: REQUIRED `ctx.task` + one of `ctx.agents`
  (diverse-LLM PATH; Chen §3 main config — array of
  `{model, system?}` specs) OR `ctx.personas` (single-model rotation
  PATH; outside Chen §3's diverse-LLM setup). (L)-override:
  `max_rounds` / `convincing_count`. (X) infrastructure: `gen_tokens` /
  `temperature` / template overrides / `parse_fn` / `confidence_buckets`.
  Total LLM calls range from N (init consensus) to N·(R+1) (no
  consensus, full R rounds). Distinct from `dmad` (no confidence
  weighting, no early-stop) and `moa` (deterministic vote, no aggregator
  LLM). Test coverage: `tests/test_reconcile.lua` (48/48 PASS) covers
  meta / spec / `_defaults` / 5-bucket boundary cases / weighted argmax
  + tie-break + tally / consensus predicate / discussion prompt
  (convincing_count cap + override + reject) / `_internal` helpers
  (normalize / coerce / parse_agent_response / resolve_agents / format
  others block) / run end-to-end (init consensus path / discussion
  rounds path / no-consensus full-R weighted-vote fallback / history
  shape / weight propagation / model id propagation / error paths).

### Changed

- **`dmad` package — paper-explicit rewrite (v0.1.0 → v0.2.0, breaking
  result shape)**. v0.1.0 cited Du 2023 (arXiv:2305.14325) but implemented
  a 4-step Hegelian dialectic (thesis / antithesis / rebuttal / synthesis)
  that has no source in Du's paper. The Hegelian methodology was extracted
  to a separate `hegelian/` pkg (Abdali 2025 paper-explicit, see Added
  above) in commit `e030095` + doc correction `5838927`. dmad v0.2.0 is
  rewritten as pure Du 2023 Multi-Agent Debate:
  - Algorithm: N parallel agents propose initial answers (round 0), then
    for r = 1..R each agent revises after seeing other N-1 agents'
    previous-round responses. Final aggregation by majority vote on
    extracted answers. Total LLM calls = N·(R+1).
  - Defaults (L from Du repo `gsm/gen_gsm.py`): N = 3 agents, R = 2
    rounds. Default 9 LLM calls per run.
  - Prompt templates (L) — Lua transcription of `gen_gsm.py` string
    literals (Python `{}` → Lua `%s`, no other transformation):
    `DEFAULT_INIT_TEMPLATE` ("Can you solve the following math problem?
    %s … \\boxed{answer} …"), `DEFAULT_DEBATE_PREFIX` /
    `DEFAULT_DEBATE_AGENT_BLOCK` (per-agent block keeps the triple-
    backtick wrapper `\`\`\`{response}\`\`\`` from
    `construct_message`) / `DEFAULT_DEBATE_SUFFIX`.
  - Spec entries (5): 4 pure helpers (`build_init_prompt` /
    `build_debate_prompt` / `extract_boxed` / `aggregate_majority`) +
    `run` Strategy. Pure helpers use `args` direct-args mode and are
    LLM-independent. `aggregate_majority` matches `eval_gsm.py:most_frequent`
    semantics (first-wins tie-break). `extract_boxed` reads `\boxed{...}`
    with last-match preference and graceful trim fallback.
  - EXTENSION POINTS: REQUIRED `ctx.task`; (L)-override `n_agents` /
    `n_rounds` (overriding invalidates paper effect guarantee); (X)
    infrastructure `gen_tokens` / `temperature` / template overrides /
    system_prompt / `extract_fn` (pluggable extractor for non-math tasks).
  - Result shape (breaking from v0.1.0): `{answer, n_agents, n_rounds,
    responses[r+1][i], last_answers[i], tally, total_llm_calls,
    debate_log}`. v0.1.0 fields `thesis` / `antithesis` / `synthesis` /
    `rebuttal` are removed — callers that depend on Hegelian semantics
    must switch to `require("hegelian")` (Abdali 2025 paper-explicit).
  - Test coverage: `tests/test_dmad.lua` (50/50 PASS) covers meta / spec /
    defaults / template literal-equality assertions / pure helpers (default +
    override + validation) / `aggregate_majority` (strict majority +
    first-wins tie-break + tally + reject) / `extract_boxed` (last-match
    + trim + fallback) / `run` end-to-end with mock alc (N·(R+1) call
    count, debate_log shape, responses indexing, other-agents exclusion
    of self, temperature propagation, error paths) / Hegelian path
    removal (no `thesis` / `antithesis` / `synthesis` fields, no
    `dialectic_mode` branching).
  - Resolves the v0.1.0 internal inconsistency where the package cited
    Du 2023 while implementing a different paper's methodology.

- **`moa` package — paper-explicit rewrite (v0.1.0 → v0.2.0, breaking
  result shape + category change `selection` → `aggregation`)**. v0.1.0
  cited Wang 2024 but implemented a hardcoded-5-PERSONA single-model
  loop with no Aggregate-and-Synthesize prompt and no clear mapping to
  the paper's §2.2 equation. v0.2.0 is paper-explicit:
  - Algorithm: For each layer i = 1..L, n proposers produce responses
    `A_{i,1..n}(x_i)`, then the aggregator applies the Aggregate-and-
    Synthesize prompt: `y_i = ⊕[A_{i,j}(x_i)] + x_1`, `x_{i+1} = y_i`.
    The final layer's aggregator output is the answer.
    Total LLM calls = L · (n + 1).
  - Defaults (L from Wang §3 main exp): L = 3 layers, n = 6 proposers.
    MoA-Lite (L = 2) supported via `n_layers` override. (X) infrastructure
    defaults: temperature = 0.7 (matches paper's single-proposer ablation
    value; main exp not explicitly stated), proposer_tokens = 512,
    aggregator_tokens = 2048.
  - `AS_PROMPT_TEMPLATE` (L) — Lua string literal identical to Wang 2024
    Table 1 (punctuation / capitalization / line breaks all match; only
    Python `{}` rendered as Lua `%s`):
    `"You have been provided with a set of responses from various
    open-source models … critically evaluate … synthesize … refined,
    accurate, and comprehensive reply … well-structured, coherent …"`
  - Spec entries (3): `build_proposer_prompt` (pure), `build_aggregator_
    prompt` (pure), `run` (Strategy). All `S.instrument`-decorated.
    Internal helpers exposed via `M._internal`:
    `format_responses_for_aggregator`, `resolve_proposers`.
  - EXTENSION POINTS: REQUIRED `ctx.task` + one of `ctx.proposers`
    (multi-model PATH; Wang §3 main config — array of
    `{model, system?}` specs) OR `ctx.personas` (single-model rotation
    PATH; outside Wang §3's multi-model setup). v0.1.0's
    hardcoded `PERSONAS` is removed — the alt-path makes persona-style
    callability explicit and opt-in. (L)-override: `n_layers`. (X)
    infrastructure: `temperature` / `proposer_tokens` / `aggregator_tokens`
    / template overrides / `system_prompt`. Overriding `aggregator_prompt`
    invalidates the AS_PROMPT (L) guarantee.
  - Result shape (breaking from v0.1.0): `{answer, n_layers, n_proposers,
    layers[{layer, proposers[{proposer, model?, text}], aggregated}],
    total_llm_calls}`. v0.1.0's `n_agents` / `total_calls` /
    `layer_outputs` fields are renamed to `n_proposers` /
    `total_llm_calls` / `layers` with richer per-layer record shape
    (now includes the explicit aggregator output per layer).
  - Category: `selection` → `aggregation` (paper §2.2 is explicitly
    aggregation: the Aggregate-and-Synthesize operator ⊕).
  - Paper proposer models (Wang §3 main exp, Together AI tier):
    Qwen1.5-110B-Chat, Qwen1.5-72B-Chat, WizardLM-8x22B,
    LLaMA-3-70B-Instruct, Mixtral-8x22B-v0.1, dbrx-instruct.
    These are (L) for reproducing paper results but NOT hardcoded by
    the pkg (would bind to a specific API tier and exclude OSS / local
    callers); caller supplies them via `proposers`.
  - Test coverage: `tests/test_moa.lua` (36/36 PASS) covers meta / spec /
    `_defaults` / AS_PROMPT_TEMPLATE literal-equality / `build_proposer_prompt`
    (layer-1 + layer-2+ + override + reject) / `build_aggregator_prompt`
    (AS_PROMPT application + override + empty reject) / `_internal` helpers
    (`resolve_proposers` multi-model + single-model rotation + neither reject) / run
    end-to-end (L·(n+1) call count + `x_{i+1}=y_i` propagation +
    per-layer aggregator + model id propagation + per-proposer system
    prompt + temperature/tokens propagation + error paths).
  - `scripts/e2e/moa.lua` rewritten for the new signature (MoA-Lite
    L=2 / 2 personas / smoke test path).

## [0.23.0] - 2026-05-10

### Added

- **`card_analysis` package** (new, category=`debugging`, 118th package):
  default analyzer pkg dispatched by the host MCP tool
  `alc_card_analyze` (`algocline-app::DEFAULT_CARD_ANALYZE_PKG =
  "card_analysis"`). Reads a Card body + samples sidecar, detects
  failure samples across 4 heuristic OR paths
  (`admission=fail` / `status∈{fail,error}` / `passed=false` /
  `score<0.5`) with no-signal fallback (entire sample pool when
  no heuristic matches), then issues one `alc.llm` call requesting
  STRICT JSON. `alc.json_extract` parses the response into the
  host-side typed struct
  `algocline-app::service::card::CardAnalyzeResult` shape:
  `{ pattern, suggested_change, confidence, failure_count?,
  sample_count? }`. On parse failure the raw LLM output is preserved
  in `_raw_llm` (compacted to 2000 chars) with `confidence=0.0`.
  Migrated from POC at `~/.algocline/packages/card_analysis/init.lua`
  with bundled refinements: `M.spec` added with inline `T.shape`
  for both input and result, `S.instrument(M, "run")` wrapper
  applied, docstring refined to bundled D1 + `## Usage` /
  `## Algorithm` / `## Failure detection` / `## Output` /
  `## Caveats` / `## References` per pkg-author-conventions §F.
  Test coverage: `tests/test_card_analysis.lua` (5 cases / 6 tests:
  happy path / input validation / empty samples sentinel / 4 failure
  heuristic paths + no-signal fallback / LLM unparseable fallback;
  all 6/6 PASS via mlua-probe-mcp).

## [0.22.1] - 2026-05-09

### Removed

- **`docs/docstring-convention.md`** (V0 single-spec doc, 335 行):
  superseded by `refs/pkg-author-conventions.md` which served as
  the rubric for the v0.22.0 full-compliance sweep (lint 96 → 0
  across all 117 packages). The V0 spec is fully absorbed into
  pkg-author-conventions and no longer maintained — keeping the
  stale copy invites divergence. Only references were inside
  `CHANGELOG.md` historical entries (kept verbatim as history).

## [0.22.0] - 2026-05-09

### Changed

- **pkg-author-conventions full compliance sweep (all 117 packages,
  lint 96 → 0)**: applied `refs/pkg-author-conventions.md` rubric to
  every bundled package in a one-package-per-commit sweep. Per-pkg
  changes: D1 docstring header normalized to
  `<pkg>(<PascalName>) — <one-line summary>` form; E16 fake-label
  blocks (`Lua Modeling style`, etc.) removed in favor of plain
  prose; E4/E5 inline math escaped into fenced math blocks where
  appropriate; F README-style sections (`## Usage`,
  `## Algorithm`, `## Theoretical foundations`,
  `## Injection points`, `## Caveats`, `## Comparison`,
  `## References`) added per pkg-conventions §F. Final
  `alc_hub_dist lint_strict=true` reports 117 generated / 0 failed /
  0 errors / 0 warnings (down from 96 W_FAKE_LABEL warnings at sweep
  start). No package implementation (`init.lua` runtime) was touched
  in this sweep — docs / docstring / spec metadata only. Tests
  remain green (existing per-pkg suites pass with no regression).
  Captured in `workspace/journal.md` 2026-05-08 ~ 2026-05-09 chapter
  (pkg-author-conventions full compliance, lint 0/0 完全制覇).

- **`scripts/e2e/review_and_investigate.lua` harness fix (final
  e2e to PASS — 19/19 complete)**: the initial run reported in the
  earlier "End-to-end real-LLM validation" entry left this single
  e2e FAIL. Root cause was identified by inspecting
  `workspace/e2e-results/2026-05-08_130610/review_and_investigate.json`
  turn-by-turn: (1) the prompt passed `code` via `task: %q` to
  `alc_advice`, but the package requires `ctx.code` not `ctx.task`,
  forcing the agent to self-correct to `alc_run` on Turn 1 (1
  wasted turn); (2) `max_iterations = 40` was insufficient for
  6 phases × 2 themes (T1 division_by_zero + T2 missing_type_validation,
  with Phase 4 diagnose triggering an 8-call calibrate-to-triad
  panel per theme), consuming all 40 iterations on phase work and
  leaving no budget for the final summary turn — resulting in a
  44-character truncated content `"**Phase 6 — Propose fix
  candidates for T2:**"`. Fix: pass `code` through `opts`
  (so it lands in `ctx.code`), raise `max_iterations` to `60`,
  and explicitly instruct the agent to surface all required
  keywords (themes / verified / explore / root_cause /
  summary.total_themes / fix recommendation) in a single final
  summary turn. Re-run result: 5/5 graders PASS, 41 turns, 164,842
  tokens — `theme_count_reported` and `all_three_callsites_reported`
  both green. With this fix, **all 19 newly-added e2e smokes PASS
  (19/19 = 100%)**, completing the post-migration validation across
  all 22 packages × 3 verification layers (static check / unit test
  / real-LLM e2e). Closes follow-up issue `1778215078-39073`.

- **End-to-end real-LLM validation of the post-migration hardening
  (Phase B verification ran)**: executed all 19 newly-added e2e
  smokes (Simple 12 from commit `954b7c8` + rstar/Multi-callsite 6
  from commit `937a925`) via `just e2e <name>` against the live
  Anthropic API. **18/19 e2e PASS** (~150,000 tokens consumed
  across all runs). The lone FAIL is `review_and_investigate`,
  whose agent ran 40 turns without crashing (agent_ok PASS,
  max_tokens PASS at 74,828 / 250,000) but truncated mid-Phase-6
  before surfacing the final result fields, so the
  `output_present` / `theme_count_reported` /
  `all_three_callsites_reported` graders failed. This is an
  **e2e-harness design issue** (max_iterations + prompt + grader
  field-name assumptions), **not a migration regression** — the
  `tests/test_review_and_investigate.lua` 5/5 stub-based unit test
  remains green and the package's own `alc.parallel` callsites
  fired correctly during the live run. Tracked separately as
  follow-up issue `1778215078-39073` (3-step refinement: confirm
  result-shape field names, raise `max_iterations`, simplify task).
  The **await-confluence pattern is now real-LLM-observable**
  across all 6 Multi-callsite packages: `cross_verify_present`
  (rstar), `comparison_phase_complete` (anti_cascade),
  `n_steps_reported` (got), `trace_results_reported` (lineage),
  `judgments_phase_complete` (counterfactual_verify), and
  `grounded_output_present` + `n_levels_reported` (coa) all
  PASSed end-to-end. With this validation, the
  `alc.map → alc.parallel` migration tracked at parent issue
  `1778144244-78327` is **functionally validated end-to-end**;
  Phase A unit tests + Phase B static checks + this real-LLM
  Phase B execution form three independent verification layers
  for the migration.

- **7 new `scripts/e2e/*.lua` real-LLM smoke tests** (Phase B
  sub-batch 2, **completing** the post-migration hardening): adds
  end-to-end smoke harnesses for `rstar` and the 6
  Multi-callsite-structured packages (`anti_cascade` / `got` /
  `lineage` / `counterfactual_verify` / `review_and_investigate` /
  `coa`). All files reuse the `scripts/e2e/sot.lua` baseline
  (commit `439ae53`) and the Simple-12 e2e batch shape (commit
  `954b7c8`). Transport: `alc_advice` (no closures). Each file
  carries 5-6 graders combining `agent_ok` + `max_tokens(N)` (200k–
  300k for multi-callsite packages, larger than the 150k Simple
  baseline because more agent turns are spent across phases) +
  `output_present` + 1-2 **phase-boundary graders** asserting that
  Phase-N of the package consumed Phase-(N-1)'s awaited result —
  the e2e-observable counterpart of the await-confluence pattern
  validated by commit `97d757a`. Phase-boundary grader assertions:
    rstar — `cross_verify_present` (a_checks_b / b_checks_a both
      surface = Phase 3 ran after Phase 1+2 completed)
    anti_cascade — `comparison_phase_complete` (flagged_steps /
      max_drift / cascade_risk surface = Phase 2 ran after Phase 1)
    got — `n_steps_reported` (graph_stats.operations surface = DAG
      Generate→Score→KeepBest→Refine→Aggregate iteration ran)
    lineage — `trace_results_reported` (traces / derives_from
      surface = Phase 2 referenced Phase 1's step_claims)
    counterfactual_verify — `judgments_phase_complete` (match_count
      / faithful surface = judgments ran after predictions + actuals,
      canonical closure-capture invariant)
    review_and_investigate — `all_three_callsites_reported` (detect
      / verify / explore-or-diagnose phases all surface)
    coa — `grounded_output_present` (grounded_chain /
      abstract_chain surface = topological loop fully resolved)
  Total ~880 LOC across 7 new files. All files pass
  `mcp__lua-debugger__check_launch` with 0 errors / 0 warnings.
  Real-LLM execution is **not** performed in this commit. With this
  commit, **all 22 migrated packages now have a real-LLM e2e smoke
  harness** (sot via `439ae53`, particle_infer / smc_sample
  pre-existing, Simple 12 via `954b7c8`, and rstar + Multi-callsite
  6 here).

- **12 new `scripts/e2e/*.lua` real-LLM smoke tests** (Phase B
  sub-batch 1 of the post-migration hardening): adds end-to-end
  smoke harnesses for the 12 Simple-structured packages migrated to
  `alc.parallel`. All files reuse the `scripts/e2e/sot.lua` baseline
  (commit `439ae53`) — `package.path` shim + `common.lua` library +
  `params` / `prompt` / `common.run({ name, prompt, params,
  max_iterations, graders })` shape. Transport: `alc_advice` (no
  closures in Simple-structured packages, opts are JSON-safe).
  Grader budget per file: 4-5 graders, each combining
  `common.grader_agent_ok()` + `common.grader_max_tokens(N)` +
  `output_present` (≥50-char content) + 1-2 package-specific
  structural assertions surfacing the `M.spec.entries.run.result`
  primary fields (e.g. `level_used_reported` for cascade,
  `attribution_score_reported` for claim_trace, `precision_score`
  in [0,1] for factscore, sort-order verification for rank,
  `verdict_reported` for maieutic / triad). Tasks are small,
  deterministic, and shaped to trigger each package's
  paper-faithful behavior (cascade escalation threshold, distill
  3-chunk Map phase, moa 2-agent × 2-layer aggregation, etc.).
  Files added:
    cascade.lua / claim_trace.lua / critic.lua / decompose.lua /
    distill.lua / factscore.lua / moa.lua / negation.lua /
    p_tts.lua / rank.lua / maieutic.lua / triad.lua
  Total ~1,150 LOC across 12 new files. All files pass
  `mcp__lua-debugger__check_launch` with 0 errors / 0 warnings.
  Real-LLM execution is **not** performed in this commit — running
  these smokes via `just e2e <name>` is User-territory (Anthropic
  API token consumption). New `scripts/e2e/*.lua` for the 7
  Multi-callsite-structured packages (`rstar` + `anti_cascade` /
  `got` / `lineage` / `counterfactual_verify` /
  `review_and_investigate` / `coa`) is tracked separately as
  Phase B sub-batch 2.

- **17 new `tests/test_*.lua` unit-test files** (Phase A of the
  post-migration hardening): adds stub-based unit tests for the 17
  packages migrated to `alc.parallel` that previously had no
  individual test coverage. All test files reuse the canonical
  `make_alc_stub` factory pattern from `tests/test_smc_sample.lua`
  (with `alc.parallel` / `alc.llm_batch` mocks delegating to the
  `alc.llm` fixture mechanism) and the `repo_root_from_package_path()`
  REPO-resolution pattern (mlua-probe-mcp safety per CLAUDE.md
  "失敗記録 2026-04-19"). Each file exercises 4-5 cases:
  Simple-structured packages (cascade / claim_trace / critic /
  decompose / distill / factscore / negation / p_tts / rank /
  maieutic / triad — 11 packages × 4 cases) cover happy path /
  input validation / package-specific behavior / edge case;
  Multi-callsite-structured packages (anti_cascade / got / lineage /
  counterfactual_verify / review_and_investigate / coa — 6 packages
  × 5 cases) add a phase-boundary or DAG-correctness case asserting
  that the awaited Phase-(N-1) result flows correctly into the
  Phase-N callback (the await-confluence pattern validated by commit
  `97d757a`). Total: 74 cases, ~3,725 LOC across 17 new files.
  No package implementation (`init.lua`) was touched. All 74 cases
  pass; existing test suites (`test_new_packages.lua` 32/32,
  `test_smc_sample.lua` 77/77, `test_particle_infer.lua` 98/98,
  `test_sot.lua` 5/5) remain green with no regression. New
  `scripts/e2e/*.lua` files for the 19 packages without real-LLM
  smokes are tracked separately as Phase B of the hardening work.

- **Multi-callsite 6 batch — `alc.map` → `alc.parallel`**: migrated
  13 call-sites across 6 Multi-callsite / Multi-phase packages to
  the true batch-parallel `alc.parallel` primitive. Applies the
  await-confluence pattern validated by commit `97d757a` (rstar):
  Phase-N callbacks that closure-capture awaited Phase-(N-1) results
  via Lua's synchronous upvalue semantics work identically under
  `alc.parallel` and `alc.map`. Migrated packages and call-sites:
    * `anti_cascade` (`:211, :232`, 2 call-sites — Phase 1
      independent re-derivation + Phase 2 pipeline-vs-independent
      compare; data-driven pack, no closure ref)
    * `got` (`:130, :222`, 2 call-sites — Generate per node-batch
      + Score per node; outer DAG step iteration loop preserved)
    * `lineage` (`:274, :307`, 2 call-sites — Phase 1 extract claims
      + Phase 2 trace deps per consecutive pair; data-driven via
      trace_pairs pack, post_fn used for parse fallback)
    * `counterfactual_verify` (`:205, :226, :243`, 3 call-sites —
      predictions + actuals + judgments; judgments
      closure-captures `predictions[i]` / `actuals[i]` from prior
      phases — canonical await-confluence)
    * `review_and_investigate` (`:358, :415, :624`, 3 call-sites —
      themes-parallel review / investigate / counter-evidence; all
      independent, no inter-callsite closure ref; one call-site
      uses post_fn)
    * `coa` (`:237`, 1 call-site — independent placeholders within
      one topological-order batch; outer topological loop preserved,
      callback closure-captures `resolved_vars` from outer loop
      state)
  Behavior is mathematically equivalent: callbacks were already
  independent within each call-site (no inter-iteration state),
  closure-captured awaited results are upvalue-stable under both
  `alc.map` and `alc.parallel`, and `alc.parallel` preserves order
  via `for ipairs(items)` iteration matching the previous semantics.
  Closes child issues `1778160596-83566` (anti_cascade),
  `1778160701-85165` (got), `1778160712-85322` (lineage),
  `1778160653-84471` (counterfactual_verify), `1778160787-86686`
  (review_and_investigate), `1778160638-84220` (coa) under parent
  migration tracker `1778144244-78327`. Tests:
  `tests/test_new_packages.lua` 32/32 pass (no regression). New
  `tests/test_*.lua` for the 6 previously-untested packages and
  `scripts/e2e/*.lua` smokes are out of scope for this batch and
  tracked separately.

- **`rstar`** (Reasoning): migrated both `alc.map` call-sites to
  `alc.parallel` — Phase 1+2 (`:98` two independent reasoning paths,
  N=2) and Phase 3 (`:129` cross-verification, N=2). Phase 3's
  callback closure-captures the awaited `path_a` / `path_b` results
  from Phase 1+2; this pattern is preserved unchanged because Lua's
  synchronous function semantics guarantee both locals are
  fully-resolved values by the time Phase 3 starts (identical to the
  `alc.map` upvalue capture semantics). This commit serves as the
  reference implementation for the **await-confluence pattern** —
  Multi-callsite packages where one phase consumes the awaited result
  of a previous phase via closure capture. Validated against the
  existing rstar test cases in `tests/test_new_packages.lua` (mutual
  disagreement / partial agreement cases). Closes child issue
  `1778160807-86996` under parent migration tracker
  `1778144244-78327`. Tests: `tests/test_new_packages.lua` 32/32
  pass (no regression across all suites).

- **Simple 12 batch — `alc.map` → `alc.parallel`**: migrated 13
  call-sites across 12 Simple-structured packages from the sequential
  `alc.map` to the true batch-parallel `alc.parallel` primitive
  (single `alc.llm_batch` round-trip per call-site). All 12 packages
  carry "parallel" wording in docstring/comments that previously
  contradicted the sequential `alc.map` implementation; this migration
  brings claim and behavior into agreement and reduces N-section
  latency from N round-trips to 1 round-trip. Migrated packages and
  call-sites:
    * `cascade` (`:194` perspectives)
    * `claim_trace` (`:236` claim attribution)
    * `critic` (`:167` per-dimension evaluation)
    * `decompose` (`:101` Phase 2 sub-task execution)
    * `distill` (`:86` MapReduce Map phase)
    * `factscore` (`:123` per-claim verification)
    * `moa` (`:103, :134` Layer 1 + Layer N agents, 2 call-sites)
    * `negation` (`:190` per-condition verification)
    * `p_tts` (`:221` per-constraint verification)
    * `rank` (`:74` Phase 1 candidate generation)
    * `maieutic` (`:62` support/oppose, N=2)
    * `triad` (`:69` proponent/opponent opening, N=2)
  Two callback patterns were used: Pattern A (single shared
  `system` / `max_tokens` shared across all items, prompt_fn returns
  prompt string; opts attached via `alc.parallel(items, fn, opts)`)
  and Pattern B (item-specific `system` / `max_tokens`, prompt_fn
  returns a `{prompt, system, max_tokens}` table per
  `prelude.lua:491-499`). Behavior is mathematically equivalent —
  callbacks were already independent (no inter-iteration state), and
  `alc.parallel` preserves order via `for ipairs(items)` iteration
  matching the previous `alc.map` semantics. `tests/test_new_packages.lua`
  gains `alc.parallel` / `alc.llm_batch` mocks (delegating to the
  existing `alc.llm` fixture mechanism, same pattern as
  `tests/test_smc_sample.lua`). Closes child issues `1778160614-83833`
  (cascade), `1778160623-83954` (claim_trace), `1778160661-84595`
  (critic), `1778160672-84753` (decompose), `1778160680-84875`
  (distill), `1778160689-85008` (factscore), `1778160554-82916` (moa),
  `1778160731-85813` (negation), `1778160738-85947` (p_tts),
  `1778160772-86479` (rank), `1778160724-85678` (maieutic),
  `1778160875-88695` (triad) under parent migration tracker
  `1778144244-78327`. Tests: `tests/test_new_packages.lua` 32/32 pass
  (moa coverage included). New `tests/test_*.lua` for the 11
  previously-untested packages and `scripts/e2e/*.lua` smokes are
  out of scope for this batch and tracked separately.

- **`scripts/e2e/sot.lua`**: new end-to-end smoke test for `sot`
  using agent-block + algocline MCP + real LLM (Anthropic API).
  Drives a 3-section Skeleton-of-Thought run on a short Lua-coroutine
  topic and asserts: agent_ok / cumulative-token budget / output
  non-empty / section_count surfaced / `##` heading marker present.
  Validates the post-migration behavior end-to-end (Phase 2 fills
  dispatched as a single `alc.llm_batch` round-trip via
  `alc.parallel`). First green run: `2026-05-08_093746`, 6 turns /
  6609 tokens / ~9 s wall-clock for 4 LLM calls (1 skeleton + 3
  fills). Run via `just e2e sot`.

- **`sot`** (Generation): migrated the section-fill call-site from
  the sequential `alc.map` to the true batch-parallel `alc.parallel`
  primitive (single `alc.llm_batch` round-trip). The previous
  implementation contradicted the package's own paper-faithful claim:
  Ning et al. "Skeleton-of-Thought: Prompting LLMs for Efficient
  Parallel Generation" (2023, arXiv:2307.15337; v3 retitled from v1
  "LLMs Can Do Parallel Decoding") reports up to **2.39× latency
  speedup** on 8/12 models in §3.1.1 — parallel section fill is the
  paper's core claim. The previous `alc.map` callback executed N
  section fills as N sequential round-trips (hence ~1× latency, not
  2.39×). Behavior is mathematically equivalent (section fills were
  already independent, no inter-iteration state); only the dispatch
  primitive changed. The inline IIFE that built the per-section
  outline marker is expanded into the prompt_fn body for
  readability. Docstring is updated to reflect the v3 paper title
  and explicitly cite the 2.39× speedup as the reason for using
  `alc.parallel` (not `alc.map`). Adds new `tests/test_sot.lua`
  (5 cases: happy path / skeleton-parse fallback / max_sections
  cap / LLM call counting / alc.parallel-not-alc.map invariant)
  using the shared `make_alc_stub` pattern from
  `tests/test_smc_sample.lua` (`alc.parallel` / `alc.llm_batch`
  mocks delegating to the existing `alc.llm` fixture mechanism).
  Closes child issue `1778160863-88511` under the parent migration
  tracker `1778144244-78327`. Tests: 5/5 pass.

- **`particle_infer` / `smc_sample`** (Sampling): migrated 3 LLM
  call-sites from the sequential `map_or_serial` helper to the true
  batch-parallel `alc.parallel(items, prompt_fn, opts)` primitive.
  The shared `map_or_serial` helper is renamed to `pure_fan_out`
  in both packages and its docstring is updated to clarify that it
  is now intentionally retained **only** for caller-injected
  non-LLM callbacks (`prm_fn` / `reward_fn` in `evaluate_prm` /
  `evaluate_rewards`) where the LLM-batch-only `alc.parallel` API
  does not apply. Migrated call-sites: `particle_infer.advance_step`
  (was 1 LLM call per active particle, now 1 round-trip via
  `alc.llm_batch`), `smc_sample.init_particles` (N independent
  draws), `smc_sample.mh_rejuvenate` Stage 1 propose (LLM calls on
  active slots). Behavior is mathematically equivalent to the
  previous sequential implementation; original `pcall` / type / nil
  guards are preserved via `opts.post_fn` since `alc.llm_batch` is
  all-or-nothing rather than per-element pcall-able. Performance:
  N round-trips → 1 round-trip per migrated call-site (latency × N
  → × 1, token cost unchanged). Paper-faithful default is preserved
  (arXiv:2502.01618 §3.1 Algorithm 1 / arXiv:2604.16453 §3
  Algorithm 1 explicitly permit but do not mandate parallel
  execution; `caller-selectable` opt-in was deliberately not added
  since neither paper requires sequential semantics). Test mocks
  in `tests/test_particle_infer.lua` and `tests/test_smc_sample.lua`
  gain `alc.parallel` / `alc.llm_batch` stubs that delegate to the
  existing `alc.llm` fixture mechanism so the existing
  `counter.llm_calls` accounting and fixture-order assertions
  remain valid. Closes child issues `1778160761-86331`
  (particle_infer) and `1778160839-87823` (smc_sample) under the
  parent migration tracker `1778144244-78327`. Tests:
  particle_infer 98/98 pass, smc_sample 77/77 pass.

### Fixed

- **README Runtime API table**: `alc.map(list, fn)` was previously
  documented as "Parallel map execution", which is misleading.
  `alc.map` is implemented as a plain sequential `for ipairs` loop
  in `algocline-engine/src/prelude.lua:89-95`; LLM calls placed
  inside its callback run **sequentially** (N round-trips, not
  batch-parallel). The table is corrected to label `alc.map` as
  Sequential, and `alc.parallel(items, prompt_fn, opts)` /
  `alc.llm_batch(items)` are now documented as the true
  batch-parallel primitives (single round-trip via Rust-side
  `coroutine.yield` + `await all` in `bridge/llm.rs`). `alc.reduce`
  is also surfaced for completeness. **Behavior unchanged**: this
  is a documentation-only correction. Per-pkg docstring claims
  ("parallel" wording) and `alc.map` → `alc.parallel` migration
  for the 24 pkg currently using `alc.map` for multi-LLM-call
  flows are tracked separately as follow-up issues — each pkg
  needs individual triage on whether sequential / parallel /
  caller-selectable is the right contract (post_fn dependency,
  inter-iteration state, paper-faithful semantics). See issue
  `1778144244-78327`.

### Added

- **`crdt_doc`** (Collaboration): Frame role substrate (no `M.run`,
  no LLM, sub-modules exposed as fields) implementing
  Shapiro, Preguiça, Baquero, Zawirski "A comprehensive study of
  Convergent and Commutative Replicated Data Types" (INRIA RR-7506,
  2011). Provides Doc + Op + Merge primitives that **external
  collaboration Frames** (state-rich orchestrators that live outside
  bundled-packages) compose to build multi-agent shared state with
  mathematical conflict-free merge. Initial lineup: OR-Map
  (tag-level primitive INSPIRED BY §3.3.5 Specification 15;
  element-level remove is a caller-side composition of tag-level
  removes — see module docstring) + LWW-Register (Last-Writer-Wins,
  §3.4.1). Public API: `M.doc.{new,snapshot,clone,delta,op_diff}`,
  `M.op.{set_add,set_remove,lww_set,is_valid}`, `M.merge(doc, op)`,
  `M.merge_docs(d1, d2)`. Op kind is declarative (`set_add` /
  `set_remove` / `lww_set`) with boundary validation via
  `M.op.is_valid`; ordered mutations are rejected at the entry rather
  than detected at runtime. Merge is commutative / associative /
  idempotent by construction (Shapiro 2011 Theorem 2.1) — exercised
  via fixed-order convergence tests across both CRDT types
  (random-sequence property testing is reserved for future work).
  Caller contract (tag uniqueness, lamport monotonicity, stable
  agent identity) is documented in the module-level `INJECTION
  POINTS` section; violations degrade convergence silently.
  `M.doc.op_diff(doc, prev)` is the quiescence-detection primitive
  (monotonic `doc.op_count` field), backed by every merged op
  including idempotent / losing-tiebreak writes. `M.doc.delta` is
  retained as a cheap SIZE proxy but is NOT a faithful quiescence
  detector (size-stable mutations report `delta == 0`).
  Pure Lua, no native dep — Y.Text-compatible sequence CRDT (RGA /
  Logoot) is reserved for a future v2. New **Collaboration**
  Packages section introduced (Category-axis), reserved for future
  primitives in this layer; Orch-side LLM-peer logic
  (`crdt_peers`-shaped) is intentionally outside bundled-packages
  (issue 1778147830-21936 follow-up).
- **Frames Roster** updated: `crdt_doc` joins `flow` and `abm` as
  the third Frame-role pkg (README §Roster).

## [0.21.0] - 2026-05-04

### Added

- **`slm_mux`** (Selection): Pure Computation pkg implementing
  Wang, Wan, Kang, Chen, Xie, Krishna, Reddi, Du
  "SLM-MUX: Orchestrating Small Language Models for Reasoning"
  (arXiv:2510.05077, ICLR 2026 Poster). Confidence-based per-model
  selection (paper §3.1 Algorithm 1: `f_i / s_i / y_i*` + tie-break by
  validation accuracy) plus complementarity-driven K-subset selection
  (paper §3.2: `𝒪(S) = UnionAcc(S) − λ · Contradiction(S)` via
  exhaustive search over `C(N, K)` subsets). Five direct-args entries:
  `confidence`, `score_subset`, `select_subset`, `inference_select`,
  `run`. Paper-faithful defaults (`λ = 1.0`, `search_method = "exhaustive"`,
  `consistency_threshold = 0.0`, `s_tie_break = "validation_accuracy"`).
  Opt-in **NOT paper-faithful** `search_method ∈ {"greedy_forward",
  "greedy_backward"}` for large `N` (loses globally-optimal guarantee
  on `𝒪`); opt-in `consistency_threshold > 0.0` strengthens the
  Contradiction predicate (departs from §3.2 formal definition).
  Pure Lua — no `alc.llm` calls; caller drives test-time inference
  with `sc` / `panel` / `smc_sample` / `particle_infer` etc. Fills the
  selection-axis gap not covered by `cascade` / `router_*` (single-best
  routing) or `ab_select` / `mbr_select` (single-best selection):
  N→K subset complementarity over a pre-computed calibration tensor.
- **`alc_shapes.M.slm_muxed`** result shape registered (open shape with
  `selected_indices`, `objective`, `union_acc`, `contradiction`,
  `lambda`, `search_method`, `search_log`).
- **`solve_verify_split`** (Orchestration): Pure Computation pkg
  implementing Singhi, Bansal, Hosseini, Grover, Chang, Rohrbach,
  Rohrbach "When To Solve, When To Verify: Compute-Optimal Problem
  Solving and Generative Verification for LLM Reasoning"
  (arXiv:2504.01005, COLM 2025). §3.1 cost model
  `C(S,V) = S · (1 + λ · V)` (per-solution verification,
  `λ = T_V / T_S`) plus §5.2 power-law allocator
  `S_opt ∝ C^a, V_opt ∝ C^b` reconstructed via the §3.2 6-step
  procedure. Five direct-args entries: `cost`, `score_split`,
  `optimal_split`, `sc_pure`, `compare_paths`. Paper-faithful default
  exponents (`a = 0.57, b = 0.39`) from §5.2 Llama-3.1-8B + GenRM-FT
  + MATH; Appendix J alternates (Qwen-2.5-7B `0.75/0.32`,
  Llama-3.3-70B `0.69/0.43`) referenced in docstring as transferred
  defaults. Prefactors `α_S, α_V` have no numeric value in the paper
  (§3.2 Step 5) — caller-fit required and runtime-asserted. Three
  rescale strategies for integer-rounding overflow:
  `"scale_proportional"` (default), `"prefer_solve"`, `"prefer_verify"`
  (paper not fixed). SC pure path automatically engages when `V_int`
  rounds to 0 (§3.1 V=0 degenerate case); opt-out via
  `sc_fallback_when_v_zero = false`. Opt-in **NOT paper-faithful**
  `cost_model = "independent"` reserved at the API surface but
  rejected at runtime in v1 (per-solution structure is paper-faithful
  contract). Pure Lua — no `alc.llm` calls; caller drives test-time
  inference with `sc` / `step_verify` / `cove`. Fills the
  orchestration-axis gap not covered by `compute_alloc` (paradigm
  choice) or `gumbel_search` / `ab_mcts` (search depth-vs-width):
  intra-paradigm S↔V split under a fixed inference budget. The §5.1
  cross-over multipliers (4× / 8× / 64× — verifier-quality and
  model-dependent observations, Appendix E) are NOT hardcoded.
- **`alc_shapes.M.compute_optimal_split`** result shape registered
  (open shape with `s_opt`, `v_opt`, `cost_used`, `cost_budget`,
  `lambda`, `integer_method`, `rescale_method`, `rescaled`,
  `is_sc_fallback`, `raw`).

### Changed

- **slm_mux**: `inference_select` result now includes `tie_break_used`
  field exposing which tie-break path actually ran (`no_tie` /
  `validation_accuracy` / `first_found` / `lexicographic_on_indices` /
  `first_found_fallback_no_validation_accuracy`). Removes silent
  degradation of paper §3.1 Algorithm 1 when tied candidates lack
  `validation_accuracy`.
- **slm_mux**: `partial_coverage = "treat_as_wrong"` no longer surfaces
  the literal string `"<missing>"` as a stand-in answer; an internal
  `missing` flag now drives `is_correct` / `is_consistently_wrong`.
- **slm_mux** (docs): `subset_tie_break = "smaller_K"` is documented as
  a no-op in fixed-K `select_subset` enumeration; preserved in the
  enum for future variable-K APIs.
- **solve_verify_split (BREAKING)**:
  - `score_split.result.predicted_sr` renamed →
    `power_law_score_proxy`. The field is the `S^a · V^b` proxy, not
    a paper-§5.2 SR estimate. Now `nil` when `V == 0` (SC pure path)
    to remove the V→0⁺ discontinuity; callers must use
    `compare_paths.delta_*` / observed accuracy for cross-path
    comparison.
  - `compare_paths.result.advantage` removed; replaced by explicit
    `delta_v_opt` and `cost_ratio` fields. The paper-§5.1 cross-over
    judgment is verifier-quality and model-dependent, so a single
    boolean / enum field cannot capture it.
  - All entries now require `B >= 1` (paper §3.1 cost unit is
    inference call / token).
  - `check_params_for_optimal` rejects `exponent_solve` /
    `exponent_verify` outside `(0, 1)` per paper §5.2 + Appendix J
    observed range.

### Fixed

- **slm_mux** (math-strict review):
  - Removed misattribution of the inference-time concentration bound to
    paper §5: arXiv:2510.05077 §5 contains no Hoeffding inequality.
    The bound `Pr(î = i*) ≥ 1 − 2(K−1)·exp(−N·γ²/2)` is now labelled
    *out-of-paper*, derived from the standard Hoeffding union bound on
    Bernoulli sample-mean concentration of `s_i`, with `p_i` (population
    argmax frequency) explicitly defined alongside `s_i` (sample
    estimate). NOT-IN-v1 docstring no longer claims a §5 flow.
  - `Per-model confidence` and `Inference-time selection` paragraphs now
    cite the correct Algorithm 1 line ranges (`Lines 6-7` / `Lines 9-13`).
  - Subset enumeration tie collection switched to eps-tolerant comparison
    (`|a − b| ≤ 1e-12`) to keep the §3.2 argmax set deterministic under
    bit-rounding noise on `𝒪(S) = UnionAcc(S) − λ · Contradiction(S)`.
  - `subset_tie_break` is now honoured in greedy paths
    (`greedy_forward` / `greedy_backward`): each greedy step collects
    ties with the same eps and routes them through the same
    `tie_break_subset` mode used by exhaustive search. Previously these
    options were silently ignored on greedy.
  - `inference_select` rejects `validation_accuracy ∉ [0, 1]` and NaN
    (paper §3.1 Algorithm 1 invariant `a_i ∈ [0,1]`) with a typed error
    instead of silently using out-of-range values for tie-break.
  - `_internal.contradiction` raises a typed error when no calibration
    question has any observed sample under the `partial_coverage`
    filter, symmetric with `_internal.union_acc`. Removes a silent `0`
    return when the helper is invoked directly via the test hook.
- **solve_verify_split** (math-strict review):
  - `optimal_split` now validates `opts.s_cap` / `opts.v_cap` as finite
    integers with floors (`s_cap ≥ 1` per paper §3.1 implication that
    at least one solution is needed; `v_cap ≥ 0`). Previously `s_cap = 0`,
    `v_cap = -1`, and fractional caps such as `0.5` were silently
    accepted and propagated to `s_opt` / `v_opt` / `cost_used`.
  - All numeric inputs (`B`, `lambda`, `exponent_*`, `prefactor_*`, caps)
    now reject NaN and ±Inf via explicit `x ~= x` and `±math.huge`
    detection. IEEE 754 NaN comparisons that previously slipped through
    `B < 1` / `lambda <= 0` checks now error out as `"must be a finite
    number, got NaN"`.
  - `is_sc_fallback` semantics unified between the two `optimal_split`
    code paths: post-rescale `v_final == 0` always sets the flag,
    independent of whether `sc_path(B)` strictly increases `s_final`.
    Previously the flag's value depended on `B` for the same allocator
    (`B = 1 → false`, `B = 3 → true`), making caller routing on
    `is_sc_fallback` unreliable.
  - `score_split.power_law_score_proxy` is now `nil` for both `S <= 0`
    and `V <= 0` (previously `S <= 0` returned `0` while `V <= 0`
    returned `nil`). Symmetric on the two axes; the proxy is undefined
    whenever either factor is non-positive.
  - Allocator algorithm docstring renamed away from "§3.2 procedure
    reconstructed" to clarify that paper §3.2 is a 6-step regression
    procedure ending at log-linear fit (Step 5), not a runtime
    allocator. The 5-step rounding/rescale algorithm in this pkg runs
    *after* the caller has fitted `(α, a, b)` per §3.2 Step 5.
  - Domain note added: paper §3.1 implies `S ≥ 1` and `V ≥ 0`;
    `optimal_split` now always returns `s_opt ≥ 1`.
  - `apply_rescale` (`scale_proportional`) carries an explicit
    termination-guarantee comment (factor < 1 plus integer no-progress
    fallback bounds the loop by `S_int + V_int`).

### Documentation

- **slm_mux** (round 3, docstring-only — no logic change):
  - `partial_coverage = "skip_missing"` now carries an explicit caveat
    that UnionAcc / Contradiction are normalised by `effective_M`,
    which can differ across subsets when profiles cover different
    questions, so `𝒪(S₁) vs 𝒪(S₂)` comparison under this mode is only
    an approximation (paper §3.2 `|𝒟|` is fixed and shared across `S`).
    `"treat_as_wrong"` keeps `|𝒟|` fixed and preserves cross-subset
    comparability.
  - `OBJ_EPS = 1e-12` (𝒪 tie collection eps) gains a scale-assumption
    comment: granularity is `1 / |effective_M|`, paper §4.3 uses
    `|𝒟| = 500` (granularity 2e-3), eps is safe up to
    `|effective_M| ≲ 10¹⁰` and should be tightened proportionally for
    larger calibration sets.
- **solve_verify_split** (round 3, docstring-only — no logic change):
  - `power_law_score_proxy` shape descriptor and internal helper
    comment now state explicitly that paper §5.2 specifies the
    *scaling* of the optimal allocation `S_opt(C), V_opt(C)`, not a
    closed-form `SR(S, V)` surface. Treating `S^a · V^b` as a ranking
    function over arbitrary `(S, V)` pairs is a caller-defined
    heuristic — monotonicity (direction) does not imply order-preserving
    rank vs. true accuracy. Use as a tiebreaker / sanity check, not an
    SR estimator; prefer `compare_paths.delta_*` or observed accuracy
    for cross-path comparison.

## [0.20.0] - 2026-04-25

### Added

- **`particle_infer`** (Selection): step-wise Particle Filter
  inference-time scaling per Puri, Sudalairaj, Xu, Xu, Srivastava 2025
  ("A Probabilistic Inference Approach to Inference-Time Scaling of
  LLMs using Particle-Based Monte Carlo Methods", arXiv:2502.01618).
  State-Space Model formulation of LLM generation (§2 emission =
  Bernoulli(r̂)). N particles advance one reasoning step at a time,
  each scored by a caller-injected Process Reward Model (PRM), then
  softmax-resampled every step (paper §3.1 Algorithm 1); a
  caller-injected Outcome Reward Model (ORM) picks the final answer
  (§3 end). Aggregation modes `product` / `min` / `last` / `model`
  (§3.2). Pure-Lua helpers (softmax with max-shift, multinomial CDF
  resample, ESS, `log_from_bern` / `logit_from_bern`) are exposed
  under `M._internal` for test injection.
- **`particle_infer` `weight_scheme` INJECT** (paper-faithful default):
  - `weight_scheme = "log_linear"` (default): `w_t = log r̂_t`,
    `softmax(w) = r̂/Σr̂` — matches paper §3.1 Algorithm 1 and
    Theorem 1 target `∝ ∏_t r̂_t`.
  - `weight_scheme = "logit_replace"` (opt-in, **NOT paper-faithful**):
    `w_t = logit r̂_t`, `softmax(w) = odds/Σodds` — mirrors the
    authors' reference implementation
    (`github.com/Red-Hat-AI-Innovation-Team/its_hub`,
    `particle_gibbs.py: _inv_sigmoid + _softmax(log_weights[-1])`).
    Samples from an odds-normalized distribution; Theorem 1
    unbiasedness proof does not cover this path. Produces sharper
    "kill-the-runt" concentration via odds divergence at r̂→1.
- **E2E script** `scripts/e2e/particle_infer.lua`: arithmetic CoT
  (23+47=70) task, N=3 particles × max_steps=2, deterministic
  pure-Lua PRM/ORM heuristics. `max_tokens(300000)` guard
  accommodates `particle_infer`'s step-wise pause/continue loop
  (6 pauses × ~20K in-context tokens per turn under agent-block's
  ReAct full-history re-send). Prompt explicitly forbids
  `alc_status` / `alc_log_view` diagnostic probes to avoid 3×19K
  redundant context re-sends.

## [0.19.0] - 2026-04-24

### Added

- **`conformal_vote`** (Governance / Selection): conformal social
  choice decision gate applying distribution-free prediction sets to
  ensemble votes for calibrated abstention.
- **`dci`** (Deliberation): Deliberative Collective Intelligence
  pkg implementing the DCI-CF 8-stage protocol.
- **`smc_sample`** (Decoding / Selection): block-SMC reward-guided
  LLM decoding with paper-faithful weight-update ordering, selective
  MH moves, and INJECTABLE overrides for transition / reward kernels.
- **`alc_shapes.M.VERSION`**: declared semver string used by algocline
  core `>= 0.25.1`'s `alc_hub_dist` resolver to drive the
  `M.meta.alc_shapes_compat` range check.
- **`alc.toml` at repo root** with `[hub]` / `[hub.context7]` /
  `[hub.devin]` sections. Project-specific `extra_rules` (context7) and
  `extra_repo_notes` (devin) migrated verbatim from the retired Lua
  configs. Schema references and precedence rules are documented in
  algocline core's `docs/hub-gendoc-config.md`.

### Changed

- **Migration — switch doc generation to algocline core `alc_hub_dist`.**
  With algocline core `>= 0.26` absorbing `narrative` / `llms` /
  `context7` / `devin` / `luacats` projections and driving config via
  `alc.toml`, bundled-side CLI generation is fully subsumed. The
  canonical pre-publish flow is now a single MCP call:

  ```
  alc_hub_dist(
    source_dir   = ".",
    output_path  = "hub_index.json",
    out_dir      = "docs",
    projections  = ["hub", "narrative", "llms", "context7", "devin", "luacats"],
    lint_strict  = true,
  )
  ```

  `config_path` is no longer needed — core auto-explores `alc.toml` at
  `source_dir` and merges `[hub] / [hub.context7] / [hub.devin]` with
  its embedded default rules / repo_notes via the 3-tier precedence
  chain documented in the core-side `docs/hub-gendoc-config.md`.

  See `just dist` / `just dist-auto` for shell entry points.

### Removed

- **`tools/docs/context7_config.lua`** / **`tools/docs/devin_wiki_config.lua`**.
  The Lua configuration files are retired per the v0.26 design
  principle that hub-level `config_path` must be TOML (Lua files are
  rejected as a typed error). The project-specific content is now
  expressed declaratively in `alc.toml`.
- **`tools/gen_docs.lua` + private helpers.** `tools/gen_docs.lua`,
  `tools/docs/json.lua`, `tools/docs/lint.lua`, `tools/docs/list.lua`,
  `tools/docs/projections.lua`, `scripts/gen_shapes_luacats.lua`, and
  `tests/test_gen_docs.lua` are removed. Their responsibilities are
  fully covered by algocline core's embedded generator. `tools/docs/`
  retains `entity_schemas.lua`, `extract.lua`, and `pkg_info.lua`
  (still consumed by tests / `alc_shapes`).
- **`justfile` recipes** `gen-docs`, `gen-docs-lint`, `gen-shapes`,
  `verify-shapes`, `gen-docs-strict` removed. `just dist` / `just
  dist-auto` (core-driven) replace them.

## [0.18.0] - 2026-04-21

### Added

- **`tests/test_gen_docs.lua`** (+16 tests): unit coverage for the new
  `tools/docs/json.lua` decoder (RFC 8259 subset, `\uXXXX` transcoding,
  `null` sentinel) and `tools/docs/list.lua` enumerator (schema_version
  gate, dir-existence validation, error message shape).
- **README.md — Architecture section**: codifies the three architectural
  roles (Strategy / Frame / Computation) and their I/O contract split,
  with a Roster enumerating current Frame and Computation pkgs.
  Clarifies that architectural role is **orthogonal** to functional
  category (a Computation pkg may appear under Selection / Aggregation /
  Attribution / Governance / Validation sections but its contract stays
  direct-args). Adds rule-of-thumb for new pkgs: `alc.llm` call →
  Strategy (ctx-threading, `input`); pure calculation → Computation
  (direct-args, positional `args`). Frames require explicit design review.
- **README.md — Direct-args mode subsection**: documents the positional
  `args` contract used by Computation pkgs (`sprt`, `kemeny`, `condorcet`,
  `scoring_rule`, `shapley`, etc.) and its mutual exclusivity with
  `input` per entry (enforced by `alc_shapes.spec_resolver`).

### Changed

- **`hub_index.json` / `docs/hub/index.json` schema**: regenerated with
  algocline 0.25.0's typed `PackageSource`. The `source` field is now a
  tagged object (`{"type":"unknown"}` / `{"type":"git","url":"...","rev":null}`
  等) instead of a plain string. algocline 0.25.0+ has a read-compat
  shim that accepts both forms, so older 0.24.x clients keep working
  unchanged; the upgrade path for users is `alc init` to re-pull this
  tag. This release is the synchronized counterpart to algocline 0.25.0,
  which moves the on-disk `~/.algocline/installed.json` / `hub_index.json`
  / `alc_hub_info` / `alc_hub_search` wire format to the same tagged
  representation.
- **`tools/gen_docs.lua` reframed as a publish-artifact generator over
  `hub_index.json`**: package enumeration is now driven by
  `hub_index.json.packages[].name` (via a minimal pure-Lua JSON decoder
  at `tools/docs/json.lua` and an index reader at `tools/docs/list.lua`).
  Filesystem walk (`ls {repo}/*/init.lua`) and the `[skip]` log path
  for non-pkg directories are removed — non-pkg dirs like `alc_shapes`
  are already excluded upstream by `alc_hub_reindex`, so gen_docs never
  sees them. The tool is analogous to `cargo-dist`: it projects release-
  facing artefacts from an upstream-produced manifest, it is not a
  per-pkg API reference generator (for local pkg lookup use `alc_info`
  / `alc_hub_search` or read the source). `--hub-index=PATH` flag added
  to override the default `{repo_root}/hub_index.json`.

### Removed

- **`alc_shapes` silently excluded from `hub_index.json`** (110 → 109 pkg).
  `alc_shapes` has no `M.meta.name` (it is a type-DSL library, not a
  packaged strategy). Prior Rust indexes fell back to the directory name
  (`name="alc_shapes"` with empty version/description/category); the
  typed indexer drops the fallback so such dirs are skipped outright.
  No user-visible count change — `README.md` and `docs/narrative/` were
  already at 109, and `tools/gen_docs.lua` no longer sees non-pkg dirs
  at all.
- **`tools/gen_docs.lua` filesystem-scan and `[skip]` logging path**:
  subsumed by the hub_index one-source model described above.

### Fixed

- **Stale/missing `hub_index.json` is now a hard error in gen_docs**:
  previously a filesystem walk would silently produce partial docs if
  new pkgs were added without reindexing; now `gen_docs.lua` requires
  a fresh, well-formed `hub_index.json` with `schema_version` =
  `"hub_index/v0"` and fails loudly on drift (index lists a pkg whose
  `{pkg}/init.lua` has been removed). Prevents silent divergence
  between the published catalogue and the generated narrative docs.

## [0.17.0] - 2026-04-19

### Added

- **[flow](flow/) v0.2.0 — Session-spanning bound APIs**: `flow.token_wrap_bound(st, opts)` / `flow.token_verify_bound(st, slot, result, opts?)` / `flow.llm_bound(st, opts)`. State-lifecycle wrappers that persist the verify-side `req` under `state.data._flow_req_<slot>` so the call-and-verify cycle can straddle an `alc.llm` yield or a full session restart. Error semantics inherit from the underlying primitives (non-symmetric, matches design proposal §3.3): `wrap_bound` asserts on invalid input; `verify_bound` returns bool with auto-delete on success (opt-out via `opts.keep=true`) and retains the record on mismatch; `llm_bound` raises on token/slot echo mismatch with auto-rollback so a retry starts clean. Persist shape is intentionally asymmetric (`llm_bound` omits prompt/payload since retry is driver-policy, not primitive); hard errors from `alc.llm` leave `_flow_req_<slot>` persisted so the driver's resume path can clean up (auto-rollback fires on echo mismatch only). Resume-friendly: a `wrap_bound` from session A is visible to a `verify_bound` in session B as long as the same FlowState id is resumed. Unit-tested end-to-end including session-boundary resume, hard-error residue, slot overwrite, and multi-slot independence (76/76 flow tests pass, 29 new).

### Fixed

- **`tests/test_flow.lua` REPO resolution under worktree**: switched from `os.getenv("PWD") or "."` to the canonical `repo_root_from_package_path()` pattern (mirrors `tests/test_gen_docs.lua` §23–33). Under a worktree run, `mlua-probe-mcp` inherits the main-repo PWD, so the old PWD-based `REPO` silently shadowed worktree code with `main_repo/flow/init.lua` and produced false-green results for any new API added in the worktree. Same class of silent-drop bug flagged in the 2026-04-18 `tests/test_abm.lua` accident comment.

### Changed

- **DRY refactor on flow session-spanning APIs**: hoisted the `_flow_req_` key prefix to `flow.state.REQ_PREFIX` as the single source of truth (was duplicated in `flow/token.lua` and `flow/llm.lua` as local constants; a rename on one side without the other would have split wrap-side and verify-side into disjoint namespaces with the mismatch surfacing only at runtime as "no persisted req for slot"). Extracted `append_flow_tags` private helper in `flow/llm.lua` so the `[flow_token=...][flow_slot=...]` byte pattern is not duplicated across `flow.llm` and `flow.llm_bound` (drift would convert every call into a silent fail-open pass).

## [0.16.0] - 2026-04-19

### Added

- **[flow](flow/) Frame substrate** (v0.1.0 debut): Light Frame over `alc.state` exposing two primitives — `FlowState` (persistent KV with resume) and `ReqToken` (random-nonce request correlation, AMQP `correlation_id` idiom) — plus `flow.llm` sugar for LLM calls with slot+token echo verification. Module-level pure-function API (`state_new / state_key / state_get / state_set / state_save / token_issue / token_wrap / token_verify / llm`). No `M.run` by design: `flow` is a substrate, not an orchestrator — the driver loop stays in user code (Functional Core / Imperative Shell). Identity `deep_equal` check on resume prevents silent parameter drift. Fail-open token verification keeps existing bundled pkgs usable without rewrite; opt-in v1 contract (see `flow/doc/contract.md`) tightens per-call verification.
- **[recipe_deep_panel](recipe_deep_panel/) Recipe** (v0.1.0 debut): production-grade 5-stage deep-reasoning pipeline composed on top of flow — `condorcet_gate` (Anti-Jury guard, p≥0.5) → fan-out of N × `ab_mcts` → `ensemble_div` (decomposition when ground_truth available) → `condorcet.prob_majority` plurality → `calibrate`. Inputs guarded: `p_estimate` required (no default), `n_branches` odd ≥3, `approaches` uniqueness. Identity = `{task, n_branches, budget, max_depth}` covers resume replay. Stage 1 abort path shares the unified result shape. `M.verified.stage_coverage` records per-stage verification status (2 stages verified with real LLM, 3 stages flagged `not_exercised` with `reason` + `to_verify` — no fabricated claims).
- **`AlcResultDeepPaneled` shape** in `alc_shapes` (22 fields, `open=true`): machine-contract for recipe_deep_panel result. LuaCATS projection in `types/alc_shapes.d.lua`.
- **`justfile` recipes** `gen-docs`, `gen-docs-lint`, `gen-docs-strict` added. Commit / release gates use `gen-docs-strict` to fail on V0 convention lint errors.
- **Integration test suites** under `tests/flow/`: `test_integ_swarm_mcts.lua` (fan-out + consensus + commit), `test_integ_gate_scale.lua` (5-gate Coding-pipeline chain with retry + resume), `test_integ_ensemble_vote.lua` (bare `flow.llm` × N + pure-compute + regen loop-back). Each file documents the flow-scaling property it exercises in a header comment.
- **Unit test suites** `tests/test_flow.lua` (51 assertions across util / state / token / llm / meta) and `tests/test_recipe_deep_panel.lua` (41 assertions across meta / ingredients / internal vote-tally / input validation / Stage 1 abort / main path / token tampering / resume). Full MCP run: 109/109 pass.
- **[sprt](sprt/) Sequential Probability Ratio Test primitive** (v0.1.0 debut): Wald 1945 / Wald & Wolfowitz 1948 SPRT as a standalone observe/decide gate on any Bernoulli stream. `sprt.new(p0, p1, alpha, beta)` → `observe(outcome)` / `decide()` → `"accept_h0" | "accept_h1" | "continue"`. Auxiliary `sprt.expected_n_envelope(n_obs, p0, p1, alpha, beta)` documented as simplified numerator-only Wald form (not exact E[N]). Verified via alpha/beta grid Monte Carlo suite (`tests/test_sprt.lua`, 33 assertions).
- **[recipe_quick_vote](recipe_quick_vote/) Recipe** (v0.1.0 debut): fills the Quick slot between `recipe_safe_panel` (fixed n≈8) and `recipe_deep_panel` (per-branch MCTS ≈52 calls). Loops sc-style samples under a Wald SPRT gate and exits as soon as the declared (α, β) error budget permits. Parameters `p0 / p1 / alpha / beta / min_n / max_n`. Minerva-style numeric normalize (`"42.0"` → `"42"`, `"1,000"` → `"1000"`, `"144/12"` → `"12"`, de_DE decimal guard preserves `"1,5"`). `needs_investigation` fires on `"truncated"` only (rejected is conclusive). Verified via 25 unit tests, E2E single-case (17+25=42, confirmed @ n=8, 16 calls, log_lr=3.29) and scenario-eval vs `math_basic` (7/7 pass_rate=1.0, 112 calls, all confirmed @ n=8).
- **`AlcResultQuickVoted` shape** in `alc_shapes`: machine-contract for recipe_quick_vote result (`sprt_decision` / `log_lr` / `n_samples` / `outcome ∈ {confirmed, rejected, truncated}` among fields). LuaCATS projection in `types/alc_shapes.d.lua`.

### Fixed

- **Strict-review hardening C1 (`flow.util.parse_tag`)**: switched from first-match (`text:match`) to LAST-match (`text:gmatch` drained to the last hit). `flow.llm` appends its `[flow_token][flow_slot]` pair to the prompt end, and prompts routinely embed a prior gate's output carrying its own echoed tags; first-match would hit the stale pair and raise a spurious mismatch against the real LLM.
- **Strict-review hardening C2 (`flow.util` PRNG seed)**: fold 4 bytes from `/dev/urandom` (when available) into `math.randomseed` input. Prevents two independent processes starting within the same `os.time()` tick from colliding on near-zero `os.clock()` and emitting identical token streams. Windows native Lua retains the `time + clock` fallback.
- **Strict-review hardening C3 (`flow.token.wrap`)**: `_flow_token` / `_flow_slot` are reserved keys owned by flow — passing a payload that already contains either now raises an assert error instead of silently overwriting caller data.
- **Strict-review hardening C4 (`flow.token.verify`)**: documented why the leading `_token` parameter is intentionally unused (API symmetry with `wrap`, reserved hook for future token rotation).
- **Strict-review hardening C5 (`flow/doc/README.md`)**: added an explicit table contrasting `token_verify`'s boolean fail-open with `flow.llm`'s error-on-mismatch semantics, so the asymmetry is not read as an inconsistency.
- **Strict-review hardening A-E on sprt / recipe_quick_vote**: (A) regenerate missing `AlcResultQuickVoted` in `types/alc_shapes.d.lua`; (B) `sprt.observe` now explicitly rejects `nil` outcome with a test lock-in; (C) `sprt.simulate` docstring warns about `math.random` global mutation; (D) `expected_n_envelope` describes simplified numerator-only Wald form, not exact E[N]; (E) `recipe_quick_vote.min_n` docstring disambiguates leader + k rule.
- **Strict-review hardening F1-F10 on sprt / recipe_quick_vote**: (F1) `sprt.expected_n_envelope` docstring covers arbitrary-p acceptance; (F2) `stage_coverage` evidence label pinpoints Monte Carlo suite; (F3) `needs_investigation` fires only on `"truncated"` (rejected is conclusive); (F4) normalize canonicalizes `"42.0"` / `"1,000"` / `"144/12"` after minerva_math BP (EleutherAI lm-evaluation-harness 3-pass canonicalize); (F5) `DIVERSITY_HINTS` cycle behavior documented in caveats; (F6) dead `type(x) == "number"` branch in `to_bernoulli` removed; (F7) alpha/beta < 0.5 practical cap rationale inlined; (F8) zero-drift `p` yields `nil` from `expected_n_envelope` (test lock-in); (F9) truncated-path trace uses consistent `log_lr` labels; (F10) `M.verified` lifecycle policy documented.
- **E2E runner stability (`scripts/e2e/common.lua`)**: wire `max_tokens_budget` through to `agent.run()` (previously silently dropped), bump default `max_tokens` 1024 → 4096 for multi-case final reports, lift `recipe_quick_vote_eval.max_tokens` 4096 → 8192 (4096 still truncated on real runs). Addresses the bundled side of the final-report truncation bug (symptom: `reports_card_id` grader FAIL on 2026-04-19_124616 run). Upstream agent-block ReAct O(N²) history growth is tracked separately in issue `1776571635-95433`.

### Changed

- **Package count**: `README.md` "## Packages (105)" → "## Packages (109)" (flow + recipe_deep_panel + sprt + recipe_quick_vote added). `hub_index.json` / `docs/hub/index.json` package_count 106 → 110 (hub counts include `alc_shapes`, README count excludes it per established convention).

## [0.15.0] - 2026-04-19

### Added

- **V0 SoT docs pipeline** (`tools/gen_docs.lua` + `tools/docs/*`): single-source-of-truth pipeline that extracts `PkgInfo` from each pkg's `init.lua` + `M.meta` / `M.spec` and projects it into narrative Markdown / machine-contract JSON / LLM-facing indexes. No legacy / fallback path — the SSoT is the pkg source. Byte-deterministic output (sorted keys, stable anchor resolution).
  - `tools/docs/pkg_info.lua`: Entity layer (`PkgInfo` / `Shape` / `TypeExpr` / `Section` / `Identity` / `Narrative`).
  - `tools/docs/extract.lua`: reads pkg → builds `PkgInfo` (deterministic anchor-collision suffix `-2` / `-3`).
  - `tools/docs/projections.lua`: Entity → String (narrative, llms index / full, hub entry JSON, context7 manifest, devin wiki manifest). Shape-as-Data kind dispatch for both `input` and `result`.
  - `tools/docs/lint.lua`: V0 convention violation detection (`W_FAKE_LABEL`, `E_RESULT_CONFLICT`, `E_PARAMETERS_CONFLICT`).
  - `tools/docs/entity_schemas.lua`: Entity registry expressed as `alc_shapes` Schema-as-Data (`open=false`, `Section.level = T.one_of({2,3})`, `AlcSchema = {kind=T.string}`). `extract.build_pkg_info` now `assert_dev`s PkgInfo against this registry in dev mode.
  - `tools/gen_docs.lua`: CLI entry (`--lint` / `--strict` / `--lint-only` / `--hub` / `--context7` / `--devin`).
  - `docs/docstring-convention.md`: V0 docstring convention spec.
- **Generated docs artefacts** (byte-deterministic, regenerated on every pipeline run):
  - `docs/narrative/*.md` (106 files): per-pkg narrative Markdown with YAML frontmatter + `## Usage` / `## Behavior` / `## Parameters` / `## Result` sections. `T.ref`-based pkgs resolve through the alc_shapes registry so ref pkgs get a symmetric Result section (previously inline-only).
  - `docs/llms.txt` + `docs/llms-full.txt`: aggregated LLM-facing index and full dump.
  - `docs/hub/*.json` (106 per-pkg machine-contract JSON): `{name, version, category, description, narrative_md, input_shape, result_shape}`. Kind-tagged `input_shape` / `result_shape` share a single walker — unblocks `alc_hub_info` chain dispatch, LLM context injection with structural semantics, and cross-pkg type lint.
  - `docs/hub/index.json` (106 pkgs aggregate, `schema_version = "hub_index/v0"`): produced via `alc_hub_reindex`.
  - `context7.json` (repo root): Context7 public-schema manifest (`$schema` + `folders=["docs/narrative"]` fixed by projection, `projectTitle` / `description` / `rules` from `tools/docs/context7_config.lua`).
  - `.devin/wiki.json`: DeepWiki public-schema manifest. `repo_notes` point consumers at `docs/narrative` as the canonical source. Page limits and content length validated at projection time.
- **`alc_shapes` DSL extensions**:
  - `T.ref(name)`: named registry reference (Malli `[:ref :name]` analogue) — resolves lazily so forward references are legal.
  - `S.instrument(mod, entry_name, spec?)`: Malli-style producer-wrap self-decoration. Reads `M.spec.entries[entry_name].{input, result}` and replaces the entry with a dev-gated validator. Bundled pkgs now self-decorate at module tail via `M.run = require("alc_shapes").instrument(M, "run")` instead of inlining `assert_dev`.
  - `S.spec_resolver` (public API): unified resolver for typed (`M.spec` declared) and opaque (external / experimental) pkgs. `resolve(pkg)` → `ResolvedSpec{kind="typed"|"opaque"}`; `run(pkg, ctx, entry_name?)` runs the entry with typed-only pre/post `assert_dev` (dev_off / opaque pass-through).
  - **Direct-args mode** for library-style pkgs: `spec.entries.{entry}.args` (positional array of shapes) validates each caller-supplied arg against `args[i]`, validates the raw return against `result` (no `ret.result` unwrapping). `input` and `args` are mutually exclusive per entry. Multi-return preserved via `table.pack` / `table.unpack` — library functions returning `(ok, reason)` / `(bool, string)` tuples no longer drop 2nd+ returns through the wrapper.
  - **Schema-as-Data invariants**: single AST / persistable (every kind's state lives in `rawget`-readable fields) / reflectable (`kind` as universal dispatch discriminator). `tests/test_alc_shapes_persist.lua` proves every consumer (`check` / `fields` / `walk` / `luacats` / ref resolution) works after deep metatable-stripping.
  - **`opts.registry` (Schema-as-Data registry)**: `S.check` / `S.assert` / `S.assert_dev` accept `opts.registry` as a plain `{name → schema}` table. `T.ref` handler does `rawget(registry, name)` — no closure invocation. Closures and non-table opts are loud-rejected. Default registry stays `require("alc_shapes")`.
  - **DSL hardening C1-C6**: (C1) `T.array_of(T.x:is_optional())` rejected at construction time (Lua `#` cannot detect holes); described-wrapper is peeled through. (C2) LuaCATS codegen expands `T.discriminated` variants as inline union literals; `array_of(union)` renders as `(A|B)[]`. (C3) `T.shape` / `T.discriminated` fields / variants are shallow-copied for Schema-as-Data immutability. (C4) `T.discriminated` variants must declare the tag field (fail loud at construction). (C5) `T.one_of` rejects duplicate literals with type-sensitive keys (string `"1"` ≠ number `1`). (C6) `AlcSchema.kind` is a whitelist of known kinds.
- **`M.spec.entries.{entry}.{input, result, args}` V0 I/O contract**: replaces the earlier `M.meta.{input_shape, result_shape}`. Clean break (pre-release, no compat shim). 106 bundled pkgs migrated across Phase 1–8 + Phase 3.5.
- **Instrument rollout across ~95 packages** (Phases 1 through 8 + 3.5):
  - **Phase 1** (`cot`): first inline-shape self-decoration.
  - **Phase 2-a / 2-b / 2-c / 2-d / 2-e / 2-f / 2-g-1/2/3**: reasoning / refinement / planning / generation / preprocessing / optimization / reasoning tier 2 (~19 pkgs).
  - **Phase 3-a / 3-b / 3-c / 3-d**: selection / mixed (12 pkgs).
  - **Phase 3.5-a / 3.5-b / 3.5-c**: library-style pkgs via direct-args mode (10 pkgs: `bft`, `eval_guard`, `cost_pareto`, `inverse_u`, `condorcet`, `shapley`, `mwu`, `scoring_rule`, `kemeny`, `ensemble_div`).
  - **Phase 4-a / 4-b / 4-c / 4-d**: validation / mixed (12 pkgs).
  - **Phase 5-a / 5-b / 5-c / 5-d**: orchestration (11 pkgs including `orch_*`, `moa`, `php`, `triad`, `pbft`, `deliberate`, `dissent`).
  - **Phase 6-a / 6-b**: ABM (7 pkgs: `boids_abm`, `epidemic_abm`, `evogame_abm`, `opinion_abm`, `schelling_abm`, `sugarscape_abm`, `coevolve`). `abm/mc.lua` + `abm/sweep.lua` expose `M.shape(...)` helpers as SSoT for the suffix-expanded MC / sweep result layout. `hybrid_abm` kept un-instrumented (ctx-supplied shapes unknowable at load time — un-instrument is principled).
  - **Phase 7-a / 7-b / 7-c / 7-d**: routing / intent / meta-reasoning / misc (18 pkgs).
  - **Phase 8-A**: search / tree (6 pkgs: `ab_mcts`, `mcts`, `rstar`, `aco`, `qdaif`, `p_tts`) with native-DSL-only nested shapes (no opaque `T.table`).
- **`:describe()` field-level annotations on 35 packages** (Phase 9-a/b/c): surfaces semantics at the spec layer for runtime introspection via `S.instrument`.
  - **Phase 9-a (Category B, 6 ABM pkgs)**: promotes head-docstring `ctx.X?` comments to field-level `:describe()` on `params_shape` (internal post-defaults hash) and `run.input`. Fills the now-empty description column in each ABM pkg's narrative.md Parameters table.
  - **Phase 9-b (Category A, 9 library-style pkgs)**: attach `:describe()` to positional `args` and result fields. DRY via local constants (`N_DESC` / `F_DESC` / `PREDS` / `TARGET` / `WEIGHTS`).
  - **Phase 9-c (Category C, 10 inline-shape pkgs)**: selective describes on domain-specific / statistical-term fields only (Beta α/β, LCB/UCB, V̂, Friedman `rank_sum` / `Q` / `χ²` critical, MBR score, inverse-U trend labels). Self-evident names (`index`, `rank`, `score`, `text`) remain un-described per Category C rationale.
- **Test additions**:
  - `tests/test_alc_shapes_instrument.lua` (133 cases): direct-args mode, multi-return preservation, nested dispatch, per-pkg self-decoration.
  - `tests/test_alc_shapes_persist.lua` (7 cases): Schema-as-Data metatable-strip survival across all consumers.
  - `tests/test_entity_schemas.lua` (136 cases): Entity registry accept/reject, composed PkgInfo nested-path reporting, conformance sweep over every `*/init.lua` that declares `M.meta`.
  - `tests/test_gen_docs.lua` (87 cases): extract / shape / projections / lint / e2e golden / context7 / devin wiki / ref resolution.
  - `tests/test_spec_resolver.lua` (22 cases): typed / opaque / inline-fixture / real-pkg (`cot`, `calibrate`) resolve, Schema-as-Data invariant.

### Changed

- **`M.meta.{input_shape, result_shape}` → `M.spec.entries.run.{input, result}`** (clean break, pre-release): 9 bundled pkgs migrated in the initial refactor (`sc`, `panel`, `calibrate`, `cot`, `rank`, `listwise_rank`, `pairwise_rank`, `recipe_safe_panel`, `recipe_ranking_funnel`); remaining 95+ pkgs migrated across Phases 1–8 + 3.5. `types/alc_pkg.d.lua`: `AlcMeta.shape` removed; `AlcSpec` / `AlcSpecEntry` / `AlcSpecCompose` classes added.
- **Caller-wrap (`spec_resolver.run`) and producer-wrap (`instrument`) coexist**: bundled pkgs prefer `instrument` — producer is the single source of truth for its own contract; every caller (direct, `SR.run`, recipe ingredient) inherits the check for free.
- **`alc_shapes` cycle guard** (`alc_shapes/check.lua`): `S.check` now enforces a recursion depth cap of 256. Previously a schema self-loop (`A = T.ref("A")`) or a value-side self-reference traversed through a recursive schema (e.g. linked-list `node.next = node`) could recurse forever in the `ref` / `shape` handlers. Raises `recursion depth exceeded at <path>` with JSONPath at the cap site.
- **`alc_shapes` LuaCATS codegen** (`types/alc_shapes.d.lua`): Nested `T.shape(...)` fields are inline-expanded as LuaLS table type literals (`{ field: type, ... }` / `{ ... }[]`) instead of `table` / `table[]`. 11 of 13 previously-opaque `table`-typed fields across 9 registered shapes are now walkable for IDE completion. Field order alphabetical, optional fields carry `?` inside inline literals. `T.discriminated` still renders as `table` (union codegen deferred via C2 for stages fields only). Class / field names unchanged — strict strengthening, not a break.
- **BREAKING (`docs/hub/*.json` wire)**: `result_shape` is now a kind-tagged JSON object (`type_to_json` form) instead of a human-readable string. Consumers must switch from string match to `kind` dispatch:
  - `T.ref(name)` → `{"kind":"label","name":"..."}`
  - inline `T.shape(...)` → `{"kind":"shape","shape":{...}}`
  - other schemas → `{"kind":"primitive|array_of|map_of|one_of|discriminated",...}`

  `input_shape` and `result_shape` share the same discriminated wire format, so a single walker processes both. Role split preserved: `docs/hub/*.json` is the machine contract (structured); `docs/narrative/*.md` YAML frontmatter `result_shape:` remains a human-readable string.
- **`alc_shapes.spec_resolver.run` ctx-threading**: aligned with `AlcCtx` convention.
- **Reserved-name list**: extended with `instrument` and `spec_resolver` (shape-name shadow prevention).

### Fixed

- **EE4 (`docs/hub/*.json` wire)**: see BREAKING above — pre-fix, inline `T.shape` result_shapes were serialized as human-readable strings that downstream consumers could not walk. Kind-tag dispatch lifts that ceiling.
- **EE5 (hardcoded `require("alc_shapes")` in ref handler)**: replaced via `opts.registry` plumbing — unblocks `entity_schemas.lua` as an independent namespace.
- **EE6 (`T.shape` open default)**: Layer contract documented — open default is a Layer-2 convention, not a primitive default.
- **EE7 (`S.assert` on nil schema)**: loud-fails with a clear error instead of silently accepting.
- **EE8 (`S.check` on ref cycles)**: addressed via the cycle guard above.
- **ABM test harness (`tests/test_abm*.lua`)**: removed `REPO = os.getenv("PWD")` + manual `package.path` preamble. Per `README.md §"Adding a new test file"`, the MCP harness sets `package.path` via `search_paths=[REPO]`; manual prepend in worktree context pointed at the parent repo, which silently shadowed worktree code and produced false-green passes. ABM result shapes (Phase 6-a-fix) now use `abm.mc.shape(...)` / `abm.sweep.shape()` helpers instead of opaque `T.table`, giving callers actual discoverability over MC / sweep suffix keys.
- **`docs/narrative/*.md` ref-based pkgs missing Result section** (Option D): `projections.lua` now resolves `T.ref` via the alc_shapes registry and emits Result symmetrically with Parameters. Unknown refs degrade silently (no Result section) to mirror `type_to_json`'s existing tolerance. `E_RESULT_CONFLICT` lint rule added for symmetry with `E_PARAMETERS_CONFLICT`. Hub JSON still carries `{kind:"label", name:...}` — resolution is narrative-projection-only (machine contract unchanged).
- **`evogame_abm.payoff_matrix` describe**: spot fix — now carries a proper English `:describe()` at the shape layer (previously undescribed, then initially committed with a Japanese string that violated the English-only shape-convention rule).

## [0.14.0] - 2026-04-17

### Added

- **alc_shapes**: Result Shape Convention — DSL-based schema definitions for `ctx.result` validation across packages.
  - **P0**: Core library (`alc_shapes/`) — DSL combinators (`T.shape`, `T.array_of`, `T.one_of`, `T.string`, `T.number`, `T.boolean`, `T.table`, `T.any`), validator (`check`/`assert`/`assert_dev`), reflection (`fields`/`walk`), LuaCATS codegen (`class_for`/`gen`). Dev-mode assert via `ALC_SHAPE_CHECK=1`. Deterministic field-name-sorted error reporting. Reserved-name guard for "any". `types/alc_shapes.d.lua` auto-generated from SSoT (`alc_shapes/init.lua`).
  - **P1**: Shape definitions for `sc` (voted), `calibrate` (calibrated + assessed), `panel` (paneled) — producer `meta.result_shape` declarations + `assert_dev` self-defense.
  - **P2-P4**: Shape definitions for `rank` (tournament), `listwise_rank` (listwise_ranked), `pairwise_rank` (pairwise_ranked), `recipe_ranking_funnel` (funnel_ranked), `recipe_safe_panel` (safe_paneled). Nested shapes with `ranked_item` variable reuse for DRY.
  - **DSL extensions**: `T.map_of(K, V)` for key/value typed maps (tableshape `types.map_of` / Zod `z.record()` equivalent), `T.discriminated(tag, variants)` for tag-dispatched heterogeneous unions (Zod `z.discriminatedUnion` equivalent). Resolves `T.table` fallbacks in `vote_counts` (→ `map_of(string, number)`) and `stages[]` (→ `discriminated("name", {...})` with 6 funnel variants + 7 safe_panel variants).
- **alc_shapes/README.md**: DSL API reference (combinators, validator, reflection, codegen, type mappings).
- **tests/test_alc_shapes_t.lua**: 34 tests (DSL combinator structure, input validation, rawget invariants).
- **tests/test_alc_shapes_check.lua**: 42 tests (primitives, shape, array_of, one_of, map_of, discriminated, assert behavior, determinism, reserved-name guard, dev-mode).
- **tests/test_alc_shapes_luacats.lua**: 20 tests (class_for field rendering, type mappings, gen output).
- **tests/test_alc_shapes_reflect.lua**: 11 tests (fields extraction, walk traversal, map_of/discriminated descent).
- **tests/test_shapes_conformance.lua**: 44 tests (meta declarations for 8 packages, mock data validation for 9 shapes, open-table tolerance).

### Changed

- **README**: added Result Shape Convention section with link to `alc_shapes/README.md`, updated "Writing your own package" with `result_shape` declaration.

## [0.13.0] - 2026-04-16

### Added

- **2 new `recipe` category packages** composing foundations into end-to-end strategies:
  - **[recipe_safe_panel](recipe_safe_panel/)**: safety-first panel QA. Composes `condorcet` (panel sizing + Anti-Jury), `sc` (self-consistency), `inverse_u` (optional scaling check), `calibrate` (confidence). Auto `M.verified.alc_eval_runs` recorded math_basic pass_rate = 1.0 (7/7) at 8 LLM calls/case under `max_n=3`.
  - **[recipe_ranking_funnel](recipe_ranking_funnel/)**: listwise → pairwise ranking funnel. Composes `listwise_rank` (coarse screening) and `pairwise_rank` (precise finalization). Verified N=8 population ranking: 7 calls vs naive all-pairs 56 (87% savings), top-1 correct.
- **`M.verified` convention**: recipe packages expose `theoretical_basis` + measured `e2e_runs` / `alc_eval_runs` only — no unverified claims. Populated empirically via agent-block E2E harness.
- **scripts/e2e/ agent-block harness** (`common.lua` + per-recipe drivers): runs full ReAct loop against real `alc.llm` / `alc_eval`, persists graded results to `workspace/e2e-results/<timestamp>/<name>.json`.
  - `recipe_safe_panel.lua`: single-case smoke (Capital of Japan)
  - `recipe_ranking_funnel.lua`: single-case smoke (Country population 2026)
  - `recipe_safe_panel_eval.lua`: multi-case `alc_eval` sweep (math_basic, 7 cases) with recipe-level budget caps (`max_n=3`, `scaling_check=false`)
- **justfile**: `just e2e <name>` / `just e2e-all` with `allow-agent` group for task-mcp exposure.
- **tests/test_recipe_ranking_funnel.lua**, **tests/test_recipe_safe_panel.lua**: structural + M.verified validation tests.
- **`calibrate.assess(ctx)`**: 1-LLM-call primitive exposing calibrate's Phase 1 (answer + self-assessed confidence) without threshold/escalation logic. `M.run` now delegates Phase 1 to `assess`, and `recipe_safe_panel` consumes it directly (replacing the earlier `calibrate.run({threshold=0, fallback="retry"})` workaround).

### Changed

- **sc** `ctx.result`: bridge API gap for recipe consumption. Added `answer_norm`, `votes` (normalized), `vote_counts`, `n_sampled`, `total_llm_calls` alongside existing `consensus` / `answer` / `paths`. `total_llm_calls` is now counted during execution (previously hardcoded `2n+1`). Representative `answer` is trimmed + trailing-punctuation-stripped so downstream prompts see "Tokyo" rather than "Tokyo." or "tokyo" depending on sampling order. Normalization = lowercase + whitespace collapse + trailing punctuation strip.
- **calibrate** `ctx.result`: added `total_llm_calls` on every return path — direct = 1, retry = 2, panel = 1 + roles + 1, ensemble = 1 + sc.total_llm_calls. Downstream consumers (e.g. recipe_safe_panel) can now read the accurate count instead of hardcoding.
- **recipe_safe_panel**: reads `cal_result.result.total_llm_calls` when present, with the previous `escalated ? 2 : 1` heuristic as backward-compat fallback.
- **recipe_safe_panel** Stage 3: renamed `inverse_u` → `vote_prefix_stability`. The stage uses a single-run vote prefix as an accuracy proxy, which is NOT the independent-panel inverse-U scenario from Chen et al. NeurIPS 2024; log messages, stage names, and caveats now state this explicitly.
- **recipe_ranking_funnel**: added `ctx.judge_gen_tokens` (default 20) — pairwise judgement calls in Stage 3 (and the N<6 bypass) no longer silently override `ctx.gen_tokens`; short-verdict token cap is now an explicit knob.
- **recipe_ranking_funnel**: `funnel_shape` is now always a 3-element array and documented with explicit semantics (`[S1-input, S2-input, S3-input]`). The N<6 bypass path emits `{N, N, N}` with the same convention so downstream consumers don't need to special-case array length. Bypass path also now reports `naive_baseline_calls` / `naive_baseline_kind` / `savings_percent` fields (previously missing).
- **recipe_ranking_funnel** `ctx.result`: added `naive_baseline_kind = "pairwise_rank_allpair_bidirectional"` so the `savings_percent` denominator is self-documenting; clarified in comments that this over-reports vs single-pass or listwise-only baselines.
- **recipe_ranking_funnel**: documented the `min_window = ceil(N/2)` rule (listwise stride = ceil(window/2), so window ≥ N/2 is needed to keep top items reachable in the final head window) and that Stage 2 intentionally discards Stage 1's ordinal ranking except as a tie-break.
- **recipe_safe_panel**: `1.5x` correlation-adjustment multiplier is now documented as a recipe-level HEURISTIC (not a theorem) corresponding to intra-panel correlation ρ ≈ 0.2–0.3 under the effective-sample-size formula `N_eff = N / (1 + (N-1)·ρ)`.
- **recipe_safe_panel**: odd-enforcement downgrade (when rounding the recommended panel size up would exceed `max_n`, the recipe rounds DOWN by 2 instead) now emits an explicit warn log identifying the downgrade and the `max_n` value needed to avoid it. Previously silent.
- **recipe_safe_panel** caveats: replaced "inverse_u needs ≥ 5 data points" (incorrect) with the accurate statement that Stage 3 requires panel `n ≥ 7` in practice, because the prefix series is sampled only at odd k ≥ 3 (so n=3 gives 1 point, n=5 gives 2 points — both below inverse_u's 3-point threshold).
- **hub_index.json**: regenerated to 105 packages (adds `recipe_ranking_funnel`, `recipe_safe_panel`).
- **README**: package count 103 → 105, added `### Recipes` section under package catalog.

### Fixed

- **recipe_safe_panel**: guarded `condorcet.optimal_n()` returning nil (unreachable target or p == 0.5 edge). Previously the next line (`ceil(recommended_n * 1.5)`) would crash with a nil-arithmetic error. Falls back to `max_n` with a warning log instead.
- **recipe_safe_panel**: validates `ctx.max_n` at entry — errors clearly on `max_n < 3` or non-numeric, eliminating the corner case where the odd-enforcement floor of 3 could silently exceed the configured cap.

## [0.12.0] - 2026-04-13

### Added

- **12 new packages** for multi-agent/Swarm foundations:
  - **[shapley](shapley/)**: Shapley Value — axiomatically unique agent contribution attribution via exact O(2^n) computation or Monte Carlo permutation sampling (Shapley 1953, Ghorbani-Zou AISTATS 2019)
  - **[mwu](mwu/)**: Multiplicative Weights Update — adversarial online agent weight learning with O(√(T ln N)) regret bound, doubling trick, log-space stability (Littlestone-Warmuth 1994, Freund-Schapire 1997)
  - **[kemeny](kemeny/)**: Kemeny-Young rank aggregation — axiomatically unique consensus ranking minimizing total Kendall tau distance. Exact for m ≤ 8, Borda fallback (Kemeny 1959, Young-Levenglick 1978)
  - **[scoring_rule](scoring_rule/)**: Proper Scoring Rules — Brier, logarithmic, spherical scores + ECE calibration measurement for agent prediction quality audit (Brier 1950, Gneiting-Raftery JASA 2007)
  - **[bft](bft/)**: Byzantine Fault Tolerance bounds — quorum thresholds and impossibility validation (Lamport-Shostak-Pease 1982)
  - **[pbft](pbft/)**: Practical BFT — 3-phase LLM consensus with BFT quorum guarantees (Castro-Liskov OSDI 1999)
  - **[condorcet](condorcet/)**: Condorcet Jury Theorem — majority-vote probability, Anti-Jury detection, optimal panel sizing (Condorcet 1785)
  - **[ensemble_div](ensemble_div/)**: Ambiguity Decomposition — Krogh-Vedelsby identity E = Ē − Ā for ensemble diversity measurement (NeurIPS 1995, Hong-Page PNAS 2004)
  - **[aco](aco/)**: Ant Colony Optimization — discrete path search with pheromone update and convergence detection (Dorigo 1996, Gutjahr 2000)
  - **[inverse_u](inverse_u/)**: Inverse-U scaling detection — non-monotonic accuracy-vs-N safety gate (Chen et al. NeurIPS 2024)
  - **[cost_pareto](cost_pareto/)**: Multi-objective Pareto dominance — frontier extraction and strategy selection (Kapoor et al. 2024)
  - **[eval_guard](eval_guard/)**: Evaluation safety gates — self-critique (N2), baseline enforcement (N3), contamination shield (N4)
- **tests/test_foundations.lua**: 79 tests for bft, condorcet, ensemble_div, inverse_u, cost_pareto, eval_guard
- **tests/test_foundations_phase2.lua**: 19 tests for pbft, aco
- **tests/test_shapley.lua**: 38 tests including axiom verification
- **tests/test_mwu.lua**: 24 tests including regret bound verification
- **tests/test_kemeny.lua**: 35 tests including Condorcet consistency axiom
- **tests/test_scoring_rule.lua**: 37 tests including properness verification

### Changed

- **Category recategorization**: removed "foundation" catch-all category. All 12 packages now use purpose-aligned categories: governance (bft), aggregation (condorcet, ensemble_div, kemeny, pbft), validation (inverse_u, eval_guard), selection (cost_pareto, mwu), attribution (shapley), evaluation (scoring_rule), exploration (aco)
- **Documentation enrichment**: all 12 packages' Lua doc headers and meta.description updated with detailed theory references, multi-agent/Swarm usage context, and cross-package composability notes
- **README**: updated package count (91 → 103), added all 12 packages to appropriate sections, added new Aggregation and Attribution sections

## [0.11.2] - 2026-04-12

### Added

- **hub_index.json**: Machine-readable package index for Hub search. Generated by `alc_hub_reindex --source_dir`. Contains 91 packages with name, version, description, and category metadata.

## [0.11.1] - 2026-04-12

### Changed

- **optimize** v0.2.0 → v0.3.0: auto_card support — emits a Card on optimization completion with two-tier content policy (Tier 1 body: config + best_params + best_score + top_k ranking; Tier 2 samples.jsonl: per-round history). Opt-in via `ctx.auto_card = true`
- **tests/test_optimize.lua**: added 4 auto_card tests (basic emit, card_pkg override, opt-out default, samples sidecar)

## [0.11.0] - 2026-04-08

### Added

- **6 new selection / ranking / partial-data pruning packages**:
  - **[ab_select](ab_select/)**: Adaptive Branching Selection — multi-fidelity Thompson sampling over a fixed candidate pool; cheap→expensive evaluator cascade allocates expensive evaluations only to promising candidates (Inoue et al., "AB-MCTS", NeurIPS 2025 Spotlight)
  - **[listwise_rank](listwise_rank/)**: Zero-shot listwise reranking — single-LLM-call permutation generation with sliding window for large N. Resolves the calibration problem of pointwise scoring (Sun et al., "RankGPT", EMNLP 2023; Pradeep et al., "RankZephyr", 2023)
  - **[pairwise_rank](pairwise_rank/)**: Pairwise Ranking Prompting (PRP) — bidirectional pairwise comparisons (A,B and B,A to cancel position bias) with Copeland-style aggregation. Modes: allpair O(N²) or sorting O(N log N) (Qin et al., NAACL 2024 Findings)
  - **[setwise_rank](setwise_rank/)**: Setwise tournament reranking — LLM picks the single best from small sets (size k); winners advance through tournament rounds. Mid-cost/mid-accuracy sweet spot between listwise and pairwise (Zhuang et al., SIGIR 2024)
  - **[cs_pruner](cs_pruner/)**: Confidence-sequence partial-data pruner — anytime-valid per-candidate kill via Empirical-Bernstein CS over a multi-dimensional rubric. Four variants: `polynomial_stitched`, `hoeffding`, `betting` (W-S&R 2024 predictable plug-in), and `kl` (Kaufmann-Cappé KL-LUCB). Optional layer-2 Successive Halving with gap guard for small-N×D regimes where the CS floor cannot fire (Howard et al., Ann. Stat. 2021; Waudby-Smith & Ramdas, JRSS-B 2024; Kaufmann & Cappé, JMLR 2013)
  - **[f_race](f_race/)**: Friedman race partial-data pruner — block-wise rank assignment over rubric dimensions; eliminates candidates whose mean rank is significantly worse than the best by a Friedman χ² + Conover post-hoc test. Designed for small N (≤10) × D (≤30) where EB-CS cannot fire (Friedman, JASA 1937; Birattari et al., GECCO 2002; Conover, 1999)
- **tests/test_cs_pruner.lua**: 24 tests covering all four CS variants, layer-2 halving, gap guard, eval_order modes, and validation
- **tests/test_f_race.lua**: Friedman race coverage
- **tests/test_ranking_packages.lua**: shared tests for ab_select / listwise_rank / pairwise_rank / setwise_rank

### Changed

- **cs_pruner**: dropped the reserved `independent_bonferroni` aggregation mode from docstring and error message. Numerical analysis (N=6, D=20, δ=0.05, t=1/dim → `radius_floor ≈ 16.78`) showed the construction is structurally incompatible with the round-robin evaluation schedule, so the v0.2 placeholder has been removed rather than carried forward. `ctx.aggregation` now documents `scalarize` as the only supported value.
- **README**: updated package count (85 → 91), added ranking/pruning packages to the Selection table and their LLM-call profiles to the table, added Testing section documenting the mlua-probe-mcp runner workflow

## [0.10.0] - 2026-04-04

### Added

- **New "Simulation" category** — Agent-Based Model framework + 7 model packages:
  - **[abm](abm/)**: Core ABM framework — Agent/Model/Scheduler (Frame layer) + Monte Carlo runner + sensitivity sweep + statistics (Analysis layer). Two-layer architecture with combinator-pattern schedulers
  - **[hybrid_abm](hybrid_abm/)**: LLM-as-Parameterizer ABM — LLM extracts simulation parameters (Phase A), Pure Lua ABM runs Monte Carlo (Phase B+C), sensitivity sweep (Phase D). Based on FCLAgent (arXiv:2510.12189)
  - **[epidemic_abm](epidemic_abm/)**: SIR Agent-Based epidemic model — stochastic individual-level disease transmission with tunable R0, herd immunity thresholds (Kermack & McKendrick 1927, Epstein 2006)
  - **[opinion_abm](opinion_abm/)**: Hegselmann-Krause Bounded Confidence opinion dynamics — emergent consensus, polarization, or fragmentation determined by ε threshold (Hegselmann & Krause, JASSS 2002)
  - **[evogame_abm](evogame_abm/)**: Evolutionary Game Theory ABM — iterated Prisoner's Dilemma / Hawk-Dove with fitness-proportionate selection and mutation. 6 classic strategies including Tit-for-Tat, Pavlov, Grudger (Axelrod 1984, Nowak & May 1992)
  - **[schelling_abm](schelling_abm/)**: Schelling Segregation model — agents on a 2D toroidal grid relocate when local same-type fraction falls below tolerance threshold (Schelling 1971, 1978)
  - **[sugarscape_abm](sugarscape_abm/)**: Sugarscape model — agents forage on a sugar landscape with heterogeneous metabolism/vision, emergent wealth inequality and Gini coefficient tracking (Epstein & Axtell 1996)
  - **[boids_abm](boids_abm/)**: Boids flocking model — separation, alignment, cohesion produce emergent flocking behavior. Tunable weights for Hybrid LLM parameter optimization (Reynolds, SIGGRAPH 1987)
- **tests/test_abm.lua**: 43 tests covering ABM framework + hybrid_abm
- **tests/test_abm_models.lua**: 20 tests covering epidemic, opinion, evogame, schelling models
- **tests/test_abm_new_models.lua**: 10 tests covering sugarscape and boids models

### Fixed

- **evogame_abm**: replaced IIFE with plain for-loop for strategy count (readability)
- **abm/frame/model**: changed 3-pass stepping (all before → all step → all after) to per-agent stepping (before → step → after per agent) — standard ABM activation semantics
- **schelling_abm**: added guard for already-vacated cells during agent movement phase
- **opinion_abm**: H-K bounded confidence comparison changed from `<` to `<=` (paper-compliant: |x_i - x_j| ≤ ε)
- **abm/sweep**: tier escalation threshold changed from `> 0` to `> 0.001` (avoids floating-point false negatives)
- **epidemic_abm, evogame_abm, opinion_abm, schelling_abm**: removed unnecessary `ctx.task` required check — task is not used in pure simulation models (available via comment for hybrid_abm integration)

### Changed

- **README**: updated package count (77 → 85), added Simulation section with 8 packages

## [0.9.0] - 2026-04-03

### Added

- **6 new packages** based on 2024-2026 test-time compute scaling and selection research:
  - **[usc](usc/)**: Universal Self-Consistency — extends SC to free-form tasks by having LLM select the most consistent response instead of majority voting. Works on open-ended QA, summarization, code generation where SC fails (Chen et al., ICML 2024, Google DeepMind)
  - **[step_verify](step_verify/)**: Step-Level Verification (PRM-style) — scores each intermediate reasoning step for logical correctness, identifies the first point of failure, and re-derives from the last correct step. Targets logical validity unlike cove (fact-checking) or factscore (claim verification) (PRM Survey 2025, ThinkPRM 2025, DiVeRSe)
  - **[compute_alloc](compute_alloc/)**: Compute-Optimal Test-Time Scaling Allocation — dynamically selects reasoning paradigm (single/parallel/sequential/hybrid) and budget based on problem difficulty. Key insight: optimal method changes with difficulty (Snell et al., ICLR 2025)
  - **[gumbel_search](gumbel_search/)**: Budget-optimal tree search — Sequential Halving for provably optimal budget allocation + Gumbel Top-k for unbiased candidate sampling. Complementary to ab_mcts: excels under fixed budget constraints (Karnin et al., ICML 2013; "Revisiting Tree Search for LLMs" 2026)
  - **[mbr_select](mbr_select/)**: Minimum Bayes Risk selection — computes pairwise similarity for all candidate pairs and selects the one with highest expected agreement. Bayes-optimal under decision theory, no bracket luck unlike tournament-based rank (MBR, NAACL 2025; Eikema & Aziz 2020)
  - **[reflexion](reflexion/)**: Episodic Memory Self-Improvement — multiple independent attempts where failures are reflected on and stored as lessons. Each new attempt references accumulated reflections. HumanEval 67%→91% (Shinn et al., NeurIPS 2023)
- **tests/test_tier1_2.lua**: 45 tests covering all 6 new packages (meta, validation, LLM call counts, index extraction, similarity matrix, episodic memory propagation)

### Changed

- **README**: updated package count (71 → 77), added new packages to Reasoning/Selection/Validation/Orchestration tables and LLM call counts table
- **README**: added 26 previously unlisted packages (v0.1.0–v0.4.0 era) to category tables and LLM Call Counts — all 77 packages now listed. New sections: Intent Understanding, Planning, Combinators
- **sc**: clarified description — "Best for tasks with canonical answer formats (numbers, options)" to distinguish from usc
- **reflect**: clarified description — "within a single attempt" to distinguish from reflexion

## [0.8.0] - 2026-04-03

### Added

- **New "Exploration" category** for population-based and adversarial search strategies:
  - **[qdaif](qdaif/)**: Quality-Diversity through AI Feedback — MAP-Elites archive with LLM-driven mutation, evaluation, and feature classification (Bradley et al., ICLR 2024)
  - **[falsify](falsify/)**: Sequential Falsification — Popper-style hypothesis exploration via active refutation, pruning, and successor derivation (Sourati et al., 2025; Yamada et al. "AI Scientist v2", 2025)
  - **[prompt_breed](prompt_breed/)**: Self-Referential Prompt Evolution — evolves task prompts via genetic operators with meta-mutation (mutation operators themselves evolve) (Fernando et al. "PromptBreeder", 2023)
  - **[coevolve](coevolve/)**: Challenger-Solver Co-evolution — adversarial self-play where Challenger generates problems at Solver's ability boundary (Singh et al., 2025; Faldor et al. "OMNI-EPIC", ICLR 2025)
- **mcts**: LATS-style Reflection mechanism — failure diagnosis injection into expansion prompts
- **optimize/search**: `breed` strategy — PromptBreeder-style meta-evolution for parameter optimization
- **LuaLS LuaCats type annotations** for all 71 packages:
  - `.luarc.json`: workspace.library configuration for `~/.algocline/types` + local `types/`
  - `types/alc_pkg.d.lua`: AlcCtx, AlcMeta type definitions — module interface contract
  - `*/init.lua`: `---@type AlcMeta`, `---@param ctx AlcCtx`, `---@return AlcCtx` annotations
- **tests/test_exploration.lua**: 38 tests covering all 4 new exploration packages + 2 extensions

### Fixed

- **types/alc_pkg.d.lua**: removed unused `AlcModule` class (LuaLS inject-field warning)

### Changed

- **README**: updated package count (67 → 71), added Exploration section, updated LLM call counts table

## [0.7.0] - 2026-03-30

### Added

- **New "Governance" category** for multi-agent pipeline robustness, based on "From Spark to Fire" (Xie et al., AAMAS 2026) and MAST (Cemri et al., 2025):
  - **[lineage](lineage/)**: Pipeline-spanning claim lineage tracking — extracts atomic claims per step, traces inter-step dependencies, detects conflicts and ungrounded claims. Defense rate improvement 0.32 → 0.89
  - **[dissent](dissent/)**: Consensus inertia prevention — forces adversarial challenge before finalizing multi-agent agreement. Composable with moa, panel, sc
  - **[anti_cascade](anti_cascade/)**: Pipeline error cascade detection — independently re-derives from original inputs at each step and compares with pipeline output to detect error amplification
- **1 new routing package**:
  - **[topo_route](topo_route/)**: Topology-aware meta-router — analyzes task characteristics and recommends optimal topology (linear/star/DAG/mesh/debate/ensemble) with concrete package mappings. Same agents, different topology → up to 40% reliability variation
- **tests/test_governance.lua**: 33 tests covering all 4 new packages (meta, validation, LLM call counts, parse logic, threshold gating)

### Changed

- **README**: updated package count (37 → 67), added Governance section and topo_route to Routing table, updated LLM call counts table

## [0.6.0] - 2026-03-29

### Added

- **6 new packages** based on 2024-2026 research:
  - **[got](got/)**: Graph of Thoughts — DAG-structured reasoning with aggregation (many-to-one merge), refinement loops, and multi-path synthesis (Besta et al., AAAI 2024)
  - **[model_first](model_first/)**: Model-First Reasoning — constructs explicit problem model (entities, states, actions, constraints) before solving (Rana & Kumar, 2025)
  - **[sketch](sketch/)**: Sketch-of-Thought — cognitive-inspired efficient reasoning via 3 paradigms with adaptive routing, 60-84% token reduction (Aytes et al., EMNLP 2025)
  - **[coa](coa/)**: Chain-of-Abstraction — reasons with abstract placeholders, then grounds via parallel knowledge resolution (Gao et al., Meta/EPFL, COLING 2025)
  - **[ab_mcts](ab_mcts/)**: Adaptive Branching MCTS — Thompson Sampling with GEN node mechanism for dynamic wider/deeper decisions (Inoue et al., NeurIPS 2025 Spotlight)
  - **[counterfactual_verify](counterfactual_verify/)**: Counterfactual faithfulness verification — tests causal dependence between premises and conclusions (Hase et al., 2026)

### Fixed

- **counterfactual_verify**: `parse_counterfactuals()` now correctly extracts all blocks including the last one (previously missed due to delimiter-based regex)

### Changed

- **README**: updated package count (31 → 37), added new packages to Reasoning and Validation tables and LLM call counts

## [0.5.0] - 2026-03-24

### Added

- **5 orchestration packages**:
  - **[orch_fixpipe](orch_fixpipe/)**: Deterministic fixed pipeline with gate/retry (Lobster/OpenClaw pattern)
  - **[orch_gatephase](orch_gatephase/)**: Phase orchestration with pre/post hooks and skip rules (Thin Agent/Fat Platform, Praetorian)
  - **[orch_adaptive](orch_adaptive/)**: Adaptive depth orchestration based on task difficulty (DAAO, arXiv:2509.11079)
  - **[orch_nver](orch_nver/)**: N-version programming with score/vote selection (Agentic SE Roadmap, arXiv:2509.06216)
  - **[orch_escalate](orch_escalate/)**: Cascade escalation from light to heavy strategies (Microsoft + DAAO cost optimization)
- **3 router packages**:
  - **[router_daao](router_daao/)**: Difficulty-aware routing with injectable confidence profiles (DAAO, arXiv:2509.11079)
  - **[router_semantic](router_semantic/)**: Keyword matching with LLM fallback, 0-1 LLM calls (Microsoft Multi-Agent Reference Architecture)
  - **[router_capability](router_capability/)**: Jaccard similarity agent registry matching (Dynamic Agent Registry pattern)
- **[optimize](optimize/)**: Modular parameter optimization orchestrator (v0.2.0)
  - 4-component architecture: search, eval, stop, orchestrator
  - **Search strategies**: UCB1 (Auer et al. 2002), random, OPRO (Yang et al. 2023), EA/GA (Guo et al. 2024), epsilon-greedy
  - **Evaluators**: evalframe integration, custom function, LLM-as-judge
  - **Stopping criteria**: variance convergence, patience (early stopping), threshold, improvement rate, composite
  - State persistence via `alc.state` for incremental optimization across sessions
  - `alc.tuning` integration for parameter merging
- **tests/**: test suites for all 9 new packages (39 tests for optimize, 8 suites for orch/router)

### Changed

- **README**: updated package count (22 → 31), added Orchestration, Routing sections and optimize to Extraction/Optimization table

## [0.4.0] - 2026-03-19

### Added

- **6 reasoning strategy packages**:
  - **[s2a](s2a/)**: System 2 Attention — strips irrelevant/biasing context before reasoning (Weston & Sukhbaatar, 2023)
  - **[plan_solve](plan_solve/)**: Plan-and-Solve — devises step-by-step plan then executes sequentially (Wang et al., 2023)
  - **[rstar](rstar/)**: Mutual reasoning verification — two independent paths cross-verify each other (Qi et al., 2024)
  - **[faithful](faithful/)**: Faithful CoT — translates reasoning into formal representation for verification (Lyu et al., 2023)
  - **[moa](moa/)**: Mixture of Agents — layered multi-agent aggregation with cross-pollination (Wang et al., 2024)
  - **[bot](bot/)**: Buffer of Thoughts — meta-reasoning with reusable structured thought templates (Yang et al., 2024)
- **tests/test_new_packages.lua**: test suite for the 6 new packages

### Changed

- **reflect**: added `ctx.initial_draft` parameter to skip initial LLM generation when caller provides a pre-generated draft
- **README**: updated package count (16 → 22), added new packages to tables and LLM call counts

## [0.3.0] - 2026-03-18

### Added

- **9 reasoning strategy packages**: bisect, blind_spot, cascade, claim_trace, critic, dmad, negation, p_tts, verify_first
- **robust_qa**: composite pipeline combining p_tts, negation, and critic
- **3 bundled eval scenarios** (`scenarios/` directory):
  - **math_basic**: arithmetic and number theory (7 cases, contains + exact_match)
  - **reasoning_basic**: logical reasoning and common knowledge (5 cases, contains)
  - **factual_basic**: factual knowledge with verifiable answers (5 cases, contains)

## [0.2.0] - 2026-03-15

### Added

- **10 reasoning strategy packages**: ucb, panel, cot, sc, reflect, calibrate, contrastive, meta_prompt, factscore, cove
- **deliberate**: structured decision-making combinator (decompose → branch reasoning → synthesize)
- **pre_mortem**: feasibility-gated proposal filtering (factscore → contrastive → calibrate → pairwise ranking)
- **4 intent understanding packages**:
  - **ambig**: AMBIG-SWE detect-clarify-integrate pipeline (ICLR 2026)
  - **prism**: cognitive-load-aware intent decomposition with topological sort (arXiv:2601.08653)
  - **intent_discovery**: exploratory intent formation via DiscoverLLM (arXiv:2602.03429)
  - **intent_belief**: Bayesian intent estimation with diagnostic questions (arXiv:2510.18476)

### Changed

- **review_and_investigate**: enhanced pipeline with span-based code slicing, migrated to alc.parse_score
- **cove, factscore, review_and_investigate**: added `grounded = true` to verification phases
- **README**: added alc-runner agent integration guide

## [0.1.0] - 2026-03-15

### Added

- Initial release
- Collection layout with `*/init.lua` convention
- **review_and_investigate**: multi-phase code review pipeline (detect → cluster → verify → diagnose → research → prescribe → report)
