# Arbitrary-N agreement composition

## What composition does

`vawlume.agreement.compose` now builds and persists the components, not just the
analysis boundary. Same entry point, same arguments as
[17_agreement_run_planning.md](17_agreement_run_planning.md); one call plans or
applies the whole derivation.

Three facts are stored, and nothing else:

| Table | One row per |
|---|---|
| `agreement_groups` | component, identified by `group_key` |
| `agreement_group_members` | native detection in a component |
| `agreement_supporting_edges` | exact `candidate_pair_id` supporting a component |

Every reported summary — member counts, extractor counts, supported and
unsupported pair labels, ambiguity — is recomputed from those rows. None is
stored.

## Edge eligibility, frozen

> Every stored `candidate_pairs` row of a declared source analysis is a support
> edge.

That is a statement about the current matcher, not a convenience. Candidate
generation keeps every pair satisfying the specification's plausibility rule and
performs no best-candidate reduction; assignment consumes all of them as graph
edges; each row is written with `candidate_status = 'eligible'`. So the stored
candidate set and the set of edges that participate in the pairwise partition
are the same set, and there is no accepted/rejected distinction to filter on.

Because that identity is load-bearing, it is **verified rather than trusted**.
Where a source analysis materialized its match groups, every edge must join two
detections of one group. An edge that does not raises
`vawlume:agreement:EdgeOutsidePairwisePartition` — which is what a future
rejected-candidate state, or a hand-authored analysis, would trip. Where a
source analysis materialized no groups, its candidate rows remain the assessed
edge set and their topology is reported as `no_group_materialized`: absence, not
ambiguity.

The result carries the rule so a caller can read it back:

```matlab
result.eligibility.edge_universe      % stored_candidate_pairs_of_declared_source_analyses
result.eligibility.status_filter      % none_applied
result.eligibility.transitive_edges   % never_synthesized
```

Two further guards: an edge whose endpoint is outside the participating node set
raises `EdgeOutsideNodeSet`, and the same detection pair supported by two source
analyses raises `DuplicateSupportEdge` (impossible under the complete-set
contract, so it means incompatible sources).

## The node set

Every native detection of the participating extraction runs on the recording,
including detections with no support edge at all. An extractor-unique event has
to reach composition to survive it as a singleton, so the node set is built from
the runs rather than from the edges.

## Connectivity is not completeness

`vawlume.agreement.internal.connectedComponents(nodeIds, edges)` returns a table
of `node_id` and `component_ordinal`. It knows nothing about detections,
extractors, or how many participants there are — which is why the composition
path has no place to acquire a hard-coded number of extractors.

It lives in `+internal` rather than the package's `private` folder so the graph
contract can be unit tested on synthetic inputs without a database. That test
exercises three, four, five, and twelve participants.

Determinism is part of the contract, because stored identity depends on it:
components are ordered by their smallest node identifier, members ascend within
a component, and permuting the nodes or the edges cannot change the output.

**A component says its nodes are connected. It never says every pair among them
is supported.** No transitive edge is synthesized to make a component look
complete. The five-member split component in the fixture would need ten edges to
be a clique over its members; it has six, and the four missing ones stay
missing.

## Component identity

`group_key` is the sorted list of member selectors, `extraction_run_key` plus
`#` plus `native_event_id`, joined with `|`:

```text
fixture_deepsqueak_social_v1#1|fixture_mupet_social_v1#1|fixture_usvseg_social_v1#1
```

Run-scoped native identity rather than detection ids, because detection ids are
surrogates. Sorted, so the key is independent of how the graph was traversed.

It is an identity, **not** a summary: nothing derivable about support belongs in
it. And unlike the pairwise layer — which matches stored components by a key
embedded in free-form `notes` — derived identity here is a real column with
`UNIQUE(analysis_run_id, group_key)` behind it. Groups and supporting edges are
written with no notes at all, which is exactly where a stored summary would
otherwise creep in unnoticed.

Rerun classification compares planned components against stored ones by
`group_key`, then by member set, then by cited `candidate_pair_id` set:

- **create** — nothing derived is stored, including a boundary applied earlier
  with composition pending;
- **reuse** — every group, member set, and edge set already matches exactly;
- **conflict** — something derived is stored and differs, with a message naming
  which component and which dimension.

## Reported dimensions, not one verdict

