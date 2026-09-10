# Phase 1 correspondence boundaries

Phase 1 produced four kinds of row that are easy to confuse and must not be.
This document names the boundary between them, states which is authority and
which is derived, and marks where the caller-attribution work of later phases
will attach.

It describes delivered behavior. Where a later-phase design is mentioned it is
labelled as not implemented.

## The four layers

```text
NATIVE DETECTIONS                       authority
  detections, event_measurements
  one row per thing an extractor reported
        │
        │  vawlume.matching.compare        THE PRIMITIVE
        ▼
PAIRWISE CORRESPONDENCE                 derived, per ordered run pair
  candidate_pairs      every temporally plausible cross-run edge
  match_groups         connected components over those edges
  consensus_events     emitted only where topology permits
        │
        │  vawlume.agreement.compose       DERIVED FROM THE PRIMITIVE
        ▼
ARBITRARY-N AGREEMENT                   derived, over a set of pairwise analyses
  agreement_groups          components over native detections
  agreement_group_members   the native detections in each
  agreement_supporting_edges every exact candidate_pair_id retained
        │
        │  (not implemented)
        ▼
CALLER ATTRIBUTION                      Phase 4+; nothing writes these rows
```

## Native detections are the only authority

A detection is one thing one extractor reported about one recording in one
extraction run. Native timing, native tokens, native units, and native field
names are never rewritten by anything downstream. Canonicalization is additive.

Separate extraction runs are never implicitly pooled. Two runs over the same
recording are two populations until something above this layer relates them,
and that relation is always a derived row with its own provenance.

Every layer below is regenerable from native detections plus a versioned
configuration. Delete every derived row and the scientific content is intact.

## Pairwise matching is the primitive

`vawlume.matching.compare` takes **two explicitly named runs** by two distinct
extractors on one recording, plus a versioned matching specification. Automatic
run discovery is forbidden by that specification.

Three distinctions matter here:

- a **candidate pair** is evidence: positive overlap meeting the configured
  temporal-IoU floor, carrying overlap, IoU, and signed onset/offset/duration
  differences. Every qualifying pair is written, so one-to-many and
  many-to-many evidence stays visible instead of collapsing to a best match;
- a **match group** is a connected component over those edges, including
  single-member groups for unmatched detections. Its `match_type` records
  topology; it does not resolve ambiguity away;
- a **consensus event** is a derived grouping emitted only where topology
  permits. A many-to-many group emits none, because one interval over it would
  assert a correspondence the evidence does not support, and an unmatched group
  emits none, because a consensus event containing one extractor's detection
  alone would imply agreement that does not exist.

Consilience statuses and agreement statistics sit beside this layer, not above
it: they quantify what these groups say for one run pair. A status is a
categorical evidence summary under a named specification, never a probability.

## Arbitrary-N agreement is composed, never measured directly

`vawlume.agreement.compose` takes **a set of completed pairwise analyses**, not
a set of runs. That is the whole architectural point: N-way agreement is
derived from the pairwise primitive rather than reimplemented as a second,
competing matcher.

The composition rules follow from that:

- for N participating extraction runs, all `N*(N-1)/2` extractor pairs must be
  present exactly once, so a missing supporting edge cannot be confused with a
  pair that was never assessed;
- every source must cite the same versioned matching specification, so one
  component's edges are not a mixture of thresholds;
- membership is **connectivity** over exact edges. Connectivity is not
  completeness: a component of three detections says they are connected, never
  that all three extractor pairs support one another;
- no transitive edge is ever synthesized to make a component look complete;
- every exact `candidate_pair_id` is retained, so a coarse summary can always
  be resolved back to the pairwise evidence that produced it;
- an extractor-unique detection survives as a single-member group.

The agreement policy declares **no threshold of any kind**, and the loader
refuses a variant that adds one. The candidate universe is already bounded by
the matching specification each source analysis recorded; a second threshold
here would be a competing authority silently re-filtering settled evidence.

### Exact support versus coarse support

These are independent and must stay so.

