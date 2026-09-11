# VAWLUME Configuration

## Purpose

VAWLUME uses tracked configuration/profile artifacts to interpret heterogeneous external structures without hard-coding one project hierarchy or one extractor format into the relational model.

The configuration layer is part of the software contract, not merely user convenience.

## Canonical format

Tracked VAWLUME configuration examples are canonical JSON. Runtime
source-mapping profile loading uses MATLAB `fileread` and `jsondecode`; Python
and PyYAML are not configuration runtime dependencies.

Executable source-mapping profiles use MATLAB `regexp` syntax directly.
Named captures use `(?<name>...)`, and JSON strings must escape backslashes.
For example, a MATLAB pattern such as:

```text
^(?<animal_id>\d{3})$
```

is authored in JSON as:

```json
"^(?<animal_id>\\d{3})$"
```

A literal dot is similarly escaped as `\\.` in JSON profile strings.

## Profile categories

### 1. Project-input source mapping profile

Defines how user project structure is recovered from:

- directories;
- filenames;
- tables;
- declared literals;
- regular expressions;
- normalization mappings.

Example concepts may include:

```text
study
group
cohort
subject
dyad
session
recording
role
```

These names are not globally prescribed.

Recommended location:

```text
config/01_mapping_profiles/project_inputs/
```

### 2. Extractor-output source mapping profile

Defines how extractor-native artifacts, hierarchy, fields, units, and values map into VAWLUME concepts while preserving native semantics.

Built-in prototype targets:

```text
DeepSqueak
MUPET
USVSEG
```

Recommended locations:

```text
config/01_mapping_profiles/extractors/deepsqueak/
config/01_mapping_profiles/extractors/mupet/
config/01_mapping_profiles/extractors/usvseg/
```

All three profiles are registered by default, so their extractor identities,
native features, canonical mappings, and eligible cross-extractor feature
relationships are part of the shipped semantic vocabulary. All three are also
importable end to end: the database-free
`vawlume.ingest.usvsegExport` adapter interprets the primary USVSEG event CSV
through this profile, and `vawlume.ingest.usvseg` registers the extraction run,
detections, and measurements. See
[`docs/development/15_usvseg_export_adapter.md`](../docs/development/15_usvseg_export_adapter.md),
[`docs/development/21_usvseg_import.md`](../docs/development/21_usvseg_import.md),
and the underlying design evidence in
[`docs/reference/extractors/USVSEG_Extractor_Design_Reference.md`](../docs/reference/extractors/USVSEG_Extractor_Design_Reference.md).

USVSEG's settings capture differs deliberately from MUPET's. MUPET's
`config.csv` is genuinely run-scoped and is required to apply; USVSEG's
`usvseg_prm.mat` is written when the application closes and is therefore
optional, weak, application-scoped evidence that never becomes an extraction
run's settings profile version.

### 3. External-stream source mapping profile

Defines how one user event table becomes a logical stream on a logical timebase,
including native and normalized labels, start/end timestamps, native time units,
typed attributes, and declared observed coverage segments. The mapping is reusable;
the source table itself and the later session alignment manifest are not embedded
in the profile.

Synthetic examples:

```text
config/01_mapping_profiles/external_streams/
```

This same profile kind also maps user-supplied acoustic-reference interval
tables. The shipped `acoustic_reference_event_mapping_profile.json` demonstrates
tone, noise, user-defined labels, optional frequency bounds, and optional channel
metadata. It produces ordinary external-event IR that can feed
`vawlume.acoustic.registerReference`; there is no separate
`acoustic_reference_mapping` kind and no vendor/controller parser.

### 4. Alignment-anchor source mapping profile

Defines explicit logical anchors and their per-clock observations. Long layouts
declare anchor, stream/timebase, timestamp, role, inclusion, uncertainty, and
optional event-reference columns. Wide layouts explicitly enumerate the columns
that represent participating streams; numeric columns are never auto-detected as
clocks. Both layouts normalize to the same anchor/observation IR.

Synthetic examples:

```text
config/01_mapping_profiles/alignment_anchors/
```

This profile is reusable. A session-specific alignment manifest remains a source
artifact handled by the alignment intake layer, not a mapping-profile kind.

### 5. Recording-device profile

Describes acquisition hardware/context, for example:

- manufacturer/model/device ID;
- nominal and actual sample rate;
- bit depth;
- channels;
- gain/filtering if recoverable;
- interface;
- calibration state;
- placement/orientation where appropriate.

Recommended location:

```text
config/02_device_profiles/
```

