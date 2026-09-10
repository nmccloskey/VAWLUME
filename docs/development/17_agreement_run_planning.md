# Arbitrary-N agreement run planning

## Public API

```matlab
result = vawlume.agreement.compose(conn, recordingRef, sources, agreementSpec)
result = vawlume.agreement.compose(conn, recordingRef, sources, agreementSpec, Apply=true)
```

`sources` is the set of **source pairwise analyses**, not a run signature. The
arbitrary-N layer composes analyses, so it takes analyses:

```matlab
[7 8 9]
["m_ds_mupet", "m_ds_usvseg", "m_mupet_usvseg"]
struct(run_key="m_ds_mupet")
```

Each entry is an `analysis_run_id`, an analysis `run_key`, or a scalar struct
holding exactly one of those. Order carries no meaning and is normalized to a
canonical order — ascending sorted extractor-pair label, then source `run_key` —
which is what identity comparison and reporting use.

`recordingRef` uses the same selectors as `vawlume.matching.compare`:
`struct(recording_id=…)` or `struct(project_key=…, source_relative_path=…)`. It
is a caller assertion validated against every stored candidate row and match
group of every source analysis, and against each participating extraction run's
declared inputs. It is required rather than derived because a pairwise analysis
records its recording on its candidate and group rows, and an analysis may
legitimately hold neither.

`agreementSpec` mirrors `matchSpec`: `run_key` is required, and `run_label`,
`vawlume_version`, `source_commit`, `notes`, and `profile_path` are optional.

This document covers the analysis boundary: which sources are composable, how
the derived run is identified, and what provenance is persisted. The composition
those sources feed is
[18_agreement_composition.md](18_agreement_composition.md).

## Compatibility contract

A composable set is a **complete unordered pairwise set**. For N participating
extraction runs, all N·(N−1)/2 extractor pairs must be present exactly once.

The reason is evidential. With a pair missing, an absent supporting edge in a
composed result could not be distinguished from a pair that was never assessed,
and every agreement pattern read off the result would be ambiguous. Partial
coverage is a later design question, not a silent allowance: the policy names
its coverage rule and the validator refuses any other value.

Two extractors have exactly one unordered pair, so a single pairwise analysis is
already complete. The degenerate N=2 case is legal rather than special-cased,
and its composed result would simply be the pairwise partition.

| Rejection | Error identifier |
|---|---|
| no sources, or below the policy minimum | `vawlume:agreement:SourcesInvalid` |
| a source supplied twice | `vawlume:agreement:DuplicateSourceAnalysis` |
| unresolvable or ambiguous source | `…:SourceAnalysisNotFound` / `…:SourceAnalysisAmbiguous` |
| source is not a `cross_extractor_matching` run | `vawlume:agreement:SourceRunTypeInvalid` |
| source is not `completed`, or declares ≠2 inputs | `vawlume:agreement:SourceAnalysisIncomplete` |
| source belongs to another project | `vawlume:agreement:SourceProjectMismatch` |
| source rows or runs describe another recording | `vawlume:agreement:SourceRecordingMismatch` |
| source links ≠1 matching specification | `vawlume:agreement:SourceSpecificationMissing` |
| source compares two runs of one extractor | `vawlume:agreement:SameExtractorPair` |
| one extractor contributes two runs | `vawlume:agreement:RepeatedExtractor` |
| one extractor pair covered twice | `vawlume:agreement:DuplicateExtractorPair` |
| a pair missing, or outside the participating set | `vawlume:agreement:IncompletePairCoverage` |
| sources cite different matching specification versions | `vawlume:agreement:SpecificationVersionMismatch` |
| policy declares a coverage rule this pass does not implement | `vawlume:agreement:CoveragePolicyUnsupported` |

Requiring one run per extractor is a Phase 1 restriction, not a permanent one:
it is what makes an unordered extractor pair name exactly one comparison.

Two analyses under different matching specification versions have different
candidate universes, so composing them would build a component whose edges
answer different questions. Sources must cite one specification version.

## Agreement policy

`config/07_agreement_profiles/prototype_multi_extractor_agreement_spec.json`,
profile key `vawlume.agreement.multi_extractor.v0_1`, kind `consilience_policy`,
linked through `analysis_run_profiles` under assignment role
**`multi_extractor_agreement_spec`**.

The role name matters: `agreement_spec` is already taken by the pairwise
consilience child run, where it links the *matching* specification that produced
the statistics. Reusing it would put two different policies under one role.

The policy declares composition rules and nothing numeric:

| Field | Value | Meaning |
|---|---|---|
| `source_analyses.pairwise_coverage` | `complete_unordered_pair_set` | the compatibility rule above |
| `edge_universe.source` | `stored_candidate_pairs_of_declared_source_analyses` | what may support a component |
| `edge_universe.defines_no_temporal_threshold` | `true` | thresholds stay in the matching specification |
| `composition.component_rule` | `connected_components_over_supporting_edges` | how components form |
| `composition.clique_completeness` | `reported_not_required` | partial patterns are kept, not discarded |
| `composition.singleton_inclusion` | `true` | single-extractor evidence stays in the population |
| `composition.ambiguity_propagation` | `recorded_per_edge_never_used_to_exclude` | pairwise topology is reported, not a filter |
| `composition.feature_support_is_admission_criterion` | `false` | feature support never decides membership |

`agreementLoadSpec` enforces these. It also scans the whole document by field
name and refuses any threshold field — `min_temporal_iou`, `relative_tolerance`,
`minimum_supporting_comparisons`, and similar — with
`vawlume:agreement:SpecificationDeclaresThreshold`. The invariant is that this
policy owns no numeric evidence bound at all, so the check is by field name
across the file rather than at the two places a threshold would most plausibly
be added.

## What apply persists

The boundary rows below. Composition adds the component rows in the same
transaction; see [18_agreement_composition.md](18_agreement_composition.md).

- `config_profiles` + `config_profile_versions` for the policy (created or reused);
- one `analysis_runs` row, `run_type = 'multi_extractor_agreement'`;
- one `analysis_run_profiles` row under `multi_extractor_agreement_spec`;
- one `analysis_run_extraction_inputs` row per participating extraction run, role `agreement_input`;
- one `analysis_run_sources` row per source pairwise analysis, role `pairwise_source`.

`parent_analysis_run_id` stays NULL. Three pairwise parents cannot live in one
parent column; that is what `analysis_run_sources` exists for.

### Status tracks whether components exist

A run that carries lineage but no composed components is `started`, because
marking it `completed` would claim a derivation that has not been performed.
`started` is therefore a **reusable** state: composition completes such a run
rather than creating a second one, and the run keeps its `analysis_run_id`. A
`failed` run is not reusable, since its provenance may be partial.

A boundary-only run's notes record `composition_pending=true`; once composed,
the notes record the component rule instead. Notes are audit text either way -
derived identity is `group_key`, never a note.

## Identity, reuse, and conflict

`run_key` is caller-declared and unique per project, as everywhere else in the
repository. Reuse requires all of:

- same project and `run_key`;
- same policy profile version **and checksum**;
- same participating extraction runs, all under role `agreement_input`;
- same set of source pairwise analyses, all under role `pairwise_source`.

Anything else is a conflict with a message naming what differs. A rerun with the
same inputs in a different order reuses the same `analysis_run_id` and writes
nothing.

Apply on a conflicting plan **reports** the conflict and writes nothing, the same
way `vawlume.matching.compare` does; it neither raises nor overwrites. The
`vawlume:agreement:PlanConflict` error guards the private apply layer against
being called directly with a conflicting plan.

A second agreement run over a different source set coexists with the first: each
is its own derived result with its own lineage.

## Source analyses are evidence, not children

Composition reads the pairwise analyses. It does not rewrite them, re-parent
them, or touch their candidate rows, match groups, consensus events, or
consilience assessments. The test suite captures every source analysis's status,
notes, parent column, and row counts before applying and requires them unchanged
after.

Deletion is governed by the Phase 1.6 schema: `analysis_run_sources
.source_analysis_run_id` is `RESTRICT`, so a source pairwise analysis cannot be
deleted while a derived agreement run cites it.

## Files

- [`../../src/+vawlume/+agreement/compose.m`](../../src/+vawlume/+agreement/compose.m) — the public entry point
- `src/+vawlume/+agreement/private/` — `agreementBuildPlan`, `agreementResolveSources`, `agreementValidateCoverage`, `agreementLoadSpec`, `agreementApplyPlan`, `agreementPlanResult`, `agreementRoles`, `agreementInsertRow`, `agreementSha256OfFile`
- [`../../config/07_agreement_profiles/prototype_multi_extractor_agreement_spec.json`](../../config/07_agreement_profiles/prototype_multi_extractor_agreement_spec.json)
- [`../../tests/integration/test_agreement_run_planning.m`](../../tests/integration/test_agreement_run_planning.m)
- [`16_multi_extractor_agreement_schema.md`](16_multi_extractor_agreement_schema.md) — the tables this run's composition will write
