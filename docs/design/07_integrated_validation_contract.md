# Integrated Validation Contract

## Status

Design contract for **Phase 7: integrated validation, QC and consolidation**,
the last phase of the prototype-v2 round. Itinerary 7.1 wrote it before any
Phase 7 code existed, so that the decisions below are made once rather than
negotiated by each later itinerary.

Written against schema `0.13-draft` (`PRAGMA user_version = 13`), verified at 7.1
on `dev` at `7d31eeb`. Phase 7 plans **at most one** version bump, to
`0.14-draft` (`PRAGMA user_version = 14`), owned by itinerary 7.2 (D10).

The contract clauses below are frozen as written. This status block is not. It
names the live schema and moves when the version moves, following the
precedent contracts 04–06 set. **Nothing machine-checks it**, because
`check_repository_self_description` exempts `docs/design/` from its version
check. The itinerary that bumps the schema moves this block by hand.

This contract **extends** [`04_caller_attribution_contract.md`](04_caller_attribution_contract.md),
[`05_backend_localization_contract.md`](05_backend_localization_contract.md) and
[`06_native_estimator_contract.md`](06_native_estimator_contract.md). It
replaces none of them. Every earlier clause holds unless a clause here says
otherwise. Three clauses here do say otherwise, on purpose:

- **D9** moves invariants 24 and 26 from producer properties to schema rules;
- **D10** supersedes contract 06 D10's single-reason `notes` convention for
  unscored candidates;
- **D17** changes `vawlume.tracking.readWindow`'s transform choice from "newest
  run" to "exactly one, or say so".

Each earlier sentence these make false carries a visible correction in its own
contract. Where this document departs from the recommendation in the 7.1
itinerary, the clause says so and gives the reason.

**The user settled these before the clauses were written:**

- the Pilot 3 dataset is available to Phase 7 outside both repositories:
  four sessions, each with two separate mono ultrasonic files, three
  extractors' output per file, a controller event log, a neural-acquisition
  TTL record, overhead video timestamps and manual codes;
- **only the anchored (right) microphone is in scope for Phase 7**. Relating
  the two microphones belongs to a planned inter-microphone consilience module
  beyond v2;
- no real paired session (two-channel audio plus tracking and geometry) exists;
- R7 (portable provenance roots) and R5 (manifest ownership) are deferred
  beyond v2;
- at most one schema bump;
- persistent databases are rebuilt from untouched sources, never migrated;
- the eighteen-itinerary plan stands;
- any MATLAB run expected to exceed about 30 minutes is prepared as a script
  that the user runs, and its log is handed back.

**The phase's one-sentence position:** Phase 7 compares stored results and
varies their declared inputs. It never combines, chooses or validates. Every
comparison and every sensitivity table can be recomputed from storage, and
says what it cannot know.

## What this phase is for

Phases 4–6 built three attribution paths that land in one representation, and
proved each one alone. The poster-MVP workstreams added an exploratory
consilience workflow and a self-describing CSV export. Three real-data bug
fixes showed that persistent databases and real extractor files have a
lifecycle the synthetic suite never exercised.

Phase 7 tests the result **as one system** (plan §12):

- it compares attribution runs across paths and across event sets;
- it varies the handles that exist and reports how conclusions move;
- it turns plan §12's six integration checks into injection-verified guards;
- it closes or re-defers every carried ledger item;
- it runs the integrated workflow on the real data that exists, and says
  exactly what that does and does not establish.

What makes the phase different is that **it adds almost no new meaning**.
Nearly everything Phase 7 builds is a reader. The temptation it must resist is
the one every comparison invites: to say which answer is right. Nothing in
VAWLUME knows that, and nothing in Phase 7 may imply it.

## Core vocabulary

These distinctions are the contract. Every decision below follows from them.

### A comparison reports agreement and disagreement; it never combines

A **comparison** reads two stored runs and reports, per unit, where they agree
and where they differ. It produces no merged caller, no consensus decision, no
combined score, no "best" path and no composite agreement score. Two runs that
disagree are reported as disagreeing. A comparison writes nothing.

### A correspondence unit is a stored join, not a computed one

A **correspondence unit** is the smallest set of targets on the left and on the
right that a stored analysis joins. Over one event set it is one target. Across
event sets it is a connected component of stored membership or correspondence
rows from a **named** analysis. The vocabulary is closed (D3):
`one_to_one`, `one_to_many`, `many_to_one`, `many_to_many`, `unmatched_left`,
`unmatched_right`.

### A structural empty is not a disagreement

A **structural empty** is a cell a path cannot produce. A native run cannot
decide `simultaneous` (invariant 27), so that cell of a cross-tab is
structurally empty for any native side. It is never counted as agreement or as
disagreement.

### An unknown input is not an unused one

An **unknown input** is a dimension a run never declared. Imported runs declare
nothing, so for them "no row" means unknown, never `not_used`
(contract 05 D7). A comparison that conditions on declared inputs reports
`unknown` and conditions on nothing.

### A variant run is an ordinary run

A **variant run** is a canonical run written by the existing producers
(`attributeCallers`, `normalizeCallLevels`, the alignment fitters, `decide`)
under one changed, declared input. It carries no flag saying it is a variant.
What makes it a variant is its membership in a family.

### A sensitivity family records which runs vary what

A **sensitivity family** is one `analysis_runs` row of type
`attribution_sensitivity`. It links its reference and its variants through
`analysis_run_sources`, and registers its design record as a checksum-bearing
profile version (D2). It holds no result.

### A reference variant is declared, never chosen

The **reference variant** is the configuration the family's variants are
compared against. It is named in the family's specification before anything
is applied, and the planner has no access to any result. Calling it the
reference makes it neither correct nor calibrated.

### A handle is an input the method declares

A **handle** is a declared input that a variant may change: a decision-policy
version, an estimator settings-profile version, a normalization-policy version,
an alignment fit, or a matching configuration.

### "Not variable" is a reported row, not a gap

A handle that method 1.0.0 does not let vary (the gates; the dimension
declarations) appears in every sensitivity summary as a row saying **not
variable in method 1.0.0**, with the reason. It is never silently omitted.

### A QC fact describes; it never judges

A **QC fact** is a number or flag derived from stored evidence alone, such as
how far an observed level difference lies from the ranking boundary. It is not
a verdict, it changes no score or decision, and it says what it cannot detect.

---

## Decisions

Itinerary 7.1 posed sixteen questions (Q1–Q16). D1–D16 answer them in order.
D17–D20 answer questions the live repository raised that the itinerary did not
pose.

| Itinerary question | Decision | Departs from recommendation? |
|---|---|---|
| Q1 where comparison and orchestration live | D1 | No. Entry points named |
| Q2 persistence and the family record | D2 | **Yes, in mechanism.** `analysis_runs.run_type` is unconstrained text, so a family needs **no** DDL |
| Q3 what counts as the same target | D3 | **Yes, in vocabulary.** The units reuse the stored `match_type` names, not new `split`/`merge`/`complex` synonyms |
| Q4 what a comparison reports | D4 | **Yes, partly.** Adds `both_empty`, a tie value, and a rule that ranks need a declared orientation |
| Q5 enforced versus stated rules | D5 | No |
| Q6 attribution-side handles | D6 | **Yes, in premise.** No tone family is measured anywhere today. The tone alternative is admitted by configuration alone, but is generated, not shipped |
| Q7 matching-side reach | D7 | No |
| Q8 the assumption-failure signal | D8 | **Yes, in scope.** The positional margin of Q6(a) is computed here, so it moves from 7.8 to 7.10 |
| Q9 invariants 24 and 26 | D9 | No. Triggers, plus named API refusals |
| Q10 what rides the bump | D10 | **Yes, in content.** Only the 24/26 triggers and the no-score-reason table ride. I-5, the 6.6/6.7 items, every P4-2 relation and the exporter identity are re-deferred |
| Q11 the shared fixture | D11 | No. One addition: the real rig's separate-file microphones as a refusal scene |
| Q12 real data and persistent databases | D12 | **Yes, in scope.** The left microphone is out (user); 7.14 splits into preparation and acceptance |
| Q13 integration checks | D13 | No |
| Q14 path resolution, R7 and R5 | D14 | No. R7 and R5 deferred beyond v2 (user) |
| Q15 closure invariants | Closure invariants section | No |
| Q16 documentation labelling | D16 | No |
| (raised by the repository) P6-4, `readWindow`'s transform choice | D17 | — |
| (raised by the repository) EXP-006 is missing from the ledger map | D18 | — |
| (raised by the repository) the real-data harness has no owner | D19 | — |
| (raised by the repository) `bracket_extrapolated` is a fixture fact, not a variant's | D20 | — |

### D1. Comparison is a read-only consumer in `+attribution/`; orchestration lives in `+eda/`

**Comparison:** one public function, `vawlume.attribution.compare`.

```matlab
result = vawlume.attribution.compare(conn, leftRunRef, rightRunRef, ...
    LeftPolicy=..., RightPolicy=..., Correspondence=..., CompareScores=false)
```

- **Read-only.** It has no `Apply`, writes no row and recomputes no score.
- **It reads each run only through `vawlume.attribution.report`'s field set**
  (invariant 16). Across event sets it also reads the stored membership rows of
  the named analysis, by read-only SQL inside `+attribution/` (D3).
- **It calls no producer.** `+attribution/` keeps its present dependency
  surface: `+alignment`'s transform appliers, `+geometry.assertCompatible`, and
  `+interval` (invariant 53).
