# 47. Attribution-side sensitivity

`vawlume.eda.attributionSensitivity` makes a **family** of variants of one
native attribution run. Each variant changes one declared input. It records the
family, and `vawlume.eda.sensitivitySummary` reports how conclusions move
against a reference **declared before any result exists**. Built at itinerary
7.8. Contract 07 D1, D2 and D6 are the design. 7.9 adds the matching-side
handles beside these.

```matlab
plan    = vawlume.eda.attributionSensitivity(conn, familySpec);              % prints, writes nothing
applied = vawlume.eda.attributionSensitivity(conn, familySpec, Apply=true);
summary = vawlume.eda.sensitivitySummary(conn, ...
    struct(analysis_run_id=applied.family_analysis_run_id), Export="summary.csv");
```

## It selects nothing

A variant says how a conclusion moves when one input changes. Nothing here, or
in the summary:

- orders variants by outcome;
- labels one as preferred;
- calls a setting "optimal", "best", "recommended", "validated" or
  "calibrated".

Rows are ordered by handle and value. The reference is the configuration the
others are compared with, and declaring it makes it neither correct nor
calibrated. A guard test fails on any of those words, or on "stable", in the
summary's columns, cells or note. On synthetic data every movement is the
generator's.

## The family specification

| Field | Meaning |
|---|---|
| `family_key` | The family record's run key |
| `output_root` | Where generated profile files go. Refused under `config/` |
| `reference.attribution_run_id` | An applied native run |
| `reference.run_spec` | The `attributeCallers` run spec that produced it. Its `run_key` and settings version must match storage |
| `reference.decision_policy` | The policy file the reference was decided under |
| `variants` | `struct(handle=..., value=struct(<factor>=...))`, one per variant |

## Handles

| Handle | Factors | A variant is | Re-reads audio? |
|---|---|---|---|
| `decision_policy` | `selection_threshold`, `separation_margin`, `co_occurrence_threshold` | A second decision set on the **reference run**, under a generated policy version | No |
| `estimator_settings` | `primary_instant_basis`, `max_interpolation_gap_s`, `min_distance`, `channel_pair` | A generated settings version, then a new `attributeCallers` run that reuses the reference's normalization runs, then `decide` under the reference policy | No (re-reads tracking windows) |
| `normalization_policy` | `reference_type` (for example `tone`) | A generated normalization policy, then `normalizeCallLevels` on each target's call-window and response runs, then a generated settings version naming that policy (6.12a requires the match), then a run and `decide` | No |
| `alignment_run` | `audio_alignment_run_id`, `tracking_alignment_run_id` | A new run naming another, already fitted alignment run, then `decide` | No |

**Generated, never shipped.** Each variant has a configuration id by the
exploration's rule (`edaConfigurationIdentity`):

- SHA-256 over the name-sorted `handle.factor=value` pairs, prefixed `cfg-` and
  cut to ten hex characters;
- numbers formatted `%.17g`, numeric vectors joined by `,`, and text verbatim.

Numeric ids are bit-identical to those before 7.8; a test pins them.

A generated profile keeps the reference's key and takes the version label
`<reference version>+sens.<configuration_id>`. Only the varied values and the
version label differ from the reference file. Each edit is made in its own JSON
member and must match exactly once there. Files are written under
`output_root` and registered through `vawlume.db.registerProfileVersion`. **No
file under `config/` is added or edited.** In particular, the tone-family
normalization alternative is generated from the shipped noise policy (contract
07 D6). It is not a shipped profile, because the one real rig's scheduled tones
lie far below the call band.

**An alternative alignment fit** is a second alignment set: the same anchors
under another declared model (for example `offset`), or with an anchor withheld
through `setAnchorInclusion`. It goes through `ingest.alignment` and
`alignment.fit`. `fit` never rewrites a completed transform, so the variant
names that set's `alignment_run_id`. The orchestrator fits nothing.

**Handles that are not varied** are rows in every summary, each with its
reason. Requesting one as a variant raises
`vawlume:eda:SensitivityHandleNotVariable`.

