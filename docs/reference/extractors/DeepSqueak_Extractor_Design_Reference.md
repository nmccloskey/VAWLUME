# VAWLUME Extractor Design Reference: DeepSqueak

**Purpose:** Design reference for VAWLUME's extractor contract, built-in DeepSqueak template, relational schema, provenance model, and cross-extractor consilience logic.  
**Prepared:** 2026-08-20  
**Primary software scope reviewed:** DeepSqueak v3.x, with particular attention to the current repository/changelog through v3.2.1 and to version-sensitive behavior documented across earlier releases.  
**Status:** Working design reference. This is not a replacement for DeepSqueak documentation and should be updated when VAWLUME adds or changes DeepSqueak support.

---

## 1. Executive design summary

DeepSqueak is not merely a program that emits one flat table of calls. Its workflow contains several distinct layers that matter to an extractor-agnostic system:

1. **source audio and audio metadata;**
2. **neural-network detection**, which creates candidate call regions and detection scores;
3. **native detection artifacts**, which retain call records plus detection metadata;
4. **manual and automatic review**, which can accept/reject, add, delete, move, or resize detections;
5. **contour extraction**, from which many exported acoustic features are calculated;
6. **classification/clustering**, which can assign or revise call labels;
7. **flat exports**, especially Excel output;
8. **higher-order analyses**, including syntax-oriented analyses.

For VAWLUME, the central implication is that a "DeepSqueak call" is not adequately represented by a single row stripped from this provenance. A useful DeepSqueak importer should preserve, or at least describe:

- which audio recording was analyzed;
- the DeepSqueak version/build;
- the detector network/model identity;
- the detector/settings configuration;
- the native output artifact and its checksum;
- whether the ingested event came from a native detection file or a flattened export;
- whether/when review or classification may have altered the event;
- which measurements are native detector geometry versus contour-derived statistics;
- the native feature name, definition, unit, and derivation stage;
- VAWLUME's canonical feature mapping without erasing the native semantics.

This makes DeepSqueak an excellent test case for a general VAWLUME extractor contract: it combines model-dependent detection, editable event state, derived acoustic measurements, classifications, and multiple artifact layers.

---

## 2. Evidence conventions used in this document

The notes below distinguish three kinds of claims:

- **Documented behavior** — stated in the DeepSqueak repository, changelog, wiki, or publication.
- **Source-inspected behavior** — inferred directly from inspected MATLAB source.
- **VAWLUME design implication** — a proposed architectural consequence; not a claim made by DeepSqueak.

When exact semantics are version-sensitive or documentation appears older than the current code, this is noted explicitly.

---

## 3. Software identity and versioning

### 3.1 Current repository state reviewed

The main DeepSqueak repository identifies the software as **DeepSqueak v3**. The changelog currently contains releases through **v3.2.1 (2025-11-07)**. The v3.2 series added high-precision neural networks, automatic horizontal-noise-band removal, and image scaling tied to trained networks. Earlier v3.x releases changed detection, clustering, review, and export behavior.

### 3.2 Version changes are analytically consequential

The changelog documents changes that can alter either the generated detections or the meaning/behavior of outputs. Examples include:

- v3.2.0: new high-precision networks, horizontal noise removal, revised image scaling;
- v3.1.0: VAE embeddings plus contour became the default clustering approach; batch Excel export gained file names;
- v3.0: YOLOv2 detection architecture and expanded manual editing/retraining workflow;
- v3.0.3: a clustering-label bug involving rejected calls was fixed/worked around;
- v2.6: supervised-classifier behavior changed in a way that could make older networks incompatible;
- v2.5: detection files became tables and automatic review options expanded;
- v2.4.x: multichannel handling changed;
- v2.3: detection ceased to be limited to two networks;
- v2.2: a precision/recall control was introduced;
- v2.1: "call power" changed from amplitude to **power spectral density, dB/Hz**;
- v1.1.4: saved files began retaining metadata including detection time, settings, audio path, and detection network.

