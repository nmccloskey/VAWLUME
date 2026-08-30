# Detection- and feature-level agreement

## Public API

```matlab
report = vawlume.consilience.summarize(conn, analysisRef)
report = vawlume.consilience.summarize(conn, analysisRef, Apply=true)
```

`analysisRef` selects exactly one completed `cross_extractor_matching` analysis
by `analysis_run_id`, by `run_key`, or by `project_key` plus `run_key`.

Read-only by default: the default call writes nothing at all, not even a derived
analysis row. `Apply=true` persists the aggregate statistics and nothing else.

The specification is **not** a caller argument. It is resolved from the
`config_profile_versions` row the matching analysis linked through
`analysis_run_profiles`, and its file is re-hashed and compared against the
stored checksum. Agreement therefore cannot be computed under a specification
different from the one that produced the groups being summarized; a changed file
raises `vawlume:consilience:SpecificationChanged`.

## Detection-level agreement

### Denominators

Every proportion uses **that run's own detection count on this recording**. The
report carries the denominators rather than leaving them to be inferred, because
a single "percent agreement" over two extractors that found different numbers of
events has no defensible denominator.

Per run:

| Column | Meaning |
|---|---|
| `total_detections` | that run's detections on this recording |
| `in_cross_extractor_groups` | detections in any component with members from both runs |
| `in_one_to_one_groups` | detections in unambiguous 1:1 components |
| `in_ambiguous_groups` | detections in 1:N, N:1, or N:M components |
| `unmatched_detections` | detections in single-member `unmatched` groups |

The last three partition each run exactly once, and the partition is asserted at
runtime: if the matching analysis does not account for every detection,
`vawlume:consilience:PartitionIncomplete` is raised rather than a proportion
computed over an incomplete denominator.

Because the denominators differ, the same numerator gives different answers on
each side. In the shipped fixture one unmatched DeepSqueak call is 33% of its
run while one unmatched MUPET syllable is 25% of its own, and both figures are
reported.

### Symmetric summary

One pooled figure is published, and it travels with its own definition and a
caution:

```text
pooled_matched_coverage = (matched_a + matched_b) / (total_a + total_b)
```

It is **coverage, not an agreement rate**, and it is not a measure of either
extractor's accuracy.

### Topology accounting

Group counts and detection counts are reported separately per topology, so a
split component is visibly one component containing three detections rather than
two or three independent matches. Nothing in the report converts an ambiguous
component's edges into individual matches for a percentage.

### Temporal agreement

Summarized over unambiguous 1:1 components only, and **read from the stored
`candidate_pairs` row** rather than recomputed. The candidate row already holds
overlap, IoU, and the signed onset, offset, and duration differences computed at
generation time under the versioned specification. Recomputing them here would
risk a subtly different formula reporting a different answer than the evidence
the database already contains. If a 1:1 component has no single stored candidate
row, `vawlume:consilience:CandidateEvidenceMissing` is raised.

Signed differences are **run_b minus run_a** throughout, matching the stored
evidence direction. The ordered pair comes from
`analysis_run_extraction_inputs.input_role`, which is the only place run
direction is recorded.

## Feature-pair discovery

### The view

`v_cross_extractor_feature_pairs` joins `feature_relationships` to both
extractors' registered features, canonical names, canonical units, derivation
stages, and operational variants. It was added in this pass because there is now
a real consumer; Phase 5 recorded it as a view candidate and deliberately left it
unbuilt until its shape could be decided against actual use.

The view **filters nothing**. `relationship_type` and `consilience_eligible` are
exposed verbatim, because sharing an equivalence class does not make a pair
eligible. Its only restriction is `extractor_a <> extractor_b`, which is what
makes it a cross-extractor view.

`feature_a` / `feature_b` follow `feature_relationships`' ascending-id `CHECK`
and carry **no extractor or directional meaning**. Consumers orient themselves by
`extractor_a_name` / `extractor_b_name`; the implementation does exactly that
before computing any difference.

### Why not canonical name

A canonical-name join finds six shared concepts and **silently returns nothing at
all for central frequency**, because DeepSqueak's contour median is registered as
`contour_median_frequency` while MUPET's filterbank mean is `frequency_center`.
Registering them under one name would assert that a contour median and a
filterbank mean are the same statistic.

The registry route finds seven eligible pairs including central frequency, and
keeps both methods distinct while doing so — different canonical names,
different `derivation_stage` (`contour_derived` versus `spectral_filterbank`),
and `relationship_type = comparable`, never `transform_equivalent`. A regression
test asserts both halves: that the naive join misses it, and that the correct one
finds it.

### Eligibility

A pair is compared only when the registry says it is defensible:

```text
consilience_eligible = 1   AND   both canonical units agree
```

Unit compatibility is reported as `compatible`, `incompatible`, or
`unit_unknown`. An incompatible pair is never converted ad hoc.

Power, energy, and amplitude remain ineligible. Both `Mean Power (dB/Hz)`
relationships are registered as `related` with `consilience_eligible = 0`, and
their two sides carry different equivalence classes and different canonical
units. They are discoverable in the report and excluded from every comparison and
summary. The exclusion comes from the registry column, not from a name list in
code — no feature name literal appears anywhere in the implementation.

Timing classes (`vocalization_start_time`, `vocalization_end_time`,
`vocalization_duration`) are flagged `primary_temporal_evidence` so a later
consilience stage does not count them twice, once as candidate evidence and once
as independent feature support.

## Feature comparison

### Scope

