# Source-Mapping Intermediate Representation

## Purpose

The source-mapping intermediate representation (IR) is the single
database-free result contract between source interpretation and project intake
or extractor ingest.
It preserves the evidence needed to create relational rows without asking an
ingester to re-read JSON, rerun regular expressions, or infer precedence from
iteration order.

The prototype IR contract version is:

```text
0.2-draft
```

Existing project/extractor profiles use profile language version `0.2-draft`.
External-stream and alignment-anchor profiles use the additive version:

```text
0.3-draft
```

## Public entry points

Project/path-oriented profiles use:

```matlab
result = vawlume.source_mapping.parse( ...
    profilePath, sourceRoot, ProfileId=profileId, RepoRoot=repoRoot);
```

A multi-profile JSON document requires `ProfileId`. The top-level operation
loads and validates the profile, discovers sources, parses path and filename
semantics, assembles records and relationships, consolidates conflicts, and
derives validity.

Profile regex declarations are MATLAB `regexp` patterns. Named captures use
MATLAB syntax, `(?<name>...)`; Python-style `(?P<name>...)` captures are
rejected during profile validation.

Profile value normalization uses list-shaped `value_map` records with
`native_value` and `canonical_value` fields. Lexical missing-token behavior is
declared per mapping through `missing_value_policy`, including
`missing_tokens`, `case_sensitive`, `blank_is_missing`, and
`preserve_raw_token`.

Already-loaded extractor, external-event, and alignment-anchor tables use:

```matlab
result = vawlume.source_mapping.mapTableToIR( ...
    tbl, loadedProfile, SourceKey=sourceKey, ...
    RelativePath=relativeArtifactPath);
```

`mapTableToIR` accepts a loaded profile bundle, one decoded profile document,
or a profile JSON path. It dispatches by the validated profile kind while keeping
one entry point and one IR. It does not read extractor or external artifacts; the
caller supplies a MATLAB `table`. Anchor profiles may additionally receive a
previously mapped external-event IR as `EventContext` to resolve optional logical
event references. The lower-level `discoverSources`,
`parsePath`, and `mapTableFields` functions remain available for focused
inspection, but downstream ingest should consume the unified IR.

Any unified IR result can be rendered as an inspectable dry-run report:

```matlab
preview = vawlume.source_mapping.preview(result);
disp(preview.text)
```

Set `Print=true` to also print the text while retaining the structured return
value. The report exposes header/profile provenance, discovery counts,
role-aware project hierarchy columns, extractor table-mapping summaries,
external stream/event/coverage summaries, anchor observations by timebase and
fit-pair eligibility, issues grouped by severity and code, bounded issue details, and a final
`READY FOR INGEST` or `NOT READY FOR INGEST` verdict. The verdict is solely a
readable view of `result.valid_for_ingest`.

`preview` consumes the IR only. It does not rediscover files, rerun mappings,
read extractor artifacts, accept a database connection, execute SQL, or imply
that ingestion occurred. The current IR retains selected sources but not the
full set of ignored discovery candidates, so the preview labels the ignored
count unavailable instead of fabricating it.

Profile-load and source-root failures that prevent any usable result retain the
existing exception contract. Mapping and validation problems discovered after
loading are returned as structured IR issues.

## Top-level contract

```matlab
result = struct( ...
    ir_schema_version=..., ...
    profile=..., ...
    sources=..., ...
    records=..., ...
    values=..., ...
    relationships=..., ...
    streams=..., ...
    events=..., ...
    event_attributes=..., ...
    coverage=..., ...
    anchors=..., ...
    anchor_observations=..., ...
    anchor_fit_pairs=..., ...
    issues=..., ...
    summary=..., ...
    valid_for_ingest=...);
```

The repeated components are MATLAB tables. No component contains a generated
SQLite surrogate ID.

### `result.profile`

