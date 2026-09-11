# Arbitrary-N extractor-agreement schema

Schema version `0.6-draft`, `PRAGMA user_version = 6`. The `0.5` to `0.6` change
adds a relational home for arbitrary-N extractor agreement: multi-source
analysis lineage, agreement groups over native detections, and exact supporting
candidate edges. No existing table, trigger, view, or index changed.

This pass is schema and provenance only. Nothing populates these tables yet,
there is no derive API, and `vawlume.matching.compare` is untouched and still
strictly pairwise.

## What the layer is

Pairwise correspondence remains the primitive. An **agreement group** is a
derived component over native detections for one recording, composed from the
exact candidate edges of two or more pairwise analyses.

It does not replace anything:

| Layer | Scope | Authority for |
|---|---|---|
| `candidate_pairs` | one ordered run pair | exact temporal edge and its metrics |
| `match_groups` | one ordered run pair | pairwise partition and topology |
| `consensus_events` | one pairwise group | derived interval geometry |
| `agreement_groups` | N runs, one recording | derived component over detections |

## Multi-source lineage

`analysis_runs.parent_analysis_run_id` cannot express this derivation. An
agreement run over three extractors consumes three pairwise analyses and there
is no single parent among them, so lineage moves to its own relation:

```sql
CREATE TABLE analysis_run_sources (
    analysis_run_id        INTEGER NOT NULL REFERENCES analysis_runs(analysis_run_id) ON DELETE CASCADE,
    source_analysis_run_id INTEGER NOT NULL REFERENCES analysis_runs(analysis_run_id) ON DELETE RESTRICT,
    dependency_role        TEXT NOT NULL DEFAULT 'source_analysis',
    notes                  TEXT,
    PRIMARY KEY(analysis_run_id, source_analysis_run_id),
    CHECK(analysis_run_id <> source_analysis_run_id)
);
```

`parent_analysis_run_id` keeps its existing meaning for genuinely single-parent
child runs, such as the pairwise agreement-statistics run, and is not
overloaded. One source analysis contributes to one derived analysis once, so
`dependency_role` is descriptive rather than part of identity.
`trg_analysis_run_source_project_scope` requires both analyses to share a
project. Cycles beyond a self-link are not policed: the derivation layer will be
the only writer and it composes already-completed pairwise analyses.

## Agreement groups, members, and supporting edges

```sql
CREATE TABLE agreement_groups (
    agreement_group_id  INTEGER PRIMARY KEY,
    analysis_run_id     INTEGER NOT NULL REFERENCES analysis_runs(analysis_run_id) ON DELETE CASCADE,
    recording_id        INTEGER NOT NULL REFERENCES recordings(recording_id) ON DELETE CASCADE,
    group_key           TEXT NOT NULL,
    derivation_method   TEXT NOT NULL,
    notes               TEXT,
    UNIQUE(analysis_run_id, group_key)
);
```

`group_key` is the group's deterministic identity within its agreement run, in
the sense the pairwise layer already uses for components: an ordered member
identity string. A rerun needs it before members exist in order to decide reuse
versus conflict, which is why it is stored rather than derived. It is an
identity, not a summary, and must not encode counts, fractions, or labels.

Agreement groups require their own analysis `run_type`,
`multi_extractor_agreement`, enforced by `trg_agreement_group_run_scope`
together with recording/project consistency. An agreement group cannot be
grafted onto a `cross_extractor_matching` analysis, which would quietly turn a
two-run partition into something else.

Members reference native detections:

```sql
CREATE TABLE agreement_group_members (
    agreement_group_id  INTEGER NOT NULL REFERENCES agreement_groups(agreement_group_id) ON DELETE CASCADE,
    detection_id        INTEGER NOT NULL REFERENCES detections(detection_id) ON DELETE RESTRICT,
    member_role         TEXT,
    PRIMARY KEY(agreement_group_id, detection_id)
);
```

`trg_agreement_member_recording` and `trg_agreement_member_analysis_partition`
mirror the pairwise member triggers: one recording per group, membership only
from extraction runs the agreement analysis declared in
`analysis_run_extraction_inputs`, and at most one group per detection per
agreement run. The same detection may join a group in a different agreement run;
two derivations over the same evidence are separate results, not a conflict.