Quantitative comparison is restricted to unambiguous `one_to_one` components.
Ambiguous components are reported with an explicit reason
(`not_computed_split_merge`) and unmatched groups with `not_computed_unmatched`.
Averaging two MUPET syllables to produce a value to compare against one
DeepSqueak call would require a scientific aggregation model that does not exist.

### Row contents

Each comparison row keeps both sides fully traceable: match group, both detection
IDs, both extractor names, both `extractor_feature_id` values, both native names,
both canonical names, both operational variants, both canonical values, the
canonical unit, and the differences. Nothing is collapsed into one anonymous
value.

### Metrics

```text
signed_difference   = value_b - value_a          (run_b minus run_a)
absolute_difference = abs(signed_difference)
pair_mean           = (value_a + value_b) / 2    (supports a Bland-Altman plot)
```

`relative_difference` is reported **only where the specification declares a
relative tolerance** for that equivalence class, which is its statement that
proportional comparison is the intended rule there. It is deliberately not
universal: an onset at 10.000 s versus 10.004 s differs by 0.04% only because the
recording happens to start where it does, and that number would say nothing about
boundary agreement.

`within_tolerance` is set exactly where a relative tolerance is declared.

### Exported duration is not the boundary delta

Two different quantities share the word duration. `temporal_agreement` reports
the boundary-derived difference from the candidate evidence; the feature
comparison for `vocalization_duration` uses MUPET's exported
**pre-noise-reduction** duration. In the shipped fixture they are −0.002 s and
−0.008 s respectively. The `operational_variant` columns carry the reason on the
row itself rather than leaving a reader to infer it.

### Missing measurements

A measurement one extractor never exported is **absent evidence, not
disagreement**. The row is kept with `status =
not_computed_missing_measurement`, NaN values, and no tolerance verdict; the
class drops out of the aggregate rather than biasing it; and the group remains
matched. A missing column does not unmatch a pair.

## Aggregate summaries

Per equivalence class, where N permits: n pairs, mean and median signed bias,
mean and median absolute difference, standard deviation, IQR, min and max, and
the count outside tolerance. Dispersion is `NaN` rather than zero when only one
matched event exists.

Correlation is **secondary characterization only** and is not computed below the
specification's `secondary_minimum_n` (10). On a synthetic fixture it would
characterize the fixture rather than the extractors, so it is reported as
`not_computed_insufficient_n` instead of printed with a caveat.

### ICC

**Deliberately not implemented.** The design outline lists it as possible "where
appropriate"; choosing an ICC form, establishing that the matched events are
independent, and validating an implementation all require real paired data that
does not exist yet. The specification carries `feature_agreement.icc.enabled =
false` with its reason, and enabling it raises
`vawlume:consilience:IccNotImplemented` rather than silently reporting an
uninterpreted coefficient.

## Persistence and provenance

### What is stored

Aggregates only, in `agreement_statistics`, under a **child analysis run** whose
`parent_analysis_run_id` is the matching analysis and whose `run_type` is
`cross_extractor_agreement`. The child links the same specification version with
`assignment_role = 'agreement_spec'` and the same ordered run inputs, so it is
self-describing.

The schema's own vocabulary is used: `detection_agreement`, `feature_agreement`,
and `matching_diagnostic`. Every `feature_agreement` row carries both
`feature_a_id` and `feature_b_id`, so each aggregate stays traceable to the exact
registered pair. Denominators, direction, scope, and definitions travel in each
row's `notes` JSON.

### What is not stored

Per-pair comparison rows are returned but never persisted. No schema row can hold
a match group, two detections, and two features with explicit lineage —
`derived_measurements` requires exactly one target and has no feature-pair
columns — and every per-pair value is exactly recomputable from the stored
candidates, measurements, and registry. Caching them would create a second copy
that could drift from the evidence.

### Rerun and change

The child analysis key includes the agreement algorithm version, so a changed
algorithm produces a new child rather than altering the meaning of stored
statistics.

A rerun with identical statistics reuses the existing child and writes zero rows.
Different statistics under the same key raise
`vawlume:consilience:AgreementConflict`. **Nothing is ever updated in place**,
which is the same immutable-analysis policy the matching stage uses.

## Upstream immutability

Agreement consumes projects, recordings, artifacts, extraction runs, detections,
event measurements, curation, classification, candidates, groups, and consensus
events **read-only**. No file under `src/+vawlume/+consilience/` contains an
`INSERT`, `UPDATE`, or `DELETE` against any of them, and a test asserts both the
static property and that a detection/measurement fingerprint is unchanged after
both a read-only and an applied summary.

## Terminology

The report carries a `terminology_note` because the vocabulary here is easy to
overstate:

- **unmatched** means no cross-extractor correspondence survived the
  specification. It is *not* a false positive.
- a **false positive or false negative** requires an independent manual
  reference, which Phase 6 does not have. Missed events are not representable at
  all: `manual_reviews` requires an existing detection, group, or consensus
  event to attach to.
- a **split or merge** group is one correspondence component, never several
  independent one-to-one matches.

## Limitations

- comparison is restricted to 1:1 components; no aggregation model exists for
  ambiguous components;
- correlation is deferred below n = 10 and ICC is not implemented;
- no consilience status, rationale, or manual adjudication is written — that is
  the next stage;
- recall against a manual reference is out of scope while missed events cannot
  be represented;
- every extractor artifact remains synthetic, so all agreement numbers
  demonstrate computation rather than measuring extractor agreement.
