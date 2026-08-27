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
- draft DeepSqueak and MUPET output-mapping profiles;
- example project-input, recording-device, experimental-setup, and profile-linkage YAML;
- a specified source-mapping architecture;
- semantic seed registration for shipped DeepSqueak/MUPET output-mapping profiles;
- a deterministic Phase 1 synthetic fixture with representative acceptance queries and MATLAB tests;
- project-source discovery/path parsing and extractor table-field mapping;
- one provenance-bearing, validated source-mapping intermediate representation for project files and supplied extractor tables;
- schema support for experimental hierarchy, extractor-native objects, detections, feature semantics, cross-extractor matching, derived analysis, and external event/timebase alignment.

The reusable `source_mapping` engine now reaches a validated intermediate
representation. The next target is human-readable dry-run preview and the
complete Phase 2 test matrix, followed by project intake and the first real
importers.

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

Mapping-profile loading uses an out-of-process Python 3 interpreter with
`PyYAML`. MATLAB selects `pyenv.Executable` by default; the public loader
and source-mapping entry points also accept an explicit `PythonExecutable`.
See
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

Phase 1 completed items 1-4 as a tested relational checkpoint; item 5 is the next active implementation target.

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
