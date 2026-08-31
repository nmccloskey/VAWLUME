# VAWLUME Prototype Usage Guide

> **Scope.** This is a practical guide to the VAWLUME prototype **as currently
> implemented**. It is not the eventual VAWLUME manual, and it does not describe
> planned functionality. Where this guide and an older design document disagree,
> the repository is the authority.
>
> **Status.** Early prototype. The schema (`0.5-draft`, `PRAGMA user_version = 5`),
> the configuration contracts, and the `vawlume.*` package API are working design
> hypotheses and may change before any public release. Every numeric threshold
> shipped with the prototype is an illustrative demonstration value, not a
> calibrated setting.

---

## 1. What VAWLUME currently does

VAWLUME is a MATLAB-centered, provenance-aware semantic mapping layer between
heterogeneous external project structures and extractor artifacts on one side,
and a common SQLite relational model on the other.

Concretely, the prototype can today:

- **interpret** a user's project folder/filename structure and an extractor's
  output table through versioned JSON **mapping profiles**, producing a
  validated, database-free **intermediate representation (IR)** plus a dry-run
  preview;
- **ingest** that IR transactionally into a relational project, experimental
  entity, and recording graph with immutable ingestion provenance;
- **import** DeepSqueak Excel call-statistics exports and MUPET per-syllable
  CSVs onto an established recording, creating extraction runs, artifacts,
  detections, and native plus canonical event measurements;
- **match** two explicitly selected extraction runs on one recording by temporal
  overlap, preserving ambiguity as connected-component match groups, and derive
  consensus events only where topology permits;
- **quantify** detection- and feature-level agreement, assign provenance-bearing
  consilience statuses, evaluate against an independent reviewer-authored
  reference set, and compare several matching thresholds side by side;
- **register** timestamped external event streams (behavioural, neural/TTL) and
  logical alignment anchors from one session manifest, **fit** offset or affine
  source-to-reference clock transforms with per-anchor residual evidence, project
  events onto a common clock, and build a coverage-aware regularized timeline.

### Important limitations

- **Extractor coverage is deliberately narrow.** DeepSqueak (Excel
  call-statistics export) and MUPET (per-syllable CSV) are the only implemented
  importers. Native DeepSqueak `.mat` containers, detector networks, and
  classification models are registered and checksummed but never parsed.
- **No GUI, no CLI.** VAWLUME is a set of namespaced MATLAB functions called
  from the MATLAB command window or a script.
- **No continuous-signal ingestion.** Only *timestamped events* enter the
  database. Neural, photometry, and video samples stay external.
- **Alignment anchors are user-supplied**, never discovered from waveforms or
  pixels. A solved fit is recorded as `estimated`, never `validated` — there is
  no calibrated acceptance threshold.
- **Sequence, bout, motif, and hierarchy-aware analyses are not implemented.**
  The `sequences`, `sequence_members`, `bouts`, and `bout_members` tables exist
  in the schema and are used by no code.
- **All validation to date is synthetic.** No real paired extractor session and
  no real manually reviewed reference subset has been available.

### VAWLUME and external extractors

VAWLUME does **not** detect or extract vocalizations. It consumes what an
external extractor already produced. The conceptual machinery — mapping
profiles, the IR, the relational model, matching, consilience, alignment — is
extractor-independent; only the shipped output-mapping profiles and the two thin
artifact adapters are extractor-specific.

Normalization is **additive, never destructive**. Native artifacts, field names,
values, units, hierarchy, labels, missing tokens, and extractor/run provenance
remain queryable even where VAWLUME also exposes a canonical concept. Structural
equivalence — a DeepSqueak *call* and a MUPET *syllable* are both vocalization
events — is never a claim of metric identity.

---

## 2. Requirements

| Requirement | Detail |
|---|---|
| MATLAB | R2026a (the release the current test suite is run against) |
| Toolbox | **Database Toolbox** — supplies the `sqlite` connection object used throughout |
| SQLite | No separate installation. The database is a file created through MATLAB's `sqlite` interface |
| Python / PyYAML | **Not required.** Configuration is canonical JSON read with `fileread` + `jsondecode` |
| Excel reading | MATLAB's built-in `readtable` — needed only for DeepSqueak workbook imports |
| Extractor input | A DeepSqueak Excel call-statistics export, and/or a MUPET per-syllable CSV plus its native `config.csv` |

See [`../development/01_environment.md`](../development/01_environment.md).

Nothing is compiled or installed. Repository setup is: obtain the repository,
put `src/` on the MATLAB path, and create a database file.

---

## 3. Conceptual workflow

