# MUPET import

## Current boundary

MUPET import has two public entry points:

```matlab
export = vawlume.ingest.mupetExport(csvPath, ...)
result = vawlume.ingest.mupet(conn, csvPath, recordingRef, runSpec, ...)
result = vawlume.ingest.mupet(..., Apply=true)
```

`mupetExport` is database-free. It reads the profile-declared per-syllable CSV,
preserves native labels and lexical missing tokens, maps values through the
shared source-mapping IR, evaluates the profile's extractor-version scope, and
optionally captures every row of native `config.csv`.

`mupet` plans by default and writes nothing. It deterministically classifies the
recording, extractor/version, output profile, run, artifacts, run-artifact
links, syllable detections, and event measurements as `create`, `reuse`, or
`conflict`. `Apply=true` commits a conflict-free plan in one transaction. A
plan that still has conflicts is returned for inspection rather than applied.

Settings provenance is required to apply. MUPET's segmentation and filtering
behaviour is settings-dependent and MUPET itself reprocesses a recording when its
configuration changes, so a run without exact settings evidence is not
reproducible. `Apply=true` without settings raises
`vawlume:ingest:MupetSettingsRequired`. Unlike DeepSqueak, MUPET has no
`not_recoverable` settings status: its output profile deliberately omits the
`required_status` block that gives DeepSqueak that escape.

## File mechanics and text assumptions

The adapter restates no field semantics and hard-codes no file mechanics. The
artifact key, file format, header row, and delimiter all come from the profile's
declared artifact block; the shipped MUPET profile declares `"header_row": 1`
and `"delimiter": ","`. A file whose extension does not match the declared
format, a file with no bytes, and a file that yields fewer than two columns under
the declared delimiter are all refused at the adapter layer, before any database
access.

Text encoding is the one file-mechanic the profile does **not** declare. The
adapter sets no `Encoding`, so MATLAB's own detection applies — UTF-8 for every
file exercised so far. A MUPET export written in some other encoding has not been
tested, and reading one is outside the demonstrated contract until a real
workspace shows it is needed.

Native headers survive verbatim (`VariableNamingRule="preserve"`), and there is
no rename table anywhere in the importer: the profile alone maps a native header
to a canonical concept. Columns whose mapping declares a `missing_value_policy`
are read as strings with MATLAB's missing-token conversion disabled, which is
what keeps `NA` a token rather than a `NaN`.

## Recording reference

MUPET consumes the graph created by project intake. Exactly one of these forms
is required:

```matlab
recordingRef = struct(recording_id=42);
recordingRef = struct( ...
    project_key="project-a", ...
    source_relative_path="audio/day1/REC_A.wav");
```

CSV basenames and native workspace paths never create or infer recordings.

## Run specification

Required fields are `run_key` and `extractor_version`. The shipped profile
accepts exact MUPET `2.1` and `2.1.*` versions and rejects missing or
incompatible version evidence at the database-planning boundary.

Optional descriptive run fields are `run_label`, `notes`, `started_at_utc`,
`completed_at_utc`, and `status`. Supported settings evidence is exactly one of:

```matlab
runSpec.settings = struct(config_path=".../config.csv", relative_path="...");
runSpec.settings = struct(json_path=".../settings.json");
```

`profile_path` is accepted as an alias for `json_path`. Missing settings remain
visible as `not_supplied`; planning is allowed, but the plan is not ready for
event apply. Incomplete native `config.csv` is rejected because substituting
defaults would create false provenance.

An optional processed native artifact may be declared as:

```matlab
runSpec.native_artifact = struct(artifact_path=".../REC_A.mat", ...
    relative_path="...");
```

The `.mat` file is only assigned portable identity and hashed. It is not parsed.
`runSpec.model` and `runSpec.classification` are rejected rather than ignored;
they are not part of this MUPET extraction contract.

## Artifact and run identity

Artifacts use project-scoped portable path identity plus checksum evidence.
The planner emits these exact roles:

| Role | Artifact type | Native |
|---|---|---:|
| `event_measurement_export` | `extractor_event_export` | no |
| `extractor_settings` (native `config.csv` mode) | `extractor_settings` | no |
| `native_processed_recording` | `native_processed_recording` | yes |

Run reuse requires the same recording, exact extractor version, exact output
mapping profile version, and the same presence, portable identity, type, and
checksum for every identity-bearing artifact role. Changed CSV or settings, or
adding, removing, or replacing the optional native artifact under the same
`run_key`, is a conflict. A different `run_key` may legitimately reuse the same
unchanged project-scoped artifact rows.

