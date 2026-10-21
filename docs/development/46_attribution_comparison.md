# 46. Comparing attribution runs

`vawlume.attribution.compare` reads two stored attribution runs and reports,
target by target, where they agree and where they differ. Built at itinerary
7.6 for runs over **one recording and one event set**. 7.7 extends the same
function across event sets through a named correspondence analysis. Contract
07 D1, D3–D5 is the design. This document records what was built.

```matlab
result = vawlume.attribution.compare(conn, leftRunRef, rightRunRef, ...
    LeftPolicy=..., RightPolicy=..., CompareScores=false)
```

## What it is not

- **Not a combination.** It does not produce:
  - a merged caller;
  - a consensus decision;
  - a combined score;
  - a preferred run;
  - an agreement percentage.

  A guard test fails if any output name is outside the closed vocabulary, or
  matches `best|winner|combined|consensus|overall|optimal|composite|agreement_score|preferred`.
- **Not a writer.** It reads each run through `vawlume.attribution.report`. The
  only other read is each side's registered decision-policy row, used to re-read
  the policy file while it matches its checksum. A test shows that
  `PRAGMA data_version` and `total_changes()` are unchanged across calls. A
  static guard finds no SQL write, and no call to a producer or to `decide`, in
  `compare.m` or its helper.
- **Not evidence of accuracy.** Two runs agreeing on data this repository
  generated is circular: it shows that the machinery joins. On any data,
  agreement says nothing about who called without independent ground truth.

## Refusals, before any table is built

| Situation | Identifier |
|---|---|
| The runs are on different recordings | `vawlume:attribution:ComparisonRecordingMismatch` |
| The runs target different event sets (different extractors, detections against consensus events, other configurations) | `vawlume:attribution:CorrespondenceAnalysisRequired`. The message points to the `Correspondence` option (7.7) |
| A side has decisions under several policy versions and none is named | `vawlume:attribution:DecisionPolicyRequired` |
| A named policy decided nothing on that side | `vawlume:attribution:DecisionPolicyNotFound` |
| `CompareScores=true`, but the scores are not on one scale | `vawlume:attribution:ScoreNotComparable` |

"One event set" is the run provenance's `target_kind`, `target_source_kind`
and `target_source_id`. Targets of the two runs meet on their stored event id
(`report.targets`' `detection_id`, `consensus_event_id` or
`agreement_group_id`, plus `agreement_extent_method`). Those columns were added
at 7.5a so that this join needs no SQL of its own.

**Scores are on one scale** only when the attribution path, the method string
(which names its version) and the settings-profile version all match. The
recording already matches. Otherwise every unit states
`score_comparability = not_comparable:<reason>`, with the reason
`producer_scale`, `method` or `settings_profile_version`. Ranks, selected sets
and statuses are still compared.

## The per-unit table (`units`)

There is one row per event, ordered by event kind, event id and extent basis.
`unit_id` numbers the rows in that order.

| Column | Values |
|---|---|
| `correspondence_unit` | `one_to_one` when both runs target the event; `unmatched_left` / `unmatched_right` when only one does; across event sets also `one_to_many`, `many_to_one`, `many_to_many` (below) |
| `event_kind`, `event_id`, `agreement_extent_method` | The shared event |
| `left_target_ids`, `right_target_ids` | Every stored target id (cells) |
| `top_entity_agreement` | `same`, `different`, `tie_left`, `tie_right`, `left_unscored`, `right_unscored`, `both_unscored`, `orientation_unknown`, `not_applicable_unit` |
| `selected_set_relation` | `equal`, `disjoint`, `subset`, `superset`, `overlap`, `left_empty`, `right_empty`, `both_empty`, `not_applicable_unit` |
| `left_decision_status`, `right_decision_status` | The stored status under the side's policy, or `no_decision`; `no_counterpart` for the side an unmatched unit lacks; `not_applicable_unit` for a side with several targets |
| `left_declared_<dim>`, `right_declared_<dim>` | `used`, `not_used` or `unknown`. No declaration row is `unknown`, never `not_used`. An imported run is `unknown` on all four dimensions |
| `score_comparability` | `comparable`, or `not_comparable:<reason>` |

**Top entity.**

- Its basis is the side's decision policy: its `reads` column, ordered
  `higher_is_stronger`.
- Without a decision set, the basis is `candidate_rank`, when every candidate
  of the target carries one. Otherwise the target is `orientation_unknown`.
- Several candidates sharing the top value form a **tie**; none is picked.
- Precedence: `orientation_unknown`, then the unscored values, then `tie_left`,
  then `tie_right`.

The basis each side used is in `sides.rank_basis`.

**Pairs.** `pairs` has the per-target columns with a `unit_id`. It holds one
row per (left, right) target pair of a unit with several targets on a side, and
one row per target of an unmatched unit, against `no_counterpart`. It is never
promoted to unit agreement.

## Decision statuses (`status_crosstab`, `status_counts`)

Every (left status, right status) cell over `one_to_one` units carries a count
and a `cell_kind`. The first rule that applies decides the kind:

1. **`structural_empty`:** one side's decision rule cannot produce that status.
   The statuses each rule can produce come from the policy loader, beside its
   rule dispatch (`threshold_with_separation` cannot say `simultaneous`). They
   are never a list of paths. Imported `simultaneous` against a native
   `ambiguous` is structural, not a disagreement. Against backend, whose rule
   can say `simultaneous`, the same pair is a disagreement.
2. **`undecided`:** `no_decision` on a side.
3. **`excluded`:** `excluded` on a side. The policy could not be applied, or a
   QC exclusion was declared. That says nothing was decided, not who called.
4. **`agree`** or **`disagree`**.