| Handle | Status | Why |
|---|---|---|
| `pose_confidence_gate`, `temporal_uncertainty_gate_s` | `not_variable` | Method 1.0.0 implements no gate (`SettingsGateNotImplemented`) |
| `dimension_declarations` | `not_variable` | Method 1.0.0 uses all four dimensions (`SettingsDimensionMisdeclared`) |
| `positional_error` | `reported_elsewhere` | A read-only margin in `vawlume.estimator.qcFacts` (7.10), not a variant |
| `identity_uncertainty` | `not_measurable` | Method 1.0.0 admits identity only as resolve-or-unscored, so there is no continuous handle |
| `call_band` | `not_exercised` | It re-measures audio, which attribution-side sensitivity does not do |

## Plan, apply, record

- **Planning is the default** and writes nothing (checked with
  `data_version` and `total_changes()`). It prints each variant's id, value and
  predicted cost: runs, decisions, normalization runs and profile versions, and
  states that no audio is re-read.
- **Apply executes exactly the plan.** The executed row deltas equal the
  predicted totals, and a test checks this.
- **The family record** is one `analysis_runs` row
  (`run_type = attribution_sensitivity`, `run_key = family_key`, its notes
  carrying the design SHA-256). It also has:
  - `analysis_run_sources`: `sensitivity_reference` for the reference run's
    analysis run, and `sensitivity_variant` for each variant run;
  - the design record (the declared design, plus every variant's run and
    profile-version ids), registered as an `analysis_settings` profile version
    linked with `sensitivity_design`.

  A policy variant is not a run: the design record names its policy version. No
  comparison result is stored (D2).
- **Re-applying the same design** is reported `reused`. A different design under
  the same key raises `vawlume:eda:SensitivityFamilyConflict`.
- **Producers own their transactions,** so a failure part-way leaves the
  variants already applied. Their run keys are deterministic
  (`<family_key>.<configuration_id>`).

**Refusals:** `SensitivityReferenceRequired` (no reference, or one that does not
describe its stored run), `SensitivityHandleNotVariable`,
`SensitivityHandleUnknown` (handle or factor), `SensitivityFamilyConflict`.

## The summary

For each variant, `sensitivitySummary` calls `vawlume.attribution.compare` on the
reference against the variant:

- a policy variant compares the reference run with itself, naming both policy
  versions;
- `CompareScores=true` is used only where `compare` reports the pair
  `comparable`.

`rows` has one row per variant and per reported handle:

| Column | Meaning |
|---|---|
| `family_key`, `handle`, `configuration_id`, `handle_value`, `variant_kind` | Identity (`decision_set` or `run`) |
| `status`, `reason` | `variant`, or the reported status and why |
| `score_comparability` | As `compare` states it |
| `one_to_one_units` | The denominator |
| `top_same`, `top_different`, `top_tie`, `top_unscored`, `top_orientation_unknown` | Top-entity agreement, counted |
| `sets_equal`, `sets_both_empty`, `sets_differ` | Selected-set relation, counted. Equal non-empty sets and "neither selected anyone" are kept apart, as `compare` keeps them |
| `status_agree`, `status_disagree`, `status_structural_empty`, `status_excluded`, `status_undecided` | `compare`'s status cross-tab by cell kind |
| `reasons_changed` | (target, entity) pairs whose stored no-score reasons, in order, differ from the reference's |
| `scores_changed` | Differing score pairs, only where values compare; NaN otherwise |
| `units_one_to_one`, `units_one_to_many`, `units_many_to_one`, `units_many_to_many`, `units_unmatched_left`, `units_unmatched_right` | Correspondence units by category (7.9). On one event set, all are `one_to_one` |
| `targets_lost`, `targets_gained` | Reference targets with no counterpart in the variant, and the reverse |
| `pairs`, `pairs_top_same`, `pairs_top_different` | Within-unit target pairs and their top-entity agreement |

The per-unit detail is `comparisons(k).comparison`, which is `compare`'s own
result. `Export=` writes the rows with `writeTableExport`. Its provenance block
carries:

- the family id;
- the reference run, settings and policy versions;
- every variant's policy and settings versions;
- the design SHA-256;
- the schema version and the MATLAB version.

## Matching-side families (`correspondenceSensitivity`, 7.9)

```matlab
plan    = vawlume.eda.correspondenceSensitivity(conn, familySpec);   % prints cost, writes nothing
applied = vawlume.eda.correspondenceSensitivity(conn, familySpec, Apply=true);
summary = vawlume.eda.sensitivitySummary(conn, struct(analysis_run_id=applied.family_analysis_run_id));
```