### 3.3 VAWLUME consequence

`extractor_version` must be first-class provenance. A settings JSON alone cannot reproduce behavior that is encoded in program source or model architecture.

Recommended provenance fields:

```text
extractor_id
extractor_name
extractor_version
source_repository
source_commit_or_tag
build_identifier
matlab_version              # when known
operating_environment       # optional
```

For published built-in templates, VAWLUME should scope parser/feature mappings to an explicit supported version range rather than silently assuming all DeepSqueak releases have identical output semantics.

---

## 4. DeepSqueak workflow as an extractor contract

A useful normalized view is:

```text
recording
   |
   v
detector model + detection settings
   |
   v
candidate detections / native detection artifact
   |
   +---- manual or automatic review
   |        - accept/reject
   |        - add
   |        - delete
   |        - move/resize
   |        - relabel
   |
   v
contour extraction
   |
   v
derived acoustic features
   |
   +---- classification / clustering
   |
   v
Excel or other exports
   |
   v
downstream analyses
```

The contract therefore needs to support more than:

```text
input file -> rows
```

It should support:

```text
input recording
+ extraction run
+ settings artifact
+ model artifact(s)
+ output artifact(s)
+ event records
+ event measurements
+ event review/classification state
```

---

## 5. Detection configuration

The DeepSqueak detection documentation exposes settings including:

| Native concept | Meaning | VAWLUME treatment |
|---|---|---|
| Total Analysis Length | Amount of audio to analyze; documentation notes `0` for whole file | Preserve exactly in settings JSON |
| Frequency Cut Off High | Ignore regions above a high-frequency boundary | Preserve exactly; optionally normalize unit |
| Frequency Cut Off Low | Ignore regions below a low-frequency boundary | Preserve exactly; optionally normalize unit |
| Score Threshold | Candidate detections below threshold can be rejected automatically | Preserve; do not treat as a universal confidence calibration |
| Append Date to File Name | Output naming behavior | Preserve if captured; operational rather than acoustic |

The detection workflow also requires selection of a **neural network**. Network/model identity is therefore not merely another scalar setting. It is a model artifact that can itself have a name, version, source, and checksum.

### VAWLUME recommendation

Keep the detailed native settings outside bespoke relational columns:

```text
settings_artifacts
------------------
settings_artifact_id
extractor_id
extractor_version
path_or_uri
checksum
format
capture_method
created_at
```

The referenced JSON can contain the exact native settings and any VAWLUME-normalized annotations:

```json
{
  "schema_version": "1.0",
  "extractor": {
    "name": "DeepSqueak",
    "version": "3.2.1",
    "source_commit": null
  },
  "capture": {
    "source": "detection_metadata",
    "artifact_checksum": "..."
  },
  "native_settings": {
    "...": "preserve values exactly as recovered"
  },
  "models": [
    {
      "role": "detector",
      "native_name": "...",
      "artifact_id": "...",
      "checksum": "..."
    }
  ]
}
```

The database can query stable cross-extractor concepts (`extractor`, `version`, `settings_artifact_id`) without attempting to predict every future detector knob.

---

## 6. Native detection artifacts

The DeepSqueak output documentation describes a saved detection result containing at least:

- **audio data/metadata**, including the audio path/information;
- **Calls**;
- **detection metadata**, including settings, detection time, and network used.

The documented `Calls` representation includes:

| Native field | Documented meaning | Important note |
|---|---|---|
| `Box` | `[Begin Time (s), Minimum Frequency (kHz), Duration (s), Frequency Range (kHz)]` | Detector-region geometry; not identical to every contour-derived export statistic |
| `Score` | Neural-network score | Model-specific; not cross-extractor calibrated by default |
| `Type` | Call category | May arise from manual/classification workflow |
| `Power` | Call power/amplitude terminology in wiki | Version-sensitive; changelog says v2.1 changed call power to PSD in dB/Hz |
| `Accept` | Accepted/rejected state | Review/curation state, not ground-truth truth value |