```text
user project structure          extractor artifacts          external event tables
(folders, filenames)            (DeepSqueak xlsx,            (behaviour, neural TTL)
                                 MUPET csv)                   + anchor tables
        |                              |                              |
        +---------------- mapping profiles (JSON) --------------------+
                                       |
                      vawlume.source_mapping.parse / mapTableToIR
                                       |
                   validated intermediate representation (IR)
                     + vawlume.source_mapping.preview (dry run)
                                       |
        +-------------------+----------+-----------+-------------------+
        |                   |                      |                   |
 vawlume.ingest.project  vawlume.ingest.       vawlume.ingest.    (session manifest)
                         deepsqueak / mupet    alignment
        |                   |                      |
        +-------------------+----------------------+
                                       |
                          SQLite relational model
                                       |
        +------------------------------+------------------------------+
        |                              |                              |
 vawlume.matching.compare     vawlume.consilience.        vawlume.alignment.fit
 (candidates, groups,         summarize / sensitivity     -> commonTime
  consensus)                  (agreement, consilience,    -> vawlume.sequence.
                               manual QC)                    regularizeTimeline
```

Two boundaries are enforced rather than merely recommended:

1. **`source_mapping` never touches the database.** It interprets sources and
   returns an IR. No SQLite ID appears in it.
2. **Planning is separate from applying.** Every database-facing function plans
   by default and writes nothing; `Apply=true` commits a conflict-free plan in
   one transaction. A conflicting plan is returned, not partially written.

---

## 4. Getting started

### 4.1 Obtain the repository

```bash
git clone <repository-url> VAWLUME
cd VAWLUME
```

### 4.2 Open it in MATLAB

Either open the MATLAB Project, which registers `src/` on the path:

```matlab
openProject("VAWLUME.prj")
```

or, from the repository root, add the one path entry by hand:

```matlab
addpath("src")
```

Only `src/` belongs on the path. The `+vawlume` namespace resolves everything
below it, and adding nested package folders separately weakens that boundary.
Add `examples` as well if you intend to run the shipped demonstrations.

### 4.3 Where your data goes

Your recordings, extractor exports, and event tables stay **outside** the
repository. VAWLUME reads them from paths you supply and records each one as a
checksummed `source_files` or `artifacts` row, so a file may be relocated later
without creating a second scientific population.

`.gitignore` already excludes `*.sqlite`, `/data/`, and `/output/`: generated
databases are disposable outputs, and the tracked schema, seed, and profile
sources are what regenerate them.

### 4.4 How configuration is selected

Configuration is never discovered implicitly. You pass a profile path — and a
`ProfileId` when the document holds several profiles — to the function that
needs it.

Only two things have a default, and both resolve to a *tracked* file beneath
`RepoRoot`: the extractor importers fall back to their shipped output-mapping
profile, and `vawlume.matching.compare` falls back to
`config/05_matching_profiles/prototype_matching_consilience_spec.json` when
`matchSpec.profile_path` is omitted. Project-input profiles, external-stream and
anchor profiles, and alignment manifests must always be named explicitly.

---

## 5. Configuration

All tracked configuration is canonical JSON under `config/`. See
[`../../config/README.md`](../../config/README.md) for the full policy.

| Directory | Kind | Needed for |
|---|---|---|
| `config/01_mapping_profiles/project_inputs/` | `project_input` | project intake |
| `config/01_mapping_profiles/extractors/deepsqueak/`, `.../mupet/` | `extractor_output` | extractor import (shipped; usable as-is) |
| `config/01_mapping_profiles/external_streams/` | `external_stream_mapping` | external event registration |
| `config/01_mapping_profiles/alignment_anchors/` | `alignment_anchor_mapping` | anchor registration |
| `config/02_device_profiles/`, `config/03_setup_profiles/` | device / setup examples | optional acquisition provenance |
| `config/04_examples/profile_linkage_example.json` | linkage | optional device/setup assignment at intake |
| `config/05_matching_profiles/` | `consilience_policy` | matching and consilience |
| `config/06_alignment_manifests/` | session manifest (**not** a profile kind) | alignment intake |

### 5.1 Defaults versus what you must author

**Usable as shipped, no editing needed:**

- both extractor-output mapping profiles;
- the prototype matching/consilience specification
  (`prototype_matching_consilience_spec.json`) — but read §10 about its
  thresholds;
- the external-stream and alignment-anchor mapping profiles, *if* your event
  tables happen to use the same columns.

**You must author or adapt:**

- a **project-input mapping profile** describing your own folder/filename
  structure. The three shipped examples
  (`example.project.mouse_courtship.folder_driven`,
  `example.project.rat_self_admin.filename_driven`,
  `example.project.social_dyad.multi_subject`) are worked examples of the
  language, not a structure you are expected to adopt;
- a **session alignment manifest** per session, if you use alignment.

### 5.2 Profile identity

Every source-mapping profile declares:

```json
"profile": {
  "id": "example.project.mouse_courtship.folder_driven",
  "kind": "project_input",
  "profile_schema_version": "0.2-draft",
  "profile_version": "0.1.0"
}
```

`profile_version` is your mapping contract's version; `profile_schema_version`
is the VAWLUME profile-*language* version. Project-input and extractor-output
profiles currently use `0.2-draft`; external-stream and alignment-anchor
profiles use the additive `0.3-draft`. The loader accepts exactly four
source-mapping kinds: `project_input`, `extractor_output`,
`external_stream_mapping`, and `alignment_anchor_mapping`.

