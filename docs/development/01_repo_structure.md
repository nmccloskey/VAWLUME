# Repository Structure Policy

## 1. Purpose

This document defines the recommended early repository structure for VAWLUME.

It adapts the general organizational principles used in the author's Python research repositories—minimal root directory, separation of code/data/docs/tests, and tracked example configuration—to MATLAB's namespace and Project systems.

The structure is deliberately modest. VAWLUME is still a poster-oriented prototype, so directories and metadata should be added when they support a concrete contract or implementation step rather than to imitate a mature package.

## 2. Design principles

### Minimal root

Keep the root focused on top-level project metadata and entry points to the main repository domains.

Recommended root contents at this stage:

```text
.gitignore
README.md
schema/
config/
src/
tests/
examples/
docs/
.dev/           # ignored
```

A license can be added when the licensing decision is ready to be made. Packaging and citation metadata can wait until public distribution is an actual target.

### Separate canonical artifacts from scratch work

`.dev/` is useful for private working notes, discarded variants, Codex prompts, and temporary artifacts.

It should **not** contain files that the implementation treats as authoritative.

If code will load a profile, tests will validate it, or the README will describe it as a built-in contract, that artifact belongs in the tracked repository.

### Preserve reproducibility without tracking runtime data

Track:

- schema source;
- seed source;
- fixture-generation source;
- small synthetic test inputs;
- reusable mapping profiles;
- example configuration;
- tests;
- design/reference documentation.

Do not normally track:

- raw research audio;
- user-specific project paths;
- generated SQLite databases;
- generated reports/figures;
- MATLAB autosaves or build artifacts.

## 3. Recommended layout

```text
VAWLUME/
├── .gitignore
├── README.md
│
├── schema/
│   ├── schema.sql
│   ├── seeds/
│   └── fixtures/
│
├── config/
│   ├── README.md
│   ├── 01_mapping_profiles/
│   │   ├── extractors/
│   │   │   ├── deepsqueak/
│   │   │   └── mupet/
│   │   └── project_inputs/
│   ├── 02_device_profiles/
│   ├── 03_setup_profiles/
│   └── 04_examples/
│
├── src/
│   └── +vawlume/
│       ├── +db/
│       ├── +source_mapping/
│       ├── +ingest/
│       ├── +matching/
│       ├── +consilience/
│       ├── +sequence/
│       ├── +alignment/
│       └── +report/
│
├── tests/
│   ├── unit/
│   └── integration/
│
├── examples/
│
├── docs/
│   ├── design/
│   ├── development/
│   └── reference/
│       └── extractors/
│
└── .dev/
```

Do not create empty directories just to reproduce the diagram. Git does not track empty folders, and placeholder files add noise. Create each module directory when its first implementation or documentation artifact exists.

## 4. MATLAB source layout

### `src/+vawlume/`

MATLAB folders beginning with `+` define namespaces.

The VAWLUME package root should therefore be:

```text
src/+vawlume/
```

and functional areas can become nested namespaces:

```text
src/+vawlume/+source_mapping/
src/+vawlume/+ingest/
src/+vawlume/+matching/
```

Only `src/` should need to be placed on the MATLAB search path.

Do **not** add every nested source folder separately. Doing so weakens the namespace boundary and makes path behavior harder to reason about.

### Why retain `src/`

MATLAB does not require the Python-style `src/` layout, but keeping it is useful here because it:

- preserves separation between implementation and repository support files;
- makes the project path explicit;
- avoids placing many package folders at repository root;
- keeps VAWLUME structurally familiar relative to the author's other repositories.

### Public versus internal code

Start with namespaced public functions.

If implementation later needs non-public helpers, prefer one of:

```text
src/+vawlume/+internal/
```

or MATLAB `private/` folders when local visibility is specifically useful.

Do not create an elaborate internal hierarchy before real code requires it.

## 5. MATLAB Project files

Create a MATLAB Project from the repository root.

Use the Project to manage:

- `src/` on the MATLAB path;
- dependencies;
- startup/shutdown automation if needed;
- project integrity checks;
- source-control-aware project metadata.

MATLAB-generated project definition files under `resources/project/` (or the project-definition structure created by the installed MATLAB release) are part of the reproducible project configuration and should be committed.

They should **not** be added to `.gitignore`.

## 6. Schema layout

Move the current root-level `schema.sql` to:

```text
schema/schema.sql
```

Do this early, before scripts and documentation accumulate hard-coded references to the root path.

Use:

```text
schema/seeds/
```

for source files that initialize stable relational vocabulary, and:

```text
schema/fixtures/
```

for synthetic fixture definitions or fixture-building inputs.

