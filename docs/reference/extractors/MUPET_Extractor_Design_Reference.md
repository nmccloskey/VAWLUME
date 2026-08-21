# VAWLUME Extractor Design Reference: MUPET

**Purpose:** Design reference for VAWLUME's extractor contract, built-in MUPET template, relational schema, provenance model, and cross-extractor consilience logic.  
**Prepared:** 2026-08-20  
**Primary software scope reviewed:** MUPET v2.1 repository/source and associated documentation/publication.  
**Status:** Working design reference. This is not a replacement for MUPET documentation and should be updated if VAWLUME supports additional versions/forks.

---

## 1. Executive design summary

MUPET (Mouse Ultrasonic Profile ExTraction) is a MATLAB workflow for automated syllable detection, acoustic characterization, dataset summaries, repertoire construction, and repertoire comparison.

For VAWLUME design, MUPET is especially informative because it exposes a multi-level output structure:

1. **WAV recordings** organized into MUPET datasets;
2. **user-editable extraction configuration** in `config.csv`;
3. **per-recording processed MATLAB state** containing syllable data/statistics and configuration;
4. **per-syllable CSV exports**;
5. **dataset-level summary CSV exports**;
6. **repertoire models/units** derived by unsupervised analysis;
7. **refined datasets/repertoires** that can remove or reassign syllables.

This means that "MUPET output" should not be represented as one generic file type in VAWLUME. The extractor contract should distinguish:

- native processed artifacts;
- event-level exports;
- dataset summary artifacts;
- repertoire/classification artifacts;
- refinement/subset lineage.

MUPET also provides a particularly strong example of why VAWLUME feature definitions need more than a normalized name and unit. The source code contains multiple operational representations of "duration": the event-filtering logic uses a duration calculated after noise-reduction thresholding, while the per-syllable CSV exports a duration based on the earlier onset/offset interval. These are related but not identical quantities.

---

## 2. Evidence conventions used in this document

The notes distinguish:

- **Documented behavior** — stated in MUPET documentation/repository/publication.
- **Source-inspected behavior** — inferred directly from inspected MATLAB source.
- **VAWLUME design implication** — proposed architectural consequence.

Where paper defaults, editable config values, and source-level constants differ in role, they are kept distinct.

---

## 3. Software identity and scope

The MUPET repository identifies the current listed version as **v2.1**, dated 2018-05-27. The repository describes the program as a MATLAB system for rodent/mouse USV processing, acoustic statistics, repertoire generation, and repertoire comparisons.

Compared with actively changing DeepSqueak v3.x, the inspected MUPET codebase is comparatively stable/old. That does **not** make version provenance unnecessary. Its source contains algorithmic constants and report behavior not fully represented by the user-editable configuration file.

### VAWLUME consequence

Record at minimum:

```text
extractor_id
extractor_name = MUPET
extractor_version = 2.1
source_repository
source_commit_or_tag
matlab_version       # if known
```

A VAWLUME built-in template should state explicitly that it targets the inspected MUPET v2.1 behavior rather than pretending to cover arbitrary forks.

---

## 4. MUPET workflow as an extractor contract

A simplified conceptual workflow is:

```text
workspace
  |
  +-- audio dataset(s)
  |      |
  |      +-- WAV recording
  |              |
  |              v
  |         config.csv
  |              |
  |              v
  |      process / segment syllables
  |              |
  |              +-- per-recording .mat state
  |              +-- per-syllable CSV export
  |
  +-- dataset summaries
  |
  +-- repertoire construction
           |
           +-- repertoire units
           +-- repertoire comparisons
           +-- refined repertoires/datasets
```

The VAWLUME contract should therefore distinguish at least:

```text
recording
extraction_run
settings_artifact
native_processed_artifact
event_export_artifact
dataset_summary_artifact
classification/repertoire_run
repertoire_artifact
refinement lineage
```

---

## 5. MUPET workspace and dataset concepts

MUPET uses a workspace/session directory and organizes source audio into datasets. Its documentation describes directory structures and dataset-oriented processing.

### Important semantic caution

A **MUPET dataset** is a software/workspace grouping. It should not automatically become a VAWLUME biological `study`, `group`, `subject`, or `session`.

VAWLUME should instead ingest it as extractor-native grouping/provenance:

```text
native_dataset_name
native_workspace_path
```

and separately map the underlying recordings to VAWLUME experimental metadata through the project's configurable metadata-ingestion rules.

This is an important example of the extractor-agnostic principle:

> software container hierarchy is not necessarily experimental hierarchy.

---

## 6. User-editable extraction configuration

MUPET documentation/source describes `config.csv` with eleven configurable entries:

1. noise reduction;
2. minimum syllable duration;
3. maximum syllable duration;
4. minimum syllable total energy;
5. minimum syllable peak amplitude;
6. minimum syllable distance;
7. sample/processing frequency;
8. minimum USV frequency;
9. maximum USV frequency;
10. number of filterbank filters;
11. filterbank type.

These settings influence segmentation, filtering, or spectral representation.

### 6.1 Important run behavior

MUPET stores the configuration used with processed data and compares it against the current configuration. Documentation/source indicate that previously processed files are recomputed when the relevant configuration differs.

This strongly supports a VAWLUME rule:

> an extraction run is inseparable from the exact settings artifact used to generate it.

### 6.2 Settings JSON

VAWLUME should preserve MUPET's settings as external JSON referenced by run provenance:

```json
{
  "schema_version": "1.0",
  "extractor": {
    "name": "MUPET",
    "version": "2.1",
    "source_commit": null
  },
  "capture": {
    "sources": [
      "config.csv",
      "filestats.configpar"
    ]
  },
  "native_settings": {
    "noise-reduction": "...",
    "minimum-syllable-duration": "...",
    "maximum-syllable-duration": "...",
    "minimum-syllable-total-energy": "...",
    "minimum-syllable-peak-amplitude": "...",
    "minimum-syllable-distance": "...",
    "sample-frequency": "...",
    "minimum-usv-frequency": "...",
    "maximum-usv-frequency": "...",
    "number-filterbank-filters": "...",
    "filterbank-type": "..."
  }
}
```

Values above are placeholders deliberately; VAWLUME should capture the exact run values rather than assume defaults.

### 6.3 Paper defaults are contextual, not a substitute for run capture

The MUPET publication reports example/default noise-reduction/detection settings including approximately:

- noise-reduction level 5;
- minimum duration 8 ms;
- maximum duration 200 ms;
- minimum total energy −15 dB;
- minimum peak amplitude −25 dB;
- minimum syllable distance 5 ms.

These are useful for understanding program behavior but should **not** be inserted into VAWLUME provenance when the actual settings artifact is available.

---

## 7. Settings do not capture the entire algorithm

Source inspection shows fixed or code-level choices in addition to user configuration, including elements such as:

- FFT size;
- spectral/activity calculations;
- noise-floor handling;
- thresholds/logic internal to segmentation;
- filter design choices;
- summary/report-specific constants.

The publication also describes a fixed signal-processing framework involving high-pass filtering, STFT/sonogram construction, noise subtraction, and a gammatone representation.

### VAWLUME consequence

`settings_artifact_id` and `extractor_version` must both be recorded.

Reproducibility is better described as:

```text
software version/source
+ settings
+ source audio
+ processing/model state
```

rather than:

```text
settings alone
```

This generalizes to DeepSqueak and future extractors.

---

## 8. Audio resampling and processing frequency

MUPET documentation/source indicate that recordings are processed at a configured sample frequency and may be up/downsampled to that frequency. It also imposes frequency-range constraints appropriate to its processing.

### VAWLUME consequence

VAWLUME should distinguish:

```text
recording_native_sample_rate_hz
extractor_processing_sample_rate_hz
```

If VAWLUME later derives features directly from source audio, it must not assume the extractor measured exactly the untouched native waveform.

A provenance record might include:

```text
input_recording_id
native_sample_rate_hz
processing_sample_rate_hz
resampling_occurred
```

where `resampling_occurred` is inferred only if determinable.

---

## 9. Per-recording native processed artifacts

Source inspection of MUPET's processing code shows that a per-recording MATLAB artifact stores variables including:

- `syllable_data`;
- `syllable_stats`;
- `filestats`.

`filestats` includes the configuration parameters used for processing.

This native artifact can therefore be richer than the flattened CSV export.

### VAWLUME recommendation

Represent it explicitly:

```text
artifact_type = native_processed_recording
```

and consider it the preferred provenance source when a robust MATLAB parser is implemented.

Potential import priorities:

```text
1. native per-recording MUPET artifact     # richest
2. per-syllable CSV                        # easiest stable tabular contract
3. dataset summaries                       # downstream/higher level only
```

The prototype can support CSV first while still designing the schema so that native import does not require a redesign.

---

## 10. Internal syllable representation

Source inspection shows that MUPET's processing pipeline retains internal structures for each detected syllable, including representations of:

- source audio/file reference;
- gammatone/filterbank information;
- FFT/spectral information;
- energy;
- onset and offset frames;
- an inclusion/consideration flag;
- noise-statistic information.

The exact internal representation is implementation detail and should not be exposed as VAWLUME's universal schema. But it matters because it proves that a flattened CSV is a **derived view**, not the complete event object.

### VAWLUME consequence