The saved detection metadata has included settings, detection time, audio path, and network identity since an early release.

### VAWLUME consequence

A DeepSqueak native artifact contains provenance that can be lost in a flattened spreadsheet. VAWLUME should therefore model output artifacts explicitly:

```text
extractor_artifacts
-------------------
artifact_id
extraction_run_id
artifact_type
path_or_uri
checksum
file_format
parent_artifact_id
created_at
imported_at
is_native
parser_template_id
```

Candidate DeepSqueak `artifact_type` values might include:

```text
native_detection
excel_event_export
detector_network
classifier_model
clustering_model
contour_export
audio_export
spectrogram_export
```

These types should be VAWLUME-controlled categories while retaining the native names/details in metadata.

---

## 7. Manual review and event mutability

DeepSqueak is specifically designed to let a user review and refine automated detections. Across the v3 workflow and review documentation, users can:

- accept/reject detections;
- delete detections;
- add previously missed calls manually;
- move or resize call regions;
- change labels/categories;
- batch-reject according to criteria;
- save the edited session.

This is a major provenance issue.

### 7.1 `Accept` should not mean `is_real_call`

A DeepSqueak acceptance field is a **curation state** produced within DeepSqueak. VAWLUME should not silently translate it to a universal claim such as:

```text
is_ground_truth = true
```

Better concepts are:

```text
native_review_status
native_accept_flag
review_provenance
```

### 7.2 Final artifacts may not preserve the full edit history

If a user deletes a detection or destructively removes rejected calls, a final file may not make the earlier state reconstructable.

For studies requiring an audit trail, VAWLUME documentation should recommend preserving:

1. initial automated output;
2. reviewed output;
3. optionally exported review logs if DeepSqueak provides them in a supported version.

VAWLUME can then connect them with:

```text
parent_artifact_id
artifact_stage
```

For example:

```text
automated_detection -> reviewed_detection -> classified_detection
```

### 7.3 Event identity

A DeepSqueak row/index should be treated as a **native event identifier scoped to the artifact/run**, not necessarily a permanent project-global identifier. VAWLUME should generate its own stable `detection_id`.

---

## 8. Contour extraction is a distinct measurement stage

DeepSqueak calculates many statistics from a spectrotemporal contour rather than directly from the neural-network bounding box.

The contour documentation describes a ridge corresponding approximately to the frequency of maximal amplitude at each time point, followed by cleaning that removes portions judged insufficiently tonal or otherwise unsuitable. Tonality and amplitude-related thresholds affect this operation.

The inspected `CalculateStats.m` source further shows that several exported features are calculated from the cleaned/smoothed ridge.

### Critical schema consequence

A generic feature table needs a way to represent **where in an extractor pipeline a quantity came from**.

Recommended fields:

```text
extractor_feature_id
extractor_id
extractor_version_min
extractor_version_max
source_artifact_type
native_name
native_unit
value_type
native_definition
derivation_stage
measurement_method
canonical_feature_id
mapping_type
transform_id
source_reference
```

Possible `derivation_stage` values:

```text
detector_geometry
contour_derived
review_state
classifier_output
export_derived
dataset_summary
```

This distinction prevents VAWLUME from conflating a detector box's start/duration with a contour-derived start/end merely because both describe call timing.

---

## 9. DeepSqueak Excel feature dictionary

The official export documentation defines the following event-level fields. The table below paraphrases their documented/source-inspected semantics for VAWLUME use.

