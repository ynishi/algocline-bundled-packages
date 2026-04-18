--- Tests for alc_shapes.instrument — Malli-style self-decoration wrapper.
---
--- Covers: load-time guards, dev-gating, M.spec.entries-driven input/result
--- checks, override via explicit `spec`, ctx-threading payload extraction,
--- integration with a real bundled pkg (calibrate: multi-entry).

local describe, it, expect = lust.describe, lust.it, lust.expect

package.loaded["alc_shapes"]                = nil
package.loaded["alc_shapes.t"]              = nil
package.loaded["alc_shapes.check"]          = nil
package.loaded["alc_shapes.instrument"]     = nil
package.loaded["alc_shapes.spec_resolver"]  = nil

local S = require("alc_shapes")
local T = S.T

-- Dev-mode helpers. instrument() short-circuits the check path when
-- ALC_SHAPE_CHECK != "1", so most shape-violation assertions must gate
-- themselves on dev mode.
local function in_dev()
    return S.is_dev_mode()
end

-- Minimal voted fixture reused across tests (shape of the "voted" registry
-- entry — the sc pkg's result shape).
local function voted_fixture()
    return {
        consensus   = "X",
        answer      = "X",
        answer_norm = "x",
        paths = {
            { reasoning = "a", answer = "X" },
            { reasoning = "b", answer = "X" },
        },
        votes = { "x", "x" },
        vote_counts = { x = 2 },
        n_sampled = 2,
        total_llm_calls = 2,
    }
end

-- ── Load-time guards ──────────────────────────────────────────────────

describe("alc_shapes.instrument: load-time guards", function()
    it("errors when mod is not a table", function()
        local ok, err = pcall(S.instrument, "nope", "run")
        expect(ok).to.equal(false)
        expect(err:match("mod must be a table")).to.exist()
    end)

    it("errors when entry_name is empty or non-string", function()
        local mod = { meta = { name = "x" }, run = function(c) return c end }
        local ok, err = pcall(S.instrument, mod, "")
        expect(ok).to.equal(false)
        expect(err:match("entry_name must be a non%-empty string")).to.exist()
        ok, err = pcall(S.instrument, mod, 42)
        expect(ok).to.equal(false)
        expect(err:match("entry_name must be a non%-empty string")).to.exist()
    end)

    it("errors when mod[entry_name] is not a function", function()
        local mod = { meta = { name = "x" }, run = "not-a-fn" }
        local ok, err = pcall(S.instrument, mod, "run")
        expect(ok).to.equal(false)
        expect(err:match("is not a function")).to.exist()
    end)

    it("errors when meta.name is missing", function()
        local mod = { run = function(c) return c end }
        local ok, err = pcall(S.instrument, mod, "run")
        expect(ok).to.equal(false)
        expect(err:match("mod%.meta%.name")).to.exist()
    end)

    it("errors when spec argument is a non-table non-nil", function()
        local mod = { meta = { name = "x" }, run = function(c) return c end }
        local ok, err = pcall(S.instrument, mod, "run", "string-spec")
        expect(ok).to.equal(false)
        expect(err:match("spec must be a table or nil")).to.exist()
    end)
end)

-- ── Transparent call (no shapes declared) ────────────────────────────

describe("alc_shapes.instrument: transparent when no shapes declared", function()
    it("passes ctx and returned value through unchanged", function()
        local mod = {
            meta = { name = "passthru" },
            run  = function(ctx)
                ctx.result = { echo = ctx.task }
                return ctx
            end,
        }
        mod.run = S.instrument(mod, "run")
        local returned = mod.run({ task = "hi" })
        expect(returned.result.echo).to.equal("hi")
    end)

    it("preserves varargs past ctx", function()
        local mod = {
            meta = { name = "vararg" },
            run  = function(ctx, a, b)
                ctx.result = { sum = a + b }
                return ctx
            end,
        }
        mod.run = S.instrument(mod, "run")
        local returned = mod.run({}, 2, 3)
        expect(returned.result.sum).to.equal(5)
    end)
end)

-- ── Result shape from M.spec.entries ─────────────────────────────────

describe("alc_shapes.instrument: result shape from M.spec.entries", function()
    local function typed_pkg()
        return {
            meta = { name = "typed_inst" },
            spec = {
                entries = {
                    run = { result = T.ref("voted") },
                },
            },
            run = function(ctx)
                ctx.result = voted_fixture()
                return ctx
            end,
        }
    end

    it("passes when ctx.result matches declared shape", function()
        local mod = typed_pkg()
        mod.run = S.instrument(mod, "run")
        local returned = mod.run({ task = "t" })
        expect(returned.result.consensus).to.equal("X")
    end)

    it("throws in dev mode when ctx.result violates shape", function()
        if not in_dev() then return end
        local mod = typed_pkg()
        mod.run = function(ctx)
            ctx.result = { wrong = true }
            return ctx
        end
        mod.run = S.instrument(mod, "run")
        local ok, err = pcall(mod.run, { task = "t" })
        expect(ok).to.equal(false)
        expect(err).to.exist()
    end)

    it("hint includes meta.name and entry_name", function()
        if not in_dev() then return end
        local mod = typed_pkg()
        mod.run = function(ctx)
            ctx.result = { wrong = true }
            return ctx
        end
        mod.run = S.instrument(mod, "run")
        local ok, err = pcall(mod.run, { task = "t" })
        expect(ok).to.equal(false)
        expect(err:match("typed_inst%.run")).to.exist()
    end)

    it("accepts string shape name (coerced to T.ref)", function()
        local mod = {
            meta = { name = "typed_str" },
            spec = { entries = { run = { result = "voted" } } },
            run = function(ctx)
                ctx.result = voted_fixture()
                return ctx
            end,
        }
        mod.run = S.instrument(mod, "run")
        local returned = mod.run({ task = "t" })
        expect(returned.result.consensus).to.equal("X")
    end)
end)

-- ── Input shape ──────────────────────────────────────────────────────

describe("alc_shapes.instrument: input shape", function()
    local function typed_input_pkg()
        return {
            meta = { name = "input_inst" },
            spec = {
                entries = {
                    run = {
                        input  = T.shape({ task = T.string }, { open = true }),
                        result = T.ref("voted"),
                    },
                },
            },
            run = function(ctx)
                ctx.result = voted_fixture()
                return ctx
            end,
        }
    end

    it("passes valid ctx", function()
        local mod = typed_input_pkg()
        mod.run = S.instrument(mod, "run")
        local returned = mod.run({ task = "t", extra = 1 })
        expect(returned.result.consensus).to.equal("X")
    end)

    it("throws in dev mode when ctx violates input shape", function()
        if not in_dev() then return end
        local mod = typed_input_pkg()
        mod.run = S.instrument(mod, "run")
        local ok, err = pcall(mod.run, { task = 42 })  -- task must be string
        expect(ok).to.equal(false)
        expect(err).to.exist()
    end)

    it("hint for input violation carries ':input' suffix", function()
        if not in_dev() then return end
        local mod = typed_input_pkg()
        mod.run = S.instrument(mod, "run")
        local ok, err = pcall(mod.run, { task = 42 })
        expect(ok).to.equal(false)
        expect(err:match("input_inst%.run:input")).to.exist()
    end)
end)

-- ── Payload extraction: ret.result vs ret ────────────────────────────

describe("alc_shapes.instrument: payload extraction", function()
    it("checks ret.result when entry returns a ctx table", function()
        -- Standard AlcCtx convention: result is wrapped in ctx.result.
        local mod = {
            meta = { name = "ctx_payload" },
            spec = { entries = { run = { result = T.ref("voted") } } },
            run = function(ctx)
                ctx.result = voted_fixture()
                return ctx
            end,
        }
        mod.run = S.instrument(mod, "run")
        local returned = mod.run({})
        expect(returned.result.consensus).to.equal("X")
    end)

    it("falls back to ret itself when ret has no .result", function()
        -- Non-standard: entry returns a raw result (rare but supported).
        local mod = {
            meta = { name = "raw_payload" },
            spec = { entries = { run = { result = T.ref("voted") } } },
            run = function(_ctx)
                return voted_fixture()  -- plain table, no .result
            end,
        }
        mod.run = S.instrument(mod, "run")
        local returned = mod.run({})
        expect(returned.consensus).to.equal("X")
    end)
end)

-- ── Override via explicit `spec` argument ────────────────────────────

describe("alc_shapes.instrument: spec override", function()
    it("override wins over M.spec.entries[entry].result", function()
        if not in_dev() then return end
        -- Declared result = voted, but override says something stricter.
        local mod = {
            meta = { name = "override_pkg" },
            spec = { entries = { run = { result = T.ref("voted") } } },
            run = function(ctx)
                ctx.result = voted_fixture()  -- valid voted
                return ctx
            end,
        }
        local strict = T.shape({
            consensus = T.string,
            must_have_this = T.string,  -- NOT in voted_fixture
        }, { open = true })
        mod.run = S.instrument(mod, "run", { result = strict })
        local ok, err = pcall(mod.run, {})
        expect(ok).to.equal(false)
        expect(err).to.exist()
    end)

    it("override works when M.spec is absent entirely", function()
        local mod = {
            meta = { name = "no_spec_pkg" },
            run = function(ctx)
                ctx.result = voted_fixture()
                return ctx
            end,
        }
        mod.run = S.instrument(mod, "run", { result = "voted" })
        local returned = mod.run({})
        expect(returned.result.consensus).to.equal("X")
    end)
end)

-- ── Direct-args mode (library-style pkgs) ───────────────────────────

describe("alc_shapes.instrument: direct-args mode", function()
    local function lib_pkg()
        -- bft-style: pure function `fn(n, f) -> number`.
        return {
            meta = { name = "libpkg" },
            spec = {
                entries = {
                    threshold = {
                        args   = { T.number, T.number },
                        result = T.number,
                    },
                },
            },
            threshold = function(n, f)
                return n - f
            end,
        }
    end

    it("validates positional args and raw return", function()
        local mod = lib_pkg()
        mod.threshold = S.instrument(mod, "threshold")
        expect(mod.threshold(5, 1)).to.equal(4)
    end)

    it("throws in dev mode when an arg has the wrong type", function()
        if not in_dev() then return end
        local mod = lib_pkg()
        mod.threshold = S.instrument(mod, "threshold")
        local ok, err = pcall(mod.threshold, 5, "oops")
        expect(ok).to.equal(false)
        expect(err:match("libpkg%.threshold:arg2")).to.exist()
    end)

    it("throws in dev mode when raw return violates result", function()
        if not in_dev() then return end
        local mod = lib_pkg()
        mod.threshold = function(n, f) return "not-a-number" end
        mod.threshold = S.instrument(mod, "threshold")
        local ok, err = pcall(mod.threshold, 5, 1)
        expect(ok).to.equal(false)
        expect(err:match("libpkg%.threshold")).to.exist()
    end)

    it("skips nil slots in args (per-arg opt-out)", function()
        if not in_dev() then return end
        -- Second slot is nil → opaque options table is NOT validated.
        local mod = {
            meta = { name = "opaque_opts" },
            spec = {
                entries = {
                    run = {
                        args   = { T.number, nil },
                        result = T.number,
                    },
                },
            },
            run = function(n, opts) return n + (opts.bias or 0) end,
        }
        mod.run = S.instrument(mod, "run")
        expect(mod.run(10, { bias = 3 })).to.equal(13)
    end)

    it("accepts optional trailing args (T.x:is_optional())", function()
        local mod = {
            meta = { name = "opt_tail" },
            spec = {
                entries = {
                    run = {
                        args   = { T.number, T.number:is_optional() },
                        result = T.number,
                    },
                },
            },
            run = function(n, bias) return n + (bias or 0) end,
        }
        mod.run = S.instrument(mod, "run")
        expect(mod.run(10)).to.equal(10)
        expect(mod.run(10, 5)).to.equal(15)
    end)

    it("string shape names in args are coerced to T.ref", function()
        -- Result-side string coercion is already tested elsewhere; this
        -- test covers the args[i] string path through coerce_args_list.
        local mod = {
            meta = { name = "argstr" },
            spec = {
                entries = {
                    run = {
                        args   = { "voted" },  -- 1st arg must match "voted"
                        result = T.string,
                    },
                },
            },
            run = function(v) return v.consensus end,
        }
        mod.run = S.instrument(mod, "run")
        expect(mod.run(voted_fixture())).to.equal("X")
    end)

    -- Multi-return preservation (Option A'): library-style pkgs often
    -- return `(bool, string)` validator tuples (bft.validate,
    -- eval_guard.self_critique, cost_pareto.is_dominated, etc). The
    -- wrapper must pass through all return values, not just the first.
    it("preserves multi-return when dev check is off", function()
        if in_dev() then return end  -- this test only meaningful when dev off
        local mod = {
            meta = { name = "multiret_off" },
            spec = {
                entries = {
                    validate = {
                        args   = { T.number, T.number },
                        result = T.boolean,
                    },
                },
            },
            validate = function(n, f) return n >= 3 * f + 1, "reason-x" end,
        }
        mod.validate = S.instrument(mod, "validate")
        local ok, reason = mod.validate(4, 1)
        expect(ok).to.equal(true)
        expect(reason).to.equal("reason-x")
    end)

    it("preserves multi-return when dev check passes", function()
        if not in_dev() then return end
        local mod = {
            meta = { name = "multiret_on" },
            spec = {
                entries = {
                    validate = {
                        args   = { T.number, T.number },
                        result = T.boolean,
                    },
                },
            },
            validate = function(n, f) return n >= 3 * f + 1, "reason-y" end,
        }
        mod.validate = S.instrument(mod, "validate")
        local ok, reason = mod.validate(4, 1)
        expect(ok).to.equal(true)
        expect(reason).to.equal("reason-y")
    end)

    it("preserves three-plus return values", function()
        local mod = {
            meta = { name = "multiret_three" },
            spec = {
                entries = {
                    score = {
                        args   = { T.number },
                        result = T.number,
                    },
                },
            },
            score = function(n) return n * 2, "label", true end,
        }
        mod.score = S.instrument(mod, "score")
        local v, label, flag = mod.score(3)
        expect(v).to.equal(6)
        expect(label).to.equal("label")
        expect(flag).to.equal(true)
    end)

    it("still validates first return against result_shape", function()
        if not in_dev() then return end
        local mod = {
            meta = { name = "multiret_bad" },
            spec = {
                entries = {
                    validate = {
                        args   = { T.number },
                        result = T.boolean,
                    },
                },
            },
            -- First return is a string, not a boolean → should throw even
            -- though 2nd return would be fine.
            validate = function(_) return "not-bool", "reason-z" end,
        }
        mod.validate = S.instrument(mod, "validate")
        local ok, err = pcall(mod.validate, 1)
        expect(ok).to.equal(false)
        expect(err:match("multiret_bad%.validate")).to.exist()
    end)

    it("rejects concurrent input + args at spec-resolve time", function()
        local mod = {
            meta = { name = "conflict" },
            spec = {
                entries = {
                    run = {
                        input  = T.shape({ task = T.string }, { open = true }),
                        args   = { T.number },
                        result = T.number,
                    },
                },
            },
            run = function(_) return 0 end,
        }
        local ok, err = pcall(S.instrument, mod, "run")
        expect(ok).to.equal(false)
        expect(err:match("mutually exclusive")).to.exist()
    end)

    it("rejects concurrent input + args via override spec", function()
        local mod = {
            meta = { name = "conflict_override" },
            run  = function(_) return 0 end,
        }
        local ok, err = pcall(S.instrument, mod, "run", {
            input  = T.shape({}, { open = true }),
            args   = { T.number },
            result = T.number,
        })
        expect(ok).to.equal(false)
        expect(err:match("mutually exclusive")).to.exist()
    end)
end)

-- ── Dev-mode gating ──────────────────────────────────────────────────

describe("alc_shapes.instrument: dev-mode gating", function()
    it("dev-off: bad result does NOT throw", function()
        if in_dev() then return end  -- this test only meaningful when dev off
        local mod = {
            meta = { name = "devoff_pkg" },
            spec = { entries = { run = { result = T.ref("voted") } } },
            run = function(ctx)
                ctx.result = { totally_wrong = 1 }
                return ctx
            end,
        }
        mod.run = S.instrument(mod, "run")
        local ok = pcall(mod.run, {})
        expect(ok).to.equal(true)
    end)
end)

-- ── Multi-entry module (calibrate-style) ─────────────────────────────

describe("alc_shapes.instrument: multi-entry", function()
    it("both entries instrumented independently", function()
        local mod = {
            meta = { name = "multi" },
            spec = {
                entries = {
                    run    = { result = T.ref("voted") },
                    assess = {
                        result = T.shape({
                            confidence = T.number,
                        }, { open = true }),
                    },
                },
            },
            run = function(ctx)
                ctx.result = voted_fixture()
                return ctx
            end,
            assess = function(ctx)
                ctx.result = { confidence = 0.42, answer = "A" }
                return ctx
            end,
        }
        mod.run    = S.instrument(mod, "run")
        mod.assess = S.instrument(mod, "assess")

        local r1 = mod.run({})
        expect(r1.result.consensus).to.equal("X")
        local r2 = mod.assess({})
        expect(r2.result.confidence).to.equal(0.42)
    end)

    it("run → assess nested dispatch goes through wrapped assess", function()
        -- Mirrors calibrate.run which internally calls M.assess(ctx). Once
        -- assess is replaced with the instrumented version, the nested call
        -- resolves to the wrapped fn at call-time (Lua table-lookup is
        -- evaluated each call), so assess's post-check fires inside run.
        if not in_dev() then return end
        local mod = {
            meta = { name = "nested" },
            spec = {
                entries = {
                    run    = { result = T.shape({ ok = T.boolean }, { open = true }) },
                    assess = { result = T.shape({ n = T.number }) },
                },
            },
        }
        mod.assess = function(ctx)
            ctx.result = { n = "NOT_A_NUMBER" }  -- violates assess's shape
            return ctx
        end
        mod.run = function(ctx)
            mod.assess(ctx)  -- nested call → wrapped version
            ctx.result = { ok = true }
            return ctx
        end
        mod.assess = S.instrument(mod, "assess")
        mod.run    = S.instrument(mod, "run")

        local ok, err = pcall(mod.run, {})
        expect(ok).to.equal(false)
        expect(err:match("nested%.assess")).to.exist()
    end)
end)

-- ── Integration with a real bundled pkg ─────────────────────────────

describe("alc_shapes.instrument: bundled pkg self-decoration", function()
    it("sc.run is the wrapped function (not the raw body)", function()
        -- After the 8-pkg migration, `sc.run` IS the instrumented wrapper.
        -- We verify it's replaceable in-place and keeps the same signature.
        package.loaded["sc"] = nil
        local sc = require("sc")
        expect(type(sc.run)).to.equal("function")
        -- Resolver confirms the declared result shape is discoverable.
        local r = S.spec_resolver.resolve(sc)
        expect(r.kind).to.equal("typed")
        expect(r.entries.run.result).to.exist()
    end)

    it("calibrate.assess and calibrate.run both resolve with declared shapes", function()
        package.loaded["calibrate"] = nil
        local cal = require("calibrate")
        expect(type(cal.run)).to.equal("function")
        expect(type(cal.assess)).to.equal("function")
        local r = S.spec_resolver.resolve(cal)
        expect(rawget(r.entries.run.result, "name")).to.equal("calibrated")
        expect(rawget(r.entries.assess.result, "name")).to.equal("assessed")
    end)

    it("cot.run is wrapped with inline T.shape input + result", function()
        -- cot exercises the inline-schema path: spec.entries.run.input
        -- and .result are both inline T.shape(...) (not T.ref). The
        -- instrument wrapper must accept them directly without going
        -- through the registry.
        package.loaded["cot"] = nil
        local cot = require("cot")
        expect(type(cot.run)).to.equal("function")
        local r = S.spec_resolver.resolve(cot)
        expect(r.kind).to.equal("typed")
        expect(rawget(r.entries.run.input, "kind")).to.equal("shape")
        expect(rawget(r.entries.run.result, "kind")).to.equal("shape")
    end)

    -- Phase 2-a (category="reasoning") pkgs: plan_solve / step_back /
    -- least_to_most. All three follow the cot precedent (inline T.shape
    -- for both input and result, no registry name).
    --
    -- Phase 2-b (category="refinement") pkgs: reflect / reflexion.
    -- Phase 2-c (category="planning") pkgs: decompose.
    -- Phase 2-d (category="generation") pkgs: sot.
    -- Phase 2-e (category="preprocessing") pkgs: s2a.
    -- Phase 2-f (category="optimization") pkgs: cod.
    -- Phase 2-g-1 (category="reasoning" 派生) pkgs: sketch / got / tot.
    -- Phase 2-g-2 (category="reasoning" 派生) pkgs: maieutic / cumulative /
    -- analogical. maieutic declares `tree = T.any` (recursive explanation
    -- tree is not expressible as a finite shape in V0).
    -- Phase 2-g-3 (category="reasoning" 派生) pkgs: verify_first / faithful /
    -- meta_prompt. Completes the 9-pkg reasoning sweep (2-g-1/2/3).
    -- Phase 3-a (category="selection") pkgs: ucb / setwise_rank / mbr_select.
    -- Phase 3-b (category="selection") pkgs: f_race / cs_pruner / ab_select.
    -- Phase 3-c (aggregation + reasoning 派生) pkgs: usc / diverse / gumbel_search.
    -- Phase 3-d (orchestration + optimization + debugging) pkgs:
    -- compute_alloc / optimize / bisect. compute_alloc declares `strategies =
    -- T.table` (user-supplied difficulty→strategy map) and `candidates` is
    -- optional (only populated for parallel / hybrid paradigms). optimize uses
    -- T.any for string-or-table inputs (scenario / search / evaluator / stop)
    -- and T.table for parameter maps (space / defaults / best_params).
    -- Phase 4-a (category="evaluation"/"validation") pkgs: critic / cove /
    -- factscore. critic declares `scores = T.table` (rubric dim → number map),
    -- `history` nested array-of-shape with per-round trace, and `rubric` as
    -- array_of({name, description}).
    -- Phase 4-b (category="validation"/"exploration") pkgs: falsify /
    -- step_verify / counterfactual_verify. falsify declares nested
    -- hypothesis shape with `derived_from` optional (seed vs derived) and
    -- per-hypothesis `history` refutation trace; step_verify has per-round
    -- `steps` array + optional `error_at`; counterfactual_verify carries
    -- `faithful` boolean + `mismatches` subset array.
    -- Phase 4-c (category="attribution"/"correction"/"validation") pkgs:
    -- claim_trace / blind_spot / negation. claim_trace uses T.any for
    -- sources (string-or-array) with optional `source_index` /
    -- `sources_count`. blind_spot has multi-role history array. negation's
    -- `initial_answer` is optional (omitted on empty-conditions short-circuit).
    -- Phase 4-d (category="combinator"/"reasoning"/"pipeline") pkgs:
    -- pre_mortem / contrastive / robust_qa. pre_mortem delegates to
    -- factscore / contrastive / calibrate (nested sub-results held as
    -- T.table / T.any). contrastive has {wrong_reasoning, error_analysis}
    -- pairs. robust_qa's `phases` is array_of(T.any) because per-phase
    -- shape differs (discriminated by `name`).
    -- Phase 5-a (category="orchestration") pkgs: orch_fixpipe /
    -- orch_adaptive / orch_gatephase. All three share a phase record
    -- sub-shape {name, output, gate_passed, attempts}. orch_adaptive
    -- adds depth_config/active_phase_count/total_phase_count; gatephase
    -- adds task_type/skipped_phases. Phase definition arrays are
    -- array_of(T.any) because callers supply opaque phase records.
    -- Phase 5-b (category="orchestration"/"selection") pkgs: orch_escalate /
    -- orch_nver / moa. orch_escalate declares per-level record with optional
    -- phase_outputs (multi_phase level only). orch_nver's result is a
    -- branch-polymorphic shape: score-branch exposes rankings/best_score/
    -- best_reasoning, vote-branch exposes variants; all such fields are
    -- `:is_optional()`. moa has a nested array_of(array_of(T.string)) for
    -- layer_outputs [layer_idx][agent_idx].
    -- Phase 5-c (category="reasoning"/"adversarial"/"aggregation") pkgs:
    -- php / triad / pbft. php has per-round record (round, answer,
    -- conclusion, hint_used). triad's transcript mixes opening (round=0)
    -- and rebuttal rounds in one array. pbft has vote_distribution as
    -- array_of({proposal, votes}) + raw proposals preserved per N2
    -- Red Line (initial answer preservation).
    -- Phase 5-d (category="combinator"/"governance") pkgs:
    -- deliberate / dissent. deliberate delegates to step_back /
    -- meta_prompt / triad / calibrate / rank, so nested sub-pkg
    -- sub-results (abstractions / expert_consultations / options /
    -- debates) are declared as T.any or T.array_of(T.any) — the
    -- shape contract is owned by each delegated pkg. dissent's
    -- consensus input is REQUIRED (not optional); revised_consensus
    -- is `:is_optional()` because it stays nil when no revision
    -- was triggered. perspectives accepts both string-array and
    -- table-array variants hence T.array_of(T.any).
    for _, name in ipairs({
        "plan_solve", "step_back", "least_to_most",
        "reflect", "reflexion",
        "decompose",
        "sot",
        "s2a",
        "cod",
        "sketch", "got", "tot",
        "maieutic", "cumulative", "analogical",
        "verify_first", "faithful", "meta_prompt",
        "ucb", "setwise_rank", "mbr_select",
        "f_race", "cs_pruner", "ab_select",
        "usc", "diverse", "gumbel_search",
        "compute_alloc", "optimize", "bisect",
        "critic", "cove", "factscore",
        "falsify", "step_verify", "counterfactual_verify",
        "claim_trace", "blind_spot", "negation",
        "pre_mortem", "contrastive", "robust_qa",
        "orch_fixpipe", "orch_adaptive", "orch_gatephase",
        "orch_escalate", "orch_nver", "moa",
        "php", "triad", "pbft",
        "deliberate", "dissent",
    }) do
        it(name .. ".run is wrapped with inline T.shape input + result", function()
            package.loaded[name] = nil
            local pkg = require(name)
            expect(type(pkg.run)).to.equal("function")
            local r = S.spec_resolver.resolve(pkg)
            expect(r.kind).to.equal("typed")
            expect(rawget(r.entries.run.input, "kind")).to.equal("shape")
            expect(rawget(r.entries.run.result, "kind")).to.equal("shape")
        end)
    end
end)
