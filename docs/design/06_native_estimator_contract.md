# Native Estimator Contract

## Status

Design contract for **Phase 6: the VAWLUME-native low-tech estimator** (Path C).
Itinerary 6.1 wrote it before any Phase 6 code existed, so that the decisions
below are made once rather than negotiated by each later itinerary.

Written against schema `0.12-draft` (`PRAGMA user_version = 12`). Phase 6 plans
exactly one version bump, to `0.13-draft` (`PRAGMA user_version = 13`), owned by
itinerary 6.2 (D14). **Itinerary 6.2 applied it; the live schema is
`0.13-draft`.** The DDL realizing D2 and D13 is documented in
[`../development/31_caller_attribution_schema.md`](../development/31_caller_attribution_schema.md).

The contract clauses below are frozen as written. This status block is not. It
names the live schema and moves when the version moves, following the
precedent contracts 04 and 05 set. **Nothing machine-checks it**, because
`check_repository_self_description` exempts `docs/design/` from its version
check. The itinerary that bumps the schema moves this block by hand.

**Status at 6.11.** The live schema is still `0.13-draft`; 6.3–6.11 changed no
DDL. Itineraries 6.2–6.10 implemented the decisions below. Development docs 38–44
document each module, and 6.9a made a native run one transaction. Itinerary 6.11
added the integrated demonstration,
[`examples/native_estimator_demo.m`](../../examples/native_estimator_demo.m),
documented in
[`../development/45_integrated_native_estimator_demonstration.md`](../development/45_integrated_native_estimator_demonstration.md),
including what it could not show. That demonstration needed no new public
function, column or schema change. The phase's sweep and closure follow 6.11,
so this block does not yet say the phase is closed.

This contract **extends** [`04_caller_attribution_contract.md`](04_caller_attribution_contract.md)
and [`05_backend_localization_contract.md`](05_backend_localization_contract.md).
It replaces neither. Every Phase 4 and Phase 5 clause holds for a native run
unless a clause here says otherwise. Two clauses here do say otherwise, on
purpose: D3 lifts the prohibition on spatial arithmetic, and D7 lifts the
prohibition on combining evidence dimensions. Each names its single home and
its guard. Where this document departs from the recommendation in the 6.1
itinerary, the clause says so and gives the reason.

**The phase's one-sentence position:** VAWLUME can now produce its own caller
score for a two-animal, two-microphone recording. The score asks how well each
animal's position explains the level difference the two microphones heard. It is
stated in decibels, valid only within that recording, uncalibrated, and never a
probability. Every input it used is stored separately, and the score can be
recomputed from those stored inputs.

## What this phase is for

Phase 4 built the canonical attribution representation and proved it with
somebody else's claims. Phase 5 proved that a localization backend's output
lands in the same representation without a parallel model. Neither phase
computed anything about who called. The 5.11 closure handoff states the
remaining gap:

> `native_estimate` is representable in the schema but is not yet writable
> through `createRun`; the public API deliberately refuses it because no native
> estimator exists.

Phase 6 closes that gap for the motivating dyadic case in plan §11: two
microphones, raw audio, channel-response references, tracked positions,
microphone geometry and aligned clocks. The result lands through the same
`createRun`, `addCandidates`, `addEvidence`, `decide` and `report` that the
other two paths use.

What makes the phase different is not its size. **It is the first phase that
lifts refusals rather than adding them.** Phases 4 and 5 refused to compute a
distance and refused to combine evidence dimensions, each time because no
consumer existed to give the computation a meaning. Phase 6 is that consumer.
The contract's job is to make each opening exactly as wide as the estimator
needs, and no wider.

## Core vocabulary

These distinctions are the contract. Everything in the Decisions section follows
from them.

### A consistency score is not a likelihood

The native score answers one question: *if this animal were the source, how far
would the level difference the microphones heard be from what its position
predicts?* That is a discrepancy, measured in dB under a stated propagation
assumption. It is not a probability that the animal called, and it is not a
likelihood under any fitted noise model. Calling it either would give it a
meaning nothing has established (plan §11.6, §15.9).

### A distance is a derived fact in one frame

A distance is computed from two positions that cite **the same**
`coordinate_system_id`. It is reported in that frame's unit, verbatim, and its
basis (which instant, observed or interpolated) is always stated. Two positions
in different frames have no distance. VAWLUME still transforms nothing between
frames (`23_spatial_geometry_schema.md`).

### A normalized level is relative, and only within one recording

Dividing a call's level on a channel by that channel's own response to a
reference signal removes the relative gain difference between the channels, to
the extent the reference represents the call band. It yields no absolute level,
no hardware calibration, and nothing comparable with another recording, whose
reference, gains and geometry all differ.

### Unscored is not low-scored

A candidate the method could not evaluate (identity unresolved, tracking
uncovered, a channel clipped) has **no score**, with a stated reason. A low score
says the evidence argues against the animal. No score says the method could not
look. Writing a floor value would turn "could not look" into "looked and found
against", and that is the absence-as-evidence error every earlier phase refused.

### A resolution is a rule's choice; an association is evidence

`vawlume.tracking.resolveIdentity` records which stored claim a stated rule
selected. The stored `tracking_identity_associations` row is the evidence. A
native candidate's spatial evidence cites the association, and records which
rule step chose it (contract 04 D8, D9).

### Self-consistency is not accuracy

A synthetic recording whose channel levels were generated from the estimator's
own spreading assumption will be scored correctly. That shows the code computes
what the method says. It shows nothing about whether real animals in real arenas
behave that way. Every test, demonstration and handoff that uses such a scene
must call it self-consistency.

---

## Decisions

Itinerary 6.1 posed thirteen questions (Q1–Q13). D1–D14 answer them. D15–D17
answer questions the live repository raised that the itinerary did not pose.

| Itinerary question | Decision | Departs from recommendation? |
|---|---|---|
| Q1 estimator home and entry point | D1 | No. `+estimator/`, confirmed by the user before 6.1 |
| Q2 settings profile kind and required blocks | D2 | **Yes, in the name.** `attribution_estimator_settings`, not `attribution_estimator` |
| Q3 spatial arithmetic home, invariant 19 | D3 | **Yes, in mechanism.** `+geometry/`, with `assertCompatible`'s identity rule extracted so pure functions share it |
| Q4 instants, interpolation, gaps, pose confidence | D4 | No |
| Q5 clock path, temporal evidence, reference → native | D5 | No. Option (a), owned by 6.4 |
| Q6 call measurement and normalization | D6 | **Yes, in the band rule.** v1 uses an explicit band only, never the event's own bounds |
| Q7 combination method and score meaning | D7 | No |
| Q8 comparability scope | D8 | No |
| Q9 identity entry, marginalization | D9 | **Yes, partly.** One track per entity or no score; several tracks for one entity are not enumerated as separate pairings in v1 |
| Q10 native candidate set and evidence rows | D10 | No |
| Q11 decision rule and `simultaneous` | D11 | No. Option (a), plus a latent defect found and assigned |
| Q12 closure invariants | D12 | No |
| Q13 what rides the bump | D13, D14 | **Yes.** P4-3 rides with `ON DELETE RESTRICT`, not CASCADE. I-5 is re-deferred |
| (raised by the repository) canonical-layer admission ownership | D15 | — |
| (raised by the repository) where declared inputs are written | D16 | — |
| (raised by the repository) frame units and distance ratios | D17 | — |

