# VAWLUME Prototype Usage Guide

> **Scope.** This is a practical guide to the VAWLUME prototype **as currently
> implemented**. It is not the eventual VAWLUME manual, and it does not describe
> planned functionality. Where this guide and an older design document disagree,
> the repository is the authority.
>
> **Status.** Early prototype. The schema (`0.11-draft`, `PRAGMA user_version = 11`),
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
- **import** DeepSqueak Excel call-statistics exports, MUPET per-syllable CSVs,
  and USVSEG `<stem>_dat.csv` event exports onto an established recording,
  creating extraction runs, artifacts, detections, and native plus canonical
  event measurements;
- **match** two explicitly selected extraction runs on one recording by temporal
  overlap, preserving ambiguity as connected-component match groups, and derive
  consensus events only where topology permits;
- **quantify** detection- and feature-level agreement, assign provenance-bearing
  consilience statuses, evaluate against an independent reviewer-authored
  reference set, and compare several matching thresholds side by side;
- **compose** a complete set of compatible pairwise analyses into arbitrary-N
  extractor agreement over native detections, and select exact or coarse
  agreement populations without collapsing split/merge components;
- **register** timestamped external event streams (behavioural, neural/TTL) and
  logical alignment anchors from one session manifest, **fit** offset, affine,
  or continuous piecewise-affine source-to-reference clock transforms with
  per-anchor residual evidence, project points, intervals, events, and coverage
  onto a common clock, and build a coverage-aware regularized timeline;
- **register** coordinate systems and per-channel microphone placements,
  canonicalize external tracking artifacts without copying dense samples into
  SQLite, preserve time-varying ambiguous track-to-entity evidence, and declare
  optional acoustic-reference points/intervals with source provenance;
- **measure** those references on explicit channels from bounded reads of the
  linked local audio, and aggregate an exact set of those measurements into
  per-family, per-channel response/QC estimates whose every supporting
  measurement and source run is cited;
- **create** a provenance-bearing caller-attribution run over one explicit
  detection, consensus-event, or agreement-group event set, snapshotting its
  direct inputs and participating entities before any caller is scored; and
- **append** several candidate callers per target with distinct score and
  probability semantics, plus separately readable temporal-alignment,
  pose/localization, visual-identity, acoustic, correspondence, or imported
  composite evidence;
- **import** an external caller-attribution table through a versioned mapping
  profile, storing every number exactly as the file carried it beside the
  semantics that say what it meant there, resolving caller labels only as the
  profile declares, and reporting every row it could not map;
- **relate** those imported windows to a run's VAWLUME events under an explicitly
  declared clock relationship and the profile's own eligibility rule, preserving
  ambiguity, naming the interval basis each score rests on, and counting rather
  than resolving the windows that match nothing or match several events;
- **decide** one status per target from stored candidates under a versioned,
  checksummed policy that keeps `ambiguous` and `simultaneous` apart, and retains
  the threshold that bound each decision; and
- **read back** a whole attribution run through one function, with QC that is
  counts, memberships and observed ranges and contains no quality score,
  threshold or verdict.

[`../../examples/multimodal_integration_demo.m`](../../examples/multimodal_integration_demo.m)
runs the whole multimodal layer as one synthetic workflow, including an
ambiguous visual crossing; it assigns no caller.
[`../../examples/caller_attribution_demo.m`](../../examples/caller_attribution_demo.m)
runs the whole imported attribution path, and what it does with a caller is
narrower than it may look: it stores what an external system claimed, relates
those claims to VAWLUME events, and applies a policy you declared. Nothing in
this prototype estimates who called.

### Important limitations

- **Extractor coverage is deliberately narrow.** DeepSqueak (Excel
  call-statistics export), MUPET (per-syllable CSV), and USVSEG
  (`<stem>_dat.csv`) are the only implemented importers, and only their primary
  event export is read. Native DeepSqueak `.mat` containers, detector networks,
  classification models, and USVSEG's optional trace/WAV/image outputs are
  registered and checksummed where supplied but never parsed. VAWLUME does not
  wrap or run any extractor.
- **Extractor agreement is not truth.** Convergence between two or three
  extractors is methodological evidence about the extractors. It is not a
  confidence probability, not a claim that a vocalization occurred, and not
  evidence about which animal called.
- **No GUI, no CLI.** VAWLUME is a set of namespaced MATLAB functions called
  from the MATLAB command window or a script.
- **No continuous-signal ingestion.** Only *timestamped events* enter the
  database. Neural, photometry, and video samples stay external.
- **Alignment anchors are user-supplied**, never discovered from waveforms or
  pixels. A solved fit is recorded as `estimated`, never `validated` — there is
  no calibrated acceptance threshold.
- **Sequence, bout, motif, and hierarchy-aware analyses are not implemented.**
  The `sequences`, `sequence_members`, `bouts`, and `bout_members` tables exist
  in the schema as modeled storage, but no current workflow writes rows to them.
- **Real-data acceptance is operational, not scientific validation.** The
  extractor-consilience exploration workflow has run end to end on one real
  Pilot 3 recording with DeepSqueak, MUPET, and USVSEG outputs. No comprehensive
  manually reviewed ground-truth reference or threshold calibration has been
  completed, and the multi-recording sampling path remains untested on real
  data.
- **Channel-response estimates are not caller evidence.** VAWLUME now reads
  bounded audio windows and measures declared references on explicit channels,
  but the result is uncalibrated response/QC evidence about the channels. It is
  not a gain correction, not a normalized call amplitude, not a preferred
  channel, and not a probability that any animal called.
- **VAWLUME estimates no caller.** The only implemented attribution path is the
  imported one: it stores what an external system claimed, relates those claims
  to VAWLUME events, and applies a policy you supplied. The backend/localization
  path and the VAWLUME-native estimator are later phases.
- **A decision is not a combination of the evidence.** The shipped policy reads
  one candidate column and no evidence row, so nothing combines pose,
  visual-identity, alignment, and acoustic evidence into a claim about who
  vocalized. Those components remain separate precisely so a later declared
  method can combine them deliberately. A decision is also not a probability,
  and no status means `validated`.
- **Every attribution threshold that ships is illustrative.** The mapping
  profile's correspondence floor and the decision policy's selection, separation
  and co-occurrence thresholds are demonstration values chosen to exercise
  behaviour on synthetic data. Calibrating them needs output from a real
  attribution system plus an independent ground truth for who called, and
  neither exists.
- **No image-based re-identification.** VAWLUME consumes whatever identity
  evidence an upstream tool supplies and performs no pixel processing of its
  own. A native track label is never treated as canonical animal identity.
- **Tracking samples stay external, and raw video is never processed.** Only the
  stream, its traces, its clock, its frame, and its coverage are stored;
  positions and confidences are read from the artifact window-wise on demand.
- **Coordinate compatibility is declaration and validation, not
  transformation.** VAWLUME confirms that two spatial facts cite the same
  declared frame, and refuses to relate them otherwise. It never transforms
  between frames, and it computes no distances.

### VAWLUME and external extractors

VAWLUME does **not** detect or extract vocalizations. It consumes what an
external extractor already produced. The conceptual machinery — mapping
profiles, the IR, the relational model, matching, consilience, agreement,
alignment — is extractor-independent; only the shipped output-mapping profiles
and the three thin artifact adapters are extractor-specific. Nothing in the
architecture is hard-coded to three extractors: the agreement layer is
combinatorial in N.

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
| Extractor input | Any of: a DeepSqueak Excel call-statistics export; a MUPET per-syllable CSV plus its native `config.csv`; a USVSEG `<stem>_dat.csv` |

See [`../development/01_environment.md`](../development/01_environment.md).

Nothing is compiled or installed. Repository setup is: obtain the repository,
put `src/` on the MATLAB path, and create a database file.

**Platform.** Development and testing have been carried out on Windows 11 only.
The implementation uses no platform-specific calls and handles path-case
sensitivity explicitly, so other platforms are expected to work — but none has
been exercised, so cross-platform support is not claimed. If you run VAWLUME on
macOS or Linux, treat the test suite (§9) as your first check.

---

## 3. Conceptual workflow

```text
user project structure          extractor artifacts          external event tables
(folders, filenames)            (DeepSqueak xlsx,            (behaviour, neural TTL)
                                 MUPET csv,                   + anchor tables
                                 USVSEG csv)
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
                         / usvseg
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
        |                      manual QC)                    regularizeTimeline
        |
 vawlume.agreement.compose  ->  vawlume.agreement.selectPopulation
 (arbitrary-N groups over        (exact pattern / coarse K populations)
  native detections)
```

A third boundary follows from the last row. **Pairwise matching is the
primitive and arbitrary-N agreement is derived from it.** `compose` takes a set
of completed pairwise *analyses*, not a set of runs, and never reimplements
matching as a second matcher.

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

Only three things have a default, and all resolve to a *tracked* file beneath
`RepoRoot`: the extractor importers fall back to their shipped output-mapping
profile, `vawlume.matching.compare` falls back to
`config/05_matching_profiles/prototype_matching_consilience_spec.json` when
`matchSpec.profile_path` is omitted, and `vawlume.agreement.compose` falls back
to `config/07_agreement_profiles/prototype_multi_extractor_agreement_spec.json`
when `agreementSpec.profile_path` is omitted. Project-input profiles,
external-stream and anchor profiles, and alignment manifests must always be
named explicitly.

---

## 5. Configuration

All tracked configuration is canonical JSON under `config/`. See
[`../../config/README.md`](../../config/README.md) for the full policy.

| Directory | Kind | Needed for |
|---|---|---|
| `config/01_mapping_profiles/project_inputs/` | `project_input` | project intake |
| `config/01_mapping_profiles/extractors/deepsqueak/`, `.../mupet/`, `.../usvseg/` | `extractor_output` | extractor import (shipped; usable as-is) |
| `config/01_mapping_profiles/external_streams/` | `external_stream_mapping` | external event registration |
| `config/01_mapping_profiles/alignment_anchors/` | `alignment_anchor_mapping` | anchor registration |
| `config/02_device_profiles/`, `config/03_setup_profiles/` | device / setup examples | optional acquisition provenance |
| `config/04_examples/profile_linkage_example.json` | linkage | optional device/setup assignment at intake |
| `config/05_matching_profiles/` | `consilience_policy` | matching and consilience |
| `config/06_alignment_manifests/` | session manifest (**not** a profile kind) | alignment intake |
| `config/07_agreement_profiles/` | `multi_extractor_agreement_spec` | arbitrary-N agreement composition |

### 5.1 Defaults versus what you must author

**Usable as shipped, no editing needed:**

- all three extractor-output mapping profiles;
- the prototype matching/consilience specification
  (`prototype_matching_consilience_spec.json`) — but read §10 about its
  thresholds;
- the prototype arbitrary-N agreement policy
  (`prototype_multi_extractor_agreement_spec.json`), which declares no
  threshold of any kind and refuses a variant that adds one;
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
in `missing_value_policy` rather than handled in code — the MUPET v2.1 profile,
for example, declares `NA` and `_` as missing tokens for the inter-syllable
interval while preserving the raw token, so a terminal sentinel never silently
becomes `0`.

### 5.5 Feature semantics

Canonical feature names and native-to-canonical mappings are derived from the
tracked extractor profiles by `vawlume.db.registerBuiltinSemantics`. The tracked
profile is the authoritative source; the seed registers it rather than
maintaining a second copy.

Run `vawlume.db.registerBuiltinSemantics(conn, repoRoot)` after opening an
existing database as well as after creating a new one. The operation is
idempotent and append-only for profile versions: it discovers every shipped
extractor-output JSON profile, adds revisions that are not yet represented in
the registry, and preserves older version rows for provenance. This step is
especially important after updating the repository, before planning an import.

One consequence matters when querying: **cross-extractor feature comparison goes
through `extractor_features.equivalence_class` and `feature_relationships`, not
through a shared canonical name.** DeepSqueak's contour median is registered
under its own canonical name rather than the generic `frequency_center` MUPET
uses, so a canonical-name join finds nothing at all for central frequency. A
shared equivalence class only nominates candidates. A pair is compared only when
its registered relationship is `consilience_eligible` and both sides' canonical
units agree.

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

Every shipped demonstration creates every input it needs under the system
temporary directory and removes it before returning. From the repository root:

