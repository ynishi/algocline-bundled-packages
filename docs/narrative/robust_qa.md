---
name: robust_qa
version: 0.1.0
category: pipeline
description: "Three-phase QA pipeline — constraint-first solving, adversarial stress-test, rubric evaluation"
source: robust_qa/init.lua
generated: gen_docs (V0)
---

# robust_qa — Three-phase quality assurance pipeline

> Chains three independent verification strategies into a single pipeline:   Phase 1 (p_tts):    Constraint-first solving — generate constraints BEFORE                        solving, verify solution against specification   Phase 2 (negation): Adversarial stress-test — generate destruction conditions,                        verify if they hold, revise if flaws found   Phase 3 (critic):   Rubric-based evaluation — score per dimension, revise                        weak areas with targeted feedback
