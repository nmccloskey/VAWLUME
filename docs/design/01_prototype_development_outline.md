# VAWLUME Prototype Development Outline

**Status:** Revised working development plan  
**Updated:** 2026-08-30
**Project stage:** Implemented through Phase 6 temporal candidate generation; assignment, consensus, agreement, and consilience remain next
**Primary implementation environment:** MATLAB + SQLite  
**Prototype objective:** Poster-ready, vertically integrated demonstration

---

# 1. Working prototype objective

Develop a poster-ready prototype of **VAWLUME** as a MATLAB-centered, database-oriented framework for reproducible vocalization analysis that demonstrates four linked scientific/software capabilities:

1. **Extractor-independent relational data modeling**
2. **Experimental and subject metadata integration**
3. **Cross-extractor detection matching and consilience-based validation**
4. **Sequence- and hierarchy-aware downstream analysis**

The prototype should demonstrate a coherent end-to-end workflow rather than attempt to become a feature-complete vocalization platform.

Its central architectural claim is now more specific:

> **VAWLUME provides a provenance-aware semantic mapping layer between heterogeneous external project/extractor structures and a common relational model, allowing extractor-specific information, experimental hierarchy, and downstream analytical relationships to coexist without being flattened into false equivalence.**

The prototype should show that:

- different extractors can generate different event populations from the same recording without being conflated;
- different project folder/file conventions can be ingested through user-configurable mappings rather than requiring a fixed directory layout;
- extractor-native levels and fields can be mapped into canonical VAWLUME concepts while preserving their original names, units, methods, and hierarchy;
- recording-device and experimental-setup metadata can be associated with recordings and inherited by extraction runs without hard-coding every possible parameter into SQL;
- cross-extractor event correspondence can be represented explicitly rather than by destructive merging;
- sequence analyses and hierarchical summaries can operate on extractor-specific or consensus event sets;
- external behavioral or neural event streams can be related to vocalization timelines through a lightweight timebase/alignment model even when direct TTL integration is unavailable.

---

# 2. Development logic

The primary dependency chain remains:

> **program goals → semantic contracts/configuration → database logic → data containers → program operations → outputs**

This replaces the earlier, simpler:

> program goals → database logic → data containers → program operations → outputs

because the project now has a clear **source-mapping/configuration layer** that must inform the schema.

The process is still iterative. Real DeepSqueak/MUPET artifacts, alignment edge cases, and downstream analysis needs may force schema or configuration revisions.

For implementation, however, the ordering is useful because it prevents:

- DeepSqueak or MUPET file formats from defining the database;
- user folder conventions from becoming hard-coded application logic;
- canonical feature names from erasing operational differences;
- downstream convenience from overriding provenance.

---

# 3. Current architectural vocabulary

The following terminology should be treated as provisional but preferred unless implementation reveals a stronger alternative.

## 3.1 `source_mapping`

**Module name:** `source_mapping`

Purpose:

- interpret externally named structures;
- parse files, paths, tables, and fields;
- map external names/levels into VAWLUME canonical concepts;
- normalize values/units without overwriting native values;
- preserve mapping provenance.

## 3.2 Semantic mapping layer

Conceptual term:

> **path/file/field-name semantic mapping layer**

The layer operates between external representations and the relational model.

Examples:

```text
user folder hierarchy
DeepSqueak output structure
MUPET output structure
behavior event export
future extractor output
        ↓
mapping profile
        ↓
VAWLUME canonical levels/fields + preserved native semantics
```

## 3.3 Mapping profiles

Configuration artifacts that declare how a source is interpreted.

Current categories:

- **project-input source mapping profile**
- **extractor-output source mapping profile**
- future external-event source mapping profiles

Examples already drafted:

- DeepSqueak v3.2 output mapping
- MUPET v2.1 output mapping
- folder-driven project hierarchy
- filename-driven project hierarchy
- dyadic/multi-subject project hierarchy

## 3.4 Recording-device profiles

Flexible JSON profiles representing acquisition hardware and recording-chain context.

Examples of profile content:

- manufacturer/model/device ID;
- nominal and actual sample rate;
- bit depth;
- channel configuration;
- gain/filtering when recoverable;
- interface;
- calibration state;
- placement/orientation where appropriate.

Detailed fields remain in JSON rather than becoming a large set of schema columns.

## 3.5 Experimental-setup profiles

Flexible JSON profiles describing the physical/behavioral recording context.

Examples:

- chamber identity;
- sound attenuation;
- lighting;
- white noise;
- arena geometry;
- divider state;
- microphone position;
- video presence;
- operant components;
- behavioral controller information;
- synchronization capabilities.

## 3.6 Extractor settings profiles

Detailed extractor configuration remains an external settings artifact, referenced by extraction-run provenance.

Examples:

- DeepSqueak detector settings/model identity;
- MUPET `config.csv` / `filestats.configpar`.

## 3.7 Profile linkage principle

