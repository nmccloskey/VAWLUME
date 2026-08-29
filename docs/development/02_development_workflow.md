# VAWLUME Development Workflow

## 1. Scope

This document defines a lightweight development workflow for the early VAWLUME prototype.

The goal is not to establish a permanent public API. It is to make the next implementation passes reproducible while preserving the project's current dependency chain:

```text
program goals
    ↓
semantic contracts / configuration
    ↓
database logic
    ↓
data containers
    ↓
program operations
    ↓
outputs
```

## 2. First repository initialization

Recommended initial setup:

1. Initialize the Git repository, preferably private during early prototyping.
2. Add the tracked repository structure.
3. Move `schema.sql` to `schema/schema.sql`.
4. Promote canonical profiles and design references out of `.dev`.
5. Create a MATLAB Project from the repository root.
6. Add only `src/` to the project path.
7. Commit MATLAB Project definition metadata.
8. Make the first commit before adding substantial implementation code.

Do not wait for a mature package structure before using source control.

## 3. MATLAB naming and namespace conventions

Use:

```text
src/+vawlume/
```

as the package namespace.

Organize code by responsibility, for example:

```text
vawlume.db.*
vawlume.source_mapping.*
vawlume.ingest.*
vawlume.matching.*
vawlume.consilience.*
vawlume.sequence.*
vawlume.alignment.*
vawlume.report.*
```

Prefer explicit namespaced function calls over adding many implementation directories directly to the MATLAB path.

Function naming can remain idiomatic MATLAB while filenames and function names match exactly.

## 4. Do not force a CLI architecture yet

The author's Python repositories often use:

```text
CLI
→ parser
→ main orchestration
→ run wrappers
→ feature modules
```

VAWLUME does not need to reproduce that structure immediately.

For the prototype, begin with callable namespaced MATLAB functions and reproducible scripts/tests.

Once a stable end-to-end workflow exists, add a thin orchestration layer if useful, for example:

```matlab
vawlume.run(...)
```

A batch/CLI wrapper can then call the same backend rather than defining a second execution path.

## 5. Configuration as contract

Treat shipped JSON profiles as versioned semantic contracts.

A mapping/profile loader should eventually expose, at minimum:

- profile kind;
- profile ID;
- profile version;
- source file;
- checksum;
- supported extractor/version where applicable;
- validation status.

Do not let arbitrary code paths interpret a profile file independently. Centralize loading and validation so configuration behavior has one source of truth.

Profile regular expressions use MATLAB `regexp` syntax. Named captures are
written as `(?<name>...)` in the MATLAB pattern and with escaped backslashes in
JSON strings, for example `(?<animal_id>\\d{3})`.

## 6. Profile responsibilities

Keep the following distinct:

```text
source mapping profile
    = how external structure is interpreted

recording-device profile
    = how audio was acquired

experimental-setup profile
    = physical/behavioral context of acquisition

extractor settings profile
    = how an extractor processed the recording

extractor-output mapping profile
    = how extractor artifacts and fields are interpreted
```

This separation should remain visible in filenames, directories, database profile kinds, and function contracts.

## 7. Semantic seed strategy

`schema.sql` should define relational grammar, not duplicate every built-in semantic record manually.

The seed layer should register built-in vocabulary from authoritative tracked sources.

Early seed targets include:

- DeepSqueak extractor identity;
- MUPET extractor identity;
- canonical levels;
- canonical features;
- extractor-native features;
- native-to-canonical mappings;
- feature relationships;
- shipped mapping profile identity/version/checksum.

A seed operation should be repeatable and either idempotent or fail transparently on conflicting definitions.

## 8. Synthetic fixture strategy

Build the first fixture to exercise awkward cases rather than only the happy path.

Minimum target:

- one study;
- multiple subjects;
- one dyad or multi-subject recording;
- two sessions;
- DeepSqueak and MUPET runs over the same recording;
- matched detections;
- unmatched detections;
- one split/merge ambiguity;
- canonical and extractor-specific features;
- device profile;
- setup profile;
- one external behavioral event stream;
- small manually reviewed subset.

Prefer fixture-building source files and scripts over a hand-edited binary SQLite database.

## 9. Test-before-importer checkpoint

Before broad importer development, write tests or acceptance queries for questions such as:

- Which detections belong to each extraction run?
- Which recordings were analyzed by both extractors?
- Which native and canonical features are available?
- Which device/setup profile is linked to each recording?
- Which entities and roles belong to a recording?
- Which candidate pairs are legal?
- Which detections form one consensus event?
- Which external events align to a recording?
- Which derived measurements came from which analysis run?

