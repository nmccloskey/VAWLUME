# Project Intake

## Purpose and status

Project intake is the transactional boundary between a validated
project-input source-mapping intermediate representation (IR) and VAWLUME's
relational project, entity, recording, profile-linkage, and audit model.

The supported flow is:

```text
project-input JSON profile
        |
        v
vawlume.source_mapping.parse
        |
        +--> vawlume.source_mapping.preview   (read-only)
        |
        v
vawlume.ingest.project                        (plan or apply)
        |
        v
SQLite project/entity/recording graph
```

Intake consumes the IR as its source of interpreted semantics. It does not
rediscover files, reopen the project-input profile, rerun regular expressions,
or contain extractor-specific artifact readers.

## Public API

The Phase 3 public entry point is:

```matlab
result = vawlume.ingest.project(conn, ir, projectSpec)
result = vawlume.ingest.project(conn, ir, projectSpec, Apply=true)
result = vawlume.ingest.project( ...
    conn, ir, projectSpec, ...
    ProfileLinkagePath=linkagePath, RepoRoot=repoRoot)
```

Planning is the default. `Apply=true` requests one atomic database mutation,
but a conflict-bearing plan is returned without writes.

`projectSpec` declares an explicit project identity:

```matlab
projectSpec = struct( ...
    project_key="stable-project-key", ...
    name="Display name", ...
    description="Optional description");
```

The project is not inferred from a study-like entity in the IR. Project
identity and experimental hierarchy are separate concepts.

When project-input profiles are parsed from a tracked repository, callers
should pass `RepoRoot` to `vawlume.source_mapping.parse` so the IR carries a
portable profile path. `RepoRoot` on intake is used to resolve optional
profile-linkage documents and their referenced profile files.

All supporting intake functions are package-private under
`src/+vawlume/+ingest/private/`. They are implementation details, not an
additional public API.

## Preflight boundary

Before constructing an apply plan, intake verifies that:

- the IR reports `valid_for_ingest=true`;
- the profile kind is `project_input`;
- profile identity, authored version, schema version, path, format, and
  checksum provenance are present;
- project and source logical keys and portable relative paths are unique;
- runtime source paths resolve to files for this execution;
- records reference known sources and relationships reference known records;
- supported project record scopes and relationship semantics are used;
- each source has exactly one `source_recording` record;
- required logical identifiers are neither missing nor ambiguous;
- optional profile-linkage declarations reference supported tracked profile
  kinds, roles, and known recordings.

These checks prevent partial writes and keep source interpretation in the
source-mapping namespace.

## IR-to-relational mapping

| IR/input component | Relational result |
| --- | --- |
| `projectSpec` | `projects` |
| `ir.profile` | `config_profiles`, `config_profile_versions`, and the mapping-profile assignment on the ingestion run |
| `ir.sources` | project-scoped `source_files` and per-attempt `ingestion_files` |
| entity-scoped `ir.records` | `entity_types` and `experimental_entities` |
| `ir.relationships` | `entity_relationships` or role-bearing participant evidence |
| `source_recording` records | one `recordings` row anchored to each source file |
| source/relationship participant evidence | `recording_entity_links` |
| optional linkage configuration | tracked device/setup profiles and `profile_assignments` |
| every successful apply attempt | one `ingestion_runs` row and one `ingestion_files` row per source |

`ir.values` remain source-mapping evidence. Phase 3 does not generically turn
them into entity attributes because that would invent a storage meaning not
declared by the project-input contract. Identity-bearing values have already
been projected into IR records by source mapping.

## Durable identity and idempotency

| Object | Durable identity |
| --- | --- |
| project | explicit `project_key` |
| mapping/device/setup profile | profile kind plus stable profile key |
| profile version | profile plus authored version/checksum provenance |
| source file | project plus normalized portable relative path |
| entity type | project plus native level name |
| entity | entity type plus native identifier |
| entity relationship | resolved endpoint pair, with semantics checked for compatibility |
| recording | unique source-file anchor |
| recording participant | recording plus entity plus role |
| profile assignment | declared scope, role, profile version, and target |

