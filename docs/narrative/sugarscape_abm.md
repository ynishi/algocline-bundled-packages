---
name: sugarscape_abm
version: 0.1.0
category: simulation
description: "Sugarscape model — agents forage on a sugar landscape, emergent wealth inequality, Pareto-like distributions, and carrying capacity. Based on Epstein & Axtell (1996)."
source: sugarscape_abm/init.lua
generated: gen_docs (V0)
---

# sugarscape_abm — Sugarscape Agent-Based Model

> Agents on a 2D toroidal grid forage for sugar. Each cell has a sugar capacity and regrows at a fixed rate. Agents have metabolism (sugar consumed per step) and vision (how far they can see). Each step, an agent looks in four cardinal directions up to its vision range and moves to the nearest unoccupied cell with the most sugar. Agents die when sugar wealth reaches zero.