| DeepSqueak export field | Unit | Operational meaning | Suggested canonical concept | Mapping caution |
|---|---:|---|---|---|
| `ID` | — | Call identifier/index in export | `native_event_id` | Scope to artifact/run |
| `Label` | — | Call category | `native_call_label` | Class ontology is model/user-specific |
| `Accepted` | binary | DeepSqueak accept/reject state | `native_review_status` | Not biological ground truth |
| `Score` | model-specific | Detector neural-network score | `native_detection_score` | Do not compare across extractors/models without calibration |
| `Begin Time (s)` | s | Contour-derived beginning time | `call_start_time` | Comparable with other onset estimates; method-specific |
| `End Time (s)` | s | Contour-derived ending time | `call_end_time` | Comparable with other offset estimates; method-specific |
| `Call Length (s)` | s | End time minus begin time | `call_duration` | Derived from DeepSqueak contour boundaries |
| `Principle Frequency (kHz)` | kHz | Median frequency of contour | `frequency_center` or more specific `contour_median_frequency` | Preserve DeepSqueak's spelling/native name; not equivalent to a mean |
| `Low Freq (kHz)` | kHz | Lowest contour frequency | `frequency_min` | Operationally contour-specific |
| `High Freq (kHz)` | kHz | Highest contour frequency | `frequency_max` | Operationally contour-specific |
| `Delta Freq (kHz)` | kHz | High minus low frequency | `frequency_bandwidth` | Comparable where other extractor uses max-min, but base extrema may differ |
| `Frequency Standard Deviation (kHz)` | kHz | SD of contour frequency | `frequency_sd` | No assumed MUPET equivalent |
| `Slope (kHz/s)` | kHz/s | Regression slope of contour | `frequency_slope` | No assumed MUPET equivalent |
| `Sinuosity` | ratio | Contour path-length relative to straight-line displacement | `contour_sinuosity` | Extractor-specific unless another method is explicitly matched |
| `Mean Power (dB/Hz)` | dB/Hz | Mean contour power spectral density | `mean_power_spectral_density` | Not equivalent to total energy or peak amplitude |
| `Tonality` | ratio | Spectral-flatness-derived tonality quantity | `tonality` | Formula/method must be retained |
| `Peak Freq (kHz)` | kHz | Contour frequency at highest power | `peak_frequency` | Do not map to generic mean/central frequency |

DeepSqueak v3.1 added file names to batch Excel export, so parser expectations should be version-aware.

### Naming note

The software documentation uses **`Principle Frequency`**, not `Principal Frequency`. VAWLUME should preserve the native spelling in `extractor_features.native_name`, even if the canonical name is standardized.

---

## 10. Raw versus canonical values

VAWLUME should avoid destructive normalization.

For each imported measurement, retain enough information to reconstruct what the extractor said:

```text
event_measurements
------------------
event_measurement_id
detection_id
extractor_feature_id
native_value
native_unit
canonical_feature_id
canonical_value
canonical_unit
transform_id
```

For example:

```text
native_name:       "Principle Frequency (kHz)"
native_value:      71.42
native_unit:       "kHz"
canonical_feature: "contour_median_frequency"
canonical_value:   71420
canonical_unit:    "Hz"
transform:         "kHz_to_Hz"
```

The unit conversion can be exact while the semantic mapping remains explicit.

---

## 11. Feature normalization should not imply metric equivalence

VAWLUME should distinguish at least:

### A. Name regularization

A parser-level mapping from a native field name to a VAWLUME feature record.

Example:

```text
"Begin Time (s)" -> DS_FEATURE_BEGIN_TIME
```

### B. Semantic/canonical mapping

The native feature is an operationalization of a canonical concept:

```text
DS_FEATURE_BEGIN_TIME -> call_start_time
```

### C. Pairwise comparability

A DeepSqueak feature and another extractor's feature may both address the same construct while being calculated differently.

Recommended relationship vocabulary:

```text
transform_equivalent
conceptually_equivalent
comparable
related
noncomparable
```

`transform_equivalent` should be reserved for cases where a deterministic representation/unit conversion is sufficient and the underlying measurement is the same operational quantity.

`comparable` is appropriate where the measurements can inform agreement/consilience but should not be pooled or substituted as if identical.

---

## 12. Candidate DeepSqueak–MUPET cross-extractor relationships

These are **VAWLUME starting hypotheses**, not universal truths. They should be calibrated and version-scoped.

