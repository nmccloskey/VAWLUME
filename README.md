# VAWLUME

**Vocalization Analysis Workflow Liaison Using MATLAB Extensions**

> **Status:** Early prototype development. The schema, configuration contracts, and package API are working design hypotheses and may change substantially before a first public release.

VAWLUME is a MATLAB-centered, relational framework that maps heterogeneous project and extractor semantics into a provenance-aware common model so vocalization detections can be compared, validated, sequenced, aligned with external events, and analyzed at appropriate biological levels without erasing how those data were originally produced.

## Prototype goals

The prototype is organized around four linked capabilities:

1. **Extractor-independent relational data modeling**
2. **Experimental and subject metadata integration**
3. **Cross-extractor detection matching and consilience-based validation**
4. **Sequence- and hierarchy-aware downstream analysis**

A lightweight external-event/timebase layer supports coordination with behavioral or neural events without making VAWLUME a full continuous-signal synchronization platform.

## Workflow structure

VAWLUME provides a provenance-aware semantic mapping layer between heterogeneous external project/extractor structures and a common relational model.

```text
external project structure / extractor artifacts / event streams
                            ↓
                    mapping profiles
                            ↓
          canonical concepts + preserved native semantics
                            ↓
                     SQLite relational model
                            ↓
         matching / validation / sequence / alignment / analysis
```

Normalization is additive rather than destructive. Native fields, values, units, hierarchy, artifacts, and extractor/run provenance remain available even when VAWLUME also exposes canonical concepts.

## Current development state

The current design includes:

- an executable `schema/schema.sql` draft with Phase 1 integrity triggers and query views;
- DeepSqueak and MUPET extractor design references;
- built-in DeepSqueak and MUPET JSON output-mapping profiles;
- example project-input, recording-device, experimental-setup, and profile-linkage JSON;
- a specified source-mapping architecture;
- semantic seed registration for shipped DeepSqueak/MUPET output-mapping profiles;
- a deterministic Phase 1 synthetic fixture with representative acceptance queries and MATLAB tests;
- project-source discovery/path parsing and extractor table-field mapping;
- one provenance-bearing, validated source-mapping intermediate representation for project files and supplied extractor tables;
- a structured, human-readable, IR-only source-mapping dry-run preview with explicit readiness verdicts;
- transactional project intake that materializes portable sources, configurable
  experimental entity graphs, recordings, profile linkage, and immutable
  ingestion-attempt provenance from validated project-input IR;
- schema support for experimental hierarchy, extractor-native objects, detections, feature semantics, cross-extractor matching, derived analysis, and external event/timebase alignment;
- a versioned prototype matching/consilience specification and a transactional
  candidate, connected-component assignment, and consensus planner over
  explicitly selected extraction runs;
- registry-driven cross-extractor feature-pair discovery and read-only
  detection- and feature-level agreement summaries with explicit denominators.

The reusable `source_mapping` engine now completes the Phase 2 checkpoint and
the Phase 2.5 native-configuration cleanup: it loads canonical JSON profiles
with MATLAB-native decoding, validates explicit profile content and language
versions, discovers and parses project sources, maps supplied extractor tables
through registered transforms, produces a validated intermediate
representation, and renders a database-free dry-run preview. Project intake is
now implemented as the transactional boundary from that IR to the relational
project/entity/recording graph.

DeepSqueak import and MUPET import are both **implemented** through their event
populations, and both are tested importing the same recording side by side
through one shared relational and semantic architecture. Import itself creates
no cross-extractor result. Matching is implemented separately from import
through transparent temporal candidates, ambiguity-preserving match groups,
and topology-governed consensus lineage. Agreement between those populations is
then quantified separately again, read-only by default. Consilience statuses and
manual adjudication remain later stages.
`vawlume.ingest.deepsqueakExport` reads a
DeepSqueak Excel call-statistics export and routes it through the tracked
DeepSqueak output-mapping profile to a validated extractor-output IR, without
any database access. `vawlume.ingest.deepsqueak` then plans or atomically
applies the run and provenance graph for that export: it resolves an
established recording, the seeded DeepSqueak extractor, and the exact
output-mapping profile version, registers the extraction run with its export,
settings, model, and native artifacts, and materializes the call population as
detections, native and canonical event measurements, extractor review
evidence, and extractor-native label assignments. Planning and applying happen
in one atomic boundary, so an extraction run never exists without its calls.

