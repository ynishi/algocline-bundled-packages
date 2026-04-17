---
name: blind_spot
version: 0.1.0
category: correction
description: "Self-Correction Blind Spot bypass — re-present own output as external source to trigger genuine error correction"
source: blind_spot/init.lua
generated: gen_docs (V0)
---

# blind_spot — Self-Correction Blind Spot bypass

> LLMs cannot correct errors in their own outputs but can successfully correct identical errors when presented as coming from external sources. This package exploits that asymmetry: generate an answer, then re-present it as a "colleague's draft" for the same LLM to review and correct.