| Field | Meaning |
| --- | --- |
| `profile_key` | Stable `profile.id` from JSON. |
| `profile_name` | Authored display name from `profile.name`; retained so intake does not reopen the profile document. |
| `profile_kind` | `project_input`, `extractor_output`, `external_stream_mapping`, or `alignment_anchor_mapping`. |
| `profile_version` | Explicit authored `profile.profile_version`. |
| `profile_version_source` | `profile.profile_version` for validated executable profiles; `not_declared` only for unvalidated in-memory documents. |
| `profile_schema_version` | Version of the profile language. |
| `profile_content_format` | Loaded artifact format (`json` for the current executable profiles). |
| `profile_path` | Portable/repository-relative path when `RepoRoot` was supplied. |
| `profile_runtime_path` | Runtime location used to load the profile. |
| `profile_checksum` | SHA-256 of a loaded JSON file. Blank for an in-memory profile document. |
| `extractor_name` | Extractor name for extractor-output profiles, otherwise blank. |
| `extractor_version_scope_preferred` | Preferred supported extractor version/range for extractor-output profiles. |
| `extractor_version_scope_compatible_family` | Broader compatible extractor family when declared. |

The current executable JSON profiles declare `profile.profile_version =
0.1.0`. Project/extractor profiles declare language version `0.2-draft`; the
new external-stream and anchor shapes declare `0.3-draft`. Extractor
compatibility remains separate under `extractor.version_scope`.

### `result.sources`

One row represents one discovered project file or supplied extractor table.

| Column | Meaning |
| --- | --- |
| `source_key` | Deterministic logical source identity. |
| `runtime_path` | Machine-local runtime path, if one exists. |
| `relative_path` | Slash-normalized portable location. |
| `filename` | Source filename. |
| `source_type` | `project_file`, `extractor_table`, `external_event_table`, or `alignment_anchor_table`. |
| `discovery_rule` | Profile discovery rule or `supplied_table`. |
| `artifact_type` | Stable source/artifact category from the mapping contract. |
| `status` | `mapped`, warning-bearing, or invalid status. |
| `source_row_count` | Supplied table height where applicable. |
| `checksum_sha256` | Optional source checksum; blank unless explicitly supplied/computed. |

Large user files are not hashed merely to produce a preview.

### `result.records`

A record is a logical source-scoped object, not a database entity.

| Column | Meaning |
| --- | --- |
| `record_key` | Deterministic source/rule-scoped logical key. |
| `source_key` | Owning source. |
| `native_level` | Project-native level or extractor-native row level. |
| `canonical_level` | Canonical role/level. |
| `native_identifier` | Preserved logical identifier when unambiguous. |
| `record_scope` | Entity, membership, source recording, or source table row. |
| `source_row` | Extractor table row, otherwise `NaN`. |
| `role_label` | Membership/participant role when declared. |
| `mapping_rule` | Rule provenance. |
| `status` | Mapped, missing-bearing, unresolved, conflict, or invalid state. |

Project records remain source-scoped. `vawlume.ingest.project` resolves
repeated logical entities through their declared level and native identifier;
it does not reconstruct those identifiers from filenames.

### `result.values`

Each row is one evidence contributor. Repeated/corroborating evidence is
preserved rather than discarded.

The table carries:

- `value_key`, `evidence_group_key`, `record_key`, and `source_key`;
- native and actual source field names;
- lexical `raw_value`;
- typed native columns and `native_value_type`;
- native unit;
- canonical field;
- typed normalized columns and `normalized_value_type`;
- canonical unit and transform key;
- mapping rule, profile location, and source row;
- derivation stage, operational variant/definition, equivalence class,
  cross-extractor relationship, consilience role, and semantic role;
- `consolidation_status`, `evidence_count`, and mapping `status`.

Heterogeneous values are not coerced into one lossy text column. Exactly one
typed value column is meaningful for a non-missing value. The lexical
`raw_value` remains available independently, including strings such as
`NA`. Explicit missingness uses type/status metadata and leaves typed payload
columns empty.

`raw_value` reports only tokens the source actually contained. A profile-declared
textual sentinel such as `NA` is preserved verbatim, but an absent numeric cell
has no lexical content and yields an empty `raw_value` rather than MATLAB's
`NaN` rendering.

### `result.relationships`

Relationships are separate from records so hierarchy is not forced into a
single-parent tree.