`vawlume.ingest.mupetExport` reads a MUPET per-syllable CSV and optionally
captures native `config.csv` settings without database access.
`vawlume.ingest.mupet` resolves an established recording and then plans or
atomically applies the exact extractor version, mapping profile, run, settings
artifact, event CSV, optional native processed `.mat` artifact, the syllable
detections, and their native and canonical measurements. Settings provenance is
required to apply, because MUPET reprocesses a recording when its configuration
changes and a run without its exact settings is not reproducible.

MUPET's differences from DeepSqueak are preserved rather than smoothed over. The
exported duration keeps its pre-noise-reduction operational variant and is never
recomputed from the boundaries; the terminal inter-syllable interval keeps its
exported `NA` token as explicit missingness rather than becoming zero; and
because the per-syllable CSV exports no review state, no class label, and no
detector score, a MUPET import creates no curation or classification rows and no
detection score. Both importers share one extractor-neutral core for feature
resolution, event routing, profile-declared validation, and detection and
measurement population.

`vawlume.matching.compare` consumes two explicitly selected runs on one
recording and the tracked matching specification. Planning is read-only and
returns every positive-overlap pair meeting the configured temporal-IoU floor,
with overlap, IoU, and signed onset/offset/duration differences plus unmatched
counts. `Apply=true` atomically registers the checksum-bearing specification,
the derived analysis parent, the ordered `run_a`/`run_b` inputs, candidate rows,
connected-component groups (including explicit unmatched groups), and the
consensus rows permitted by topology. It deliberately creates no agreement or
consilience row. See
[`docs/development/07_matching_candidate_generation.md`](docs/development/07_matching_candidate_generation.md)
and
[`docs/development/08_matching_assignment_and_consensus.md`](docs/development/08_matching_assignment_and_consensus.md).

`vawlume.consilience.summarize` then quantifies what those groups say. It is
read-only by default and resolves the specification from the analysis itself
rather than from the caller, refusing to summarize groups under a specification
that did not produce them. Detection agreement reports per-run counts with the
denominator stated on every proportion, keeps group counts separate from
detection counts so a split component is never read as several matches, and
takes its temporal deltas from the stored candidate evidence rather than
recomputing them. Feature comparison is discovered through
`extractor_features.equivalence_class` and `feature_relationships` — never
through canonical name, which finds nothing at all for central frequency — and
is restricted to unambiguous one-to-one groups. `Apply=true` persists only
aggregate statistics, under a child analysis run parented to the matching
analysis. See
[`docs/development/09_detection_and_feature_agreement.md`](docs/development/09_detection_and_feature_agreement.md).

A disposable all-profile demonstration is available at
[`examples/project_intake_demo.m`](examples/project_intake_demo.m). It runs the
folder-driven, filename-driven, and dyadic project patterns through profile
validation, source mapping, preview, intake, and relational read-back; it also
demonstrates idempotency, root relocation, and tracked device/setup provenance.

A second disposable demonstration covers the DeepSqueak path at
[`examples/deepsqueak_import_demo.m`](examples/deepsqueak_import_demo.m). It
establishes one project recording, generates a small synthetic call-statistics
workbook, imports it, and reads back extraction-run and artifact provenance,
detections, native and canonical measurements, and review and label evidence. It
also shows an unchanged rerun and an artifact relocation producing no second
scientific population.

A third covers the MUPET path at
[`examples/mupet_import_demo.m`](examples/mupet_import_demo.m). It establishes
one project recording, generates a small synthetic per-syllable CSV and its
native `config.csv`, previews the mapped IR before any write, imports it, and
reads back run, artifact, and settings provenance, syllable detections, native
and canonical measurements, and the terminal inter-syllable `NA` preserved as
explicit missingness. It shows an unchanged rerun and a relocation of all three
artifacts, states the zero curation and zero classification counts positively,
and closes with a short appendix importing DeepSqueak onto the same recording so
the two populations can be seen coexisting. That appendix computes no
correspondence between them, and the run ends with zero candidate pairs, match
groups, consensus events, and consilience assessments.

From the repository root:

```matlab
addpath("examples")
project_intake_demo
deepsqueak_import_demo
mupet_import_demo
```

All three create every input they need under the system temporary directory and
remove it before returning.

## Configuration policy

Tracked configuration artifacts should describe reusable semantics or examples:

- extractor-output mapping profiles;
- project-input source mapping profiles;
- example device profiles;
- example experimental-setup profiles;
- profile-linkage examples.

User-specific runtime paths, local data, generated databases, and private project configuration should remain untracked.

See [`config/README.md`](config/README.md).

## Runtime dependency

