---
name: bisect
version: 0.1.0
category: debugging
description: "Binary search for reasoning errors — locate first incorrect step in O(log n), then regenerate from that point"
source: bisect/init.lua
generated: gen_docs (V0)
---

# bisect — Binary search for reasoning errors

> Instead of verifying every step of a reasoning chain (O(n)), bisects the chain to locate the first error in O(log n) steps. Once found, regenerates only the erroneous step and continues.
