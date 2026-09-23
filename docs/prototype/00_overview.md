# VAWLUME Prototype Overview

> **Scope.** This document explains what the VAWLUME prototype is trying to do, how its major capabilities fit together, what is implemented now, and where its current boundaries lie. Procedural instructions belong in the [prototype usage guide](01_usage_guide.md); implementation-level contracts belong under [`docs/design/`](../design/) and [`docs/development/`](../development/).
>
> **Status.** VAWLUME is a research prototype, not a released or scientifically validated tool. Its schema, configuration contracts, and public MATLAB API remain subject to change. Numeric thresholds shipped with the prototype are demonstration values unless explicitly documented otherwise.

## 1. Purpose and niche

VAWLUME — **Vocalization Analysis Workflow Liaison Using MATLAB Extensions** — is a MATLAB-centered, relational framework for connecting analyses that are usually performed in separate tools.

Its central design aim is to make independent vocalization analyses interoperable **without collapsing their disagreement**.

A vocalization project can produce several representations of the same underlying experiment: extractor-specific detections and measurements, manual annotations, behavioral events, neural or acquisition timing events, pose tracks, identity evidence, microphone geometry, acoustic calibration/reference observations, caller-attribution outputs, and later sequence- or bout-level summaries. Those representations are useful precisely because they are not identical. VAWLUME therefore treats provenance, semantic differences, uncertainty, and correspondence as data rather than as cleanup problems to be silently removed.

VAWLUME is not itself a vocalization detector. It sits downstream of external extractors and upstream of analyses that need to compare or combine their outputs with one another and with other experimental evidence.

## 2. Six prototype goals

The project is currently organized around six linked goals.

| Goal | Current prototype status |
|---|---|
| **1. Relational ingestion of USV and other data** | Implemented for project metadata, DeepSqueak, MUPET, USVSEG, external events/alignment anchors, spatial/tracking inputs, acoustic-reference evidence, and imported caller-attribution outputs. |
| **2. Extractor consilience exploration / data-validation support** | Implemented for pairwise correspondence, ambiguity-preserving match groups, arbitrary-N agreement, feature comparison where semantics support it, independent manual-reference evaluation, and threshold sensitivity. |
| **3. Multimodal temporal alignment** | Implemented as user-anchored source-to-reference clock alignment with native timestamps retained, fit/QC evidence preserved, and common-time projection exposed downstream. |
| **4. Caller-attribution support** | Partially implemented. VAWLUME can represent spatial, tracking, identity, acoustic, correspondence, and imported attribution evidence and can apply declared decision policies. It does not yet estimate callers natively. |
| **5. Incorporating sequence / bout analysis** | Planned. Storage concepts exist, but no current workflow populates sequence or bout analyses. Future grouping rules must be explicit and provenance-bearing. |
| **6. Niche EDA for the above** | Early implementation exists for consilience-oriented exploration, support-pattern characterization, feature disagreement, threshold screening, metadata-aware sampling, and spectrogram examples. This area is expected to grow with the other goals. |

These are related capabilities rather than six independent products. The relational model provides the common substrate; correspondence and alignment make heterogeneous observations relatable; attribution and sequence/bout analysis add higher-level structure; and EDA exposes where those representations converge, diverge, or remain uncertain.

## 3. Core design principles

### 3.1 Preserve provenance before harmonizing semantics

VAWLUME normalizes additively rather than destructively. Native artifacts, field names, values, units, missing-value behavior, labels, extractor versions, run settings, and lineage remain queryable even when VAWLUME also exposes a canonical concept.

A shared representation therefore does not imply that two measurements are metrically identical. Feature relationships can express structural or analytical comparability without renaming unlike measurements into a false equivalence.

### 3.2 Keep import, correspondence, agreement, and interpretation separate

Importing two extractor outputs onto the same recording does not itself create a match. Pairwise matching is a separate analysis. Agreement and consilience are then derived from stored correspondence evidence rather than folded into ingestion.

That separation allows several matching specifications or threshold choices to coexist over the same native detections without rewriting the imported data.

### 3.3 Preserve ambiguity instead of forcing one-to-one answers

Cross-extractor correspondence can be one-to-one, one-to-many, many-to-one, unmatched, or more complex once several extractors are considered together. VAWLUME keeps those component shapes explicit.