A key distinction:

```text
source mapping profile
    = how external structure is interpreted

recording-device profile
    = how audio was acquired

experimental-setup profile
    = physical/behavioral context of acquisition

extractor settings profile
    = how an extractor processed the recording

extractor-output mapping profile
    = how the extractor's artifacts/fields are interpreted
```

These profiles should have stable IDs, versions, and checksums in the database while their detailed JSON content remains external.

---

# 4. Prototype design principles

## 4.1 Preserve source information

Normalization must be additive rather than destructive.

VAWLUME should retain:

- native artifact;
- native level;
- native field name;
- native value;
- native unit;
- extractor version;
- parser/mapping-profile version;
- canonical mapping;
- canonical normalized value where applicable;
- transform used.

## 4.2 Distinguish structural equivalence from metric identity

A shared canonical level or field does **not** imply identical measurement.

Examples:

```text
DeepSqueak call
MUPET syllable
    → canonical event / vocalization_event
```

but their segmentation boundaries may differ.

Likewise:

```text
DeepSqueak contour median frequency
MUPET mean frequency
    → broader frequency-center concept
```

while remaining methodologically non-equivalent.

## 4.3 Preserve meaningful extractor-native hierarchy

Extractor-native levels should not be flattened merely because VAWLUME has a canonical model.

Examples:

- MUPET workspace;
- MUPET data set;
- MUPET repertoire;
- MUPET repertoire unit;
- refined MUPET data set/repertoire;
- DeepSqueak detector artifact;
- DeepSqueak call;
- DeepSqueak classification/clustering run;
- DeepSqueak class/cluster.

## 4.4 Experimental hierarchy is configurable, not prescribed

VAWLUME should not require:

```text
study → group → animal → session → recording
```

as a universal tree.

It should also support:

- cohort;
- dyad;
- cage;
- interaction unit;
- observer/performer;
- resident/intruder;
- male/female partner;
- repeated sessions;
- multi-subject recordings.

The schema should therefore treat hierarchy and membership relationships as data.

## 4.5 Extractor hierarchy is not experimental hierarchy

A software grouping must not be silently translated into biological meaning.

Especially:

> A MUPET `data set` is an extractor/workspace-defined analytical grouping, not automatically a VAWLUME `study`, `group`, `session`, or `subject`.

## 4.6 Observations are not biological truth

Distinguish:

- extractor-specific detections;
- extractor review/filter state;
- classification assignments;
- candidate cross-extractor correspondence;
- matched groups;
- VAWLUME consensus events;
- consilience assessments;
- manual adjudication.

## 4.7 Make provenance queryable

Major records should be traceable to:

- source recording;
- project hierarchy;
- acquisition device/setup;
- extractor/version;
- extractor settings/model;
- extraction run;
- source artifact;
- mapping profile;
- transformation/analysis run.

## 4.8 Treat hierarchy as an analytical safeguard

Analytical outputs should preserve higher-level IDs and denominators so thousands of calls cannot accidentally substitute for a biological sample size of a handful of animals.

## 4.9 Keep the prototype vertically integrated

The pilot should implement each major concept only far enough to demonstrate an end-to-end workflow.

Do not turn the poster prototype into:

- a universal ontology;
- a full workflow engine;
- a generalized electrophysiology platform;
- a complete behavioral synchronization package.

---

# 5. Relational foundation — current schema architecture

A first `schema.sql` draft now exists and has been executable/fixture-tested in SQLite.

The schema should be treated as the current relational hypothesis rather than immutable API.

## 5.1 Generic experimental entities

Instead of fixed tables for every biological level, the schema uses generic experimental entities and typed relationships.

Core concepts:

```text
entity_types
experimental_entities
entity_relationships
```

These allow native/user-defined hierarchy names while preserving optional canonical roles.

This supports both hierarchical and membership relationships.

Example:

```text
study
  ↓
cohort
  ↓
dyad
 ↙   ↘
male female
  ↓
session
  ↓
recording
```

without forcing both animals into a single-parent tree.

## 5.2 Recordings

Recordings remain a stable central entity.

Expected stable concepts include:

- recording ID;
- source path/name;
- checksum;
- audio metadata;
- links to experimental entities;
- linked acquisition/setup profile snapshots.

Recording identity is the anchor for connecting multiple extractor runs.

## 5.3 Configuration/profile artifacts

The schema stores stable references for flexible profiles rather than arbitrary profile fields.

Relevant categories include:

- source mapping;
- extractor-output mapping;
- extractor settings;
- recording device;
- experimental setup;
- consilience policy;
- analysis configuration.

Profiles should preserve:

- profile ID;
- profile version;
- file path/URI;
- checksum;
- kind/type;
- capture/snapshot context.

## 5.4 Extractors and extraction runs

Core concepts:

```text
extractors
extraction_runs
extraction_run_inputs
extractor_artifacts
model_artifacts
```