If these are awkward to express, revisit the schema or semantic contracts before building large adapters around them.

## 10. `source_mapping` implementation order

Recommended first implementation slice:

1. load JSON;
2. validate profile identity/kind/version;
3. compile MATLAB `regexp` path/filename regular expressions;
4. discover source files;
5. parse level/field values;
6. apply declared transformations;
7. preserve native values;
8. produce warnings/conflicts;
9. return a validated intermediate representation;
10. support dry-run preview.

Keep database insertion separate from source interpretation.

Conceptually:

```text
source_mapping.parse(...)
        ↓
validated intermediate representation
        ↓
source_mapping.preview(...)  [read-only dry run]
        |
        v
ingest/database layer
```

`vawlume.source_mapping.preview` returns structured report sections and a text
view derived solely from the intermediate representation. It accepts no
database connection and its readiness verdict mirrors IR validity; it does not
claim that ingestion occurred.

The implemented database boundary is `vawlume.ingest.project`. It consumes a
validated project-input IR, plans create/reuse/conflict outcomes by durable
logical identity, and optionally applies the project/entity/recording graph in
one transaction. It does not repeat discovery or parsing. See
[`04_project_intake.md`](04_project_intake.md) for the current contract.

### JSON loader runtime dependency

`vawlume.source_mapping.loadProfile` reads tracked JSON profiles with
MATLAB-native `fileread` and `jsondecode`. Configuration loading does not
require Python or PyYAML.

Missing files, file-read failures, malformed JSON, and duplicate JSON object
members are reported as `vawlume:source_mapping:ProfileLoadFailed`.

## 11. Testing conventions

Use MATLAB's unit testing framework.

Start with function-based tests unless reusable setup/teardown requirements justify class-based tests.

Suggested naming:

```text
test_schema_creation.m
test_seed_registration.m
test_mapping_profile_loading.m
test_project_input_parsing.m
```

Add integration tests when multiple layers are connected.

Each bug that changes a semantic or relational invariant should ideally produce a regression test.

The current checkpoint has completed source mapping, transactional project
intake, DeepSqueak import, and MUPET CSV/provenance planning. MUPET event
population and atomic apply are the next implementation target.
Cross-extractor matching and consensus remain unimplemented, so no comparison
between extractors is yet possible.

## 12. Generated artifacts

Generated outputs should not become accidental source-of-truth files.

Normally ignore:

- runtime SQLite databases;
- SQLite journal/WAL files;
- generated reports;
- generated figures;
- temporary extraction copies;
- MATLAB autosaves;
- compiled/codegen/build artifacts.

For poster reproducibility, retain the script/config/seed sources necessary to regenerate the outputs.

## 13. Provenance rule for implementation

When a module writes a major derived record, its contract should make it possible to trace the output to the relevant combination of:

- recording;
- experimental context;
- device/setup profile;
- extractor/run;
- extractor settings/model;
- source artifact;
- mapping profile;
- transformation/analysis run.

Do not postpone provenance until reporting.

## 14. Commit granularity

Useful early commits are architectural checkpoints, for example:

```text
Initialize MATLAB project and repository structure
Promote built-in mapping profiles
Add semantic seed registration
Add synthetic relational fixture
Add source-mapping profile loader
Add project-input path parser
Add DeepSqueak importer
Add MUPET importer
```

Avoid mixing schema redesign, importer behavior, and analysis output changes in one large commit when they can be separated.

## 15. Development sequence

Current recommended sequence:

```text
schema vocabulary stabilization
        ↓
semantic seed/registration
        ↓
synthetic fixture
        ↓
schema tests/queries
        ↓
source_mapping
        ↓
project intake
        ↓
DeepSqueak importer
        ↓
MUPET importer
        ↓
matching/consensus
        ↓
compact sequence/alignment analysis
        ↓
poster-ready integration
```

## 16. When to add more infrastructure

Add infrastructure when it protects a real workflow:

- CI: when tests are fast/stable enough to run automatically;
- build tooling: when repeated local tasks exist;
- package metadata: when installation/distribution is being tested;
- CLI/batch interface: when the orchestration contract stabilizes;
- citation metadata: before public archival/release;
- contribution guide: when outside contributions are plausible.

Prototype velocity is more valuable than ceremonial completeness.