### 6. Experimental-setup profile

Describes the physical/behavioral recording context, for example:

- chamber identity;
- sound attenuation;
- lighting;
- white noise;
- geometry;
- divider state;
- microphone position;
- video presence;
- operant components;
- controller information;
- synchronization capabilities.

Recommended location:

```text
config/03_setup_profiles/
```

### 7. Extractor settings profile

Captures the detailed settings used for one extraction context.

Unlike the built-in output mapping profile, an extractor settings profile describes **how a particular extractor run was configured**, not how VAWLUME interprets that extractor's file format.

Settings artifacts may remain external to the repository for real projects, with file identity/checksum recorded in provenance.

### 8. Matching and consilience specification

Governs one cross-extractor matching analysis: which run pair is legal, what
makes a detection pair a temporally plausible candidate, how ambiguity is
assigned rather than resolved away, when a consensus event may be derived, which
feature comparisons are eligible, what a consilience status means, and what
counts as independent manual review.

These thresholds belong here, to project/consilience configuration, and
**never** to an extractor output mapping profile or an importer constant. An
output mapping profile describes how VAWLUME reads one extractor's format; it
has no business deciding when two extractors agree.

Registered as a `config_profiles` row of kind `consilience_policy`, versioned
and checksummed in `config_profile_versions`, and linked to its analysis run
through `analysis_run_profiles`. A changed specification produces a new analysis
run rather than rewriting an existing one.

Location:

```text
config/05_matching_profiles/
```

The shipped
[`prototype_matching_consilience_spec.json`](05_matching_profiles/prototype_matching_consilience_spec.json)
carries `calibration_status.state = "illustrative_prototype"`. Every numeric
threshold in it is a deterministic demonstration value chosen to exercise
algorithm behaviour on synthetic fixtures. None is empirically calibrated, and
none should be reported as optimal or recommended.

### 9. Session alignment manifests

Location:

```text
config/06_alignment_manifests/
```

A manifest is **not a reusable semantic profile** and is deliberately not a
`config_profiles.profile_kind`. It describes one concrete session: which clocks
participate, which of them is the reference, and where each event and anchor
table plus its mapping profile lives. It points at data and never embeds event
rows.

Alignment intake registers the manifest as a checksummed `source_files` row and
links it to the alignment set, so the exact request stays reconstructable. The
reusable half — how to read an event or anchor table — remains a versioned
mapping profile under `config/01_mapping_profiles/`.

The tracked
[`synthetic_session_alignment_manifest.json`](06_alignment_manifests/synthetic_session_alignment_manifest.json)
is illustrative. Its clocks, rates, and file names are synthetic, and it is an
example of the manifest grammar rather than a template of validated settings.

### 10. Arbitrary-N extractor-agreement policies

Location:

```text
config/07_agreement_profiles/
```

An agreement policy governs how a set of pairwise matching analyses is composed
into arbitrary-N agreement over native detections: which source analyses are
composable, how components are formed, whether single-extractor detections are
retained, and how pairwise ambiguity is carried. Like a matching specification
it is registered and checksummed in `config_profile_versions`, but it is linked
under its own assignment role, `multi_extractor_agreement_spec`, because
`agreement_spec` already names the *matching* specification of a pairwise
agreement-statistics run.

The shipped
[`prototype_multi_extractor_agreement_spec.json`](07_agreement_profiles/prototype_multi_extractor_agreement_spec.json)
declares **no threshold of any kind**, and the loader refuses a variant that
adds one. The candidate universe it composes over is already bounded by the
versioned matching specification each source analysis recorded; a second
threshold here would be a competing authority that could silently re-filter
evidence the pairwise layer already decided. For the same reason the policy
cannot make feature support an admission criterion: potential support, realized
availability, and observed outcome stay separately queryable rather than
becoming a membership test.

### 11. Cross-profile examples

Examples that demonstrate how multiple profile kinds are associated can live in:

```text
config/04_examples/
```

For example, a linkage example may show how a recording is associated with a device profile and setup profile while an extraction run references settings and an output mapping profile.

## Mapping principle

A canonical mapping does not erase the source representation.

Where available, VAWLUME should retain:

- native artifact;
- native level;
- native field name;
- native value;
- native unit;
- extractor version;
- mapping-profile version;
- canonical level/field;
- normalized value/unit;
- transformation used.

## Structural equivalence is not metric identity

For example:

```text
DeepSqueak call
MUPET syllable
    → canonical vocalization event
```

is a structural mapping. It does not imply identical segmentation boundaries.