An extraction run is a specific application of an extractor/version/settings/model context to one or more recordings.

The schema must guarantee that:

> two runs over the same recording remain distinct even if they produce similarly named events/features.

## 5.5 Extractor-native objects

The schema includes a generic representation for extractor-native higher-order objects.

Purpose:

- preserve MUPET data sets/repertoires/refinements;
- preserve DeepSqueak classification/clustering constructs;
- support future extractor-native hierarchy without new schema tables.

These objects should not automatically become biological hierarchy.

## 5.6 Detections/events

Extractor-specific detections remain first-class observations.

Each event must remain linked to:

- extraction run;
- recording;
- native artifact/object context;
- native ID where available.

No cross-extractor merge should destroy the native detections.

## 5.7 Feature semantics

The schema separates:

```text
extractor_features
canonical_features
feature_mappings
feature_relationships
event_measurements
```

This implements the semantic-mapping principle:

- native names are preserved;
- canonical concepts provide common access;
- pairwise feature relationships describe actual comparability;
- shared names alone do not imply equivalence.

## 5.8 Classification/review

Keep separate relational support for:

- review/curation state;
- classification runs;
- classes;
- assignments.

DeepSqueak `Accepted` should not become universal biological ground truth.

MUPET repertoire units should remain model/run-specific.

## 5.9 Cross-extractor correspondence

Matching should use separate layers:

```text
candidate pairs
    ↓
assignment / match groups
    ↓
consensus events
    ↓
consilience assessment
```

This preserves:

- one-to-one matches;
- one-to-many candidates;
- split/merge cases;
- unmatched detections;
- ambiguous assignments.

## 5.10 Derived analysis

Relational support should exist for:

- analysis runs;
- derived features/metrics;
- sequences;
- bouts;
- epochs;
- hierarchy-aware aggregation.

Derived values should never overwrite extractor-native measurements.

## 5.11 External event streams and alignment

The schema now reserves a lightweight synchronization layer for external data.

Core concepts include:

```text
timebases
external_streams
external_events
alignment_anchors
alignment_segments / transforms
aligned event times
```

Purpose:

- relate USVs to nose pokes, attacks, tones, shocks, social interactions, video annotations, photometry events, etc.;
- support cases where audio and behavioral/neural systems do not share direct TTL integration;
- store continuous raw data externally while keeping event/timebase provenance in SQLite.

This should remain modest in the prototype.

VAWLUME does not need to become a full continuous-signal analysis system.

---

# 6. Goal 1 — Extractor-independent relational data modeling

## Prototype claim

VAWLUME can represent outputs from multiple vocalization extractors in one relational system while preserving extractor-specific hierarchy, semantics, and provenance.

---

## Phase 1A — Finalize semantic contracts

### Status

Substantially underway.

Human-readable design references have been developed for:

- DeepSqueak;
- MUPET.

Built-in extractor-output mapping profiles have been drafted for:

- DeepSqueak v3.2;
- MUPET v2.1.

### Current mapping-profile responsibilities

Each profile describes:

- supported extractor/version;
- artifact discovery;
- native hierarchy;
- native-to-canonical level equivalencies;
- source-field parsing;
- native/canonical units;
- transformations;
- operational definitions;
- missing-value behavior;
- settings capture;
- validation checks;
- provenance;
- initial cross-extractor comparability.

### Important level mappings

Examples:

```text
DeepSqueak call
MUPET syllable
    → event
    → equivalence_class: vocalization_event
```

```text
DeepSqueak class/cluster
MUPET repertoire unit
    → classification_class
    → equivalence_class: extractor_native_class
```

The second mapping is structural only; it does not make the categories identical.

### Remaining work

- validate profiles against real outputs;
- refine version aliases;
- decide formal mapping-profile schema/validator;
- establish machine-readable profile inheritance/override rules.

---

## Phase 1B — Core SQL schema

### Status

First draft completed.

### Current scope

- generic experimental hierarchy;
- recordings;
- profiles/configuration references;
- extractors and extraction runs;
- artifacts/models;
- extractor-native objects;
- detections;
- feature dictionaries/mappings;
- review/classification;
- matching/consensus;
- sequence/derived analysis;
- external streams/timebase alignment;
- views, constraints, indexes, triggers.

### Immediate schema tasks

1. add a small fixture/seed package;
2. initialize shipped semantic vocabulary from mapping profiles;
3. run representative queries;
4. test awkward hierarchy cases;
5. test artifact/refinement lineage;
6. revisit tables that prove unnecessarily general or insufficient.

---

## Phase 1C — Built-in semantic vocabulary initialization

This phase becomes more important than the older outline anticipated.

`schema.sql` should define the database grammar.

Separate initialization should populate the current semantic vocabulary from built-in profiles.

Examples:

```text
extractors:
  DeepSqueak
  MUPET

canonical levels:
  recording
  extraction_run
  event
  classification_run
  classification_class

canonical features:
  call_start_time
  call_end_time
  call_duration
  frequency_min
  frequency_max
  frequency_bandwidth
  frequency_center
```