Absolute runtime paths are used to prove that sources exist and are returned
in the plan for diagnostics. They are not persisted as durable identity.
Relocating the same project root therefore reuses the same relational graph.
Files with the same basename in different relative folders remain distinct.

Reapplying compatible input reuses semantic rows. A changed meaning for an
existing durable identity is reported as a conflict rather than silently
updated or ignored. Successful reruns intentionally create new ingestion-run
and ingestion-file audit rows, so graph idempotency does not erase attempt
history.

## Transaction and audit semantics

Apply requires a connection that enters with autocommit enabled. Intake then
uses one transaction in dependency order:

1. mapping profile/version and optional linked profile versions;
2. project and project-level profile assignments;
3. ingestion run;
4. source files and ingestion files;
5. entity types, entities, and entity relationships;
6. recordings and recording-entity links;
7. recording-level profile assignments.

Any failure rolls the transaction back, restores the connection's autocommit
state, and rethrows the error. Planning conflicts and failed preflight create
no audit rows because no apply attempt begins. A successful no-op graph rerun
still records a completed ingestion attempt.

Semantic rows retain the `ingestion_run_id` of the attempt that first created
them. Later compatible attempts are represented by their own immutable audit
rows rather than rewriting original provenance.

## Device and setup profile linkage

Phase 3 supports the tracked JSON linkage example used by the three shipped
project-input patterns. It can:

- register recording-device and experimental-setup profile versions;
- assign project-default device/setup profiles;
- inherit those defaults onto recordings when declared;
- create explicit recording-level assignments;
- preserve assignment source and role.

The current validators intentionally cover only the demonstrated linkage
language. Generalized profile composition, arbitrary inheritance, and full
device/setup domain validation remain future work.

## Result manifest

The returned result exposes:

- planning or committed status and a `committed` flag;
- resolved project, mapping-profile, source, entity, relationship, recording,
  and assignment IDs/maps;
- created, reused, conflicting, and applied counts;
- ingestion-run and ingestion-file planning details;
- warnings and structured issues;
- the complete plan, including runtime source locations used for this attempt.

This makes the plan inspectable before apply and supports deterministic
relational read-back after commit.

## Relational read-back

The current schema answers the Phase 3 review questions without another view:

- recording to source and participant roles: `v_recording_entity_context`;
- entity hierarchy and native identifiers: joins through
  `entity_relationships`, `experimental_entities`, and `entity_types`;
- intake attempt to mapping profile: `ingestion_runs` through
  `config_profile_versions` and `config_profiles`;
- recording to device/setup provenance: `profile_assignments` through profile
  version/profile joins;
- ingestion run to source files and statuses: `ingestion_files` joined to
  `source_files`.

The recording's unique `source_file_id` is the extractor-import anchor. The
DeepSqueak importer now resolves that established portable source/recording
identity before attaching its extraction run and artifacts; MUPET is the next
consumer of the same boundary.

## Current limitations

- Intake does not read audio metadata or extractor artifacts.
- Audio duration, sample rate, channels, and checksums are not enriched unless
  a future adapter supplies that evidence.
- Multi-source recording evidence remains a plan-level concept; the current
  relational contract creates one recording per source file.
- Profile-linkage validation is limited to the shipped demonstrated language.
- Only declared project-default inheritance and explicit recording assignments
  are supported.
- Conflicting existing semantic rows are not updated in place; an explicit
  migration/update workflow is future work.
- DeepSqueak and MUPET importers are outside Phase 3.

These are bounded Phase 3 limitations, not hidden fallbacks. DeepSqueak import
now consumes the established source-file/recording and profile-provenance
anchors without changing the project-intake boundary; MUPET import is next.