Only `agree` and `disagree` are agreement or disagreement. `status_counts` gives
each kind's count beside the `one_to_one` denominator, with no percentage.

The status cross-tab compares statuses, not callers. Two `assigned` decisions
that selected different animals agree in the cross-tab and disagree in the unit
row (`different`, `disjoint`). Both are reported.

## Reasons, windows and claims

- **`reasons`:** per side, each unscored candidate's stored reasons in order
  (`unscored_candidate`), and each excluded decision's reason
  (`excluded_decision`).
- **`windows`:** per side, every imported or backend window. Each is
  `corresponded` or `uncorresponded` and none is dropped. Each lists the
  targets its stored correspondences reach.
- **`claims`:** per side, every window claim. A claim is `promoted` when its
  entity is a candidate on a target its window corresponds to. An unpromoted
  claim is never compared as a candidate.
- **`claim_counts`:** per side, `claims_promoted`, `claims_not_promoted` and
  `windows_uncorresponded`.

## Scores (`CompareScores=true`)

For each `one_to_one` unit, each within-unit pair, and each entity, `scores`
gives the target ids and each side's stored score and semantics side by side. There is no difference column. It is allowed only
when `score_comparability` is `comparable`.

## Across event sets (`Correspondence=`, itinerary 7.7)

```matlab
result = vawlume.attribution.compare(conn, dsRunRef, mupetRunRef, ...
    Correspondence=struct(analysis_run_id=dsMupetAnalysisId))   % or struct(run_key=...)
```

**The join is the stored one.** One named analysis supplies it, and no
"latest analysis" is ever assumed:

| Left / right | Analysis | Stored rows |
|---|---|---|
| detections / detections | `cross_extractor_matching` | `match_group_members` |
| detections / detections | `multi_extractor_agreement` | `agreement_group_members` (restricted to the two runs' targets) |
| detections / consensus events | the `cross_extractor_matching` analysis that produced the consensus events | `consensus_event_members` |
| detections / agreement groups | that `multi_extractor_agreement` analysis | `agreement_group_members` |
| consensus events of matching analysis P / of matching analysis Q (7.9) | none named: `Correspondence=struct(shared_member_detections=true)`. The two analyses are the runs' own target sources, and must be complete and over the same extraction runs | both analyses' `consensus_event_members`, joined on shared member detections |

**A unit** is one connected component of those rows, restricted to the two
runs' targets. Its type is decided by counting its targets on each side:

- `one_to_one`;
- `one_to_many`: the right side has several, a right-side split;
- `many_to_one`;
- `many_to_many`;
- `unmatched_left` / `unmatched_right`: a target in no stored group with a
  counterpart.

Units are ordered by smallest left, then smallest right target id. Their
`event_kind` is `correspondence_component`.

**Within a unit, nothing is picked.**

- A `one_to_one` unit is compared like a same-set target.
- A unit with several targets on a side keeps `not_applicable_unit` in `units`.
  Every (left, right) target pair is reported in `pairs` and is never promoted.
- An unmatched target's own decision is reported against `no_counterpart`, in
  `units` and in `pairs`. It is neither a disagreement nor dropped.
- The status cross-tab counts only `one_to_one` units.

**Values.** Native runs over two event sets of one recording, under one
settings version, are `comparable`. `correspondence.value_note` says that the
two targets are different measured windows of the same call.

**Refused by name:**

- `CorrespondenceAnalysisRequired`: different event sets and no analysis named.
- `CorrespondenceAnalysisInvalid`: any of these:
  - a missing analysis, or one of another project;
  - an analysis that is not complete, or of another kind;
  - an analysis that does not take both runs' event sets as inputs or
    outputs;
  - an analysis with no rows on the recording;
  - an analysis named for one event set;
  - shared member detections asked of sides that are not both consensus events,
    or of analyses over different extraction runs.

**Proof that the join is stored.** On the 7.3 fixture:

- the split, merge and miss scenes give `one_to_many`, `many_to_one` and
  `unmatched_left`, as the manifest says;
- for all three pairwise analyses and the agreement analysis, the units equal
  components computed independently from SQL;
- a second DeepSqueak–MUPET analysis under `min_temporal_iou = 0.9` stores
  different groups, and the units change exactly as the rows do. The split
  becomes unmatched on both sides.

A static guard finds no `+matching`, `+agreement`, `+consilience` or
`+interval` call, no interval field (`start_time`, `end_time`, overlap, IoU) and
no SQL write in `compare` or its two helpers. It fails on an injected planner
call and on injected overlap arithmetic.

## Comparing a variant with its reference (for 7.8)

A variant differs from its reference in one declared handle, on the same
recording and event set, so every column is defined. Which columns carry
meaning depends on the handle:

- **A decision-policy variant** is a second decision set on the **same** run.
  Compare the run with itself, naming `LeftPolicy` and `RightPolicy`:
  - candidates, scores and ranks are identical by construction;
  - `left_decision_status`, `right_decision_status`, `selected_set_relation`
    and the cross-tab carry the movement;
  - `top_entity_agreement` moves only if the two policies read different
    columns.
- **An estimator-settings variant** is a new run under another settings
  version:
  - `score_comparability` is `not_comparable:settings_profile_version`, so
    `CompareScores=true` is refused;
  - ranks, sets, statuses and the reasons table carry the movement;
  - declared inputs move only if the settings declare differently.
- **A variant under the same method and settings version** (for example one
  that changes only an input run, such as an alignment fit) is a new run:
  - scores are `comparable`, and `CompareScores=true` shows the values side by
    side;
  - reasons show which obstacle moved (for example `alignment_extrapolated`).
- **A variant that changes a settings parameter** (a normalization policy
  named in the settings, for example) is a settings variant (see above).