The database should not duplicate detailed profile definitions manually where the profile can be the authoritative source.

### Deliverable

A seed/registration operation that ingests built-in mapping profiles into the relational dictionaries.

---

## Phase 1D — Source-mapping engine

Implement the reusable `source_mapping` module.

### Responsibilities

- load mapping profile;
- discover source files;
- parse path/filename/table semantics;
- map native levels;
- map fields;
- normalize values/units;
- preserve native values;
- validate required fields;
- return an import-ready representation;
- log parse warnings/conflicts.

### Important separation

`source_mapping` interprets source structure.

It should **not** directly contain the entire database insertion workflow.

A likely flow:

```text
source_mapping.parse(...)
        ↓
validated intermediate representation
        ↓
ingestion/database layer
```

### Deliverables

- profile loader;
- regex/path parser;
- table-field parser;
- transformation registry;
- validation report;
- dry-run preview.

---

## Phase 1E — Project-input ingestion

Implement structure-agnostic user project parsing.

### Supported prototype patterns

At minimum:

1. folder-driven hierarchy;
2. filename-driven hierarchy;
3. multi-subject/dyadic hierarchy.

### Example user concepts

```text
study
group
cohort
animal
dyad
session
recording
```

but these names should be user-definable.

### Dry-run behavior

Before database insertion, report:

```text
files found
levels parsed
missing matches
multiple matches
cross-source conflicts
unresolved recordings
```

### Deliverables

- example project profiles;
- project intake manifest;
- validation report;
- ingestion into experimental entities/relationships/recordings.

---

## Phase 1F — Extractor-output ingestion

### Prototype target

DeepSqueak + MUPET.

### Current status

The DeepSqueak minimum is implemented through its tracked call-statistics
profile, explicit recording resolution, atomic run/artifact/event import, and
runnable demonstration. The MUPET minimum is implemented on the same terms
through its tracked per-syllable CSV profile, required settings provenance,
atomic syllable and measurement population, and its own runnable demonstration,
with both extractors tested importing one recording side by side. The Step 8
exit review has now been run and passed, so extractor-output ingestion is
complete for the two prototype extractors. Phase 1F's remaining scope —
cross-extractor correspondence — belongs to Goal 3 and Step 9. Its contract,
versioned specification, and temporal candidate generation are now implemented;
assignment and later correspondence stages remain pending.

### DeepSqueak minimum

Support at least:

- Excel call-statistics export;
- recording/native artifact linkage;
- call ID;
- timing;
- review/accept status;
- score;
- label;
- supported acoustic features;
- settings/model provenance where recoverable.

### MUPET minimum

Support at least:

- per-syllable CSV;
- recording linkage;
- syllable ID;
- timing;
- duration;
- native interval;
- frequency measures;
- energy/amplitude;
- config/settings provenance.

### Higher-order support

Architect for:

- MUPET data sets;
- repertoires;
- refined outputs;
- DeepSqueak classification/clustering.

Full native `.mat` support can remain beyond the first importer pass if needed.

---

# 7. Goal 2 — Experimental and subject metadata integration

## Prototype claim

VAWLUME can recover a user's experimental structure from their existing file/folder semantics and relate vocalization outputs to biologically meaningful units without requiring a fixed project layout.

---

## Phase 2A — Project structure mapping

This replaces the older assumption that metadata arrives primarily as a standard CSV/XLSX table.

A tabular metadata supplement can still be supported, but the primary user-facing concept is now:

> **declarative project source mapping**

Users define:

- hierarchy levels;
- relationships;
- parsing sources;
- regular expressions;
- literals;
- normalization mappings;
- validation rules.

### Example

```text
control/mouse_001/courtship/001_courtship_1.wav
```

can be interpreted as:

```text
study = courtship_pilot
group = control
subject = 001
session = courtship
recording_take = 1
```

without VAWLUME requiring that exact directory layout globally.

---

## Phase 2B — Metadata augmentation

Filesystem semantics will not always contain all metadata.

Support supplemental metadata through:

- CSV;
- XLSX;
- manually declared mappings;
- future structured formats.

Examples:

- genotype;
- phenotype;
- treatment;
- age;
- sex;
- behavioral score;
- manually established group equivalencies.

### Rule

Supplemental metadata should augment the relational entities created from project ingestion rather than create a parallel metadata system.

---

## Phase 2C — Recording-device integration

Recording-device profiles should be linked primarily to recordings.

### Principle

The acquisition device belongs to the production of the recording, not inherently to the extraction run.

Extraction runs may:

- inherit the linked device profile;
- snapshot the profile version/checksum;
- explicitly override if the analyzed representation differs.

### Prototype deliverables

- device-profile loader;
- recording-to-device linkage;
- run-time provenance snapshot.

---

## Phase 2D — Experimental-setup integration