```matlab
addpath("src")
addpath("examples")

project_intake_demo            % source mapping -> preview -> intake -> read-back
deepsqueak_import_demo         % + DeepSqueak run, artifacts, detections, measurements
mupet_import_demo              % + MUPET syllables, settings provenance, NA missingness
usvseg_import_demo             % + USVSEG syllables, weak settings, zero-detection run
matching_consensus_demo        % + matching, consensus, agreement, consilience, sensitivity
multi_extractor_agreement_demo % + three extractors, arbitrary-N agreement, exact vs coarse
agreement_filter_demo          % + agreement populations joined to context and features
temporal_alignment_demo        % + manifest registration, transform fitting, common time
multimodal_integration_demo    % geometry, tracking, visual identity, acoustic response
caller_attribution_demo        % + imported caller attribution, correspondence, decisions
consilience_exploration_demo   % + diagnostics, threshold screen, subset probe, gallery
```

Each returns a struct and prints a compact report; pass `Print=false` to
suppress the printing. Every one is covered by an integration test, so the
numbers they print are asserted rather than merely observed.

Five are worth reading first. `matching_consensus_demo` is the complete
**pairwise** path, including consilience and threshold sensitivity.
`multi_extractor_agreement_demo` is the complete **three-extractor** path:
it imports all three extractors onto one recording, runs all three pairwise
comparisons, composes them into agreement groups, and then queries the same run
by exact edge pattern and by coarse K-of-possible support.

`multimodal_integration_demo` is the complete **multimodal input** path, and it
shares no surface with the extractor ones. It declares an arena frame and two
microphone placements, registers an external tracking artifact holding three
native trajectories, reads bounded tracking windows in all three coverage
states, records identity evidence across a crossing where two trajectories swap
animals, declares four acoustic references, measures them on both channels from
bounded audio reads, and aggregates one response/QC profile with exact lineage.
It keeps pose confidence, visual-identity evidence, clock residual, and acoustic
response as four separate numbers and combines none of them. See
[`../development/29_integrated_multimodal_demonstration.md`](../development/29_integrated_multimodal_demonstration.md).

`caller_attribution_demo` is the complete **imported caller-attribution** path,
and it is the one to read if you want to know what this prototype will and will
not tell you about who called. It imports an external export on the exporting
system's own clock, fits a piecewise-affine transform relating that clock to the
recording's, corresponds the imported windows to VAWLUME detections across it,
and then does the whole thing again over VAWLUME consensus events. One target
carries three candidate callers and one carries none, one window plausibly refers
to two events, one window refers to nothing, and one claim carries no number and
keeps none. It decides the same candidates twice under different thresholds, so
you can see the decision move while the candidates do not, and it demonstrates
four named refusals beside the successes. See
[`../development/34_integrated_caller_attribution_demonstration.md`](../development/34_integrated_caller_attribution_demonstration.md).

`consilience_exploration_demo` is the complete **extractor-consilience
exploration** path, and it is the slowest of the set because it really executes
two sensitivity probes. It applies the tracked reference configuration, diagnoses
the candidate-metric space, decides for itself which matching thresholds to screen
and at what values, screens them over the whole dataset, draws a seeded
metadata-stratified subset and probes it harder, compares the two probes,
characterizes every exact extractor-support pattern, renders a spectrogram
gallery, and exports the tables, figures, example index and provenance. It
deliberately shows thin data: a fractional screen that makes no leverage claim
about any factor, three support patterns with no members at all, and six that
cannot supply the number of examples requested. See §6.5 and
[`../development/35_consilience_exploration_workflow.md`](../development/35_consilience_exploration_workflow.md).

To explore the relational model without running a workflow at all, build the
deterministic Phase 1 synthetic fixture — one study, several subjects, a dyadic
recording, two sessions, DeepSqueak, MUPET, and USVSEG runs over one recording,
matched and unmatched detections, a split/merge ambiguity, device and setup
profiles, and an external event stream:

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

### 6.4 Three extractors: arbitrary-N agreement

Once a recording carries three extraction runs by three distinct extractors,
agreement over all of them is composed from the pairwise analyses rather than
computed directly.

**Step 1 — every pairwise comparison, under one specification.** For N runs you
need all `N*(N-1)/2` extractor pairs, each exactly once, and each citing the
same versioned matching specification. Composition refuses an incomplete or
mixed set, so that a missing supporting edge can never be confused with a pair
that was never assessed.

```matlab
specPath = fullfile(repoRoot, "config", "05_matching_profiles", ...
    "prototype_matching_consilience_spec.json");
pairs = {"m-ds-mupet",     "ds-run-01",    "mupet-run-01"
         "m-ds-usvseg",    "ds-run-01",    "usvseg-run-01"
         "m-mupet-usvseg", "mupet-run-01", "usvseg-run-01"};
for k = 1:size(pairs, 1)
    vawlume.matching.compare(conn, recordingRef, ...
        struct(run_a=pairs{k,2}, run_b=pairs{k,3}), ...
        struct(run_key=pairs{k,1}, profile_path=specPath), ...
        RepoRoot=repoRoot, Apply=true);
end
```

**Step 2 — compose.** `sources` is the set of *analyses*, not runs. Order
carries no meaning.

```matlab
composed = vawlume.agreement.compose(conn, recordingRef, ...
    ["m-ds-mupet", "m-ds-usvseg", "m-mupet-usvseg"], ...
    struct(run_key="agree-01"), RepoRoot=repoRoot, Apply=true);
```

**Step 3 — select populations.** `selectPopulation` is read-only.

```matlab
ref = struct(project_key="quickstart", run_key="agree-01");

all      = vawlume.agreement.selectPopulation(conn, ref);
exact    = vawlume.agreement.selectPopulation(conn, ref, ...
    ExactSupportPattern="deepsqueak--mupet|mupet--usvseg");
coarse   = vawlume.agreement.selectPopulation(conn, ref, ...
    MinSupportedPairCount=2);
ambiguous = vawlume.agreement.selectPopulation(conn, ref, ...
    Completeness="complete", Multiplicity="multiple_per_extractor");
```

**Reading the result correctly** matters more here than anywhere else in the
prototype:

- **Exact and coarse are different questions.** `ExactSupportPattern` asks
  *which* extractor pairs are supported; `MinSupportedPairCount` /
  `ExactSupportedPairCount` ask *how many*. Two components can both support two
  of three possible pairs while supporting different pairs, and only the coarse
  query merges them.
- **The denominator is component-local.** `possible_extractor_pair_count` is
  `C(N,2)` over the extractors actually represented in that component, not a
  run-wide constant. A two-extractor component has a denominator of 1.
- **A singleton's support fraction is `NaN`, not 0.** No extractor pair was
  possible, which is not the same as corroboration that failed.
- **Groups and members are different denominators.** `result.groups` is one row
  per component; `result.members` is one row per native detection. A split/merge
  component is one group with several native observations. Say which
  denominator a summary used.
- **Connectivity is not completeness.** A three-member component says its
  members are connected, never that all three extractor pairs support one
  another. Check `is_extractor_pair_support_complete`.

[`../../examples/multi_extractor_agreement_demo.m`](../../examples/multi_extractor_agreement_demo.m)
is the tested version of this whole sequence, from three imports through both
query styles, over a fixture built to contain each of those shapes.
[`../../examples/agreement_filter_demo.m`](../../examples/agreement_filter_demo.m)
goes one step further and joins the selected native members to time-bounded
experimental context and long-form measurements.

Agreement strength is methodological evidence about extractor convergence. It
is not a calibrated confidence probability and not a biological truth label.

### 6.5 Exploring extractor consilience

Once a project carries runs from several extractors, you can ask a different
kind of question: not *what did they agree on under this configuration*, but
*how does their agreement respond to the configuration at all*, and *what kinds
of detections occupy each extractor set*.

That is one call.

```matlab
options = vawlume.eda.explorationOptions(struct(seed=20260918));

exploration = vawlume.eda.runExploration(conn, ...
    struct(project_key="my_project"), ...
    Options=options, RepoRoot=repoRoot, ...
    OutputRoot=fullfile(tempdir, "vawlume_exploration"), ...
    SourceRoot="C:\path\to\audio_root");
```

[`../../examples/templates/consilience_exploration_workflow_template.m`](../../examples/templates/consilience_exploration_workflow_template.m)
is a ten-section template to copy and edit: everything you choose is in section
one, and the rest reads the results back.

**You do not define a parameter grid.** Which matching dimensions are screened,
at what low and high values, how large the subset is and which recording-level
field it is stratified on are all decided by the workflow and written into its
provenance record. A normal run configures a seed and nothing else.

#### What it does, in order

1. **Applies the tracked reference configuration** to every recording. The
   diagnostics read stored candidate pairs and the probe values are anchored on
   quantiles of those same observed metrics, so something has to have matched
   first. This is also the run the extractor-set summaries and the gallery are
   computed at.
2. **Diagnoses the candidate-metric space** — distributions and robust
   quantiles, Pearson and Spearman correlation, partial correlation, coverage in
   five disjoint categories, and redundancy findings.
3. **Resolves what to screen.** Up to four dimensions participate:
   `min_temporal_iou` and the three `max_abs_{onset,offset,duration}_difference_s`
   bounds. A dimension with too little coverage, or whose low and high values
   resolve equal, is reported **inactive with its reason** rather than screened
   at an arbitrary value.
4. **Screens the whole dataset** under a bounded, interaction-aware design.
5. **Draws a seeded subset of recordings**, stratified automatically when a
   recording-level field qualifies, and probes it with a larger budget.
6. **Compares the two probes**, per factor per response.
7. **Characterizes every exact extractor set** at the reference
   configuration, with coverage beside every feature summary.
8. **Renders a representative spectrogram gallery** from the original audio.
9. **Exports** tables, figures, the example index and a provenance record.

Generated specifications, exports, and the gallery use three sibling locations
under `OutputRoot`: `exploration/<run key>/specs/`, `exports/`, and `gallery/`.
The tables, figures, provenance JSON, example index, and images are therefore
not nested under the run-key specification directory.

Each stage can be run on its own. `Stages="diagnostics"` gives you the cheap
first look without building a design or executing a probe, and `Apply=false`
prices every probe without writing anything — worth doing before you commit to a
long run.

#### Know the cost before you start it

For `C` configurations, `R` recordings and `N` extractors the work is

```
C × R × N(N−1)/2   matching analyses   +   C × R   agreement analyses
```

For three extractors that is **four analyses per configuration per recording**,
so a configuration count understates the real work roughly fourfold. Eight
configurations over twenty recordings is 640 analyses, not 8. The workflow
prints this estimate before each probe, warns at 250 analyses, and refuses above
2 500 unless you pass `AllowExceedingMaximum` deliberately. Setting
`analysis_budget` in the configuration struct lowers that ceiling; a refusal then
names the budget, the recordings and the design rather than truncating the probe
to fit.

#### Reading the output

- **`exploration.probe.resolution.factors`** is the record of what the system
  chose: each factor's interval, the quantile it came from, how many
  observations supported it, which end is stricter, and whether the reference
  configuration's own value falls inside the probed interval. It often does not,
  and that matters: the screen then explores a neighbouring region rather than
  the neighbourhood of the configuration the support summaries use.
- **`exploration.screen.design.alias.alias_table`** says what the design can and
  cannot separate. If the design is a fraction rather than a full factorial,
  some effects are confounded. At resolution III every main effect is confounded
  with a two-factor interaction, and the leverage report will then categorise
  every factor as `interaction_suspected` and make **no leverage claim at all**.
  That is the screen declining to say something its design cannot support, not a
  failure.
- **`exploration.concordance.comparison`** is a table, not a score. There is no
  agreement percentage, and you should not compute one: the probes differ in
  design *and* in dataset, so disagreement may mean the compact screen is
  misleading, or that the subset is unrepresentative, or that an effect genuinely
  varies between recordings. The output names those possibilities and chooses
  between none of them.
- **`exploration.support_patterns.primary.patterns`** has one row per exact
  extractor set — for three extractors, each alone, each pair, and the triple —
  including the ones nothing occupies. A zero row and an absent row mean
  different things.
- An **undefined value is a finding.** Undefined correlations carry a reason
  (`constant_column`, `ill_conditioned`, `insufficient_observations`, …) rather
  than being regularized into a plausible-looking number.

#### Cautions you should not have to discover

- **Agreement among extractors is methodological evidence, not ground truth.**
  Extractors can share biases, and a detection reported by only one extractor may
  still be a real vocalization.
- **Non-agreement is not symmetric evidence.** One extractor failing to report an
  event does not establish that the event is false. An extractor-unique detection
  belongs to an extractor set; it is not an error category.
- **No threshold here is recommended, selected, or calibrated.** The reference
  configuration's own status is `illustrative_prototype`. Screening around a
  value does not calibrate it.
- **Agreement between the two probes does not remove the need for calibration.**
  They share every assumption of the matching and agreement layers and neither
  observes ground truth.
- **A one-recording screen/subset comparison cannot test subset
  representativeness.** In the real Pilot 3 acceptance run the subset was the
  whole frame, so identical response and effect behavior was expected and is
  not evidence that the richer-subset strategy is stable across recordings.
