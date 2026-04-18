--- tools.docs.devin_wiki_config — human-curated inputs for .devin/wiki.json.
---
--- Consumed by `tools.docs.projections.devin_wiki` to build
--- `.devin/wiki.json` at the repository root (see pipeline-spec §7.6).
---
--- DeepWiki auto-crawls the entire repository — unlike Context7 it has
--- no `folders` filter. We therefore point DeepWiki at the canonical
--- narrative via `repo_notes` rather than a folders list.
---
--- Schema reference: https://docs.devin.ai/work-with-devin/deepwiki
---   * repo_notes[*].content : max 10,000 chars
---   * pages                 : max 30 (80 for enterprise accounts)
---   * repo_notes + page_notes : max 100 total

return {
    repo_notes = {
        {
            content =
                "algocline is an LLM amplification engine whose packages " ..
                "are Pure Lua modules executed via `alc.run(ctx)`. The " ..
                "authoritative per-package narrative lives at " ..
                "`docs/narrative/{pkg}.md` and is generated " ..
                "deterministically by `tools/gen_docs.lua` from each " ..
                "package's `init.lua` docstring plus its `M.meta` and " ..
                "`M.spec` tables. When generating wiki content, prefer " ..
                "these canonical narratives over re-deriving from the " ..
                "source files.",
        },
        {
            content =
                "Each bundled package declares `M.spec.entries.run.input` " ..
                "(and often `M.spec.entries.run.result`) using the " ..
                "`alc_shapes.t` combinator DSL. This is the single " ..
                "source of truth for a package's I/O contract — the " ..
                "Parameters table in the narrative is a projection of " ..
                "that DSL, not separate documentation. Do not contradict " ..
                "the narrative's Parameters / result with freshly-derived " ..
                "schemas.",
        },
        {
            content =
                "Strategies are invoked through `alc.run(ctx)` where " ..
                "`ctx` is a plain Lua table shaped by the package's " ..
                "`M.spec.entries.run.input`. An `alc.llm(prompt)` call " ..
                "inside a strategy pauses execution and resumes when the " ..
                "host provides the completion via `alc_continue`. Keep " ..
                "wiki pages aligned with this pause/resume execution model.",
        },
    },
    -- `pages` is intentionally omitted — algocline ships 105 packages,
    -- which exceeds DeepWiki's 30-page limit for non-enterprise accounts.
    -- Leaving `pages` unset lets DeepWiki apply its default cluster-based
    -- planning, steered by the repo_notes above.
}