The user settled four questions before 6.1 ran: **no real paired session is
available**, so Phase 6 is synthetic; **v1 is two animals and two microphones**;
**the estimator lives in `+estimator/`**; and **P4-3 rides the bump**. Thirteen
itineraries were kept.

### D1. The estimator is a producer in `+estimator/`, and attribution stays path-agnostic

A new package, `src/+vawlume/+estimator/`, plays the same role for the native
path that `+ingest/` plays for the imported and backend paths: **a producer that
writes through `+attribution/`'s public API**. It writes no SQL of its own.

Public functions:

| Function | Itinerary | What it is |
|---|---|---|
| `vawlume.estimator.loadSettings` | 6.8 | Reads and validates an estimator settings profile, and refuses one that omits any required block (D2) |
| `vawlume.estimator.levelDifferenceConsistency` | 6.8 | **The method.** Pure: values in, scores and reasons out (D7) |
| `vawlume.estimator.candidateGeometry` | 6.5 | Read-only: per participant, the identity-resolved track and its distances to the two placed channels (D9) |
| `vawlume.estimator.attributeCallers` | 6.9 | The entry point. Plans by default; `Apply=true` writes one native run atomically through the canonical API |

`attributeCallers(conn, recordingRef, runSpec, Apply=false)` follows the
repository's plan/apply convention: one function, read-only by default. Event →
reference-clock instants is a private helper in `+estimator/` (owned by 6.4),
because which instants a call is evaluated at is estimator policy.

**Rejected: a subpackage or functions inside `+attribution/`.** Phase 5
invariant 16 holds because `+attribution/` is the canonical layer every path
shares, and the backend producer lives in `+ingest/` for that reason. Putting a
producer in the consumer layer would make "nothing in `+attribution/` combines
dimensions" impossible to state, and that statement is how D7's opening is kept
narrow.

### D2. Estimator settings are a profile of kind `attribution_estimator_settings` that states the five conditions

A new `config_profiles.profile_kind` member, `attribution_estimator_settings`,
added by 6.2. The name follows `extractor_settings` and `analysis_settings`. It
is settings for a computation, not a mapping or a policy, which is why it is
not the itinerary's suggested `attribution_estimator`.

**Rejected: reusing `analysis_settings`.** That kind is generic. The response
aggregation policy uses it, and a loader could not tell an estimator profile
from any other analysis setting without inspecting content. Contract 05 D13
chose a new kind for the same reason.

The shipped profile lives at
`config/10_estimator_settings/native_level_difference_estimator_v1.json` (6.8).
`vawlume.estimator.loadSettings` **refuses** a profile missing any of these
blocks, by name:

| Block | Contents |
|---|---|
| `profile` | `id`, `name`, `kind`, `profile_schema_version`, `profile_version` |
| `method` | `key = vawlume.estimator.level_difference_consistency`, `version = 1.0.0` |
| `scope` | `candidate_count = 2`, `channel_count = 2`, `target_event_sets = [detections, consensus_events]` |
| `dimensions` | `used` or `not_used`, plus a one-sentence `role`, for **each** of `temporal_alignment`, `pose_localization`, `visual_identity`, `acoustic`; and `source_localization: not_used` with its reason. **Condition 1** |
| `score` | `unit = dB`, `orientation = higher_is_stronger`, `meaning`, `what_this_is_not` (first entry: not a probability). **Condition 2** |
| `scaling` | how each input is scaled, and `comparability_scope = within_recording` with its justification. **Condition 3** |
| `readability` | the evidence rows each input becomes, matching D10. **Condition 4** |
| `calibration_status` | `state = uncalibrated`, `evidence_basis`, `calibration_requires`. **Condition 5** |
| `parameters` | every method parameter (D4–D7, D17). **No parameter has a code default.** A missing parameter is refused, because a code default would be a second, unversioned copy of the method |

A profile whose `calibration_status.state` is `calibrated` is refused, as
`attributionLoadPolicy` refuses a calibrated decision policy.

### D3. Spatial arithmetic lives in `+geometry/`, and the guard becomes a package boundary

**Lifts the prohibition contract 05 D11 imposed.** That prohibition existed
because distance had no consumer. It now has one.

`+geometry/` already owns frames, placements and `assertCompatible`, so it
becomes the **only** package where spatial arithmetic may appear. That mirrors
`+alignment/` as the only home of transform arithmetic. The package that decides
whether two frames may be related is the only package that relates them, so a
distance cannot be computed without the compatibility check.

**Departure in mechanism.** The 6.3 itinerary asks for pure primitives that
refuse mismatched frames "through `assertCompatible`". `assertCompatible`
takes a connection, because it returns the frame row. Those two demands
conflict, and a second, local id comparison would be the duplicate rule doc 23
forbids. Resolution: **6.3 extracts `assertCompatible`'s identity comparison
into one private function in `+geometry/`**. `assertCompatible` and the pure
primitives both call it. `assertCompatible`'s behaviour stays bit-identical. The
identity rule then has one implementation, and the primitives stay pure.

Primitives (6.3), all pure:

| Function | Purpose |
|---|---|
| `vawlume.geometry.distance` | Euclidean distance between position sets, each carrying a frame descriptor (`coordinate_system_id`, `dimensionality`, `unit`), refusing different frames through the shared identity rule |
| `vawlume.geometry.positionAtInstants` | Position of one (track, bodypart) trace at query instants, under D4's policy |
| `vawlume.geometry.summarizeDistances` | Window summaries over a distance series, with coverage counts and an explicit empty state |

**Revised invariant 19, the sentence 6.13 verifies:**

> Spatial arithmetic (distance, norm, angle, and position interpolation) occurs
> only in `src/+vawlume/+geometry/`. A distance is computed only between
> positions whose frames pass the shared identity rule. No coordinate is
> transformed, rescaled or converted between frames anywhere in `src/`.

**The guard.** `testNoSourceComputesADistanceAngleOrTransform` in
`tests/integration/test_localization_evidence.m` becomes a **package
allow-list** for `+geometry/`. Every existing non-spatial exemption (RMS
amplitude, clock-fit RMSE, partial correlation) stays a per-line entry with its
reason, so none of them broadens into a package. F5.10-8 rides with it: string
literals are stripped before comments, and the pattern gains `cos`, `sin`, `tan`,
`deg2rad`, `rad2deg` and their degree variants, with word bounds that keep
`acos` and `cos` distinct. 6.3 makes the revision and injection-verifies it.

### D4. Every defensible instant is computed and labelled; interpolation is bounded and never extrapolates

