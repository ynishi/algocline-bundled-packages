--- tools.docs.context7_config — human-curated inputs for context7.json.
---
--- Consumed by `tools.docs.projections.context7_config` to build
--- `context7.json` at the repository root (see pipeline-spec §7.6).
---
--- Only static, repo-level fields belong here. The pipeline-fixed
--- fields (`$schema`, `folders = ["docs/narrative"]`) are injected by
--- the projection and MUST NOT be set in this table.
---
--- Schema reference: https://context7.com/schema/context7.json

return {
    projectTitle = "algocline",
    description  =
        "LLM amplification engine — Pure Lua strategies executed via " ..
        "`alc.run(ctx)` that structurally enhance LLM reasoning " ..
        "(CoT, Self-Consistency, CoVe, panel / ucb / cot / ... packages).",
    rules = {
        "Each package is a Pure Lua module with a top-level `M.meta` " ..
            "table describing identity (name / version / category / " ..
            "description) and shapes (`input_shape` / `result_shape` " ..
            "built from `alc_shapes.t` combinators).",
        "Invoke a strategy through `alc.run(ctx)`; `ctx` is a plain Lua " ..
            "table shaped by the package's `M.meta.input_shape`.",
        "An `alc.llm(prompt)` call inside a strategy pauses execution " ..
            "and resumes when the host provides the completion via " ..
            "`alc_continue`.",
        "Package narratives live under `docs/narrative/{pkg}.md` and are " ..
            "generated deterministically by `tools/gen_docs.lua` from " ..
            "each package's `init.lua` docstring plus its `M.meta`.",
    },
}
