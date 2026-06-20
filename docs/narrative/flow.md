---
name: flow
version: 0.4.0
category: substrate
description: "Flow Frame — FlowState + ReqToken + IR substrate for composing algo-based pkg (ab_mcts / cascade / coevolve / ...). Light Frame: driver loop stays in user code. v0.3 adds `flow.ir` — Schema-as-Data Node + Expr IR with Def→Compile→Exec; L3 surface complete (6 Node + 8 Expr + 1 L4 effect). v0.4 publishes the Constructor API + Introspect API (walk / type_of / children_of / refs_of) so engine integrators consume the Node tree via a frozen visitor contract."
source: flow/init.lua
generated: gen_docs (V0)
---

# flow — Light Frame substrate for composing algo-based pkg

> Provides three primitives:   FlowState — a plain table persisted via alc.state (KV primitive).   ReqToken  — a random nonce bound to a state, echoed by downstream               pkg results and verified on return.   IR        — Schema-as-Data Node + Expr IR with Def → Compile → Exec               (see `flow.ir`, `flow/doc/ir.md`). Host-neutral               substrate for authoring pipelines as a single Lua               table; effects enter only through the `step` Node               which calls an injected `opts.dispatch(ref, input)`.