- **A fractional design aliases effects it cannot separate.** Read the alias
  table before reading a main effect.
- **The duration screen is scale-dependent.**
  `max_abs_duration_difference_s` is an absolute bound in seconds, not a ratio.
  A 0.02 s bound is a 200% tolerance for a 10 ms call and a 10% tolerance for a
  200 ms call, yet the workflow reports one leverage number for the factor.
  Interpret it as sensitivity to that absolute bound over this dataset, not as
  a uniform relative-duration tolerance.
- **The shared feature space across DeepSqueak, MUPET and USVSEG is two features
  wide** — duration and centre frequency. Minimum, maximum and bandwidth
  frequency are registered for DeepSqueak and MUPET only, so they can be reported
  *within* those extractor sets and never across extractor sets: the difference
  would be the extractor composition, not the calls. The workflow refuses such
  a request rather than flagging it.
- **USVSEG contributes no measured frequency band edges.** Its annotations show a
  time extent and the frequency markers it did measure. No band is ever
  synthesized from a centre value, a peak value, a coefficient of variation, or
  assumed call shape, so a group containing a USVSEG detection shows rectangles
  for DeepSqueak and MUPET beside full-height boundary lines and markers for
  USVSEG. That mixture is the honest picture.
- **The gallery is illustrative, not a review form.** There is no verdict column
  and no re-import path, and an extractor set with too few members yields what it
  has plus a reported shortfall rather than being padded from a neighbour.

#### Real-data acceptance boundary

One real Pilot 3 recording containing 3,324 detections traversed the complete
workflow, produced every analysis-figure family, and rendered a usable gallery
after real audio/channel metadata were registered. The full run took roughly
5.8 hours: about 3.62 hours for the 16-configuration whole-data screen and 2.09
hours for a 16-configuration subset probe over the same recording. Treat that as
a scaling warning before running the four-recording pilot dataset, not as a
default-runtime promise.

The run also established two interpretation boundaries. First, the partial-
correlation matrix was intentionally undefined with reason `ill_conditioned`:
263 complete cases exceeded the required minimum, but exact redundant metrics
made the correlation matrix unsuitable for inversion. Second, a DeepSqueak
detection whose exported low and high frequencies were identical rendered as a
literal zero-height extent. Native GUI geometry may differ from exported summary
features; VAWLUME renders the exported measurements and does not infer a taller
box.

Still open are real multi-recording stratified-subset acceptance, a meaningful
whole-versus-subset comparison on different recording sets, broader manual
gallery adjudication, runtime scaling, and paper-grade threshold or ground-truth
validation.

[`../development/35_consilience_exploration_workflow.md`](../development/35_consilience_exploration_workflow.md)
documents the stages, the designs, the coverage vocabulary, the provenance
record, and the full list of what this workflow does not do.

---

## 7. Using your own data

Moving from the example to a real project is four decisions.

### 7.1 Describe your project structure

Copy one of the three profiles in
`config/01_mapping_profiles/project_inputs/project_input_source_mapping_examples.json`
into your own JSON file and edit it. You are declaring:

- a `source.include.glob` that finds your recordings;
- a `hierarchy.levels` list of your **native** level names, each with a
  `canonical_role` and a `parent`. The role vocabulary is open: `study`,
  `experimental_group`, `subject`, `session`, and `recording` are examples used
  by the shipped profiles and fixtures, not a fixed list, and neither the
  profile validator nor the schema restricts the value;
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

**USVSEG** — one `<stem>_dat.csv` per segmentation pass. `run_key` and
`extractor_version` are required, and `extractor_version` **raises** rather than
warning if it is missing or outside the profile's scope, because USVSEG writes
no version string into any artifact and there is nothing to fall back on.

Settings evidence is **optional** here, which is the opposite of MUPET. USVSEG
writes `usvseg_prm.mat` when the application closes, holding whatever parameters
were active at that moment, and not beside the CSV it may or may not correspond
to. Requiring it would refuse ordinary correct output. Supply it through
`runSpec.settings = struct(artifact_path="…/usvseg_prm.mat")` to have it hashed
and registered — but it is recorded as application-scoped *weak* evidence and
never becomes the run's settings profile version.

The importer preserves the literal `#` header and every printed source token,
treats a header-only CSV as a valid zero-detection run, and writes any source
column the profile does not claim to `unmapped_source_values` rather than
discarding it. It creates no curation, classification, detection-score, or
frequency-bound row, because USVSEG exports none and none may be synthesized.

```matlab
usvsegSpec = struct(run_key="usvseg-run-01", extractor_version="0.9r2");
result = vawlume.ingest.usvseg(conn, usvsegCsvPath, recordingRef, usvsegSpec, ...
    RepoRoot=repoRoot);                     % plan
result = vawlume.ingest.usvseg(conn, usvsegCsvPath, recordingRef, usvsegSpec, ...
    RepoRoot=repoRoot, Apply=true);         % commit
```

See [`../development/21_usvseg_import.md`](../development/21_usvseg_import.md).

Inspect any supported export without a database first:

```matlab
export = vawlume.ingest.deepsqueakExport(artifactPath, RepoRoot=repoRoot, ...
    ExtractorVersion="3.2.1");
vawlume.source_mapping.preview(export.ir, Print=true);

usvseg = vawlume.ingest.usvsegExport(usvsegCsvPath, RepoRoot=repoRoot, ...
    ExtractorVersion="0.9r2");
vawlume.source_mapping.preview(usvseg.ir, Print=true);
```

For an extractor VAWLUME ships no profile for, the path is to author a new
`extractor_output` profile against that extractor's documented fields and
validate it through `loadProfile` and `preview`. Nothing in the ingest,
matching, consilience, agreement, or alignment layers is specific to any of the
three shipped extractors, and the agreement layer's combinatorics are in N
rather than fixed at three.

### 7.4 Register external events and align clocks

Write one session manifest per session, following
`config/06_alignment_manifests/synthetic_session_alignment_manifest.json`. It
names the participating clocks, which one is the reference, the `method`
(`offset`, `affine`, or `piecewise_affine`), and — for each stream and for the anchors — a source
table plus its mapping profile. It **points at** data and never embeds event
rows.

```matlab
bundle = vawlume.ingest.alignmentManifest(manifestPath, RepoRoot=repoRoot, ...
    SourceRoot=sessionFolder);                       % no database access
intake = vawlume.ingest.alignment(conn, manifestPath, RepoRoot=repoRoot, ...
    SourceRoot=sessionFolder, Apply=true);
% Offset or affine: fit every registered source clock.
fitted = vawlume.alignment.fit(conn, struct(run_key="my-alignment"), Apply=true);

% Piecewise affine: breakpoints belong to one source clock and are declared,
% never estimated. Fit each piecewise source independently.
fitted = vawlume.alignment.fit(conn, struct(run_key="my-alignment"), ...
    SourceTimebase="video_native", Breakpoints=[900 1800], Apply=true);
qc     = vawlume.alignment.report(conn, struct(run_key="my-alignment"));
view   = vawlume.alignment.commonTime(conn, struct(run_key="my-alignment"), ...
    VocalizationSource="detections", VocalizationRunId=1);
```

Anchors are paired by **logical anchor identity** — an anchor key you supply on
each clock — never by nearest timestamp or pulse order. An anchor contributes to
a fit only when exactly one *included* observation exists on the source clock and
exactly one on the reference clock.

`piecewise_affine` is continuous across the declared breakpoints. A breakpoint
is a claim about one source clock, so `SourceTimebase` is required whenever
`Breakpoints` is supplied. The declaration is persisted; later identical calls
reuse it, while a different breakpoint set is a different alignment identity.
VAWLUME does not search residuals for change points and never falls back to an
affine fit.

Use `vawlume.alignment.setAnchorInclusion` to withhold or restore a specific
observation, always with a `Reason`. A withheld anchor still receives a residual
it did not influence. Replicate observations likewise remain QC evidence: their
dispersion is reported, never averaged into another statistical anchor.

`qc.anchor_diagnostics` reports paired, included, withheld, and unpaired counts,
the included source-time span, and the largest gap as a fraction of that span.
These are descriptions, not acceptance tests. `qc.failures` names a failure code
and reason for every attempted source clock that could not support its declared
model. One clock can fail while the others remain `estimated`; the containing
set then remains `draft`, which tells you to inspect that clock's anchors,
declared method, and breakpoints before creating a corrected alignment identity.

Points and intervals both use stored coefficients:

```matlab
[aligned, transform] = vawlume.alignment.applyTransform(conn, runId, times);
intervals = vawlume.alignment.applyTransformInterval(conn, runId, starts, ends);
```

`transform.extrapolated` distinguishes a time outside the included-anchor span
from a supported time. Interval endpoints transform independently, so a duration
can change across a breakpoint; `segments_crossed` and `duration_change_s` make
that visible. `transform.uncertainty_s` is the largest recorded uncertainty of
the anchors determining the selected segment, expressed on the reference clock.
It is explicitly uncalibrated — not a confidence interval, standard error, or
probability — and is never combined with residual size. `NaN` means no
contributing anchor recorded uncertainty, not zero uncertainty.

Coverage and transform support remain separate. `observation_status` says the
stream was observed; `projection_status` says whether the transform was anchored
or extrapolated there. Consequently a regularized bin can be covered-empty and
extrapolated at the same time.

[`../../examples/temporal_alignment_demo.m`](../../examples/temporal_alignment_demo.m)
runs the complete synthetic Phase 3 workflow, including a piecewise tracking
read through the same `applyTransform` API used by every other consumer.

### 7.5 Declare geometry, register tracking, and record identity evidence

**Prerequisite: channel rows.** Microphone placement, bounded audio reads, and
response measurement all address an established `recording_channels` row, and
project intake establishes the recording but not its channels — how many channels
a file carries is a property of the acquisition rather than of the mapping.
Declare them explicitly:

```matlab
execute(conn, "UPDATE recordings SET channel_count=2 WHERE recording_id=1");
left = vawlume.geometry.registerRecordingChannel(conn, ...
    struct(recording_id=1), struct(channel_index=1, channel_label="left"));
right = vawlume.geometry.registerRecordingChannel(conn, ...
    struct(recording_id=1), struct(channel_index=2, channel_label="right"));
```

`channel_index` is one-based and must match the channel order in the audio file.
That is a caller assertion: nothing inspects the audio to confirm it, and the
returned `channel_count_is_caller_asserted` says so. A channel index above the
recording's declared `channel_count` is refused when the recording declares one;
a recording declaring no count is not second-guessed.

Re-registering a channel with the same label and role reuses it. Re-registering
the same index with a *different* label or role raises
`vawlume:geometry:ChannelConflict` rather than rewriting it, because placements,
measurements and response estimates already address that channel by ID and
changing what it denotes underneath them would silently re-point evidence.

`readAudioWindow` refuses a recording whose declared `channel_count` or
`sample_rate_hz` disagrees with the artifact. A recording-native video clock in
`timebases` is likewise a prerequisite for tracking registration and is
established by the alignment intake path or by hand.

Spatial facts must name the frame they are stated in. Declare one coordinate
system for the project, locate each microphone channel in it, and point the
tracking profile's `context.coordinate_system_key` at the same frame:

```matlab
vawlume.geometry.registerCoordinateSystem(conn, projectRef, struct( ...
    coordinate_system_key="arena_2d", ...
    coordinate_system_name="Courtship arena floor plane", ...
    dimensionality=2, unit="cm", ...
    origin_description="front-left inner corner of the arena floor"));
vawlume.geometry.registerChannelPlacement(conn, recordingRef, struct( ...
    channel_index=1, coordinate_system_key="arena_2d", ...
    position_x=0, position_y=18.5, placement_role="microphone"));

% Tracking is an external stream. This registers the stream, its clock, its
% frame, its traces, and its coverage - and no samples at all.
vawlume.tracking.register(conn, recordingRef, struct( ...
    artifact_path="session01_tracking.csv", profile_path=profilePath, ...
    timebase_key="video_native"), Apply=true, SourceRoot=sessionFolder);

% Relating tracking coordinates to microphone coordinates is legal only when
% both cite the same declared frame. This checks; it never transforms.
vawlume.tracking.assertGeometryCompatible(conn, streamRef, recordingRef);

% Dense samples are read window-wise from the artifact on demand.
window = vawlume.tracking.readWindow(conn, streamRef, [4 6], ...
    SourceRoot=sessionFolder);
```

`profilePath` points at your copy of
`config/01_mapping_profiles/tracking/generic_tracking_mapping_profile.json` with
each column role aimed at whatever your tracker called it, and `streamRef` is
`struct(project_key="my_project", stream_name="tracking_primary")` — the
`stream_name` defaults to the profile's `context.stream_key`.

