# Backend Localization Contract

## Status

Design contract for **Phase 5 — the backend/localization attribution path**
(Path B). Written by itinerary 5.1 before any Phase 5 code exists, so that the
decisions below are made once rather than negotiated by each later itinerary.

Written against schema `0.11-draft` (`PRAGMA user_version = 11`). Phase 5 plans
exactly one version bump, to `0.12-draft` (`PRAGMA user_version = 12`), owned by
itinerary 5.2 (D12). **Itinerary 5.2 applied it.** Phase 6's one bump, applied
at 6.2 for the native estimator
([`06_native_estimator_contract.md`](06_native_estimator_contract.md) D14), makes
the live schema `0.13-draft` (`PRAGMA user_version = 13`). The DDL realizing D1, D3, D4, D6, D7 and D13 is documented in
[`../development/31_caller_attribution_schema.md`](../development/31_caller_attribution_schema.md).

The contract clauses below are frozen as written. This status block is not: it
names the live schema, and it moves when the version moves. The Phase 4
contract set that precedent. **Nothing machine-checks it.**
`check_repository_self_description` exempts all of `docs/design/` from its
version check, which is how the Phase 4 contract's status block came to claim
`0.10-draft` for a whole workstream after `0.11-draft` landed. The itinerary that
bumps the schema moves this block by hand.

This contract **extends** [`04_caller_attribution_contract.md`](04_caller_attribution_contract.md);
it does not replace it. Every Phase 4 clause holds for a backend run unless a
clause here says otherwise, and none does. Where this document departs from the
recommendation in the 5.1 itinerary, the clause says so and says why.

This contract governs what a backend's output **means** once it is inside
VAWLUME, and what the representation must keep distinguishable. It does not
describe a localization method. VAWLUME localizes nothing in Phase 5.

**The phase's one-sentence position:** VAWLUME can hold a localization backend's
claim about where a sound came from and who made it, in the frame the backend
measured it in, with the backend's own numbers and producer named. It can relate
that claim to its own calls without computing anything spatial itself.

## What this phase is for

Plan §18 states the reason the backend path comes before the native estimator:

> A backend path provides another test of the canonical attribution boundary and
> can expose requirements that would otherwise become hard-coded into the native
> estimator.

Phase 4 has already used that test once, at its own close. It found three
things the canonical model cannot hold (`phase_4.13_handoff.md` §12):

1. `attribution_evidence` cannot store a localization coordinate, and cannot name
   the coordinate system one is expressed in;
2. `attribution_evidence` cannot name the `recording_channel_id` its evidence
   came from;
3. `evidence_dimension` has no member for acoustic source localization.

These three are the phase's spine. Everything else in Phase 5 is reuse: the
mapping-profile machinery, `correspondWindows`, `addCandidates`, `decide` and
`report` already work for a run whose `attribution_path` is `backend`.

The second purpose is plan §15.3's. A USVCAM-like export is the motivating case,
and the schema must not become USVCAM-shaped. One adapter cannot tell "general"
from "fitted to the first backend it met". Two can, which is why itinerary 5.8
maps a structurally different second backend before the demonstration.

## Core vocabulary

These distinctions are the contract. Everything in the Decisions section follows
from them.

### "Imported" means produced outside VAWLUME

The attribution schema uses *imported* for one property: **the row records
something an external system produced, brought in through a mapping profile.**
It does not mean "came from the generic imported path".

A localization backend's output has exactly that property. VAWLUME does not run
the backend; it reads the backend's export. So a backend's own segmentation
belongs in `imported_attribution_windows`, and its caller claims belong in
`imported_attribution_claims`, without strain (D5).

Which *kind* of external system produced a run is a separate fact. It lives on
`attribution_runs.attribution_path` (`imported`, `backend`, `native_estimate`),
which the schema has admitted since `0.9-draft`. Path C, the native estimator,
will never write an imported window, because it targets VAWLUME's own events
directly. That is what keeps the word honest.

### A backend is a producer, not a parallel path through the schema

Plan §17 draws three attribution paths converging on one canonical result.
Phase 5 takes that literally. A backend run uses the same run, target, window,
claim, correspondence, candidate, evidence and decision tables as an imported
run. What a backend adds is **content those tables could not hold**: coordinates
with a frame, a channel citation, and native fields. Each gets the smallest
addition that holds it, and **no table, column or vocabulary member is named
after a backend** (§15.3).

### A source localization is not a pose

`pose_localization` means *where a tracked bodypart is* (plan §4.5). It is
uncertainty about a visual trajectory.

A backend's localization estimate means *where a sound originated*, as a
spatial-acoustic system computed it. It may be close to a snout position. That
closeness is the hypothesis a caller-attribution analysis tests, so the
representation must not assume it. Storing a source localization as a pose would
make the hypothesis look like its own evidence (D3).

### A position is not a distance

VAWLUME stores the coordinates a backend reported and validates the frame they
claim. It computes no distance, angle, bearing, nearest animal, or any other
geometric derivation (D11). "Distance to microphone" is plan §4.5's reusable
primitive and §11.3's *Phase 6 evidence*, and it belongs where its consumer is.

### A frame is part of the coordinate

A pair of numbers without a declared coordinate system is not a weak coordinate.
It is not a coordinate. Phase 2 built `coordinate_systems` so that every spatial
fact names its frame. Compatibility is **identity** of `coordinate_system_id`,
never structural similarity (`23_spatial_geometry_schema.md`). A localization
estimate that could not name its frame would be the only spatial fact in the
repository that does not (D1).

### A localization confidence is not a caller probability