Use an artifact parser that converts native structures into normalized events, while retaining the source artifact and feature lineage.

Do not encode MUPET's cell-array positions as permanent VAWLUME schema columns.

---

## 11. Syllable segmentation behavior

MUPET identifies candidate vocal activity from spectral/energy information and joins sufficiently close fragments according to the configured minimum-syllable-distance criterion.

This affects event identity itself.

### VAWLUME consequence

A MUPET syllable boundary is an **algorithmic segmentation estimate**. It can be semantically aligned to DeepSqueak's call onset/offset while remaining metrically non-identical.

This distinction supports:

```text
canonical concept: call_start_time
relationship: conceptually equivalent intent
metric relationship: comparable, calibrated empirically
```

rather than:

```text
DeepSqueak start == MUPET start
```

The same applies to offset and duration.

---

## 12. The two MUPET duration concepts

This is one of the most important findings for VAWLUME.

Source inspection of `syllable_activity_file_stats.m` indicates that MUPET keeps at least two related duration calculations:

### A. Pre-noise-reduction/onset-offset duration

A duration derived from the broader event onset/end interval is stored separately.

### B. Post-noise-reduction/thresholded duration

Another duration is based on the retained/thresholded timestamps after noise-reduction processing.

The source uses the latter for minimum/maximum-duration eligibility filtering.

### C. CSV export behavior

Inspection of `export_csv_files_syllables.m` shows that the per-syllable CSV's:

```text
syllable duration (msec)
```

comes from the **pre-noise-reduction/onset-offset duration** value, not the post-noise-reduction duration used for filtering.

### Why this matters

A schema containing only:

```text
feature_name = duration
```

would lose a scientifically meaningful distinction.

Recommended MUPET-native feature concepts:

```text
syllable_duration_pre_noise_reduction
syllable_duration_post_noise_reduction
```

Both can relate to a broad VAWLUME canonical concept:

```text
call_duration
```

but they should retain their `operational_variant`/`derivation_stage`.

For cross-extractor comparison with DeepSqueak's contour-derived `Call Length`, the MUPET CSV duration is plausibly comparable, but it is not automatically metrically equivalent.

---

## 13. Per-syllable CSV export

The v2.1 source exports event rows with the following columns:

| MUPET CSV field | Unit | VAWLUME interpretation |
|---|---:|---|
| `Syllable number` | — | Native event ordinal scoped to recording/export |
| `Syllable start time (sec)` | s | Segmentation-derived onset |
| `Syllable end time (sec)` | s | Segmentation-derived offset |
| `inter-syllable interval (sec)` | s | Interval to adjacent/next syllable; last entry uses a missing/sentinel representation |
| `syllable duration (msec)` | ms | Pre-noise-reduction/onset-offset duration exported by MUPET |
| `starting frequency (kHz)` | kHz | Frequency estimate near beginning of retained syllable |
| `final frequency (kHz)` | kHz | Frequency estimate near end |
| `minimum frequency (kHz)` | kHz | Method-specific minimum frequency |
| `maximum frequency (kHz)` | kHz | Method-specific maximum frequency |
| `mean frequency (kHz)` | kHz | MUPET's mean/weighted central-frequency measure |
| `frequency bandwidth (kHz)` | kHz | Maximum minus minimum according to MUPET's definitions |
| `total syllable energy (dB)` | dB | Total-energy metric |
| `peak syllable amplitude (dB)` | dB | Peak-amplitude metric |

### Correction to an earlier hypothetical mapping example

An earlier VAWLUME discussion used `EndTimeSeconds` as a hypothetical MUPET field name. In the inspected MUPET v2.1 CSV source, the actual exported header is:

```text
Syllable end time (sec)
```

VAWLUME should use the actual native header in its built-in v2.1 template while allowing alternate/fork-specific aliases through configuration.

### Export precision

The CSV writer formats values at finite decimal precision. Native MATLAB state can therefore retain more numerical precision than the CSV.

This is another reason to retain:

```text
source_artifact_type
```

on measurements, or at minimum on imported event batches.

A value imported from a CSV and a value parsed from native MUPET state may be semantically the same native feature but differ slightly due to export rounding.

---

## 14. Event ID semantics

`Syllable number` is best treated as a native ordinal, not a permanent identifier.

Recommended VAWLUME representation:

```text
detection_id                # VAWLUME UUID/integer
extraction_run_id
recording_id
native_event_id             # MUPET syllable number
native_event_id_scope       # recording + artifact
```

If a dataset is refined/reprocessed, syllable numbering may not be safe as a cross-artifact key.

Event matching across revisions should therefore rely on provenance plus temporal/acoustic identity, not on ordinal equality alone.

---

## 15. Start/end timing