`window.coverage_status` is `covered`, `partial`, or `uncovered`, and
`window.sample_status` distinguishes a covered-but-empty window from an
uncovered one. Zero rows in an uncovered window means nothing established that
anyone was observing — not that the tracker saw nothing.
`window.samples.pose_confidence` is the upstream localization quality and is
missing, never `1.0`, when the tracker emits none.

A native track label is a trajectory label, never an animal. Record the
relationship as interval-scoped evidence, which is what makes a crossing
representable:

```matlab
% Before the crossing: a manual assertion, with no invented number.
vawlume.tracking.registerIdentityAssociation(conn, streamRef, struct( ...
    native_track_id="track0", entity_native_id="mouse_a", ...
    start_time_native=0, end_time_native=4, ...
    assignment_state="assigned", evidence_kind="manual_assertion"));

% During it: two candidates over one interval. That is the ambiguity model.
vawlume.tracking.registerIdentityAssociation(conn, streamRef, struct( ...
    native_track_id="track0", entity_native_id="mouse_b", ...
    start_time_native=4, end_time_native=6, ...
    assignment_state="ambiguous", evidence_kind="reidentification_score", ...
    identity_value=0.52, ...
    identity_value_semantics="cosine_similarity_of_appearance_embeddings", ...
    calibration_status="uncalibrated"));

candidates = vawlume.tracking.identityCandidates(conn, streamRef, [4 6]);
```

A number must state what it means: `identity_value` without
`identity_value_semantics` is refused by both the API and a schema `CHECK`,
because a re-identification cosine similarity, an upstream likelihood, and a
calibrated posterior are different quantities. `candidates.tracks.resolution`
is `resolved`, `ambiguous`, `unresolved`, or `none`, and the last two are
deliberately distinct: an explicit unresolved statement means somebody looked
and could not tell, while `none` means nobody looked.

Optional provenance — `analysis_run_id`, `source_file_id`,
`mapping_profile_version_id`, `source_locator` — is validated, not just stored.
Each reference must belong to the same project as the stream, and a cited mapping
profile must be of kind `tracking_input_mapping` or `external_stream_mapping`. A
placement's `source_profile_version_id` must likewise be a `recording_device` or
`experimental_setup` profile from this project. Built-in profiles, which carry no
project, remain citable everywhere. Citing another experiment's file or an
extractor's output profile is refused rather than recorded as though it were
auditable.

**`external_events.entity_id` is not the same thing.** When alignment intake
reads a behaviour table, it links an event to an entity by matching your subject
column against the entity's native id — a declared attribution with no evidence
kind, semantics, or review state. That is reasonable for a scoring sheet, but it
is much weaker than an identity association, and the two should not be pooled as
if they were one kind of claim just because both end in an `entity_id`.

VAWLUME performs no image-based re-identification and no crossing detection. See
[`../development/23_spatial_geometry_schema.md`](../development/23_spatial_geometry_schema.md),
[`../development/24_tracking_input_contract.md`](../development/24_tracking_input_contract.md),
and
[`../development/25_visual_identity_association.md`](../development/25_visual_identity_association.md).

### 7.6 Register and read acoustic references

Acoustic references are optional recording-native points or intervals. A
channel-specific tone and a recording-wide noise interval can coexist:

```matlab
tone = struct(reference_key="low-tone-01", reference_type="tone", ...
    native_label="LOW_TONE", start_time_s=15, end_time_s=17, ...
    channel_index=1, frequency_min_hz=18000, frequency_max_hz=22000);
vawlume.acoustic.registerReference(conn, recordingRef, tone);

noise = struct(reference_key="noise-01", reference_type="white_noise", ...
    start_time_s=30, end_time_s=40); % no channel_index: all channels
vawlume.acoustic.registerReference(conn, recordingRef, noise);

references = vawlume.acoustic.readReferences(conn, recordingRef, ...
    ChannelIndex=1, StartTimeS=10, EndTimeS=35);

% Read only this half-open native-audio window from the linked local artifact.
window = vawlume.acoustic.readAudioWindow(conn, recordingRef, 1, 15, 17, ...
    SourceRoot=sessionFolder);

% Measure without writes, then persist under a stable analysis-run key.
preview = vawlume.acoustic.measureReferenceResponse(conn, ...
    struct(acoustic_reference_id=1), 1, SourceRoot=sessionFolder);
stored = vawlume.acoustic.measureReferenceResponse(conn, ...
    struct(acoustic_reference_id=1), 1, SourceRoot=sessionFolder, ...
    Apply=true, RunKey="session01-low-tone-ch1");

% Aggregate an explicit set of compatible measurement rows. Reference types
% remain separate; required missing types and divergence become QC evidence.
response = vawlume.acoustic.estimateChannelResponse(conn, recordingRef, ...
    rmsMeasurementIds, RequiredReferenceTypes=["tone", "white_noise"], ...
    MinReferences=2, DivergenceRelativeThreshold=0.25, ...
    Apply=true, RunKey="session01-channel-response");
audit = vawlume.acoustic.readChannelResponse(conn, ...
    struct(analysis_run_id=response.analysis_run_id));
```

`reference_type` is open text, frequency bounds are optional, and equal start/end
times are legal point-like references. A supplied `external_event_id` preserves
the source event link but never creates an alignment anchor. User event tables
reuse the normal `external_stream_mapping` path; see the shipped
`acoustic_reference_event_mapping_profile.json` and
[`../development/26_acoustic_reference_registration.md`](../development/26_acoustic_reference_registration.md).
Bounded reads and response measurements are described in
[`../development/27_audio_window_and_response_measurement.md`](../development/27_audio_window_and_response_measurement.md).
Cross-reference response/QC aggregation and its exact supporting lineage are
described in
[`../development/28_channel_response_estimates.md`](../development/28_channel_response_estimates.md).

Reference families are aggregated separately and never blended, a required
family with no evidence produces an explicit QC row rather than disappearing,
and the caller supplies exact measurement identifiers so the population of a
profile is visible in the call. The result is uncalibrated response/QC evidence
about the channels: not a gain correction, not a normalized call value, not a
preferred channel, and not a caller probability.

[`../../examples/multimodal_integration_demo.m`](../../examples/multimodal_integration_demo.m)
runs sections 7.5 and 7.6 together on a synthetic session.

### 7.7 Create an attribution run, candidates, and evidence

Caller attribution begins by fixing the run's provenance and denominator, not
by choosing a caller. Register the settings profile version and direct sources
first, then identify exactly one event set.

A run cites the settings it ran under by profile *version*, and that version is
checksum-bearing so the citation still means something later. Register the file
you actually used:

```matlab
settings = vawlume.db.registerProfileVersion(conn, ...
    struct(project_key="my_project"), struct( ...
    profile_key="session01-import-settings", ...
    profile_name="Imported attribution run settings", ...
    version_label="1.0.0", ...
    content_path="my_project/session01_attribution_settings.json"));
```

VAWLUME hashes the file and records the path; it never copies the bytes. A file
under the repository root is stored with a repository-relative `content_uri` so
the citation resolves on another machine; one outside it keeps its absolute path,
which is honest rather than portable. Re-registering the same version over
*different* bytes is refused (`vawlume:db:ProfileVersionConflict`) — decisions
and imported windows already cite the version by ID, so rewriting what it denotes
would silently re-point stored evidence. Publish a new `version_label` instead.
`profile_kind` defaults to `analysis_settings` and is checked against the
schema's own vocabulary.

This example then targets two native detections from one extraction run:

```matlab
targetSet = struct(detection_ids=[101 102]);
sources = struct(source_file_ids=44, artifact_ids=19, ...
    external_stream_ids=7);
runSpec = struct( ...
    run_key="session01-imported-caller-v1", ...
    attribution_path="imported", ...
    method="External caller system 2.0", ...
    settings_profile_version_id=settings.profile_version_id, ...
    target_set=targetSet, ...
    participating_entity_ids=[3 4 5], ...
    sources=sources);

preview = vawlume.attribution.createRun(conn, recordingRef, runSpec);
created = vawlume.attribution.createRun(conn, recordingRef, runSpec, Apply=true);

% Read-only verification against the stored event-set identity.
resolved = vawlume.attribution.resolveTargets(conn, ...
    struct(project_key="my_project", ...
           run_key="session01-imported-caller-v1"), targetSet);

% Several candidates for one target are ordinary. The external system supplies
% both numbers and their meanings; VAWLUME does not convert either column.
scoreMeaning = "External Caller 2.0 raw margin; producer=External Caller " + ...
    "2.0; range=unbounded; uncalibrated; higher is better; not a probability";
probabilityMeaning = "Exporter-labelled caller probability; producer=" + ...
    "External Caller 2.0; range=[0,1]; calibration=exporter-claimed and " + ...
    "not validated by VAWLUME";
candidates = table([3; 4; 5], [1; 2; 2], [42.7; 10.0; 10.0], ...
    repmat(scoreMeaning,3,1), [0.81; 0.12; 0.07], ...
    repmat(probabilityMeaning,3,1), ...
    VariableNames=["entity_id", "candidate_rank", "score", ...
    "score_semantics", "probability", "probability_semantics"]);
targetRef = struct(attribution_target_id=created.targets.attribution_target_id(1));
candidatePreview = vawlume.attribution.addCandidates(conn, targetRef, candidates);
candidateResult = vawlume.attribution.addCandidates(conn, targetRef, ...
    candidates, Apply=true);

% Each evidence dimension remains its own row. A source_locator is the general
% provenance fallback; source_file_id, mapping_profile_version_id, and
% alignment_run_id provide relational links where the schema has one.
evidence = table( ...
    ["temporal_alignment"; "pose_localization"; ...
     "visual_identity"; "acoustic"], ...
    ["propagated_bound"; "keypoint_confidence"; ...
     "reidentification_similarity"; "channel_rms_ratio"], ...
    [0.002; 0.73; 0.55; 0.42], ...
    ["s"; "upstream_score"; "cosine_similarity"; "ratio"], ...
    ["Largest contributing anchor uncertainty; uncalibrated; not a probability"; ...
     "Tracker-exported keypoint confidence; uncalibrated; not caller probability"; ...
     "Appearance-embedding similarity; uncalibrated; not caller probability"; ...
     "Native channel RMS ratio; uncalibrated; not caller probability"], ...
    ["alignment_run:9"; "tracking.csv#frame=120"; ...
     "reid.json#track=A"; "audio.wav#samples=1000:2000"], ...
    VariableNames=["evidence_dimension", "evidence_kind", "value_real", ...
    "value_units", "value_semantics", "source_locator"]);
evidencePreview = vawlume.attribution.addEvidence(conn, ...
    struct(attribution_candidate_id= ...
        candidateResult.candidates.attribution_candidate_id(1)), evidence);
evidenceResult = vawlume.attribution.addEvidence(conn, ...
    struct(attribution_candidate_id= ...
        candidateResult.candidates.attribution_candidate_id(1)), ...
    evidence, Apply=true);
```

Use `consensus_event_ids` instead to target one matching analysis's consensus
events. Use `agreement_group_ids` plus one of the five documented
`agreement_extent_method` values to target an arbitrary-N agreement population.
A single run cannot mix those event-set kinds or combine events from different
source extraction/analysis runs; make a separate attribution run when the
denominator changes.

Planning is the default and writes nothing. `Apply=true` atomically creates the
`analysis_runs` parent, settings-profile link, source lineage, `attribution_runs`
row, and every `attribution_targets` row. The direct source IDs and the exact
participating entity/link IDs are retained in the run's versioned provenance
snapshot. An entity not linked to the recording and an empty or cross-recording
target set are named errors, not silent omissions.

`addCandidates` and `addEvidence` also plan by default and apply whole batches
atomically. Candidate entities must belong to the run's snapshotted participant
set. A score is unconstrained but requires semantics; a probability separately
requires semantics and lies in `[0,1]`. A label without a supplied number leaves
both numeric columns absent—it is never rewritten as `1.0`. Supplied ranks are
checked, not generated: rank 1 is strongest, a higher score must have a lower
rank, and equal scores retain equal ranks. Omit rank when the source score's
ordering has another meaning.

Every evidence row has exactly one numeric or text value, explicit units and
semantics, and a source pointer or locator. `imported_composite` may preserve a
number another system already combined, provided its semantics says so; VAWLUME
does not compute that number. Evidence rows have no natural schema key, so each
successful `addEvidence(..., Apply=true)` deliberately appends new observations.


Rather than entering candidates by hand, an external attribution system's export
can be imported through a versioned mapping profile:

```matlab
% Plan first. Nothing is written, and every row it could not map is listed.
plan = vawlume.ingest.attribution(conn, ...
    struct(project_key="my-project", run_key="caller-import-1"), ...
    "data/caller_export.csv");
disp(plan.windows)
disp(plan.issues)

result = vawlume.ingest.attribution(conn, runRef, "data/caller_export.csv", ...
    Apply=true);
```

Omit `ProfilePath` to use the shipped template under
`config/01_mapping_profiles/attribution/`, or pass your own. The source file's
SHA-256, the profile version and its checksum are all recorded, so every imported
value can be traced back to the bytes it came from.

**The exporting system's numbers are stored exactly as the file carried them.**
No rescaling, no renormalization, no clamping, and no promotion of a score to a
probability because it happened to fall in `[0,1]`. Each number carries the
profile's declared semantics, saying what it meant *where it came from*.

**And the stored semantics names the system that produced the number.** Write
`{producer}` wherever you want it in your profile's `value_semantics` strings and
it is substituted from `context.exporting_system`, joined with
`exporting_system_version` when you declare one that is not `unknown`. A profile
that never uses the placeholder still gets `; producer=<name>` appended, because
the point is that a reader holding only the database can tell whose number this
was. No column records the exporting system, so without this the semantics string
would be the only place it appears.

**What is not recorded is which evidence the exporter used.** An imported score is
somebody else's combination and nothing says what went into it. You can see the
score, and separately whichever of the four dimensions this run holds; you cannot
tell which of them the exporter had already used. Take that into account before
putting an imported score beside VAWLUME evidence and reading them as
independent.

**Caller labels resolve only as the profile declares.** A label is a string in
somebody else's file. Nothing infers which entity it denotes, and nothing creates
an entity to accommodate an unrecognized one — a label naming an animal that was
never in the recording is refused by name, with every offending label listed.

**Unmappable rows are reported, not dropped.** A reversed window, a missing
caller, an undeclared label and an out-of-range probability each appear in
`plan.issues` with the row number and the reason.

**Each claimed caller becomes its own row**, in `imported_attribution_claims`, with
its label exactly as the file spelled it, the entity it resolved to, and the
exporter's score and probability beside the semantics declared for each. One window
claimed by two callers is two rows with two numbers, not one row with the labels
run together.

**A claim with no number keeps no number.** Both value columns are NULL. Nothing
substitutes `1.0` for a caller the exporter named without scoring — turning a name
into certainty is the specific thing this refuses.

**Intake relates imported windows to no VAWLUME event.** They land with their
native timing intact, on the exporting system's own clock. Because of that, an
import stores windows, claims and provenance but **no candidate rows**: a candidate
belongs to a target, an imported claim belongs to a window, and mapping one onto
the other requires a correspondence that has not been established. Correspondence
does not later promote a claim into a candidate either — which correspondence is
good enough to carry a claim onto an event is your judgement, not the importer's.
See
[`../development/32_imported_attribution_intake.md`](../development/32_imported_attribution_intake.md)
for what that means in practice.

An import applies once per run. Evidence is append-only, so a second apply would
duplicate rather than reconcile.

Imported windows arrive related to nothing. Relating them to the events VAWLUME
knows about is an explicit, separate step:

```matlab
% The exporter used its own clock: transform through a fitted alignment run.
result = vawlume.attribution.correspondWindows(conn, runRef, ...
    AlignmentRun=7, Apply=true);

% Or assert that the exporter used the recording's clock.
result = vawlume.attribution.correspondWindows(conn, runRef, ...
    SameClock=true, Apply=true);
```

**One of the two is required.** There is no default, because a correspondence
computed on incomparable clocks is a plausible number and a wrong one — the IoU
looks ordinary, the row stores cleanly, and the error surfaces as a caller
attributed to the wrong call.

The rule comes from the `correspondence` block of the mapping profile the import
registered, so a stored correspondence names a rule that still exists. It is
attribution's own and deliberately **not** the matching specification's: two
detectors disagreeing is a measurement difference, while an attribution system's
window disagreeing with a VAWLUME event may mean the two were segmenting
different things.

**Ambiguity is preserved.** A window plausibly referring to two events produces
two correspondences, both stored with their scores. Nothing chooses;
`result.ambiguous_window_count` tells you how many windows are in that state.
Windows matching nothing are counted in `windows_without_correspondence` — a
finding, not a failure.

Each correspondence records whether its IoU was computed on `native` or `aligned`
intervals, because **aligned duration is not native duration** under a piecewise
clock, and whether either endpoint fell outside the transform's anchored range.
See [`../development/33_attribution_correspondence.md`](../development/33_attribution_correspondence.md).

To read a correspondence together with the imported claim behind it:

```matlab
rows = fetch(conn, "SELECT native_window_id, source_caller_label, " + ...
    "claim_score, claim_score_semantics, target_kind, target_extent_basis, " + ...
    "iou_basis, temporal_iou " + ...
    "FROM v_attribution_window_correspondences " + ...
    "WHERE attribution_run_id = 1");
```

**`iou_basis` and `target_extent_basis` are different facts.** The first says
whether the IoU was computed on native or aligned intervals. The second says which
of the five derived extents supplied an agreement group's interval at all, and is
NULL for a detection or consensus event, which carry their own. Reading one as the
other would attribute a clock-drift artefact to a choice about group boundaries.

A NULL `claim_score` means the exporter supplied no number for that caller. It does
not mean zero.

### Comparing extent bases

An agreement group has no interval of its own — five derivations are defensible and
VAWLUME computes all of them, imposing none. To compare two, name both when the run
is created:

```matlab
run = vawlume.attribution.createRun(conn, struct(recording_id=1), struct( ...
    run_key="caller-import-1", attribution_path="imported", ...
    method="External Caller 2.0", settings_profile_version_id=1, ...
    target_set=struct(agreement_group_ids=[1 2], ...
        agreement_extent_method=["union_boundary_of_members", ...
                                 "intersection_boundary_of_members"]), ...
    participating_entity_ids=[1 2], ...
    sources=struct(source_file_ids=1)), Apply=true);
```

Each *(group, basis)* becomes its own target, so one run gives you both answers
rather than needing a second run over a re-imported copy of the same claims.
`result.extent_bases` lists the bases a run spans, and every correspondence names
its own in `target_extent_basis`.

**Do not pool results across bases.** The intervals differ, so the scores differ;
aggregating them averages numbers that were never comparable. Filter or group by
`target_extent_basis` instead.

Where members do not all overlap, the **intersection extent is empty** and that
target simply produces nothing — no zero-length interval, no fallback. Under a
multi-basis run this is ordinary rather than an error: the union target
corresponds and the intersection target does not.

Which basis is right for your question is yours to decide. VAWLUME records which
one a result rests on; it does not rank them.

### Re-running a correspondence

Applying twice is refused — `vawlume:attribution:CorrespondenceAlreadyApplied` —
because evidence is append-only and a second apply would duplicate rather than
reconcile. To correspond the same windows under different terms, create a new run.

Planning still works on an applied run, so you can preview what a different clock
declaration would have produced without writing anything.

Applying a declared policy turns those candidates into one decision per target,
and completes the run:

```matlab
% Plan first. Nothing is written, and every target's outcome is visible.
decisionPreview = vawlume.attribution.decide(conn, ...
    struct(project_key="my-project", run_key="caller-import-1"));
disp(decisionPreview.decisions)

decisionResult = vawlume.attribution.decide(conn, ...
    struct(project_key="my-project", run_key="caller-import-1"), ...
    struct(), Apply=true);
```

Omit the policy reference to use the shipped illustrative policy,
[`prototype_attribution_decision_policy.json`](../../config/08_attribution_policies/prototype_attribution_decision_policy.json),
or pass `struct(profile_path="path/to/your_policy.json")` to supply your own.
Either way the policy is registered and checksummed, and each decision names the
version that produced it.

The five statuses, and what each one claims:

| Status | Selected candidates | The claim |
|---|---|---|
| `assigned` | exactly 1 | this entity called |
| `simultaneous` | 2 or more | these entities called — a claim about the world |
| `ambiguous` | 0 | we cannot tell which — a claim about the evidence |
| `unassigned` | 0 | the policy ran and nothing was supportable |
| `excluded` | 0 | the policy could not be applied, or you declared a QC exclusion |

**Ambiguous and simultaneous are opposite claims, not degrees of the same one.**
Both leave several candidates standing. The shipped policy separates them by
asking whether every close contender is *independently* strong: if they are, it
says two animals called; if they are merely close, it says the evidence cannot
separate them.

**Clearing a threshold is never sufficient by itself.** A candidate is assigned
only when no other candidate is within the policy's `separation_margin` of it.
That is what stops a threshold quietly manufacturing confidence out of a narrow
margin.

Exclude a target yourself when you know something the numbers do not:

```matlab
vawlume.attribution.decide(conn, runRef, struct(), Apply=true, ...
    Exclusions=struct(attribution_target_id=7, ...
        reason="channel 2 clipped through this call"));
```

A reason is required. VAWLUME does not invent QC failures from the numbers.

**A decision is derived, and the layers stay separate.** Apply a different
policy to the same candidates and you get a different decision while every
candidate row stays byte-identical. Both decisions remain readable, which is how
you compare policies over one body of evidence. A second decision for one target
under the *same* policy version is refused rather than rewritten.

Once every target has a decision the attribution run becomes `complete` and its
analysis parent `completed`. Completion freezes the **evidence** — further
candidates and evidence rows are refused — but deliberately not the decision
set, because applying another policy to frozen candidates is the point.

**What a decision is not.** It is not a probability that the selected entity
called, it is not calibrated, and it is not a combination of the four evidence
dimensions: the policy reads one candidate column and no evidence row. No status
means `validated`, and the vocabulary does not contain the word.

### Reading a run back

One function returns everything the run stored, and judges none of it:

```matlab
value = vawlume.attribution.report(conn, ...
    struct(project_key="my-project", run_key="caller-import-1"));

disp(value.candidates)            % every candidate, with its semantics
disp(value.evidence)              % one row per dimension, units intact
disp(value.claim_correspondences) % the imported claim beside the event it reached
disp(value.decisions)             % each decision with the policy that bound it
disp(value.qc)                    % facts about the run
```

**Know the grain of each table before you count anything.**

| Table | One row per |
|---|---|
| `targets` | attribution target |
| `candidates` | (target, candidate entity) |
| `evidence` | stored evidence record |
| `imported_claims` | (imported window, claimed caller) |
| `correspondences` | stored correspondence |
| `claim_correspondences` | (claim, correspondence) — the joined story |
| `decisions` | (target, policy version) |
| `decision_selections` | candidate a decision selected |

`claim_correspondences` is the one to be careful with. A window carrying two
claims appears **twice** there for one correspondence, and a claim whose window
corresponds to two targets appears twice for one claim. Both are real
multiplicities and neither is collapsed — but count correspondences from
`correspondences`, not from the joined table. QC does exactly that.

**All candidates appear.** Nothing marks one as the answer. If you want the
highest-scoring one, sort by `score` yourself and know that you did.

**The four evidence dimensions stay separate**, as rows carrying their own
`evidence_dimension`, units and semantics. `qc.evidence_by_dimension` counts each
one; there is no total, no coverage fraction, and no field spanning two. An
`imported_composite` row is somebody else's already-combined number, stored with
its producer named — VAWLUME did not compute it and does not decompose it.

**Absence reads as absence.** A missing number is `NaN` and missing text is `""`,
never `0` and never a default. A candidate with no acoustic evidence has no
acoustic row rather than a zero-valued one, because a zero would claim a
measurement was made. `NaN` in `imported_claims.score` means the exporting system
supplied no number for that caller.

### What QC tells you, and what it does not

`value.qc` is counts, memberships and observed ranges:

- `targets_without_candidate` — which targets got nothing, with enough identity
  to go and look;
- `targets_with_empty_extent` — agreement groups whose declared extent is empty,
  so nothing *could* correspond to them;
- `evidence_by_dimension` — how much of each kind of evidence this run carries;
- `claims_without_score` — imported claims the source supplied no number for;
- `windows_without_correspondence` and `windows_with_multiple_correspondences`;
- `correspondence_by_basis` — count, window count, and observed IoU min, median
  and max, **per basis pair**;
- `imported_label_resolution` — which source label resolved to which entity.

**There is no quality score, no threshold, and no aggregate that reads as a
verdict.** That is deliberate. A count of scoreless claims is a fact; "this run
has poor score coverage" would be an opinion dressed as a measurement, and this
prototype has no calibrated basis for one.

QC cannot tell you whether any claimed caller called, whether the exporting
system's numbers are calibrated, whether a window that corresponded to nothing
refers to a real call VAWLUME missed, or which extent basis is right for your
question. Counts of missing evidence describe this run's **inputs**, not its
quality.

