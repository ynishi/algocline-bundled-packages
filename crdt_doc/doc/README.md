# crdt_doc — CRDT-backed shared document substrate

CRDT (Conflict-free Replicated Data Type) primitive over `alc.state`. Frame role
substrate: provides `Doc + Op + Merge` for **external collaboration Frames**
(state-rich orchestrators that live outside bundled-packages, per the design
philosophy `[実測: bundled-packages/README.md:1-5,44]` 「bundled は research-backed
reasoning strategy + Frame は rare、Orch 系は意図的に外部に分離」). **Substrate, not
orchestrator** — no `M.run` entry, no LLM call, sub-modules exposed as fields.

```lua
local crdt = require("crdt_doc")

local doc = crdt.doc.new({ id = "canvas-1" })
local op_a = { kind = "set_add", agent = "a", key = "title", value = "draft" }
local op_b = { kind = "lww_set", agent = "b", key = "title", value = "final",
               lamport = 7 }

crdt.merge(doc, op_a)
crdt.merge(doc, op_b)
local snapshot = crdt.doc.snapshot(doc)  -- { title = "final" }
```

## When to use

Use `crdt_doc` when multiple agents (LLM call peers / Strategy peers) edit a
shared state independently, and the merge must converge **mathematically**
(commutative + associative + idempotent) without an aggregator.

Do **not** use `crdt_doc` for:

- single-agent state (use `alc.state` directly)
- aggregator-based merge with judge / synthesizer (use `panel` / `triad` / `pbft`)
- semantic-level integration (`agent A 「太字」+ agent B 「削除」` の意味整合) —
  CRDT は構造的整合のみ保証。意味検査は将来 `semantic_validator` pkg の領分

## Initial lineup (Issue Open Q1)

Pure Lua 実装、native dep なし。`[理論値: Shapiro et al. 2011, §3.3-3.5]`

| Type | Source | Use case |
|---|---|---|
| **OR-Map** (tag-level primitive INSPIRED BY §3.3.5 Specification 15) | §3.3.5 | key-value store with concurrent add/remove |
| **LWW-Register** (Last-Writer-Wins, §3.4.1 Specification 9) | §3.4.1 | single value with timestamp tiebreak |

OR-Map は **tag-level primitive** で、論文 Specification 15 の `remove(e)`
(element-level) とは API が異なる。element-level remove は caller が
`doc.or_map.entries` を enumerate して観測 tag ごとに `set_remove` を発行
する責務 (詳細は `crdt_doc/or_map.lua` module docstring)。CvRDT merge 不変量
(commutative / associative / idempotent, Theorem 2.1) は tag 粒度で保たれる。

Y.Text 互換 sequence CRDT (RGA / Logoot) は v2。理由: pure Lua 実装 600+ 行
規模、Y.js binding は C bridge 必要 (no native dep 規約と衝突)。

## Op kind (declarative, Issue Open Q2)

各 op は kind を declarative 宣言。順序 dependency を持つ op は入口で reject
し runtime 検出は v2。`[実測: Issue 提案 §設計で詰めるべき open question Q2]`

```lua
-- OR-Map
{ kind = "set_add",    agent = "a", key = "k", value = v, tag = "a:42" }
{ kind = "set_remove", agent = "a", key = "k", remove_tag = "a:42" }

-- LWW-Register
{ kind = "lww_set",    agent = "a", key = "k", value = v, lamport = 7 }
```

Each op carries `agent` + (`tag` for OR-Set elements / `lamport` for LWW
ordering). `crdt.op.is_valid(op)` returns false for missing fields, ordered
mutations, or non-CRDT kinds.

## Merge invariants `[理論値: Shapiro 2011 §2.3, Theorem 2.1]`

State-based CRDT (CvRDT) requires the merge function `⊔` to satisfy:

- **Commutative**: `s1 ⊔ s2 = s2 ⊔ s1`
- **Associative**: `(s1 ⊔ s2) ⊔ s3 = s1 ⊔ (s2 ⊔ s3)`
- **Idempotent**: `s ⊔ s = s`

These are enforced by construction (OR-Map = ∪ of (key, value, tag) tuples, with
remove via tombstone; LWW-Register = max by lamport, lexicographic agent
tiebreak). `tests/test_crdt_doc.lua` exercises all three invariants on
hand-crafted op sets per CRDT type, plus a 3-agent integration test that
checks convergence across 3 distinct arrival orderings (fixed-order
convergence tests; random-sequence property testing is future work).

## Caller contract (must hold for convergence)

The substrate is intentionally minimal — three caller obligations are
NOT enforced inside the module and degrade convergence silently when
violated. See `crdt_doc/init.lua` `INJECTION POINTS` for the full text.

1. **Tag uniqueness (OR-Map)** — `op.tag` MUST be globally unique across
   all replicas. Convention: `agent_id .. ":" .. local_counter`. Reusing a
   tag yields non-deterministic merge.
2. **Lamport monotonicity (LWW)** — `op.lamport` MUST come from a
   per-replica monotonically-increasing clock. Same lamport from same
   replica with different values is undefined behaviour.
3. **Stable agent identity** — `agent` MUST be stable per replica and
   unique across replicas (used for LWW lex tiebreak + OR-Map provenance).

## alc_shapes contract (Frame role)

`crdt_doc` is a Frame `[実測: bundled-packages/README.md:20-29]`. Therefore:

- **No `M.run` entry**. Sub-modules exposed as fields:
  - `M.doc` — document lifecycle (`new` / `snapshot` / `clone`)
  - `M.op`  — op factory + validator (`set_add` / `set_remove` / `lww_set` / `is_valid`)
  - `M.merge` — pure merge function `(doc, op) → doc'`
- **No `alc.llm` call**. Pure Lua data structure operations only.
- `M.spec` declares per-entry input/result schemas via `alc_shapes`.
- `M.meta.category = "collaboration"` (Issue Q6 Human 決定済)

## Termination guidance (Issue Open Q4)

`crdt_doc` itself は無限に op を蓄積し続ける。termination 条件は caller
(`crdt_peers` 等 recipe 側) の責務。推奨 pattern:

- `max_rounds` 上限
- `quiescence_window`: 連続 N round で `crdt.doc.op_diff(doc, prev) == 0`
  なら終了

`crdt.doc.delta(doc, prev)` は **size proxy** で、size-stable mutations
(例: `add tag b:1` + `remove tag a:1` 同 key 内、LWW tiebreak 敗北 write)
を見逃す **false-positive 源**。quiescence 判定には必ず
`crdt.doc.op_diff(doc, prev)` を使う (monotonic `doc.op_count` フィールド
ベース、idempotent / 敗北 write 含む全 merge を数える)。

## Future work

- v2: Y.Text 互換 sequence CRDT (RGA), causal consistency layer (vector clock
  embedding), persistence (`alc.state`)
- 外部 Frame として: collaboration orch (LLM peers as CRDT participants、
  termination state 込み、alc.parallel で N peers 並列発行)。本 substrate の
  consumer になる予定だが bundled の外側で設計される (issue 別途起票予定)

## Reference

- Shapiro, M., Preguiça, N., Baquero, C., Zawirski, M. "A comprehensive study
  of Convergent and Commutative Replicated Data Types." INRIA Research Report
  RR-7506, 2011. https://hal.inria.fr/inria-00555588
- Nicolaescu, P. et al. "Near Real-Time Peer-to-Peer Shared Editing on
  Extensible Data Types." GROUP 2016. (Yjs / Y.Doc base)