| Canonical concept | DeepSqueak | Likely relation to MUPET v2.1 feature | Consilience role |
|---|---|---|---|
| Call onset | `Begin Time (s)` | MUPET `Syllable start time (sec)` | **Comparable; conceptually equivalent intent.** Strong event-matching candidate |
| Call offset | `End Time (s)` | MUPET `Syllable end time (sec)` | **Comparable; conceptually equivalent intent.** Strong event-matching candidate |
| Duration | `Call Length (s)` | MUPET CSV `syllable duration (msec)` | **Comparable**, not assumed metric-equivalent; segmentation/derivation differs |
| Minimum frequency | `Low Freq (kHz)` | MUPET `minimum frequency (kHz)` | **Comparable**, operational definitions differ |
| Maximum frequency | `High Freq (kHz)` | MUPET `maximum frequency (kHz)` | **Comparable**, operational definitions differ |
| Frequency span | `Delta Freq (kHz)` | MUPET `frequency bandwidth (kHz)` | **Comparable**, because both depend on method-specific extrema |
| Central frequency | `Principle Frequency (kHz)` = contour median | MUPET `mean frequency (kHz)` | **Comparable only**, not equivalent: median contour frequency vs MUPET's mean/weighted construction |
| Peak frequency | `Peak Freq (kHz)` | No clear direct MUPET v2.1 CSV equivalent | Do not force mapping |
| Mean PSD | `Mean Power (dB/Hz)` | MUPET total energy / peak amplitude | **Related at most**, not directly comparable by default |
| Tonality | `Tonality` | No clear direct MUPET v2.1 CSV equivalent | Extractor-specific |
| Sinuosity | `Sinuosity` | No clear direct MUPET v2.1 CSV equivalent | Extractor-specific |
| Frequency SD | `Frequency Standard Deviation (kHz)` | No direct MUPET v2.1 event CSV equivalent | Extractor-specific |
| Frequency slope | `Slope (kHz/s)` | No direct MUPET v2.1 event CSV equivalent | Extractor-specific |

### Recommended consilience strategy

Timing should probably be the first-line basis for determining whether two detections refer to the same acoustic event:

```text
temporal overlap
onset difference
offset difference
duration difference
```

Frequency features can then support or challenge that pairing.

Detector `Score` should **not** enter a cross-extractor agreement calculation as though it were on the same scale as another system's confidence quantity.

---

## 13. Detection geometry versus contour timing: a subtle but important distinction

DeepSqueak's native `Box` represents a detector region:

```text
[begin time, minimum frequency, duration, frequency range]
```

The Excel documentation/source indicate that exported `Begin Time` and `End Time` are calculated from the contour.

Therefore, within DeepSqueak itself, VAWLUME may encounter two conceptually related timing representations:

```text
detector_box_start
detector_box_duration
```

and

```text
contour_start_time
contour_end_time
contour_duration
```

They should not be flattened into one undifferentiated `start_time` field without lineage.

A useful VAWLUME approach is:

```text
canonical_feature = call_start_time
operational_variant = detector_box
```

versus:

```text
canonical_feature = call_start_time
operational_variant = contour
```

Then downstream policies can choose which operational representation is suitable.

For cross-extractor comparison with MUPET's segmented syllable boundaries, the contour-derived timing may be the more natural DeepSqueak default, but this is an empirical/calibration decision.

---

## 14. Classification and clustering

DeepSqueak supports several forms of call categorization:

- manual labels;
- supervised classification;
- unsupervised clustering;
- version-dependent clustering machinery, including VAE + contour approaches in newer v3.x behavior.

These labels must not be treated as extractor-independent biological categories simply because they occupy a `Label`/`Type` column.

Recommended schema:

```text
classification_runs
-------------------
classification_run_id
extractor_id
extractor_version
model_artifact_id
settings_artifact_id
parent_extraction_run_id
method
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
score_or_distance
```

If a user later establishes equivalence between a DeepSqueak class and a MUPET repertoire unit or a laboratory taxonomy, that should be a **separate explicit mapping** with provenance.

---