Experimental-setup profiles should generally attach to:

- session;
- recording;
- or another appropriate experimental entity.

Extraction runs inherit setup context through their recording/session relationship.

### Examples

- courtship chamber;
- operant chamber;
- social-defeat enclosure;
- playback arena.

### Deliverables

- setup-profile loader;
- relationship/link table insertion;
- run context inheritance.

---

## Phase 2E — Analysis-ready relational views

Create reusable views connecting:

```text
detection
→ extraction run
→ recording
→ project hierarchy
→ device/setup context
```

and, after Goal 3:

```text
consensus event
→ member detections
→ recording
→ hierarchy
```

Possible views:

- call/detection analysis view;
- recording/session summary view;
- subject/dyad summary view;
- cross-extractor matched-event view;
- aligned behavior-event view.

---

## Phase 2F — Hierarchical safeguards

Prototype safeguards should include:

- explicit higher-level IDs in analytical outputs;
- biological and technical sample counts;
- required aggregation level;
- grouped train/test splitting;
- warnings when call-level data are being treated as independent units;
- support for role-specific subjects in shared recordings.

---

# 8. Cross-cutting capability — external behavioral/neural event coordination

This is not promoted to a fifth headline prototype goal yet.

It is a supporting interoperability feature connecting Goals 2 and 4.

## Motivation

VAWLUME vocalization sequences may need to be coordinated with:

- nose pokes;
- attacks;
- social contacts;
- cue onset;
- shocks;
- video-coded behaviors;
- photometry events;
- neural event timestamps.

Direct TTL integration may not be available.

## Prototype strategy

Provide a lightweight event/timebase model capable of representing:

```text
external stream
native timebase
event timestamps
alignment anchors
offset/drift transform
recording-relative aligned time
```

### Possible alignment modes

- exact shared timestamps;
- known constant offset;
- multiple anchor points;
- piecewise linear correction;
- manually established synchronization markers;
- external toolkit-derived alignment transform.

### Explicit non-goal

Do not attempt to implement a full photometry/video synchronization ecosystem in the pilot.

VAWLUME should instead be compatible with downstream aligners and preserve enough timing/provenance information to participate in them.

---

# 9. Goal 3 — Cross-extractor detection matching and consilience-based validation

## Prototype claim

VAWLUME can determine when detections from different extractors plausibly refer to the same underlying vocal event and quantify agreement without treating either extractor as automatic ground truth.

---

## Phase 3A — Candidate matching specification

Separate:

1. candidate generation;
2. candidate scoring;
3. assignment;
4. consensus grouping;
5. feature agreement;
6. consilience classification.

### Primary evidence

Timing:

- temporal overlap;
- onset difference;
- offset difference;
- duration difference.

### Supporting evidence

Where explicitly comparable:

- minimum frequency;
- maximum frequency;
- bandwidth;
- frequency-center measures.

### Exclude by default

- model-specific detector scores;
- non-equivalent energy/power metrics;
- extractor-native class labels unless explicitly mapped.

---

## Phase 3B — Candidate-pair generation

Candidate pairs should require:

- same recording;
- different extraction runs;
- plausible temporal relationship.

The schema already includes integrity logic enforcing the same-recording/different-run principle.

### Deliverable

A candidate table with transparent evidence fields.

---

## Phase 3C — Assignment and ambiguity

Handle:

- one-to-one;
- one-to-many;
- many-to-one;
- split/merge;
- unmatched;
- ambiguous.

Do not force a one-to-one solution where extractor segmentation disagrees.

---

## Phase 3D — Consensus events

A VAWLUME consensus event is a derived grouping of extractor-specific detections.

It must never replace its member detections.

Possible status examples:

- matched;
- ambiguous;
- split;
- merge;
- extractor-specific only.

---

## Phase 3E — Detection-level agreement

Possible metrics:

- matched proportion;
- extractor-specific unmatched proportion;
- symmetric overlap;
- temporal offset distribution;
- split/merge counts;
- manual-reference precision/recall where a reference subset exists.

ICC is not the primary measure of event detection agreement.

---

## Phase 3F — Feature-level agreement

For matched events and explicitly comparable features:

- ICC where appropriate;
- mean/median absolute differences;
- bias;
- Bland–Altman-style summaries;
- rank/Pearson association as secondary characterization.

The feature-relationship registry determines which comparisons are defensible.

---

## Phase 3G — Consilience rules

Possible VAWLUME statuses:

- single-extractor detection;
- temporally matched;
- matched with supporting feature agreement;
- matched with feature discrepancy;
- ambiguous split/merge;
- manually reviewed;
- adjudicated positive/negative.

Thresholds should belong to project/consilience configuration, not global extractor mapping profiles.

---

## Phase 3H — Manual QC anchor

Use a manageable manually reviewed subset to estimate:

- extractor-specific false positives/negatives;
- boundary differences;
- useful match thresholds;
- value of cross-extractor agreement;
- residual ambiguity.