**Correspondence scores are summarized within a basis pair and never pooled.** An
IoU on aligned intervals is not the IoU of the native ones under a piecewise
clock, and an IoU against a group's union extent is not the IoU against its
intersection extent. A single run-wide distribution would average quantities that
measure different things, so none is offered.

---

## 8. Outputs and data model

### 8.1 What is written where

VAWLUME's primary data store is one SQLite file. The consilience workflow can
write reports and figures, and the CSV export workflow described in §8.5 can
write a self-describing relational package; other derived tables are returned
to MATLAB.

| Stage | Principal tables written |
|---|---|
| Schema + seed | `schema_info`, `extractors`, `extractor_versions`, `canonical_features`, `extractor_features`, `feature_mappings`, `feature_relationships`, `metric_definitions`, `config_profiles`, `config_profile_versions` |
| Project intake | `projects`, `source_files`, `entity_types`, `experimental_entities`, `entity_relationships`, `recordings`, `recording_entity_links`, `*_profile_assignments`, `ingestion_runs`, `ingestion_files` |
| Extractor import | `extraction_runs`, `extraction_run_inputs`, `extraction_run_profiles`, `artifacts`, `extraction_run_artifacts`, `detections`, `event_measurements`; `unmapped_source_values` for unclaimed source columns — currently USVSEG only, since the DeepSqueak and MUPET importers report unclaimed columns as warnings without preserving their values; and — DeepSqueak only — `curation_events`, `classification_runs`, `classification_classes`, `classification_assignments` |
| Matching | `analysis_runs`, `analysis_run_profiles`, `analysis_run_extraction_inputs`, `candidate_pairs`, `match_groups`, `match_group_members`, `consensus_events`, `consensus_event_members` |
| Consilience | `consilience_assessments`, `agreement_statistics`; `manual_reviews` and `manual_reference_events` hold independent human input |
| Arbitrary-N agreement | `analysis_runs` (a `multi_extractor_agreement` run with many-parent lineage), `agreement_groups`, `agreement_group_members`, `agreement_supporting_edges` |
| Alignment | `timebases`, `external_streams`, `external_stream_sources`, `external_stream_coverage`, `external_events`, `external_event_attributes`, `alignment_sets`, `alignment_anchors`, `alignment_anchor_observations`, `time_alignment_runs`, `alignment_segments`, `alignment_anchor_residuals` |
| Multimodal intake and response | `coordinate_systems`, `channel_placements`, `tracking_streams`, `tracking_series`, `tracking_identity_associations`, `acoustic_references`; response applies add `analysis_runs`, `analysis_run_sources`, `derived_measurements`, `channel_response_estimates`, and `channel_response_estimate_sources` |
| Attribution run and evidence | setup writes `analysis_runs`, `analysis_run_profiles`, `analysis_run_extraction_inputs` or `analysis_run_sources`, `attribution_runs`, and `attribution_targets`; candidate/evidence batches add `attribution_candidates` and `attribution_evidence`; `vawlume.ingest.attribution` adds `imported_attribution_windows` and `imported_attribution_claims`; `vawlume.attribution.correspondWindows` adds `attribution_window_correspondences`; `vawlume.attribution.decide` adds `attribution_decisions` and `attribution_decision_candidates` |

Note that `agreement_statistics` belongs to *pairwise* consilience despite its
name; the arbitrary-N layer stores no summary at all. Its counts, fractions,
patterns, and status flags are SQLite views over the member and edge rows, so
they cannot drift from the evidence they summarize.

Convenience views: `v_detection_core`, `v_recording_entity_context`,
`v_event_measurements_long`, `v_match_group_members`,
`v_agreement_group_members`, `v_agreement_supporting_edges`,
`v_agreement_extractor_pair_support`, `v_agreement_group_summary`,
`v_cross_extractor_feature_pairs`, `v_feature_relationship_endpoints`,
`v_external_events_aligned`, `v_sequence_members`, `v_agreement_group_extent`,
`v_attribution_window_correspondences`.

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
     │              │                       │
     │              │                       └── cited exactly by
     │              │                           agreement_supporting_edges
     │              │
     │              ├──< analysis_run (consilience, child) ──< consilience_assessment
     │              │                                          agreement_statistics
     │              │
     │              └──< analysis_run (arbitrary-N agreement, many parents)
     │                        └──< agreement_group ──< agreement_group_member
     │                                                    └── one native detection
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
`agreement_statistics`, `agreement_groups`, `agreement_group_members`,
`agreement_supporting_edges`, `alignment_segments`,
`alignment_anchor_residuals`, the whole `commonTime` table, and the regularized
timeline. The regularized timeline
is a **MATLAB working artifact only** — deliberately not persisted, which is why
`sequences` and `sequence_members` stay empty after a full workflow.

The database file itself is a derived artifact. What is worth version
controlling is the profiles, manifests, specifications, and scripts that
regenerate it.

### 8.5 Self-describing CSV export

CSV export is a faithful relational projection of a VAWLUME database, not an
analysis-ready denormalization. It preserves canonical table, view, and column
names and writes one CSV per selected object. CSV is the only implemented
format even though the API retains an explicit `Format` option; every other
value fails with `vawlume:export:UnsupportedFormat`.

Always call the entry point fully qualified. Do not write
`import vawlume.export.*`, because MATLAB already has functions named `export`
and `database`.

Normal export writes every base table and no views by default:

```matlab
addpath("src")
result = vawlume.export.database("data/study.sqlite", ...
    Output="exports/study_csv", Format="csv");
```

Select exact, case-sensitive table and view names with `Tables`. An explicitly
named view is exported even though `IncludeViews` defaults to `false`:

```matlab
result = vawlume.export.database("data/study.sqlite", ...
    Output="exports/detection_subset", ...
    Tables=["detections", "v_detection_core"]);
```

For the most accessible repository-supported schema reference, omit the
database and request schema-only mode. It exports no data and creates no
`csv/` directory:

```matlab
result = vawlume.export.database( ...
    Output="exports/vawlume_schema", SchemaOnly=true);
```

The runnable [`csv_export_demo`](../../examples/csv_export_demo.m) builds the
Phase 1 fixture and exercises all three calls through the public API.

#### Package contents

```text
<Output>/
|-- README.md
|-- meta/
|   |-- manifest.csv
|   |-- tables.csv
|   |-- columns.csv
|   `-- relationships.csv
`-- csv/                         normal mode only
    `-- <object_name>.csv        one per selected table or view
```

`tables.csv` always describes all supported tables and views; its `exported`,
`row_count`, and `filename` fields identify what this particular package
contains. `columns.csv` describes every column and identifies authored versus
explicitly inherited view-column descriptions. `relationships.csv` lists every
foreign key from child/source to parent/target. These three files are stable
schema projections and are not narrowed to the selected objects.

`manifest.csv` contains export-instance facts as `key,value,detail` rows. It
records the package and format versions, mode and UTC timestamp; source filename,
size and schema versions where applicable; repository and semantic-metadata
versions; supported, selected and exported object/row/file counts; the NULL,
quoting, REAL, BLOB, encoding and line-ending policies; and warnings. Schema-only
mode leaves source facts blank with `detail=not_applicable` and records zero
selected/exported objects, rows, and data files. The manifest is written last,
after the staged package has been read back and validated.

Stable meaning and instance facts have different authorities:

- [`schema/schema.sql`](../../schema/schema.sql) is the executable relational
  structure.
- [`schema/schema.json`](../../schema/schema.json) is its generated structural
  projection and is never hand-edited.
- [`schema/schema_metadata.json`](../../schema/schema_metadata.json) is the
  hand-authored semantic source for object, column, and relationship meaning.
- `meta/manifest.csv`, row counts, filenames, selection, warnings, timestamp,
  and source identity describe one export only.

[`schema/README.md`](../../schema/README.md) explains those authorities and the
metadata validation command. Export does not write a semantic-metadata snapshot
into the source SQLite database.

#### Fidelity and strict reading

SQL NULL is a bare empty field; empty text is the quoted field `""`. Every
non-NULL value is quoted using RFC 4180 rules. INTEGER values use full decimal
text, REAL values use SQLite `printf('%!.17g')`, and BLOBs use uppercase
hexadecimal. Files are UTF-8 without a BOM and use CRLF record terminators.
Embedded newlines in quoted text are preserved.

CSV preserves exact value text plus schema context, not SQLite storage types.
Naive readers may infer numeric types again, including for quoted text that
looks numeric. Force every variable to string when exact lexical values and the
NULL-versus-empty distinction matter:

```matlab
file = "exports/study_csv/csv/event_measurements.csv";
opts = detectImportOptions(file, Delimiter=",", TextType="string");
opts = setvartype(opts, "string");
rows = readtable(file, opts);
```

#### Destination, overwrite, and version behavior

`Output` is mandatory and its parent must already exist. A relative database
path or `Output`, as in the examples above, is resolved against the current
MATLAB folder; on Windows, a drive-relative path such as `C:data\study.sqlite`
or a rooted one without a drive such as `\data\study.sqlite` is refused with
`vawlume:export:AmbiguousPath`. An absent or empty destination is accepted. A non-empty destination is refused by default.
`Overwrite=true` replaces only an empty directory or a previous package that is
recognized by both `README.md` and a `meta/manifest.csv` whose package format is
`vawlume_csv_export`; it never authorizes deletion of an arbitrary directory.
Filesystem/home/repository roots, directories containing a `.git` entry,
ancestors of the VAWLUME repository, the source database's directory or a
directory containing the source, and existing files are refused. A cleanup
failure after a successful overwrite emits
`vawlume:export:PreviousPackageNotRemoved`; the new validated package is already
published, and the warning identifies the old sibling that remains.

The database is opened read-only. The exporter compares SQLite
`PRAGMA data_version` before and after reading every selected object and publishes
nothing if it changes. This detects a concurrent committed change; it is not a
read-isolation transaction, and work may be discarded only after the change is
detected.

The source database's schema version must match the repository schema version.
A mismatch fails with `vawlume:export:SchemaVersionMismatch`. If exporting an
older or otherwise different database is intentional,
`AllowSchemaVersionMismatch=true` proceeds and records the mismatch in both the
manifest and generated README; its data headers may differ from the repository
metadata. A source filename literally equal to an option name, such as `Output`,
can be parsed by MATLAB as a name-value argument; pass a normal path string with
an extension.

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
| USVSEG version missing or wrong | `:UsvsegVersionRequired`, `:UsvsegVersionIncompatible` | USVSEG writes no version string, so you must declare one in the profile's scope (`"0.9r2"`). This raises rather than warning |
| USVSEG settings rejected | `:UsvsegSettingsNotFound`, `:UsvsegSettingsInvalid` | The path does not exist, or the `.mat` holds no `prm` variable. Settings are optional — omit them rather than supplying a wrong file |
| USVSEG export carries review or class columns | `:UsvsegUnsupportedEventEvidence` | USVSEG exports no curation or classification evidence, so such a column means the artifact is not what the profile describes. It is refused rather than silently dropped |
| USVSEG event validation failed | `:UsvsegEventValidationFailed` | Duplicate `#` identifiers, or `end` before `start`, in the export |
| Workbook or CSV unreadable | `:DeepSqueakArtifactUnreadable`, `:MupetArtifactUnreadable`, `:*ArtifactUnsupported`, `:*ArtifactNotFound` | Wrong file, wrong sheet, or a format outside the profile's declared artifact class |
| IR not valid | `:MupetIRNotValid` | Fix the mapping issues the preview reported before importing |

The DeepSqueak profile's version scope prefers 3.2.x within the 3.x family; a
version outside it is reported in the adapter result rather than silently
accepted.

### Arbitrary-N agreement

Most of these mean the source set is not a coherent basis for composition. That
is deliberate: a missing supporting edge must never be confusable with a pair
that was never assessed.

