# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-03-18

### Added

- **9 reasoning strategy packages**: bisect, blind_spot, cascade, claim_trace, critic, dmad, negation, p_tts, verify_first
- **robust_qa**: composite pipeline combining p_tts, negation, and critic
- **3 bundled eval scenarios** (`scenarios/` directory):
  - **math_basic**: arithmetic and number theory (7 cases, contains + exact_match)
  - **reasoning_basic**: logical reasoning and common knowledge (5 cases, contains)
  - **factual_basic**: factual knowledge with verifiable answers (5 cases, contains)

## [0.2.0] - 2026-03-15

### Added

- **10 reasoning strategy packages**: ucb, panel, cot, sc, reflect, calibrate, contrastive, meta_prompt, factscore, cove
- **deliberate**: structured decision-making combinator (decompose → branch reasoning → synthesize)
- **pre_mortem**: feasibility-gated proposal filtering (factscore → contrastive → calibrate → pairwise ranking)
- **4 intent understanding packages**:
  - **ambig**: AMBIG-SWE detect-clarify-integrate pipeline (ICLR 2026)
  - **prism**: cognitive-load-aware intent decomposition with topological sort (arXiv:2601.08653)
  - **intent_discovery**: exploratory intent formation via DiscoverLLM (arXiv:2602.03429)
  - **intent_belief**: Bayesian intent estimation with diagnostic questions (arXiv:2510.18476)

### Changed

- **review_and_investigate**: enhanced pipeline with span-based code slicing, migrated to alc.parse_score
- **cove, factscore, review_and_investigate**: added `grounded = true` to verification phases
- **README**: added alc-runner agent integration guide

## [0.1.0] - 2026-03-15

### Added

- Initial release
- Collection layout with `*/init.lua` convention
- **review_and_investigate**: multi-phase code review pipeline (detect → cluster → verify → diagnose → research → prescribe → report)