| | Meaning | Column |
|---|---|---|
| **Exact** | *which* unordered extractor pairs are supported | `supported_extractor_pair_pattern` |
| **Coarse** | *how many* are supported out of how many are possible | `supported_extractor_pair_count` / `possible_extractor_pair_count` |

Two components can both support two of three possible pairs while supporting
different pairs. Only the coarse query merges them. Reducing exact shape to K
is a deliberate query-time choice, never a storage decision.

`possible_extractor_pair_count` is component-local `C(N,2)` over the extractors
actually represented in that component — not a run-wide constant. A singleton
has no possible pair, so its support fraction is SQL NULL and MATLAB `NaN`
rather than zero: no corroboration was possible, which is not the same as
corroboration that failed.

### Group and member denominators

A split/merge component is **one agreement group with several native
observations**. Group counts and native-member counts are different
denominators, and a summary that does not say which one it used is
uninterpretable. `vawlume.agreement.selectPopulation` returns both, plus
`agreement_group_ids` and `detection_ids`, so downstream code must choose.

## The line that Phase 1 does not cross

Agreement is **methodological evidence about extractor convergence**. It is not:

- a confidence probability, calibrated or otherwise;
- a biological truth label;
- a claim that a vocalization occurred;
- evidence about *who* called.

Three extractors agreeing means three programs, given one recording, drew
similar boundaries. Whether they were all right in the same way is exactly what
this schema declines to assert. Triple convergence is never hard-coded as
"three votes = truth".

Every numeric threshold that any of these edges depends on is an illustrative
demonstration value. Calibration requires a genuine paired extractor session
and an independent manually reviewed reference subset, neither of which exists.

## Where caller attribution will attach

Not implemented. Recorded here so the boundary is not blurred retroactively.

Caller attribution targets a vocal event and asks which subject produced it.
That is a different question from correspondence, and it will need its own
evidence rows, candidate-caller rows, and decision rows — see the v2
development plan. Two constraints follow from the layering above:

- an attribution target must name whether it is an extractor-native detection,
  a pairwise consensus event, or an agreement group, because those are three
  different event sets with three different denominators;
- correspondence evidence and attribution evidence must not share a table.
  A high temporal IoU between two extractors says nothing about which animal
  called, and a schema that let one stand in for the other would make the
  distinction unrecoverable.

Hierarchy linkage as it exists today is **context, not attribution**.
`selectPopulation`'s `EntityId` filter scopes to recording-linked entities and
explicitly does not assert that the linked entity emitted any selected
detection; time-bounded participation requires the interval join demonstrated
in [`examples/agreement_filter_demo.m`](../../examples/agreement_filter_demo.m).

## Where each contract is documented

| Layer | Documents |
|---|---|
| Import | [`05_deepsqueak_import.md`](05_deepsqueak_import.md), [`06_mupet_import.md`](06_mupet_import.md), [`21_usvseg_import.md`](21_usvseg_import.md) |
| Pairwise | [`07_matching_and_consensus.md`](07_matching_and_consensus.md) (overview), [`07_matching_candidate_generation.md`](07_matching_candidate_generation.md), [`08_matching_assignment_and_consensus.md`](08_matching_assignment_and_consensus.md), [`09_detection_and_feature_agreement.md`](09_detection_and_feature_agreement.md), [`10_consilience_manual_qc_and_sensitivity.md`](10_consilience_manual_qc_and_sensitivity.md) |
| Arbitrary-N | [`16_multi_extractor_agreement_schema.md`](16_multi_extractor_agreement_schema.md), [`17_agreement_run_planning.md`](17_agreement_run_planning.md), [`18_agreement_composition.md`](18_agreement_composition.md), [`19_agreement_query_views.md`](19_agreement_query_views.md), [`20_agreement_population_selection.md`](20_agreement_population_selection.md) |
| Runnable | [`examples/multi_extractor_agreement_demo.m`](../../examples/multi_extractor_agreement_demo.m) crosses all three layers in one script |