MUPET derives onset/offset from activity frames in its processing pipeline. The exported start/end timestamps are therefore tied to MUPET's signal-processing/segmentation method.

Recommended native definitions:

```text
extractor_feature:
  native_name: "Syllable start time (sec)"
  canonical_feature: "call_start_time"
  derivation_stage: "segmentation"
  measurement_method: "MUPET v2.1 activity segmentation"
```

and similarly for end time.

### Cross-extractor relationship

With DeepSqueak's contour-derived timing:

```text
relationship_type = comparable
semantic_intent = conceptually_equivalent
consilience_eligible = true
```

They are especially useful for determining whether two events are likely the same vocalization.

---

## 16. Frequency-feature semantics

Source inspection indicates that MUPET's frequency statistics come from its spectral/filterbank representation and thresholded syllable content.

Important MUPET features include:

- starting frequency;
- final frequency;
- minimum frequency;
- maximum frequency;
- mean frequency;
- bandwidth.

### 16.1 Mean frequency is not DeepSqueak Principle Frequency

DeepSqueak's `Principle Frequency (kHz)` is documented as the **median contour frequency**.

MUPET's `mean frequency (kHz)` is calculated differently from its filterbank/spectral representation.

Therefore:

```text
DS Principle Frequency
MUPET mean frequency
```

should map to a broader concept such as:

```text
frequency_center
```

only with:

```text
relationship_type = comparable
```

They should not be pooled as repeat measurements of an identical statistic.

### 16.2 Min/max/bandwidth

DeepSqueak low/high frequency arise from its contour; MUPET min/max arise from its own spectral/filterbank logic. Both aim at similar lower/upper spectral extents.

Thus:

```text
minimum frequency <-> Low Freq
maximum frequency <-> High Freq
bandwidth <-> Delta Freq
```

are strong **comparability** candidates, not guaranteed metric equivalences.

### 16.3 Start/final frequencies

MUPET exports start and final frequency explicitly. DeepSqueak's standard Excel export does not provide a directly named pair of start/final contour frequencies.

VAWLUME should not invent a direct equivalence. If future VAWLUME code derives DeepSqueak contour-start/contour-end frequencies from native contours, those should be marked as **VAWLUME-derived features with source lineage**, not misrepresented as DeepSqueak-native export fields.

---

## 17. Energy and amplitude features

MUPET exports:

```text
total syllable energy (dB)
peak syllable amplitude (dB)
```

DeepSqueak exports a mean power spectral-density measure in dB/Hz and a peak-frequency feature.

These are not interchangeable.

Recommended relationship to DeepSqueak's `Mean Power (dB/Hz)`:

```text
relationship_type = related
consilience_eligible = false by default
```

unless a calibration study establishes a specific meaningful transformed comparison.

### General lesson

Names like:

```text
power
energy
amplitude
```

are particularly dangerous candidates for naive name regularization. Unit, formula, reference, and aggregation all matter.

VAWLUME should require explicit feature definitions before assigning strong equivalence.

---

## 18. Inter-syllable interval

MUPET exports an inter-syllable interval and uses a special/missing representation for the final syllable where no subsequent interval exists.

This highlights two schema requirements:

1. parser templates must define **missing-value/sentinel behavior**;
2. sequence-derived features can exist natively in an extractor but should still retain their derivation semantics.

VAWLUME may later calculate its own canonical inter-call interval from normalized timestamps. It should distinguish:

```text
MUPET-native inter-syllable interval
```

from:

```text
VAWLUME-derived inter-call interval
```

This creates a useful internal validation opportunity: compare VAWLUME's derived interval to MUPET's native value after import.

---

## 19. Quality filtering versus curation state

MUPET differs meaningfully from DeepSqueak here.

DeepSqueak commonly retains an explicit accepted/rejected state and supports post-detection manual review.

MUPET's core syllable workflow filters candidates using criteria such as duration, energy, and peak amplitude. Its exported event table therefore represents events that survived programmatic filtering rather than necessarily carrying a per-row DeepSqueak-like `Accepted` flag.

### VAWLUME consequence

Do not force every extractor into:

```text
accepted = 0/1
```

Instead separate:

```text
detection_state
quality_filter_state
manual_review_state
```

and allow fields to be absent when an extractor does not expose them.

This is exactly why the contract should specify **capabilities**, not identical source columns.

---

## 20. Dataset-level profile outputs

MUPET can export dataset-level summaries in addition to event-level rows. Source/documentation describe summaries covering areas such as:

- frequency/spectral profile;
- bandwidth;
- syllables per second;
- inter-syllable interval;
- syllable duration;
- total number of syllables;
- total syllable activity;
- total recording time.

These values are **aggregates**, not event measurements.

