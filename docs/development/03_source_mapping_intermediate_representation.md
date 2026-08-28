# Source-Mapping Intermediate Representation

## Purpose

The source-mapping intermediate representation (IR) is the single
database-free result contract between source interpretation and later ingest.
It preserves the evidence needed to create relational rows without asking an
ingester to re-read JSON, rerun regular expressions, or infer precedence from
iteration order.

The prototype IR contract version is:

```text
0.1-draft
```

Executable source-mapping profiles use profile language version:

```text
0.2-draft
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

Already-loaded extractor tables use:

```matlab
result = vawlume.source_mapping.mapTableToIR( ...
    tbl, loadedProfile, SourceKey=sourceKey, ...
    RelativePath=relativeArtifactPath);
```

`mapTableToIR` accepts a loaded profile bundle, one decoded profile document,
or a profile JSON path. It does not read DeepSqueak or MUPET artifacts; the
caller supplies a MATLAB `table`. The lower-level `discoverSources`,
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
issues grouped by severity and code, bounded issue details, and a final
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
| `profile_kind` | `project_input` or `extractor_output`. |
| `profile_version` | Explicit authored `profile.profile_version`. |
| `profile_version_source` | `profile.profile_version` for validated executable profiles; `not_declared` only for unvalidated in-memory documents. |
| `profile_schema_version` | Version of the profile language. |
| `profile_path` | Portable/repository-relative path when `RepoRoot` was supplied. |
| `profile_runtime_path` | Runtime location used to load the profile. |
| `profile_checksum` | SHA-256 of a loaded JSON file. Blank for an in-memory profile document. |
| `extractor_name` | Extractor name for extractor-output profiles, otherwise blank. |
| `extractor_version_scope_preferred` | Preferred supported extractor version/range for extractor-output profiles. |
| `extractor_version_scope_compatible_family` | Broader compatible extractor family when declared. |

The current executable JSON profiles declare `profile.profile_version =
0.1.0` and `profile.profile_schema_version = 0.2-draft`. Extractor
compatibility remains separate under `extractor.version_scope`.

### `result.sources`

One row represents one discovered project file or supplied extractor table.

| Column | Meaning |
| --- | --- |
| `source_key` | Deterministic logical source identity. |
| `runtime_path` | Machine-local runtime path, if one exists. |
| `relative_path` | Slash-normalized portable location. |
| `filename` | Source filename. |
| `source_type` | `project_file` or `extractor_table`. |
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

Project records remain source-scoped. A later ingester may resolve repeated
logical entities through their declared level and native identifier; it need
not reconstruct those identifiers from filenames.

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
including `COLUMN_MISSING`, `COLUMN_AMBIGUOUS`, `REGEX_NO_MATCH`,
`REGEX_MULTIPLE_MATCH`, `REQUIRED_VALUE_MISSING`,
`TYPE_COERCION_FAILED`, `TRANSFORM_FAILED`,
`MISSING_TOKEN_NORMALIZED`, `SOURCE_DUPLICATE_DISCOVERY`,
`VALUE_CORROBORATED`, and `VALUE_CONFLICT`. Profile validation codes remain
visible when they already express a stable profile-level contract.

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

## Phase 1 relational compatibility

The IR carries enough source/profile/rule identity for later ingest to create
`source_files`, `config_profile_versions`, and ingestion provenance. Project
records and relationships can populate `experimental_entities`,
`entity_relationships`, recordings, and role-bearing
`recording_entity_links`. Extractor table records/values retain row-scoped
event identity, native/canonical measurements, transforms, operational
variants, and raw sentinels needed for detections and
`event_measurements.native_raw_token`.

Later ingest must resolve logical keys to database IDs. The source-mapping
layer does not open SQLite, execute SQL, or mutate a database.

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
