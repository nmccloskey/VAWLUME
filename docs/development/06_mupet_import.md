# MUPET import

## Current boundary

Phase 5 Pass 3 implements two public entry points:

```matlab
export = vawlume.ingest.mupetExport(csvPath, ...)
plan = vawlume.ingest.mupet(conn, csvPath, recordingRef, runSpec, ...)
```

`mupetExport` is database-free. It reads the profile-declared per-syllable CSV,
preserves native labels and lexical missing tokens, maps values through the
shared source-mapping IR, evaluates the profile's extractor-version scope, and
optionally captures every row of native `config.csv`.

`mupet` is read-only in Pass 3. It deterministically classifies the recording,
extractor/version, output profile, run, artifacts, and run-artifact links as
`create`, `reuse`, or `conflict`. `Apply=true` is deliberately refused until
Pass 4 can commit the run and its complete syllable population atomically. This
prevents a permanent extraction run with no events.

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
experimental hierarchy rows. Pass 3 also creates no extractor-native objects.

## Deferred event population

The returned manifest reports the CSV source-row count and an explicit
`deferred_to_phase_5_pass_4` event-population status. It plans zero detections.
Pass 4 owns syllable identity, measurements, validation, and the final atomic
apply transaction.