- **One function for both itineraries.** 7.6 builds the function and the
  same-event-set path, and 7.7 adds the `Correspondence` option. The per-unit
  shape is shared, so a cross-event-set unit is reported in exactly the columns
  a same-set target is.

A comparison that reads only `report`'s field set is path-agnostic, so it does
not breach invariant 16. The precedent is domain QC living with its domain:
`vawlume.matching.compare` and `vawlume.consilience.sensitivity`.

**Orchestration:** in `+eda/`, which already materializes configurations and
runs producers.

| Entry point | Itinerary | Plan/apply | Purpose |
|---|---|---|---|
| `vawlume.eda.attributionSensitivity(conn, familySpec, Apply=false)` | 7.8 | Separate: `Apply=false` plans every variant and writes nothing | Produces variant runs over attribution-side handles through the existing producers, and records the family |
| `vawlume.eda.correspondenceSensitivity(conn, familySpec, Apply=false)` | 7.9 | Same | Produces matching configurations from `+eda` configuration records, attributes each configuration's events, and records the family |
| `vawlume.eda.sensitivitySummary(conn, familyRef)` | 7.8 (7.9 extends) | Read-only | Compares each variant with the reference through `vawlume.attribution.compare`, and returns the tables |

**Rejected: (b), a new `+qc/` package.** It would be a second home for
comparison, beside the domain-QC precedent, and it would invite exactly the
"best path" summary this phase forbids, in a package with no domain contract.

**Rejected: (c), both in `+eda/`.** `compare` reads the canonical
representation, and only `+attribution/` owns that. Putting the reader in
`+eda/` would make the exploration package a second interpreter of
`report`'s semantics.

**Not in `+attribution/`: orchestration.** It calls producers (`+estimator/`,
`+acoustic/`, `+alignment/`), and the canonical layer must not depend on them.

### D2. Variant runs persist as ordinary runs; a family is an `analysis_runs` row; comparison outputs are transient

- **Variant runs** are written by the existing producers and `createRun` /
  `addCandidates` / `addEvidence` / `decide`, exactly as any run is.
- **A decision-policy variant is not a run.** It is a second decision set over
  the same run, under a different policy version. `attribution_decisions` is
  unique per (target, policy version), so the two sit side by side.
- **A family** is one `analysis_runs` row with `run_type =
  'attribution_sensitivity'`, linked to every attribution run it covers through
  `analysis_run_sources`:
  - `dependency_role = 'sensitivity_reference'` for the reference's run;
  - `'sensitivity_variant'` for each variant's run.
- **Its design record** is registered as a `config_profile_versions` row of
  kind `analysis_settings`, `content_format = 'json'`, and linked through
  `analysis_run_profiles` with `assignment_role = 'sensitivity_design'`. This is
  the persistence the exploration runner already uses
  (`run_type = 'consilience_exploration'`, role `exploration_design`). The
  record lists, per variant:
  - the handle;
  - its value or values;
  - the configuration identity;
  - the run id;
  - for policy variants, the policy profile version id.
- **Comparison and summary outputs are not persisted.** They are deterministic
  tables, recomputable from stored rows, and are exported with provenance
  through `vawlume.eda.writeTableExport`. A stored comparison could go stale
  against the runs it describes; a recomputed one cannot.

**Departure: no DDL.** The itinerary expected a new `analysis_type` CHECK value
to ride 7.2. `analysis_runs.run_type` has **no** CHECK constraint, and the
consilience-exploration contract (§N) already relies on that. Its values are
snake-case noun phrases (`multi_extractor_agreement`,
`consilience_exploration`). Two schema triggers compare `run_type` with
`'multi_extractor_agreement'` and are unaffected by a new value.
`schema_metadata.json` documents no `run_type` vocabulary, so it does not move
either.

**Rejected: (b), comparison tables.** That would be a comparison-specific
result model, which 6.13 §12 rules out, and a second source of truth.

### D3. "The same target" comes only from storage; units reuse the stored topology vocabulary

**Same event set.** Two runs compare target by target when both target the same
recording and the same event-set column. That means the same `detection_id`,
or the same `consensus_event_id`. Agreement-group targets compare only when
`agreement_extent_method` is also equal. A group on the union extent and the
same group on the intersection extent are different targets, as contract 04
already says.

**Imported window claims** reach events only through stored
`attribution_window_correspondences`. A claim that was never promoted to a
candidate is not compared. The comparison counts such claims per side
(`claims_not_promoted`) and never treats them as candidates.

**Different event sets** correspond only through stored rows of **one named**
analysis:

| Left / right | Joined through |
|---|---|
| detections of extractor X / detections of extractor Y | `match_group_members` of a named `cross_extractor_matching` analysis, or `agreement_group_members` of a named `multi_extractor_agreement` analysis |
| detections / consensus events | `consensus_event_members` of the analysis that produced the consensus events |
| consensus events of configuration P / of configuration Q | shared member detections in both analyses' `consensus_event_members` (7.9) |

**A unit is one connected component** of the bipartite membership graph
restricted to the two compared event sets. Its type is decided by counting its
members on each side:

| Left members | Right members | Unit |
|---|---|---|
| 1 | 1 | `one_to_one` |
| 1 | ≥2 | `one_to_many` |
| ≥2 | 1 | `many_to_one` |
| ≥2 | ≥2 | `many_to_many` |
| ≥1 | 0 | `unmatched_left` |
| 0 | ≥1 | `unmatched_right` |

These are the counts `matchingBuildGroups` already applies. The unit keeps the
stored `match_type` verbatim, re-oriented to the comparison's left and right.
An agreement group is restricted to the two compared extractors' members.

**Refused by name:**

- different event sets with no analysis named:
  `vawlume:attribution:CorrespondenceAnalysisRequired`;
- a named analysis that does not join the two event sets, belongs to another
  recording, or is not complete: `vawlume:attribution:CorrespondenceAnalysisInvalid`.

**Nothing infers correspondence from time overlap at comparison time.** That
would be re-matching under unrecorded terms. `compare` calls no `+interval`
primitive for this purpose (invariant 46).

**Departure: the vocabulary.** The itinerary proposed `split`, `merge` and
`complex`. Two reasons for not adopting them:

- **The facts already have names in storage.** `match_groups.match_type` uses
  `one_to_many`, `many_to_one` and `many_to_many`, and so does
  `vawlume.consilience.sensitivity`. A second vocabulary for the same fact
  would be a translation layer.
- **"Split" is not well defined in a two-sided comparison.** One extractor's
  split is the other side's merge. `one_to_many` says which side has several
  members.

