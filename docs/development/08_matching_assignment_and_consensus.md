# Matching Assignment and Consensus

## Scope

`vawlume.matching.compare` converts the complete temporal candidate graph into
an ambiguity-preserving detection partition and, where the versioned matching
specification permits it, derived consensus intervals. This stage does not
compute feature agreement, consilience classifications, or agreement
statistics, and it never changes native detection boundaries or measurements.

## Assignment model and deterministic identity

Candidate detections are the vertices of a bipartite graph and every persisted
candidate pair is an edge. Match groups are the graph's connected components;
there is no optimizer, score winner, nearest-neighbour reduction, or forced
one-to-one assignment. Candidate input is sorted by ordered run-side detection
IDs before union operations. Components are ordered by their smallest global
detection ID, making the result independent of candidate query or insert order.

Every detection in either analysis input belongs to exactly one group. An
isolated vertex is an explicit single-member `unmatched` group. The stable key
is `run_a:[ordered IDs]|run_b:[ordered IDs]`; it and the member counts are
stored in `match_groups.notes`. Database row IDs are storage identities, while
ordered membership is the scientific rerun identity.

Topology comes only from member counts on the explicitly ordered run pair:

| Run A | Run B | `match_type` | `ambiguity_status` |
|---:|---:|---|---|
| 1 | 1 | `one_to_one` | `unambiguous` |
| 1 | N | `one_to_many` | `ambiguous` |
| N | 1 | `many_to_one` | `ambiguous` |
| N | M | `many_to_many` | `ambiguous` |
| one side only | 0 | `unmatched` | `unmatched` |

Split/merge labels are relative descriptions, not ground-truth claims.
`match_score` remains NULL because no component score is specified.

## Consensus policy

Consensus is gated by the checksum-bearing JSON specification:

| Topology | Emit | Boundary rule | Status |
|---|---|---|---|
| `one_to_one` | yes | mean member start and mean member end | `derived_unambiguous` |
| `one_to_many` | yes | minimum start through maximum end | `derived_ambiguity_preserving` |
| `many_to_one` | yes | minimum start through maximum end | `derived_ambiguity_preserving` |
| `many_to_many` | no | none | none |
| `unmatched` | no | none | none |

Stored methods are `mean_boundary_of_members` and
`union_boundary_of_members`. Each consensus event links to its group and repeats
exactly that group's detection membership and run-side roles. Confidence stays
NULL because this pass defines no calibrated confidence model.

## Apply, legacy completion, and reruns

For a new analysis, one transaction writes provenance, candidates, groups,
members, consensus events, and consensus members before marking the analysis
complete. A failure rolls back the entire graph.

Pass 2 could leave a completed candidate-only analysis. With the same run key,
ordered inputs, specification checksum, and exact candidates, apply appends the
derived graph atomically without deleting or rewriting candidate evidence. The
parent remains completed during that private transaction because no partial
graph is externally visible; its completion timestamp is refreshed only after
all derived rows succeed. Failure restores the original completed,
candidate-only state.

An exact full rerun reuses stored IDs and writes nothing. Any partial or
differing membership, topology, status, method, interval, or lineage is a
pre-write conflict. Schema triggers enforce analysis-input scope,
one-group-per-analysis partitioning, consensus/group scope, and consensus
membership containment.

## Current boundary

This pass stops at assignment and consensus lineage. It creates no
`consilience_assessments` or `agreement_statistics`, performs no feature joins,
treats neither extractor as ground truth, and never overwrites native timing.
