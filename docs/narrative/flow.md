---
name: flow
version: 0.6.0
category: substrate
description: "Flow Frame — FlowState + ReqToken + IR substrate for composing algo-based pkg (ab_mcts / cascade / coevolve / ...). Light Frame: driver loop stays in user code. v0.3 adds `flow.ir` — Schema-as-Data Node + Expr IR with Def→Compile→Exec; L3 surface complete (6 Node + 8 Expr + 1 L4 effect). v0.4 publishes the Constructor API + Introspect API (walk / type_of / children_of / refs_of) so engine integrators consume the Node tree via a frozen visitor contract. v0.5 adds Persistence API (to_json / from_json) with a 2-step injection seam (opts.alc + _G.alc) — host-neutral, caller supplies the JSON impl; round-trip property pinned across all 7 Node + 8 Expr. v0.6 completes the fanout join enum to the canonical Promise / futures combinator set (all / any / race / all_settled) with serial-fallback interpreter semantics; concurrent execution is engine territory (swarm-frame)."
source: flow/init.lua
generated: gen_docs (V0)
---

# flow — Light Frame substrate for composing algo-based pkg

> Provides three primitives:   FlowState — a plain table persisted via alc.state (KV primitive).   ReqToken  — a random nonce bound to a state, echoed by downstream               pkg results and verified on return.   IR        — Schema-as-Data Node + Expr IR with Def → Compile → Exec               (see `flow.ir`, `flow/doc/ir.md`). Host-neutral               substrate for authoring pipelines as a single Lua               table; effects enter only through the `step` Node               which calls an injected `opts.dispatch(ref, input)`.