### VAWLUME consequence

Do not import them into `event_measurements`.

Use either:

```text
extractor_summary_artifacts
```

or a generalized:

```text
derived_metrics
---------------
metric_id
source_artifact_id
scope_type
scope_id
feature_id
value
unit
derivation_provenance
```

Possible `scope_type` values:

```text
recording
extractor_dataset
session
subject
group
study
consensus_event_set
```

This also anticipates VAWLUME's own hierarchy-aware summaries.

---

## 21. Dataset summaries may have their own code-level assumptions

Inspection of MUPET summary/export code indicates that some report behavior includes constants/selection logic in source rather than simply replaying every editable `config.csv` setting.

### VAWLUME consequence

A dataset summary should be tied to:

```text
extractor_version
source_artifact
summary_method
```

and should not be treated as a transparent recomputation from event rows unless VAWLUME has independently verified the formula.

If VAWLUME recomputes a metric from imported events, it should store it as a **VAWLUME-derived metric**, not overwrite the MUPET-native summary.

---

## 22. Repertoire construction is a higher-order analysis

MUPET supports unsupervised repertoire construction, commonly with a user-selected number of repertoire units. Its publication/docs describe clustering syllables using spectrotemporal representations and comparing repertoires across datasets.

These outputs are conceptually different from detection.

Recommended schema:

```text
classification_runs
-------------------
classification_run_id
extractor_id
extractor_version
parent_extraction_run_id
settings_artifact_id
method
number_of_units
created_at
```

```text
classification_assignments
--------------------------
classification_assignment_id
detection_id
classification_run_id
native_class_id
native_class_label
distance_or_similarity
```

```text
classification_models
---------------------
model_artifact_id
classification_run_id
artifact_path
checksum
```

A repertoire unit should be scoped to the repertoire/model that generated it. `RU 12` in one model is not automatically the same category as `RU 12` in another.

---

## 23. Repertoire refinement and lineage

MUPET allows repertoires/datasets to be refined by removing unwanted repertoire units, producing updated/refined outputs.

This is a direct example of why VAWLUME needs parent-child artifact lineage.

Recommended representation:

```text
artifact_id = refined_dataset_002
parent_artifact_id = original_dataset_001
transformation_type = repertoire_refinement
```

Likewise, event inclusion/exclusion due to refinement should not erase the original event record.

VAWLUME can represent:

```text
event_membership
----------------
detection_id
derived_artifact_id
membership_status
reason
```

This preserves the distinction between:

```text
event did not exist
```

and

```text
event existed but was excluded from this refined representation
```

---

## 24. MUPET repertoire units are not canonical vocalization classes

A repertoire unit is model/run-specific. It may be reproducible and biologically useful, but it is not automatically a universal label.

Therefore a VAWLUME built-in template should **not** contain global mappings such as:

```text
MUPET RU 4 = DeepSqueak trill
```

unless a user or validated method explicitly establishes that relationship.

If equivalence/comparability is asserted, store it separately:

```text
class_relationships
-------------------
class_a_id
class_b_id
relationship_type
method
evidence_artifact_id
notes
```

The same principle used for feature comparability should apply to classification ontologies.

---

## 25. Proposed MUPET native feature dictionary

A VAWLUME built-in v2.1 feature template can begin with:

| Native feature | Canonical target | Native unit | Derivation stage | Default relationship strength |
|---|---|---:|---|---|
| `Syllable number` | `native_event_id` | — | export identity | identifier only |
| `Syllable start time (sec)` | `call_start_time` | s | segmentation | conceptually equivalent intent; cross-extractor comparable |
| `Syllable end time (sec)` | `call_end_time` | s | segmentation | conceptually equivalent intent; cross-extractor comparable |
| `inter-syllable interval (sec)` | `inter_call_interval` | s | sequence-derived | preserve native; validate against VAWLUME-derived |
| `syllable duration (msec)` | `call_duration` | ms | pre-noise-reduction/onset-offset | comparable |
| `starting frequency (kHz)` | `frequency_start` | kHz | spectral/filterbank | extractor-specific unless paired intentionally |
| `final frequency (kHz)` | `frequency_end` | kHz | spectral/filterbank | extractor-specific unless paired intentionally |
| `minimum frequency (kHz)` | `frequency_min` | kHz | spectral/filterbank | comparable |
| `maximum frequency (kHz)` | `frequency_max` | kHz | spectral/filterbank | comparable |
| `mean frequency (kHz)` | `frequency_center` | kHz | spectral/filterbank | comparable, not equivalent to contour median |
| `frequency bandwidth (kHz)` | `frequency_bandwidth` | kHz | spectral/filterbank | comparable |
| `total syllable energy (dB)` | `total_energy` | dB | spectral | no direct DS equivalence |
| `peak syllable amplitude (dB)` | `peak_amplitude` | dB | spectral | no direct DS equivalence |