Native `config.csv` remains the source artifact. Its faithful 11-key structured
capture and structured checksum are stored in planned artifact metadata. The
current schema has no clean edge expressing derivation from that source artifact
to a synthesized `config_profile_versions` row, so the planner does not invent
one. A caller-supplied VAWLUME settings JSON is likewise a portable,
checksum-bearing project-scoped `extractor_settings` config profile. Run reuse
compares its exact profile version and checksum through
`settings_profile_version_id`.

## Native workspace and dataset provenance

Optional `runSpec.dataset` fields (`workspace_name`, `dataset_name`, and
`native_dataset_path`) are preserved as extractor provenance in artifact
metadata. They never create `study`, `group`, `session`, `subject`, or other
experimental hierarchy rows. No extractor-native objects are created either: the
per-syllable CSV declares no emitted container hierarchy.

## Syllable identity

A detection's native event id is the exported `Syllable number`, scoped by the
schema's `UNIQUE(extraction_run_id, recording_id, source_artifact_id,
native_event_id)`. That is an ordinal, not a durable cross-artifact identifier:

- the same syllable numbers may legally repeat across two MUPET runs;
- the same numbers may legally coincide with DeepSqueak call ids;
- duplicate or absent numbers inside one export are refused before any write;
- CSV row order is provenance, recorded in `detections.notes` and in each
  measurement's `source_locator`, and never event identity.

No cross-revision MUPET event key exists. A refined or reprocessed export must
not be assumed to preserve identity merely because its ordinals repeat; that is
matching and lineage work, not import.

## Event geometry, duration, and interval

Detection boundaries come from the profile-declared geometry equivalence classes
and are recorded with `timing_basis = profile_selected_event_geometry`. Each
measurement's derivation stage is answerable through its registered
`extractor_features` row, where MUPET's boundaries are `segmentation`.

The exported `syllable duration (msec)` is the **pre-noise-reduction
onset/offset** duration, not the post-noise-reduction duration MUPET filters on
and does not export. It is stored with its native millisecond value, its
canonical second value, the `ms_to_s` transform, and
`operational_variant = pre_noise_reduction`. Neither the duration nor the
boundaries is ever recomputed from the other.

Because those are different quantities, the profile's `duration_consistency`
check is expected to report on correct MUPET data. It is declared at warning
severity, so the import proceeds and both source values are stored as exported.
The MUPET profile names its tolerance source as export-rounding-aware profile or
project configuration but declares no numeric value, so the shared validator
applies a representation-noise fallback rather than an invented empirical
threshold. A profile that declares a numeric `tolerance` on a check is honoured.

`inter-syllable interval (sec)` is imported as extractor-native
sequence-derived evidence with `derivation_stage = native_sequence_derived`. The
terminal syllable has no following syllable, so its exported `NA` sentinel is
stored as `native_value_type = 'missing'` with `native_raw_token = 'NA'` and no
typed value. It never becomes zero, and no VAWLUME-derived interval is computed
or substituted during import.

## Deliberate absences

The per-syllable CSV exports no row-level review state, no class label, and no
detector score. Therefore a MUPET import creates:

- zero `curation_events` rows;
- zero `classification_runs`, `classification_classes`, and
  `classification_assignments` rows;
- detections whose `detection_score` is NULL.

Surviving MUPET's programmatic duration, energy, and amplitude filtering is not a
reviewed state and no reviewer is invented. Those filter thresholds are recorded
once as run-level settings provenance instead of restated per syllable.

This absence is produced by the profile rather than by a MUPET-specific branch:
the shared router populates review, label, and score fields only when a profile
declares those roles, and the MUPET profile declares only `identifier`. The
returned manifest states the two zeros positively, in `result.curation`,
`result.classification`, and the `curation_rows_expected` /
`classification_rows_expected` counts. If a future MUPET profile revision does
declare a curation or label role, the importer refuses with
`vawlume:ingest:MupetUnsupportedEventEvidence` rather than silently discarding
that evidence.

## Transaction and reuse

One private apply owner opens one transaction covering the settings profile, the
exact extractor version, every artifact, the extraction run, its recording input,
its artifact role links, the syllable detections, and their measurements. A
failure at any point rolls the whole graph back, restores connection state, and
rethrows, so the invariant holds:

```text
an extraction run exists  <=>  its intended syllables were imported
```

A compatible rerun reuses every scientific row and writes nothing; it is reported
as committed because no per-attempt audit row exists. Reuse requires full
evidence comparison, not mere row existence: a stored measurement that is
missing, duplicated, or differs in value, raw token, unit, transform, operational
variant, canonical feature, source artifact, or source locator is an explicit
conflict. Nothing is repaired or updated in place.

## Shared extractor core

Both importers resolve, plan, and write through extractor-neutral private
helpers. The event layer is `extractorFeatureDictionary`,
`extractorRouteEventValues`, `extractorValidateEvents`,
`extractorClassifyDetections`, and `extractorApplyEvents`; the provenance layer
is `extractorApplyProvenance` on top of the Pass 3 resolvers. `mupetApplyPlan`
issues no insert of its own at all — every row it writes goes through that
shared core — while `deepsqueakApplyPlan` adds only its own curation and
classification writes. See `05_deepsqueak_import.md` for those layers.

## Co-residence with DeepSqueak

Both extractors can import the same recording as separate runs, each keeping its
own extractor version, output mapping profile, settings, artifacts, detections,
and measurements. Native event ids are scoped by extraction run, so DeepSqueak
call 1 and MUPET syllable 1 coexist on one recording without collision, and two
MUPET runs may repeat the same syllable ordinals.

Six broad concepts are queryable for both extractors by canonical name:
`call_start_time`, `call_end_time`, `call_duration`, `frequency_min`,
`frequency_max`, and `frequency_bandwidth`. Canonical units agree even though
native units do not, and every row still names its extractor, native field,
native unit, and transform.

**Central frequency is the deliberate exception, and matters for any later
matching work.** DeepSqueak's `Principle Frequency (kHz)` is registered under
the canonical name `contour_median_frequency`, not the generic
`frequency_center` that MUPET's `mean frequency (kHz)` uses, because a contour
median and a filterbank mean are not the same statistic. Joining the two
extractors on `canonical_name` therefore finds nothing for that concept. The
bridge is `extractor_features.equivalence_class`, which both carry as
`vocalization_frequency_center`, plus the seeded `feature_relationships` row
between them. The profile's `broader_canonical_concept` declaration is preserved
as registered feature provenance in `extractor_features.notes`, not as a
joinable column.

The general rule that follows: **join on `equivalence_class` for cross-extractor
comparison, and on `canonical_name` only when both extractors genuinely share
one canonical feature.** No `transform_equivalent` relationship exists between
any DeepSqueak and MUPET feature, and the power/energy/amplitude relationships
remain `related` with `consilience_eligible = 0`.

Capability differences remain visible rather than smoothed over: DeepSqueak
detections carry curation rows, class assignments, and detector scores; MUPET
detections carry none of the three. No matching, consensus, or consilience rows
are created by either importer.

## Demonstration

`examples/mupet_import_demo.m` runs the whole path on generated inputs and
returns every read-back as a struct:

```matlab
addpath("examples")
demonstration = mupet_import_demo;
```

It establishes one project recording through the real intake path, generates a
four-syllable CSV and a complete native `config.csv`, previews the mapped IR
before any write, plans, applies, and then reads back run/artifact/settings
provenance, the syllables with their exported duration beside the boundary span,
representative measurements, the terminal `NA`, the two zero capability counts,
an unchanged rerun, a relocation of all three artifacts, and a short DeepSqueak
co-residence appendix. Every input is created under the system temporary
directory and removed before the function returns.

Two of its outputs are worth reading closely because they are contract rather
than noise. The demonstration reports one `duration_consistency` warning, for
the one syllable whose exported pre-noise-reduction duration differs from its
boundary span; both values are stored exactly as exported. And the extraction-run
read-back reports MUPET's settings as `<native settings artifact>` rather than
as a profile key or as `<not recoverable>`, which distinguishes "captured and
hashed as its native artifact" from "genuinely lost".

`tests/integration/test_mupet_import_demonstration.m` asserts against the
demonstration itself rather than restating its orchestration.

## Limitations

Bounded deliberately, and none of these is scheduled work hidden behind an
omission:

- only the per-syllable CSV is imported; dataset summary, repertoire, and
  refinement exports are not;
- the native processed `.mat` is assigned portable identity and hashed but never
  parsed, and never accepted as settings evidence;
- settings capture covers the demonstrated native `config.csv` key set and a
  caller-supplied VAWLUME settings JSON, and nothing else;
- built-in support is scoped to the tracked MUPET v2.1 output mapping profile;
- the native syllable ordinal is run-scoped identity and is never treated as a
  cross-revision or cross-extractor event key;
- no numeric tolerance is declared for `duration_consistency` or
  `bandwidth_consistency`; the shared validator applies a representation-noise
  fallback rather than an invented empirical threshold;
- `final_inter_syllable_interval_missingness`, `source_recording_linkage`, and
  `settings_consistency` are declared by the profile and reported as unevaluated;
- no matching, consensus, or consilience is implemented, and no VAWLUME-derived
  sequence metric is computed during import;
- every MUPET artifact exercised so far is synthetic. No real MUPET workspace has
  been available, so the fixtures demonstrate the contract rather than validate
  it against field output.