### 5.3 Regular expressions and JSON escaping

Profiles use **MATLAB `regexp` syntax directly**, with named captures written
`(?<name>...)`. Because the profile is JSON, backslashes must be escaped. A
MATLAB pattern

```text
^(?<animal_id>\d{3})$
```

is authored as

```json
"^(?<animal_id>\\d{3})$"
```

and a literal dot as `\\.`.

### 5.4 Value maps and missing tokens

Value normalization uses order-insensitive `value_map` records with explicit
`native_value` and `canonical_value` fields. Lexical missing tokens are declared
in `missing_value_policy` rather than handled in code — the MUPET profile, for
example, declares `NA` as a missing token for the inter-syllable interval while
preserving the raw token, so a terminal `NA` never silently becomes `0`.

### 5.5 Feature semantics

Canonical feature names and native-to-canonical mappings are derived from the
tracked extractor profiles by `vawlume.db.registerBuiltinSemantics`. The tracked
profile is the authoritative source; the seed registers it rather than
maintaining a second copy.

One consequence matters when querying: **cross-extractor feature comparison goes
through `extractor_features.equivalence_class` and `feature_relationships`, not
through a shared canonical name.** DeepSqueak's contour median is registered
under its own canonical name rather than the generic `frequency_center` MUPET
uses, so a canonical-name join finds nothing at all for central frequency.

### 5.6 Authoring rhythm

1. draft or edit the JSON profile;
2. `vawlume.source_mapping.loadProfile(path, ExpectedKind=...)`;
3. run the relevant parse or table-mapping call;
4. inspect `vawlume.source_mapping.preview(ir, Print=true)` **before** any
   ingest.

The dry-run preview is the main safety mechanism. It reports missing columns,
regex misses, ambiguous fields, value conflicts, and an explicit readiness
verdict without touching the database.

---

## 6. A minimal end-to-end example

### 6.1 The shortest path: run a shipped demonstration

Five runnable demonstrations create every input they need under the system
temporary directory and remove it before returning. From the repository root:

```matlab
addpath("src")
addpath("examples")

project_intake_demo        % source mapping -> preview -> intake -> read-back
deepsqueak_import_demo     % + DeepSqueak run, artifacts, detections, measurements
mupet_import_demo          % + MUPET syllables, settings provenance, NA missingness
matching_consensus_demo    % + matching, consensus, agreement, consilience, sensitivity
temporal_alignment_demo    % + manifest registration, transform fitting, common time
```

Each returns a struct and prints a compact report; pass `Print=false` to suppress
the printing. `matching_consensus_demo` is the complete cross-extractor path and
is the best single thing to read.

To explore the relational model without running a workflow at all, build the
deterministic Phase 1 synthetic fixture — one study, several subjects, a dyadic
recording, two sessions, DeepSqueak and MUPET runs over one recording, matched
and unmatched detections, a split/merge ambiguity, device and setup profiles,
and an external event stream:

```matlab
[conn, summary] = vawlume.db.createPhase1FixtureDatabase( ...
    fullfile(tempdir, "vawlume_fixture.sqlite"), string(pwd));
```

[`../../schema/fixtures/phase1_acceptance_queries.sql`](../../schema/fixtures/phase1_acceptance_queries.sql)
holds representative queries against it, and
[`../../schema/fixtures/phase1_synthetic_fixture.md`](../../schema/fixtures/phase1_synthetic_fixture.md)
documents every row. The builder refuses an existing file
(`vawlume:db:FixtureDatabaseExists`); the database is disposable, so delete it
when finished.

### 6.2 The shortest path you type yourself

This is the smallest workflow that produces a real VAWLUME database. It uses the
shipped folder-driven project-input profile against a one-file synthetic tree.
Run it from the repository root.

