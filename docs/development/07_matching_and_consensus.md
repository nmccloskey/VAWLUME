# Matching and consensus prototype

## Scope

VAWLUME's Phase 6 prototype compares two explicitly selected extractor runs on
one recording without treating either as truth. It retains transparent temporal
candidate evidence, preserves split/merge ambiguity in connected-component
groups, derives bounded consensus lineage, reports detection and eligible
feature agreement, assigns categorical consilience statuses, compares them with
an independent manual reference, and exposes threshold sensitivity.

The runnable developer example is
[`examples/matching_consensus_demo.m`](../../examples/matching_consensus_demo.m).
It starts with public project intake and both public extractor importers and
removes its synthetic inputs and database before returning.

## Public API

```matlab
plan = vawlume.matching.compare(conn, recordingRef, runPair, matchSpec)
result = vawlume.matching.compare(conn, recordingRef, runPair, matchSpec, ...
    Apply=true)

report = vawlume.consilience.summarize(conn, matchingAnalysisRef)
report = vawlume.consilience.summarize(conn, matchingAnalysisRef, Apply=true)

sweep = vawlume.consilience.sensitivity(conn, matchingAnalysisRefs)
```

Planning is read-only. Matching apply persists the complete candidate,
group/member, and topology-permitted consensus graph atomically. Summarization
is read-only by default; apply persists aggregate statistics and one automated
assessment per group under a child `cross_extractor_agreement` analysis.
Sensitivity is always read-only and compares already-applied matching analyses.

## Analysis identity and configuration

A matching analysis is scoped by:

```text
project and recording
+ explicitly ordered run_a/run_b extraction runs
+ analysis run_key
+ matching profile key/version/exact SHA-256
+ matching algorithm key/version
```

The matching/consilience specification is canonical JSON under
`config/05_matching_profiles/`. It records candidate thresholds, assignment and
consensus policy, eligible feature support, tolerances, consilience rules,
manual-reference matching, and sensitivity configuration. Thresholds shipped
for the prototype are illustrative synthetic settings, not user defaults shown
to be scientifically calibrated.

Changed configuration uses a new immutable matching analysis. It never rewrites
an older candidate or group population.

## Temporal candidates

Geometry comes from `v_detection_core`; matching never reopens extractor files.
For run A interval `[startA,endA]` and run B interval `[startB,endB]`:

```text
overlap = max(0, min(endA,endB) - max(startA,startB))
union = max(endA,endB) - min(startA,startB)
temporal_iou = overlap / union
onset_difference = startB - startA
offset_difference = endB - endA
duration_difference = (endB-startB) - (endA-startA)
candidate_score = temporal_iou
```

The current candidate rule requires positive overlap and IoU at or above the
profile threshold. Every eligible edge is retained; no nearest-neighbour,
Hungarian, score-winner, or learned assignment is used.

## Assignment graph and topology

Detections are bipartite vertices, eligible candidates are edges, and connected
components are correspondence groups. Isolated vertices become explicit
single-member unmatched groups. Every input detection therefore belongs to
exactly one group under one analysis while candidate evidence remains separately
queryable.

Topology uses ordered side counts:

| Run A | Run B | Topology |
|---:|---:|---|
| 1 | 1 | `one_to_one` |
| 1 | N | `one_to_many` |
| N | 1 | `many_to_one` |
| N | M | `many_to_many` |
| one side only | 0 | `unmatched` |

Split/merge direction is relative to caller-supplied run order, never a claim
that one extractor segmented a true biological event correctly.

## Consensus semantics

A consensus event is a derived lineage object and never replaces or retimes a
native detection.

| Topology | Emit | Interval method |
|---|---|---|
| `one_to_one` | yes | mean member starts and mean member ends |
| `one_to_many` / `many_to_one` | yes | minimum start through maximum end |
| `many_to_many` | no | ambiguity remains group-only |
| `unmatched` | no | one extractor is not cross-extractor consensus |

Each emitted event repeats its group's exact detection membership and roles.
No calibrated consensus confidence is stored.

## Detection agreement

Each run reports its own denominator and partitions detections into:

- unambiguous one-to-one membership;
- ambiguous 1:N/N:1/N:M membership;
- unmatched membership.

It also reports participation in any cross-extractor group and proportions
using that run's total detection count. Topology group counts remain separate
from participating-detection counts, so a 1:2 component is one group rather
than two independent matches. Temporal summaries for 1:1 groups reuse stored
candidate evidence and preserve the `run_b - run_a` direction.

## Feature eligibility and comparison

Cross-extractor feature discovery uses the registered semantic route:

```text
extractor_features.equivalence_class
+ feature_relationships relationship metadata
+ consilience_eligible
+ compatible canonical units
```

Canonical-name equality is neither required nor sufficient. The central-
frequency proof keeps DeepSqueak `contour_median_frequency` and MUPET
`frequency_center` distinct while discovering their shared
`vocalization_frequency_center` equivalence class and `comparable` relationship.
They are comparable; they are not relabeled as identical or transform-
equivalent.

DeepSqueak mean power spectral density versus MUPET total energy or peak
amplitude remains visible as `related`, unit-incompatible, and
`consilience_eligible = 0`. Those relationships are not scored.