**Instants.** For each target, positions are taken at the call's **onset**,
**midpoint** and **offset** on the reference clock, plus a **`window_median`**
distance over the samples observed inside the call window. Every evidence row
carries its basis. The method scores on one basis, which the profile declares in
`parameters.primary_instant_basis`. Distances on the other bases are still
written as evidence, so a later analysis can rescore on another basis without
re-reading tracking (plan §4.7, and its corollary that a consumer names the basis
it used).

**Interpolation**, in `vawlume.geometry.positionAtInstants`:

- an instant equal to a sample time returns that sample, basis `observed`;
- an instant between two samples **of the same trace**, whose gap is no more
  than `parameters.max_interpolation_gap_s`, is linearly interpolated, basis
  `interpolated`;
- a wider gap gives `not_covered` for every instant inside it;
- an instant before the first sample or after the last gives `not_covered`.
  **There is no extrapolation and no nearest-sample fallback**;
- input must be sorted by time with unique times. Unsorted or duplicate input is
  **refused**, not sorted, because a tracker that emitted it has a problem the
  caller should see;
- `window_median` uses observed samples only, never interpolated ones, and is
  `not_covered` over zero samples.

The gap is measured in **reference-clock seconds**, because the primitive
receives reference times (D5). It never sees a clock.

**Pose confidence** travels beside each position: both bracketing samples'
values, and their minimum, reported as `pose_confidence_min_bracket`. It is
never multiplied into a position. v1 records it as `pose_localization` evidence.
It is **not** used to gate or weight, because no pose-confidence scale is
established as comparable across trackers (contract 04 D9's refusal about
identity values applies equally here). The profile parameter
`pose_confidence_gate` exists and is `null` in the shipped profile. The
profile's `dimensions.pose_localization.role` says positions are used and
confidence is recorded, not used.

**The three coverage states** of `vawlume.tracking.readWindow` carry through
unchanged. `uncovered` and `covered`-but-empty are different states and give
different no-score reasons (D10).

### D5. Events reach the tracking clock only through `+alignment/`, which gains a reference → native transform

**The gap.** `applyTransform` and `applyTransformInterval` map **native →
reference only**. `readWindow` takes its interval in the tracking stream's native
units. Choosing which tracking samples to read for a call therefore requires
reference → native, which plan §4.3 lists as an `+alignment/` responsibility
("reference → native transforms when mathematically supported") and which was
never built.

**Decision: an additive `vawlume.alignment.applyInverseTransform(conn,
alignmentRunId, referenceTimes, ErrorOnExtrapolation=false)`**, owned by 6.4. It
returns native times plus the transform of record, as the forward function does.
It selects segments on the reference side, under the same half-open boundary
rule as `+internal/evaluateSegments`. It refuses a segment whose scale is not
positive, because that segment is not invertible. It flags extrapolation exactly
as the forward function does. A native → reference → native round trip must
return its input at segment interiors and exactly at breakpoints. The forward
functions stay **bit-identical**, shown by a before/after comparison.

**Rejected: reading the stream's whole coverage and filtering on
`time_reference_s`.** That reads dense data with no bound. **Rejected outright:
estimating the native interval outside `+alignment/`.** That is transform
arithmetic in another package.

Phase 5 invariant 10 ("no diff under `+alignment`") was a Phase 5 freeze. **Its
Phase 6 replacement:** *`+alignment/` changes are additive, and every existing
transform result is bit-identical.*

**The clock path for one target:**

1. The event's native interval comes from its own table, on the recording-native
   timebase.
2. It reaches the reference clock through `applyTransformInterval`, unless the
   recording-native timebase **is** the reference timebase. That is established
   from stored timebase rows, never inferred from a key's spelling.
3. The tracking read interval is the event's reference interval, padded on each
   side by `max_interpolation_gap_s`, mapped through `applyInverseTransform`
   onto the tracking stream's native clock.
4. `readWindow(..., ReferenceTimebaseKey=)` returns samples with
   `time_reference_s`.
5. Instants and samples now share the reference clock, and only then does
   `positionAtInstants` run.

**`SameClock` is an explicit declaration only**, as in `correspondWindows`:
`runSpec.clock_relation` is `alignment_run` or `same_clock`. With
`same_clock`, steps 2–3 are identity and the evidence says so. Without an
alignment and without the declaration, the run is refused before anything is
written.

**Temporal evidence.** Each target gets one `temporal_alignment` evidence row
per alignment run used. It carries the propagated uncertainty bound and its
semantics, verbatim from `applyTransform` (uncalibrated: not a confidence
interval, a standard error, or a probability), cites `alignment_run_id`, and
records the extrapolation state. The method uses the transform **structurally**:
it places the call, and the score cannot exist without it. So the profile
declares `temporal_alignment: used`, with a role saying the bound is recorded
and not used to gate or weight. An **extrapolated** event or bracket is a no-score
reason when `parameters.refuse_extrapolated_alignment` is true, which it is in
the shipped profile.

### D6. Calls are measured with the reference method's core; normalization is a versioned, band-matched division

**Measurement (6.6).** A new fixed method,
`vawlume.acoustic.call_window_response` version `1.0.0`, implemented by
`vawlume.acoustic.measureCallWindow`. It extracts and shares
`measureReferenceResponse`'s computational core, with reference measurement
proven bit-identical. Three new built-in metric definitions are added in
`+db/registerBuiltinSemantics.m`, which is seed, not DDL: `call_rms_amplitude`,
`call_peak_abs_amplitude`, `call_band_power`, with the same units as their
reference counterparts. A call's RMS and a tone's RMS are measurements of
different things, so they get different keys even though the arithmetic is
shared.

- The window is the event's own native interval on the recording-native audio
  clock. No transform applies.
- Rows are `derived_measurements` targeting `detection_id` or
  `consensus_event_id`, with `recording_channel_id` as the qualifier. The
  existing channel-scope triggers already resolve both targets' recordings.
- Agreement-group targets are **refused** in v1, because `derived_measurements`
  has no agreement-group target.
- The analysis run type is `acoustic_call_window_response`. Plan, apply, run-key
  and conflict discipline match `measureReferenceResponse` exactly.

**Departure: the band is explicit only.** The itinerary allowed the event's own
frequency bounds "where semantically compatible". v1 does not use them. Deciding
compatibility per extractor is a judgement the repository has refused to make
casually since Phase 1, because extractor frequency fields are not
interchangeable (plan §15.6). An explicit band, supplied to the call and stored
in method evidence, is always honest. No band means no band power, as for
references.

**Normalization (6.7).** `vawlume.acoustic.normalizeCallLevels`, under a
versioned policy of the existing kind `analysis_settings`, linked to the run with
role `call_level_normalization_policy`. The run type is
`acoustic_call_level_normalization`. The shipped policy lives at
`config/09_acoustic_normalization_policies/band_matched_noise_reference_v1.json`.