| Symptom | Identifier | Cause |
|---|---|---|
| Not every extractor pair is covered | `vawlume:agreement:IncompletePairCoverage` | For N runs you must supply all `N*(N-1)/2` pairwise analyses. Run the missing comparison first |
| Two sources cover the same pair | `:DuplicateExtractorPair`, `:DuplicateSourceAnalysis` | Each unordered extractor pair must appear exactly once |
| Sources cite different specifications | `:SpecificationVersionMismatch` | Every source analysis must cite the same versioned matching specification, or its edges are not comparable |
| A source is not usable | `:SourceAnalysisNotFound`, `:SourceAnalysisAmbiguous`, `:SourceAnalysisIncomplete`, `:SourceRunTypeInvalid` | Each source must resolve to exactly one **completed** `cross_extractor_matching` analysis |
| A source describes another recording or project | `:SourceRecordingMismatch`, `:SourceProjectMismatch` | `recordingRef` is validated against every source analysis; it is not derived, because a valid source may legitimately hold no rows |
| Two runs by the same extractor | `:SameExtractorPair`, `:RepeatedExtractor` | Agreement is across extractors. Two runs of one extractor are not an extractor pair |
| Agreement policy rejected | `:SpecificationDeclaresThreshold`, `:SpecificationInvalid`, `:UnexpectedSpecificationKind` | The policy declares no threshold of any kind. A variant that adds one is refused rather than allowed to re-filter evidence the pairwise layer already settled |
| A detection carries no native event identifier | `:NativeEventIdMissing`, `:NodeSelectorAmbiguous` | Agreement uses `extraction_run_key#native_event_id` as component identity, so the identifier must be present and unique within its run. Import under a profile that maps one and declares `native_event_id_uniqueness` at error severity. Matching does not require it, because it keys on `detection_id` |
| An extractor identifier contains a pattern delimiter | `:IdentifierDelimiterConflict` | An extractor key, extractor name, or extraction run key contains `--`, `\|` or `;`. See the limitation in §10 |
| Apply refused, nothing written | `:PlanConflict` | Stored components or edges differ from the recomputed plan. Inspect the returned conflicts |
| `selectPopulation` refuses | `:AnalysisNotFound`, `:AnalysisAmbiguous`, `:AnalysisTypeInvalid`, `:AnalysisNotCompleted` | The reference must resolve to exactly one completed `multi_extractor_agreement` run; add `project_key` to disambiguate |
| Filter rejected | `:PopulationFilterInvalid`, `:PopulationFilterConflict` | Counts must be nonnegative integers, and `ExactSupportedPairCount` cannot be below `MinSupportedPairCount` |
| A singleton's `support_fraction` is `NaN` | — | Not an error. No extractor pair was possible, which is not the same as corroboration that failed |

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
| `applyTransform` raises | `vawlume:alignment:TransformRunNotFound`, `:TransformNotFitted`, `:TransformNotUsable` | The run does not exist, was never fitted, or its fit was rejected/failed. It will not return a plausible-looking number instead |
| Piecewise fit fails | `vawlume:alignment:BreakpointsRequired`, `:BreakpointsInvalid`, `:InsufficientAnchors`, `:DegenerateAnchors` | Declare source-clock breakpoints with `SourceTimebase`, and supply enough distinct included anchors to determine every segment. VAWLUME neither estimates breakpoints nor falls back to affine |
| Transformed time is flagged or raises | `vawlume:alignment:ExtrapolatedTime` | The time lies outside the included-anchor span. Inspect `transform.extrapolated`, or use `ErrorOnExtrapolation=true` to refuse it |
| Event outside declared coverage | `vawlume:alignment:EventOutsideCoverage` | Fix the declared coverage, or pass `ErrorOnOutsideCoverage=false` knowingly |
| Bin or window rejected | `vawlume:sequence:WindowInvalid`, `:WindowNotDivisible`, `:BinOriginMisaligned`, `:AggregationUnsupported` | Supported aggregations are `onset_count`, `presence`, and `any_overlap` |

### Three environment gotchas

1. **`fetch` fails on NULL text columns.** MATLAB's Database Toolbox raises
   `Unexpected NULL; (zero-based) column index: N` when a text column in the
   result set contains SQL `NULL`. Wrap nullable text columns:
   `SELECT IFNULL(native_recording_id,'') AS native_recording_id …`. The shipped
   demonstrations do this throughout.
2. **`executeSQLScript` is not used.** `vawlume.db.applySchema` executes the
   schema statement by statement, preserving `CREATE TRIGGER … END;` blocks,
   because the Database Toolbox does not support script execution for `sqlite`
   connections in this environment.
3. **A sentinel must match its column's type.** The same wrapping is needed for
   nullable *numeric* columns, and there the sentinel's type matters: the Database
   Toolbox types a fetched column from its **first row**, so an integer sentinel on
   a REAL column returns integers for every row in that column once the first row
   is the sentinel. `IFNULL(uncertainty_s,-1)` reads a stored `0.001998` back as
   `0`. Use `IFNULL(uncertainty_s,-1.0)`. This is the more dangerous half of the
   NULL trap: the text case raises, this one returns a wrong number. VAWLUME's own
   sources are held to it by `tests/unit/test_null_sentinel_convention.m`.

### Running the test suite

```matlab
addpath("src")
results = runtests("tests", IncludeSubfolders=true);
table(results)
assert(~isempty(results), "No tests discovered.");
assertSuccess(results);
assert(~any([results.Incomplete]), "Incomplete tests.");
```