Support is the exact pairwise edge:

```sql
CREATE TABLE agreement_supporting_edges (
    agreement_supporting_edge_id INTEGER PRIMARY KEY,
    agreement_group_id  INTEGER NOT NULL REFERENCES agreement_groups(agreement_group_id) ON DELETE CASCADE,
    candidate_pair_id   INTEGER NOT NULL REFERENCES candidate_pairs(candidate_pair_id) ON DELETE RESTRICT,
    notes               TEXT,
    UNIQUE(agreement_group_id, candidate_pair_id)
);
```

`trg_agreement_supporting_edge_scope` requires the cited candidate pair to come
from an analysis declared in `analysis_run_sources`, to describe the group's
recording, and to join two detections that are both members of the group it
supports. Members must therefore be inserted before their edges.

## Topology needs no second foreign key

The pairwise match group of a supporting edge is reachable and unique: a
pairwise analysis assigns each detection to at most one group, and a candidate
edge's two endpoints are joined into the same component. So no `match_group_id`
is stored here.

```sql
SELECT ase.agreement_supporting_edge_id, ar.run_key,
       IFNULL(g.match_type, 'no_group_materialized') AS pairwise_topology
FROM agreement_supporting_edges ase
JOIN candidate_pairs cp ON cp.candidate_pair_id = ase.candidate_pair_id
JOIN analysis_runs ar ON ar.analysis_run_id = cp.analysis_run_id
LEFT JOIN (
    SELECT mgm.detection_id, mg.analysis_run_id, mg.match_group_id, mg.match_type
    FROM match_group_members mgm
    JOIN match_groups mg ON mg.match_group_id = mgm.match_group_id
) g ON g.detection_id = cp.detection_a_id
   AND g.analysis_run_id = cp.analysis_run_id;
```

The analysis constraint belongs inside that join. Joining
`match_group_members` on the detection alone fans out across every analysis the
detection participates in. A candidate-only source analysis reports no group,
which is absence rather than ambiguity and does not disqualify the edge.

## Deletion policy

`RESTRICT` on `analysis_run_sources.source_analysis_run_id`,
`agreement_supporting_edges.candidate_pair_id`, and
`agreement_group_members.detection_id`. A persisted derived result must not
silently outlive the evidence it was composed from, so deleting a source
analysis, a cited candidate pair, or any detection that a derived agreement
group holds as a member is refused while that group still cites it. Deleting the
agreement run cascades the derived layer away and touches no pairwise or native
row; the source evidence is then deletable again.

The member restriction is not redundant with the edge restriction. A matched
member is protected indirectly, because the candidate pair joining it to the
group is itself restricted. A singleton or extractor-unique member participates
in no candidate pair, so without its own restriction it would cascade away
silently, leaving a group whose stored `group_key` — the sorted list of its
members' selectors — still named a detection that no longer exists. That member
is exactly the one the composition policy deliberately keeps.

## Evidence-capacity contract

Three dimensions stay separate. Collapsing them is what makes a single
categorical status look like a verdict on the match.

| Dimension | Question | Where it lives |
|---|---|---|
| Potential feature support | what could in principle be compared across these extractor versions | `feature_relationships` + `consilience_eligible` + equivalence class + unit compatibility + the versioned policy |
| Realized availability | what could actually be computed for this matched event | `event_measurements` for the two member detections |
| Observed outcome | what was within tolerance, outside it, or missing | the pairwise comparison under the versioned tolerances |

### Potential support is relational, not intrinsic

There is deliberately no `extractor_features.support_level` column. The same
native feature has different support capacity depending on which extractor
versions are being compared, so capacity is a property of the relationship
graph, not of the feature.

`v_feature_relationship_endpoints` exposes that graph one endpoint at a time:
exactly two rows per registered cross-extractor relationship, one from each
feature's point of view. `v_cross_extractor_feature_pairs` answers "what is this
pair?"; this view answers "which counterparts does this feature have, in which
extractors?", which is the question capacity actually asks. Orienting from the
pair view requires checking both sides every time, because `feature_a`/
`feature_b` order follows the ascending-id CHECK and carries no extractor
meaning.