Quantitative comparison is restricted to `one_to_one` groups. Ambiguous members
are never averaged without a scientific aggregation model. Returned rows retain
both methods and values and provide signed difference (`run_b - run_a`),
absolute difference, and pair mean. Aggregates include bounded descriptive
summaries. Correlation is withheld below the configured sample size; ICC is
disabled pending a justified form and real data.

## Consilience rules

One automated categorical status is assigned per group:

| Status | Evidence rule |
|---|---|
| `single_extractor` | unmatched under this specification |
| `ambiguous_split_merge` | 1:N, N:1, or N:M topology |
| `temporally_matched` | 1:1 with insufficient eligible feature support |
| `matched_feature_supported` | enough eligible comparisons and none outside tolerance |
| `matched_feature_discrepant` | at least one eligible comparison outside tolerance |

Missing evidence is not discrepancy. Ineligible relationships cannot move a
status. The schema score stays NULL because these categories are not calibrated
probabilities. Manual adjudication is reported as a separate relational verdict
and never overwrites the automated status.

`single_extractor` means only that no eligible cross-extractor correspondence
survived this specification. It does not mean false positive or invalid call.

## Independent manual-QC boundary

Reviewer-authored `manual_reference_events` are recording/reference-set scoped,
not derived from DeepSqueak Accepted, native labels, or detector scores. The
manual detection-to-reference IoU rule is separately configured from the
extractor-to-extractor rule and uses one-to-one greatest-IoU assignment.

With exhaustive coverage, the report provides per-extractor true positives,
false positives, false negatives, precision, recall, and boundary error. Under
partial coverage, recall and false-negative statistics are withheld because the
denominator is unknown. DeepSqueak curation may be shown as a secondary
cross-reference but enters no automated rule and authors no manual label.

The prototype does not yet provide a reviewer-file ingest API. The disposable
demonstration therefore authors its four explicitly synthetic reviewer rows in
code; no interactive database edit is required.

## Threshold sensitivity

The demonstration applies three separate matching profiles over identical
inputs:

```text
permissive    IoU 0.05
illustrative  IoU 0.10
strict        IoU 0.50
```

Sensitivity reports candidates, topology, unmatched counts, statuses, profile
lineage, and manual metrics. It refuses analyses with different recordings,
ordered runs, algorithm versions, or reference sets. It selects no winner:
choosing a threshold from synthetic manual agreement would fit the fixture, not
calibrate a scientific matcher.

## Transactions and idempotency

Matching apply is atomic across its full graph. Agreement apply is separately
atomic under its child analysis across statistics and assessments. Compatible
reruns reuse identities and write nothing; stored differences conflict rather
than being repaired. Multiple threshold analyses coexist over the same native
detections.

Matching and consilience never update extractor runs, artifacts, detections,
measurements, curation, classification, candidates from another analysis, or
native timing. `PRAGMA foreign_key_check` is part of demonstration and test
read-back.

## Demonstration topology

The synthetic example imports four DeepSqueak calls and six MUPET syllables.
Under the illustrative profile it produces four candidate edges and six groups:

- two `one_to_one` groups;
- one `one_to_many` group containing one DeepSqueak call and two MUPET
  syllables;
- one unmatched DeepSqueak group;
- two unmatched MUPET groups;
- three consensus events: two mean-boundary 1:1 intervals and one union envelope.

The two 1:1 groups become one feature-supported and one feature-discrepant
status. The ambiguous group remains ambiguous and all unmatched groups remain
single-extractor. The independent reference yields DeepSqueak precision/recall
of 0.75/0.75 and MUPET precision/recall of 0.50/0.75 on this fixture. These are
computation checks, not extractor-performance estimates.

## Limitations

- every extractor artifact and reviewer event in the demonstration is synthetic;
- matching and manual-reference thresholds are illustrative and uncalibrated;
- there is no learned matcher or automatic biological class reconciliation;
- ambiguous groups are preserved, not automatically adjudicated or aggregated;
- feature agreement is limited to registered eligible relationships and 1:1
  groups;
- no sequence/bout analysis, external-event alignment, hierarchy-aware
  inferential model, or poster claim of validated extractor performance exists;
- correlation/ICC remain unexercised at realistic sample size;
- there is no reviewer-file ingest API, so reference events must be authored
  directly against `manual_reference_events`;
- registered feature relationships are matched to an analysis by extractor
  name, not by extractor version. A relationship registered against a different
  version of the same extractor yields an unavailable comparison rather than a
  wrong one, but it is not selected out explicitly.

`candidate_pairs` is constrained by trigger to one recording and two distinct
extraction runs, but not to its analysis run's declared inputs; that narrower
scope is enforced by the implementation and asserted by tests rather than by the
schema. `match_group_members` is trigger-constrained to the declared inputs.

The Phase 6 integration and exit review has passed. Goal 3 has a functioning
prototype, and the next implementation target is one compact sequence/alignment
analysis.

More detailed stage contracts remain in
[`07_matching_candidate_generation.md`](07_matching_candidate_generation.md),
[`08_matching_assignment_and_consensus.md`](08_matching_assignment_and_consensus.md),
[`09_detection_and_feature_agreement.md`](09_detection_and_feature_agreement.md),
and
[`10_consilience_manual_qc_and_sensitivity.md`](10_consilience_manual_qc_and_sensitivity.md).