| Column | Meaning |
| --- | --- |
| `relationship_key` | Deterministic relationship identity. |
| `source_key` | Source evidence scope. |
| `from_record_key` | Parent/container/member-owning record. |
| `to_record_key` | Child/member record. |
| `native_relationship` | Profile-native relationship declaration. |
| `canonical_relationship` | Currently `contains` or `has_member`. |
| `role_label` | For example `male_partner` or `female_partner`. |
| `mapping_rule` | Profile declaration that produced the edge. |
| `status` | Mapping state. |

### External-stream tables

`result.streams` distinguishes the logical `stream_key`, its `timebase_key`, and
the supplied `source_key`; modality never substitutes for clock identity.

`result.events` contains one source row per operational event. It preserves the
native event ID/label and native start/end values, adds normalized seconds and an
optional normalized project event key, and records the actual timestamp columns
plus whether they resolved by exact name, declared alias, or deterministic
default. A missing end value means a point event at the start; it does not mean an
unknown start. Event keys are deterministic source/row keys and never SQLite IDs.

`result.event_attributes` is long-form typed evidence. Each row carries the
native and resolved field names, operational attribute name, raw token, one typed
normalized value, native/normalized units, transform key, mapping rule, source
row, locator, and status. Only explicitly declared fields become attributes.

`result.coverage` contains explicit observed segments in both native time and
seconds. The implemented prototype path is `coverage.mode = constant_segments`;
`manifest_later` explicitly defers coverage to Phase 7 intake. Event bounds never
imply continuous observation, so a gap between segments remains unavailable.

### Alignment-anchor tables

`result.anchors` is logical identity and optional type/order metadata. It has no
timestamp. `result.anchor_observations` carries each clock reading with distinct
stream/timebase keys, native and normalized time, role, tri-state inclusion while
resolution is pending, uncertainty, source locator, and optional logical event
reference (`event_source_key` plus native event ID).

Long profiles map an explicit observation-identity column through declared
stream/timebase context. Wide profiles enumerate every clock column in
`layout.stream_columns`; no numeric column is auto-detected. Both paths populate
the same two tables. Redundant observations remain separate. One explicit
primary/included row resolves a duplicate group; unresolved duplicates or more
than one primary produce `ANCHOR_PRIMARY_AMBIGUOUS` and make the IR not ready.

`result.anchor_fit_pairs` is the IR-derived readiness summary for profile-declared
source/reference clock pairs. Its count includes a logical anchor only when the
IR contains exactly one valid included observation on both clocks. Preview reads
this table and does not reimplement eligibility in display code.

### `result.issues`

| Column | Meaning |
| --- | --- |
| `issue_key` | Deterministic key assigned after sorting. |
| `severity` | `info`, `warning`, `error`, or reserved `fatal`. |
| `code` | Stable machine-readable code. |
| `source_key`, `record_key` | Affected logical scope when available. |
| `location` | Profile/runtime location. |
| `field_or_rule` | Field, rule, or evidence group. |
| `message` | Human-readable explanation. |
| `affects_validity` | Derived from central severity policy. |

The IR normalizes component-specific diagnostics into a compact vocabulary,
including `COLUMN_MISSING`, `COLUMN_AMBIGUOUS`, `SOURCE_COLUMN_UNMAPPED`,
`REGEX_NO_MATCH`, `REGEX_MULTIPLE_MATCH`, `REQUIRED_VALUE_MISSING`,
`TYPE_COERCION_FAILED`, `TRANSFORM_FAILED`,
`MISSING_TOKEN_NORMALIZED`, `SOURCE_DUPLICATE_DISCOVERY`,
`VALUE_CORROBORATED`, and `VALUE_CONFLICT`. Profile validation codes remain
visible when they already express a stable profile-level contract.