- **Operation:** `normalized = measured / median_response`. The pair is declared
  per metric: `call_band_power` is divided by `acoustic_band_power` from a
  response estimate with a declared `reference_type` and **the identical band**.
  A metric, family or band mismatch is refused. Families are never averaged
  (doc 28).
- **Same recording only.** A response estimate from another recording is refused
  by name. Condition 3's scope is enforced wherever the repository can enforce
  it.
- **`qc_status` handling**, each declared in the policy with nothing left to a
  code default. Shipped values: `ok` is used; `divergent` and `source_qc_warning`
  are used, and the flag propagates to the normalized row; `insufficient_evidence`
  and `not_comparable` give **no normalized value**, with a reason.
- Normalized rows are `derived_measurements` under new built-in metrics
  (`call_band_power_normalized`, unit `ratio_to_channel_response`). They carry
  lineage to both parent runs through `analysis_run_sources`
  (`call_window_measurement`, `channel_response_estimate`), and each row's
  method evidence names its exact measurement and response estimate.
- Clipping, partial coverage and failed measurements on the source row propagate
  as flags. Nothing repairs them.

**The level difference.** `vawlume.acoustic.levelDifference` is pure. For an
ordered channel pair `(a, b)` of normalized power values,
`ΔL_obs = 10·log10(P_a / P_b)` dB, positive when channel `a` is louder. It
refuses rather than computes when either side is missing, failed or clipped
(`parameters.refuse_clipped_channels = true`). It lives in `+acoustic/` because it
compares two measurements **of one quantity**, the same dimension on two
channels. It combines no dimensions, and its help text says so.