The scientific question for the poster remains:

> Does cross-extractor consilience increase confidence and target manual review more efficiently than relying on one extractor alone?

---

# 10. Goal 4 — Sequence- and hierarchy-aware downstream analysis

## Prototype claim

VAWLUME can derive temporal and hierarchical analyses over extractor-specific, consensus, or externally aligned event sets while preserving the unit of biological inference.

---

## Phase 4A — Canonical temporal derivation

Generate VAWLUME-derived features from normalized timestamps.

Examples:

- inter-call interval;
- onset-to-onset interval;
- silence/non-call duration;
- elapsed time;
- local call rate;
- bout membership;
- bout duration;
- within-bout index.

### Important rule

Where an extractor provides its own version—e.g., MUPET inter-syllable interval—retain both:

```text
MUPET-native interval
VAWLUME-derived interval
```

and compare them for validation rather than overwrite either one.

---

## Phase 4B — Sequence construction

Sequence source can be:

- DeepSqueak detections;
- MUPET detections;
- VAWLUME consensus events;
- manually curated events;
- aligned external behavioral events;
- mixed event streams where analytically justified.

Sequence scope can be:

- recording;
- epoch;
- session;
- subject;
- dyad;
- behavioral window;
- extractor-specific event set.

---

## Phase 4C — Sequence descriptors

Candidate prototype measures:

- transition matrix;
- run length;
- repetition/recurrence;
- transition entropy;
- call-feature trajectories;
- lagged relationships;
- bout composition;
- event-triggered call summaries around external behaviors.

Limit the first implementation to a compact set that produces scientifically interpretable poster figures.

---

## Phase 4D — Behavioral/neural alignment analyses

Once an external event stream is aligned to the recording timebase, derive examples such as:

- calls before/after nose poke;
- call rate around attack onset;
- vocalization features around social-contact events;
- calls around photometry transients;
- peri-event sequence windows.

For continuous neural traces, VAWLUME should store/reference the external data and alignment rather than ingest every sample into SQLite.

---

## Phase 4E — Hierarchical aggregation

Provide explicit aggregation paths such as:

```text
event
→ bout
→ recording/epoch
→ session
→ subject/dyad
→ group/condition
```

Functions should record:

- source event set;
- aggregation level;
- number of lower-level observations;
- number of biological units;
- analysis run/provenance.

---

## Phase 4F — Hierarchy-aware inferential/ML example

Demonstrate at least one analysis that avoids call-level pseudoreplication.

Candidates:

- subject-level feature summary;
- mixed-effects model;
- hierarchical bootstrap;
- grouped cross-validation;
- grouped permutation.

One defensible example is preferable to a large ML suite.

---

## Phase 4G — Visualization

Candidate poster figures:

- extractor overlap/matching visualization;
- feature agreement plot;
- consilience status distribution;
- call-feature trajectory over sequence;
- transition matrix;
- peri-behavior event plot;
- hierarchy-aware group/subject distribution.

---

# 11. Cross-cutting implementation phases

## Phase A — Specification and semantic contract freeze

### Largely complete for pilot

Define:

- prototype claims;
- extractor scope;
- project-source mapping concept;
- DeepSqueak/MUPET mapping profiles;
- device/setup profile concept;
- schema vocabulary;
- explicit non-goals.

### Remaining exit criteria

- mapping-profile schema validator;
- fixture profile set;
- decisions on profile override/inheritance.

---

## Phase B — Relational foundation

### Current status

First `schema.sql` draft exists.

### Outputs

- `schema.sql`;
- entity dictionary;
- mapping-profile registration strategy;
- fixture database;
- representative queries;
- schema tests.

---

## Phase C — Source mapping and ingestion

Primary focus:

- `source_mapping`;
- project intake;
- profile loading;
- DeepSqueak import;
- MUPET import.

### Outputs

- mapping-profile parser;
- dry-run project intake;
- DeepSqueak adapter;
- MUPET adapter;
- provenance logging;
- import validation.

---

## Phase D — Cross-extractor correspondence

Outputs:

- candidate-pair generation;
- match scoring;
- assignment;
- ambiguity flags;
- consensus groups/events.

---

## Phase E — Validation and consilience

Outputs:

- detection agreement;
- feature agreement;
- consilience statuses;
- manual-QC comparison;
- threshold sensitivity.

---

## Phase F — Sequence, hierarchy, and alignment analyses

Outputs:

- temporal derived features;
- bouts/sequences;
- external event alignment;
- hierarchy-aware summaries;
- one inferential/ML-safe example.

---

## Phase G — Poster-ready integration

Outputs:

- example database;
- reproducible scripted workflow;
- figures;
- summary tables;
- architecture diagram;
- methods;
- limitations;
- poster claims.

---

# 12. Updated implementation-pass hierarchy

Each major component can still be developed through iterative Codex passes.

## Pass 1 — Contract/specification

Define:

