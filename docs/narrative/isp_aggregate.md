---
name: isp_aggregate
version: 0.2.0
category: aggregation
result_shape: isp_voted
description: "LLM aggregation via higher-order information (Zhang et al. 2025, arXiv:2510.01499). Paper-faithful ISP (inverse surprising popularity) and OW (optimal weight) aggregators with a calibration/run split mirror of conformal_vote. Non-paper-faithful meta-prompt SP path is an explicit opt-in for calibration-free settings."
source: isp_aggregate/init.lua
generated: gen_docs (V0)
---

# isp_aggregate — LLM Aggregation via Higher-Order Information.

> Based on: Zhang, Yan, Perron, Wong, Kong   "Beyond Majority Voting: LLM Aggregation by Leveraging Higher-    Order Information" (arXiv:2510.01499, 2025-10)

## Contents

- [Parameters](#parameters)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.agents` | any | optional | Array of agent specs (string prompt \| {prompt,system?,model?,temperature?,max_tokens?} table). Default: diversity-hinted builder of length n. |
| `ctx.calibration` | any | optional | Output of M.calibrate. REQUIRED for method ∈ {isp, ow_l, ow_i}. |
| `ctx.gen_tokens` | number | optional | Max tokens per 1st-order LLM call (default 200). |
| `ctx.method` | one_of("isp", "ow", "ow_l", "ow_i", "meta_prompt_sp") | optional | Aggregator. Default 'isp'. 'meta_prompt_sp' is NOT paper-faithful. |
| `ctx.n` | number | optional | Agent count when `agents` is nil (default 5). |
| `ctx.options` | array of string | **required** | Candidate labels |
| `ctx.second_order_gen_tokens` | number | optional | Only used with method='meta_prompt_sp' (default 400). |
| `ctx.task` | string | **required** | Question text presented to each agent |
| `ctx.tie_break` | one_of("first_in_options", "uniform_random") | optional | Score-tie rule (default 'first_in_options'). |
| `ctx.x_direct` | array of number | optional | REQUIRED for method='ow'. Length = #agents; each x_i ∈ [0,1]. |
| `ctx.x_eps` | number | optional | Clamp floor for σ_K⁻¹ input (default 1e-6). |