Prose, fixture manifests and demonstrations may say "split" or "merge" only
with the side named ("a MUPET-side split, `one_to_many` with DeepSqueak on the
left").

### D4. Per unit, a closed set of tidy columns; ranks need a declared orientation

One row per unit. The columns are closed:

| Column | Vocabulary |
|---|---|
| `correspondence_unit` | D3's six values; `one_to_one` for every same-set target |
| `left_target_ids`, `right_target_ids` | stored ids, all of them; never collapsed |
| `top_entity_agreement` | `same`, `different`, `tie_left`, `tie_right`, `left_unscored`, `right_unscored`, `both_unscored`, `orientation_unknown`, `not_applicable_unit` |
| `selected_set_relation` | `equal`, `disjoint`, `subset`, `superset`, `overlap`, `left_empty`, `right_empty`, `both_empty`, `not_applicable_unit` |
| `left_decision_status`, `right_decision_status` | the stored status, or `no_decision` |
| `left_declared_<dimension>`, `right_declared_<dimension>` | `used`, `not_used`, `unknown`, for the four uncertainty sources |
| `score_comparability` | `comparable`, or `not_comparable:<reason>` |

`not_applicable_unit` is the value for any unit other than `one_to_one`. A
`one_to_many` unit has no single left and right target to compare, so its
per-target comparisons are reported in a second table, one row per (left
target, right target) pair inside the unit, carrying the unit's id. They are
**never** promoted to unit-level agreement, and never reported as several 1:1
units.

**The decision-status cross-tab** is a separate table:

- one cell per (left status, right status);
- `assigned`, `ambiguous`, `unassigned`, `excluded`, `simultaneous`;
- every `simultaneous` cell on a native side is marked `structural_empty`;
- such cells are excluded from every agreement or disagreement count.

**Departure: `both_empty`.** Two empty selections are an empty-set equality.
They are kept distinct from `equal` because "neither run selected anyone" and
"both selected A" must not be pooled.

**Departure: a tie value.** The native symmetric scene gives two candidates
equal scores. "The top-ranked entity" does not exist there, and pretending one
does would be an arbitrary choice.

**Repository-raised: ranks need an orientation, and the orientation is
declared.** `candidate_rank` is presentation, and native runs omit it
(contract 06 D10). A score's direction is not stored on the candidate. It is
declared in the decision policy (`decision_rule.ordering`). So the rank basis
for each side is:

1. the decision policy named for that side (`LeftPolicy`/`RightPolicy`), whose
   `ordering` and `reads` say which column ranks, and in which direction;
2. otherwise `candidate_rank`, when every candidate of the target carries one;
3. otherwise `orientation_unknown`.

Probability needs no declaration: it ranks higher-is-stronger by definition.
The basis used is a column of the result.

**Repository-raised: a run with several decision sets must name one.** When
decisions exist under more than one policy version and the caller names none:
`vawlume:attribution:DecisionPolicyRequired`. When the named policy decided
nothing on that run: `vawlume:attribution:DecisionPolicyNotFound`.

**Guard (7.6):** a test fails if any returned field or column name matches
`best_`, `combined_`, `winner`, `consensus_`, `composite`, `overall`,
`agreement_score` or `preferred`.

### D5. Which comparability rules code refuses, and which output states

| Rule | Enforcement | Identifier or field |
|---|---|---|
| Scores compare only under the same method, method version, settings-profile version and recording | **Refused** when `CompareScores=true` and any differs. Otherwise no score column exists | `vawlume:attribution:ScoreNotComparable` |
| Native scores never compare across recordings or settings-profile versions | **Refused** (the same rule, named in the message) | `vawlume:attribution:ScoreNotComparable` |
| A comparison is within one recording | **Refused** | `vawlume:attribution:ComparisonRecordingMismatch` |
| Different event sets need a named analysis | **Refused** | `CorrespondenceAnalysisRequired`, `CorrespondenceAnalysisInvalid` |
| A run with several decision sets names one | **Refused** | `DecisionPolicyRequired`, `DecisionPolicyNotFound` |
| Imported and backend scores are on their producers' scales | **Stated**: `score_comparability = not_comparable:producer_scale` | — |
| Structural empties are not disagreement | **Stated** in the cross-tab, and **enforced** in counts by a test | `structural_empty` |
| Undeclared means unknown | **Stated** (`unknown`) | — |
| Native lineage runs through `analysis_run_sources`, not `parent_attribution_run_id` | **Stated** in the provenance block | — |
| The method's intermediates are not stored | **Stated**. Recomputing them is the estimator's (D8), never `compare`'s | — |

All identifiers are `vawlume:attribution:*`. A refusal happens before any table
is built, so a refused comparison returns nothing partial.

### D6. Attribution-side handles: four vary, two do not, one is a margin and one is not measurable

Each handle was verified against the live code at 7.1.

| Handle | How 7.8 varies it | Verified |
|---|---|---|
| Decision policy | `decide` again under a materialized policy version. Decisions sit beside the earlier ones | `decide` refuses only a repeat under the same version |
| Estimator settings-profile version | A new profile version varying `primary_instant_basis`, `max_interpolation_gap_s`, `min_distance` or `channel_pair`, then `attributeCallers` reusing the normalization runs | `loadSettings` requires every parameter stated, and reads the profile from the stored `content_uri` by checksum |
| Instant basis alone | As above. Distances on all five bases are already stored, so nothing re-reads tracking | The evidence rows exist per basis |
| Normalization policy | `normalizeCallLevels` under the alternative policy on the existing call-window runs, then a settings-profile version naming that policy (6.12a requires the match) | See below |
| Alignment fit | An alternative fit (affine against piecewise; one anchor excluded through `setAnchorInclusion`) named by `alignment_run_id` in the run spec | `attributeCallers` takes explicit alignment runs, never "the latest" |
| Gates (`pose_confidence_gate`, `temporal_uncertainty_gate_s`) | **Not variable in method 1.0.0.** `loadSettings` refuses a non-null value (`SettingsGateNotImplemented`) | A "not variable" row |
| Dimension declarations | **Not variable in method 1.0.0.** All four must read `used` (`SettingsDimensionMisdeclared`) | A "not variable" row |
| Positional error | **A read-only margin** (D8): how far each candidate's distance would have to change to reverse the ranking | Computed in `+estimator/`, owned by 7.10 |
| Identity uncertainty | **Not measurable in v2** | See below |

**Departure: the normalization alternative's premise.** The itinerary suggested
"a policy reading the tone reference family, which the Phase 6 demonstration
already measures". **It does not.** `examples/native_estimator_demo.m` registers
references of `reference_type = "noise"` only. Its noise is synthesized from
four sinusoids inside the call band, but it is registered and estimated as
noise. No shipped path measures a tone family.

**Does the code admit a tone policy by configuration alone? Yes.** Verified in
`acousticLoadNormalizationPolicy`:

- `pairs[].reference_type` is free text;
- `band_match` must be `identical`;
- nothing names `noise`.

`normalizeCallLevels` filters estimates by the pair's `reference_type` and
band. So a policy identical to the shipped one except `reference_type = "tone"`
runs unchanged, **provided** a tone family is registered, measured and
estimated in a band identical to the call band. **No code change is needed.**
The 7.3 fixture supplies such a family (D11).

**The alternative is generated, not shipped.** 7.8 derives it from the shipped
policy as a variant: the same profile key, version label
`1.0.0+sens.<configuration_id>`, one factor `reference_type = tone`. It is
written under the output root. It is not added to `config/`, for two reasons:

- A shipped profile says "a user might choose this". On the one real rig
  Phase 7 has, the scheduled tones sit near 2.5 and 5 kHz, far below the
  ultrasonic call band. A tone family there would give
  `response_band_mismatch` on every channel.
- Every other Phase 7 variant is a generated runtime artifact (D2). One
  shipped exception would blur that line.

**Identity uncertainty: (c), not measurable in v2.** Native v1 admits identity
only as resolve-or-unscored (contract 06 D9). One time-valid association, or no
score with a reason. There is no continuous handle. The value of
`identity_value` is never read, so varying it changes nothing. A different
association set is a different input, not a profile variant. The fixture's
identity-swap scene shows the only behaviour v1 has.

**Rejected: (b), perturbed tracking streams** registered as new streams. They
would be new evidence, not a variation of a declared input. The synthetic
perturbation would also have to choose an error model, which is a calibration
claim in disguise.

**Variant materialization.** 7.8 reuses the exploration's identity rule rather
than inventing a second one:

- the configuration id is SHA-256 over the name-sorted `name=value` pairs,
  prefixed `cfg-` and truncated to ten hex characters, as
  `edaConfigurationIdentity` does;
- numbers are formatted `%.17g`, exactly as today. Text values (an instant
  basis, a reference type) enter verbatim. That extension must leave every
  numeric identity bit-identical;
- the version label is `<base version>+sens.<configuration_id>`, beside the
  exploration's `+exp.`;
- files are written under the output root, never under `config/`.

**The reference variant** is the shipped, registered profile and policy
versions, named explicitly in the family specification:

- a specification without a reference is refused:
  `vawlume:eda:SensitivityReferenceRequired`;
- a request to vary a not-variable handle is refused:
  `vawlume:eda:SensitivityHandleNotVariable`;
- an unknown handle is refused: `vawlume:eda:SensitivityHandleUnknown`;
- a family key reused with a different design:
  `vawlume:eda:SensitivityFamilyConflict`.

**Recommendation upheld: do not version the method** to make the gates or the
declarations variable (map non-goals).

### D7. Matching-side sensitivity reaches attribution through stored consensus membership

- **The orchestrator.** `vawlume.eda.correspondenceSensitivity` consumes `+eda`'s
  configuration records: the reference configuration
  (`vawlume.eda.referenceConfiguration`) plus a small, declared set of
  alternatives materialized by `materializeConfigurations`.
- **Per configuration** it applies the matching (or reuses an applied analysis
  whose checksum is identical). It attributes the resulting consensus events
  through the native path. It then compares configurations through D3's
  third join: consensus events joined by shared member detections.
- **`runExploration`'s stage list is not widened.** The poster MVP's runner
  keeps its contract.
- **The honest reach.** `feature_support.discrepancy_tolerance` governs
  consilience classification, not candidate generation (consilience contract
  §B), so spectral policy cannot move consensus events. **7.9 demonstrates
  this rather than assuming it.** Under a tolerance variant, every consensus
  event's member set must be identical, and the comparison must report only
  `one_to_one` units with `equal` selections.
- **Temporal thresholds can move candidate generation**, and so the
  `one_to_many`, `many_to_one` and `unmatched_*` structure. 7.9 shows which
  units change, and nothing more.
- **The budget is the synthetic fixture only.** EXP-050 measured about
  5.8 hours for one real recording's exploration, and a matching-side
  attribution family multiplies that by the attribution chain per
  configuration. **No real-data run of this orchestrator happens in Phase 7.**
  7.14 runs the exploration, not this.

### D8. The assumption-failure signal is a read-only QC fact in `+estimator/`

**Function:** `vawlume.estimator.qcFacts(conn, runRef)`, owned by 7.10.

- **It reads through `vawlume.attribution.report`** and the stored settings
  profile version.
- **It recomputes the method's intermediates** by calling the pure method
  (invariant 23). It writes nothing and changes no score or decision.
- **One row per scored native target.** For an unscored target: no facts, and
  a reason. A non-native run is refused by name:
  `vawlume:estimator:QcFactsNotNative`.

**The facts, all derived from stored evidence alone:**

| Fact | Meaning |
|---|---|
| `observed_db` | The stored `normalized_level_difference` |
| `predicted_db_<entity>` | Each candidate's prediction on the primary instant basis |
| `prediction_gap_db` | The absolute difference between the two predictions |
| `tolerance_db` | Half the gap: the largest unmodelled level bias that leaves the ranking unchanged (6.11's measured statement) |
| `acoustic_margin_db` | How far the observed difference is from the ranking boundary (the midpoint of the predictions). A bias larger than this reverses the ranking |
| `observed_outside_predictions` / `outside_by_db` | Whether the observed difference lies outside the interval the two predictions span, and by how much |
| `no_candidate_within_tolerance` | No candidate's discrepancy is within `tolerance_db` |
| `positional_margin_<entity>_<channel>` | **Q6(a).** The change in that candidate's distance to that microphone, holding the other distance, that would move its prediction to the ranking boundary. In the frame's unit |

The positional margin inverts the method's own formula,
`20*log10(d_b / d_a)`, on two stored distances. It reads no coordinate and
computes no position, so it is not spatial arithmetic in invariant 19's sense.
It is method arithmetic, and it lives where the method lives.

**What it must say it cannot detect.** Its output carries this text verbatim:
*"A wrong animal that fits well is not detectable from these facts. When an
unmodelled bias moves the observed difference toward the wrong candidate's
prediction by more than `acoustic_margin_db` and less than the gap, the wrong
animal scores best and every fact here looks ordinary."*

That is the 6.11 model-mismatch case. These facts make the margin visible; they
do not flag the failure.

**What it never does:**

- issue a verdict;
- change a score or decision;
- gate, weight or decide anything. That would be a new method version.

**Where it does not live:** in `report`. A native-only computation there would
be a path branch, which breaks invariant 16.

**What it stores: nothing.** No consumer needs the facts stored. They are
recomputable from storage, and storing them would make them a second copy of
the method's intermediates. The method's stored outputs are unchanged, so no
method version is needed.

**Departure: scope.** The positional margin is computed here rather than in
7.8, because it is the same inversion of the same formula as
`acoustic_margin_db`. Splitting it would put two copies of one piece of
arithmetic in two itineraries. 7.8's sensitivity summary cites it as the
positional-error row.

### D9. Invariants 24 and 26 become schema rules, with named API refusals in front

**Decision: (b), triggers, plus (a), API refusals.** The triggers cover direct
SQL, which is the half 6.13 found open. The API refusals give a caller a named
identifier before the database raises.

**DDL (7.2), one insert/update pair each:**

| Trigger pair | Fires when | On |
|---|---|---|
| `trg_attribution_candidate_native_no_probability` (+ `_update`) | `probability IS NOT NULL` or `probability_semantics IS NOT NULL` | `attribution_candidates` whose target's run has `attribution_path = 'native_estimate'` |
| `trg_attribution_evidence_native_identity_cited` (+ `_update`) | `evidence_dimension IN ('pose_localization', 'visual_identity')` and `tracking_identity_association_id IS NULL` | `attribution_evidence` whose target's run is `native_estimate` |

**`_update` twins** follow schema §14's exception, because a change alters what
the row claims. One consequence must be tested and documented by 7.2:
`attribution_evidence.tracking_identity_association_id` is `ON DELETE SET NULL`.
Deleting an association cited by a native pose row therefore performs an
update that the twin refuses. **That is intended.** It is contract 06 D13's
rule: a derived score must not outlive an input it was computed from. 7.2
verifies by test that SQLite fires the twin on the foreign-key action. If it
does not, 7.2 records that and the guard stays insert-only plus API.

**API (7.4):**

- `addCandidates` refuses a probability on a native run:
  `vawlume:attribution:NativeProbabilityRefused`;
- `addEvidence` refuses a native pose or identity row without a cited
  association: `vawlume:attribution:NativeIdentityCitationRequired`.

**Not in the schema: the semantics text.** Invariant 24's second half, "every
native score's semantics say it is not one", is a property of a text string.
A trigger matching prose would be fragile, and would give false confidence. It
stays a producer property, checked by the existing tests.

**Evidence at 7.18 for HOLD, not QUALIFIED:**

- a direct-SQL insert and update of each forbidden row raises;
- each API path raises its identifier before any write;
- each guard fails when its trigger is dropped (injection).

### D10. What rides the bump

Verified at 7.1: the live schema reads `0.13-draft` / `user_version = 13`. The
bump is `0.13-draft` → `0.14-draft` and is owned by 7.2.

| Item | Decision | Phase 7 consumer, or the reason it does not ride |
|---|---|---|
| Invariants 24/26 | **Rides**: D9's two trigger pairs | 7.4's API refusals; 7.13's guard; 7.18's HOLD |
| Every no-score reason | **Rides**: a child table | 7.8's sensitivity summary (below) |
| I-5 `ordinal_source` | **Re-deferred beyond v2** | No Phase 7 comparison joins on a backend estimate's ordinal. It concerns backend localization estimates, which no comparison reads |
| 6.6: a duplicate guard for call rows | **Re-deferred beyond v2** | The only writer creates rows inside a new run and cannot duplicate them. No Phase 7 join depends on the guard |
| 6.6: a record of an all-failed run | **Re-deferred beyond v2** | No Phase 7 consumer reads a run with zero rows |
| 6.7: normalized row → estimate as a foreign key | **Re-deferred beyond v2** | The per-channel estimate is recoverable at run level (`analysis_run_sources` → the response run) plus the policy's declared matching rule. No comparison needs the row-level link. The residual risk, a direct deletion of one estimate row, stays documented (doc 42) |
| P4-2 / F5.10-10: run source and participant snapshots, distance-row basis flags | **None promoted** | `compare` reads participants from `report`'s decoded `participating_entity_ids`, and basis flags from evidence semantics. Nothing joins on them in SQL |
| The exporting system's identity on `imported_attribution_windows` | **Re-deferred beyond v2** | No comparison groups runs by exporter. `attribution_runs.method` names it |
| An `analysis_type` / `run_type` value | **No DDL** | `run_type` is unconstrained (D2) |

**The no-score-reason table:**

```text
attribution_candidate_no_score_reasons
    attribution_candidate_id  NOT NULL FK → attribution_candidates, ON DELETE CASCADE
    reason_ordinal            NOT NULL, >= 1   (the producer's order; 1 is the first reason)
    reason_code               NOT NULL TEXT    (the producer's closed set; free text in the schema)
    PRIMARY KEY (attribution_candidate_id, reason_ordinal)
    UNIQUE (attribution_candidate_id, reason_code)
```

Plus one insert trigger, refusing a reason on a candidate whose `score` is not
NULL. A scored candidate has no reason not to be scored.

- **Why a table, and why now.** `levelDifferenceConsistency` already returns
  every applicable reason (`no_score_reasons`), and storage keeps only the
  first. 7.8's summary must say why a candidate's scored state moved under a
  variant. Suppose a candidate is unscored under the reference for
  (`identity_changes_within_window`, `alignment_extrapolated`), and only for
  the first under an alignment variant. The first reason is identical on both
  sides, so the movement would be invisible.
- **Why `reason_code` is not a CHECK.** The set is the method's, versioned with
  the method (contract 06 D10). A schema vocabulary would need a bump to add a
  reason to a future method version.
- **Rejected: a delimited `notes` convention** (`no_score_reasons=a,b`). That is
  the `|`-join defect the schema has dropped once, and P4-2 again.
- **The `notes` token is retired for runs written after 7.4.** The table becomes
  the only home for reasons, so there is no second authority. `report` reads
  the table (7.5). No persistent native database exists to need the old
  convention (D12's rebuild policy). Contract 06 D10 carries the correction.

**What moves with the version** (contract 05 D12's list, the CSV contract §A.1,
and `30_repository_self_description.md` §3):

- the three spellings of the version in `schema.sql`;
- `schema/schema_metadata.json`: `schema_version`, a description for the new
  table, its columns, its relationship and its triggers, and a
  `metadata_version` bump;
- `schema/schema.json`, regenerated, with its freshness check;
- the usage guide's status line;
- the status blocks of contracts 04, 05, 06 and this one.

7.2 confirms that the CSV export needs no change by exporting a freshly built
`0.14` fixture.

### D11. The shared integrated fixture is a shipped builder beside the Phase 1 one

**Where:** `vawlume.db.buildIntegratedFixture` (with
`createIntegratedFixtureDatabase` beside it, if 7.3 finds the Phase 1 pair's
split useful). It is shipped in `+db/`, so that tests **and** 7.16's
demonstration call one builder. Test-only helpers would need the path
manipulation the demonstrations avoid. It returns a manifest of every scene's
ids and expected outcomes, so no consumer hard-codes an id.

**What it contains**, on one recording:

- three extractors' detections (DeepSqueak, MUPET, USVSEG), each carrying one
  real-shape token:
  - MUPET's terminal `_` sentinel;
  - USVSEG `NaN` feature missingness;
  - a DeepSqueak zero-height box;
- one pairwise matching analysis per extractor pair, one agreement analysis,
  and their consensus events;
- two-channel audio with **both** a noise family and a tone family registered
  in the call band (D6 needs the tone family);
- placements, and tracking on a piecewise clock;
- the audio clock fitted affine from three anchors with about 200 ppm drift,
  mirroring the real rig;
- identity associations;
- all three attribution paths over overlapping targets: imported, backend and
  native.

**Scenes:**

- separable;
- symmetric;
- model mismatch;
- coverage gap;
- identity swap;
- a `one_to_many` unit (one extractor splits a call);
- a `many_to_one` unit (one extractor merges two);
- an extractor-specific miss;
- a call outside the tracking bracket (`bracket_extrapolated = true`, D20);
- **one addition**: a second, single-channel recording standing for the real
  rig's separate-file microphone. The native path must refuse it with
  `vawlume:estimator:InputRecordingMismatch`, which is the real-data reason
  native attribution is not applicable (D12).

**Where natural**, it also carries one non-ASCII label and one value with an
embedded newline, for 7.13's CSV audit.

**The session-fixture copies (6.13 §10), found by searching:**

- three test copies: `tests/integration/test_event_window_tracking_retrieval.m`,
  `test_identity_candidate_geometry.m` and `test_native_estimation_run.m`. Each
  has a local `setUpSession`; the latter two say in comments that they copy the
  6.4 and 6.5 setups;
- the fourth is the session the Phase 6 demonstration builds for itself,
  `examples/native_estimator_demo.m`.

7.3 retires the three test copies onto the builder. It moves the demonstration
only if its integration test's assertions stay identical. Otherwise it records
why the demonstration keeps its own scene.

**If the builder is over-large** (the map's most likely `a`), 7.3 stops after
the extractor, audio, clock and native scenes, and hands the backend and
imported scenes to `7.3a`.

### D12. Real data: what 7.14 runs, what it may claim, and the persistent-database policy

**The data (map decision 1).** The Pilot 3 dataset: four sessions, each with
two independently started mono ultrasonic files, plus:

- DeepSqueak, MUPET and USVSEG output per file;
- a controller (MedPC) log;
- a neural-acquisition GPIO record;
- traces;
- overhead video with per-frame timestamps;
- whole-second manual video anchors;
- proximity codes;
- experimenter events.

No tracking, no microphone geometry, and no real paired session exist. No
ground truth for who called exists.

**Scope, settled by the user at 7.1:**

- **The right microphone only.** The two microphones are separate files with
  unknown relative clocks, and only the right one is anchored. The left one is
  neither ingested nor aligned in Phase 7. Integrating both belongs to the
  planned inter-microphone consilience module, beyond v2.
- **Three audio anchors per session.** Markers 4, 6 and 8 only. Markers 1 and 3
  are not annotated; that waits for the planned user-guided,
  program-refined anchoring function. So:
  - an affine fit per clock pair has one residual degree of freedom;
  - a piecewise fit is not supportable on real data;
  - leave-one-anchor-out leaves two anchors, an exactly determined affine fit
    whose only output is the left-out anchor's prediction error.
- **The GPIO channel carrying the controller's TTL2 line is confirmed** by the
  user. The other GPIO channels are ignored.
- **The video clock shares the neural-acquisition start** (the two systems are
  coordinated, per the user). The video timebase is therefore declared the
  same origin as the GPIO clock, not fitted. Two recorded facts travel with
  that declaration:
  - the user recalls a video rate of 15/s. The stored Ch6 frame timestamps give
    a mean interval of 33.3 ms (30.0 fps), a modal interval of 32.0 ms, and a
    total span equal to the neural span. **Video time comes from the per-frame
    timestamps, never from a nominal rate**, so the discrepancy changes nothing
    computed. It is recorded, not explained away;
  - the manual video anchors sit 0.18–0.73 s before the TTL onsets in three
    sessions, consistent with coding to the whole second. In the fourth the gap
    is 1.15 s, which whole-second coding cannot explain. It is recorded as a
    discrepancy and the video anchors serve as QC only.
- **Protocol epochs:**
  - the encounter epoch runs from the experimenter's female-introduction event
    to `video_end`. Acquisition stopped after the controller's
    remove-female marker, and the separation time was not recorded, so video
    end is the analysis endpoint;
  - the empty-chamber epoch is bounded above by the controller's
    "begin connecting probe" marker. Standby runs from there to the
    experimenter-triggered "probe is connected" marker. The male's connection
    time is not otherwise known.
- **Marker sounds** (user, read from a spectrogram):
  - the mid tone is near 2.5 kHz and the high tone near 5 kHz;
  - the low tone is below the mid tone and barely visible;
  - the white noise extends to about 60 kHz.

  Two consequences follow. First, tones cannot trigger ultrasonic detections,
  but white noise overlaps the lower call band. Second, the audio anchors were
  placed at the mid tone's leading edge minus 2 s. They therefore embed the
  controller's tone schedule. A systematic offset common to every session
  would not appear in any residual, and that limitation is recorded.
- **DeepSqueak settings were identical across extractions** (user), so run-date
  heterogeneity, which concerned a left-microphone file only, is moot.

**What 7.14 runs.** The real-data QC plan's stage R2, trimmed to the
right microphone, in its order:

| Part | Runs | Note |
|---|---|---|
| R2-A | Fresh build at `0.14-draft`: 4 recordings, intake, three imports each, `registerBuiltinSemantics` right after opening | Untouched sources; hashes match the preflight manifest |
| R2-B | Ingestion reconciliation for 12 extractor files | Every `_` and `NaN` raw-preserved with a NULL payload; zero-height boxes literal |
| R2-D | Alignment: the corrected Ch6 rerun (the obligation), then the other three sessions by the same recipe | Audio and controller fitted affine to the GPIO clock; video declared same-origin; per-anchor residuals; drift per session and its spread; status `estimated`. Gathers the R5 and R7 inventories |
| R2-E | Proximity codes and experimenter events as interval streams on the video timebase, placed in common time through `vawlume.alignment.*` | Coverage gaps explicit |
| R2-G | Acoustic chain on one channel: marker references, response measurement, a bounded call sample | Noise family only; tones do not reach the call band. Native run **not applicable**; the refusal is observed if attempted |
| R2-F | The protocol-asserted negative control: detections in the empty-chamber epoch and in each marker window | Labelled "protocol-asserted; not observed". White-noise windows overlap the call band, which is stated beside the counts |
| R2-I | CSV export of the R2-A database and `validateMetadata(Mode="complete")` | — |
| R2-J | A second build from sources, compared by content | Timestamps and run ids are documented exclusions |
| R2-C | The four-recording exploration (EXP-048), checkpointed per recording | The long run: **prepared as a script, run by the user** |
| R2-H | **Approved as optional, last**: protocol-derived imported claims (claimed caller = the male, for calls in the male-only habituation epoch), correspondence, decisions, and 7.7's cross-event-set comparison | Labelled "derived from the session design, not an external estimator". Mechanics and scale only; no accuracy statement |
| R2-K | Evidence manifest and a sanitized handoff | Aggregates only |

**Departure: 7.14 splits.** The map has one itinerary. The real-data plan adds a
preparation stage (R1: harness, preflight, clock tables, session profiles,
smoke database, cost calibration). Under the user's runtime policy, the long
parts must be handed off as scripts. The split:

- **7.14** (R1) may run any time after 7.2;
- **7.14a** (R2) runs on the committed candidate after 7.13;
- **7.14b**, if needed, reads the user-run logs and writes the acceptance
  record.

D19 records the harness's ownership.

**What 7.14 may claim:**

- **F (functional):** formats ingest, provenance holds, counts reconcile,
  refusals fire, the database reads back and exports;
- **C (consistency):** drift and residuals are similar across sessions, and
  exploration outputs are comparable across recordings;
- **only R2-F** may be labelled "protocol-asserted";
- nothing is validation, and nothing is accuracy.

**EXP-036 (pooled profiler): re-deferred.** 7.14 reports per-recording
support-pattern profiles. A pooled profile needs a denominator decision no
Phase 7 consumer requires.

**The persistent-database policy: rebuild, never migrate** (user). A database
is rebuilt from untouched sources into a fresh database at the live schema,
then `registerBuiltinSemantics` runs. No migration machinery is built.

The one older real database (a September preliminary-analysis database) is
**optional, read-only and probed on a copy only**, in a work directory outside
both repositories. Its `user_version` is recorded, and `vawlume.export.database`'s
refusal of a schema mismatch is observed. `registerBuiltinSemantics` may be run
on the copy to record how sync behaves on an older DDL. It never touches the
original.

**The CH6 rerun's place:** R2-D, first, under the alignment-intake contract:

- falling-edge GPIO onsets;
- the corrected audio anchor;
- the cited anchor time is the onset.

It gathers the R5 inventory (which keys and coverage windows were
session-specific) and the R7 inventory (every external path stored or opened),
in shape only in the handoff. Real paths stay private.

### D13. The integration checks: extend existing guards first, add five, and inject every one

Plan §12's six checks, mapped onto guards that exist at `7d31eeb`:

| Check | Existing guard(s) | Missing (owner 7.13 unless stated) |
|---|---|---|
| 1. Source mapping remains provenance-preserving | Adapter suites: `test_mupet_export_adapter` (the `_` sentinel), `test_usvseg_export_adapter` (`NaN`, undeclared tokens), `test_deepsqueak_export_adapter`; `test_table_field_mapping` | **A token-to-target trace**: on the integrated fixture, the raw `_` and `NaN` tokens are readable from a detection that is an attribution target, and no payload is zero |
| 2. Native data are never overwritten by derived values | `testSummarizeNeverMutatesUpstreamRows`; alignment "completed transform not rewritten"; the attribution read-only tests | **A before/after content checksum** of the native tables (`detections`, `event_measurements`, `external_events`, `tracking_*`, `imported_attribution_*`) across the whole fixture pipeline, including comparison and sensitivity runs |
| 3. Time alignment has one authoritative transform representation | `test_alignment_transform_application`, `test_alignment_transform_math`; invariant 9 was measured by a live search at 6.13, not by a guard | **A static transform-arithmetic scanner**: coefficient arithmetic (`offset_s`, `scale`, segment slopes) outside `+alignment/`. It extends the geometry arithmetic scanner's machinery |
| 4. Dense continuous inputs are not needlessly duplicated in SQLite | `test_tracking_source_mapping/testIRCarriesMetadataAndNeverASample`; `readWindow` stores no sample | **A row-count invariance test**: doubling the fixture's tracking samples and audio length changes no row count in any table |
| 5. Attribution paths produce the same canonical result structure | `test_native_estimation_run/testAllThreePathsReadBackThroughOneFieldSet` (invariant 16) | Extend: `compare`'s output is identical in shape for every path pair (7.6 builds it; 7.13 injects) |
| 6. Shared correspondence utilities create no semantic coupling | `test_attribution_correspondence/testMatchingPackageIsUntouched`; `test_eda_subset_probe/testNothingOutsideTheEdaPackageNeededEditing` | **A dependency-direction scanner** over code, not comments (invariant 53): `+interval` calls no VAWLUME package; `+matching` calls only `+interval`; `+attribution` calls only `+alignment`'s appliers, `+geometry.assertCompatible`, `+interval`, `+db` and `+schema` |

**Cross-workstream checks:**

| Check | Guard | Owner |
|---|---|---|
| CSV export of the integrated database is faithful, and its metadata complete | Export the 7.3 fixture; `validateMetadata(Mode="complete")`; per-object counts equal SQLite; the non-ASCII and newline values round-trip | 7.13 |
| The consilience exploration runs over the integrated fixture | `runExploration` with `Stages="diagnostics"` (bounded) on the fixture | 7.13 |
| Registry sync on a database seeded with older profile versions | Extend `test_seed_registration`: seed a database with an older shipped profile version, sync, and assert append-only and idempotent | 7.13 |
| Real-shape tokens survive to attribution targets | Check 1's new trace | 7.13 |
| The alignment-intake invariants | Existing `test_alignment_intake` regressions (recording scope, immutable streams, the onset rule), re-run against the integrated fixture's manifest | 7.13 |

**Every guard is injection-verified in 7.13.** That means a scratch copy of the
tree with the violation injected, the guard failing for its own reason, and the
injection reverted, as 6.13's row 29 did.

### D14. Path resolution has one home; R7 and R5 are deferred beyond v2

**The single home:** `vawlume.internal.resolvePath`, promoted from
`exportResolvePath`'s pattern. It is a new package, `src/+vawlume/+internal/`,
on the `vawlume.export.internal` precedent. It must be callable from about
seven packages, so it cannot be `private/`, and `+internal` says it is not
user API.

- **Modes:**
  - caller-relative, resolved against `pwd`;
  - base-relative, resolved against a named base such as `RepoRoot`
    (`Base=`);
  - an `isAbsolute` predicate.
- **Behaviour carried from the export helper:** Windows drive-relative and
  driveless-rooted paths are refused rather than resolved, and the result is
  canonicalized only once absolute.
- **The export's error contract is preserved.** `exportResolvePath` stays as a
  thin wrapper that keeps `vawlume:export:AmbiguousPath`. The shared helper
  raises `vawlume:internal:AmbiguousPath`.
- **Not one semantics for all sites.** Many of the 39 sites resolve against
  `RepoRoot` or a source root, not `pwd`. Each site keeps its base, and 7.11
  records, per site, which base it had and that it kept it.

**The equivalence proof 7.11 must give.** For each touched site, a test
resolves:

- an absolute path;
- a `RepoRoot`-relative path;
- a caller-relative path;

with MATLAB's current folder deliberately different from the JVM's
`user.dir`. Each must resolve identically to the pre-change result on the same
inputs, or to the documented correction where the old result was the P7-5
defect.

**R7 (portable provenance roots): deferred beyond v2** (user). Its
prerequisites, as the alignment-intake handoff §11 stated them:

1. R5's ownership and precedence decision complete or explicitly frozen;
2. the corrected CH6 rerun's inventory of real external paths (gathered by
   7.14 / 7.14a, R2-D);
3. an inventory of every provenance URI writer and reader, distinguishing
   identity stored for audit from a location used for later access (7.11
   records it);
4. an explicit base/root or URI-scheme contract, with relocation, security
   boundaries, and compatibility for existing absolute and `RepoRoot`-relative
   values.

**R5 (manifest ownership of session-specific declarations): deferred beyond
v2**, confirmed. The real-data plan found that every real session needs its own
profile. That is evidence for R5, which 7.14 records as the R5 inventory. It is
not a reason to build R5 in the closing phase.

### D15. Closure invariants

See [Closure invariants](#closure-invariants) below, numbered so 7.18 can cite
them.

### D16. Documentation labels: usable, experimental, internal; one table in the usage guide

7.15 applies three labels:

| Label | Meaning | Members at 7.1 |
|---|---|---|
| **usable** | Documented, contract-governed and tested within the prototype. Still a prototype: uncalibrated where it says so | Intake and source mapping; the three extractor imports; matching, agreement, consensus and population selection; alignment intake, fitting and projection; geometry and tracking registration and reads; acoustic reference registration and measurement; the canonical attribution API (`createRun`, `addCandidates`, `addEvidence`, `correspondWindows`, `decide`, `report`, `resolveTargets`); imported and backend intake; `vawlume.export.database`; `vawlume.schema.*` |
| **experimental** | Works and is tested, but its method or output shape may change without a contract change, and its numbers carry no calibrated meaning | The native estimator (`vawlume.estimator.*`); call-window measurement and call-level normalization; the consilience exploration's runner and its public stages; Phase 7's `compare`, the sensitivity entry points, and `qcFacts` |
| **internal** | Public only so that packages or demonstrations can call it. Not user API | `vawlume.internal.*`; `vawlume.export.internal.*`; fixture builders (`buildPhase1Fixture`, `buildIntegratedFixture`); `+eda` building blocks that exist for the runner's composition (rendering, styling and helper functions 7.15 enumerates) |

**Where the label lives:**

- **One authority**: a "Status of public functions" table in
  `docs/prototype/01_usage_guide.md`. `docs/prototype/00_overview.md` links to
  it and does not restate it.
- **Help text** of each experimental entry point gains one pointer line,
  `Status: experimental (usage guide, "Status of public functions")`. It is a
  pointer, not a second copy of the label.
- **Internal functions are not documented in the usage guide** beyond the
  table.

7.15 also renames the v1 "Phase 6" wording in user-visible strings and in
development docs 02, 07, 09 and 10. One live example is in `matchingLoadSpec`'s
error text, "does not match the Phase 6 contract".

### D17. `readWindow` uses exactly one transform, or says why it cannot (P6-4)

**Raised by the repository.** `trackingResolveAlignmentRun` selects
`ORDER BY r.alignment_run_id DESC`, so with two usable fits the newest wins
silently. That is the "latest of anything" lookup the native path refuses.

**Decision (7.12):**

- `readWindow` gains `AlignmentRun=<id>`;
- with `ReferenceTimebaseKey` and **exactly one** usable completed transform,
  behaviour is unchanged;
- with **several** and none named, it returns
  `reference_time_status = "transform_ambiguous"`, listing the candidates'
  ids, and leaves native times untouched. It does not raise.

The status is in keeping with `readWindow`'s "common time is optional and never
faked" rule. The native path already names its run and is unaffected.

### D18. EXP-006 is owned by 7.12

**Raised by the repository.** The consilience closure ledger carries EXP-006:
`summarize` raises on a hand-edited NULL temporal metric. The Phase 7 map's
ledger table omits it. It joins 7.12's consilience items: fix, or re-defer with
a reason.

### D19. The real-data harness lives in the development repository and has an owner

**Raised by the repository.** The real-data plan's R1 stage (harness, preflight,
clock-table extraction, session profiles, smoke database, cost calibration) has
no owning itinerary in the map. It belongs to **7.14** (D12's split):

- **Scripts** live in the development repository's real-data QC scripts folder.
  They call VAWLUME only through public functions, and write only under
  configured roots in the private workspace. They are never in the software
  repository.
- **A prepared input may derive within one clock only** (a GPIO edge table, a
  parsed controller log, video time from per-frame timestamps). Every
  cross-clock placement goes through `vawlume.alignment.*`, so invariant 9
  holds in QC code too.
- **Any part expected to exceed about 30 minutes is prepared as a script**,
  with progress output and a log. The user runs it and returns the log:
  - R1.6's cost calibration;
  - R2-C's exploration;
  - possibly R1.1's hashing on a cold OneDrive cache.
- **Real-data defects are recorded, not fixed**, in the pass that finds them.

### D20. `bracket_extrapolated = true` is a fixture fact

**Raised by the repository.** The map assigned "`bracket_extrapolated` exercised
only as `false`" to 7.8, through an alignment variant. The flag is computed
where tracking samples bracket an instant (`positionsAtInstants`,
`candidateGeometry`). A call outside the tracking bracket is a scene, so **7.3's
out-of-bracket scene closes the item**. 7.8 may still show a variant moving the
flag, but that is not the closing evidence. One owner: 7.3.

---

## Inherited-ledger audit

One row per carried item. "Re-defer" means beyond v2, with the reason stated.
The delta plan in the development repository mirrors this table with
tripwires.

### From Phase 6 (6.13 §10)

| Item | Disposition | Owner |
|---|---|---|
| Invariants 24/26 DEV halves (canonical layer accepts a native probability or label-only pose row) | Fix: D9 | 7.2 (DDL), 7.4 (API) |
| No signal when the method's assumption fails | Fix as a QC fact, with its stated blind spot: D8 | 7.10 |
| Only the first no-score reason stored | Fix: D10 | 7.2 (DDL), 7.4 (writers), 7.5 (reader) |
| v1 "Phase 6" naming in user-visible strings and docs 02/07/09/10 | Fix: D16 | 7.15 |
| Demo refusal harness checks failure, not identifier | NO ACTION: the integration test pins identifiers | — (7.18 carries) |
| Invariant-25/30 guards skip text after `%` inside a string | NO ACTION: recorded | — (7.18 carries) |
| P6-1: two writers of `attribution_run_declared_inputs` | Fix: one writer. A `private/` helper cannot cross from `+ingest/` into `+attribution/`, so 7.4 chooses between `createRun` accepting a backend run's declarations from intake's plan, and one public `+attribution/` writer both paths call. It records the choice | 7.4 |
| P6-4: `readWindow` picks its transform by newest run id | Fix: D17 | 7.12 |
| P4-2 / F5.10-10: relations in JSON | Re-defer: no Phase 7 join needs one (D10) | — |
| I-3: no windows table in `report` | Fix: `report` gains a `windows` table, one row per imported window, with its native times and provenance as stored. Window-level counts stay in `qc` | 7.5 |
| I-6: unpaged `report` | Fix: `report` gains `Targets=` (a target-id filter) and `Tables=` (a projection). Default behaviour is unchanged | 7.5 |
| I-5: `ordinal_source` not stored | Re-defer: no Phase 7 consumer (D10) | — |
| 6.6/6.7 schema items | Re-defer: D10 | — |
| `bracket_extrapolated` exercised only as `false` | Fix: D20 | 7.3 |
| Session fixture in four places | Fix: D11 | 7.3 |
| Three near-copies of `+acoustic/` persistence helpers | Fix: one private helper set | 7.12 |
| I-1 extended: no real backend export, no real paired session | Limitation. 7.14 records the real data that does exist. Neither gap closes | 7.18 carries |
| F5.10-12: stale development-repository protocol references | User's development-repository maintenance; 7.17 lists them | — |
| Accepted limits: guard blind spots (hand-written arithmetic; neutral-name combination; invariant-26 same-line); exact-band matching; `min_distance` in frame units; `report` reading the profile by `content_uri`; writers without `"caller"` mode | NO ACTION | 7.18 carries |

### From the consilience-exploration MVP (part 17b §10)

| Item | Disposition | Owner |
|---|---|---|
| EXP-048: four-recording real-data acceptance | Run: R2-C | 7.14a (script, user-run) |
| EXP-050: about 5.8 h on one recording; redundant identical-frame subset probe | Fix: profile, and short-circuit identical whole/subset frames before 7.14 | 7.12 |
| EXP-051: undefined partial-correlation figure lacks one prominent refusal message | Fix or re-defer | 7.12 |
| CAL-001 DEV half: duration factor is absolute | Re-defer: changing `vawlume.interval.relation` is not recommended in the closing phase | — |
| EXP-038: reference profile names a synthetic evidence basis | Re-defer to the next deliberate version of that profile. 7.9 must not bump it to make variants | — |
| EXP-042, EXP-043, EXP-044, EXP-045, EXP-005 residue, EXP-013 | Fix or re-defer, each | 7.12 |
| EXP-006: `summarize` raises on a hand-edited NULL temporal metric | Fix or re-defer: D18 | 7.12 |
| EXP-036: no pooled multi-recording profiler | Re-defer: D12 | — |
| EXP-014: design-incompleteness signal does not survive the session | Re-defer: the consumer refuses incomplete designs by default, and no Phase 7 consumer reads a design across sessions | — |
| EXP-024: shared analysis carries only the first probe's dependency role | Re-defer: design records still list configurations and recordings. D2's families link attribution runs, not agreement analyses, so they do not inherit the gap | — |
| CAL-002: review table cannot target an agreement group | NO ACTION: moot | — |

### From the CSV-export MVP (part 8 §10)

| Item | Disposition | Owner |
|---|---|---|
| P7-5: the `java.io.File` relative-path idiom, 39 occurrences in 27 files | Fix: D14 | 7.11 |
| Newline, non-ASCII and BLOB values proven only by unit tests | Fix in part: the fixture carries non-ASCII and newline values (D11), and 7.13 audits the export. BLOB stays unit-proven: no VAWLUME column holds one by design | 7.3, 7.13 |
| `tp*` image caches left in `%TEMP%` by figure suites | Fix | 7.12 |
| I-1 (`data_version` detects, does not isolate), I-3, I-4, P5-2, P5-3, P5-4, P7-6 | NO ACTION: known limitations | 7.18 carries |

### From the bug fixes

| Item | Disposition | Owner |
|---|---|---|
| MUPET reader leaves non-lexical numeric mappings to MATLAB type inference | Fix: adapter hardening | 7.12 |
| MUPET recheck against the untouched 1,317-row file | **Substituted.** That file belongs to the left microphone, which the user put out of scope. 7.14a rechecks the same real shape on the four right-microphone MUPET files (one terminal `_` each). 7.14 also confirms from the part 17a record whether the 1,317-row file was already ingested there | 7.14a |
| USVSEG `NaN` recheck (1,159 rows) | **Substituted** as above: the four right-microphone USVSEG files (1–28 `NaN` rows each) | 7.14a |
| Persistent-database lifecycle: registry sync, no DDL migration | Policy: D12 (rebuild). Guard: D13 | 7.13 (guard), 7.14a (follows policy) |
| R7: portable provenance roots | Re-defer: D14 (user) | — |
| R5: manifest ownership | Re-defer: D14 (user) | — |
| Corrected CH6 alignment rerun | Run: R2-D | 7.14a |
| USVSEG long-mode chunk boundaries | Re-defer: architectural | — |
| Stale self-description usage-guide path | Resolved before Phase 7 | 7.17 confirms |
| Registry-sync handoff: the full gate was not run | Superseded: gates have run since (6.13). Nothing carries | — |

---

## Closure invariants

7.18 verifies each by a **search for its violation** plus the evidence named.
Numbers 1–31 are Phase 6's, as contract 06 D12 froze them and 6.13 §9A
measured them. This contract revises two of them and adds 32–54.

**Carried, 1–31.** Unchanged except:

- **24 (revised):** No native candidate carries a probability, **enforced by
  the schema for every writer**, and every native score's semantics say it is
  not one. Verdict sought: HOLD (D9).
- **26 (revised):** A track reaches an entity only through a cited
  `tracking_identity_associations` row, **and the schema refuses a native pose
  or identity evidence row without one**. No string comparison between a track
  label and an entity id exists in `+estimator/` or `+tracking/`. Verdict
  sought: HOLD (D9).

**The workstream invariants:**

32. No consilience-exploration output selects, ranks or recommends a threshold.
    No argmax over configurations exists, and no selected-threshold field
    exists. *Search:* `selected_threshold`, `argmax`, `best_config`, and
    `optimal`/`recommended` not negated, in `+eda/` and its exports.
33. No frequency extent is fabricated. Gallery and annotation geometry come only
    from measured extractor values. *Search:* any band synthesized from a centre,
    peak or coefficient of variation.
34. An ill-conditioned partial correlation is refused (`NaN` plus reason), never
    regularized. *Search:* ridge, shrinkage or diagonal loading in `+eda/`.
35. The reference configuration is declared, never chosen from results.
    `referenceConfiguration` takes no result argument. *Search:* any call
    passing a probe result to it.
36. Column meaning has one authority, `schema/schema_metadata.json`, and
    `validateMetadata(Mode="complete")` passes at the live schema.
37. The CSV export is a faithful relational projection: per-object counts and
    headers equal SQLite, with no join, alias or summary.

**The bug-fix invariants:**

38. Missing-value tokens are profile-declared and field-scoped. The raw token is
    preserved, and no missing value becomes zero. *Search:* a profile missing
    token without a field scope; a stored zero where the raw token is a declared
    missing token.
39. Profile versions are append-only and checksum-immutable. Registry sync
    appends and never mutates a prior row.
40. Non-native clocks default to recording scope. A shared clock requires
    explicit `scope: "project"`.
41. A stream key names immutable evidence. Changed evidence under an existing
    key is a conflict.
42. A cited anchor time means the event onset, within the documented roundoff
    tolerance only.

**Phase 7's own:**

43. A comparison produces no combined value: no merged caller, consensus
    decision, combined score, "best" path or composite agreement score.
    *Search:* D4's forbidden column names in every Phase 7 output.
44. No value is compared across paths. A score comparison exists only under an
    identical method, method version, settings-profile version and recording,
    and is otherwise refused by name (`ScoreNotComparable`).
45. A structural empty is never counted as disagreement, and an undeclared input
    is never counted as `not_used`.
46. Correspondence between event sets comes only from stored rows of a named
    analysis. *Search:* any interval or matching primitive called by `compare`
    to make a join.
47. Sensitivity selects nothing. No argmax over variants exists, and no output
    calls a setting, threshold or path "optimal", "best", "recommended",
    "validated" or "calibrated" except in a negation.
48. Comparisons and sensitivity summaries are recomputable from storage. No
    table holds a comparison result, and a rerun on the same database gives
    identical tables.
49. Every sensitivity family's reference variant is named in its specification
    before any variant is applied. The planner has no access to results.
50. Every Phase 7 integration guard (D13) fires when its violation is injected.
51. The QC facts (D8) write nothing, change no score or decision, and are not
    computed inside `report`.
52. Every unscored candidate's reasons are stored in full, in producer order
    (D10), and a scored candidate has none.
53. `+attribution/` depends only on `+alignment`'s transform appliers (at 7.1,
    `applyTransformInterval` alone), `+geometry.assertCompatible`, `+interval`,
    `+db` and `+schema`. `+interval` depends on no VAWLUME package, and
    `+matching` only on `+interval`. *Search:* code references, comments and
    help text excluded. At 7.1 `+attribution/` names `+estimator` and `+ingest`
    only in help text and error prose.
54. Caller-supplied paths resolve through `vawlume.internal.resolvePath`.
    *Search:* `java.io.File(...).isAbsolute` and `getCanonicalPath` outside it
    and its documented wrappers.

## Plan §19: the evidence 7.18 will gather

"Architecture" means the representation and machinery are shown on synthetic
data generated by this repository. It does not mean the capability is shown on
real data. Criteria 1, 9, 10, 11 and 13 can be satisfied **only as
architecture** in their real-data reading; 7.14a may move 1 and 13 partly.

| § 19 | Synthetic evidence (source) | Real-data reading (source) | Expected at 7.18 |
|---|---|---|---|
| 1. One recording through DeepSqueak, MUPET, USVSEG | 7.3 fixture; Phase 1 suites | Four right-microphone recordings (7.14a R2-A/B) | Met on real data |
| 2. Native detections distinct | Agreement and matching suites; invariant 2 | Ingestion reconciliation (R2-B) | Met on real data |
| 3. Temporal (± spectral) matching | Matching suites | Exploration (R2-C) | Met on real data; the spectral space is thin |
| 4. Split, merge, ambiguity preserved | 7.7's units on the fixture | Exploration (R2-C) | Met on real data |
| 5. Tracking and geometry registered without raw video | Phase 2 suites; the fixture | None (no tracking exists) | Synthetic only |
| 6. Track ≠ entity identity | Invariant 26 (D9); the identity-swap scene | None | Synthetic only |
| 7. Multiple streams aligned | Alignment suites; the fixture | Audio, controller, GPIO, video same-origin (R2-D) | Met on real data |
| 8. Drift-aware alignment, QC-able | Piecewise suites; the fixture | Affine with about 200 ppm drift (R2-D). Piecewise is not supportable (three anchors) | Affine on real data; piecewise synthetic |
| 9. External caller estimates imported and matched | Imported path suites; the fixture | Optional R2-H, protocol-derived claims (mechanics only) | Architecture; mechanics on real event density if R2-H ran |
| 10. Backend outputs mapped | Backend suites; the fixture | None | Architecture only |
| 11. Native dual-microphone estimator | Phase 6; the fixture; `qcFacts` | Not applicable: separate files (refusal observed), no tracking, no geometry | Architecture only |
| 12. Unassigned or multiple callers | Decision suites; native and co-occurrence policies | Optional R2-H | Synthetic; mechanics if R2-H ran |
| 13. Compared across event sets, paths, settings, normalization | 7.6–7.9 on the fixture | Optional R2-H: across extractor event sets only | Architecture; one real reading if R2-H ran |

## What comparisons and sensitivity analyses may and may not claim

**May claim:**

- where two stored runs select the same entity, the same set, or the same
  status, and where they do not, per unit;
- how a conclusion (a selected set, a status, a scored state, a rank) moves
  when one declared input changes, with every other input held;
- which handles method 1.0.0 does not let vary;
- that the machinery joins correctly, on the fixture.

**May not claim:**

- **that any path, variant, setting or threshold is right**, better, optimal,
  recommended, validated or calibrated;
- **that agreement between paths is evidence of accuracy.** On the fixture,
  every path's input was generated by this repository, so agreement is
  circular;
- that a score difference across paths, recordings or settings-profile versions
  means anything;
- that a structural empty or an unknown input is a disagreement;
- that a sensitivity result generalizes beyond the fixture or dataset it ran on.

## Constraints inherited from elsewhere

From contracts 05 and 06, still binding:

- **The MATLAB Database Toolbox raises on any SQL NULL in a result set**,
  including aggregates over empty sets. Every new nullable read (the
  no-score-reason table's outer join, a decision cell with no decision, a
  correspondence count over an empty set) needs the established `IFNULL(...)`
  sentinel treatment, and every count needs a test over an empty set.
- **It can also return empty TEXT as `<missing>` even under `IFNULL`.** Every
  nullable text read goes through a `presentText`-style normalizer.
- **Absence reads as absence:** `NaN` for a number, `""` for text, never `0`
  and never `1.0`.
- **Insert-only scope triggers are the repository convention** (schema §14),
  with `_update` twins only where a change alters a row's meaning. D9 and D10
  qualify.
- **The semantic metadata document is the single authority for column
  meaning.** New objects need descriptions in the same change as the DDL, or
  the completeness gate fails.
- **`regexp` over MATLAB source is DOTALL by default, and comments are not
  code.** `regexp(..., "once")` over a string returns `<missing>` on no match,
  which is not empty. Every scanner (D13) enumerates and reads its matches, and
  is injection-verified.
- **"Phase 6" and "Phase 7" in `01_prototype_development_outline.md` and
  `02_temporal_alignment_contract.md` mean prototype v1.** A finding labelled
  "P7-5" is CSV-export Part 7 finding 5, not a Phase 7 finding.
- **`TaskStop` kills a shell but not its MATLAB child.** Check for orphaned
  MATLAB processes before timing anything.

## Phase 7 non-goals

- a new native method version, or any method that combines evidence beyond
  method 1.0.0;
- a merged, consensus or "best" attribution across paths, or any composite
  agreement score;
- threshold calibration, recommendation or optimization, on either side;
- a comparison-specific result model, or persisted comparison tables;
- schema migration machinery;
- new intake formats, a real backend adapter, raw-video processing,
  continuous-signal (trace) ingestion, a GUI, or human-in-the-loop review;
- relating the two real microphones (the inter-microphone consilience module),
  or merging their files into one recording;
- user-guided anchor refinement;
- R5, R7, I-5, the 6.6/6.7 schema items, P4-2 promotion, the exporter-identity
  column, CAL-001, EXP-014, EXP-024, EXP-036, EXP-038;
- USVSEG long-mode chunk-boundary behaviour;
- spatial terms in window correspondence (contract 05 D10's open question:
  answered "not in v2");
- extending the generic imported profile to declare its consumed inputs
  (contract 05 D7's deferral stands).

## What Phase 7 and the v2 round will not be able to claim

Written at 7.1, while it is cheap, and carried to 7.18.

- **Cross-path agreement on synthetic fixtures is circular.** The repository
  generated every path's input, so agreement shows the machinery joins
  correctly, not that any path is accurate.
- **No real backend export and no real paired session have ever been
  ingested.** Real data cannot show native attribution: the real rig's two
  microphones are separate files with unknown relative clocks, and there is no
  tracking or geometry.
- **No ground truth for who called exists** for any recording VAWLUME has seen.
- **No score is comparable across recordings**, and no response estimate or
  threshold is calibrated.
- **Sensitivity shows how conclusions move** under stated variations of
  declared inputs. It selects nothing, and moving or not moving is not
  evidence of correctness.
- **The QC facts make the method's margin visible, not its failures.** A wrong
  animal that fits well is not detectable from storage.
- **Real-data acceptance is functional and consistency acceptance only:**
  - one acquisition day, four animals, one rig, the right microphone only;
  - three anchors per clock pair;
  - behaviour coded to the second;
  - protocol epochs asserted by the controller program, not observed;
  - the video rate discrepancy recorded, not resolved.
- **The empty-chamber control is protocol-asserted**, and white-noise marker
  windows overlap the lower call band.
- **The audio anchors embed the controller's tone schedule.** A systematic
  offset common to all four sessions would not appear in any residual.
- **Whatever 7.14 / 7.14a did not run** is carried to 7.18 as not run,
  unchanged.

## Definition of done for Phase 7

- `vawlume.attribution.compare` compares any two runs on one recording, over
  one event set or through a named analysis, in D4's closed columns, and
  refuses D5's cases by name;
- sensitivity families over D6's handles and D7's matching configurations are
  recorded as D2 specifies, and summarized without selecting anything;
- `vawlume.estimator.qcFacts` reports D8's facts and its blind spot;
- invariants 24 and 26 hold for every writer (D9), and every no-score reason is
  stored (D10), in one bump to `0.14-draft`;
- one shipped builder (D11) serves the tests and the demonstration;
- plan §12's six checks and the cross-workstream checks are
  injection-verified guards (D13);
- path resolution has one home (D14);
- every carried ledger item is closed with evidence or re-deferred with a
  reason;
- the real-data acceptance ran as far as D12 allows, or is recorded as not
  run;
- the documentation is labelled per D16;
- the full gate passes on a committed candidate, and 7.18 verifies
  invariants 1–54 and plan §19.

## Related documents

- [`04_caller_attribution_contract.md`](04_caller_attribution_contract.md): the attribution model the comparison reads
- [`05_backend_localization_contract.md`](05_backend_localization_contract.md): declared inputs (D7), the "Phase 7 question" its D10 left
- [`06_native_estimator_contract.md`](06_native_estimator_contract.md): the method, its licence, invariants 1–31
- [`../development/31_caller_attribution_schema.md`](../development/31_caller_attribution_schema.md): the attribution data dictionary 7.2 extends
- [`../development/35_consilience_exploration_workflow.md`](../development/35_consilience_exploration_workflow.md): the exploration whose machinery D2 and D7 reuse
- [`../development/42_call_level_normalization.md`](../development/42_call_level_normalization.md): the normalization D6 varies
- [`../development/44_native_estimation_run.md`](../development/44_native_estimation_run.md): the run D8 reads
- [`../development/45_integrated_native_estimator_demonstration.md`](../development/45_integrated_native_estimator_demonstration.md): the model-mismatch scene D8's blind spot names
- [`../development/12_alignment_intake_and_registration.md`](../development/12_alignment_intake_and_registration.md): the alignment-intake rules invariants 40–42 carry
- [`../development/30_repository_self_description.md`](../development/30_repository_self_description.md): what moves with a version
- [`../../schema/README.md`](../../schema/README.md): the three schema artifacts a bump moves together
- [`../prototype/01_usage_guide.md`](../prototype/01_usage_guide.md): where D16's labels will live