- purpose;
- inputs;
- outputs;
- relational entities touched;
- mapping/profile dependencies;
- invariants;
- provenance;
- edge cases;
- acceptance tests.

## Pass 2 — Skeleton

Create:

- module/file;
- public function signatures;
- help/docstrings;
- test fixtures;
- placeholder logging/validation.

## Pass 3 — Nominal implementation

Implement the simplest supported workflow end-to-end.

## Pass 4 — Validation and edge cases

Add:

- malformed profiles;
- unmatched files;
- duplicate imports;
- conflicts;
- ambiguous matches;
- missing native fields;
- version mismatches.

## Pass 5 — Integration

Connect upstream/downstream modules.

## Pass 6 — Demonstration

Add:

- runnable example;
- provenance output;
- expected database rows;
- poster-relevant table/figure.

---

# 13. Updated recommended implementation sequence

The earlier outline proposed beginning with `schema.sql`.

That has now occurred conceptually and as a first executable draft.

Phase 1 completed Steps 1-4, Phase 2 completed Step 5, Phase 3 completed Step 6,
Phase 4 completed Step 7, and Phase 5 completed Step 8 as tested relational
checkpoints. The recommended sequence below remains the implementation spine,
with Step 9 — matching and consensus — as the active target. Its candidate
generation stage is complete; assignment and consensus remain next.

## Step 1 — Stabilize schema vocabulary

Review `schema.sql` against:

- DeepSqueak mapping profile;
- MUPET mapping profile;
- project-input examples;
- device/setup examples;
- external-event alignment needs.

Avoid major restructuring unless a concrete contract cannot be represented cleanly.

## Step 2 — Build semantic seed/registration logic

Register:

- extractors;
- canonical features;
- canonical levels;
- extractor-native feature definitions;
- feature mappings;
- feature relationships;
- shipped mapping profiles.

## Step 3 — Build a synthetic fixture database

Fixture should include:

- one study;
- multiple subjects;
- one dyad/multi-subject recording;
- two sessions;
- DeepSqueak and MUPET runs over the same recording;
- matched/unmatched detections;
- split/merge case;
- canonical + extractor-specific features;
- device/setup profile;
- one external behavioral event stream;
- manual QC subset.

## Step 4 — Write schema queries/tests before broad importer work

Examples:

- Which detections belong to each run?
- Which recordings were analyzed by both extractors?
- Which native and canonical features are available?
- Which recordings inherited which device/setup profile?
- Which experimental entities/roles belong to a recording?
- Which candidate pairs are legal?
- Which detections form one consensus event?
- Which external events align to a recording?
- Which derived features came from which analysis run?

Current checkpoint:

- clean schema creation is covered by MATLAB unit tests;
- shipped DeepSqueak/MUPET semantic registration is reproducible and conflict-checked;
- the synthetic fixture exercises multi-subject hierarchy, shared recordings, scoped native IDs, matching, review, and alignment;
- Q01-Q14 acceptance queries are tracked under `schema/fixtures/` and asserted by integration tests.

## Step 5 — Implement `source_mapping`

Current checkpoint complete:

- JSON profile loading with identity, kind, explicit content version, MATLAB regexp syntax, and checksum provenance;
- deterministic project-source discovery and path/filename semantic extraction;
- extractor table-field mapping through a closed transform registry;
- one normalized, provenance-bearing intermediate representation for project
  sources and supplied extractor tables;
- structured database-free preview and validation diagnostics;
- unit and integration coverage for all shipped executable profiles, with no
  database writes in the `source_mapping` namespace.

## Step 6 — Implement project intake

Current checkpoint complete:

- one public planning/apply API consuming validated project-input IR;
- explicit project identity separate from experimental hierarchy;
- portable source, entity, relationship, recording, and participant identity;
- mapping-profile, recording-device, and experimental-setup provenance;
- atomic application with immutable ingestion-attempt audit rows;
- idempotent graph reuse, explicit conflicts, relocation behavior, and
  relational read-back across all three shipped project patterns.

## Step 7 — Implement DeepSqueak importer

Current checkpoint complete:

- one public planning/apply importer plus one read-only workbook adapter;
- tracked-profile interpretation through the source-mapping IR, with native and
  canonical measurement evidence preserved;
- explicit recording, extraction-run, artifact, settings, and model provenance;
- atomic and idempotent detection, review, and native-label population with
  explicit identity conflicts;
- portable artifact identity, relocation behavior, and a runnable end-to-end
  demonstration.

## Step 8 — Implement MUPET importer

Critical proof that the design is not merely a generalized DeepSqueak schema.

Current checkpoint complete:

- one public planning/apply importer plus one read-only per-syllable CSV adapter;
- tracked-profile interpretation through the same source-mapping IR, with native
  and canonical measurement evidence preserved;
- required settings provenance, plus extraction-run, artifact, and optional
  native-artifact provenance;
