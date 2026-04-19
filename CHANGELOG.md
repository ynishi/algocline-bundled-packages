# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.16.0] - 2026-04-19

### Added

- **[flow](flow/) Frame substrate** (v0.1.0 debut): Light Frame over `alc.state` exposing two primitives — `FlowState` (persistent KV with resume) and `ReqToken` (random-nonce request correlation, AMQP `correlation_id` idiom) — plus `flow.llm` sugar for LLM calls with slot+token echo verification. Module-level pure-function API (`state_new / state_key / state_get / state_set / state_save / token_issue / token_wrap / token_verify / llm`). No `M.run` by design: `flow` is a substrate, not an orchestrator — the driver loop stays in user code (Functional Core / Imperative Shell). Identity `deep_equal` check on resume prevents silent parameter drift. Fail-open token verification keeps existing bundled pkgs usable without rewrite; opt-in v1 contract (see `flow/doc/contract.md`) tightens per-call verification.
- **[recipe_deep_panel](recipe_deep_panel/) Recipe** (v0.1.0 debut): production-grade 5-stage deep-reasoning pipeline composed on top of flow — `condorcet_gate` (Anti-Jury guard, p≥0.5) → fan-out of N × `ab_mcts` → `ensemble_div` (decomposition when ground_truth available) → `condorcet.prob_majority` plurality → `calibrate`. Inputs guarded: `p_estimate` required (no default), `n_branches` odd ≥3, `approaches` uniqueness. Identity = `{task, n_branches, budget, max_depth}` covers resume replay. Stage 1 abort path shares the unified result shape. `M.verified.stage_coverage` records per-stage verification status (2 stages verified with real LLM, 3 stages flagged `not_exercised` with `reason` + `to_verify` — no fabricated claims).
- **`AlcResultDeepPaneled` shape** in `alc_shapes` (22 fields, `open=true`): machine-contract for recipe_deep_panel result. LuaCATS projection in `types/alc_shapes.d.lua`.
- **`justfile` recipes** `gen-docs`, `gen-docs-lint`, `gen-docs-strict`: fills the gap where `CLAUDE.md` documented these commands but the justfile lacked them. Commit / release gates use `gen-docs-strict` to fail on V0 convention lint errors.
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
- **`alc_shapes.spec_resolver.run` ctx-threading**: aligned with `AlcCtx` convention (earlier prototype in `workspace/` diverged; migration preserved test fixtures).
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