For arbitrary-N agreement, a complete set of pairwise analyses is composed into groups over native detections while retaining the **actual supporting pairwise edges**. Connectivity is not treated as proof of complete agreement, and no missing transitive edge is invented. An extractor-unique event remains a singleton rather than disappearing from the analysis population.

### 3.4 Treat consilience as evidence, not truth

Cross-extractor convergence is methodological evidence about the behavior of the extractors under a declared correspondence rule. It is not automatically:

- a probability that a biological vocalization occurred;
- a calibrated confidence score;
- proof that an extractor-unique event is false;
- evidence about which animal vocalized; or
- a substitute for independent manual ground truth when scientific validation requires one.

Manual reference events and manual adjudication therefore remain independent of automated consilience status.

### 3.5 Keep uncertainty dimensions separate until a declared method combines them

Temporal-alignment uncertainty, pose/localization evidence, visual-identity evidence, acoustic evidence, correspondence evidence, and imported caller-attribution scores have different semantics. VAWLUME stores them separately rather than averaging them into a generic confidence value.

A later analysis may combine them, but that combination should itself be explicit, versioned, and reproducible.

### 3.6 Preserve native clocks and derive common time

Temporal alignment does not overwrite source timestamps. Native times remain the primary observations; source-to-reference transforms and their supporting anchor evidence are stored separately, and common-time projections are derived from them.

### 3.7 Prefer auditable, versioned analysis over hidden defaults

Mapping profiles, matching rules, agreement policies, alignment manifests, and attribution policies are explicit configuration artifacts. Database-facing workflows plan before applying and are intended to commit derived state atomically rather than partially mutating a project.

## 4. Conceptual workflow

```text
project structure / extractor artifacts / external events / tracking / attribution
                                  |
                                  v
                     versioned mapping + provenance
                                  |
                                  v
                       SQLite relational model
                                  |
          +-----------------------+-----------------------+
          |                       |                       |
          v                       v                       v
 extractor correspondence   temporal alignment      multimodal evidence
 + consilience              + common time           + caller support
          |                       |                       |
          +-----------+-----------+-----------+-----------+
                      |                       |
                      v                       v
              analysis populations      sequence / bout layer
              + niche EDA               (planned)
                      |
                      v
                 export / reuse
```

Dense continuous signals are not generally copied into SQLite. Where appropriate, VAWLUME registers their provenance and reads bounded windows from linked artifacts while keeping the relational database focused on identities, events, measurements, evidence, transformations, and derived analyses.

## 5. Relational ingestion and semantic mapping

The prototype uses versioned JSON mapping profiles to interpret heterogeneous external sources into a validated intermediate representation before database application. The source-mapping boundary is intentionally independent of SQLite identifiers: parsing and semantic interpretation happen before project-specific database identity is assigned.

The current extractor integrations are:

- **DeepSqueak** — Excel call-statistics exports;
- **MUPET** — per-syllable CSV exports, with run settings provenance where available/required; and
- **USVSEG** — `<stem>_dat.csv` event exports, with extractor-version declaration and preservation of unclaimed source columns.

The three importers reach a shared relational model but do not pretend their native semantics are identical. Extractor-specific absences remain absences rather than being synthesized. For example, an importer does not create a detector score, review state, class label, or frequency extent when the source artifact did not provide one.

The same general modeling approach also supports project/entity metadata, external events, timebases and anchors, coordinate systems, microphone placement, tracking-stream registration, identity evidence, acoustic-reference evidence, and imported attribution outputs.

The authoritative database model is [`schema/schema.sql`](../../schema/schema.sql). An exported representation is available through [`schema/schema.json`](../../schema/schema.json).

## 6. Extractor consilience and data-validation support

Extractor consilience is the most distinctive analytical layer in the current prototype.

The workflow does not ask only which extractor is “best.” Instead, it keeps each extractor's native detection population and asks how those populations relate under an explicit correspondence rule.

### Pairwise correspondence

Pairwise matching begins with explicitly selected extraction runs on the same recording. Candidate evidence is based on the declared matching specification and is stored separately from later agreement or consilience summaries.

Connected components preserve correspondence topology rather than forcing a bijection. A component may therefore represent a clean one-to-one relation, a split/merge pattern, or an unmatched event.

### Arbitrary-N agreement

For N extractor runs, VAWLUME composes a complete set of compatible pairwise analyses. Agreement groups retain:

- their native detection members;
- the exact extractor pairs that provided supporting edges;
- the distinction between group count and native-member count; and
- ambiguity that would be lost by reducing everything to “K of N extractors agreed.”

