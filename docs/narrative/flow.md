---
name: flow
version: 0.2.0
category: substrate
description: "Flow Frame — FlowState + ReqToken substrate for composing algo-based pkg (ab_mcts / cascade / coevolve / ...). Light Frame: driver loop stays in user code. v0.2 adds session-spanning bound APIs (wrap_bound / verify_bound / llm_bound) that persist verify-side state across alc.llm yield boundaries."
source: flow/init.lua
generated: gen_docs (V0)
---

# flow — Light Frame substrate for composing algo-based pkg

> Provides two primitives:   FlowState — a plain table persisted via alc.state (KV primitive).   ReqToken  — a random nonce bound to a state, echoed by downstream               pkg results and verified on return.
