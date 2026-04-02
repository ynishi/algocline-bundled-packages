--- robust_qa — Three-phase quality assurance pipeline
---
--- Chains three independent verification strategies into a single pipeline:
---   Phase 1 (p_tts):    Constraint-first solving — generate constraints BEFORE
---                        solving, verify solution against specification
---   Phase 2 (negation): Adversarial stress-test — generate destruction conditions,
---                        verify if they hold, revise if flaws found
---   Phase 3 (critic):   Rubric-based evaluation — score per dimension, revise
---                        weak areas with targeted feedback
---
--- Each phase operates on a different axis of quality:
---   p_tts    = "Does it satisfy the requirements?"  (specification compliance)
---   negation = "Can it be broken?"                  (adversarial robustness)
---   critic   = "Is it well-crafted?"                (holistic quality)
---
--- The phases are sequential: each operates on the (potentially revised)
--- output of the previous phase. This means later phases evaluate a
--- progressively hardened answer, not the naive initial generation.
---
--- Usage:
---   local robust_qa = require("robust_qa")
---   return robust_qa.run(ctx)
---
--- ctx.task (required): The task/question to solve
---
--- Phase 1 (p_tts) options:
---   ctx.max_constraints: Max constraints to generate (default: 5)
---   ctx.max_repairs: Max p_tts repair attempts (default: 1)
---   ctx.plan_tokens: Max tokens for planning (default: 400)
---
--- Phase 2 (negation) options:
---   ctx.max_conditions: Max destruction conditions (default: 4)
---
--- Phase 3 (critic) options:
---   ctx.rubric: Table of {name, description} dimension definitions
---   ctx.threshold: Min acceptable score per dimension (default: 7)
---   ctx.max_revisions: Max critic revision rounds (default: 1)
---
--- General options:
---   ctx.gen_tokens: Max tokens for generation steps (default: 600)
---   ctx.skip_phases: NOT SUPPORTED — all phases run. Partial execution
---                    produces sub-standard output and is not meaningful.

local M = {}

---@type AlcMeta
M.meta = {
    name = "robust_qa",
    version = "0.1.0",
    description = "Three-phase QA pipeline — constraint-first solving, adversarial stress-test, rubric evaluation",
    category = "pipeline",
}

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local gen_tokens = ctx.gen_tokens or 600

    local phases = {}

    -- ═══════════════════════════════════════════════════════════════
    -- Phase 1: p_tts — constraint-first solving
    -- ═══════════════════════════════════════════════════════════════
    alc.log("info", "robust_qa: ═══ Phase 1/3 — p_tts (constraint-first solving) ═══")

    local p_tts = require("p_tts")
    local p_tts_result = p_tts.run({
        task = task,
        max_constraints = ctx.max_constraints or 5,
        max_repairs = ctx.max_repairs or 1,
        plan_tokens = ctx.plan_tokens or 400,
        gen_tokens = gen_tokens,
        verify_tokens = 150,
    })

    local phase1 = {
        name = "p_tts",
        answer = p_tts_result.result.answer,
        constraints_total = p_tts_result.result.total_constraints,
        constraints_passed = p_tts_result.result.pass_count,
        constraints_failed = p_tts_result.result.fail_count,
        repairs = p_tts_result.result.repairs,
        all_passed = p_tts_result.result.all_passed,
        plan = p_tts_result.result.plan,
        constraints = p_tts_result.result.constraints,
    }
    phases[#phases + 1] = phase1

    alc.log("info", string.format(
        "robust_qa: Phase 1 complete — %d/%d constraints passed, %d repairs",
        phase1.constraints_passed, phase1.constraints_total, phase1.repairs
    ))

    local current_answer = phase1.answer

    -- ═══════════════════════════════════════════════════════════════
    -- Phase 2: negation — adversarial stress-test
    -- ═══════════════════════════════════════════════════════════════
    alc.log("info", "robust_qa: ═══ Phase 2/3 — negation (adversarial stress-test) ═══")

    local negation = require("negation")
    local neg_result = negation.run({
        task = task,
        answer = current_answer,
        max_conditions = ctx.max_conditions or 4,
        gen_tokens = gen_tokens,
        verify_tokens = 200,
        revise_tokens = gen_tokens,
    })

    local phase2 = {
        name = "negation",
        answer = neg_result.result.answer,
        conditions_total = neg_result.result.total,
        conditions_holding = neg_result.result.holding,
        conditions_refuted = neg_result.result.refuted,
        survived = neg_result.result.survived,
        revised = neg_result.result.revised,
    }
    phases[#phases + 1] = phase2

    alc.log("info", string.format(
        "robust_qa: Phase 2 complete — %d/%d conditions refuted, survived=%s, revised=%s",
        phase2.conditions_refuted, phase2.conditions_total,
        tostring(phase2.survived), tostring(phase2.revised)
    ))

    current_answer = phase2.answer

    -- ═══════════════════════════════════════════════════════════════
    -- Phase 3: critic — rubric-based evaluation
    -- ═══════════════════════════════════════════════════════════════
    alc.log("info", "robust_qa: ═══ Phase 3/3 — critic (rubric evaluation) ═══")

    local critic = require("critic")
    local critic_result = critic.run({
        task = task,
        answer = current_answer,
        rubric = ctx.rubric,
        threshold = ctx.threshold or 7,
        max_revisions = ctx.max_revisions or 1,
        gen_tokens = gen_tokens,
        eval_tokens = 200,
        revise_tokens = gen_tokens,
    })

    local phase3 = {
        name = "critic",
        answer = critic_result.result.answer,
        scores = critic_result.result.scores,
        avg_score = critic_result.result.avg_score,
        revisions = critic_result.result.revisions,
    }
    phases[#phases + 1] = phase3

    alc.log("info", string.format(
        "robust_qa: Phase 3 complete — avg_score=%.1f, %d revisions",
        phase3.avg_score, phase3.revisions
    ))

    -- ═══════════════════════════════════════════════════════════════
    -- Final summary
    -- ═══════════════════════════════════════════════════════════════
    local final_answer = phase3.answer

    alc.log("info", string.format(
        "robust_qa: ═══ Pipeline complete ═══\n"
            .. "  Phase 1 (p_tts):    %d/%d constraints passed\n"
            .. "  Phase 2 (negation): %d/%d conditions survived\n"
            .. "  Phase 3 (critic):   avg=%.1f/10",
        phase1.constraints_passed, phase1.constraints_total,
        phase2.conditions_refuted, phase2.conditions_total,
        phase3.avg_score
    ))

    ctx.result = {
        answer = final_answer,
        phases = phases,
        -- Convenience fields
        constraints_passed = phase1.all_passed,
        adversarial_survived = phase2.survived,
        critic_avg_score = phase3.avg_score,
        critic_scores = phase3.scores,
        -- Traceability
        phase1_answer = phase1.answer,
        phase2_answer = phase2.answer,
        phase3_answer = phase3.answer,
    }
    return ctx
end

return M