A backend may report how confident it is in *where* a sound came from, and
separately how strongly it attributes the sound to *whom*. These are different
quantities on different scales. They are stored in different tables, and neither
can be read as the other (D1, D2).

### A claim is not a candidate, and an estimate is not evidence, until promoted

This extends the Phase 4 contract's "a candidate is not a decision", and it is
the clause most likely to be got wrong.

At intake, a backend's output has a **window grain**. Its caller score is about
(backend window, claimed caller). Its localization estimate is about (backend
window, optionally a claimed caller). No VAWLUME target exists yet: relating a
window to a VAWLUME event is correspondence, and correspondence happens later.

Attribution has a **target grain**. A candidate is about (target, entity). An
evidence row is about a target or a candidate.

Crossing from the first grain to the second is a policy question: which
correspondence is good enough to carry this claim, or this estimate, onto this
target? Phase 4 answered that for claims by never crossing implicitly.
`vawlume.attribution.addCandidates` is the explicit path. Phase 5 answers it the
same way for estimates. `vawlume.attribution.addEvidence` is the explicit path.
Neither intake nor correspondence promotes anything (D2, D3).

### A native field is not a canonical field

A backend's own fields are preserved where the profile asks, in a table
separate from every canonical column (D6). Nothing downstream may mistake a
backend's `conf_v2` for a canonical confidence. The separation is what enforces
that.

---

## Decisions

Itinerary 5.1 posed twelve questions (Q1–Q12). D1–D12 answer them, though not
in the same order, because D1 and D2 depend on each other. D13–D15 answer
questions the live repository raised that the itinerary did not pose.

| Itinerary question | Decision | Departs from recommendation? |
|---|---|---|
| Q1 localization representation | D1 | **Yes, in the link.** A new table, as recommended, but keyed to the backend window rather than to a candidate or target |
| Q2 `evidence_dimension` member | D3 | No. Named `source_localization` |
| Q3 `attribution_evidence.recording_channel_id` | D4 | No |
| Q4 keep `imported_attribution_windows` | D5 | No, and the reason is stronger than the recommendation gave |
| Q5 native fields | D6 | No. A long-form typed table with no JSON value type |
| Q6 P4-3 rides the bump | D8 | **Yes. Declined** |
| Q7 P4-2 rides the bump | D9 | No. Declined |
| Q8 caller score: candidate or evidence | D2 | **Yes, in the mechanism.** A claim at intake, then a candidate by explicit promotion |
| Q9 spatial correspondence term | D10 | No |
| Q10 distance or geometry | D11 | No |
| Q11 declared modalities | D7 | Refined: a long-form table, a four-member closed vocabulary, used by both paths |
| Q12 the version bump | D12 | **Yes, in the numbers.** `0.11` is already taken; the bump is `0.11-draft` → `0.12-draft` |

### D1. A localization estimate is a row of its own, keyed to the backend window that produced it

**Closes the first inherited gap.** A new table,
`attribution_localization_estimates`, one row per estimate:

| Column | Rule | Why |
|---|---|---|
| `attribution_localization_estimate_id` | primary key | |
| `imported_attribution_window_id` | **NOT NULL**, FK, `ON DELETE CASCADE` | An estimate belongs to the backend segment it was computed over |
| `imported_attribution_claim_id` | nullable FK, `ON DELETE CASCADE` | Set when the backend tied this estimate to a claimed caller; a trigger requires the claim to belong to the same window |
| `estimate_ordinal` | NOT NULL, `>= 1`; `UNIQUE(imported_attribution_window_id, estimate_ordinal)` | A backend may report several localization candidates for one window (plan §9.2). The ordinal is the backend's order, not a VAWLUME ranking |
| `native_estimate_id` | nullable text, verbatim | The backend's own identifier, never interpreted |
| `coordinate_system_id` | **NOT NULL**, FK, `ON DELETE RESTRICT` | The frame is part of the coordinate. RESTRICT for the reason `channel_placements` gives: a coordinate whose frame vanished is in no declared space |
| `position_x`, `position_y` | **NOT NULL** real | An estimate with no position is not an estimate |
| `position_z` | nullable real; permitted only under a 3-dimensional frame | A 2D backend stores NULL, never `0`: a zero claims a measurement on a plane the backend never estimated |
| `position_semantics` | **NOT NULL** text | What point this is, and who computed it, for example *"estimated sound-source location; producer=…; not a bodypart position"* |
| `confidence` | nullable real, **unconstrained** | The backend's scale; VAWLUME does not know its range, as with `attribution_candidates.score` |
| `confidence_semantics` | required whenever `confidence` is present (CHECK) | A number without stated semantics is not interpretable evidence. P3-1 exists because that rule was once applied unevenly |
| `source_file_id`, `mapping_profile_version_id`, `source_locator`, `notes` | as on `imported_attribution_windows` | Every stored number traces to its bytes |

Triggers, following the established patterns:

- **dimensionality**, insert and update: `position_z` only under a frame whose
  `dimensionality = 3`. Copied from `trg_channel_placement_dimensionality` and its
  `_update` twin, for the reason given there: without the update guard, a row
  inserted legally could later be given a `z`, or have its frame repointed.
- **project scope**: the frame belongs to the project of the window's
  recording. This is the same class of guard as
  `trg_channel_placement_project_scope` and `trg_tracking_stream_project_scope`.
- **claim scope**: a cited claim belongs to the same window.

**Rejected: widening `attribution_evidence` with coordinate columns** (Q1 option
b). The table is deliberately long-form, one value per row. Every non-spatial
evidence row would carry four permanently NULL columns, the "weakly defined
nullable columns" plan §5 warns against.