## 15. Model artifacts should be first-class

DeepSqueak's behavior depends on trained networks and classification models.

VAWLUME should support:

```text
model_artifacts
---------------
model_artifact_id
extractor_id
model_role
native_name
path_or_uri
checksum
model_version
parent_model_artifact_id
training_dataset_reference
metadata_json_path
```

Roles might include:

```text
detector
posthoc_denoiser
supervised_classifier
vae_embedding_model
clustering_model
```

Not every field will be recoverable from every DeepSqueak artifact. Unknown values should remain unknown rather than fabricated.

For reproducibility, a checksum is particularly valuable where a model has a user-defined filename but no formal release version.

---

## 16. Input recording identity

Cross-extractor matching only works safely if VAWLUME knows that two outputs came from the same source recording.

File paths are fragile. Recommended matching hierarchy:

1. cryptographic checksum of the source WAV;
2. persistent VAWLUME `recording_id`;
3. documented original relative path;
4. file name as a weaker fallback.

The DeepSqueak native artifact's audio-path metadata can help establish this linkage.

Recommended:

```text
recordings
----------
recording_id
source_path
source_filename
checksum
sample_rate_hz
channel_count
duration_s
...
```

```text
extraction_run_inputs
---------------------
extraction_run_id
recording_id
input_role
```

This generalizes cleanly to MUPET and future extractors.

---

## 17. Multichannel audio is version-sensitive

DeepSqueak's changelog records changes in multichannel handling across releases. At different points, behavior included first-channel use, averaging, maximum-intensity projection, or selectable handling.

Therefore:

- channel behavior belongs in run provenance/settings when recoverable;
- `recording.channel_count` is not enough to infer what DeepSqueak actually analyzed;
- a VAWLUME calibration study should ensure both extractors receive meaningfully comparable channel/audio representations.

If the lab preprocesses audio before one or both extractors, that preprocessing should be represented as its own artifact/transformation, not hidden in notes.

---

## 18. Review/calibration implications for VAWLUME consilience

DeepSqueak's editable detections support the proposed VAWLUME calibration workflow particularly well:

1. run DeepSqueak and MUPET on a representative calibration corpus;
2. preserve initial automated artifacts;
3. human-review a manageable sample;
4. estimate detection error and boundary/feature agreement;
5. establish project-specific candidate-match and corroboration thresholds;
6. freeze the extractor versions, model artifacts, settings artifacts, and VAWLUME consilience policy;
7. apply the automated policy to the production corpus;
8. retain disagreement cases for optional targeted review.

This uses manual labor strategically rather than assuming it can be eliminated.

The schema should therefore distinguish:

```text
extractor_native_acceptance
human_calibration_reference
vawlume_consensus_status
```

They are different evidentiary layers.

---

## 19. Proposed DeepSqueak built-in template contents

A VAWLUME template should be more than a column rename dictionary.

Suggested structure:

```yaml
template:
  extractor: DeepSqueak
  supported_versions:
    - "3.2.x"

artifacts:
  native_detection:
    parser: ...
    priority: preferred
  excel_event_export:
    parser: ...
    priority: supported

settings_capture:
  preferred_source: detection_metadata
  externalize_to_json: true

models:
  detector:
    capture_identity: true
    checksum_when_available: true

features:
  - native_name: "Begin Time (s)"
    canonical_name: "call_start_time"
    native_unit: "s"
    canonical_unit: "s"
    derivation_stage: "contour_derived"
    mapping_type: "conceptually_equivalent"

  - native_name: "Principle Frequency (kHz)"
    canonical_name: "contour_median_frequency"
    native_unit: "kHz"
    canonical_unit: "Hz"
    derivation_stage: "contour_derived"
    transform: "kHz_to_Hz"

review:
  accept_field: "Accepted"
  treat_as_ground_truth: false

event_identity:
  native_id_field: "ID"
  scope: "artifact"

consilience_defaults:
  candidate_matching:
    primary:
      - call_start_time
      - call_end_time
    supporting:
      - call_duration
      - frequency_min
      - frequency_max
  thresholds:
    source: "project_config_only"
```

