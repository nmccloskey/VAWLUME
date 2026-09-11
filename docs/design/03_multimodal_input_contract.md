# Multimodal Input and Acoustic-Reference Contract

## Status

**Design contract. Nothing in this document is implemented yet.**

This is the governing contract for VAWLUME's multimodal input layer: spatial
coordinate systems, microphone geometry, canonicalized tracking inputs,
optional acoustic references, bounded external-data access, and measured channel
response. It defines vocabulary, the authoritative representation for each
concept, the invariants that must hold, and the boundaries this layer must not
cross.

It is the multimodal sibling of
[`02_temporal_alignment_contract.md`](02_temporal_alignment_contract.md), and it
deliberately follows that document's structure and its central discipline:
decide what the distinct concepts *are* before writing tables, and refuse to let
two of them share a representation because they happen to look alike.

Read this before changing anything under the coordinate-system, placement,
tracking, or acoustic-reference tables.

## Emphasis: inputs, not inference

This layer exists to make non-extractor inputs **expressible with provenance**.
It performs no attribution, no caller assignment, no scoring, and no
localization.

The following belong to later work and must not be pre-implemented here:
caller-candidate models, caller probabilities or evidence scores, localization
backends, spatial plausibility reasoning, and any function that combines
acoustic and spatial evidence into a claim about who vocalized.

Building the estimator before the inputs have a stable, provenance-bearing
representation would mean estimating from data whose meaning is not yet
established. That is the same ordering argument alignment made against sequence
analysis, and it holds here for the same reason.

## Motivating workflow

```text
canonicalized tracking output (DeepLabCut / SLEAP / other)
+ a declared spatial coordinate system
+ microphone positions in that same system
+ optional acoustic-reference intervals (tones, noise, user-defined)
+ VAWLUME-linked audio recordings
                    ↓
source mapping / registration
                    ↓
VAWLUME operational ontology
    coordinate systems
    channel placements
    tracking streams + series (dense samples stay external)
    acoustic references
                    ↓
bounded window access
    tracking window reader
    audio window reader
                    ↓
measured evidence
    per-reference, per-channel response measurements
                    ↓
aggregated channel-response estimates + QC
                    ↓
    (later phases: caller attribution)
```

## The six distinct concepts

As with the alignment layer, the most important property of this contract is
that these are six different things:

```text
coordinate system   a declared spatial frame with a unit and a dimensionality
channel placement   where one recording channel's microphone was, in one system
tracking stream     a logical series of spatial samples on one clock
tracking series     one (entity, bodypart) trace within such a stream
acoustic reference  an interval of a recording asserted to carry a known signal
response estimate   an aggregated, QC-bearing summary of measured channel response
```

Two of these are new kinds of object for VAWLUME. The other four extend or
subtype machinery that already exists, and this document says which, and why,
in each case.

## Coordinate systems

### Identity, not structural equality

`coordinate_systems` declares a spatial frame: a key, a human-readable name, a
dimensionality, a unit, and free-text origin and orientation descriptions.

**Two spatial facts are compatible if and only if they cite the same
`coordinate_system_id`.** Compatibility is identity, never structural
similarity.

This is the single most important rule in this contract, and it is deliberately
stricter than it needs to be. Two systems that both say `dimensionality = 2` and
`unit = 'cm'` are *not* interchangeable: they may have different origins,
different axis directions, or describe different arenas entirely. Treating
matching metadata as license to compare coordinates is precisely how a confident,
wrong distance gets computed. VAWLUME validates that a comparison is declared
legal; it does not infer that one is.

### No transformations

**VAWLUME does not transform coordinates between spatial systems.** There is no
rotation, no translation, no rescaling, no projection, and no registration
between frames.

If a user's tracking output and microphone positions are in different systems,
the correct response is to refuse the operation and say so, not to guess a
transform. Users who need a common frame must produce their data in one.

