# Integrated caller-attribution demonstration

[`examples/caller_attribution_demo.m`](../../examples/caller_attribution_demo.m)
exercises the whole Phase 4 caller-attribution path as one synthetic workflow:
an attribution run over an explicit event set, an external attribution export
imported through a versioned mapping profile, a piecewise-affine transform
relating the exporting system's clock to the recording's, correspondence across
that transform, several candidate callers per target, evidence in four
dimensions, decisions under two policies, and one read-only report of the whole
run. It then does the representation again over VAWLUME consensus events, so
both implemented target kinds are shown.

It is the cross-module proof for the phase. Every capability it claims is
asserted by
[`tests/integration/test_caller_attribution_demonstration.m`](../../tests/integration/test_caller_attribution_demonstration.m),
so the numbers the example prints are checked rather than merely observed.

The example estimates no caller. It computes no score from evidence, derives no
probability, combines no two uncertainty dimensions, and promotes no imported
claim into a candidate. What it decides, it decides from candidate values you
supplied under a policy you declared.

## What the workflow covers

| Step | Public API |
| --- | --- |
| Establish the recording's channels | `vawlume.geometry.registerRecordingChannel` |
| Derive consensus events to attribute to | `vawlume.matching.compare` |
| Register the exporter clock and its anchors | `vawlume.ingest.alignment` |
| Fit the piecewise-affine transform | `vawlume.alignment.fit`, `vawlume.alignment.report` |
| Register the identity statement evidence will cite | `vawlume.tracking.register`, `registerIdentityAssociation` |
| Plan and create the attribution run | `vawlume.attribution.createRun` |
| Verify the stored event set | `vawlume.attribution.resolveTargets` |
| Preview, then import, the external export | `vawlume.ingest.attribution` |
| Relate imported windows to VAWLUME events | `vawlume.attribution.correspondWindows` |
| Show one window crossing a breakpoint | `vawlume.alignment.applyTransformInterval` |
| Append several candidate callers per target | `vawlume.attribution.addCandidates` |
| Append four separate evidence dimensions | `vawlume.attribution.addEvidence` |
| Apply a declared policy, twice | `vawlume.attribution.decide` |
| Read the whole run back | `vawlume.attribution.report` |

Some setup is written as direct SQL rather than through a public function, and
the example says so where it does it:

- the project, source files, recording, entities, participant links, two
  extraction runs and their detections, because project intake and extractor
  import are already demonstrated by `project_intake_demo` and the three
  importers, and repeating them here would bury the path this example exists to
  show;
- **one `config_profiles` / `config_profile_versions` pair.** This one is a real
  gap rather than a deliberate omission: `createRun` requires a checksum-bearing
  settings-profile version and no public function registers an analysis-settings
  profile. A user following the usage guide has to write those two rows by hand
  too.

## The synthetic session

One 120 s recording with two channels and three participating entities, `A`, `B`
and `C`.

| Object | Extent on the recording clock | Role |
| --- | --- | --- |
| `c01` | `[10.00, 10.30]` | three candidate callers; the four evidence dimensions |
| `c02` | `[10.40, 10.62]` | **no candidates**; the second half of the ambiguous window |
| `c03` | `[20.00, 20.25]` | `simultaneous` |
| `c04` | `[30.00, 30.20]` | `ambiguous` |
| `c05` | `[40.00, 40.35]` | `unassigned`; reached by the window crossing the breakpoint |
| `c06` | `[50.00, 50.30]` | `excluded` by a caller-declared QC reason |
| `c07` | `[60.00, 60.20]` | `assigned`; reached by the window with an extrapolated endpoint |

A second extraction run supplies three near-coincident detections, so
`vawlume.matching.compare` derives consensus events rather than the example
declaring any.

## Two clocks, and why the transform is fitted rather than written

The exporting system's clock runs on its own piecewise-affine relationship to the
recording's:

```text
t_recording = 1.002 * t_exporter + 5.00      for t_exporter <  35
t_recording = 0.998 * t_exporter + 5.14      for t_exporter >= 35
```

Six anchors are declared at exporter times `5, 15, 25, 35, 45, 55`, the segments
are continuous at the breakpoint, and the fit recovers both scales to within
`1e-12` and both offsets to within `1e-9`.

The transform is fitted through `vawlume.alignment.fit` rather than inserted,
because the claim this example makes about clocks is that **attribution reaches
them through one shared API and adds no correction of its own**. Nothing in
`+attribution/` reads `alignment_segments`; `correspondWindows` calls
`vawlume.alignment.applyTransformInterval` and stores what it returns.

Two consequences are shown directly:

- **Aligned duration is not native duration.** The window at
  `[34.90, 35.30]` spans the breakpoint. Its native duration is 0.4000 s and its
  aligned duration is 0.3996 s, and the correspondence records the aligned
  interval because that is the one comparable to a detection.
- **An extrapolated endpoint survives into storage.** The anchored source range
  ends at exporter time 55, and one window ends at 55.15. Its stored
  correspondence carries `end_extrapolated = 1`. Dropping the flag after using
  the number would hide that the correspondence rests on a time no anchor
  constrains.