Likewise, multiple frequency-center measures can map to a broader canonical concept while remaining methodologically distinct.

Pairwise feature relationships should record actual comparability.

## Shipped versus local configuration

### Track in Git

Track reusable, versioned semantic/configuration artifacts such as:

- built-in extractor-output mapping profiles;
- reusable project-input examples;
- device/setup examples;
- profile-linkage examples;
- schemas/validators for these files.

### Keep local/untracked

Normally keep these out of Git:

- machine-specific paths;
- private study metadata;
- raw data locations;
- real subject identifiers;
- credentials;
- generated run settings containing local paths unless intentionally sanitized;
- runtime output directories.

## Versioning and provenance

Executable source-mapping profiles declare stable identity and provenance
fields:

```text
profile_id
profile_kind
profile_version
profile_schema_version
content_uri
checksum_sha256
```

`profile_version` is the authored VAWLUME mapping contract version, currently
`0.1.0` for the shipped executable source-mapping profiles.
`profile_schema_version` is the VAWLUME profile-language version. Existing
project-input and extractor-output profiles remain `0.2-draft`; external-stream
and alignment-anchor profiles use the additive `0.3-draft` language. Recording-device and
experimental-setup examples are separate profile languages and currently keep
their own `0.1-draft` schema declarations.

Extractor-output profiles additionally identify the supported extractor
version range under `extractor.version_scope`; that compatibility scope is not
the profile content version.

Profile value maps use ordered-insensitive `value_map` records with explicit
`native_value` and `canonical_value` fields. Source-specific lexical
missing-token behavior is declared in `missing_value_policy` rather than in
runtime code. For example, the current MUPET inter-syllable interval mapping
declares `NA` as an explicit missing token while preserving the raw token.

The database can store profile identity/version/checksum while the JSON remains the detailed source representation.

## Authoring workflow

Profile authoring should follow a validate-before-ingest rhythm:

1. Draft or edit the JSON profile.
2. Load it with `vawlume.source_mapping.loadProfile`.
3. Run the relevant `source_mapping` parse or table-mapping workflow.
4. Inspect `vawlume.source_mapping.preview` before any database ingest step.

The dry-run preview is the main safety mechanism for unsupported project
structures or extractor outputs. It should expose missing columns, regex
misses, ambiguous fields, value conflicts, and readiness before records are
inserted.

## AI-assisted profile authoring

Researchers may use a generative-AI assistant to help draft a profile for an
unsupported extractor or project structure, especially when they can provide
extractor documentation, source examples, and field definitions. The assistant
is not a semantic authority: generated profiles must pass VAWLUME validation
and dry-run preview, and researcher review remains required before ingest.
VAWLUME does not require an AI service at runtime.

## Validation

The profile loader should reject or clearly flag:

- missing required profile identity;
- unsupported profile kind;
- duplicate keys with ambiguous meaning;
- missing source-mapping profile content versions;
- malformed regular expressions;
- duplicate or malformed value-map entries;
- required field mappings that cannot be resolved;
- unsupported transformations;
- missing-token mappings without explicit token/blank behavior;
- incompatible extractor/version declarations.

The current source-mapping preview surfaces mapping conflicts and readiness
diagnostics without performing database insertion.

`vawlume.source_mapping.loadProfile` accepts four source-mapping kinds:
`project_input`, `extractor_output`, `external_stream_mapping`, and
`alignment_anchor_mapping`. Settings profiles and the matching and
consilience specification are not source-mapping profiles: they declare no
fields, transforms, or discovery rules, and are read directly with `fileread`
and `jsondecode`, then registered as checksum-bearing `config_profile_versions`
rows. Their identity block (`profile.id`, `profile.kind`,
`profile.profile_version`) follows the same convention so provenance reads the
same way across every profile kind.

## Current project-intake linkage

`vawlume.ingest.project` can register and associate the tracked
recording-device and experimental-setup profile examples through the linkage
document under `config/04_examples/`. The Phase 3 contract supports declared
project-default assignments, inheritance of those defaults onto recordings,
and explicit recording assignments. Its validators cover this demonstrated
linkage language; generalized profile composition and full device/setup domain
validation remain future work.

See
[`docs/development/04_project_intake.md`](../docs/development/04_project_intake.md)
for the intake, identity, transaction, and provenance contract.

## Authority rule

For shipped semantic definitions:

> The tracked mapping profile should be the authoritative detailed source; SQL seed registration should import/register that vocabulary rather than maintain a second manually synchronized copy.

This avoids semantic drift between JSON profiles and the relational dictionaries.