This is a narrower scope than the temporal layer, which *does* fit and apply
transforms between clocks. The asymmetry is intentional: clock transforms are
identifiable from explicit anchor observations that users actually supply, and
the affine model is transparent and checkable. No equivalent anchor evidence
exists for spatial frames in the motivating workflows, so a spatial transform
would be an assumption wearing the costume of a measurement.

### Dimensionality and units

- `dimensionality` is `2` or `3`. 2D is the working case; 3D is representable
  and never required.
- A `z` coordinate may be supplied **only** when the cited system declares
  `dimensionality = 3`. Enforced by trigger, because SQLite `CHECK` cannot
  reference another table.
- `z` remains optional even in a 3D system: an unknown height is missing data,
  not a modelling error.
- `unit` is free text (`cm`, `mm`, `m`, `px`, …) and is a property of the
  system, so units cannot disagree between two compatible facts.

**Pixel units are permitted and are a recorded limitation.** Tracking output is
frequently in pixels, and Phase 2 has no reason to demand metric calibration
because it computes no distances. A later phase that needs real distance must
either require a metric system or introduce an explicit, provenance-bearing
scale — and must not silently treat pixels as centimetres. This contract records
the hazard rather than solving it.

## Channel placement

### The microphone is the channel

A microphone reaches VAWLUME as a **recording channel**. `recording_channels`
already exists, is scoped to one recording, and carries a channel index, label,
and role. Placement therefore attaches to `recording_channel_id`.

This choice does two things at once. It makes placement **session-specific by
construction** — because a channel belongs to exactly one recording, a placement
row cannot claim a position that outlives the session it was measured in. And it
matches what a later estimator actually needs, which is the position of the
microphone that produced *this channel's* samples.

A four-microphone interface produces four channels with four placements. That is
not duplication; those are four different microphones in four different places.

### One authority, with the profile as provenance

Placement is **not** read from the device profile at query time, and the device
profile's `placement` block is **not** the authority.

Today `config/02_device_profiles/recording_device_profile_examples.json` carries
a `placement` object (`position_label`, `orientation`, `distance_to_arena_cm`),
and `config/03_setup_profiles/…` carries `recording_geometry.microphone_positions`.
Both are *reusable* profiles that may be applied to many sessions, so neither can
answer "where was this microphone during this recording" without pretending
hardware has one eternal position. Those blocks remain useful as authoring input
and as human documentation; they stop being consulted once a placement row
exists.

A registration function may read a setup profile and write per-recording
placement rows, recording the originating `config_profile_versions` row as
provenance. The database then holds exactly one answer per channel.

**A two-level model — reusable setup geometry plus per-recording override — was
considered and rejected.** It would create two competing answers to the same
question, which is the failure the alignment layer already corrected when it
removed the direct `source_file_id`, `artifact_id`, and
`mapping_profile_version_id` columns from `external_streams` in favour of
`external_stream_sources` alone. That precedent is binding here.

### Scope limits

- **One placement per channel.** A microphone moved mid-recording is not
  representable and is out of scope. If that becomes real, it needs a time-bounded
  placement model and an explicit decision, not a quietly added nullable interval.
- **Only audio channels.** Cameras, arena landmarks, and other located objects
  are not placed by this contract. The coordinate system exists and a later phase
  may add its own placement table citing it.

## Tracking inputs

### A tracking stream is an external stream

`external_streams`, `external_stream_sources`, `external_stream_coverage`, and
`timebases` already express everything a tracking stream shares with a
behavioural or neural stream: a logical identity distinct from its files, one or
more provenance-bearing sources, a clock, and multi-segment coverage.

Tracking **reuses all four**. It does not get a parallel stream ontology.

`external_streams.stream_kind` gains `tracking` in its CHECK vocabulary. The
existing `continuous` value was considered and rejected: a tracking stream is not
a continuous signal in the sense that a photometry trace is, and conflating them
would blur a distinction the coverage and window-reading semantics depend on.

### The tracking subtype

`tracking_streams` is a **1:1 subtype** of `external_streams`, keyed by
`external_stream_id`, holding the facts only tracking has:

- the cited `coordinate_system_id`;
- the native time basis — `time`, `frame`, or `both`;
- a nominal frame rate, required when the basis is frame-only;
- whether the source supplies confidence;
- a declared sample count, for sanity checks against the artifact.

Stream identity, sources, timebase, and coverage stay on the parent tables. There
is one stream ontology with a tracking-specific extension, not two.

### Series, not an ontology

`tracking_series` names one `(native track, bodypart)` trace within a stream:

| Column | Meaning |
| --- | --- |
| `native_track_id` | the source's own trajectory/individual label, preserved verbatim |
| `native_bodypart_label` | the source's own landmark term, preserved verbatim |
| `canonical_bodypart_role` | optional normalized role, e.g. `snout` |

**VAWLUME does not define a bodypart ontology.** Native labels are always
preserved and always queryable. A canonical role is optional, additive, and
justified per project — the same additive-normalization rule
`external_events.event_type` follows beside `native_event_label`, and the same
rule the extractor layer follows for canonical features.

### A track label is not an animal

`native_track_id` is the **upstream trajectory identity** — `track0`,
`individual1`, or an animal-like name the tracker happened to use. A tracker may
emit a stable-looking label while still permitting identity swaps, ambiguous
crossings, and uncalibrated identity evidence, so the label names a trajectory
and is not evidence about which animal it follows.

**There is deliberately no `entity_id` on this table.** Associating a native
track with a canonical experimental entity is time-varying evidence carrying its
own score semantics, calibration status, review state and provenance — a
separate layer, not a column. A nullable column here would make an unverified
guess indistinguishable from a verified assertion, and would force one identity
per trace for an entire session, so an identity swap mid-session could not be
represented at all.

Four uncertainties stay separate throughout this layer and must never be
collapsed into one confidence value: **pose/localization** uncertainty (where a
bodypart is), **visual-identity** uncertainty (which animal a trajectory
represents), **temporal-alignment** uncertainty (which samples correspond to an
event), and later **caller-attribution** uncertainty.

### Dense samples stay external

**No table in this contract stores a tracking sample.** `tracking_series` is
metadata — tens of rows per stream, one per trace — not data.

Positions, frames, and confidences remain in the registered artifact and are
read window-wise on demand. This follows the policy the schema already applies to
continuous neural data, and it is a hard boundary: an itinerary that finds itself
wanting a `tracking_samples` table has left this contract and needs an explicit
decision, not a migration.

Confidence is never mandatory. A tracker that emits none produces a stream with
`has_confidence = 0`, and readers report its absence rather than substituting a
value.

## Acoustic references

### A reference is a claim about a recording, not a stream

An `acoustic_references` row asserts that a named interval of a recording carries
a known signal: a scripted tone, white noise, a persistent background band, or
anything a user defines.

It is scoped to `recording_id`, optionally narrowed to `recording_channel_id`,
and stated **in the recording's own native audio clock**.

Routing references through `external_events` was considered and rejected. An
external event belongs to an external stream on that stream's timebase, so every
reference would have to invent a stream and a clock, and the audio reader would
then have to resolve a *time transform* to get back to the audio samples it needs
to measure. That would make a measurement requiring no alignment depend on the
alignment layer. A reference lives where its samples live.

The reuse path is preserved rather than discarded: `acoustic_references` carries
a nullable `external_event_id`, so a reference identified from a mapped event
table keeps its link to the imported event, and the existing profile-driven event
import can feed reference registration without owning it.

### Type is open

`reference_type` is **free text**, not an enum.

A closed vocabulary would force an unfamiliar reference into the wrong category
or block it entirely, which is the same reasoning that keeps `timebase_kind` free
text. Shipped examples will demonstrate tone-like, noise-like, and user-defined
types without any of them being privileged.

Optional `frequency_min_hz` and `frequency_max_hz` describe a band when one is
known. They are never required, and a reference with no declared band is a
complete, valid reference.

### A reference is not an alignment anchor

These are different objects with different purposes, and the same physical tone
may legitimately be both.