```matlab
addpath("src")
repoRoot  = string(pwd);
workspace = fullfile(tempdir, "vawlume_quickstart");
if isfolder(workspace), rmdir(workspace, "s"); end

% 1. A source tree the shipped folder-driven profile understands:
%    <root>/<group>/mouse_<nnn>/<session>/<nnn>_<session>_<take>.wav
projectRoot = fullfile(workspace, "project");
audioPath   = fullfile(projectRoot, "control", "mouse_001", "baseline", ...
    "001_baseline_1.wav");
mkdir(fileparts(audioPath));
fid = fopen(audioPath, "w"); fclose(fid);   % placeholder stand-in for audio

% 2. A fresh database: schema, then the shipped semantic vocabulary.
databasePath = fullfile(workspace, "quickstart.sqlite");
conn = sqlite(char(databasePath), "create");
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
vawlume.db.registerBuiltinSemantics(conn, repoRoot);

% 3. Interpret the source tree. No database access happens here.
profilePath = fullfile(repoRoot, "config", "01_mapping_profiles", ...
    "project_inputs", "project_input_source_mapping_examples.json");
ir = vawlume.source_mapping.parse(profilePath, projectRoot, ...
    ProfileId="example.project.mouse_courtship.folder_driven", ...
    RepoRoot=repoRoot);

% 4. Dry run before any write.
report = vawlume.source_mapping.preview(ir, Print=true);   % -> "READY FOR INGEST"

% 5. Plan, then apply. Planning writes nothing.
projectSpec = struct( ...
    project_key="quickstart", ...
    project_name="VAWLUME quickstart", ...
    description="Minimal end-to-end example.");
plan    = vawlume.ingest.project(conn, ir, projectSpec);              % status "planned"
applied = vawlume.ingest.project(conn, ir, projectSpec, Apply=true);  % status "completed"

% 6. Read the relational result back.
fetch(conn, "SELECT recording_id, IFNULL(native_recording_id,'') AS native_recording_id " + ...
    "FROM recordings")
fetch(conn, "SELECT recording_id, entity_type, canonical_role, entity_native_id " + ...
    "FROM v_recording_entity_context")
fetch(conn, "PRAGMA foreign_key_check")   % expect an empty result

close(conn)
rmdir(workspace, "s")
```

**Inputs:** one placeholder `.wav` path plus the tracked project-input profile.

**Outputs:** one SQLite file at `<tempdir>/vawlume_quickstart/quickstart.sqlite`
holding the project, its portable source file, the experimental entity graph,
one recording, the mapping-profile provenance, and one immutable ingestion run.

**Verifying success.** Three cheap checks:

1. `report.verdict` is `"READY FOR INGEST"` and `ir.valid_for_ingest` is `true`;
2. `applied.status` is `"completed"` and `applied.committed` is `true`;
3. `PRAGMA foreign_key_check` returns no rows, and
   `v_recording_entity_context` shows the subject (`001`) and the session
   (`baseline`) recovered from the path.

Re-running step 5 against the same database is **idempotent for scientific
content**: the project, sources, entity graph, and recordings are reused, not
duplicated. One thing does grow — each apply records a new immutable
`ingestion_runs` attempt, which is the audit trail rather than a second
population.

### 6.3 Going further in the same database

Once a recording exists, an extractor import is one call. The importers take the
recording you already established — never inferred from the workbook basename,
the export's `File` column, or a folder convention:

```matlab
recordingRef = struct(recording_id=1);
% or: struct(project_key="quickstart", source_relative_path="control/.../001_baseline_1.wav")

runSpec = struct(run_key="ds-run-01", extractor_version="3.2.1");
result  = vawlume.ingest.deepsqueak(conn, exportPath, recordingRef, runSpec, ...
    RepoRoot=repoRoot);                     % plan
result  = vawlume.ingest.deepsqueak(conn, exportPath, recordingRef, runSpec, ...
    RepoRoot=repoRoot, Apply=true);         % commit
```

Then matching over two runs on that recording:

```matlab
matchSpec = struct(run_key="match-01", profile_path=fullfile(repoRoot, ...
    "config", "05_matching_profiles", "prototype_matching_consilience_spec.json"));
matching = vawlume.matching.compare(conn, recordingRef, ...
    struct(run_a="ds-run-01", run_b="mupet-run-01"), matchSpec, ...
    RepoRoot=repoRoot, Apply=true);

agreement = vawlume.consilience.summarize(conn, struct(run_key="match-01"), ...
    RepoRoot=repoRoot);   % read-only; Apply=true persists the aggregates
```

[`../../examples/matching_consensus_demo.m`](../../examples/matching_consensus_demo.m)
is the tested version of exactly this sequence, including the synthetic extractor
exports it imports.

---

## 7. Using your own data

Moving from the example to a real project is four decisions.

### 7.1 Describe your project structure

Copy one of the three profiles in
`config/01_mapping_profiles/project_inputs/project_input_source_mapping_examples.json`
into your own JSON file and edit it. You are declaring:

- a `source.include.glob` that finds your recordings;
- a `hierarchy.levels` list of your **native** level names, each with a
  `canonical_role` (`study`, `experimental_group`, `subject`, `session`,
  `recording`, …) and a `parent`;
- one `mappings` entry per level, drawn from a path component
  (`path_component_regex`), the filename (`filename_regex`), or a `literal`.

Keep your own profile outside the repository, or somewhere untracked, if it
encodes private study metadata or real subject identifiers.

Then iterate: `parse` → `preview` → fix the profile → repeat. Do not run intake
until the preview verdict is `READY FOR INGEST`.

### 7.2 Establish the recordings

```matlab
ir = vawlume.source_mapping.parse(myProfilePath, myProjectRoot, ...
    ProfileId="my.project.profile.id", RepoRoot=repoRoot);
vawlume.source_mapping.preview(ir, Print=true);
vawlume.ingest.project(conn, ir, ...
    struct(project_key="my-study", project_name="My study"), Apply=true);
```

