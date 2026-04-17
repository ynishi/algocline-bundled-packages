---
name: step_verify
version: 0.1.0
category: validation
description: "Step-level reasoning verification — PRM-style LLM-as-Verifier that scores each reasoning step independently. Identifies the first point of failure and re-derives from the last correct step."
source: step_verify/init.lua
generated: gen_docs (V0)
---

# step_verify — Step-Level Verification (PRM-style, LLM-as-Verifier)

> Verifies each intermediate reasoning step independently, identifying exactly where errors occur. Retains only verified-correct steps and re-derives from the last correct point.