An alignment anchor establishes a relationship **between clocks**. An acoustic
reference characterizes a **channel's response**. Making one imply the other
would mean either that every sync tone silently becomes calibration evidence, or
that every calibration tone silently becomes a clock correspondence — both wrong.

If a signal serves both purposes it gets a row in each table, by explicit user
declaration. Nothing links them automatically.

### The logical reference is not its measurement

A reference row says *where to look and what is claimed to be there*. It stores
no amplitude, no power, and no measured quantity. What was actually observed in
that window is derived evidence, below.

## Measured response

### Reuse `metric_definitions` and `derived_measurements`

Both tables already exist and are currently written by no code path. They
provide exactly what response measurement needs: a metric vocabulary with units
and definitions, and a typed, provenance-bearing measurement owned by an
`analysis_run` with `derivation_details_json` for method settings.

Response measurements **reuse them** rather than adding a parallel measurement
table. This is the first real user of that machinery, and the same machinery is
the natural home for later attribution evidence.

Two extensions are required:

- `acoustic_reference_id` joins the exactly-one-target CHECK, so a measurement
  can be about a reference window;
- `recording_channel_id` is added as an optional **qualifier**, deliberately
  outside the target CHECK, because a channel is not a target — it is which
  channel a measurement of some target was taken on. A trigger constrains the
  channel to the same recording as the target where a recording is resolvable.

### Conservative metrics only

Every stored metric needs defined units, defined semantics, and method
provenance. The initial set is deliberately small and synthetically verifiable:
RMS amplitude, peak absolute amplitude, and band-limited power **only** when an
explicit valid band is supplied and the sample rate supports it.

No metric is added merely because it is computable. Native audio is never
modified, and extractor-reported power is never overwritten or treated as
interchangeable with a VAWLUME measurement.

### Estimates, not profiles

Aggregated per-channel response is stored as `channel_response_estimates` with a
supporting-evidence junction naming the measurements behind each estimate.

**The name avoids `profile` on purpose.** Everywhere else in VAWLUME a "profile"
is *authored configuration* — a versioned JSON document a user wrote, registered
in `config_profiles`. A channel-response summary is the opposite: it is derived
from measured evidence by an analysis run. Calling it a profile would put two
incompatible meanings on one word in a schema where profile provenance is already
load-bearing.

An estimate records which channels it describes, which measurements support it,
the aggregation method, frequency scope where relevant, a QC state, and analysis
provenance. It is not permitted to collapse to a single opaque gain number when
the evidence is frequency- or reference-dependent, and contradictory evidence
produces an explicit QC state rather than a silently averaged result.

## Bounded window access

### Two readers, not a framework

Tracking and audio each get one focused reader:

```text
vawlume.tracking.readWindow(conn, streamRef, interval, options)
vawlume.acoustic.readAudioWindow(conn, recordingRef, channel, interval)
```

**No generalized continuous-data access framework is built.** Two readers with
two concrete jobs is the whole requirement; a shared abstraction over exactly two
implementations would be speculative, and the live code gives no evidence it is
needed.

What they share is a **result-shape convention**, documented and followed, not
enforced by a common base class:

- the requested interval and the interval actually read, separately;
- the stream, timebase, and coordinate system (tracking) or recording, channel,
  and sample rate (audio), stated explicitly rather than assumed;
- an explicit status distinguishing the coverage cases below;
- native values preserved.

### Coverage states are three, not two

A reader must never let "no rows came back" mean "nothing happened". The
distinction mirrors the regularized-timeline rule the alignment contract
established, and the states are:

1. **covered and populated** — the interval is inside declared coverage and
   samples exist;
2. **covered but empty or invalid** — observation is established and the samples
   are missing or unusable, which is a QC finding;
3. **not covered** — declared coverage does not establish that anyone was
   observing, so absence means nothing at all.

Partial overlap with coverage is reported as partial, with the covered sub-interval
named. It is never rounded up to covered or down to absent.

### Compatibility is validated, never repaired

