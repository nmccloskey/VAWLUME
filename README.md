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
- schema support for experimental hierarchy, extractor-native objects, detections, feature semantics, cross-extractor matching, derived analysis, and external event/timebase alignment.

The reusable `source_mapping` engine now completes the Phase 2 checkpoint and
the Phase 2.5 native-configuration cleanup: it loads canonical JSON profiles
with MATLAB-native decoding, validates explicit profile content and language
versions, discovers and parses project sources, maps supplied extractor tables
through registered transforms, produces a validated intermediate
representation, and renders a database-free dry-run preview. Project intake is
the next architectural implementation target, followed by the first real
extractor importers.

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
Python or PyYAML runtime dependency; project intake remains the next
implementation target.

## Documentation

- [`docs/design/01_prototype_development_outline.md`](docs/design/01_prototype_development_outline.md) — current prototype development plan
- [`docs/development/01_repo_structure.md`](docs/development/01_repo_structure.md) — repository policy and MATLAB-specific layout
- [`docs/development/02_development_workflow.md`](docs/development/02_development_workflow.md) — development conventions for the prototype

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