Mapping-profile loading uses MATLAB-native JSON decoding through
`fileread` and `jsondecode`. It does not require Python or PyYAML for
configuration loading. See
[`docs/development/03_source_mapping_intermediate_representation.md`](docs/development/03_source_mapping_intermediate_representation.md).

## Development order

The current recommended order is:

1. stabilize schema vocabulary;
2. implement semantic seed/registration;
3. build a synthetic fixture database;
4. write representative schema queries/tests;
5. implement `source_mapping`;
6. implement project intake;
7. implement DeepSqueak import;
8. implement MUPET import;
9. implement matching/consensus;
10. implement one compact sequence/alignment analysis.

Phase 1 completed items 1-4 as a tested relational checkpoint. Phase 2
completed item 5 through the validated IR and dry-run boundary. Phase 2.5
completed the JSON/native-loader/profile-language cleanup without adding a
Python or PyYAML runtime dependency. Phase 3 completed project intake through
transactional application, provenance read-back, and the all-profile
demonstration. Phase 4 completed item 7: the DeepSqueak artifact adapter, its
Excel-to-IR boundary, the transactional run and artifact provenance graph, the
detection, measurement, review, and label population, and a reproducible
end-to-end demonstration. Phase 5 completed item 8: the MUPET CSV adapter, the
run and provenance graph, the atomic syllable and measurement population, the
dual-extractor proof that both importers reach one relational model without
semantic collapse, and a runnable MUPET demonstration with a bounded
co-residence appendix. Item 9, matching and consensus, is underway: its
versioned contract, temporal candidates, connected-component assignment,
explicit unmatched groups, and topology-gated consensus lineage are
implemented, as are registry-driven feature-pair discovery and detection- and
feature-level agreement. Consilience statuses, manual QC, and threshold
sensitivity remain pending, so nothing yet writes a consilience assessment or a
manual review.

The dual-extractor result is worth stating precisely, because it is what
distinguishes a shared architecture from two special cases. Both extractors
populate six broad canonical concepts over the same recording in comparable
units. Central frequency is deliberately *not* one of them: DeepSqueak's contour
median is registered under its own canonical name rather than the generic
`frequency_center` MUPET uses, so cross-extractor comparison of that concept must
go through the shared `equivalence_class` and the seeded feature relationship
rather than through a canonical-name join. Structural equivalence is queryable;
metric identity is never asserted.

## Documentation

- [`docs/design/01_prototype_development_outline.md`](docs/design/01_prototype_development_outline.md) — current prototype development plan
- [`docs/development/01_repo_structure.md`](docs/development/01_repo_structure.md) — repository policy and MATLAB-specific layout
- [`docs/development/02_development_workflow.md`](docs/development/02_development_workflow.md) — development conventions for the prototype
- [`docs/development/03_source_mapping_intermediate_representation.md`](docs/development/03_source_mapping_intermediate_representation.md) — source-mapping IR and dry-run contract
- [`docs/development/04_project_intake.md`](docs/development/04_project_intake.md) — transactional project-intake boundary and identity contract
- [`docs/development/05_deepsqueak_import.md`](docs/development/05_deepsqueak_import.md) — DeepSqueak import contract, identity, provenance, and limitations
- [`docs/development/06_mupet_import.md`](docs/development/06_mupet_import.md) — MUPET import contract, syllable identity, the deliberate curation/classification absences, and the shared extractor core
- [`docs/development/07_matching_candidate_generation.md`](docs/development/07_matching_candidate_generation.md) — explicit run-pair resolution, temporal candidate evidence, provenance, planning, and atomic apply
- [`docs/development/08_matching_assignment_and_consensus.md`](docs/development/08_matching_assignment_and_consensus.md) — connected-component topology, explicit unmatched groups, consensus lineage, and rerun semantics
- [`docs/development/09_detection_and_feature_agreement.md`](docs/development/09_detection_and_feature_agreement.md) — agreement denominators, registry-driven feature-pair discovery, comparison scope, and what is and is not persisted

Extractor-specific design references should live under:

```text
docs/reference/extractors/
```

rather than `.dev`, because they document shipped mapping contracts.

## Prototype boundaries

The first prototype is not intended to provide:

- exhaustive extractor support;
- a GUI;
- a universal experimental ontology;
- a generalized workflow engine;
- full continuous neural-signal ingestion;
- complete photometry/video synchronization;
- a full machine-learning framework;
- automatic biological interpretation of extractor-native classes.

The goal is a vertically integrated, reproducible demonstration of the architecture.