## The import, and what it refuses

The export is a long table — one row per (window, claimed caller) — carrying ten
source rows. The dry run writes nothing and reports what it read:

| Outcome | Rows |
| --- | --- |
| mapped into claims | 8, over 7 windows |
| reported as issues | 2 |

The two issues are a window whose end precedes its start
(`ATTRIBUTION_WINDOW_REVERSED`) and a caller label the profile does not declare
(`ATTRIBUTION_CALLER_LABEL_UNDECLARED`). Both name the source row. A preview that
hid what it could not read would be worse than one that read nothing.

One window carries two callers, so it becomes **one window and two claims**, not
one claim with the labels run together. One claim carries no score and no
probability, and both columns stay NULL: turning a name into certainty is the
specific failure the writer refuses.

`caller_export_rejected.csv` exists to be refused. It claims a caller `D`, a
label the demonstration's profile does declare — the exporting system knows that
animal — but which resolves to no participating entity of this recording. The
import raises `vawlume:attribution:CallerLabelUnresolved`, names `D`, and writes
nothing. An undeclared label is a row issue; a declared label pointing outside
the run's participants is a refusal, because the second means the file and the
session disagree about who was there.

## Correspondence, and the ambiguity it keeps

Seven imported windows produce seven correspondences over six of them:

| Window | Corresponds to | Note |
| --- | --- | --- |
| `w1` | `c01` **and** `c02` | one window, two plausible events, both stored |
| `w2`–`w5` | one detection each | `w4` crosses the breakpoint |
| `w6` | `c07` | `end_extrapolated = 1` |
| `w7` | nothing | counted in `windows_without_correspondence` |

Nothing chooses between `c01` and `c02`. The two correspondences carry different
IoUs and no field in any returned table marks either as preferred; the count of
such windows is reported and the resolution is left to a reviewer, who is the
only one who can weigh it.

`w7` corresponding to nothing is a finding, not a failure. It may mean the
exporter windowed something VAWLUME's extractors did not detect, or it may mean
the exporter produced a window over nothing. The demonstration counts it and
declines to say which.

## The decision layer, shown twice

Five statuses exist and all five appear:

| Target | Candidate scores | Status | Why |
| --- | --- | --- | --- |
| `c01` | 0.92, 0.40, 0.20 | `assigned` | one candidate, nothing close to it |
| `c03` | 0.88, 0.82 | `simultaneous` | two contenders, each independently strong |
| `c04` | 0.62, 0.58 | `ambiguous` | two contenders, neither independently strong |
| `c05` | 0.31, 0.22 | `unassigned` | the rule ran and nothing was supportable |
| `c06` | 0.77, 0.30 | `excluded` | a caller declared a QC reason |

**`ambiguous` and `simultaneous` are opposite claims, not degrees of one.** Both
leave several contenders standing. `simultaneous` selects all of them and says
more than one animal called — a claim about the world. `ambiguous` selects none
and says the evidence cannot separate them — a claim about the evidence.

`c02` has no candidates and is therefore not decided at all: a target with no
candidates is an unfinished analysis, not an outcome, and `decide` refuses it
rather than reporting absence of evidence as evidence of absence. It appears in
`qc.targets_without_candidate` with enough identity to go and look.

The same six targets are then decided again under a policy with a lower selection
threshold, a narrower separation margin, and a higher co-occurrence threshold.
Three statuses move — `simultaneous` becomes `assigned`, `unassigned` becomes
`assigned`, and the excluded target is decided because the second call declares
no exclusion — and **every candidate row is byte-identical afterwards**. Both
decisions remain readable, one per (target, policy version), each naming the
policy and the threshold that bound it. That is the whole point of a decision
never being rewritten in place.

The candidate set on `c07` includes one entity with a label and no score. The
policy ignores it for ranking and reports `readable_count` below the candidate
count. It is not treated as zero and not treated as one.

## Four dimensions, none combined

One candidate carries evidence in all four:

| Dimension | Kind | Value | Units |
| --- | --- | --- | --- |
| `temporal_alignment` | `propagated_bound` | 0.0020 | s |
| `pose_localization` | `keypoint_confidence` | 0.7300 | upstream score |
| `visual_identity` | `reidentification_similarity` | 0.5500 | cosine similarity |
| `acoustic` | `channel_rms_ratio` | 0.4200 | ratio |

Four numbers, four scales, four meanings. No row spans two dimensions,
`qc.evidence_by_dimension` has no total and no coverage fraction, and no returned
field is a function of more than one of them. The integration test asserts this
as a name scan over every table the demonstration displays, so a combining field
added later fails a test rather than passing unnoticed.

Each row also says where its number came from, **relationally wherever the schema
has a link**:

| Dimension | Points at | Kind |
| --- | --- | --- |
| `temporal_alignment` | `time_alignment_runs` | relational (`alignment_run_id`) |
| `pose_localization` | `tracking.csv#time=10.0` | locator string |
| `visual_identity` | `tracking_identity_associations` | relational |
| `acoustic` | `source_files` | relational (`source_file_id`) |