The internal post-noise-reduction duration should receive its own native feature record if/when the native `.mat` parser exposes it.

---

## 26. Pairwise DeepSqueak–MUPET comparability

Suggested initial relationship matrix:

| Concept | DeepSqueak | MUPET | Relationship | Default consilience use |
|---|---|---|---|---|
| onset | contour `Begin Time (s)` | `Syllable start time (sec)` | comparable; same intended construct | **Primary** |
| offset | contour `End Time (s)` | `Syllable end time (sec)` | comparable; same intended construct | **Primary** |
| duration | contour `Call Length (s)` | CSV pre-noise-reduction duration | comparable | **Primary/supporting** |
| minimum frequency | `Low Freq (kHz)` | `minimum frequency (kHz)` | comparable | Supporting |
| maximum frequency | `High Freq (kHz)` | `maximum frequency (kHz)` | comparable | Supporting |
| bandwidth | `Delta Freq (kHz)` | `frequency bandwidth (kHz)` | comparable | Supporting |
| central frequency | contour median (`Principle Frequency`) | MUPET mean frequency | comparable only | Supporting |
| power/energy | mean PSD dB/Hz | total energy dB | related, not equivalent | None by default |
| peak amplitude/power | no same standard exported measure | peak amplitude dB | no direct equivalence | None |
| start frequency | no direct standard Excel field | starting frequency | unmatched | None |
| final frequency | no direct standard Excel field | final frequency | unmatched | None |

The initial VAWLUME contract should be conservative: only features with explicit methodological justification should contribute to a consensus score.

---

## 27. Event matching should precede feature agreement

For MUPET/DeepSqueak integration, VAWLUME should solve:

### Question 1: Are these detections likely the same event?

Candidate evidence:

```text
temporal overlap / intersection-over-union
absolute onset difference
absolute offset difference
duration difference
recording identity
```

### Question 2: Given a candidate pair, how similarly were they measured?

Candidate evidence:

```text
minimum/maximum frequency difference
bandwidth difference
central-frequency difference
other calibrated comparisons
```

This avoids using frequency similarity to pair two unrelated nearby calls unless timing also supports the match.

---

## 28. Settings versus consilience policy

MUPET settings belong to the extraction run:

```text
MUPET config -> extraction_run.settings_artifact_id
```

VAWLUME matching/consilience settings belong to the project or consensus-analysis run:

```text
VAWLUME consilience config -> consensus_run.settings_artifact_id
```

These must remain distinct.

For example:

```yaml
consilience:
  event_matching:
    onset_tolerance_ms: ...
    minimum_temporal_iou: ...
  supporting_features:
    frequency_center:
      relationship: comparable
      tolerance_khz: ...
```

The thresholds should come from a project's calibration protocol, not be hard-coded into the global MUPET template.

---

## 29. Proposed MUPET built-in template contents

A machine-readable template should eventually include:

```yaml
template:
  extractor: MUPET
  supported_versions:
    - "2.1"

artifacts:
  native_processed_recording:
    parser: ...
    priority: preferred
  per_syllable_csv:
    parser: ...
    priority: supported
  dataset_profile_csv:
    parser: ...
    scope: aggregate
  repertoire:
    parser: ...
    scope: classification

settings_capture:
  sources:
    - config.csv
    - filestats.configpar
  externalize_to_json: true

features:
  - native_name: "Syllable start time (sec)"
    canonical_name: "call_start_time"
    native_unit: "s"
    derivation_stage: "segmentation"

  - native_name: "syllable duration (msec)"
    canonical_name: "call_duration"
    native_unit: "ms"
    canonical_unit: "s"
    transform: "ms_to_s"
    operational_variant: "pre_noise_reduction"

missing_values:
  inter_syllable_interval:
    final_event: "native sentinel/missing"

event_identity:
  native_id_field: "Syllable number"
  scope: "recording_artifact"

consilience_defaults:
  thresholds:
    source: "project_config_only"
```

As with DeepSqueak, parser mechanics and feature semantics belong in the built-in template; empirical acceptance thresholds belong in project config.

---

## 30. Artifact types motivated by MUPET

MUPET suggests a general artifact taxonomy:

```text
source_audio
settings
native_processed_recording
event_export
dataset_summary
repertoire_model
repertoire_assignment_export
repertoire_comparison
refined_dataset
refined_repertoire
```

VAWLUME should allow extractor-specific metadata without hard-coding all these as relational columns.

Recommended generic table:

```text
extractor_artifacts
-------------------
artifact_id
extraction_run_id
artifact_type
native_artifact_type
path_or_uri
checksum
file_format
parent_artifact_id
created_at
imported_at
is_native
metadata_json_path
```

This taxonomy is also broad enough to accommodate DeepSqueak detector/classifier outputs.

---

## 31. Proposed general feature schema motivated by MUPET

MUPET's multiple duration definitions strongly motivate:

```text
extractor_features
------------------
extractor_feature_id
extractor_id
version_scope
native_name
native_unit
value_type
native_definition
source_artifact_type
derivation_stage
measurement_method
operational_variant
source_reference
```

Then:

```text
feature_mappings
----------------
extractor_feature_id
canonical_feature_id
mapping_type
transform_id
notes
```

And:

```text
feature_relationships
---------------------
feature_relationship_id
feature_a_id
feature_b_id
relationship_type
comparison_method
unit_normalization
consilience_eligible
default_role
version_scope
justification
```

This prevents a string such as `duration` from creating a false homonym across algorithms or pipeline stages.

---

## 32. Preserve both native and canonical values

MUPET exports kHz, seconds, milliseconds, and dB-valued features.

VAWLUME may prefer canonical SI-like units such as seconds and Hz, but normalization should be additive rather than destructive.

Example:

```text
native_name        = "syllable duration (msec)"
native_value       = 34.7
native_unit        = "ms"
canonical_feature  = "call_duration"
canonical_value    = 0.0347
canonical_unit     = "s"
transform_id       = "ms_to_s"
```

If the value is rounded in the CSV, VAWLUME should not imply more precision than the native export contained.

---

## 33. Sequence and hierarchy integration

MUPET natively exposes event timing and an inter-syllable interval. This fits VAWLUME's sequence-aware aims well, but VAWLUME should derive its own sequence representation from normalized event timing where possible.

Benefits:

- identical sequence logic can be applied to MUPET, DeepSqueak, or consensus events;
- extractor-native interval calculations can be retained for validation;
- VAWLUME can group sequences according to project metadata (session, animal, group, study);
- disagreement between extractor segmentations becomes inspectable rather than hidden.

Recommended sequence lineage:

```text
source_event_set = MUPET detections
or
source_event_set = DeepSqueak detections
or
source_event_set = VAWLUME consensus events
```

Then apply the same sequence-analysis functions.

---

## 34. Input recording identity and cross-extractor linkage

MUPET's per-recording artifacts and CSV filenames provide useful clues, but filename equality should not be the strongest identity rule.

VAWLUME should map both MUPET and DeepSqueak outputs to a persistent `recording_id`, preferably using a checksum of the original audio.

Recommended:

```text
recordings
----------
recording_id
source_filename
source_path
checksum
native_sample_rate_hz
channel_count
duration_s
```

and:

```text
extraction_run_inputs
---------------------
extraction_run_id
recording_id
input_role
```

If MUPET resamples internally, the original recording identity remains stable while the run provenance records processing sample rate.

---

## 35. Calibration implications

The MUPET publication itself emphasizes parameter optimization/visual inspection when establishing appropriate processing conditions. That meshes naturally with VAWLUME's proposed calibration protocol.

A defensible workflow can be:

1. select a representative calibration subset;
2. optimize MUPET settings and DeepSqueak settings/models;
3. preserve exact settings/model artifacts;
4. manually inspect a defined sample;
5. quantify detection-level precision/recall and boundary agreement;
6. establish VAWLUME matching thresholds;
7. examine whether cross-extractor intersection/weighted consensus improves precision at an acceptable recall cost;
8. freeze run configurations and consensus policy;
9. process the larger corpus;
10. target optional manual review at disagreement/ambiguous cases.

MUPET's automatic filtering and DeepSqueak's editable review provide complementary examples of why VAWLUME should not assume every extractor has the same human-curation interface.

---

## 36. Import-time validation checks

A MUPET importer could non-destructively verify:

- `end_time >= start_time`;
- exported duration approximately matches `end_time - start_time` within expected rounding;
- native syllable numbers are unique within the recording/export;
- expected headers match the version-scoped parser template;
- units are recognized;
- final inter-syllable interval sentinel is converted to explicit missingness while preserving the raw token;
- frequency minimum <= maximum;
- bandwidth approximately matches maximum minus minimum, subject to export rounding;
- recording linkage is resolved;
- settings artifact/checksum exists where required;
- configuration recovered from native state matches associated `config.csv` when both are available.

Any discrepancy should become a validation/log record rather than silently altering source data.

---

## 37. Open questions for implementation testing

Before calling MUPET support production-ready, test real v2.1 outputs for:

1. exact `config.csv` key spelling/order in typical installations;
2. exact native `.mat` structure across multiple processed files;
3. whether `filestats.configpar` always captures every user setting;
4. how ignored files are represented;
5. how refined repertoire/dataset outputs alter event numbering and membership;
6. native precision versus CSV precision;
7. representation of missing/sentinel values in every export mode;
8. behavior around closely spaced syllables merged by minimum-distance logic;
9. whether start/end timestamps refer to pre- or post-resampling timebase identically in all cases;
10. relation between the internal two duration measures across realistic calls;
11. exact contents/formats of repertoire assignment exports;
12. how a repertoire's identifying information can be hashed/versioned;
13. whether metadata needed to identify original audio is always recoverable from native artifacts.

These should become parser fixtures/tests using a small legally shareable or synthetic audio corpus.

---

## 38. Proposed minimum MUPET contract for the VAWLUME prototype

### Required run-level values

- extractor = MUPET;
- version = 2.1 or explicit detected/supplied version;
- source recording mapping;
- settings JSON captured from config/native state;
- source artifact checksum;
- parser/template version.

### Required event-level values

- VAWLUME `detection_id`;
- native syllable number;
- recording ID;
- start time;
- end time;
- exported duration;
- inter-syllable interval if present;
- exported spectral/acoustic measurements.

### Required semantic metadata

- native name;
- native definition;
- native unit;
- canonical mapping;
- derivation stage;
- operational variant;
- version scope;
- pairwise DeepSqueak relationship where established.

### Required provenance behavior

- preserve raw/native artifact;
- retain raw values and tokens;
- normalize units into separate canonical fields;
- record transformations;
- do not treat repertoire units as universal call classes;
- preserve refinement lineage.

---

## 39. Design conclusions for VAWLUME

MUPET strongly supports these general design rules:

1. **One extractor can produce event-, dataset-, and model-level outputs.** The schema needs artifact scope.
2. **The extractor's own "dataset" hierarchy is not necessarily the experiment's hierarchy.**
3. **Settings should remain detailed external artifacts referenced by stable run provenance.**
4. **Software version/source remains necessary because algorithmic behavior is not fully encoded in user settings.**
5. **A single everyday feature word can hide multiple operational quantities.** Duration is the clearest example.
6. **Native and canonical feature values should coexist.**
7. **Cross-extractor similarity should be encoded explicitly, pairwise, and conservatively.**
8. **Timing is especially useful for event correspondence, while frequency statistics can provide supporting consilience.**
9. **Energy/amplitude/power fields should never be equated by name alone.**
10. **Higher-order repertoire labels are run/model-specific.**
11. **Refined datasets should preserve parent-child lineage rather than overwrite source events.**
12. **Project-specific consensus thresholds should remain separate from the global MUPET parser/feature template.**

---

## 40. Sources reviewed

### Primary MUPET repository

- MUPET repository: https://github.com/mvansegbroeck/mupet
- Repository README: https://github.com/mvansegbroeck/mupet/blob/master/README.md

### Documentation

- MUPET GitHub Wiki (when accessible from repository): https://github.com/mvansegbroeck/mupet/wiki

### Source inspected

Repository source root:
- https://github.com/mvansegbroeck/mupet/tree/master

Relevant functions inspected include the repository implementations of:

- `utils/create_configfile.m`
- `core/audio/compute_musv.m`
- `core/audio/compute_musv_segment.m`
- `core/syllable_activity_file_stats.m`
- per-syllable CSV export code (`export_csv_files_syllables.m`)
- dataset-summary CSV export code
- repertoire-learning/refinement functions
- clustering functions using cosine-based similarity/k-means/k-medoids machinery

Because repository directory organization may change in forks, VAWLUME machine-readable templates should ultimately pin source links to an exact supported commit/tag.

### Publication

- Van Segbroeck M, Knoll AT, Levitt P, Narayanan S. MUPET—Mouse Ultrasonic Profile ExTraction: a signal processing tool for rapid and unsupervised analysis of ultrasonic vocalizations. *Neuron*. 2017. Open-access version: https://pmc.ncbi.nlm.nih.gov/articles/PMC5939957/

---

## 41. Recommended status in the VAWLUME project

**Use this document as the human-readable basis for:**

- the initial `MUPET v2.1` extractor template;
- exact native CSV-name mappings;
- settings JSON capture;
- schema decisions around artifact scope and refinement lineage;
- operationally explicit duration/frequency definitions;
- MUPET–DeepSqueak pairwise comparability;
- parser fixture/testing requirements.

The most important implementation lesson is simple:

> VAWLUME should regularize *access* to extractor measurements without regularizing away the methodological differences that give those measurements meaning.

That principle is central to both extractor-agnostic integration and defensible cross-extractor consilience.
