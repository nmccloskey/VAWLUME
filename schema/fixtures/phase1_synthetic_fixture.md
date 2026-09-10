# Phase 1 Synthetic Fixture

This source document defines the deterministic fixture inserted by
`vawlume.db.buildPhase1Fixture`. It is intentionally text/source controlled:
tests build a temporary SQLite database from `schema/schema.sql`, register the
the built-in extractor semantics, and then populate these rows. Registration
covers every shipped extractor profile, so the semantic vocabulary is complete
whether or not a given extractor has an extraction run here.

## Stable Keys

- Project: `phase1_synthetic_fixture`
- Study entity: `STUDY_SYNTH_USV`
- Cohort entity: `COHORT_A`
- Dyad entity: `DYAD_01`
- Subjects: `SUBJ_M01`, `SUBJ_F01`, `SUBJ_OBS01`
- Sessions: `SESSION_BASELINE`, `SESSION_SOCIAL`
- Recordings: `REC_SOCIAL_DYAD_01`, `REC_BASELINE_M01`
- Extraction runs: `fixture_deepsqueak_social_v1`, `fixture_mupet_social_v1`,
  `fixture_usvseg_social_v1`, `fixture_deepsqueak_baseline_v1`
- Stored analysis runs: `fixture_cross_extractor_matching_v1`,
  `fixture_behavior_audio_alignment_v1`

A fixture detection is selected by extraction-run key plus native event id.
That pair is unique across the fixture, so tests never need a generated
`detection_id`.

## Experimental Shape

The hierarchy is deliberately not a strict tree. The cohort contains three
subjects and the dyad, while the dyad has role-labelled membership edges to the
male and female subjects. The shared social recording links to the dyad, both
dyad members, and the social session. The baseline recording links to one
subject and the baseline session.

## Referenced Profile Artifacts

- Recording device profile:
  `config/02_device_profiles/recording_device_profile_examples.json`,
  profile `example.device.ultrasonic_usb_primary`, version `1`
- Experimental setup profile:
  `config/03_setup_profiles/experimental_setup_profile_examples.json`,
  profile `example.setup.mouse_courtship_chamber`, version `1`

The fixture stores the selected profile identity, version, source path, and
whole-file SHA-256 checksum in `config_profiles` and
`config_profile_versions`. Detailed profile bodies remain in JSON.

## Extraction Runs

`REC_SOCIAL_DYAD_01` has one DeepSqueak run, one MUPET run, and one USVSEG run.
DeepSqueak is also run on `REC_BASELINE_M01` so repeated native event IDs are
represented across distinct extraction-run and artifact scopes.

Shared social detections:

| Logical case | DeepSqueak event | MUPET event(s) | USVSEG event(s) | Intended interpretation |
| --- | --- | --- | --- | --- |
| Three-extractor convergence | `1`, 10.000-10.050 s | `1`, 10.004-10.052 s | `1`, 10.0020-10.0490 s | one-to-one in all three pairs |
| DeepSqueak plus USVSEG | `2`, 20.000-20.040 s | none | `2`, 20.0010-20.0410 s | two extractors detect it; MUPET does not |
| MUPET plus USVSEG | none | `2`, 30.000-30.035 s | `3`, 30.0010-30.0360 s | two extractors detect it; DeepSqueak does not |
| Split/merge | `3`, 40.000-40.100 s | `3`, 40.002-40.045 s and `4`, 40.052-40.098 s | `4`, 40.0010-40.0430 s and `5`, 40.0500-40.0990 s | one long call against two syllable pairs |
| USVSEG-unique | none | none | `6`, 50.0000-50.0600 s | single-extractor evidence |

Baseline detection:

| Extractor | Native event | Time |
| --- | --- | --- |
| DeepSqueak | `1` | 12.000-12.040 s |

### Pairwise correspondence the geometry produces

The geometry is software-regression behavior, not biological calibration. Under
the tracked matching specification (`min_temporal_iou = 0.10`) it yields three
separately interpretable pairwise analyses:

| Pair | Candidates | Topologies |
| --- | --- | --- |
| DeepSqueak ↔ MUPET | 3 | one 1:1, one 1:many, two unmatched |
| DeepSqueak ↔ USVSEG | 4 | two 1:1, one 1:many, two unmatched |
| MUPET ↔ USVSEG | 4 | four 1:1, two unmatched |

Three-way support is not uniform, which is the point. At the split locus the
long DeepSqueak call supports both MUPET syllables and both USVSEG syllables,
while MUPET event `3` and USVSEG event `5` have no overlap at all: that trio is
supported by two of the three unordered pairs, not three. The two syllable-level
extractors agree one-to-one with each other there and both split the DeepSqueak
call.

The fixture stores matching rows only for the DeepSqueak/MUPET pair, and that
analysis has exactly two extraction inputs. The other two pairwise analyses are
produced by `vawlume.matching.compare` in tests rather than hand-authored here,
so the fixture never asserts a correspondence the matcher did not derive.

## Measurements

Every fixture detection preserves native timing/frequency values and additive
canonical values. DeepSqueak frequency values normalize `kHz` to `Hz`; MUPET
duration normalizes `ms` to `s`; and the final MUPET inter-syllable interval
preserves raw token `NA` as explicit missingness.

USVSEG contributes exactly the seven columns it exports, with the print
precision of its own exporter preserved in `native_raw_token` (four decimal
seconds, one decimal millisecond, three decimal kHz, one decimal dB, four
decimal ratio). It exports no frequency extent, no detection score, no
inter-event interval, and no curation or class evidence, so the fixture stores
none of those for it: `detections.detection_score` stays NULL and no
`curation_events` row exists for that run. USVSEG also writes no run-scoped
settings file, so `extraction_runs.settings_profile_version_id` stays NULL and
its only registered artifact is the summary CSV.

## Review, Matching, And Alignment

DeepSqueak-native `Accepted` curation is stored as extractor-authored
`curation_events`. Manual adjudication is separate in `manual_reviews`, including
a false-positive decision for the DeepSqueak-only event.

The matching layer contains legal candidate pairs, one-to-one and split/merge
match groups, unmatched groups, consensus events that retain native detections
as members, and consilience assessment rows.

An external behavioral event stream uses a controller timebase aligned to the
shared recording timebase with `target_time = source_time + 0.55`. Two external
events are materialized in aligned recording-relative seconds.