Pose confidence is the one that cannot cite a row, and the reason is by design: a
tracking sample is a line in an external artifact, not a row in this database.
The locator is the honest form of that pointer, not a shortcut.

The `visual_identity` row additionally declares **which kind of statement** it
read, through `identity_statement_kind`. The storage layer refuses a bare
identity number: identity evidence that cannot say which statement it rests on is
not identity evidence, and a declared entity link and an inferred association are
different strengths of claim.

The correspondence layer writes its own `correspondence`-dimension evidence at
target level, which is why `evidence_by_dimension` shows five dimensions rather
than four. It is a fifth kind of evidence, not a combination of the other four.

## Refusals, beside the successes

The Phase 3 demonstration's most useful single element was a source clock that
failed with a named reason beside two that succeeded. These are this phase's:

| Attempted | Identifier |
| --- | --- |
| an imported label naming an animal not in this recording | `vawlume:attribution:CallerLabelUnresolved` |
| a correspondence that did not say how the two clocks relate | `vawlume:attribution:ClockRelationUndeclared` |
| a second correspondence apply over the same run | `vawlume:attribution:CorrespondenceAlreadyApplied` |
| a candidate appended after the run's evidence was frozen | `vawlume:attribution:RunNotWritable` |

The second is the one worth dwelling on. `correspondWindows` requires either
`AlignmentRun` or `SameClock` and offers no default, because a correspondence
computed on incomparable clocks is a plausible number and a wrong one: the IoU
looks ordinary, the row stores cleanly, and the error surfaces much later as a
caller attributed to the wrong call.

## Grain, stated beside every count

The demonstration prints what each returned table counts, because confusing the
grains is the easiest available mistake:

| Table | One row per | In this run |
| --- | --- | --- |
| `targets` | attribution target | 7 |
| `candidates` | (target, candidate entity) | 14 |
| `evidence` | stored evidence record | 11 |
| `imported_claims` | (imported window, claimed caller) | 8 |
| `correspondences` | stored correspondence | 7 |
| `claim_correspondences` | (claim, correspondence) | 8 |
| `decisions` | (target, policy version) | 12 |
| `decision_selections` | candidate a decision selected | 9 |

`claim_correspondences` is the trap, and this run contains both ways to fall into
it: `w2` carries two claims over one correspondence, and `w1` carries one claim
over two correspondences. Both multiplicities are real and neither is collapsed —
but correspondences are counted from `correspondences`, and QC does exactly that.

## Boundaries the example does not cross

- No caller is estimated. The only implemented path is the imported one.
- No imported claim becomes a candidate. The candidate set is authored
  independently, and `c02` proves it: that target is reached by a corresponded
  claim and still has no candidate.
- No evidence dimension is combined with another, and the decision policy reads
  one candidate column and no evidence row.
- No imported number is rescaled, renormalized, clamped, or promoted from a score
  to a probability.
- No caller label becomes an entity, and no entity is created to accommodate one.
- No correspondence resolves an ambiguity; it counts them.
- No status means `validated`, and no threshold anywhere in the path is
  calibrated.
- `attribution_path` values `backend` and `native_estimate` are never written.

## What the demonstration could not show

- **Agreement-group targets, and therefore a multi-basis run.** Both are
  implemented and covered by `test_attribution_report`, but showing them here
  would have needed an arbitrary-N agreement run over the same recording on top
  of everything else. The consequence is that `qc.correspondence_by_basis` prints
  one row with an empty `target_extent_basis`, so the demonstration states that
  scores are summarized per basis pair without showing two bases side by side.
- **An empty agreement extent**, for the same reason — the case where members do
  not all overlap and a target simply produces nothing.
- **Realistic scale.** Seven targets, fourteen candidates and eight claims. The
  example says nothing about whether `report` is usable over a session with
  thousands of claim-correspondence rows, because it fetches every row of every
  table with no paging or filtering.
- **A real exporting system.** Every number in the export was written by this
  example to exercise a branch.

## Validation limitation

Everything here is synthetic. The transform recovers its parameters exactly
because the anchors were generated from them, which says nothing about real
acquisition hardware. Every threshold the example passes — the correspondence
floor, the selection threshold, the separation margin, the co-occurrence
threshold — is an illustrative demonstration value, not a calibrated
recommendation, and no decision the example produces is evidence that any animal
called.

## See also

- [`31_caller_attribution_schema.md`](31_caller_attribution_schema.md)
- [`32_imported_attribution_intake.md`](32_imported_attribution_intake.md)
- [`33_attribution_correspondence.md`](33_attribution_correspondence.md)
- [`13_transform_fitting_and_alignment_qc.md`](13_transform_fitting_and_alignment_qc.md)
- [`25_visual_identity_association.md`](25_visual_identity_association.md)
- [`29_integrated_multimodal_demonstration.md`](29_integrated_multimodal_demonstration.md)
- [`../design/04_caller_attribution_contract.md`](../design/04_caller_attribution_contract.md)
- [`../usage/01_prototype_usage_guide.md`](../usage/01_prototype_usage_guide.md) §7.7