Optionally pass `ProfileLinkagePath=` to attach tracked recording-device and
experimental-setup profiles, following
`config/04_examples/profile_linkage_example.json`.

### 7.3 Import your extractor output

**DeepSqueak** — one Excel call-statistics export per run. `runSpec.run_key` and
`runSpec.extractor_version` are required (the tracked profile declares
`extractor.version_required_at_ingest`, and the workbook carries no trustworthy
version). Optional `settings`, `model`, and `native_artifact` structs register
external evidence; absent evidence is recorded as unavailable rather than
defaulted.

**MUPET** — one per-syllable CSV per run. `run_key` and `extractor_version` are
required, and **settings evidence is required to apply**: supply either
`runSpec.settings = struct(config_path="…/config.csv")` or
`struct(json_path="…/settings.json")`. Applying without it raises
`vawlume:ingest:MupetSettingsRequired`, because MUPET reprocesses a recording
when its configuration changes and a run without its exact settings is not
reproducible.

Inspect either export without a database first:

```matlab
export = vawlume.ingest.deepsqueakExport(artifactPath, RepoRoot=repoRoot, ...
    ExtractorVersion="3.2.1");
vawlume.source_mapping.preview(export.ir, Print=true);
```

For an extractor VAWLUME ships no profile for, the path is to author a new
`extractor_output` profile against that extractor's documented fields and
validate it through `loadProfile` and `preview`. Nothing in the ingest, matching,
consilience, or alignment layers is DeepSqueak- or MUPET-specific.

### 7.4 Register external events and align clocks

Write one session manifest per session, following
`config/06_alignment_manifests/synthetic_session_alignment_manifest.json`. It
names the participating clocks, which one is the reference, the `method`
(`offset` or `affine`), and — for each stream and for the anchors — a source
table plus its mapping profile. It **points at** data and never embeds event
rows.

```matlab
bundle = vawlume.ingest.alignmentManifest(manifestPath, RepoRoot=repoRoot, ...
    SourceRoot=sessionFolder);                       % no database access
intake = vawlume.ingest.alignment(conn, manifestPath, RepoRoot=repoRoot, ...
    SourceRoot=sessionFolder, Apply=true);
fitted = vawlume.alignment.fit(conn, struct(run_key="my-alignment"), Apply=true);
qc     = vawlume.alignment.report(conn, struct(run_key="my-alignment"));
view   = vawlume.alignment.commonTime(conn, struct(run_key="my-alignment"), ...
    VocalizationSource="detections", VocalizationRunId=1);
```

Anchors are paired by **logical anchor identity** — an anchor key you supply on
each clock — never by nearest timestamp or pulse order. An anchor contributes to
a fit only when exactly one *included* observation exists on the source clock and
exactly one on the reference clock.

---

## 8. Outputs and data model

### 8.1 What is written where

VAWLUME writes into one SQLite file. There is no report or figure output layer
in the prototype; derived tables are returned to MATLAB.

| Stage | Principal tables written |
|---|---|
| Schema + seed | `schema_info`, `extractors`, `extractor_versions`, `canonical_features`, `extractor_features`, `feature_mappings`, `feature_relationships`, `config_profiles`, `config_profile_versions` |
| Project intake | `projects`, `source_files`, `entity_types`, `experimental_entities`, `entity_relationships`, `recordings`, `recording_entity_links`, `*_profile_assignments`, `ingestion_runs`, `ingestion_files` |
| Extractor import | `extraction_runs`, `extraction_run_inputs`, `extraction_run_profiles`, `artifacts`, `extraction_run_artifacts`, `detections`, `event_measurements`, and — DeepSqueak only — `curation_events`, `classification_runs`, `classification_classes`, `classification_assignments` |
| Matching | `analysis_runs`, `analysis_run_profiles`, `analysis_run_extraction_inputs`, `candidate_pairs`, `match_groups`, `match_group_members`, `consensus_events`, `consensus_event_members` |
| Consilience | `consilience_assessments`, `agreement_statistics`; `manual_reviews` and `manual_reference_events` hold independent human input |
| Alignment | `timebases`, `external_streams`, `external_stream_sources`, `external_stream_coverage`, `external_events`, `external_event_attributes`, `alignment_sets`, `alignment_anchors`, `alignment_anchor_observations`, `time_alignment_runs`, `alignment_segments`, `alignment_anchor_residuals` |

Convenience views: `v_detection_core`, `v_recording_entity_context`,
`v_event_measurements_long`, `v_match_group_members`,
`v_cross_extractor_feature_pairs`, `v_external_events_aligned`,
`v_sequence_members`.

### 8.2 Identifiers and provenance

- `INTEGER PRIMARY KEY` columns are VAWLUME surrogate IDs. Native identifiers
  (`native_event_id`, `native_recording_id`, `run_key`, `project_key`,
  `stream_key`, `timebase_key`, anchor keys) stay TEXT and explicitly scoped.
