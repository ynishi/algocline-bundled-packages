---
name: topo_route
version: 0.1.0
category: routing
result_shape: "shape { analysis: string, confidence: number, description: string, dimensions: map of string to string, governance_addons: array of string, mitigations: string, packages: array of shape { package: string, role: string }, risks: string, topology: string }"
description: "Topology-aware meta-router — analyzes task characteristics and recommends optimal agent topology (linear/star/DAG/mesh/debate) with concrete package mappings. Generalizes Topological Sensitivity from 'From Spark to Fire' (Xie et al., AAMAS 2026). Same agents, different topology → up to 40% reliability variation."
source: topo_route/init.lua
generated: gen_docs (V0)
---

# topo_route — Topology-aware meta-router for multi-agent pipelines

> Analyzes task characteristics and recommends the optimal agent topology (linear, star, DAG, mesh, debate) along with concrete package combinations from the algocline bundled collection.

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.analysis_tokens` | number | optional | Max tokens for the analysis LLM call (default 600) |
| `ctx.available_packages` | any | optional | Override default package registry (reserved; not currently consumed) |
| `ctx.task` | string | **required** | Task description to route (required) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `analysis` | string | — | Raw LLM analysis text (kept for downstream consumers) |
| `confidence` | number | — | Parsed CONFIDENCE in [0, 1] (default 0.5 on parse failure) |
| `description` | string | — | Short topology description |
| `dimensions` | map of string to string | — | Task analysis axes; keys are complexity/decomposability/verification_need/adversarial_value/cost_sensitivity, values are LOW\|MEDIUM\|HIGH |
| `governance_addons` | array of string | — | Filtered governance packages from LLM suggestion (subset of {lineage, dissent, anti_cascade}) |
| `mitigations` | string | — | Suggested mitigation packages for those risks |
| `packages` | array of shape { package: string, role: string } | — | Flattened package list covering all roles of the selected topology plus governance addons |
| `risks` | string | — | Topology-specific risk summary |
| `topology` | string | — | Recommended topology name: linear \| star \| dag \| debate \| ensemble \| escalation |