A reusable validation operation confirms that a tracking stream and a channel
placement cite the same coordinate system before any operation that would relate
them. Incompatible references fail with a clear identifier. Nothing is
transformed, rescaled, or reinterpreted to make a comparison possible.

### The alignment boundary

Window access uses the **existing** alignment transforms where a common-time
operation is already supported, and does nothing else.

If a requested operation needs a transform the alignment layer does not
implement — piecewise-affine, in particular — the reader returns a clear
unsupported status. It must not reimplement transform arithmetic locally, and it
must not degrade silently to a simpler model. Alignment robustification belongs
to a later phase and stays there.

## What is authoritative

| Question | Authority |
| --- | --- |
| Which spatial frame is this in? | the cited `coordinate_systems` row |
| Where was this microphone during this recording? | `channel_placements` for that channel |
| Where did the placement numbers come from? | the cited `config_profile_versions` row |
| What does this tracking stream contain? | `tracking_streams` + `tracking_series` |
| Where are the tracking samples? | the registered artifact, never the database |
| When was this stream observed? | `external_stream_coverage` |
| What signal is claimed in this window? | `acoustic_references` |
| What was actually measured there? | `derived_measurements` |
| What do repeated measurements imply for a channel? | `channel_response_estimates` |

Native observations remain immutable. Nothing in this layer writes to
`detections`, `event_measurements`, `recordings`, or any extractor-native table.

## Invariants

1. Spatial compatibility is coordinate-system **identity**; structural similarity
   is never sufficient.
2. No coordinate transformation exists between spatial systems.
3. `z` is present only when the cited system is 3D, and optional even then.
4. A placement belongs to one recording channel and therefore to one recording.
5. Reusable device and setup profiles are placement **provenance**, never
   placement authority.
6. No tracking sample is stored in SQLite.
7. Native entity and bodypart labels are always preserved; canonical roles are
   additive and optional.
8. Tracking confidence is optional, and its absence is reported, never imputed.
9. An acoustic reference is stated in the recording's native audio clock.
10. `reference_type` is open text; no reference type is mandatory or privileged.
11. An acoustic reference and an alignment anchor are distinct objects and are
    never inferred from one another.
12. A reference stores its claim; measurement stores what was observed.
13. Every stored metric has defined units, defined semantics, and method
    provenance.
14. Raw audio is never modified, and extractor-reported values are never
    overwritten.
15. Absence of data is reported against declared coverage, never as an implicit
    zero or an implicit "no event".
16. No caller-attribution concept — candidate, score, probability, assignment —
    appears anywhere in this layer.

## Non-goals

Not in this layer:

- raw-video ingestion, pose estimation, or any pixel processing;
- caller attribution, caller candidates, caller probabilities, or assignment;
- localization backends or USVCAM-specific structures;
- spatial transformations, registration, or projection between frames;
- a universal bodypart, subject, or reference-type ontology;
- dense tracking or audio samples materialized into SQLite;
- a generalized continuous-data access framework;
- a universal multimodal matcher;
- piecewise-affine or drift-aware alignment robustification;
- mandatory calibration hardware or a mandatory reference type;
- automatic correction or rewriting of user tracking artifacts;
- a calibrated acoustic normalization model presented as validated.

## Known boundaries recorded at design time

These are deliberate stopping points, not oversights:

1. **Pixel coordinate systems compute no real distance.** A later metric
   requirement or an explicit scale is needed, and must be explicit.
2. **Placement has no intra-recording history.** A microphone moved mid-session is
   unrepresentable.
3. **Only audio channels are placed.** Cameras and arena landmarks are not.
4. **Compatibility is declaration-checked, not physically verified.** VAWLUME
   confirms two facts cite one system; it cannot confirm the user measured them
   in one.
5. **No spatial uncertainty model.** Tracking confidence is carried as a native
   value, not propagated into any error estimate.
6. **Response estimates are uncalibrated evidence.** They preserve what was
   measured under a stated method. They are not a validated calibration and must
   never be reported as one.
7. **Validation will be synthetic.** As with every prototype phase so far, correct
   arithmetic on generated inputs says nothing about real hardware.
