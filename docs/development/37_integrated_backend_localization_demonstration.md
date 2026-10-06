# Integrated backend/localization demonstration

[`examples/backend_localization_demo.m`](../../examples/backend_localization_demo.m)
exercises the whole Phase 5 backend/localization path as one synthetic workflow:
a localization backend's export on the backend's own clock, previewed and then
imported through a versioned `attribution_backend_mapping` profile; a fitted
piecewise-affine transform relating that clock to the recording's;
correspondence across it; explicit promotion of the backend's caller scores into
candidates and of a localization estimate, a per-channel value and a track
reference into evidence; all five evidence dimensions on one candidate; a
decision for every status; and one read-only report. A second, structurally
different backend is then imported over the same recording and read back through
the same function.

It is the cross-module proof for Phase 5. Every capability it claims is asserted
by
[`tests/integration/test_backend_localization_demonstration.m`](../../tests/integration/test_backend_localization_demonstration.m).

The example estimates no caller, computes no distance, transforms no frame,
combines no evidence dimensions, and promotes nothing implicitly. What it
decides, it decides from the backend's own scores, under a policy it declared,
after promoting them by its own explicit rule.

## What the workflow covers

| Step | Public API |
| --- | --- |
| Declare the frames: shared 2D, a 3D one, another project's | `vawlume.geometry.registerCoordinateSystem` |
| Establish the recording's channels | `vawlume.geometry.registerRecordingChannel` |
| Register the run's settings profile | `vawlume.db.registerProfileVersion` |
| Register the backend clock and its anchors; fit the transform | `vawlume.ingest.alignment`, `vawlume.alignment.fit`, `vawlume.alignment.report` |
| Register the tracking stream and the identity association the backend refers to | `vawlume.tracking.register`, `registerIdentityAssociation` |
| Create backend runs | `vawlume.attribution.createRun` (`attribution_path="backend"`) |
| Preview, then import, the backend export | `vawlume.ingest.backendAttribution` |
| Relate backend windows to VAWLUME events | `vawlume.attribution.correspondWindows` (`AlignmentRun`; `SameClock` for the second backend) |
| Promote backend claims into candidates | `vawlume.attribution.addCandidates` |
| Promote an estimate, a channel value and a track reference into evidence; add temporal and pose evidence | `vawlume.attribution.addEvidence` |
| Apply a declared policy | `vawlume.attribution.decide` |
| Read both runs back | `vawlume.attribution.report` |

## The synthetic session

One recording (`REC_BACKEND_01`) with two channels and six detections `c01`–`c06`.
Entities A, B and C participate; D exists in the project but was not recorded.
A second project owns `other_lab_arena`, a 2D centimetre frame, which this
session must not use. The tracker and the caller-scoring backend share
`arena_2d`; the array backend reports in `arena_3d` (millimetres).

Seeded directly: the projects, the recording, the entities and their links, and
the extraction run and its detections. Each has its own demonstration. Every
Phase 5 object is created through a public function.

## The backend export, on its own clock

The export's times are the events' recording-clock times expressed in backend
seconds under the fitted transform, hand-authored rather than computed: the
example performs no transform arithmetic. Windows `b1`–`b5` cover `c01`–`c05`.
`c06` has no backend window, which is what makes it the target with no
candidates. Row `b9` ends before it starts. The dry run reports it with its row
number and writes nothing, and the apply imports the rest.

| Window | Callers and scores | Estimate | Decision |
|---|---|---|---|
| `b1` | A 0.95, B 0.10 | (10.5, 20.25) cm, confidence 0.9; A tied to `track_a`; channel powers | assigned |
| `b2` | A 0.85, B 0.80 | (30, 40), 0.7 | simultaneous |
| `b3` | A 0.60, B 0.55 | (50, 60), **no confidence** | ambiguous |
| `b4` | A 0.30, B 0.20 | (70, 10), 0.4 | unassigned |
| `b5` | A, **no score** | (80, 15), 0.5 | excluded (the policy cannot apply) |

The profile declares that the backend used acoustic and pose evidence and not
visual identity, and **leaves temporal alignment undeclared**, so the read-back
shows three declarations and one unknown.

## Five dimensions on one candidate, none combined

Candidate A on `c01` carries one row per dimension:

| Dimension | Where it came from | What is stored on the row |
|---|---|---|
| `temporal_alignment` | the fitted alignment run | 0.002 s, its semantics, the alignment run |
| `pose_localization` | the tracker | 0.73 keypoint confidence: where a bodypart is |
| `visual_identity` | the identity association `track_a` → A (the backend's track reference) | 0.55 similarity, the association id |
| `acoustic` | the backend's folded `channel:1:backend_channel_power` | −41.25 dB, its semantics, **`recording_channel_id` (mic_left)** |
| `source_localization` | the backend's estimate for `b1` | **no value of its own**: it cites the estimate, whose frame (`arena_2d`), position and confidence the read-back shows |

The sound-source position and the snout's pose confidence sit on one candidate as
different dimensions, with different units and different semantics.

## The second backend

The 3D array template is imported over the same recording, on the recording's
clock, re-using `c01` as its event reference. It reports two ranked sources
(z = 15 and 12 mm), covariance terms as estimate-owned native attributes, and no
scalar confidence. `report` returns the same fields for both runs, and the
localization QC is one row per frame, never pooled.

## Refusals, beside the successes

Captured by a harness that **fails the example if any of them stops refusing**:

| Attempted | Refused as |
|---|---|
| an export whose positions name another project's frame | `vawlume:attribution:LocalizationFrameScopeMismatch` |
| a caller label declared to be D, who was not in the recording | `vawlume:attribution:CallerLabelUnresolved` |
| a second apply of the same export | `vawlume:attribution:ImportAlreadyApplied` |
| a correspondence with no clock declaration | `vawlume:attribution:ClockRelationUndeclared` |
| source-localization evidence citing an estimate without declaring its frame | `vawlume:attribution:LocalizationFrameRequired` |

## Grain, stated beside every count

The printed read-back puts each table's grain beside its row count, now including
`localization_estimates` (backend-window grain), `native_attributes` (owner,
name) and `declared_inputs` (run, upstream input). The native-attribute count is
dominated by channel values, which are folded at window grain with a companion
semantics row each.

## Boundaries the example does not cross

No distance, angle or frame transformation. No combination of evidence
dimensions. No caller estimate. No candidate or evidence created by intake or
correspondence. No comparison between the two backends' results (Phase 7).

## What the demonstration could not show

Each item is covered elsewhere or is a known limit. They are the places a sweep
should look first.

- **A backend window that crosses the clock breakpoint, or is extrapolated.**
  Every backend window lies inside one segment and inside the anchored range. The
  Phase 4 demonstration shows both for imported windows; no backend-specific
  path differs, but it is not shown here.
- **A backend window corresponding to two events, or to none.** Every window here
  corresponds to exactly one event (covered by
  `test_backend_attribution_path.m`).
- **Two localized sources for one call, each tied to its caller.** The main
  backend attaches estimates to windows, so the ambiguous call has one estimate.
  The claim-attached case is `test_backend_attribution_path.m`'s.
- **A cross-frame refusal at promotion.** The refusals shown are at intake and for
  a missing frame. A declared frame differing from the estimate's
  (`vawlume:geometry:CoordinateSystemMismatch`) is covered by
  `test_localization_evidence.m`.
- **Choosing an identity association by time.** The track reference resolves to
  the one association that exists. With several time-varying associations for a
  track, the example would have to choose one through declared alignment, and no
  helper does that.
- **A completed backend run.** `c06` has no candidates and is not decided, so the
  run stays `planned`. Completion and the evidence freeze over a backend run are
  in `test_backend_attribution_path.m`.
- **Consensus-event or agreement-group targets for a backend run.** Only detection
  targets are used. Nothing in the backend path is target-kind specific, but it is
  not shown.
- **Raw window inspection.** `report` has no standalone windows table, so the
  windows are visible only through their claims, estimates, native fields and
  correspondences.
- **Any use of the declared inputs.** They are stored and read back; nothing
  consumes them yet. That consumer is Phase 7's comparison.
- **A real backend.** Both exports are invented, and so is every number.

## Validation limitation

Everything here is synthetic and written by this repository to exercise a branch.
The demonstration proves the path composes, refuses correctly and reads back
coherently. It proves nothing about any real localization backend's format,
accuracy or calibration, and nothing about who called.

## See also

- [`../design/05_backend_localization_contract.md`](../design/05_backend_localization_contract.md) — the decisions
- [`36_backend_attribution_intake.md`](36_backend_attribution_intake.md) — the adapter contract and what cannot be held
- [`31_caller_attribution_schema.md`](31_caller_attribution_schema.md) — the tables
- [`34_integrated_caller_attribution_demonstration.md`](34_integrated_caller_attribution_demonstration.md) — the Phase 4 demonstration this one follows