Runtime is machine-dependent; observed wall times range from roughly nine to
twenty-five minutes. Passing the suite is the strongest available check that an
environment is correctly configured. For the current size of the suite, and the
rest of the repository inventory, run `repository_inventory` from
[`../../tools/`](../../tools/) rather than trusting a count quoted here.
Use the [canonical batch gate in the README](../../README.md#quick-start) for
non-interactive verification with a nonzero exit code on failure or incomplete
tests. Synthetic regression coverage does not establish scientific calibration.

---

## 10. Prototype limitations

### Implemented and tested

Schema and semantic seeding; project-input, extractor-output, external-stream,
and alignment-anchor source mapping with dry-run preview; transactional project
intake; DeepSqueak, MUPET, and USVSEG import; cross-extractor matching,
connected-component assignment, explicit unmatched groups, and topology-gated
consensus; detection- and feature-level agreement; consilience statuses;
manual-reference evaluation; threshold sensitivity; arbitrary-N extractor
agreement composed from compatible pairwise analyses with exact supporting
edges retained and exact/coarse population selection; alignment registration,
offset, affine, and declared continuous piecewise-affine transform fitting with
residual, replicate-dispersion, anchor-configuration, influence, and failure QC;
point/interval and common-time projection with explicit extrapolation and
uncalibrated uncertainty propagation; coverage-aware regularized timelines;
coordinate-system and microphone-placement
declaration with identity-based compatibility checking; external tracking
registration and bounded, coverage-aware window reads that store no sample;
interval-scoped native-track to canonical-entity identity evidence with explicit
ambiguity, unresolved statements, and declared value semantics; acoustic-
reference registration and query; bounded local-audio reads; deterministic
per-reference, per-channel response measurements with QC; per-family,
per-channel response/QC estimates with restrictive supporting lineage;
checksum-bearing registration of configuration profile versions with
repository-relative citation and conflict refusal;
plan-then-apply creation of attribution runs over explicit, single-kind target
sets with settings, direct-source, participant, and event-set provenance;
atomic multi-candidate and long-form attribution-evidence batches whose stored
numbers retain separate declared semantics; profile-driven import of external
caller-attribution tables with verbatim source values, declared-only label
resolution, and per-row issue reporting; correspondence of imported windows to
detection, consensus-event, and multi-basis agreement-group targets under an
explicitly declared clock with preserved ambiguity and extrapolation flags;
policy-governed decisions carrying the versioned policy and the threshold that
bound each one; one read-only report returning the whole run with counts,
memberships and observed ranges as its only QC; and one automated
extractor-consilience exploration carrying a dataset from candidate-metric
diagnostics through a bounded whole-dataset threshold screen, a seeded
metadata-stratified subset probe, a per-factor per-response probe comparison,
exact extractor-support-pattern characterization with registered-only feature
comparability and coverage, and a measured-geometry spectrogram gallery, to
exported tables, figures, an example index and a provenance record.

### Implemented but explicitly uncalibrated or narrow

- **CSV export is relational and fidelity-oriented, not denormalized analysis
  output.** Canonical names and selected objects are preserved; no joins,
  summaries, or presentation aliases are introduced. Only CSV is implemented.
- **CSV is not a type-preserving SQLite round trip.** It preserves exact value
  text and distinguishes NULL from empty text, but consumers must use the schema
  context and disable naive type inference where lexical identity matters.
- **Exports do not embed semantic metadata in the source database.** Packages
  project the current repository's `schema_metadata.json`; schema-only mode also
  describes that repository-supported schema rather than an experimental
  database.
- **The source-change guard detects rather than isolates concurrent writes.** A
  changed `PRAGMA data_version` prevents publication, but the exporter has no
  supported snapshot transaction and discovers the change after reading.
- Objects above 5,000,000 rows produce an advisory warning rather than a failure.
  That threshold is extrapolated from a 100,000-row measurement and is not a
  validated scale limit; export is neither chunked nor streamed.

- **Every shipped threshold is illustrative.** The matching specification carries
  `calibration_status.state = "illustrative_prototype"`. Calibration needs a
  genuine paired extractor session and an independent manually reviewed reference
  subset; neither exists yet. No configuration should be reported as optimal,
  validated, or recommended.
- **The consilience exploration selects no threshold and recommends none.** It
  reports how correspondence responds to matching assumptions in one dataset:
  several transparent measures, never a single score, and no argmax over
  configurations. Adding screenable dimensions and probing around a value does
  not calibrate that value. Agreement between its two sensitivity probes is
  informative and does not establish that manual calibration is unnecessary.
- **A fractional screening design aliases effects it cannot separate**, and at
  resolution III it can make no leverage claim about any factor at all. The alias
  table is part of the result and should be read before any main effect.
- **Only duration and centre frequency are registered as comparable across all
  three pilot extractors.** Minimum, maximum and bandwidth frequency are
  registered for DeepSqueak and MUPET only and are reportable within those
  patterns alone; peak frequency is declared by two extractors and paired by no
  relationship, so it is comparable nowhere. The shared space is thin, and that
  thinness is a property of the extractor set and its registry rather than
  something the prototype closed by harmonizing features itself.
- **The support-pattern profile is per recording.** Agreement is
  recording-scoped, so a reference run over several recordings yields one profile
  each. They are reported separately and are not pooled.
- A solved alignment fit is `estimated`, never `validated`. There is no
  calibrated acceptance threshold.
- Anchor uncertainty is preserved, propagated as a stated uncalibrated bound,
  and **not** used as a fit weight. Replicate observations contribute dispersion
  evidence but are not pooled or counted as independent anchors.
- Piecewise breakpoints are caller-declared through `fit`, never estimated, and
  a session manifest cannot yet declare them. Piecewise segments are continuous;
  clock discontinuities and nonlinear warping are not represented.
- Alignment diagnostics and residuals are reported, never judged. No automatic
  anchor exclusion, calibrated acceptance threshold, confidence interval,
  standard error, or p-value is produced.
- Coverage comes only from profile-declared constant segments; recording coverage
  is duration-derived with no multi-segment dropout model, and an event spanning
  two adjacent coverage segments is rejected.
- One source file per manifest stream declaration.
- MUPET creates no curation, classification, or detection-score rows — the
  per-syllable CSV exports none, and surviving MUPET's programmatic filtering is
  not a reviewed state.
- USVSEG creates none of those either, and no frequency minimum, maximum, or
  bandwidth. Its `usvseg_prm.mat` is application-scoped weak evidence, never the
  verified configuration of a run, and its version is always a caller assertion.
- **Agreement is not calibrated and not truth.** Every supporting edge inherits
  the matching specification's uncalibrated temporal-IoU floor. The agreement
  layer adds no threshold of its own, which bounds the problem but does not
  solve it: change that floor and the component shapes change with it. Report
  which specification produced a population.
- Arbitrary-N agreement requires a **complete** pairwise set, so N extractors
  cost `N*(N-1)/2` matching analyses. Query performance is exercised at
  synthetic-fixture scale only; no index or materialization has been justified
  against a representative workload.
- **Extractor identifiers must not contain `--`, `|` or `;`.** Pair and set
  identifiers are built by joining identifiers with delimiters, and more than one
  convention is in use: pair *keys* join extractor keys with `--` and separate
  pairs with `|`, pair *labels* join extractor names with ` -- ` and separate
  pairs with `;`, set keys join with `|`, and the MATLAB result joins the two
  sides of one pair with `|`. The schema constrains none of the underlying
  columns, and `extractor_name` is free text. Composition therefore refuses an
  agreement run whose participating extractor keys, extractor names, or
  extraction run keys contain one of those sequences
  (`vawlume:agreement:IdentifierDelimiterConflict`), because a pattern built from
  such a value would parse ambiguously and silently return the wrong population
  rather than raising. The three shipped extractors satisfy this; keep your own
  extractor keys and names free of those characters.
- A canonical feature may have several native or operational variants, so a
  measurement join must select the intended variant rather than assume one
  feature row per native detection.
- Project-intake profile-linkage validation covers the demonstrated linkage
  language; generalized profile composition and full device/setup domain
  validation are not implemented.
- `aligned_external_events` is an optional cache with no public refresh API.
- `recording_channels` rows are a caller assertion: `registerRecordingChannel`
  records that a recording has a channel, and nothing inspects the audio to
  confirm it. A channel index above a declared `channel_count` is refused; a
  recording declaring no count is not checked at all.
- Only long-form delimited-text tracking exports are supported, one source file
  per stream, and `readWindow` reads the whole artifact and filters in memory. A
  frame-basis window cannot be projected onto a reference clock.
- Channel placement has no intra-recording history, so a microphone moved
  mid-session is unrepresentable, and only audio channels are placed — cameras
  and arena landmarks are not.
- A pixel coordinate system supports no real-distance computation, and VAWLUME
  computes no distances at all.
- Identity association intervals for one track may overlap. `identityCandidates`
  still returns every overlapping claim and never chooses; `resolveIdentity`
  applies a stated precedence rule when a caller asks for one answer. That rule
  reads `assignment_state` and interval width only — not `identity_value`,
  `evidence_kind`, `review_state` or recency — and it refuses to break a tie
  rather than inventing a winner. It is a rule, not a measurement, and two
  equally specific claims in the same state remain unresolved by design.
- Identity evidence is keyed on the track label rather than on a trace row, so
  deleting a stream's `tracking_series` rows by hand leaves its associations
  behind. `PRAGMA foreign_key_check` cannot see this. No public function deletes
  a series row, so normal use does not reach it.
- Cross-table scope is enforced when rows are inserted, which is how the public
  functions write them. A direct `UPDATE` in SQL can still move a placement,
  tracking stream, or identity association across a project boundary. Change
  these tables through the API rather than by hand.
- Median is the only channel-response aggregation method, a response profile is
  scoped to one recording, and the caller supplies exact measurement identifiers
  because no discovery or selection helper exists.
- **`imported` is the only attribution path.** The backend/localization path and
  the VAWLUME-native estimator are later phases, so nothing in this prototype
  estimates a caller — it imports, relates, and decides over what somebody else
  estimated.
- The imported table must be long, one row per (window, claimed caller). A
  system emitting one row per window with several caller columns needs its own
  profile; no universal reshaper is attempted, because guessing would
  mis-associate scores with callers silently.
- **Every caller label must be declared in the profile.** Nothing infers which
  entity a label denotes and nothing creates an entity to accommodate one. An
  undeclared label is reported as a row issue; a declared label resolving outside
  the run's participating entities refuses the whole import by name.
- An import applies once per run and a correspondence applies once per run, both
  refused by name on a second apply, because attribution evidence is append-only
  and a second apply would duplicate rather than reconcile. To work under
  different terms, create a new run.
- Correspondence compares **intervals only**. No frequency, spectral, channel, or
  caller-label evidence enters the eligibility rule, and its `min_temporal_iou`
  is an illustrative value independent of the matching specification's floor.
- The clock relationship is a caller declaration — `AlignmentRun` or
  `SameClock` — and is never inferred. A correspondence computed on incomparable
  clocks would be a plausible number and a wrong one.
- **The shipped decision policy reads one candidate column and no evidence row.**
  It is not a combination of the four uncertainty dimensions, not a probability
  that the selected entity called, and not calibrated. No status means validated
  and the vocabulary does not contain the word.
- A target with no candidates is refused rather than decided, so a run whose
  every target must reach a decision needs candidates on all of them. Completion
  freezes candidates and evidence but deliberately not the decision set.
- `vawlume.attribution.report` fetches every row of every table for a run, with
  no paging, filtering or projection. It has been exercised at synthetic-fixture
  scale only; whether it is usable over a session with thousands of
  claim-correspondence rows is untested.
- **Nothing records which evidence an exporting system used.** An imported score
  is a combination somebody else already performed, and no column or profile
  field says which modalities went into it. VAWLUME's own four dimensions sit
  beside it unmerged, but you cannot tell which of them the exporter had already
  consumed — so an imported score and a VAWLUME dimension are not safely
  independent evidence.
- The exporting system's identity lives in the rendered semantics string and in
  `attribution_runs.method`, not in a column of its own. Recording it
  relationally on `imported_attribution_windows` would be cleaner and costs a
  schema version bump; it is deferred, not rejected.
- `vawlume.db.registerProfileVersion` registers a profile version and validates
  nothing about the file's contents. Each consuming layer still validates its own
  profile grammar, and the existing registrars inside the matching, agreement and
  attribution-policy paths have not been refactored onto it.

### Modeled in the schema but not populated by current workflows

`sequences`, `sequence_members`, `bouts`, and `bout_members` are implemented
schema: their tables, constraints, triggers, and the `v_sequence_members` view
exist and are valid storage for modeled sequences and bouts. What is missing is
a writer. No current workflow inserts rows into them, because the regularized
timeline they would be built from remains a MATLAB working artifact that is
deliberately not persisted (see §8.4). An empty sequence table therefore means
no workflow has written one, not that the storage is absent or that no sequence
exists in the data. `recording_epochs` is written only by the Phase 1 synthetic fixture builder
— no ingest or analysis path populates it. `metric_definitions` and
`derived_measurements` are now written, but only by the acoustic
reference-response path: the shipped metric definitions are the three acoustic
ones registered by `vawlume.db.registerBuiltinSemantics`, and no other analysis
writes a derived measurement.

Every caller-attribution table is now written by a public code path. What the
schema still represents and no code produces is a **non-imported** attribution
path: `attribution_runs.attribution_path` admits `backend` and `native_estimate`
for Phases 5 and 6, and only `imported` is reachable today.

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
- [`../design/03_multimodal_input_contract.md`](../design/03_multimodal_input_contract.md) — multimodal input design contract. Spatial geometry, tracking input/identity, and acoustic response/QC estimation are implemented without caller attribution.
- [`../design/04_caller_attribution_contract.md`](../design/04_caller_attribution_contract.md) — caller-attribution design contract: what a candidate, a decision, and an imported claim each mean, and why a detection is not an attribution claim. The whole imported path is implemented — run, target, candidate, evidence, import, correspondence, decision, and read-back; the backend and native-estimator paths are not.

### Contracts per stage

- [`../development/03_source_mapping_intermediate_representation.md`](../development/03_source_mapping_intermediate_representation.md) — the IR and dry-run contract
- [`../development/04_project_intake.md`](../development/04_project_intake.md) — intake boundary, identity, transactions, provenance
- [`../development/05_deepsqueak_import.md`](../development/05_deepsqueak_import.md) — DeepSqueak import contract and limitations
- [`../development/06_mupet_import.md`](../development/06_mupet_import.md) — MUPET import, the deliberate absences, and the shared extractor core
- [`../development/15_usvseg_export_adapter.md`](../development/15_usvseg_export_adapter.md) and [`../development/21_usvseg_import.md`](../development/21_usvseg_import.md) — the database-free USVSEG boundary, then the import contract, caller-supplied version, and optional weak settings evidence
- [`../development/22_phase1_correspondence_boundaries.md`](../development/22_phase1_correspondence_boundaries.md) — **the orientation document**: what separates native detections, pairwise candidate/match/consensus, arbitrary-N agreement groups, and future caller-attribution evidence
- [`../development/07_matching_and_consensus.md`](../development/07_matching_and_consensus.md) — the end-to-end matching → consilience workflow
- [`../development/07_matching_candidate_generation.md`](../development/07_matching_candidate_generation.md) and [`../development/08_matching_assignment_and_consensus.md`](../development/08_matching_assignment_and_consensus.md) — candidates, topology, consensus lineage
- [`../development/09_detection_and_feature_agreement.md`](../development/09_detection_and_feature_agreement.md) — agreement denominators and feature-pair discovery
- [`../development/10_consilience_manual_qc_and_sensitivity.md`](../development/10_consilience_manual_qc_and_sensitivity.md) — status rules, manual reference, sensitivity
- [`../development/16_multi_extractor_agreement_schema.md`](../development/16_multi_extractor_agreement_schema.md), [`../development/17_agreement_run_planning.md`](../development/17_agreement_run_planning.md), and [`../development/18_agreement_composition.md`](../development/18_agreement_composition.md) — arbitrary-N storage, source resolution, and composition
- [`../development/19_agreement_query_views.md`](../development/19_agreement_query_views.md) and [`../development/20_agreement_population_selection.md`](../development/20_agreement_population_selection.md) — the agreement views and the read-only selection API
- [`../development/11_temporal_alignment_schema.md`](../development/11_temporal_alignment_schema.md) — the alignment data dictionary
- [`../development/12_alignment_intake_and_registration.md`](../development/12_alignment_intake_and_registration.md) — manifest contract and transaction semantics
- [`../development/13_transform_fitting_and_alignment_qc.md`](../development/13_transform_fitting_and_alignment_qc.md) — fit models, residuals, `estimated` versus `validated`
- [`../development/14_common_time_views_and_regularized_timeline.md`](../development/14_common_time_views_and_regularized_timeline.md) — common time and bin semantics
- [`../development/23_spatial_geometry_schema.md`](../development/23_spatial_geometry_schema.md) — coordinate systems and microphone placement
- [`../development/24_tracking_input_contract.md`](../development/24_tracking_input_contract.md) — tracking registration and bounded reads
- [`../development/25_visual_identity_association.md`](../development/25_visual_identity_association.md) — track-to-entity association and ambiguity
- [`../development/26_acoustic_reference_registration.md`](../development/26_acoustic_reference_registration.md) — acoustic-reference registration, query, provenance, and mapper reuse
- [`../development/27_audio_window_and_response_measurement.md`](../development/27_audio_window_and_response_measurement.md) — bounded local-audio reads, deterministic response metrics, QC, and persistence
- [`../development/28_channel_response_estimates.md`](../development/28_channel_response_estimates.md) — per-family/channel aggregation, divergence policy, settings provenance, and exact source lineage
- [`../development/29_integrated_multimodal_demonstration.md`](../development/29_integrated_multimodal_demonstration.md) — the integrated multimodal example, its synthetic session, the ambiguous crossing, and the four uncertainty components it keeps apart
- [`../development/31_caller_attribution_schema.md`](../development/31_caller_attribution_schema.md) — the attribution data dictionary: run, target, candidate, evidence, decision
- [`../development/32_imported_attribution_intake.md`](../development/32_imported_attribution_intake.md) — the imported path, declared-only label resolution, and why intake relates a window to no event
- [`../development/33_attribution_correspondence.md`](../development/33_attribution_correspondence.md) — the declared clock, the eligibility rule, the two bases, and preserved ambiguity
- [`../development/34_integrated_caller_attribution_demonstration.md`](../development/34_integrated_caller_attribution_demonstration.md) — the integrated caller-attribution example, its two target kinds, the refusals it demonstrates, and what it cannot show
- [`../development/35_consilience_exploration_workflow.md`](../development/35_consilience_exploration_workflow.md) — the exploratory workflow: its stages, the analysis-cost arithmetic, the diagnostic battery and what an undefined partial correlation means, fractional-factorial aliasing, subset sampling, the two support-pattern vocabularies, the thin shared feature space, the USVSEG frequency-extent limitation, and its explicit non-goals

### Configuration and schema

- [`../../config/README.md`](../../config/README.md) — profile categories, authoring workflow, versioning
- [`../../schema/schema.sql`](../../schema/schema.sql) — the executable schema, its triggers, and its views
- [`../../schema/fixtures/phase1_synthetic_fixture.md`](../../schema/fixtures/phase1_synthetic_fixture.md) and [`../../schema/fixtures/phase1_acceptance_queries.sql`](../../schema/fixtures/phase1_acceptance_queries.sql) — the deterministic fixture and representative queries

### Extractor references

- [`../reference/extractors/DeepSqueak_Extractor_Design_Reference.md`](../reference/extractors/DeepSqueak_Extractor_Design_Reference.md)
- [`../reference/extractors/MUPET_Extractor_Design_Reference.md`](../reference/extractors/MUPET_Extractor_Design_Reference.md)
- [`../reference/extractors/USVSEG_Extractor_Design_Reference.md`](../reference/extractors/USVSEG_Extractor_Design_Reference.md)

### Development conventions

- [`../development/01_environment.md`](../development/01_environment.md) — MATLAB release and toolbox
- [`../development/01_repo_structure.md`](../development/01_repo_structure.md) — repository layout policy
- [`../development/02_development_workflow.md`](../development/02_development_workflow.md) — namespace, testing, and provenance conventions

### License and citation

- [`../../LICENSE`](../../LICENSE) — MIT.
- The README's **Citation** section explains how to cite the prototype. There is
  no DOI and no accompanying publication yet, so cite the repository and the
  exact commit you used.

There is currently no `CONTRIBUTING.md`; contribution guidance is deferred until
outside contributions are plausible.
