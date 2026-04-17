---
name: rank
version: 0.1.0
category: selection
result_shape: tournament
description: "Tournament selection — generate candidates, pairwise LLM-as-Judge ranking"
source: rank/init.lua
generated: gen_docs (V0)
---

# Rank — generate candidates and select best via pairwise comparison

> Generates N candidate responses, then uses LLM-as-Judge to perform pairwise tournament selection. Produces a winner with reasoning.