Actual machine-readable VAWLUME templates can be designed later. The important point is that **global templates define semantics and parser behavior; project configuration defines empirical acceptance thresholds.**

---

## 20. Recommended general schema additions motivated by DeepSqueak

DeepSqueak provides concrete justification for the following general-purpose entities:

### `extractors`

Program identity.

### `extractor_versions`

Optional normalized release/build table if VAWLUME needs version-specific behavior.

### `extraction_runs`

A specific application of an extractor to one or more recordings.

Suggested stable fields:

```text
extraction_run_id
extractor_id
extractor_version
software_commit
settings_artifact_id
started_at
completed_at
run_scope
notes
```

### `extractor_artifacts`

Native/derived files produced or used during a run.

### `model_artifacts`

Detector/classifier models that materially determine output.

### `extractor_features`

Native feature definitions, version scope, units, methods.

### `canonical_features`

VAWLUME feature concepts.

### `feature_mappings`

Native-to-canonical semantic/name mappings.

### `feature_relationships`

Pairwise relationships used for cross-extractor comparability/consilience.

### `detections`

Extractor-specific event records.

### `event_measurements`

Long-form native/canonical measurements.

### `review_states` or `curation_events`

Extractor/manual acceptance, rejection, deletion, or other review state where recoverable.

### `classification_runs` / `classification_assignments`

Labels derived after detection.

### `consensus_events` / `consensus_event_members`

VAWLUME-created cross-extractor event groupings.

---

## 21. Suggested pairwise feature-relationship table