This means two three-extractor components can both have two supporting extractor pairs while still representing different exact support patterns.

### Feature agreement

Feature comparison is only performed when the schema explicitly records a supported relationship between extractor measurements. Similar names are not enough. This is important because extractors may operationalize duration, center frequency, contours, frequency bounds, amplitude, or “syllable” concepts differently.

### Independent manual reference

Manual reference events are scoped independently of any extractor or matching analysis. They can therefore be used to evaluate extractor populations without turning one extractor's curation into ground truth for another.

### Threshold sensitivity and EDA

Several correspondence configurations can coexist over the same native events. VAWLUME can compare resulting populations and summaries without naming a configuration “optimal.” Current exploratory workflows characterize exact support patterns, inspect candidate-metric behavior, sample examples, render spectrogram context, and expose thin-data conditions rather than hiding them.

Every shipped matching, tolerance, and manual-reference threshold should currently be treated as provisional unless explicitly calibrated outside the prototype.

## 7. Multimodal temporal alignment

VAWLUME supports lightweight event-level synchronization across acquisition systems by relating source clocks to a declared reference clock through user-supplied logical anchors.

Implemented transform families include offset, affine, and continuous piecewise-affine mappings over caller-declared breakpoints. Anchor identities are explicit; VAWLUME does not discover synchronization pulses from raw waveforms or pixels.

The alignment layer preserves:

- native timestamps;
- the source and reference timebases;
- the exact observations used to fit a transform;
- per-anchor residual evidence;
- coverage information;
- transform identity and coefficients; and
- common-time projections derived from, rather than substituted for, native time.

A solved transform is an estimate, not automatically a validated synchronization result. No global calibrated fit threshold is currently claimed.

See [`docs/design/02_temporal_alignment_contract.md`](../design/02_temporal_alignment_contract.md) for the detailed contract.

## 8. Caller-attribution support

Caller attribution is treated as an integration problem before it becomes an estimator problem.

The current prototype can represent or register:

- declared coordinate systems;
- per-channel microphone positions;
- external tracking streams and bounded position reads;
- time-varying track-to-entity identity evidence;
- acoustic-reference intervals and per-channel response/QC measurements;
- attribution targets based on detections, consensus events, or agreement-group event sets;
- multiple candidate callers per target;
- separately typed attribution evidence; and
- imported attribution claims produced by an external system.

VAWLUME currently **does not estimate who called from those multimodal inputs**. The implemented attribution path preserves an external system's claims, relates its time windows to VAWLUME events under an explicit clock/correspondence rule, and can apply a declared decision policy. That policy does not implicitly combine pose, identity, alignment, acoustic, and correspondence evidence into one probability.

This keeps the architecture compatible with external localization/attribution systems while leaving room for a later VAWLUME-native estimator.

See [`docs/design/03_multimodal_input_contract.md`](../design/03_multimodal_input_contract.md) and the caller-attribution development documents under [`docs/development/`](../development/).

## 9. Sequence and bout analysis

Sequence- and bout-aware analysis remains a planned capability.

The relational schema already contains sequence/bout concepts, but the current prototype does not populate them through a supported analysis workflow. That is intentional: grouping vocal events into bouts or higher-order sequences requires definitions that may depend on extractor behavior, experimental context, timing rules, or an external analytical toolkit.

Extractor-native terminology should not silently become VAWLUME analytical semantics. In particular, an extractor that calls its event units “syllables” does not thereby define a VAWLUME bout. Future sequence/bout workflows should record the source event population, grouping rule or external method, parameters, and derived membership as provenance-bearing analysis.

The project therefore uses **incorporating sequence/bout analysis** as the goal: VAWLUME may implement some operations directly and may integrate specialized toolkits where that is more appropriate.

## 10. Niche exploratory analysis

VAWLUME's EDA is intended to expose properties that arise specifically from the integration layers above rather than to replace general statistical software.

Examples include:

- temporal “X-ray” views of extractor-specific and shared detection populations;
- exact pairwise and multi-extractor support-pattern summaries;
- split/merge and other correspondence ambiguity;
- feature disagreement conditional on support topology;
- threshold-sensitivity comparisons across matching configurations;
- metadata-stratified inspection of consilience patterns;
- spectrogram examples linked back to relational event identities;
- common-time inspection of vocalization populations alongside external events; and
- later, bout/sequence summaries over explicitly defined event populations.