Each group in the result carries these separately:

| Field | Says |
|---|---|
| `member_count`, `extractor_count`, `extractor_names` | how big and how wide |
| `support_edge_count` | how many exact edges hold it together |
| `supported_pair_labels` | which unordered extractor pairs have support |
| `unsupported_pair_labels` | which pairs among its extractors do not |
| `pair_support_complete` | whether every possible pair is supported |
| `ambiguous_source_topologies` | which contributing pairwise topologies were ambiguous |
| `is_singleton` | single-extractor evidence |

Coarse support is summarized at the **extractor-pair** level, never by raw
detection-edge count. A component holding two MUPET syllables against one
DeepSqueak call keeps all its edges and still supports exactly one pair.

These are deliberately orthogonal. Collapsing them would destroy real
distinctions the fixture produces:

| Component | Shape | Pairs supported | Ambiguous |
|---|---|---|---|
| DS#1, MUPET#1, USVSEG#1 | complete triangle | 3 of 3 | no |
| DS#3, MUPET#3, MUPET#4, USVSEG#4, USVSEG#5 | split/merge | 3 of 3 | **yes** (`one_to_many`) |
| DS#3, MUPET#4, USVSEG#5 *(strict spec)* | open chain | **2 of 3** | no |
| DS#2, USVSEG#2 | pair only | 1 of 1 | no |
| USVSEG#6 | singleton | none possible | no |

The second and third rows are the point. One is complete at extractor-pair level
and still ambiguous; the other is partial and entirely unambiguous. A single
score or boolean cannot hold both.

## Ambiguity is carried, never coerced

A pairwise group's topology is derivable from each supporting edge and is
reported per edge and per component. It never removes an edge or a member.
Composition does not turn a split/merge into a one-to-one "agreement", and does
not refuse to compose a component because one source pair was ambiguous.

## The source universe decides the shape

The agreement layer applies no threshold. The candidate universe is whatever the
source analyses' versioned matching specifications defined.

The composition test demonstrates this directly: the same three extractors,
composed twice, once under the tracked specification (`min_temporal_iou` 0.10 →
11 edges, 5 components) and once under a stricter variant (0.47 → 8 edges, 6
components). The open-chain component only exists in the second run. Both
agreement runs coexist, each with its own lineage and components, and neither
re-filtered the other's evidence.

## Transaction and status

One transaction covers the boundary and the composition. Write order is fixed by
the schema: groups, then members, then supporting edges — the supporting-edge
trigger requires both endpoint detections to already be members of the group the
edge supports.

The run reaches `status = 'completed'` only once its components exist. A
boundary left `'started'` by an earlier pass is composed **into** and completed,
not duplicated: `analysis.action` is `reuse` while `analysis.graph_action` is
`create`, and the run keeps its `analysis_run_id`.

## Files

- [`../../src/+vawlume/+agreement/compose.m`](../../src/+vawlume/+agreement/compose.m)
- [`../../src/+vawlume/+agreement/+internal/connectedComponents.m`](../../src/+vawlume/+agreement/+internal/connectedComponents.m)
- `src/+vawlume/+agreement/private/` — `agreementResolveGraph` (nodes, edges, eligibility guard), `agreementBuildComponents` (components and reported dimensions), `agreementResolveDerivedGraph` (rerun classification), plus the 1.7 boundary files
- [`../../tests/unit/test_agreement_components.m`](../../tests/unit/test_agreement_components.m) — the arbitrary-N graph contract
- [`../../tests/integration/test_agreement_composition.m`](../../tests/integration/test_agreement_composition.m) — composition over the three-extractor fixture
- [`16_multi_extractor_agreement_schema.md`](16_multi_extractor_agreement_schema.md) — the tables and their triggers

## What 1.9 may derive from the stored facts

Everything in the reported-dimensions table above, plus anything else computable
from members, exact edges, the source analyses' declared inputs, and
`feature_relationships`: participating extractor sets, per-pair support
patterns, clique completeness, corroboration counts per detection, and the
potential/realized/observed feature-support dimensions from
[16_multi_extractor_agreement_schema.md](16_multi_extractor_agreement_schema.md).

None of it is stored, and none of it may become a membership test.

Phase 1.9 now exposes these derivations through
[19_agreement_query_views.md](19_agreement_query_views.md), while leaving this
composition and storage contract unchanged.