Phase 7 adds stable table-mapping diagnostics including
`TIMESTAMP_COLUMN_MISSING`, `TIMESTAMP_INVALID`, `EVENT_INTERVAL_INVALID`,
`TIME_UNIT_UNSUPPORTED`, `NATIVE_EVENT_ID_DUPLICATE`,
`NORMALIZED_EVENT_TARGET_UNKNOWN`, `COVERAGE_INTERVAL_INVALID`,
`ANCHOR_KEY_MISSING`, `ANCHOR_OBSERVATION_IDENTITY_MISSING`,
`ANCHOR_IDENTITY_UNDECLARED`, `ANCHOR_PRIMARY_AMBIGUOUS`,
`WIDE_STREAM_COLUMN_MISSING`, `EVENT_REFERENCE_UNRESOLVED`,
`ANCHOR_ROLE_INVALID`, and `ANCHOR_INCLUDED_INVALID`. Normal malformed user data
therefore becomes structured evidence rather than a raw indexing error.

### Undeclared source columns

A supplied table column that no field mapping declares as a source field or
alias produces one `SOURCE_COLUMN_UNMAPPED` issue. A column claimed by a
mapping that failed for another reason is not reported again here, so one fault
yields one diagnostic.

This is the only IR code whose severity is chosen by the profile rather than by
the central severity policy, because the mapping contract is what defines which
fields are known. The profile's `mapping_policy.unknown_fields` decides:

| `unknown_fields` | Severity | Effect on `valid_for_ingest` |
| --- | --- | --- |
| `preserve_and_warn`, `warn` | `warning` | none |
| `error`, `fail`, `reject` | `error` | invalidates |
| absent or anything else | `info` | none |

`mapTableFields` also returns `unmapped_source_fields` for inspection. The
current IR reports these columns but does not yet carry their per-row values, so
populating the schema's `unmapped_source_values` table remains future work.

## Conflict and validity semantics

Values sharing an `evidence_group_key` are consolidated centrally:

- one contributor is `unique`;
- multiple equal normalized contributors are `corroborated`;
- different normalized contributors are all marked `conflict`, preserved,
  and accompanied by one `VALUE_CONFLICT` error.

No value wins because it happened to be processed first. Profile-declared
precedence can be added later, but the shipped profiles do not currently
declare one.

`valid_for_ingest` is derived and cannot be supplied by a caller:

```text
true  = no error or fatal issue
false = one or more error/fatal issues
```

Warnings and informational diagnostics remain visible without automatically
blocking ingest.

## Determinism

- Discovery is ordered by normalized relative path.
- Record, value, relationship, and issue tables are sorted by their stable
  logical keys.
- Issue keys are assigned only after deterministic sorting.
- Project keys depend on source-relative identity, never temporary/source-root
  absolute paths.
- No random UUID or database ID is allocated.

## Relational compatibility

The IR carries enough source/profile/rule identity for project intake to create
`source_files`, `config_profile_versions`, and ingestion provenance. Project
records and relationships can populate `experimental_entities`,
`entity_relationships`, recordings, and role-bearing
`recording_entity_links`. Extractor table records/values retain row-scoped
event identity, native/canonical measurements, transforms, operational
variants, and raw sentinels needed for detections and
`event_measurements.native_raw_token`.

`vawlume.ingest.project` resolves project logical keys to database IDs. The
source-mapping layer still does not open SQLite, execute SQL, or mutate a
database. See [`04_project_intake.md`](04_project_intake.md) for the stable
Phase 3 identity, transaction, linkage, and read-back contract.

The Phase 7 tables deliberately stop at logical identity. They carry the stream,
timebase, source, event, anchor, observation, mapping rule, and source locator
needed by the later registration boundary, but no `timebase_id`,
`external_stream_id`, `external_event_id`, or alignment surrogate. The external
event/attribute/coverage and anchor/observation shapes mirror the normalized
targets documented in
[`11_temporal_alignment_schema.md`](11_temporal_alignment_schema.md) without
performing those writes.

The dry-run test suite enforces this boundary against a disposable Phase 1
fixture database by comparing every user-table row count and foreign-key check
before and after parse plus preview.

## JSON runtime dependency

The central loader reads tracked JSON profile bytes with `fileread`, checks
for duplicate JSON object members, decodes with MATLAB `jsondecode`, and
preserves SHA-256 checksums of the exact loaded file bytes.

Malformed JSON, duplicate object members, missing profile files, and file-read
failures are reported as `vawlume:source_mapping:ProfileLoadFailed`.
Profile-validation failures after successful decoding continue to use the
structured source-mapping validation identifiers and IR issue machinery.