DeepSqueak makes a pairwise relationship table preferable to inferring comparability solely from shared canonical names:

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
source_reference
```

Example conceptually:

```text
DS contour Begin Time
<-> MUPET syllable start time
relationship_type = comparable
comparison_method = absolute_difference + temporal_overlap
consilience_eligible = true
default_role = primary
```

By contrast:

```text
DS Mean Power (dB/Hz)
<-> MUPET total syllable energy (dB)
relationship_type = related
consilience_eligible = false
```

This prevents a shared generic acoustic domain ("power") from creating a false equivalence.

---

## 22. Validation checks VAWLUME can perform on import

A DeepSqueak importer could run non-destructive quality checks such as:

- verify that `end_time >= begin_time`;
- compare exported `Call Length` with `End Time - Begin Time`;
- verify unit declarations;
- detect duplicated native IDs within one artifact;
- identify missing or unexpected columns against the version-scoped template;
- verify source recording linkage;
- report accepted/rejected proportions without changing them;
- detect whether file-name columns expected for a particular export version are present;
- flag feature-semantic mismatches instead of guessing.

Derived validation quantities should be stored or logged separately from native extractor values.

---

## 23. Open questions for implementation testing

Documentation/source inspection cannot answer every practical import issue. Before finalizing DeepSqueak support, VAWLUME should test real artifacts for:

1. exact serialized structure of current v3.2.x native detection files;
2. whether all relevant settings are reliably retained in `detection_metadata`;
3. network/model identifiers and whether model file checksums can be recovered cleanly;
4. how manual box edits propagate to contour-derived features;
5. whether review/edit history is recoverable or only final state;
6. behavior when rejected calls are excluded from Excel export;
7. exact column order/naming across batch/single exports and versions;
8. representation of missing values;
9. time precision in native versus Excel export;
10. how classifications are stored after manual/supervised/unsupervised workflows;
11. whether source audio metadata is sufficient to hash/verify the originating recording automatically;
12. current multichannel behavior and its settings representation.

These are excellent candidates for VAWLUME parser fixtures generated from small synthetic/test recordings.

---

## 24. Proposed minimum DeepSqueak contract for the VAWLUME prototype

For the prototype, a realistic minimum is:

### Required run-level inputs

- extractor = DeepSqueak;
- extractor version;
- source recording mapping;
- DeepSqueak settings JSON or explicit "not recoverable";
- detector-network identity if recoverable;
- source artifact checksum.

### Required event-level values

- VAWLUME `detection_id`;
- native event ID/index;
- source recording;
- start time;
- end time;
- duration;
- accepted/rejected state if exported;
- detector score if exported;
- label if exported;
- acoustic features available in the chosen export.

### Required feature metadata

- native name;
- canonical feature mapping;
- native/canonical units;
- derivation stage;
- operational definition/source;
- version scope;
- pairwise comparability rules for MUPET-supported features.

### Required provenance behavior

- preserve raw artifact;
- never overwrite native values during normalization;
- record parser/template version;
- preserve transformation lineage.

That is sufficient to demonstrate an extractor-agnostic pattern without implementing every DeepSqueak artifact type immediately.

---

## 25. Design conclusions for VAWLUME

DeepSqueak supports several general principles that should survive beyond DeepSqueak itself:

1. **Extractor output is layered.** Model artifacts, native detections, reviewed detections, contours, exports, and classifications should not be conflated.
2. **Software version is part of measurement provenance.** Settings alone do not capture algorithm changes.
3. **Model identity is part of run provenance.**
4. **Review state is not ground truth.**
5. **Native and canonical feature values should coexist.**
6. **A canonical feature name denotes a construct, not automatic metric interchangeability.**
7. **Derivation stage matters.** Detector geometry and contour-derived timing can both describe "start time" while representing different operational measurements.
8. **Cross-extractor consilience should use documented pairwise comparability, not shared strings.**
9. **Project-specific thresholds belong in project configuration.** Built-in extractor templates should define semantics and sensible comparison candidates, not universal validation cutoffs.
10. **Artifacts should be immutable evidence where possible.** VAWLUME should add normalized layers rather than destructively rewrite extractor outputs.

---

## 26. Sources reviewed

### Primary DeepSqueak repository and release history

- DeepSqueak repository: https://github.com/DrCoffey/DeepSqueak
- Changelog: https://github.com/DrCoffey/DeepSqueak/blob/master/CHANGELOG.md

### DeepSqueak wiki/documentation

- Wiki home: https://github.com/DrCoffey/DeepSqueak/wiki
- USV Detection: https://github.com/DrCoffey/DeepSqueak/wiki/USV-Detection
- Output: https://github.com/DrCoffey/DeepSqueak/wiki/Output
- Export to Excel: https://github.com/DrCoffey/DeepSqueak/wiki/export-to-excel
- Selection Review: https://github.com/DrCoffey/DeepSqueak/wiki/Selection-Review
- Contour Detection: https://github.com/DrCoffey/DeepSqueak/wiki/Contour-Detection
- Supervised Classification: https://github.com/DrCoffey/DeepSqueak/wiki/Supervised-Classification
- Unsupervised Clustering: https://github.com/DrCoffey/DeepSqueak/wiki/Unsupervised-Clustering
- Syntax Analysis: https://github.com/DrCoffey/DeepSqueak/wiki/Syntax-Analysis

### Source inspected

- `Functions/CalculateStats.m`: https://github.com/DrCoffey/DeepSqueak/blob/master/Functions/CalculateStats.m

### Publication

- Coffey KR, Marx RG, Neumaier JF. DeepSqueak: a deep learning-based system for detection and analysis of ultrasonic vocalizations. *Neuropsychopharmacology*. 2019. Open-access version: https://pmc.ncbi.nlm.nih.gov/articles/PMC6461910/

---

## 27. Recommended status in the VAWLUME project

**Use this document as the human-readable basis for:**

- the initial `DeepSqueak` extractor template;
- version-scoped feature definitions;
- settings/model provenance requirements;
- schema decisions around artifacts, review state, and derivation stage;
- DeepSqueak–MUPET pairwise feature relationships;
- parser fixture/testing requirements.

When implementation begins, each machine-readable mapping should point back to a source reference and template version so that the code does not silently outgrow this design record.
