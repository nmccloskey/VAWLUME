# Temporal Candidate Generation

## Scope

`vawlume.matching.compare` implements the first derived correspondence stage.
It consumes imported relational detections from two explicit extraction runs,
returns every temporally plausible cross-run edge, and can persist that candidate
graph with immutable analysis/configuration provenance.

Candidate generation itself does not discard or assign an edge. The public
`compare` workflow now continues into connected-component assignment and
consensus, documented in `08_matching_assignment_and_consensus.md`.

## Public call

```matlab
plan = vawlume.matching.compare(conn, recordingRef, runPair, matchSpec)
result = vawlume.matching.compare(conn, recordingRef, runPair, matchSpec, ...
    Apply=true)
```

`recordingRef` uses either `recording_id` or `project_key` plus
`source_relative_path`. `runPair` explicitly names `run_a` and `run_b`; each may
be a project-scoped extraction `run_key`, an `extraction_run_id`, or a scalar
struct containing one of those values. No latest-run or automatic discovery
policy exists.

`matchSpec.run_key` is the project-scoped immutable analysis identity.
`matchSpec.profile_path` optionally selects a JSON matching specification; when
omitted, the tracked prototype specification under
`config/05_matching_profiles/` is used. Optional descriptive fields are
`run_label`, `vawlume_version`, `source_commit`, and `notes`.

## Legal run pair

Both runs must:

- exist in the intended project;
- register the intended recording as an extraction input;
- be different extraction runs;
- belong to different extractors.

Caller order is preserved in `analysis_run_extraction_inputs.input_role` as
`run_a` and `run_b`. It defines the direction of signed evidence. The schema's
`candidate_pairs.detection_a_id < detection_b_id` rule is separate: those two
columns are numerically sorted and carry no run-side meaning. Candidate
`details_json` records both directed detection identities.

## Relational geometry and evidence

Geometry comes only from `v_detection_core`. Matching never opens an extractor
artifact or output-mapping profile and never recomputes imported semantics.
Duration is the view's boundary-derived `end_time_s - start_time_s` surface.
A zero-duration, non-finite, or otherwise invalid interval is a matching
preflight defect rather than silently producing `NaN` evidence.

For run A interval `[startA,endA]` and run B interval `[startB,endB]`:

```text
temporal_overlap_s     = max(0, min(endA,endB) - max(startA,startB))
union_s                = max(endA,endB) - min(startA,startB)
temporal_iou           = temporal_overlap_s / union_s
onset_difference_s     = startB - startA
offset_difference_s    = endB - endA
duration_difference_s  = (endB-startB) - (endA-startA)
candidate_score        = temporal_iou
```

The arithmetic is provided by
`vawlume.interval.relation(startA, endA, startB, endB)`. Matching supplies the
run-side meaning and retains its own eligibility rule; the interval primitive
has no detection identifiers, thresholds, candidate status, or domain mode.

The candidate rule always requires:

```text
temporal_overlap_s > 0
AND temporal_iou >= min_temporal_iou
```

Exact boundary contact is therefore not a candidate. Every qualifying edge is
retained; there is no nearest-neighbour or best-IoU reduction. The result also
returns detection IDs from each run with zero eligible edges.

### Optional magnitude bounds

`candidate_generation.plausibility_rule` may additionally declare any of:

```text
max_abs_onset_difference_s      admit iff abs(onset_difference_s)    <= value
max_abs_offset_difference_s     admit iff abs(offset_difference_s)   <= value
max_abs_duration_difference_s   admit iff abs(duration_difference_s) <= value
```

Each is a finite real scalar `>= 0` in seconds. Each is validated with its own
error identifier — `vawlume:matching:MaxAbsOnsetDifferenceInvalid`,
`...MaxAbsOffsetDifferenceInvalid`, `...MaxAbsDurationDifferenceInvalid`.

**Absent means unconstrained.** A specification that declares none of them
behaves exactly as before, down to the bytes of the evidence it stores. The
fields are optional rather than defaulted because the specification checksum is
taken over exact file bytes: a required field would change every tracked
specification's checksum and so invalidate the identity of every matching
analysis already recorded against one.

**The semantics are magnitude, not signed.** The `max_abs_` prefix is part of
the contract rather than a naming preference. `vawlume.interval.relation`
returns signed differences directed as run B minus run A, so a bound of 0.05 s
excludes a pair at −0.05 s exactly as it excludes one at +0.05 s. The comparison
uses the same three evidence fields the candidate row stores; matching
introduces no second definition of onset, offset, or duration difference.

Each bound can only remove a pair the rule above already admits, so the
start-ordered interval sweep's pruning remains correctness-preserving: a pair
the sweep never examines has no positive overlap and was never admissible.

There is no scale-free duration ratio. The duration dimension is an absolute
difference in seconds, because that is the quantity
`vawlume.interval.relation` computes and that primitive is shared with
`vawlume.attribution`.

### The recorded rule

`candidate_pairs.details_json` states which gates actually admitted the row.
`eligibility_rule` names the active gates joined by `_and_`, and each declared
bound appears beside `min_temporal_iou` with its value. Under an IoU-only
specification the rule reads `positive_overlap_and_min_temporal_iou` and no
bound keys are written, so old and new rows remain directly comparable.

The tracked `prototype_matching_consilience_spec.json` declares none of these
dimensions.

## Planning, provenance, and apply

Planning is database-read-only. The result exposes resolved recording and run
identity, specification key/version/checksum, algorithm key/version, detection
counts, candidate evidence, and unmatched counts.

The current apply owns one transaction containing:

1. project-scoped `config_profiles` / `config_profile_versions` registration;
2. one `analysis_runs` parent with `run_type = cross_extractor_matching`;
3. the `matching_spec` analysis-profile link;
4. ordered `run_a` / `run_b` extraction-input links;
5. all eligible `candidate_pairs` rows;
6. the ambiguity-preserving group/member partition;
7. topology-permitted consensus events and lineage members;
8. transition of the analysis parent from `started` to `completed`.

Any failure rolls the whole graph back and restores connection autocommit.
An identical rerun under one `run_key` reuses the completed analysis and writes
nothing. A changed checksum, ordered input pair, or candidate population under
that identity is a conflict. A different analysis `run_key` can coexist over
the same detections.

## Prototype calibration boundary

The shipped `min_temporal_iou = 0.10` value is an illustrative synthetic-fixture
setting, not an empirically calibrated or recommended scientific threshold.
Tests also load a distinct strict profile version to prove that the threshold is
configuration data and that multiple analyses can coexist without rewriting
prior evidence.