- Every identity-bearing file — source recordings, extractor exports, settings
  artifacts, native `.mat` containers, mapping profiles, matching
  specifications, alignment manifests — is registered with a **SHA-256 checksum**
  and a portable relative path. Relocating a file is recognized as the same file;
  changing its content is a **conflict**, not an overwrite.
- `analysis_runs` carries `vawlume_version` and `source_commit`, supplied by the
  caller on the matching `matchSpec` or the alignment `RunSpec`. Neither is
  inferred from the working tree.

### 8.3 How the pieces relate

```text
recording ──< extraction_run ──< detection ──< event_measurement
     │              │
     │              └── artifacts, settings, model, mapping profile
     │
     ├──< analysis_run (matching) ──< candidate_pair ──< match_group ──< consensus_event
     │              │
     │              └──< analysis_run (consilience, child) ──< consilience_assessment
     │                                                        agreement_statistics
     │
     ├──< manual_reference_events   (reviewer-authored, scoped to the recording,
     │                               never derived from extractor curation)
     │
     └──< timebase (native audio) ──< alignment_set ──< time_alignment_run
                    external_stream ──< external_event         │
                    alignment_anchor ──< observation ──< residual, alignment_segment
```

### 8.4 Source versus derived

**Source (never rewritten by VAWLUME):** your recordings and extractor exports;
and, in the database, `source_files`, `artifacts`, `detections`,
`event_measurements`, `external_events`, `external_stream_coverage`,
`alignment_anchor_observations`, `manual_reference_events`. Native timestamps are
never updated — an aligned time is derived on demand from stored coefficients.

**Derived (regenerable from source plus configuration):** `candidate_pairs`,
`match_groups`, `consensus_events`, `consilience_assessments`,
`agreement_statistics`, `alignment_segments`, `alignment_anchor_residuals`, the
whole `commonTime` table, and the regularized timeline. The regularized timeline
is a **MATLAB working artifact only** — deliberately not persisted, which is why
`sequences` and `sequence_members` stay empty after a full workflow.

The database file itself is a derived artifact. What is worth version
controlling is the profiles, manifests, specifications, and scripts that
regenerate it.

---

## 9. Validation and troubleshooting

Errors carry `vawlume:<package>:<Identifier>` message IDs, so
`catch e; e.identifier` tells you which contract was violated.

### Configuration and profile loading