**The two-channel quantity is not persisted as a derived measurement**
(itinerary Q6(b)). The per-channel normalized levels are the citable rows. The
difference becomes a target-level `acoustic` evidence row that names both channel
indices in its semantics, and it can be reconstructed exactly from the two cited
per-channel rows. **Rejected:** a derived measurement with the pair in
`derivation_details_json`, which puts a relation into JSON (P4-2's lesson);
and a junction table, which is DDL that nothing needs once (b) works.

**Doc 28's sentence "never correction factors"** becomes false for this one
policy. 6.7 corrects it in place, with a visible marker, saying what the policy
does and why the estimates remain uncalibrated.

**Extractor-reported power is not used in v1.** It is declared `not_used` in the
estimator profile's `acoustic` role text.

### D7. The method is level-difference consistency under spherical spreading, scored in dB

**Lifts the prohibition contracts 04 and 05 kept** on combining evidence
dimensions, for this method only.

`vawlume.estimator.levelDifferenceConsistency`, method key
`vawlume.estimator.level_difference_consistency`, version `1.0.0`. For one target
and the declared ordered channel pair `(a, b)`:

1. For each candidate entity with usable geometry, the distances `d_a`, `d_b` from
   its bodypoint to each microphone, on the primary instant basis (D4).
2. The **predicted** level difference under spherical spreading, where power
   falls as `1/d²`: `ΔL_pred = 20·log10(d_b / d_a)` dB.
3. The **observed** normalized level difference `ΔL_obs` (D6).
4. **Score:** `−|ΔL_obs − ΔL_pred|` dB, `higher_is_stronger`, at most 0. Every
   intermediate (`d_a`, `d_b`, `ΔL_pred`, `ΔL_obs`, the discrepancy) is returned,
   not only the score.

**What it combines, and so what it is:** acoustic evidence (the observed
difference) with pose/location evidence (the distances), through visual-identity
evidence (which track the distances belong to) and temporal alignment (which
instant). This is the plan §11.3 evidence family *"spatial plausibility for
observed channel difference"*.

**Why natural units.** A dB discrepancy can be audited by hand, and it does not
invite being read as a probability. **Rejected:** a bounded transform such as
`exp(−(Δ/σ)²)`. It lies in (0, 1], so it would be read as a probability, and `σ`
would be a scale chosen with no measurement behind it. That fails condition 3
while appearing to meet it.

`probability` and `probability_semantics` stay NULL on every native candidate.
The score semantics string is generated from the profile and names the method
key and version, the unit and orientation, `uncalibrated`, `within_recording`,
and "not a probability".

**Assumptions, and what failure of each looks like:**

| Assumption | When it fails | What the method then does |
|---|---|---|
| Point source at the declared bodypoint (e.g. snout) | The sound radiates from elsewhere, or the bodypoint is mislocalized | Predictions shift; the true caller may score worse than a neighbour |
| Omnidirectional source | A rodent call is directional; the head faces one microphone | Observed difference is biased toward the faced microphone, independently of distance. **This is the dominant expected failure**, and 6.8's model-mismatch test probes it |
| Omnidirectional, matched microphones after normalization | Microphone directivity, or a response that differs between reference and call band | Residual gain error biases every target the same way within a recording |
| Free field: no reflections or obstruction | Walls, bedding, a nearby animal's body | Unpredictable error per position |
| Inverse-square spreading only | Atmospheric absorption at ultrasonic frequencies differs between paths | Small bias growing with path-length difference. Stated, not corrected |
| Microphones in the animals' plane when the frame is 2D | Overhead microphones | Planar distances overstate the ratio's range. Real ratios are compressed toward 0 dB, so separation looks easier than it is |
| One source in the window | Overlapping calls | `ΔL_obs` describes a mixture. The method cannot tell; see D11 |
| Two candidates, two channels (D2 `scope`) | Any other count | **Refused by name**, never extrapolated |

**Distances of zero or effectively zero** (`d < parameters.min_distance`, in
frame units) give no score, reason `distance_degenerate`, because the logarithm
is undefined.

### D8. Comparability is within one recording, and nothing claims more

**Condition 3, answered by narrowing the claim rather than proving a broad one.**
Every input to one score comes from one recording: two channels of one audio file
over one call window, normalized by that recording's own response estimates, and
distances in one declared frame that the recording's placements also cite. The
method compares nothing across recordings.

So scores are **comparable between candidates of one target**, and between
targets **of one recording under one profile version**. They are **not
comparable across recordings, sessions, devices or arenas**, and the semantics
string and the profile both say so. Normalization refuses foreign-recording
response estimates (D6), and the geometry layer refuses foreign frames, so the
scope is enforced wherever the repository can enforce it.

Nothing available could justify a broader claim. That would require calibrated
response estimates, which do not exist, and evidence that the propagation
assumption holds equally across arenas, which does not exist either.

### D9. Identity enters through a time-valid association, one track per entity, never marginalized

**The time-valid helper (closes I-4).** `vawlume.tracking.identityOverWindow`
(6.5), read-only, in `+tracking/`. For a tracking-native window and a set of
tracks, it calls `resolveIdentity` over the window and **adds no precedence
rule**. It then classifies time validity:

| `time_validity` | Meaning |
|---|---|
| `whole_window` | the chosen association's interval covers the entire window |
| `changes_within_window` | another non-rejected association for the track names a different entity, or none, over part of the window, e.g. a swap mid-call |
| `partial` | no association covers the whole window, and none contradicts the chosen one |
| `none` | no identity evidence for the track over the window |

It returns `resolveIdentity`'s reasoning (`decided_by_step`, set-aside claims)
alongside the time validity.

**Entity → track (in `vawlume.estimator.candidateGeometry`, 6.5).** A participant
gets distances **only** when exactly one track resolves to it with
`time_validity = whole_window`. Otherwise it gets no score, with one of these
reasons: `identity_no_track`, `identity_multiple_tracks`,
`identity_changes_within_window`, `identity_partial_window`, or
`identity_unresolved`.

**Partial departure.** The itinerary allowed several tracks for one entity to be
enumerated as separate labelled pairings. v1 does **not** enumerate them. Each
pairing would produce its own score for one candidate, and choosing between two
scores for one (target, entity) is itself a combination rule with no stated
basis. "Two trajectories claim this animal" is a finding to report, not something
to resolve.

**Enumerate, never marginalize.** No `identity_value` is read as a weight. Nothing
averages over tracks. Contract 04 D9's refusal stands: identity values from
different upstream systems are not comparable.

### D10. Every participant is a candidate, and every input is a cited evidence row

**Candidates.** v1 requires exactly two participating entities (D2 `scope`).
Each target gets one candidate row per participant:

- `score` and `score_semantics` from the method; or `score` NULL with
  `notes = "no_score_reason=<code>"` when the method could not evaluate that
  entity;
- `probability` NULL always; `source_label` NULL, because no upstream label
  exists; `candidate_rank` omitted, because rank is presentation and not
  evidence.

Absence stays visible: an unscored entity is a candidate row, not a missing row.

**No-score reasons**, a closed set the method returns:
`identity_no_track`, `identity_multiple_tracks`, `identity_changes_within_window`,
`identity_partial_window`, `identity_unresolved`, `track_not_covered`,
`track_covered_empty`, `bodypart_missing`, `alignment_extrapolated`,
`channel_unplaced`, `frame_unit_not_accepted`, `distance_degenerate`,
`acoustic_unavailable`, `acoustic_clipped`.

**Evidence rows written per target** (6.9 implements; 6.11 prints):

| Dimension | Kind | Grain | Value | Units | Citations |
|---|---|---|---|---|---|
| `temporal_alignment` | `call_clock_placement` | target, per alignment run | uncertainty bound (NaN when unrecorded, stated) | `s` | `alignment_run_id` |
| `acoustic` | `call_band_power_normalized` | target, per channel | normalized level | `ratio_to_channel_response` | `derived_measurement_id` (D13), `recording_channel_id` |
| `acoustic` | `normalized_level_difference` | target | `ΔL_obs` | `dB` | none relational; semantics name channel indices `a`, `b`. Reconstructible from the two rows above |
| `visual_identity` | `track_entity_association_used` | candidate | text: track id, `decided_by_step`, `time_validity` | `text` | `identity_statement_kind = identity_association`, `tracking_identity_association_id` |
| `pose_localization` | `bodypoint_microphone_distance` | candidate × channel × instant basis | distance | frame unit | `tracking_identity_association_id`, `recording_channel_id` |
| `pose_localization` | `bodypoint_pose_confidence` | candidate × instant basis | `pose_confidence_min_bracket` | `upstream_score` | `tracking_identity_association_id` |

Rows are written **only for values that exist**. An unscored candidate still
gets every row its available evidence supports. An identity-swap candidate, for
example, still has its target's acoustic rows. Every `value_semantics` names its
producer (method key and version), following contract 05.

**Reconstruction is the test of condition 4.** From storage alone (these rows,
the rows they cite, and the stored profile version), 6.9 recomputes every score
by calling the pure method and gets the stored value back.

### D11. A native decision policy uses an additive rule that has no `simultaneous` branch

The shipped rule `threshold_with_separation_and_co_occurrence` reads two
independently strong contenders as `simultaneous`, which is a claim about the
world. For a consistency score, two strong contenders mean the geometry cannot
separate the animals, for example when they are equidistant from both
microphones. That is **ambiguity**. And a level difference over one window
cannot show two simultaneous sources at all (D7, last assumption).

**Decision: an additive rule key, `threshold_with_separation`**, owned by 6.10.
It is identical to the existing rule through the separation step. Several
contenders give `ambiguous`, with `separation_margin` recorded as the applied
threshold. There is no co-occurrence step, and a policy using this key that
declares `co_occurrence_threshold` is **refused**, because a threshold that
nothing reads would mislead. Existing policies decide **bit-identically**, shown
by before/after decisions on the existing fixtures.

**Rejected: a co-occurrence threshold set out of reach.** That is a constant
posing as a policy.

**A latent defect found while deciding this.** `attributionLoadPolicy` requires
`decision_rule.key` but never dispatches on it: any key string runs the shipped
rule. A policy naming a rule VAWLUME does not implement is silently decided by a
different one. 6.10 fixes this as part of D11. The loader dispatches on the key
and refuses an unknown one by name.

The native policy ships at
`config/08_attribution_policies/native_level_difference_decision_policy.json`. Its
thresholds are in dB discrepancy and illustrative, chosen by 6.10 against the
score ranges 6.8 observes. Its `what_this_policy_is_not` says that equal scores
mean the geometry cannot separate the candidates, and that this method cannot
evidence simultaneous calling. A target with no scored candidate is `excluded`
under the `no_readable_value` rule, which is distinct from `unassigned`.

### D12. Closure invariants: three revised, one retired, new ones frozen

Carried from `phase_5.11_handoff.md` §9A. The changed ones are worded here as
6.13 verifies them:

- **5 (revised):** Evidence dimensions are combined only inside
  `src/+vawlume/+estimator/`, by a method whose settings profile states the five
  conditions. Nothing in `+attribution/`, `+acoustic/`, `+tracking/`, `+geometry/`
  or `+alignment/` combines them. `+acoustic/`'s level difference compares one
  dimension across two channels and is not a combination.
- **10 (revised):** `+alignment/` changes are additive, and every existing
  transform result is bit-identical.
- **14 (retired):** "the native estimator was not introduced early" no longer
  applies. **Replaced by:** every native run's settings profile states all five
  conditions, and its four declared inputs are stored with none undeclared.
- **16 (extended):** imported, backend and native runs read back through one
  field set, and the only path branch in `report` is caveat prose.
- **19 (revised):** D3's sentence.

**New Phase 6 invariants:**

23. Every native candidate score is reconstructible from its cited evidence rows,
    the rows they cite, and the stored settings profile version.
24. No native candidate carries a probability, and every native score's semantics
    say it is not one.
25. The native estimator reads no `imported_attribution_*`,
    `attribution_localization_estimates` or `imported_composite` row.
26. A track reaches an entity only through a cited
    `tracking_identity_associations` row. No string comparison between a track
    label and an entity identifier exists in `+estimator/` or `+tracking/`.
27. The native decision policy cannot produce `simultaneous`.
28. Normalization never crosses recordings, and never mixes metric, reference
    family or band.
29. Every guard Phase 6 revised or added fires when its violation is injected.
30. The estimator package contains no SQL write statement; every native write goes
    through `+attribution/`'s public functions.

### D13. P4-3 rides as one column, `attribution_evidence.derived_measurement_id`, with `ON DELETE RESTRICT`

**Closes P4-3 in the form the native estimator needs.** Contract 05 D8 deferred
P4-3 explicitly to here, predicting that the right citation might be a
`derived_measurement_id` rather than an `analysis_run_id`. It is.

**What breaks without it:** the per-channel acoustic evidence (D10) could cite its
channel but not the measurement it reports. Reconstruction (invariant 23) would
then depend on searching `derived_measurements` by (event, channel, metric, run),
a query whose population changes silently. Doc 28 designed
`estimateChannelResponse` to take explicit IDs precisely to avoid that.

- One nullable FK, `REFERENCES derived_measurements(derived_measurement_id)`.
- **`ON DELETE RESTRICT`, departing from the itinerary's CASCADE suggestion.**
  CASCADE would delete an acoustic evidence row when its measurement run is
  deleted, while the candidate score computed from it survives. The score would
  then be unreconstructible, silently breaking invariant 23. RESTRICT forces the
  attribution run to be deleted first. That is the rule
  `channel_response_estimate_sources` and `analysis_run_sources` already follow
  for derived results: a derived result must not outlive the evidence it was
  computed from. (Contract 05 D3 chose CASCADE for estimate citations because no
  score was computed from them.)
- **Scope triggers, insert and `_update`.** The measurement's recording, resolved
  through its target as `trg_derived_measurement_channel_scope` resolves it, must
  equal the evidence row's run recording. The `_update` twin falls under schema
  §14's exception: repointing a citation changes what the row claims.
- **Not in the schema, by the Phase 4 split** (the schema refuses false claims;
  the API refuses unsupported ones): that the measurement targets the same event
  as the attribution target, and that its channel matches the row's
  `recording_channel_id`. These are `addEvidence` refusals (D15).
- **Rejected: the three-column form** contract 05 D8 sketched (analysis run,
  artifact, stream). No Phase 6 consumer needs the other two. The run is reachable
  from the measurement.

### D14. One bump, `0.12-draft` → `0.13-draft`, owned by 6.2; I-5 and P4-2 do not ride

Verified at 6.1: the live schema reads `0.12-draft` / `PRAGMA user_version = 12`.

**Rides:** D13's column and triggers; D2's profile kind. Nothing else.

**I-5 (`ordinal_source` not stored) is re-deferred. This departs from the 5.11
disposition** ("next schema bump") and from the itinerary map. Applying the test
contract 05 D9 applied to P4-2, *say what breaks without it in this phase*,
finds nothing: I-5 concerns backend localization estimates, which the native
estimator never reads (invariant 25). Closing it also needs more than a column.
Backend intake must write it and `report` must read it. That is behaviour in
`+ingest/` and `+attribution/` that no Phase 6 itinerary otherwise touches, and
6.2's tripwire forbids it. **Named opening:** the next itinerary that edits
backend intake, or Phase 7 consolidation.

**P4-2 does not ride**, for contract 05 D9's reasons. The estimator's own profile
is relational: a settings profile version on the run, plus declared inputs.

What moves with the bump is contract 05 D12's list: the three spellings in
`schema.sql`, `schema_metadata.json` (descriptions for the new column, triggers,
relationship and vocabulary member, plus a `metadata_version` bump),
`schema.json` (regenerated), the usage guide's status line, and the status blocks
of contracts 04, 05 and 06. 6.2 confirms with one export of a migrated fixture
that the CSV export needs no change.

### D15. The canonical write layer's two admissions belong to 6.8

The itinerary set left an orphan. `addEvidence` must accept and validate D13's new
column, and 6.2 (representation only), 6.8 and 6.9 each carried a tripwire that
forbade editing it.

**Owner: 6.8.** 6.8 is where the canonical layer admits a native result, and both
admissions are the same kind of change:

- `createRun` admits `attribution_path = 'native_estimate'` (D16);
- `addEvidence` accepts `derived_measurement_id` on any dimension, refusing it by
  name when the measurement does not exist, belongs to another recording, targets
  a different event from the evidence row's target, or carries a different channel
  from the row's `recording_channel_id`.

6.8's tripwire therefore narrows. `addCandidates`, `decide` and `report` stay
unchanged in 6.8, and `addEvidence` changes only to accept the citation. 6.9's
tripwire (no `+attribution/` change) stands. `report`'s explicit column lists
gain the new column in 6.10.

### D16. `createRun` writes declared inputs from the run spec; a native run declares all four

The backend path writes `attribution_run_declared_inputs` in a private loop inside
`+ingest/` (`attributionBackendApplyPlan`). `+estimator/` cannot call it and must
not write SQL itself (invariant 30).

**Decision:** `createRun` gains an optional `runSpec.declared_inputs`. It is a
table of (`input_dimension`, `declaration`, `notes`), written in the same
transaction as the run, with `declared_by_profile_version_id` set to the run's
settings profile version. For `attribution_path = 'native_estimate'`:

- the settings profile **must** be of kind `attribution_estimator_settings`, and
  that kind is refused on any other path;
- `declared_inputs` is **required and complete**, with all four dimensions, so a
  native run has no undeclared dimension;
- `vawlume.estimator.attributeCallers` builds it from the profile's `dimensions`
  block. The declaration therefore comes from the same profile version that
  `declared_by` cites.

Backend intake is **unchanged**. It keeps its own writer for its own profile
language. That leaves two code paths inserting into one table. They interpret
different configuration contracts, so `02_general.md` §6 is not breached. It is
recorded as a minor consolidation item for whichever itinerary next edits
backend intake.

### D17. The method uses distance ratios; the profile names the frame units it accepts

`23_spatial_geometry_schema.md` requires that a phase needing metric distance
"must require a metric unit or an explicit provenance-bearing scale, and must
never treat pixels as centimetres".

D7 uses only the **ratio** `d_b / d_a`, which is unchanged by any uniform,
isotropic scaling of the frame. The method therefore needs no metric unit. It
needs a frame whose scale is **uniform and isotropic** over the arena. A `px` frame
from an overhead camera with perspective or lens distortion is not, and VAWLUME
cannot tell which kind of frame it has.

**Decision:** `parameters.accepted_frame_units` is an explicit list of unit
strings that the profile author asserts denote uniform-scale frames. The shipped
profile lists `cm`, `mm` and `m`. The check is exact string membership. VAWLUME
interprets nothing, as doc 23 requires. The profile author made the declaration,
and it is versioned. A frame whose unit is not listed gives no score, with reason
`frame_unit_not_accepted`. Distances are still computed and stored in the frame's
unit, because 6.3's primitives are unit-agnostic.

---

## The five conditions, answered

These are the words the shipped settings profile uses (D2), written here first.

### 1. Which dimensions it uses, and which it ignores

| Uncertainty source | Declaration | Role |
|---|---|---|
| `temporal_alignment` | `used` | Places the call on the tracking clock; the score cannot exist without it. Its uncertainty bound is recorded as evidence, not used to gate or weight. An extrapolated placement gives no score |
| `pose_localization` | `used` | The bodypoint position at the declared instant gives both microphone distances. Pose confidence is recorded as evidence, not used to gate or weight |
| `visual_identity` | `used` | Decides which trajectory's positions belong to which candidate, through one time-valid association. Used as a gate, never as a weight; `identity_value` is not read |
| `acoustic` | `used` | The band-matched, normalized level difference between the two channels. Extractor-reported power is not used |
| `source_localization` | `not_used` | The native path consumes no backend output (invariant 25) |

The four declarations are stored per run in `attribution_run_declared_inputs`
(D16).

### 2. What the resulting number means

The negative absolute difference, in dB, between the inter-channel level
difference the microphones recorded and the difference the candidate's position
predicts under spherical spreading. Higher is stronger, and 0 is perfect
agreement. **It is not a probability, not a likelihood, not a posterior, and not
a confidence that the candidate called.** It says how well one explanation fits,
not how likely it is.

### 3. How each input was scaled, and why the scales are comparable

Acoustic levels are divided by each channel's own median response to a
band-matched reference of a declared family in the same recording (D6), and
compared as a dB ratio between two channels of one file. Distances enter only as
a ratio within one declared frame whose unit the profile accepts as uniform-scale
(D17). The two sides of the comparison are therefore both dB quantities about one
recording at one call. **Comparability is claimed within one recording only**
(D8). Nothing establishes comparability across recordings, and none is claimed.

### 4. That every input remains separately readable

Every input is its own `attribution_evidence` row with its citation (D10). The
measurement rows behind the acoustic evidence are themselves stored and cited
(D13). The score is reconstructible from storage alone, and a test proves it
(invariant 23).

### 5. Calibration status

`uncalibrated`. No ground truth for who called exists for any recording VAWLUME
has seen, and the response estimates the normalization uses are themselves
uncalibrated (doc 28). Calibration requires recordings with an independently
established caller, which is outside VAWLUME's control.

## The two refusals lifted

| Refusal | Was | Now | Single home | Guard |
|---|---|---|---|---|
| Spatial arithmetic | "VAWLUME computes no distance, angle, or coordinate transformation" (contract 05 D11; Phase 5 invariant 19) | Distance and position interpolation, within one frame, never across frames (D3, D4) | `+geometry/` | Package allow-list in `testNoSourceComputesADistanceAngleOrTransform` (6.3) |
| Combining dimensions | "VAWLUME combines none of them" (contract 04 uncertainty position; contract 05 D3; Phase 5 invariant 5) | One method combines acoustic, pose and identity evidence over an aligned instant (D7) | `+estimator/` | A combination package-boundary guard, added by 6.8 and injection-verified |

Contracts 04 and 05 are not rewritten. Sentences this phase makes false are
corrected in place with a visible marker by the itinerary that makes them false:

- contract 05, "VAWLUME computes no distances today, and Phase 5 does not start"
  (D11) and the core-vocabulary sentence "It computes no distance…": **6.3**;
- contract 05, "VAWLUME combines none of the five" and the matching sentences in
  contract 04's uncertainty position: **6.8**, once the method exists;
- `createRun`'s help text ("nothing produces one yet"): **6.8**;
- doc 28's "never correction factors": **6.7**;
- doc 24's "What is not here: Interpolation…": **6.4**, which records that
  interpolation now exists in `+geometry/` and still never modifies tracking
  values.

## Phase 6 non-goals

- a Bayesian, learned or trained model;
- any calibrated threshold, calibrated probability, or status meaning `validated`;
- a claim of comparability across recordings, sessions, devices or arenas (D8);
- transforming coordinates between frames; treating an unaccepted unit as
  uniform-scale (D17);
- angles, bearings, directivity models, time-difference-of-arrival,
  beamforming, or source separation;
- more than two candidates or two channels in v1 (D2 `scope`);
- marginalizing over tracks, or reading `identity_value` as a weight (D9);
- consuming imported claims, backend estimates or `imported_composite` rows
  (invariant 25);
- agreement-group targets for the native path (D6);
- using extractor-reported power or an event's own frequency bounds (D6);
- raw-video ingestion, pose estimation, or image-based re-identification;
- dense tracking, audio or identity materialization;
- cross-path comparison, sensitivity analysis, or comparison of normalization
  profiles (Phase 7);
- I-5 and P4-2 (D14).

## Inherited schema audit

### Already correct — preserve

- **`attribution_runs.attribution_path`** already admits `native_estimate`.
  Only `createRun`'s plan builder refuses it (D16).
- **`attribution_candidates`**: unconstrained score with required semantics,
  bounded probability, `UNIQUE(target, entity)`, rank as presentation. A
  negative dB score is legal as it stands.
- **`attribution_evidence`**: closed dimensions, free-text kinds, `value_real`
  with required semantics, `identity_statement_kind` with
  `tracking_identity_association_id`, `alignment_run_id`,
  `recording_channel_id` (0.12). Every D10 citation already exists except the
  measurement (D13).
- **`attribution_run_declared_inputs`** (0.12): four uncertainty sources,
  `used`/`not_used`, provenance required. It holds condition 1 unchanged.
- **`attribution_decisions` and its link table**: set-valued decisions,
  cardinality triggers in three directions, policy retention. Unchanged.
- **`derived_measurements`**: detection and consensus-event targets with a
  channel qualifier, channel-scope triggers in both directions. Holds call
  measurements and normalized levels unchanged.
- **`analysis_run_sources`**: many-parent lineage with RESTRICT. Holds the
  normalization run's two parents.
- **`channel_response_estimates`**: per channel, metric, family and band; QC
  vocabulary. Read, never modified.
- **`coordinate_systems`, `channel_placements`, `tracking_streams`**: frames by
  identity, units free text, `z` NULL in 2D. D3 and D17 build on them.
- **`tracking_identity_associations`**: interval-scoped, `unresolved` distinct
  from none, values with semantics. D9 reads them and writes none.
- **`vawlume.alignment.applyTransform` / `applyTransformInterval`**: the forward
  clock path, bit-identical after D5.

### Gaps Phase 6 must fill

| Gap | Decision | Owner |
|---|---|---|
| Evidence cannot cite a derived measurement (P4-3) | D13 | 6.2 (DDL), 6.8 (`addEvidence`), 6.9 (writes), 6.10 (`report` reads) |
| No profile kind for estimator settings | D2 | 6.2 (vocabulary), 6.8 (profile and loader) |
| No spatial arithmetic | D3, D4 | 6.3 |
| No reference → native transform | D5 | 6.4 |
| No event-window position retrieval | D4, D5 | 6.4 |
| No time-valid identity helper (I-4) | D9 | 6.5 |
| No call-window measurement | D6 | 6.6 |
| No normalization or level difference | D6 | 6.7 |
| `createRun` refuses `native_estimate`; no generic declared-inputs write | D16 | 6.8 |
| No method | D7 | 6.8 |
| No native writer | D10 | 6.9 |
| Decision rule cannot express "no `simultaneous`"; rule key not dispatched | D11 | 6.10 |
| `report` does not show the new column; no native caveat prose (F5.10-11) | D12 | 6.10 |

The delta plan beside the 6.1 itinerary in the development repository assigns
every individual change to exactly one itinerary.

### Constraints inherited from elsewhere

- **The MATLAB Database Toolbox raises on any SQL NULL in a result set**,
  including aggregates over empty sets. Every new nullable read (the new FK, an
  unscored candidate's score, a normalized level with no estimate, a distance at
  an uncovered instant) needs the established `IFNULL(...)` sentinel treatment,
  and every QC count needs testing over an empty set.
- **It can also return an empty TEXT column as `<missing>` even under `IFNULL`**
  (doc 24). Every nullable text read goes through a `presentText`-style
  normalizer.
- **Absence reads as absence**: NaN for a number, `""` for text, never `0` and
  never `1.0`.
- **Insert-only scope triggers are the repository-wide convention** (schema §14),
  with `_update` twins only where a change alters a row's meaning. D13 qualifies.
- **The semantic metadata document is the single authority for column meaning**
  (`schema/README.md`). New columns, triggers and vocabulary members need
  descriptions in the same change as the DDL, or the completeness gate fails.
- **`regexp` over MATLAB source is DOTALL by default, and comments are not code.**
  `regexp(..., "once")` over a string returns `<missing>` on no match, which is
  not empty. Any sweep for a literal enumerates and reads its matches.
- **"Phase 6" in `01_prototype_development_outline.md` and
  `02_temporal_alignment_contract.md` means prototype v1's Phase 6.** A search for
  the phrase must read each hit.

## What Phase 6 will not be able to claim

Written at 6.1, while it is cheap, and carried to 6.13.

**No real paired session is available** (confirmed by the user before 6.1). Every
recording, tracking file, placement and reference Phase 6 reads will have been
written by this repository. Therefore:

- **The estimator's successes on synthetic data are self-consistency, not
  accuracy.** A scene generated under spherical spreading from a point source is
  scored correctly because the method assumes exactly that. 6.8 and 6.11 also
  build a **model-mismatch scene**, with the level difference generated under a
  directional source. It shows how the method fails when its dominant assumption
  is wrong. It shows only the direction of failure for one synthetic directivity,
  not its rate in real animals. *(Recorded at 6.11: in the demonstration's scene,
  a −9 dB bias at one microphone exceeded the 5.63 dB tolerance, which is half
  the gap between the two candidates' predictions. The animal that did not
  generate the call then scored −2.27 dB, ranked first, and was `assigned` under
  the native policy. Nothing in the run flagged it. See
  [`../development/45_integrated_native_estimator_demonstration.md`](../development/45_integrated_native_estimator_demonstration.md).)*
- **Nothing establishes that any score is comparable across recordings** (D8),
  and none is claimed.
- **Nothing establishes that normalization corrects anything in absolute terms.**
  The response estimates are uncalibrated (doc 28). Normalization removes the
  relative gain difference between channels only to the extent the reference
  family represents the call band.
- **The method cannot detect simultaneous calling** (D7, D11). A mixture of two
  callers yields one observed difference, which the method scores as if one
  animal produced it.
- **It cannot claim a frame was declared correctly**, or that a microphone
  placement was measured correctly. VAWLUME confirms that facts cite one frame. It
  cannot confirm they were measured in it.
- **It cannot claim a track was the animal the association says.** It confirms an
  association exists and is time-valid. The association's correctness is its
  producer's claim.
- **Every threshold is a demonstration value**, chosen against synthetic score
  ranges.
- **Nothing is known about scale.** `report` has no paging (I-6), and D10 writes
  roughly a dozen evidence rows per candidate per target.

If real paired data becomes available later, the itinerary that uses it must say
what it is and what it does not cover. **Without an independent record of who
called, it validates the pipeline on a real format, not the estimates.**

## Definition of done for Phase 6

The phase is complete when:

- `createRun` creates a native run under an `attribution_estimator_settings`
  profile that states the five conditions, and stores all four declared inputs;
- spatial arithmetic exists only in `+geometry/`, within one frame, with
  interpolation bounded and never extrapolating, and its guard is a package
  boundary that was injection-verified;
- an event reaches the tracking clock only through `+alignment/`, which gained a
  bit-identity-preserving reference → native transform;
- a participant gets distances only through one time-valid association;
- calls are measured from raw audio through the reference method's shared core,
  and normalized band-matched within one recording under a versioned policy;
- one pure, versioned method combines the evidence into a dB score that is never a
  probability, and combination exists nowhere else;
- `vawlume.estimator.attributeCallers` writes a native run through the canonical
  API only, and every stored score is reconstructible from storage;
- a native decision policy cannot produce `simultaneous`, and the decision rule
  key is dispatched;
- `report` returns all three paths through one field set;
- the schema is `0.13-draft` / `user_version = 13`, reached in one bump;
- the whole path runs as one public demonstration on synthetic data. That
  includes a separable scene, a symmetric scene, a model-mismatch scene, a
  coverage gap, an identity swap, and named refusals;
- the full gate passes on a committed candidate with a clean tree.

## Related documents

- [`04_caller_attribution_contract.md`](04_caller_attribution_contract.md): the attribution contract; its five conditions are answered above
- [`05_backend_localization_contract.md`](05_backend_localization_contract.md): the backend contract; D8 deferred P4-3 to here, D11 deferred distance to here
- [`03_multimodal_input_contract.md`](03_multimodal_input_contract.md): frames, tracking, identity, and the dense-data policy
- [`../development/23_spatial_geometry_schema.md`](../development/23_spatial_geometry_schema.md): compatibility is identity; no frame transforms; the metric-unit rule D17 answers
- [`../development/24_tracking_input_contract.md`](../development/24_tracking_input_contract.md): three-state coverage; pose confidence is localization quality only
- [`../development/25_visual_identity_association.md`](../development/25_visual_identity_association.md): associations, `unresolved` versus none, the precedence helper
- [`../development/27_audio_window_and_response_measurement.md`](../development/27_audio_window_and_response_measurement.md): the measurement method D6 extends
- [`../development/28_channel_response_estimates.md`](../development/28_channel_response_estimates.md): the response estimates D6 divides by
- [`../development/31_caller_attribution_schema.md`](../development/31_caller_attribution_schema.md): the attribution data dictionary 6.2 extends
- [`../development/30_repository_self_description.md`](../development/30_repository_self_description.md): version claims, before the bump
- [`../../schema/README.md`](../../schema/README.md): the three schema artifacts a bump must move together