**Rejected: three long-form evidence rows, one per axis** (option c). Nothing
would say that the three rows are one estimate, and nothing would tie them to one
frame.

**Departure from the recommendation: the link.** The itinerary proposed linking an
estimate "to the candidate or target". At intake neither exists. A backend
estimate is computed over the backend's own window, and which VAWLUME event that
window refers to is decided later by correspondence, possibly ambiguously. Keying
the estimate to a candidate would force intake to choose a target, which is
exactly the policy question correspondence exists to leave open.

The repository has made this mistake once already. **P4-5**: through `0.9-draft`
the imported path parsed an exporter's score and then had nowhere to put it,
because a candidate belongs to (target, entity) and an imported claim belongs to
(window, entity). The number was discarded at intake.
`imported_attribution_claims` was created at `0.10-draft` to hold it before
correspondence. A localization estimate has the same grain problem. It gets the
same answer, from the start rather than after a second bump. It reaches a
target only by explicit promotion (D3).

**One estimate is a window-level summary.** A time-resolved localization track
(a position per frame within a call) is dense data. Like dense tracking samples
and dense identity traces, it stays in the registered artifact, under the
multimodal input contract's storage policy. A backend that reports only a dense
track and no summary has nothing for this table to hold. Itinerary 5.8 records
that case if it meets it; nothing here invents a summary for it.

### D2. A backend's caller score is a claim at intake, and a candidate only by explicit promotion

**Departs from the recommendation in mechanism, agrees in outcome.** The
itinerary recommended that the score be "a candidate", arguing that routing it
to `attribution_candidates` is what keeps `decide` unchanged, and that "the
imported path's symmetry is the point". The symmetry *is* the point. But the
imported path does not write candidates at intake. It writes
`imported_attribution_claims` rows, at (window, entity) grain, and leaves
promotion to `addCandidates` (P4-5, and the `vawlume.ingest.attribution` help
text: *"No candidate or evidence row is written."*).

So, for a backend:

1. **intake** writes each (window, claimed caller, score/probability) to
   `imported_attribution_claims`, through the same declared-only label
   resolution against the run's participant snapshot;
2. **correspondence** relates windows to targets, unchanged;
3. **promotion** to `attribution_candidates` is an explicit
   `vawlume.attribution.addCandidates` call;
4. **`decide`** then runs unchanged, because the candidates it reads are
   ordinary candidates.

The recommendation's outcome survives: `decide` works over a backend run
without change, which 5.6 verifies. Its mechanism does not. Writing candidates
at intake would assert that every window's claim applies to whichever event the
importer guessed.

The score/probability discipline is unchanged. The score is unconstrained, and
the probability is bounded because the word means something. Nothing converts
between them. A label with no number stores NULL, never `1.0`. The semantics
string **names its producer**, through the existing `{producer}` rendering.

### D3. `evidence_dimension` gains `source_localization`, and an evidence row cites its estimate rather than copying it

**Closes the third inherited gap.** `attribution_evidence.evidence_dimension`
gains one member, `source_localization`: *a spatial estimate of where a sound
originated, produced by an external system.*

| Member | Means | Not |
|---|---|---|
| `pose_localization` | where a tracked bodypart is | where a sound came from |
| `acoustic` | an acoustic measurement, such as a channel level or a spectral quantity | a position |
| `source_localization` | where a sound originated, per an external spatial-acoustic estimate | a bodypart position, or an acoustic measurement |

**This is a deliberate widening of a closed vocabulary.** The vocabulary is
closed because that is what makes the separation claim assertable, and 4.13 held
it closed on that ground. It is widened once here, by decision, with the schema
comment saying what the new member means and how it differs from
`pose_localization`.

**The separation claim is now about five evidence dimensions.** Precisely:

- plan §4.6 names **four upstream uncertainty sources**: temporal alignment,
  pose/localization, visual identity, and acoustic/caller evidence. These stay
  four. The phrase "the four uncertainty dimensions" remains correct wherever it
  refers to them;
- `evidence_dimension` now has **five separated evidence dimensions**: those four
  plus `source_localization`. It also has two members that are not dimensions:
  `correspondence`, and `imported_composite` for somebody else's already-combined
  number;
- **VAWLUME combines none of the five.** A source localization sits beside pose,
  identity, acoustic and temporal evidence, and nothing in `src/` computes a
  function of it and any other dimension.

So "the four evidence dimensions" becomes false in any sentence that describes
the vocabulary, and "the four uncertainty dimensions" stays true. Itinerary 5.5
owns the sweep and must judge each occurrence by which of the two it means. It
must sweep for the literal word, not from memory.

**An evidence row cites the estimate; it does not copy it.** `attribution_evidence`
gains `attribution_localization_estimate_id` (nullable FK, `ON DELETE CASCADE`)
with a CHECK making the relationship two-way:

```sql
CHECK ((evidence_dimension = 'source_localization')
     = (attribution_localization_estimate_id IS NOT NULL))
```

A `source_localization` row must cite an estimate, and no other dimension may.
The row carries no copied coordinate and no copied confidence. Its `value_real`
and `value_text` are NULL, because the estimate is the authority, and the
repository's rule is that a quantity readable from its authority does not get a
second home. CASCADE rather than SET NULL, because the CHECK makes an orphaned
`source_localization` row illegal. An evidence row about an estimate that no
longer exists says nothing.

