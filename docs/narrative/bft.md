---
name: bft
version: 0.1.0
category: governance
description: "Byzantine Fault Tolerance quorum thresholds and impossibility bounds."
source: bft/init.lua
generated: gen_docs (V0)
---

# bft(BFT) — Byzantine Fault Tolerance impossibility bounds

> Pure-computation utility for BFT quorum thresholds and validation. No LLM calls; used as a governance primitive by higher-level packages such as `pbft`, `dissent`, and `anti_cascade`.

## Contents

- [Usage](#usage)
- [Theoretical foundations](#theoretical-foundations)
- [References](#references)

## Usage {#usage}

```lua
local bft = require("bft")
assert(bft.validate(7, 2))          -- 7 >= 3*2+1 = true
assert(bft.threshold(7, 2) == 5)    -- quorum = 2*2+1 = 5
assert(bft.max_faults(7) == 2)      -- floor((7-1)/3) = 2
```

## Theoretical foundations {#theoretical-foundations}

Lamport, Shostak, and Pease's core result (Theorem 1): with oral
messages, agreement is possible iff `n >= 3f + 1`, where `n` is the
total number of nodes and `f` is the number of faulty nodes. The
required quorum is `2f + 1` so that any two quorums share at least one
honest node. With signed messages (SM(m), §4 of the same paper), the
weaker bound `n >= f + 2` suffices.

In LLM agent swarms, "Byzantine faults" map to hallucinating,
adversarial, or compromised agents that may produce arbitrarily wrong
outputs. BFT bounds answer the governance question "given N agents,
how many can fail before consensus breaks?". Practical uses include
panel sizing (given an expected hallucination rate `f/n`), `pbft`
quorum derivation, and signed-message mode for agents producing
verifiable outputs (e.g. code with unit tests) where the weaker
`n >= f + 2` bound permits smaller panels.

## References {#references}

- Lamport, L., Shostak, R., Pease, M. (1982). "The Byzantine Generals
  Problem". ACM TOPLAS 4(3), pp.382-401.
  https://doi.org/10.1145/357172.357176
- Xie, ... et al. (2026). "From Spark to Fire". AAMAS 2026.
