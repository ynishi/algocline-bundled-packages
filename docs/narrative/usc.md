---
name: usc
version: 0.1.0
category: aggregation
description: "Universal Self-Consistency — LLM-based consistency selection across free-form responses. Extends SC to open-ended tasks where majority vote is inapplicable."
source: usc/init.lua
generated: gen_docs (V0)
---

# USC — Universal Self-Consistency

> Extends standard Self-Consistency (SC) to free-form generation tasks. Instead of majority voting on extracted answers (which requires structured answer formats), USC concatenates all candidate responses and asks the LLM to select the most consistent one.