A trigger requires the cited estimate's window to belong to the **same
attribution run** as the evidence row's target. That is a scope rule. The
workflow rules (that a stored correspondence exists between the estimate's
window and the target, and that an estimate tied to a claimed caller supports
only that caller's candidate) are `addEvidence` refusals, owned by 5.5. The
split is the Phase 4 one: the schema refuses false claims, and the API refuses
unsupported ones.

### D4. `attribution_evidence` gains `recording_channel_id`, scope-guarded

**Closes the second inherited gap.** A nullable FK to `recording_channels`, with
`ON DELETE CASCADE` as on `derived_measurements`. The channel is part of what a
per-channel evidence row *is*, not merely where it came from, so the row
does not outlive it.

Guarded by an insert trigger **and an `_update` twin**: the channel must belong to
the recording of the evidence row's attribution run. The attribution slice's
triggers are otherwise insert-only, by the repository-wide convention in schema
§14. The twin is justified under that convention's own exception. Repointing a
channel changes what the row claims was measured, not just where it is filed,
and `derived_measurements` guards its channel both ways for the same reason.

**A channel index is a caller assertion about the acquisition.** Intake resolves
the backend's channel index against the recording's declared channels. Nothing
inspects the audio to confirm that the backend's numbering matches the
recording's, and the documentation must say so rather than imply a check.

### D5. `imported_attribution_windows` keeps its name

**Agrees with the recommendation, for a reason stronger than the one it gave.**
The itinerary framed keeping the name as accepting "a name that needs explaining
for the rest of the project's life". Under the core vocabulary's definition, the
name is accurate. A backend's segmentation was produced outside VAWLUME and
brought in through a profile, which is what *imported* means in this schema. The
explanation is one sentence, and it is written once, here and in the schema
comment.

**Rejected: renaming to a path-neutral name** (option b). The cost is larger than
the itinerary estimated. Since Phase 4 closed, the CSV-export workstream has made
`schema/schema_metadata.json` the single authority for what every column means,
with a completeness gate, and has generated `schema/schema.json` from the DDL. A
rename now touches the DDL, both schema artifacts, `+attribution/`,
`+ingest/`, `+db/`, three development documents, the usage guide, and every FK column
named `imported_attribution_window_id`: in `imported_attribution_claims`,
`attribution_window_correspondences`, and every Phase 5 table that cites a
window. The benefit is a name that is no more accurate.

**Rejected outright: a parallel backend-window table** (option c). It is the
parallel result model this phase exists to refuse.

**Consequence, accepted knowingly:** Phase 5's new tables cite windows through a
column named `imported_attribution_window_id`. That is correct under the
definition above.

### D6. Backend-native fields live in a long-form typed attribute table, with no JSON value type

**Agrees with the recommendation.** A new table, `attribution_native_attributes`,
following `entity_attributes` and `external_event_attributes`:

- **exactly one owner**, by the exclusive-target CHECK that `attribution_targets`,
  `manual_reviews` and `consilience_assessments` use: one of
  `imported_attribution_window_id`, `imported_attribution_claim_id`,
  `attribution_localization_estimate_id`. A native field describes a window, a
  claim, or an estimate, and the row says which. All three FKs are
  `ON DELETE CASCADE`;
- `attribute_name` (the profile's name for the field), `native_field_name` (the
  source's own column name, verbatim), `unit`, `source_locator`, and
  `mapping_rule_key`;
- `value_type IN ('text','real','integer','boolean','missing')` with typed value
  columns and the exactly-one-value CHECK, so `missing` stays distinguishable from
  absent;
- `native_raw_token`: the source token verbatim, as on
  `external_event_attributes`;
- one value per (owner, `attribute_name`), enforced by three partial unique
  indexes, because a UNIQUE over nullable owner columns does not constrain in
  SQLite.

**`json` is deliberately not a value type.** `external_event_attributes` admits
it; this table does not. **P4-2** is the ledger item created by choosing JSON
once, and this phase does not create a second. A structured native field, such
as a covariance matrix, is preserved as several named scalar attributes, or as
`native_raw_token` text, by the profile's declaration (D15).

The table is **path-neutral by name and by shape**. Nothing in it is
backend-specific, and the imported path may use it later without a schema
change. Phase 5 does not retrofit the imported intake to write it.

### D7. A producer may declare which evidence dimensions it consumed, and the declaration is stored with the run

**Closes the mechanism the 4.12a correction deferred to Phase 5.** The Phase 4
contract records, corrected in place: *"Nothing records which of the four
dimensions an exporting system used."* It declined a field at 4.12a because
nothing would read it, and said Phase 5 *"should design it once for both"*.
Phase 5 has the reader. 5.7's QC and the report reader need it to tell what a
backend's score already consumed. Phase 7 needs it to compare paths.

A new table, `attribution_run_declared_inputs`:

| Column | Rule |
|---|---|
| `attribution_run_id` | NOT NULL FK, `ON DELETE CASCADE` |
| `input_dimension` | NOT NULL, closed: `temporal_alignment`, `pose_localization`, `visual_identity`, `acoustic` |
| `declaration` | NOT NULL, closed: `used`, `not_used` |
| `declared_by_profile_version_id` | NOT NULL FK to `config_profile_versions`, `ON DELETE RESTRICT`: a declaration with no source is an opinion with no provenance |
| `notes` | |
| | `PRIMARY KEY(attribution_run_id, input_dimension)` |

Three states, not two. **No row means undeclared**, and that is not the same as
`not_used`. The profile field is optional, because a user who does not know what
a backend consumed must not be made to guess. A reader shown an undeclared
dimension is told "unknown", never "no".

**The vocabulary is plan §4.6's four uncertainty sources, not the five evidence
dimensions.** The question being answered is which of VAWLUME's own evidence
families the producer had *already consumed*. `source_localization` is a
backend's *output*. If a later producer consumes another system's source
localization (a Phase 6 estimator reading a backend's estimate, say), widening
this vocabulary is a deliberate act for that phase.

**Rejected: a column on `attribution_runs`.** A list in one column is JSON, which
is P4-2 again, or a delimited string. The 4.13 ledger already carries a `|`-join
defect, and a synthesized `|`-joined label was dropped from
`imported_attribution_windows` at `0.10-draft` for being a string no source
contained.

**Rejected: inferring the declaration from the producer's name.** That is the
inference the optional field exists to replace.

**Designed for both paths**, as 4.12a asked. The table is keyed by run, not by
path. 5.3 adds the optional declaration block to the backend profile language,
and 5.4 writes it at backend intake. Extending the generic imported profile to
declare the same block is small and well-defined, but it changes a shipped Phase 4
profile contract. It is **deferred**, not scheduled, and recorded in the delta
plan.

### D8. P4-3 does not ride this bump

**Departs from the recommendation.** P4-3: `attribution_evidence` cannot
relationally cite a general analysis run, artifact, or stream.

The recommendation was "yes, because 5.2 must widen that exact table anyway and a
backend's evidence wants to cite the analysis run and artifact it came from". The
itinerary sets a test for P4-2: *say what breaks without it in Phase 5
specifically. "The DDL is open" is not a reason.* That test should apply to P4-3
as well. Applied, it finds nothing in Phase 5 that breaks:

- a backend's localization evidence cites its **estimate** (D3), which cites its
  source file, profile version and locator (D1);
- a backend's per-channel evidence cites its **channel** (D4) and its source
  file;
- a backend's identity evidence cites its **identity association**, as Phase 4
  already allows;
- the backend run's own analysis run is the attribution run's `analysis_run_id`,
  so citing it per row would be a second copy of one fact.

P4-3's own ledger text notes that the Phase 4 demonstration's fourth dimension
cited no relation. With D4, a backend's acoustic evidence does cite one.

The real consumer of "evidence cites an analysis run" is **Phase 6's native
estimator**. Its acoustic evidence will be derived from VAWLUME's own
`derived_measurements` and `channel_response_estimates`, and the right citation
there may well be a `derived_measurement_id` rather than an `analysis_run_id`.
Choosing the column now would be choosing it for an estimator nobody has
written. The Phase 4 contract names that as the failure the phase order exists
to avoid.

**If the user has already decided otherwise**, the contingent shape is recorded
in the delta plan as a 5.2 item that is ready to apply. The cost of reversing
this decision is three nullable FK columns, their metadata descriptions and
their tests, all inside the same bump.

### D9. P4-2 does not ride this bump

**Agrees with the recommendation.** Run source and participant snapshots stay
canonical JSON. P4-2 belongs to a different subsystem, and nearby schema work is
not a reason to take unrelated schema work. 4.9a refused the same temptation.

**What Phase 5 specifically loses, said plainly:** a backend's own settings file,
supplied through `createRun`'s `sources`, is recorded only inside the run's JSON
source snapshot. It is not a relational link: the schema has no run-to-source-file
or run-to-artifact table, and the relational input links cover only extraction and
analysis runs (`31_caller_attribution_schema.md`). It remains readable, since `report`
returns the decoded envelope, and the producer and version are named in every
semantics string (D2). It is not queryable by join. That is a cost, not a
breakage, and P4-2's existing disposition covers it.

### D10. Correspondence gains no spatial term

**Agrees with the recommendation.** `correspondWindows` asks whether a backend
window refers to a call VAWLUME knows about. That is a temporal question. A
spatial eligibility term would make it a caller judgement in disguise. The
correspondence layer deliberately reads no caller label for exactly this reason.
A shared primitive acquiring a domain term is also the UniversalMatcher §14
forbids. If spatial correspondence proves valuable, it is a Phase 7 question.

### D11. Phase 5 computes no distance, angle, or geometric derivation

**Agrees with the recommendation, and says so explicitly** because plan §4.5
lists "distance to microphone/reference point" as a reusable primitive. A later
reader will reasonably ask why Phase 5, the first phase to hold a sound-source
coordinate, did not build it.

The answer is plan §11.3: distance is **Phase 6 evidence**. Building a primitive
whose only consumer does not exist yet is how a representation ends up fitted to
an estimator nobody has written. VAWLUME computes no distances today, and
Phase 5 does not start.

What Phase 5 does with geometry is **validate frames**:

- every estimate names its frame (D1);
- **comparing estimates across frames is refused** through
  `vawlume.geometry.assertCompatible`, which compares identifiers and nothing
  else;
- **nothing is transformed between frames.** No rotation, translation, rescaling
  or projection. If a backend's frame and the tracking frame genuinely describe
  one space, the fix is upstream: declare and use one frame. A `px` frame stays a
  `px` frame and supports no real-distance claim.

A frame belonging to another project and a frame that does not exist are
**different refusals with different names**, because they are different problems.

### D12. One version bump: `0.11-draft` → `0.12-draft`, owned by 5.2

**Departs from the itinerary in the numbers, not the discipline.** The itinerary
map and the 5.1 and 5.2 itineraries were drafted on 2026-09-15 against Phase 4's
closing state at `8982412`, schema `0.10-draft`. Since then the CSV-export
workstream took `0.11-draft` for schema hygiene (commit `47d8f6b`, "csv export
Part 3i"). Phase 5's bump is therefore **`0.11-draft` → `0.12-draft`,
`PRAGMA user_version = 12`**. Every Phase 5 itinerary that says `0.11` means
`0.12`.

**One bump, owned by 5.2.** 5.3 through 5.11 each carry a tripwire that
`schema/schema.sql` is unchanged. An itinerary that believes it needs a second
bump stops and records what must close before the phase candidate, and why no
earlier itinerary could have taken it. That is the discipline 4.9a followed.

**What moves with the bump is more than it was at Phase 4**, and 5.2 owns all of
it:

1. the three spellings in `schema/schema.sql` (header, `schema_info` seed,
   `PRAGMA`), checked for agreement;
2. `schema/schema_metadata.json`: `schema_version`, a description for every new
   table, column and relationship (assigned to the existing `attribution`
   domain), a revisit of every description the change invalidates
   (`attribution_evidence.evidence_dimension` above all), and a
   `metadata_version` bump. `validateMetadata(Mode="complete")` fails until
   coverage is whole;
3. `schema/schema.json`, regenerated with `schema_documentation`, never
   hand-edited;
4. every current-state document that states the relational version with its
   `user_version`. Today that is the usage guide's status line. The
   self-description check enforces this, and its failing is the intended
   behaviour;
5. the status blocks of this contract and the Phase 4 contract, which nothing
   checks.

**The CSV export needs no change.** It discovers objects from the live schema and
describes them from `schema_metadata.json`, so new tables are exported once the
metadata covers them. 5.2 should confirm that with one export of a migrated
fixture rather than assume it.

### D13. Backend intake is `vawlume.ingest.backendAttribution`, mapping through profile kind `attribution_backend_mapping`

**Answers what the 5.3 and 5.4 itineraries left to 5.1.**

- **Profile kind `attribution_backend_mapping`**, added to
  `config_profiles.profile_kind` by 5.2 and to the source-mapping dispatch by 5.3.
  This departs from 5.3's suggested `backend_localization_mapping`. A backend
  that scores callers but localizes nothing is a legitimate shape that 5.8 may
  test, and a kind named for localization would mislabel it. The `attribution_`
  prefix matches `attribution_input_mapping` and `attribution_policy`.
- **A new kind, not a widened `attribution_input_mapping`.** The generic
  imported profile is a shipped, tested contract
  (`profile_schema_version` `0.3-draft`). Widening it would give every Phase 4
  profile spatial semantics it was never validated for. A new kind costs one
  dispatch `case` and one mapper file. `mapTableToIR` dispatches on kind, which
  is a dispatch table rather than a mode flag, and the shared mapper takes no new
  parameter.
- **A new public entry point, `vawlume.ingest.backendAttribution`**, beside
  `vawlume.ingest.attribution`. The two have different run preconditions,
  different resolutions (frames, channels and track associations exist only on
  the backend side) and different result shapes. One function switching on path
  would be the switch-laden entry point §14 warns against.
- **Path and kind must agree.** `backendAttribution` accepts only a run whose
  `attribution_path` is `backend` and a profile of kind
  `attribution_backend_mapping`. `vawlume.ingest.attribution` keeps its existing
  `imported`-only rule. A mismatch is refused by name.
- **Shared rules are shared code, not copies.** Declared-only label resolution,
  preserved source values, producer rendering, unmappable-row reporting and
  source-file provenance must be one implementation used by both intake paths.
  Where they currently live inside the imported path's private functions, 5.3 or
  5.4 extracts them, with bit-identical imported behaviour as the bar. P3-2
  records the cost of keeping two implementations in agreement by duplication.

### D14. A backend window is the backend's own reported interval; an echoed VAWLUME ID is not a target

A backend may segment calls itself, or it may localize the calls VAWLUME already
detected and echo their IDs back. In both cases the window stores **the interval
the backend reports**, on the backend's own clock, with `native_window_id`
verbatim.

An echoed ID is **never interpreted as a VAWLUME detection ID**, even when it
looks like one. The shipped imported profile already says this of
`native_window_id`. Relating the window to the event it names is correspondence,
usually with `SameClock`, and it will normally be a clean one-to-one result.
That clean result is evidence that the backend used VAWLUME's windows. Treating
the ID as a key would assume it.

A backend that reports an event reference and **no interval at all** has nothing
`imported_attribution_windows` can hold, because native times are NOT NULL by
design. Phase 5 does not build a target-keyed shortcut for it. If 5.8's second
shape is such a backend, that is a finding to record, with the smallest fix and
whether that fix would be backend-specific.

### D15. Positional uncertainty richer than one scalar is preserved, not canonicalized

D1 gives an estimate one canonical scalar `confidence` with declared semantics.
A backend may instead report per-axis standard deviations, a covariance, or an
error ellipse. Plan §11.3 names "calibrated or estimated positional error" as
Phase 6 evidence.

**Phase 5 adds no canonical columns for it.** Such quantities are preserved as
native attributes on the estimate (D6), by the profile's declaration, with their
native names and units. Canonical columns stay conservative (§10). A covariance
is the case most likely to have nowhere good to go, and the honest response is
to preserve it legibly rather than invent a canonical shape for a consumer that
does not exist. 5.8 tests whether this is adequate and records the gap if it is
not.

---

## The uncertainty position

**Phase 5 declines the permission to combine evidence dimensions**, as Phase 4
did, and for the same reason. A backend's confidence and a backend's caller score
are numbers it already produced, by a method VAWLUME did not run and cannot
inspect. Recomputing, re-weighting or re-normalizing them destroys the only
property that makes them auditable: that they are still the backend's numbers.

So a backend result carries, unmerged:

- the backend's own claims, with their scores or probabilities and semantics
  naming the producer (D2);
- the backend's localization estimates, each in its declared frame, with the
  backend's own confidence and semantics (D1);
- whichever of the five evidence dimensions have been promoted onto targets and
  candidates, each as its own rows (D3);
- **and, newly, the backend's declaration of which uncertainty sources it had
  already consumed**, where the profile declares one (D7). This answers the
  question the 4.12a correction left open: a reader can now tell, when the
  producer said so, whether a backend score already used the acoustic evidence
  VAWLUME also holds.

The five conditions a method must state to exercise the permission are frozen in
the Phase 4 contract and in `phase_4.13_handoff.md` §12. They are not restated
here, and they now apply to five dimensions rather than four. Phase 6 inherits
them.

## Phase 5 non-goals

- estimating a caller from VAWLUME's own acoustic, pose, or identity evidence
  (Phase 6);
- computing any distance, angle, bearing, nearest-animal assignment, or other
  geometric derivation (D11);
- transforming coordinates between frames;
- a USVCAM-specific schema (§15.3), or a parser suite for any named commercial
  backend (§15.11);
- computing any combination of the five evidence dimensions;
- presenting a normalized evidence score, or a localization confidence, as a
  calibrated probability;
- a calibrated acceptance threshold, or any status meaning `validated`;
- forcing one caller per event, or a single `caller_id` column;
- a UniversalMatcher, or a spatial term in interval correspondence (D10);
- raw-video ingestion, pose estimation, or image-based re-identification;
- dense tracking-sample, dense identity, or dense localization materialization
  (D1);
- overwriting native timestamps, native coordinates, or native scores;
- P4-3 (D8) and P4-2 (D9);
- comparing a backend result against an imported one, or any cross-path
  comparison or sensitivity analysis (Phase 7).

## Inherited schema audit

What Phase 5 builds on, and what it must not disturb.

### Already correct — preserve

- **`attribution_runs.attribution_path`** already admits `backend`, and
  `createRun` does not constrain the path. No schema change is needed to create a
  backend run. `createRun`'s help text still says *"currently imported"*, which is
  stale (5.6).

  **Corrected at 5.10a.** The second sentence of this bullet was wrong about the
  tree it audited. The schema admitted `backend`, but `createRun` did constrain
  the path: before Phase 5 its plan builder refused every `attribution_path`
  except `imported` ("Phase 4 creates imported attribution runs only"). The help
  text was accurate, not stale. Itinerary 5.4 found this (F5.4-1) and admitted
  `backend`; `native_estimate` is still refused. The gap table's `createRun` row
  below therefore understated the gap: it was a two-line code change owned by 5.4,
  not a help-text change owned by 5.6. No schema change was needed, as stated.
- **`imported_attribution_windows`**: native times, never overwritten, keyed by
  `native_window_id` per run. It holds a backend's segmentation unchanged (D5).
- **`imported_attribution_claims`**: (window, entity) grain, score and
  probability disciplines, NULL never `1.0`, declared-only resolution. It holds a
  backend's caller scores unchanged (D2).
- **`attribution_window_correspondences` and `correspondWindows`**: clock
  declaration required (`AlignmentRun` or `SameClock`), ambiguity and
  extrapolation preserved, attribution's own eligibility rule. Unchanged (D10).
- **`attribution_candidates`, `attribution_decisions`,
  `attribution_decision_candidates`**: set-valued decisions, status-to-cardinality
  triggers in all three directions (the delete direction was added at
  `0.11-draft`, which closed the 4.13 ledger item "decision cardinality not
  re-checked on DELETE"), and policy retention. Unchanged.
- **`coordinate_systems`**: compatibility by identity, no transforms, unit as
  free text never interpreted. D1 and D11 build on it.
- **`channel_placements`**: its dimensionality and project-scope trigger pattern
  is what D1 copies.
- **`derived_measurements`**: its channel-scope trigger pair is what D4 copies.
- **`external_event_attributes` / `entity_attributes`**: the typed long-form
  attribute pattern D6 follows (minus `json`).
- **`tracking_identity_associations`** and `identity_statement_kind`: how a
  backend's video-derived association reaches attribution, unchanged.
- **`vawlume.alignment.applyTransform` / `applyTransformInterval`**: the only clock
  path. **No module outside `+alignment/` performs transform arithmetic.** That is
  the operative wording. Phase 4's itineraries said "nothing outside
  `+alignment/` reads `alignment_segments`", which was untrue of the Phase 1
  fixture builder when they said it (4.13 §9).
- **`report`'s explicit column lists**: it selects evidence columns by name, so
  5.2's new columns cannot change its output. Its closed field-list tests change
  only when 5.7 deliberately extends it.

### Gaps Phase 5 must fill

| Gap | Decision | Owner |
|---|---|---|
| A coordinate cannot be stored with a frame | D1 | 5.2 (DDL), 5.4 (intake), 5.5 (evidence) |
| Evidence cannot name a channel | D4 | 5.2 (DDL), 5.5 (write path) |
| No dimension for source localization | D3 | 5.2 (DDL), 5.5 (write path and the "five" sweep) |
| No home for backend-native fields | D6 | 5.2 (DDL), 5.4 (intake) |
| Nothing records which dimensions a producer consumed | D7 | 5.2 (DDL), 5.3 (profile), 5.4 (intake), 5.7 (read) |
| No profile kind for a backend | D13 | 5.2 (DDL vocabulary), 5.3 (loader and mapper) |
| No backend intake | D13 | 5.4 |
| `report` returns none of the above | — | 5.7 |
| `createRun` help says "currently imported" | — | 5.6 |
| Only one backend shape would ever have been tested | §15.3 | 5.8 |

The delta plan beside the 5.1 itinerary in the development repository assigns
every individual change to exactly one itinerary.

### Constraints inherited from elsewhere

- **The MATLAB Database Toolbox raises on any SQL NULL in a result set**,
  including numeric columns and `MIN()`/`MAX()`/aggregates over empty sets. It bit
  Phase 3 three times, the Phase 4 read surface once, and 4.12's own diagnostic
  tooling twice. Every new nullable column (`position_z`, `confidence`, every
  optional FK, every native-attribute value column) needs the established
  `IFNULL(...)` sentinel treatment on read, and every QC range needs testing
  over an empty set.
- **Absence reads as absence**: NaN for a number, `""` for text, never `0` and
  never `1.0`. A 2D `z` is NaN on read, and a missing confidence is NaN.
- **Insert-only scope triggers are the repository-wide convention** (schema §14),
  with `_update` twins only where a change would alter a row's meaning. D1's
  dimensionality guard and D4's channel guard qualify, and each says why.
- **The semantic metadata document is the single authority for column meaning**
  (`schema/README.md`). Every new table, column and relationship needs a
  description there in the same change as the DDL, or the completeness gate
  fails.
- **Free-text identity vocabularies** (`evidence_kind`,
  `identity_value_semantics`, `review_state`, `method`) stay open. Nothing in
  Phase 5 keys behaviour on them.
- **A `regexp` over MATLAB source is DOTALL by default, and comments are not
  code.** Four of 4.13's five false probe results came from that. Any Phase 5
  sweep for a literal ("four", "imported", "localiz") enumerates and reads its
  matches rather than tightening a pattern until it looks clean.

## What Phase 5 will not be able to claim

Written at 5.1, while it is cheap, and carried to 5.11.

**No real backend export is available.** As of 5.1 there is no USVCAM-like, or
any other, localization-backend output in either repository or in the
development workspace's data area. Unless that changes before 5.8:

- **Phase 5's validation is entirely synthetic**, in exactly the way Phase 4's
  was. Every backend file it ever reads will have been written by this repository
  to exercise a branch.
- **The phase cannot claim that its adapter meets any real backend's format.** It
  can claim that two structurally different synthetic shapes land in one
  representation (5.8). That is evidence about the representation's generality,
  not about any backend.
- **It cannot claim anything about localization accuracy**, about whether any
  backend's confidence is calibrated, or about whether a localized source was an
  animal at all.
- **It cannot claim a coordinate frame was declared correctly.** VAWLUME confirms
  that two facts cite one declared frame. It cannot confirm that the backend and
  the tracker measured in it.
- **It cannot claim a channel index was correct.** It confirms the channel exists
  on the recording (D4).
- **It cannot claim that VAWLUME estimated a caller.** VAWLUME still has not. The
  backend path stores what an external system claimed and applies a policy the
  user supplied.
- **Every threshold it uses remains a demonstration value**, inherited unchanged
  from Phase 4.
- **Nothing is known about scale.** The Phase 4 read surface has no paging. A
  backend that reports several estimates per window multiplies row counts, and
  no fixture will be large.

**If real backend data becomes available**, 5.8 is where it is used, in place of
or in addition to the synthetic second shape. The handoff that uses it must say
what the data is, what it does not cover (a single session is not a format
survey), and which of the claims above it changes. Most of them it does not
change: one real export proves one real format.

## Definition of done for Phase 5

The phase is complete when:

- a backend export maps through a versioned `attribution_backend_mapping`
  profile with dry-run preview and per-row issue reporting, and commits
  atomically through `vawlume.ingest.backendAttribution`, refusing a second apply
  by name;
- a localization estimate is stored with its frame, its semantics and its
  confidence, cannot be stored without the first two, and stores a 2D `z` as NULL;
- an estimate reaches a target only through explicit `addEvidence` promotion, as
  a `source_localization` row that cites it, and a claim reaches a target only
  through explicit `addCandidates`;
- evidence can name its channel, scope-guarded;
- comparing estimates across frames is refused, and nothing is transformed;
- backend-native fields are preserved in `attribution_native_attributes`, and no
  canonical column is named after a backend;
- a producer's consumed-dimension declaration is stored and read back as three
  states;
- correspondence, candidates, `decide` and `report` work over a backend run
  through the Phase 4 functions, verified by tests rather than asserted;
- a second, structurally different backend lands in the same representation, or
  the precise reason it cannot is recorded;
- nothing in `src/` combines any two of the five evidence dimensions, or computes
  a distance;
- the schema is `0.12-draft` / `user_version = 12`, reached in one bump;
- the whole path runs as one public demonstration on synthetic data, including at
  least one named refusal;
- the full gate passes on a committed candidate with a clean tree.

## Related documents

- [`04_caller_attribution_contract.md`](04_caller_attribution_contract.md): the contract this one extends
- [`03_multimodal_input_contract.md`](03_multimodal_input_contract.md): frames, tracking, identity, and the dense-data policy
- [`../development/23_spatial_geometry_schema.md`](../development/23_spatial_geometry_schema.md): compatibility is identity; no frame transforms
- [`../development/24_tracking_input_contract.md`](../development/24_tracking_input_contract.md): pose confidence is localization quality only
- [`../development/31_caller_attribution_schema.md`](../development/31_caller_attribution_schema.md): the attribution data dictionary 5.2 extends
- [`../development/32_imported_attribution_intake.md`](../development/32_imported_attribution_intake.md): the intake the backend path mirrors
- [`../development/33_attribution_correspondence.md`](../development/33_attribution_correspondence.md): correspondence, unchanged by D10
- [`../development/30_repository_self_description.md`](../development/30_repository_self_description.md): version claims, before the bump
- [`../../schema/README.md`](../../schema/README.md): the three schema artifacts a bump must move together