| Symptom | Identifier | What to do |
|---|---|---|
| Profile file will not load | `vawlume:source_mapping:ProfileLoadFailed`, `:FileReadFailed` | Check the path and that the file is valid JSON |
| Wrong profile kind for the call | `:UnexpectedProfileKind`, `:UnsupportedProfileKind` | Only `project_input`, `extractor_output`, `external_stream_mapping`, `alignment_anchor_mapping` are source-mapping kinds |
| Multi-profile document, no `ProfileId` | `:ProfileSelectionRequired`, `:ProfileIdNotFound` | Pass `ProfileId=` naming one `profile.id` in the document |
| Regex rejected at load | `:InvalidProfileRegex` | MATLAB `regexp` syntax, with `\` escaped as `\\` in JSON |
| Missing or duplicate value-map entry | `:InvalidProfileValueMap` | Each entry needs explicit `native_value` and `canonical_value` |
| Unknown transform key | `:UnknownTransform` | Transforms are a whitelist; arbitrary function names are never dispatched from profile text |
| Missing profile version | `:MissingProfileVersion`, `:UnsupportedProfileSchemaVersion` | Declare both `profile_version` and a supported `profile_schema_version` |

### Source discovery and parsing

Discovery and parsing rarely raise — they record **structured issues** in the IR,
which is what `preview` renders. Read the verdict, not just the absence of an
exception:

- **no sources found** — the `include.glob` did not match. Discovery is recursive
  and case-sensitive;
- **unmatched sources / regex misses** — a `path_component_regex` or
  `filename_regex` did not match a discovered file. The preview names the rule
  and the file;
- **`VALUE_CORROBORATED` (INFO)** — two rules captured the same normalized value
  for one concept. Harmless; it is how the folder-driven example recovers
  `subject_id` from both the folder and the filename;
- **value conflict / ambiguity (ERROR)** — two rules disagree.
  `ir.valid_for_ingest` becomes `false` and intake will refuse the IR;
- `vawlume:source_mapping:SourceRootNotFound` / `:PathOutsideRoot` — the source
  root does not exist, or a resolved path escaped it.

### Intake and import

| Symptom | Identifier | Cause |
|---|---|---|
| Apply refused, nothing written | `vawlume:ingest:PlanConflict` | Some identity already exists with incompatible content — usually a changed checksum under an existing key. Inspect the returned conflicts |
| `projectSpec` rejected | `vawlume:ingest:InvalidProjectSpec` | `project_key` **and** `project_name` are both required |
| Recording not resolved | `:DeepSqueakRecordingRefInvalid`, `:MupetRecordingRefInvalid` | Supply exactly one of `recording_id`, or `project_key` **with** `source_relative_path` — never both modes |
| Run spec rejected | `:DeepSqueakRunSpecInvalid`, `:MupetRunSpecInvalid` | `run_key` and `extractor_version` are required |
| MUPET apply refused | `:MupetSettingsRequired` | Supply `settings.config_path` or `settings.json_path`. No default configuration is ever substituted |
| Workbook or CSV unreadable | `:DeepSqueakArtifactUnreadable`, `:MupetArtifactUnreadable`, `:*ArtifactUnsupported`, `:*ArtifactNotFound` | Wrong file, wrong sheet, or a format outside the profile's declared artifact class |
| IR not valid | `:MupetIRNotValid` | Fix the mapping issues the preview reported before importing |

The DeepSqueak profile's version scope prefers 3.2.x within the 3.x family; a
version outside it is reported in the adapter result rather than silently
accepted.

### Matching, consilience, alignment

| Symptom | Identifier | Cause |
|---|---|---|
| Run pair rejected | `vawlume:matching:RunPairInvalid` | The two runs must be distinct runs by distinct extractors on the same recording. Automatic run discovery is forbidden by the specification |
| Specification rejected | `vawlume:matching:SpecificationInvalid`, `:UnexpectedSpecificationKind` | The spec must be a `consilience_policy` profile |
| Summarize refuses | `vawlume:consilience:AnalysisRefInvalid`, `:SpecificationInvalid` | The reference resolved to zero or several analyses, or the spec is not the one that produced those groups |
| Feature comparison reports `not_computed_split_merge` | — | Not an error. Quantitative comparison is restricted to unambiguous one-to-one groups; ambiguous groups are never averaged into a value |
| Central frequency compares nothing | — | Expected. Use `equivalence_class` / `feature_relationships`, not a canonical-name join (§5.5) |
| Sensitivity raises | — | The compared analyses must share one recording, one ordered run pair, and one algorithm version, or the rows would not be comparable |
| Alignment set not found or ambiguous | `vawlume:alignment:AlignmentSetNotFound`, `:AlignmentSetAmbiguous`, `:AlignmentRefInvalid` | Select exactly one set by `alignment_set_id`, `run_key`, or `project_key` + `run_key` |
| Manifest rejected | `vawlume:ingest:AlignmentManifestInvalid` | Check the clocks, the reference timebase, and each stream's source plus mapping profile |
| `applyTransform` raises | `vawlume:alignment:TransformRunNotFound` | The run was never fitted, or its fit was rejected. It will not return a plausible-looking number instead |
| `piecewise_affine` raises | — | Deliberate. Piecewise is representable in the schema but unimplemented, and silently returning an affine fit would answer a different question |
| Event outside declared coverage | `vawlume:alignment:EventOutsideCoverage` | Fix the declared coverage, or pass `ErrorOnOutsideCoverage=false` knowingly |
| Bin or window rejected | `vawlume:sequence:WindowInvalid`, `:WindowNotDivisible`, `:BinOriginMisaligned`, `:AggregationUnsupported` | Supported aggregations are `onset_count`, `presence`, and `any_overlap` |

### Two environment gotchas

1. **`fetch` fails on NULL text columns.** MATLAB's Database Toolbox raises
   `Unexpected NULL; (zero-based) column index: N` when a text column in the
   result set contains SQL `NULL`. Wrap nullable text columns:
   `SELECT IFNULL(native_recording_id,'') AS native_recording_id …`. The shipped
   demonstrations do this throughout.
2. **`executeSQLScript` is not used.** `vawlume.db.applySchema` executes the
   schema statement by statement, preserving `CREATE TRIGGER … END;` blocks,
   because the Database Toolbox does not support script execution for `sqlite`
   connections in this environment.

### Running the test suite

```matlab
addpath("src")
results = runtests("tests", IncludeSubfolders=true);
table(results)
```

The suite is currently **329 tests** and takes roughly eleven minutes. Passing it
is the strongest available check that an environment is correctly configured.

---

## 10. Prototype limitations

### Implemented and tested

Schema and semantic seeding; project-input, extractor-output, external-stream,
and alignment-anchor source mapping with dry-run preview; transactional project
intake; DeepSqueak and MUPET import; cross-extractor matching,
connected-component assignment, explicit unmatched groups, and topology-gated
consensus; detection- and feature-level agreement; consilience statuses;
manual-reference evaluation; threshold sensitivity; alignment registration,
offset/affine transform fitting with residual QC, common-time projection, and
coverage-aware regularized timelines.

### Implemented but explicitly uncalibrated or narrow

- **Every shipped threshold is illustrative.** The matching specification carries
  `calibration_status.state = "illustrative_prototype"`. Calibration needs a
  genuine paired extractor session and an independent manually reviewed reference
  subset; neither exists yet. No configuration should be reported as optimal,
  validated, or recommended.
- A solved alignment fit is `estimated`, never `validated`. There is no
  calibrated acceptance threshold.
- Anchor uncertainty is preserved but **not** used as a fit weight; replicate
  observations are preserved but not pooled.
- Coverage comes only from profile-declared constant segments; recording coverage
  is duration-derived with no multi-segment dropout model, and an event spanning
  two adjacent coverage segments is rejected.
- One source file per manifest stream declaration.
- MUPET creates no curation, classification, or detection-score rows — the
  per-syllable CSV exports none, and surviving MUPET's programmatic filtering is
  not a reviewed state.
- Project-intake profile-linkage validation covers the demonstrated linkage
  language; generalized profile composition and full device/setup domain
  validation are not implemented.
- `aligned_external_events` is an optional cache with no public refresh API.

### Representable in the schema but unimplemented

`piecewise_affine` transforms raise rather than approximating. `sequences`,
`sequence_members`, `bouts`, `bout_members`, `metric_definitions`, and
`derived_measurements` are written by no code path at all. `recording_epochs` is
written only by the Phase 1 synthetic fixture builder — no ingest or analysis
path populates it.

### Deliberately deferred

Sequence, bout, motif, transition, and hierarchy-aware analyses; edit-distance
and string methods; sequence clustering; peri-event summaries; machine learning;
continuous-signal ingestion; full acquisition synchronization; automatic outlier
rejection in matching; a universal experimental ontology; a GUI; a CLI or batch
wrapper; exhaustive extractor support; automatic biological interpretation of
extractor-native classes; publication artefacts.

---

## 11. Where to look next

### Design and architecture

- [`../design/01_prototype_development_outline.md`](../design/01_prototype_development_outline.md) — prototype development plan and completion criteria
- [`../design/02_temporal_alignment_contract.md`](../design/02_temporal_alignment_contract.md) — alignment design contract, exit criteria, known limitations

### Contracts per stage

- [`../development/03_source_mapping_intermediate_representation.md`](../development/03_source_mapping_intermediate_representation.md) — the IR and dry-run contract
- [`../development/04_project_intake.md`](../development/04_project_intake.md) — intake boundary, identity, transactions, provenance
- [`../development/05_deepsqueak_import.md`](../development/05_deepsqueak_import.md) — DeepSqueak import contract and limitations
- [`../development/06_mupet_import.md`](../development/06_mupet_import.md) — MUPET import, the deliberate absences, and the shared extractor core
- [`../development/07_matching_and_consensus.md`](../development/07_matching_and_consensus.md) — the end-to-end matching → consilience workflow
- [`../development/07_matching_candidate_generation.md`](../development/07_matching_candidate_generation.md) and [`../development/08_matching_assignment_and_consensus.md`](../development/08_matching_assignment_and_consensus.md) — candidates, topology, consensus lineage
- [`../development/09_detection_and_feature_agreement.md`](../development/09_detection_and_feature_agreement.md) — agreement denominators and feature-pair discovery
- [`../development/10_consilience_manual_qc_and_sensitivity.md`](../development/10_consilience_manual_qc_and_sensitivity.md) — status rules, manual reference, sensitivity
- [`../development/11_temporal_alignment_schema.md`](../development/11_temporal_alignment_schema.md) — the alignment data dictionary
- [`../development/12_alignment_intake_and_registration.md`](../development/12_alignment_intake_and_registration.md) — manifest contract and transaction semantics
- [`../development/13_transform_fitting_and_alignment_qc.md`](../development/13_transform_fitting_and_alignment_qc.md) — fit models, residuals, `estimated` versus `validated`
- [`../development/14_common_time_views_and_regularized_timeline.md`](../development/14_common_time_views_and_regularized_timeline.md) — common time and bin semantics

### Configuration and schema

- [`../../config/README.md`](../../config/README.md) — profile categories, authoring workflow, versioning
- [`../../schema/schema.sql`](../../schema/schema.sql) — the executable schema, its triggers, and its views
- [`../../schema/fixtures/phase1_synthetic_fixture.md`](../../schema/fixtures/phase1_synthetic_fixture.md) and [`../../schema/fixtures/phase1_acceptance_queries.sql`](../../schema/fixtures/phase1_acceptance_queries.sql) — the deterministic fixture and representative queries

### Extractor references

- [`../reference/extractors/DeepSqueak_Extractor_Design_Reference.md`](../reference/extractors/DeepSqueak_Extractor_Design_Reference.md)
- [`../reference/extractors/MUPET_Extractor_Design_Reference.md`](../reference/extractors/MUPET_Extractor_Design_Reference.md)

### Development conventions

- [`../development/01_environment.md`](../development/01_environment.md) — MATLAB release and toolbox
- [`../development/01_repo_structure.md`](../development/01_repo_structure.md) — repository layout policy
- [`../development/02_development_workflow.md`](../development/02_development_workflow.md) — namespace, testing, and provenance conventions

There is currently no `CONTRIBUTING.md`; contribution guidance is deferred until
outside contributions are plausible.