- atomic and idempotent syllable and measurement population with explicit
  identity conflicts;
- portable artifact identity, relocation behavior, and a runnable end-to-end
  demonstration;
- **no fabricated curation, classification, or detector-score evidence**, and no
  experimental hierarchy inferred from MUPET workspace or dataset names;
- both extractors importing one recording through shared infrastructure, with
  each extractor's semantics preserved and no matching row created.

The proof this step existed to provide holds: the shared import core carries no
DeepSqueak or MUPET semantic literal in executable behavior, and MUPET's absent
capabilities are produced by its output profile rather than by a MUPET branch.

## Step 9 — Implement matching/consensus prototype

Temporal-first, ambiguity-preserving.

**Current checkpoint:** the caller-selected run-pair resolver, versioned
matching-spec registration, transparent temporal evidence, exhaustive candidate
generation, unmatched summaries, and atomic candidate persistence are
implemented. Candidate generation performs no assignment. Connected-component
groups, consensus timing, agreement statistics, and consilience remain later
Step 9 stages.

## Step 10 — Implement a small sequence/alignment analysis

Prefer one scientifically illustrative example over broad analytical scope.

---

# 14. Proposed repository organization

A possible early structure:

```text
VAWLUME/
├── schema/
│   ├── schema.sql
│   ├── seeds/
│   └── fixtures/
│
├── config/
│   ├── mapping_profiles/
│   │   ├── extractors/
│   │   └── examples/
│   ├── device_profiles/
│   └── setup_profiles/
│
├── src/
│   └── +vawlume/
│       ├── +db/
│       ├── +source_mapping/
│       ├── +ingest/
│       ├── +matching/
│       ├── +consilience/
│       ├── +sequence/
│       ├── +alignment/
│       └── +report/
│
├── tests/
│
├── examples/
│
└── docs/
```

This is a planning suggestion, not yet a frozen package/API structure.

---

# 15. Prototype boundaries

The first prototype should probably **not** attempt:

- exhaustive support for all vocalization extractors;
- a GUI;
- a generalized workflow engine;
- a universal experimental ontology;
- automatic hyperparameter optimization;
- full continuous neural-signal ingestion;
- complete photometry/video synchronization;
- every sequence metric;
- full machine-learning framework;
- definitive validation thresholds;
- automatic biological interpretation of extractor classes;
- automatic reconciliation of semantically incompatible features.

---

# 16. Updated prototype completion criteria

The prototype is successful when it can reproducibly demonstrate:

1. Create an empty VAWLUME SQLite database from `schema.sql`.
2. Register built-in semantic/mapping profiles.
3. Parse a user project hierarchy from path/file semantics.
4. Import/link subject, session, dyad/role, and recording structure.
5. Link recording-device and experimental-setup profiles.
6. Import DeepSqueak detections with run/settings/artifact provenance.
7. Import MUPET detections from at least one overlapping recording.
8. Preserve extractor-native hierarchy and fields.
9. Keep extraction runs and event populations distinct.
10. Expose explicitly comparable canonical features without erasing native definitions.
11. Generate cross-extractor candidate matches.
12. Resolve or flag one-to-one and ambiguous split/merge cases.
13. Create consensus-event groupings without replacing native detections.
14. Quantify detection-level agreement.
15. Quantify feature-level agreement for selected comparable features.
16. Assign transparent consilience/validation status.
17. Compare automated consilience to a manually reviewed subset.
18. Derive at least one sequence representation.
19. Import or reference at least one external behavioral event stream.
20. Demonstrate one aligned vocalization/behavior analysis.
21. Aggregate at an appropriate biological hierarchy.
22. Demonstrate one hierarchy-aware inferential or exploratory ML analysis.
23. Produce a small set of reproducible poster-ready figures/tables.
24. Trace major outputs back through source recording, experimental context, acquisition profile, extractor run, settings, artifacts, mappings, and transformations.

---

# 17. Immediate next planning target

With the schema, semantic seed, synthetic fixture, acceptance queries, Phase 2
`source_mapping` engine, Phase 3 project intake, and Phase 4 DeepSqueak import
in place, the next architectural hinge is the second real extractor import.

The recommended next target is:

## **MUPET import**

MUPET should reuse the established source-mapping, portable recording,
extraction-run, artifact, and native/canonical measurement boundaries while
preserving MUPET's own dataset, repertoire, syllable, and settings semantics.
It is the critical proof that the relational/import architecture is not merely
a generalized DeepSqueak schema. Shared importer helpers should be factored
only where the two implemented paths demonstrate genuine duplication.

The completed Phase 1-4 test and demonstration suite remains the regression
floor for that work.

---

# 18. Current project thesis in one sentence

> **VAWLUME is a MATLAB-centered, relational framework that maps heterogeneous project and extractor semantics into a provenance-aware common model so vocalization detections can be compared, validated, sequenced, aligned with external events, and analyzed at appropriate biological levels without erasing how those data were originally produced.**