**Where the matching side reaches attribution.** A matching configuration
changes the consensus events. Those events are attributed, and two
configurations' runs are compared through `compare`'s
`Correspondence=struct(shared_member_detections=true)`. That joins consensus
events where their stored members share a detection (contract 07 D3's third
join).

**The specification fields:**

- `family_key`, `output_root`, `recording_id`;
- `extraction_runs` (every pair is matched);
- `consensus_pair` (the pair whose analysis supplies the attributed consensus
  events);
- `reference`:
  - an optional `specification_path` (the tracked specification by default,
    through `vawlume.eda.referenceConfiguration`);
  - `run_spec`: the native fields every configuration shares (settings,
    participants, clock, tracking);
  - `decision_policy`;
  - `measurement`: channels, band, audio source root and response run;
- `variants`.

**Handles:**

| Handle | Factor | A configuration is |
|---|---|---|
| `matching_temporal` | `min_temporal_iou` | A generated specification whose `plausibility_rule.min_temporal_iou` differs |
| `matching_spectral` | `relative_tolerance` | A generated specification whose every `feature_support.discrepancy_tolerance` entry differs |
| `matching_duration` | — | Reported `not_variable`: the tracked plausibility rule has no duration bound. Were one added, CAL-001 applies: the duration difference is in absolute seconds, so its axis is not scale-free |

Generated specifications follow the same byte-copy rule (`+sens.<id>`). The
tracked specification is never edited.
`vawlume.eda.materializeConfigurations` is not used. It overrides only
`plausibility_rule` fields, so it cannot make a spectral variant, and it expects
a full screening design.

**Per configuration, the reference included:**

1. `matching.compare` for every pair, and `agreement.compose`. An applied
   analysis over the same runs and recording, with an identical specification
   checksum, is reused (contract 07 D7). On the fixture the reference
   configuration reuses the fixture's own analyses.
2. For each consensus event of the consensus pair's analysis:
   `measureCallWindow`, which **reads audio**, and `normalizeCallLevels`.
3. `attributeCallers` over those consensus events, then `decide`.

**Cost.**

- The plan prints the analyses (the consilience formula: N(N−1)/2 matching plus
  one agreement per configuration, minus reuse), the runs, and the consensus
  events to measure. That last count is estimated from the reference analysis:
  a configuration's own count exists only after its matching.
- Apply measures the wall time per configuration. On the 7.3 fixture this was
  roughly 8–18 s per configuration.
- EXP-050 is the warning: analysis counts do not predict wall time on real
  data. No real-data run of this orchestrator happens in Phase 7.

**The summary** reads a matching-side family with the same columns. The unit
categories and the targets lost or gained carry the correspondence movement.
The reference configuration has no row.

**What the fixture shows:**

- **`min_temporal_iou` 0.9.** The DeepSqueak–MUPET consensus events go from 9
  to 7. Two reference consensus events have no counterpart and become
  `unmatched_left` (2 targets lost). One of them is the merge: two DeepSqueak
  detections against one MUPET call. The other 7 units stay `one_to_one`.
- **`relative_tolerance` 0.001.** The reach is demonstrated, not assumed:
  - every match-group, agreement-group and consensus-event member set is
    identical to the reference's;
  - every unit is `one_to_one` with no set or status disagreement and no score
    change;
  - the consilience classification (`vawlume.consilience.summarize`) moves 7
    groups from `matched_feature_supported` to `matched_feature_discrepant`.

  The tolerance governs classification only, as the consilience contract says.

## What the 7.3 fixture shows

- **Stricter threshold.** A selection threshold of −1 dB turns model_mismatch
  from `assigned` into `unassigned`. B fits within 3 dB but not within 1 dB. No
  score moves.
- **Instant basis.** `onset` instead of `midpoint` leaves the symmetric scene
  `ambiguous`. Its scores do **not** move, because the fixture's animals are
  stationary, so no distance depends on the instant. The variant is
  `not_comparable:settings_profile_version`.
- **Tone normalization.** Dividing by the tone family's estimate changes the
  normalized levels.
- **Offset alignment.** The variant's clock evidence cites the offset fit. It
  compares values (same settings). The out-of-bracket call's distance rows
  still read `bracket_extrapolated=true`. That is 7.3's scene; the variant only
  carries it.
