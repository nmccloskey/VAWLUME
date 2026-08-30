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

The configured candidate rule is:

```text
temporal_overlap_s > 0
AND temporal_iou >= min_temporal_iou
```

Exact boundary contact is therefore not a candidate. Every qualifying edge is
retained; there is no nearest-neighbour or best-IoU reduction. The result also
returns detection IDs from each run with zero eligible edges.

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
