# Phase 1 Synthetic Fixture

This source document defines the deterministic fixture inserted by
`vawlume.db.buildPhase1Fixture`. It is intentionally text/source controlled:
tests build a temporary SQLite database from `schema/schema.sql`, register the
built-in DeepSqueak and MUPET semantics, and then populate these rows.

## Stable Keys

- Project: `phase1_synthetic_fixture`
- Study entity: `STUDY_SYNTH_USV`
- Cohort entity: `COHORT_A`
- Dyad entity: `DYAD_01`
- Subjects: `SUBJ_M01`, `SUBJ_F01`, `SUBJ_OBS01`
- Sessions: `SESSION_BASELINE`, `SESSION_SOCIAL`
- Recordings: `REC_SOCIAL_DYAD_01`, `REC_BASELINE_M01`

## Experimental Shape

The hierarchy is deliberately not a strict tree. The cohort contains three
subjects and the dyad, while the dyad has role-labelled membership edges to the
male and female subjects. The shared social recording links to the dyad, both
dyad members, and the social session. The baseline recording links to one
subject and the baseline session.

## Referenced Profile Artifacts

- Recording device profile:
  `config/02_device_profiles/recording_device_profile_examples.yaml`,
  profile `example.device.ultrasonic_usb_primary`, version `1`
- Experimental setup profile:
  `config/03_setup_profiles/experimental_setup_profile_examples.yaml`,
  profile `example.setup.mouse_courtship_chamber`, version `1`

The fixture stores the selected profile identity, version, source path, and
whole-file SHA-256 checksum in `config_profiles` and
`config_profile_versions`. Detailed profile bodies remain in YAML.

## Extraction Runs

`REC_SOCIAL_DYAD_01` has one DeepSqueak run and one MUPET run. DeepSqueak is
also run on `REC_BASELINE_M01` so repeated native event IDs are represented
across distinct extraction-run and artifact scopes.

Shared social detections:

| Logical case | DeepSqueak event | MUPET event(s) | Intended interpretation |
| --- | --- | --- | --- |
| Matched | `1`, 10.000-10.050 s | `1`, 10.004-10.052 s | one-to-one match |
| DeepSqueak-only | `2`, 20.000-20.040 s | none | unmatched native detection |
| MUPET-only | none | `2`, 30.000-30.035 s | unmatched native detection |
| Split/merge | `3`, 40.000-40.100 s | `3`, 40.002-40.045 s and `4`, 40.052-40.098 s | one DeepSqueak event to two MUPET syllables |

Baseline detection:

| Extractor | Native event | Time |
| --- | --- | --- |
| DeepSqueak | `1` | 12.000-12.040 s |

## Measurements

Every fixture detection preserves native timing/frequency values and additive
canonical values. DeepSqueak frequency values normalize `kHz` to `Hz`; MUPET
duration normalizes `ms` to `s`; and the final MUPET inter-syllable interval
preserves raw token `NA` as explicit missingness.

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
