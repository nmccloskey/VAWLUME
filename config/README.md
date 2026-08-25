# VAWLUME Configuration

## Purpose

VAWLUME uses tracked configuration/profile artifacts to interpret heterogeneous external structures without hard-coding one project hierarchy or one extractor format into the relational model.

The configuration layer is part of the software contract, not merely user convenience.

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
```

Recommended locations:

```text
config/01_mapping_profiles/extractors/deepsqueak/
config/01_mapping_profiles/extractors/mupet/
```

### 3. Recording-device profile

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

### 4. Experimental-setup profile

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

### 5. Extractor settings profile

Captures the detailed settings used for one extraction context.

Unlike the built-in output mapping profile, an extractor settings profile describes **how a particular extractor run was configured**, not how VAWLUME interprets that extractor's file format.

Settings artifacts may remain external to the repository for real projects, with file identity/checksum recorded in provenance.

### 6. Cross-profile examples

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

Each profile type should eventually support stable identity and provenance fields such as:

```text
profile_id
profile_kind
profile_version
file_path_or_uri
checksum
```

Extractor-output profiles should additionally identify the supported extractor/version range.

The database can store profile identity/version/checksum while the YAML remains the detailed source representation.

## Validation

The profile loader should reject or clearly flag:

- missing required profile identity;
- unsupported profile kind;
- duplicate keys with ambiguous meaning;
- malformed regular expressions;
- required field mappings that cannot be resolved;
- unsupported transformations;
- incompatible extractor/version declarations.

A dry-run mode should surface mapping conflicts before database insertion.

## Authority rule

For shipped semantic definitions:

> The tracked mapping profile should be the authoritative detailed source; SQL seed registration should import/register that vocabulary rather than maintain a second manually synchronized copy.

This avoids semantic drift between YAML and the relational dictionaries.