The view joins no canonical features: a feature may carry several canonical
mappings across profile versions, and fanning them out would make every
counterpart count wrong. It also classifies nothing — which equivalence classes
count as primary temporal evidence rather than independent support is a policy
statement, so `equivalence_class` is exposed verbatim and the caller applies
`feature_support.timing_classes_reserved_as_primary_evidence` from the versioned
specification.

Derivable per selected extractor set, and deliberately unstored: the exact
eligible counterpart set, distinct counterpart count, possible counterpart count
(`N - 1`), which counterparts are absent, and convenience categories such as no
counterpart / one counterpart / multiple counterparts.

### Worked example

Eligible non-timing relationships per extractor pair in the shipped registry:

| Pair | Eligible non-timing relationships |
|---|---|
| DeepSqueak ↔ MUPET | 4 |
| DeepSqueak ↔ USVSEG | 1 |
| MUPET ↔ USVSEG | 1 |

The specification's `consilience.support_rule.minimum_supporting_comparisons`
is 2. That is the whole reason a USVSEG-involving one-to-one group cannot reach
`matched_feature_supported` and stays `temporally_matched`: USVSEG exports no
frequency extent, so it shares only the three timing classes and the central
frequency class with either peer, and timing classes are reserved as primary
temporal evidence rather than independent support.

That is a limitation of the categorical support rule, not evidence that the
temporal match failed. Deriving it from exact edges keeps the explanation true
if a relationship is later registered or withdrawn.

Counts alone are not enough, which is why they are not stored. DeepSqueak's
`Delta Freq (kHz)` and `Mean Power (dB/Hz)` both have exactly one distinct
counterpart extractor; the first has one eligible counterpart feature and the
second has two counterparts, neither eligible. And a shared equivalence class is
not comparability: DeepSqueak's `Peak Freq (kHz)` and USVSEG's `maxfreq` both
sit in `vocalization_peak_frequency` with no registered relationship at all, so
neither reports the other as a counterpart.

## Non-filtering semantics

Membership and supporting edges are never gated on feature support. An
`agreement_supporting_edges` row stays valid when no eligible non-timing feature
relationship exists, when only one exists, when a measurement is missing for
this event, when the group is only `temporally_matched`, and when the feature
evidence is discrepant. Nothing in the layer reads
`consilience_assessments.status`.

Temporal correspondence, pairwise topology, feature-support potential, feature
availability, and feature outcome remain five separately queryable dimensions.
Later query, report, and EDA surfaces may filter and sort on any of them; the
derivation layer does not erase a row because it fails one convenience label.

The candidate universe is a different matter. Pairwise matching still defines
its candidates as positive temporal overlap plus the versioned
`min_temporal_iou` floor, and pairs below that floor are absent from the source
analysis. This layer preserves and labels the evidence *inside* that universe.
Storing all positive-overlap candidates and thresholding at query time would be
a matcher and specification change, planned explicitly rather than folded in
here.

## What is deliberately not stored

Participating extractor count, supported-edge count, possible-edge count,
support fraction, completeness, pattern labels such as `2_of_3`, extractor-set
labels, feature-support capacity counts, and confidence categories. All are
derivable from the members, the edges, the source analyses' declared extraction
inputs, and `feature_relationships`. Storing any of them would create a second
answer that can drift out of agreement with the evidence it summarises.

The schema tests assert the column lists of all four new tables, and of
`extractor_features` and `feature_relationships`, so adding such a column is a
test failure rather than a silent change.

## Tests

- [`../../tests/unit/test_agreement_schema.m`](../../tests/unit/test_agreement_schema.m) —
  object existence, column lists, lineage constraints, run-type and recording
  scope, member partitioning, edge scope, non-gating on feature support,
  topology derivation, and deletion policy.
- [`../../tests/integration/test_feature_support_capacity.m`](../../tests/integration/test_feature_support_capacity.m) —
  the endpoint view over the shipped registry: exactness, per-pair non-timing
  potential, counterpart identity, absent counterparts, and two same-count
  patterns that stay distinguishable.
- [`../../tests/unit/test_schema_creation.m`](../../tests/unit/test_schema_creation.m) —
  schema version, `user_version`, and the object inventory.