The EDA layer should remain descriptive unless a separate inferential method justifies stronger conclusions.

## 11. Export and interoperability

VAWLUME can export relational data to CSV packages, including selective and schema-only use cases. Export is a supporting capability rather than one of the six scientific goals: its purpose is to make the relational model accessible to downstream analysis and documentation tools without requiring those tools to understand MATLAB's SQLite interface directly.

The generated [`schema/schema.json`](../../schema/schema.json) also supports schema visualization and documentation workflows.

## 12. Prototype boundaries

The current prototype is deliberately bounded. It is not intended to provide, yet:

- exhaustive extractor support;
- a GUI or general-purpose workflow engine;
- a universal experimental ontology;
- continuous neural/photometry/video sample ingestion into SQLite;
- automatic discovery of alignment anchors from raw signals;
- full acquisition-system synchronization;
- native pose estimation, image-based re-identification, or raw-video analysis;
- a VAWLUME-native caller-attribution estimator;
- a calibrated universal caller-confidence score;
- implemented sequence/bout/motif inference; or
- automatic biological interpretation of extractor-native labels.

Tracking and other dense data may remain external by design even as their identities, clocks, frames, coverage, and derived evidence become relationally addressable.

## 13. Validation status

The prototype has extensive synthetic demonstrations and regression/integration testing. The extractor-consilience exploration workflow has also completed an operational run on one real Pilot 3 recording containing DeepSqueak, MUPET, and USVSEG outputs.

That real-data run establishes that the software path can execute on real imported data. It does **not** establish scientific validity, calibrated correspondence thresholds, calibrated feature tolerances, or generalization across recordings, experiments, laboratories, or extractor configurations.

Comprehensive manually reviewed ground truth and broader real-data validation remain necessary before any threshold or configuration can be described as validated or recommended.

## 14. Relationship to external extractors

DeepSqueak, MUPET, and USVSEG are integrations, not VAWLUME components. VAWLUME contains none of their source code and does not invoke them as part of extraction.

The supported integrations reflect the starting point of the prototype, not a claim that these are the only relevant extractors. The mapping, provenance, correspondence, agreement, alignment, and downstream analysis layers are intended to remain extractor-agnostic; a new extractor should require an adapter/mapping contract for its actual outputs rather than a redesign of the relational architecture.

External projects:

- [DeepSqueak](https://github.com/DrCoffey/DeepSqueak)
- [MUPET](https://github.com/mvansegbroeck/mupet)
- [USVSEG](https://github.com/rtachi-lab/usvseg)

## 15. Schema and ERD

VAWLUME's relational model is defined by [`schema/schema.sql`](../../schema/schema.sql).

**[Explore the VAWLUME schema interactively with the Liam ERD](https://liambx.com/erd/p/github.com/nmccloskey/VAWLUME/blob/main/schema/schema.json?format=tbls).**

The ERD is generated from VAWLUME's exported schema representation rather than maintained as a separate hand-drawn diagram. [`schema/README.md`](../../schema/README.md) documents schema authority and regeneration.

## 16. Documentation map

Use the documentation by purpose:

- **[Prototype usage guide](01_usage_guide.md)** — practical setup, configuration, running examples, importing data, testing, and troubleshooting.
- [`../design/01_prototype_development_outline.md`](../design/01_prototype_development_outline.md) — prototype development plan.
- [`../design/02_temporal_alignment_contract.md`](../design/02_temporal_alignment_contract.md) — temporal-alignment contract.
- [`../design/03_multimodal_input_contract.md`](../design/03_multimodal_input_contract.md) — multimodal-input contract.
- [`../development/22_phase1_correspondence_boundaries.md`](../development/22_phase1_correspondence_boundaries.md) — orientation to native detections, pairwise correspondence, arbitrary-N agreement, and attribution boundaries.
- [`../development/35_consilience_exploration_workflow.md`](../development/35_consilience_exploration_workflow.md) — consilience-oriented exploratory workflow.
- [`../development/`](../development/) — implementation contracts and completed development work.
- [`../reference/extractors/`](../reference/extractors/) — extractor-specific mapping references.
- [`../../config/README.md`](../../config/README.md) — tracked configuration policy.
- [`../../schema/README.md`](../../schema/README.md) — database schema and generated representation.

The repository and executable tests remain authoritative when an older design document describes an earlier implementation state.