Prefer generating a fixture database from text/source artifacts rather than committing a mutable binary SQLite database.

A useful early distinction is:

```text
schema.sql
    = database grammar

seed definitions
    = shipped semantic vocabulary

fixture definitions
    = synthetic example/test rows
```

## 7. Configuration layout

### Built-in mapping profiles

The DeepSqueak and MUPET mapping JSON files should be tracked under:

```text
config/01_mapping_profiles/extractors/
```

Suggested organization:

```text
config/01_mapping_profiles/extractors/
├── deepsqueak/
│   └── deepsqueak_output_mapping_profile.json
└── mupet/
    └── mupet_output_mapping_profile.json
```

Version-specific profiles can later use explicit filenames or version subdirectories if multiple profiles coexist.

### Project-input mappings

Move reusable project-structure examples to:

```text
config/01_mapping_profiles/project_inputs/
```

### Device and setup profiles

Use:

```text
config/02_device_profiles/
config/03_setup_profiles/
```

for reusable/example profile definitions.

### Cross-profile examples

Use:

```text
config/04_examples/
```

for examples whose purpose is to demonstrate how multiple profile categories are linked.

See `config/README.md` for profile responsibilities.

## 8. Documentation layout

### `docs/design/`

Canonical architectural and prototype planning documents.

The current revised VAWLUME prototype outline belongs here because it now defines implementation contracts and completion criteria.

### `docs/reference/extractors/`

Human-readable extractor design references.

Move:

```text
DeepSqueak_Extractor_Design_Reference.md
MUPET_Extractor_Design_Reference.md
```

here.

These documents explain the rationale behind tracked extractor mapping profiles and therefore should not remain only in ignored development notes.

### `docs/development/`

Repository conventions, development workflow, testing conventions, and future implementation notes that are meant to remain current.

### `.dev/`

Keep:

- archived outline iterations;
- temporary comparison notes;
- Codex prompts;
- planning scratch;
- experimental files not yet promoted into a repository contract.

## 9. Migration from the current tree

Recommended moves:

| Current location | Recommended tracked location |
| --- | --- |
| `schema.sql` | `schema/schema.sql` |
| `.dev/.../01_outline/01_VAWLUME_prototype_development_outline_002.md` | `docs/design/01_prototype_development_outline.md` |
| DeepSqueak output mapping JSON | `config/01_mapping_profiles/extractors/deepsqueak/` |
| MUPET output mapping JSON | `config/01_mapping_profiles/extractors/mupet/` |
| DeepSqueak design reference | `docs/reference/extractors/` |
| MUPET design reference | `docs/reference/extractors/` |
| project-input mapping examples | `config/01_mapping_profiles/project_inputs/` |
| recording-device examples | `config/02_device_profiles/` |
| experimental-setup examples | `config/03_setup_profiles/` |
| profile-linkage example | `config/04_examples/` |
| old outline revisions | remain in ignored `.dev/.../99_archive/` |

## 10. Tests

Use MATLAB's unit testing framework.

Recommended early split:

```text
tests/
├── unit/
└── integration/
```

Start with function-based tests unless a class-based fixture pattern becomes clearly useful.

Suggested first test domains:

```text
test_schema_creation.m
test_seed_registration.m
test_source_mapping_profile_loading.m
test_project_path_parsing.m
```

Integration tests can later cover:

```text
project intake → database rows
DeepSqueak import → database rows
MUPET import → database rows
matching → consensus rows
```

Keep synthetic source artifacts small and deterministic.

## 11. Examples

Use `examples/` for runnable demonstrations, not configuration vocabulary.

For example:

```text
examples/
└── poster_prototype/
```

could eventually contain a scripted, synthetic end-to-end demonstration that creates a database, runs import/matching/analysis, and emits poster-relevant outputs.

Configuration snippets that merely demonstrate profile syntax should remain under `config/`.

## 12. Files to defer

The following are useful later but not necessary to initialize the prototype:

- `CONTRIBUTING.md` — add when collaborators/public contributions make it useful;
- `CHANGELOG.md` — add when release history begins;
- `CITATION.cff` — add when the repository becomes citable/public;
- MATLAB Package Manager metadata — add if package distribution becomes a target;
- toolbox packaging files — add if `.mltbx` distribution becomes a target;
- CI workflows — add once there is a useful automated test suite;
- command-line wrappers — add once there is a stable workflow worth wrapping.

Avoid creating Python analogues merely because they exist in other repositories.

## 13. Root cleanliness rule

A simple test for new root-level files:

> Does this file describe, configure, or launch the repository as a whole?

If not, it probably belongs under `src/`, `schema/`, `config/`, `tests/`, `examples/`, or `docs/`.
