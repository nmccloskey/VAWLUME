-- VAWLUME prototype relational schema
-- Version: 0.8-draft
-- Date: 2026-09-11
-- Target: SQLite (MATLAB-centered workflow)
--
-- Design priorities:
--   * extractor-independent event representation without erasing native semantics
--   * structure-agnostic experimental hierarchy parsed by source_mapping profiles
--   * JSON profile artifacts for source mappings, extractor settings,
--     recording devices, experimental setups, and analysis policies, while
--     retaining historical YAML/YML content-format provenance support
--   * multiple extraction runs per recording with full provenance
--   * explicit artifact/model/settings lineage
--   * conservative native-to-canonical feature mapping
--   * cross-extractor candidate matching, match groups, consensus, and review
--   * arbitrary-N extractor agreement as a derived layer over exact pairwise
--     candidate edges, with multi-source analysis lineage and no stored
--     summary counts, fractions, or agreement labels
--   * sequence/hierarchy-aware derived analyses
--   * lightweight support for external behavioral/neural streams and time alignment
--   * timebase-level temporal alignment: one native audio clock per recording,
--     logical streams with explicit source provenance and observed coverage,
--     logical anchors observed on many clocks, one reference-bearing alignment
--     set per operation, pairwise transforms, and per-anchor residual evidence
--
-- Conventions:
--   * INTEGER PRIMARY KEY values are VAWLUME-generated surrogate IDs.
--   * User/extractor-native identifiers remain TEXT and are scoped explicitly.
--   * Timestamps are UTC ISO-8601 TEXT unless a source-native timestamp is retained.
--   * Detailed current profile contents remain external JSON artifacts; the
--     database stores stable IDs, versions, paths/URIs, and checksums.
--   * Native values are preserved; canonical values are additive, never destructive.

PRAGMA foreign_keys = ON;
PRAGMA recursive_triggers = ON;

BEGIN TRANSACTION;

-- ============================================================================
-- 0. Schema identity
-- ============================================================================

CREATE TABLE schema_info (
    schema_version      TEXT PRIMARY KEY,
    applied_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    description         TEXT
);

INSERT OR IGNORE INTO schema_info(schema_version, description)
VALUES ('0.8-draft', 'Alignment robustification: declared piecewise breakpoints, named transform failure reasons, declared segment-uncertainty semantics, and identity-dependent anchor evidence');

PRAGMA user_version = 8;

-- ============================================================================
-- 1. Project and configuration-profile infrastructure
-- ============================================================================

CREATE TABLE projects (
    project_id          INTEGER PRIMARY KEY,
    project_key         TEXT NOT NULL UNIQUE,
    project_name        TEXT NOT NULL,
    description         TEXT,
    created_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    archived_at_utc     TEXT
);

-- A logical profile identity. Built-in profiles may have project_id NULL.
CREATE TABLE config_profiles (
    profile_id          INTEGER PRIMARY KEY,
    project_id          INTEGER REFERENCES projects(project_id) ON DELETE CASCADE,
    profile_key         TEXT NOT NULL,
    profile_name        TEXT NOT NULL,
    profile_kind        TEXT NOT NULL CHECK (profile_kind IN (
                            'project_input',
                            'extractor_output',
                            'extractor_settings',
                            'recording_device',
                            'experimental_setup',
                            'external_stream_mapping',
                            'alignment_anchor_mapping',
                            'tracking_input_mapping',
                            'analysis_settings',
                            'consilience_policy',
                            'other'
                        )),
    is_builtin          INTEGER NOT NULL DEFAULT 0 CHECK (is_builtin IN (0,1)),
    description         TEXT,
    created_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    UNIQUE(project_id, profile_key)
);

-- Immutable/versioned profile snapshots. Detailed profile JSON is referenced,
-- not decomposed into bespoke schema columns; historical YAML/YML provenance
-- rows remain legal content-format records.
CREATE TABLE config_profile_versions (
    profile_version_id  INTEGER PRIMARY KEY,
    profile_id          INTEGER NOT NULL REFERENCES config_profiles(profile_id) ON DELETE CASCADE,
    version_label       TEXT NOT NULL,
    profile_schema_version TEXT,
    content_format      TEXT NOT NULL CHECK (content_format IN ('yaml','yml','json','toml','other')),
    content_uri         TEXT NOT NULL,
    checksum_sha256     TEXT,
    is_snapshot         INTEGER NOT NULL DEFAULT 1 CHECK (is_snapshot IN (0,1)),
    created_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    notes               TEXT,
    UNIQUE(profile_id, version_label)
);

CREATE TABLE project_profile_assignments (
    project_id          INTEGER NOT NULL REFERENCES projects(project_id) ON DELETE CASCADE,
    profile_version_id  INTEGER NOT NULL REFERENCES config_profile_versions(profile_version_id) ON DELETE RESTRICT,
    assignment_role     TEXT NOT NULL,
    is_default          INTEGER NOT NULL DEFAULT 0 CHECK (is_default IN (0,1)),
    assigned_at_utc     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    PRIMARY KEY (project_id, profile_version_id, assignment_role)
);

-- ============================================================================
-- 2. Source files and ingestion provenance
-- ============================================================================

CREATE TABLE source_files (
    source_file_id      INTEGER PRIMARY KEY,
    project_id          INTEGER NOT NULL REFERENCES projects(project_id) ON DELETE CASCADE,
    file_role           TEXT NOT NULL,
    path_or_uri         TEXT NOT NULL,
    relative_path       TEXT,
    filename            TEXT,
    file_format         TEXT,
    size_bytes          INTEGER CHECK (size_bytes IS NULL OR size_bytes >= 0),
    checksum_sha256     TEXT,
    source_modified_at  TEXT,
    discovered_at_utc   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    UNIQUE(project_id, path_or_uri)
);

CREATE TABLE ingestion_runs (
    ingestion_run_id        INTEGER PRIMARY KEY,
    project_id              INTEGER NOT NULL REFERENCES projects(project_id) ON DELETE CASCADE,
    mapping_profile_version_id INTEGER NOT NULL REFERENCES config_profile_versions(profile_version_id) ON DELETE RESTRICT,
    run_label               TEXT,
    vawlume_version         TEXT,
    source_commit           TEXT,
    status                  TEXT NOT NULL DEFAULT 'started' CHECK (status IN ('started','completed','completed_with_warnings','failed')),
    started_at_utc          TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    completed_at_utc        TEXT,
    log_uri                 TEXT,
    notes                   TEXT
);

CREATE TABLE ingestion_files (
    ingestion_run_id    INTEGER NOT NULL REFERENCES ingestion_runs(ingestion_run_id) ON DELETE CASCADE,
    source_file_id      INTEGER NOT NULL REFERENCES source_files(source_file_id) ON DELETE CASCADE,
    parse_status        TEXT NOT NULL DEFAULT 'pending' CHECK (parse_status IN ('pending','parsed','parsed_with_warnings','skipped','failed')),
    warning_count       INTEGER NOT NULL DEFAULT 0 CHECK (warning_count >= 0),
    error_count         INTEGER NOT NULL DEFAULT 0 CHECK (error_count >= 0),
    parser_message      TEXT,
    PRIMARY KEY (ingestion_run_id, source_file_id)
);

-- ============================================================================
-- 3. Structure-agnostic experimental hierarchy
-- ============================================================================

-- Projects define their own hierarchy vocabulary (study/group/animal/session,
-- cohort/dyad/session, etc.). canonical_role supplies interoperability without
-- forcing a fixed hierarchy.
CREATE TABLE entity_types (
    entity_type_id      INTEGER PRIMARY KEY,
    project_id          INTEGER NOT NULL REFERENCES projects(project_id) ON DELETE CASCADE,
    native_name         TEXT NOT NULL,
    canonical_role      TEXT,
    hierarchy_order     INTEGER,
    is_biological_unit  INTEGER NOT NULL DEFAULT 0 CHECK (is_biological_unit IN (0,1)),
    is_subject_like     INTEGER NOT NULL DEFAULT 0 CHECK (is_subject_like IN (0,1)),
    description         TEXT,
    UNIQUE(project_id, native_name)
);

CREATE TABLE experimental_entities (
    entity_id           INTEGER PRIMARY KEY,
    project_id          INTEGER NOT NULL REFERENCES projects(project_id) ON DELETE CASCADE,
    entity_type_id      INTEGER NOT NULL REFERENCES entity_types(entity_type_id) ON DELETE RESTRICT,
    native_id           TEXT NOT NULL,
    display_label       TEXT,
    ingestion_run_id    INTEGER REFERENCES ingestion_runs(ingestion_run_id) ON DELETE SET NULL,
    created_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    UNIQUE(entity_type_id, native_id)
);

-- Supports tree edges and non-tree membership/role relations (e.g. subjects in a dyad).
CREATE TABLE entity_relationships (
    entity_relationship_id INTEGER PRIMARY KEY,
    project_id          INTEGER NOT NULL REFERENCES projects(project_id) ON DELETE CASCADE,
    parent_entity_id    INTEGER NOT NULL REFERENCES experimental_entities(entity_id) ON DELETE CASCADE,
    child_entity_id     INTEGER NOT NULL REFERENCES experimental_entities(entity_id) ON DELETE CASCADE,
    relationship_type   TEXT NOT NULL DEFAULT 'contains',
    role_label          TEXT,
    valid_from_utc      TEXT,
    valid_to_utc        TEXT,
    ingestion_run_id    INTEGER REFERENCES ingestion_runs(ingestion_run_id) ON DELETE SET NULL,
    source_file_id      INTEGER REFERENCES source_files(source_file_id) ON DELETE SET NULL,
    source_locator      TEXT,
    mapping_rule_key    TEXT,
    CHECK (parent_entity_id <> child_entity_id),
    UNIQUE(parent_entity_id, child_entity_id, relationship_type, role_label)
);

-- Queryable arbitrary metadata parsed from user project semantics.
CREATE TABLE entity_attributes (
    entity_attribute_id INTEGER PRIMARY KEY,
    entity_id           INTEGER NOT NULL REFERENCES experimental_entities(entity_id) ON DELETE CASCADE,
    attribute_name      TEXT NOT NULL,
    value_type          TEXT NOT NULL CHECK (value_type IN ('text','real','integer','boolean','json','missing')),
    value_text          TEXT,
    value_real          REAL,
    value_integer       INTEGER,
    value_boolean       INTEGER CHECK (value_boolean IS NULL OR value_boolean IN (0,1)),
    value_json          TEXT,
    unit                TEXT,
    ingestion_run_id    INTEGER REFERENCES ingestion_runs(ingestion_run_id) ON DELETE SET NULL,
    source_file_id      INTEGER REFERENCES source_files(source_file_id) ON DELETE SET NULL,
    source_locator      TEXT,
    mapping_rule_key    TEXT,
    CHECK (
      (value_type = 'missing' AND value_text IS NULL AND value_real IS NULL AND value_integer IS NULL AND value_boolean IS NULL AND value_json IS NULL)
      OR
      (value_type <> 'missing' AND
       (value_text IS NOT NULL) + (value_real IS NOT NULL) + (value_integer IS NOT NULL) + (value_boolean IS NOT NULL) + (value_json IS NOT NULL) = 1)
    )
);

-- ============================================================================
-- 4. Recordings and acquisition context
-- ============================================================================

CREATE TABLE recordings (
    recording_id        INTEGER PRIMARY KEY,
    project_id          INTEGER NOT NULL REFERENCES projects(project_id) ON DELETE CASCADE,
    source_file_id      INTEGER NOT NULL UNIQUE REFERENCES source_files(source_file_id) ON DELETE RESTRICT,
    native_recording_id TEXT,
    checksum_sha256     TEXT,
    sample_rate_hz      REAL CHECK (sample_rate_hz IS NULL OR sample_rate_hz > 0),
    bit_depth           INTEGER CHECK (bit_depth IS NULL OR bit_depth > 0),
    channel_count       INTEGER CHECK (channel_count IS NULL OR channel_count > 0),
    duration_s          REAL CHECK (duration_s IS NULL OR duration_s >= 0),
    recorded_start_utc  TEXT,
    created_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    notes               TEXT
);

CREATE TABLE recording_channels (
    recording_channel_id INTEGER PRIMARY KEY,
    recording_id        INTEGER NOT NULL REFERENCES recordings(recording_id) ON DELETE CASCADE,
    channel_index       INTEGER NOT NULL CHECK (channel_index >= 1),
    channel_label       TEXT,
    channel_role        TEXT,
    UNIQUE(recording_id, channel_index)
);

-- Many experimental entities can participate in one recording; role_label handles
-- male/female, resident/intruder, observer/performer, etc. Optional time bounds allow
-- changing participation within a recording.
CREATE TABLE recording_entity_links (
    recording_entity_link_id INTEGER PRIMARY KEY,
    recording_id        INTEGER NOT NULL REFERENCES recordings(recording_id) ON DELETE CASCADE,
    entity_id           INTEGER NOT NULL REFERENCES experimental_entities(entity_id) ON DELETE CASCADE,
    link_type           TEXT NOT NULL DEFAULT 'participant',
    role_label          TEXT,
    start_time_s        REAL CHECK (start_time_s IS NULL OR start_time_s >= 0),
    end_time_s          REAL CHECK (end_time_s IS NULL OR end_time_s >= 0),
    ingestion_run_id    INTEGER REFERENCES ingestion_runs(ingestion_run_id) ON DELETE SET NULL,
    CHECK (end_time_s IS NULL OR start_time_s IS NULL OR end_time_s >= start_time_s),
    UNIQUE(recording_id, entity_id, link_type, role_label, start_time_s)
);

CREATE TABLE recording_attributes (
    recording_attribute_id INTEGER PRIMARY KEY,
    recording_id        INTEGER NOT NULL REFERENCES recordings(recording_id) ON DELETE CASCADE,
    attribute_name      TEXT NOT NULL,
    value_type          TEXT NOT NULL CHECK (value_type IN ('text','real','integer','boolean','json','missing')),
    value_text          TEXT,
    value_real          REAL,
    value_integer       INTEGER,
    value_boolean       INTEGER CHECK (value_boolean IS NULL OR value_boolean IN (0,1)),
    value_json          TEXT,
    unit                TEXT,
    ingestion_run_id    INTEGER REFERENCES ingestion_runs(ingestion_run_id) ON DELETE SET NULL,
    source_file_id      INTEGER REFERENCES source_files(source_file_id) ON DELETE SET NULL,
    source_locator      TEXT,
    mapping_rule_key    TEXT,
    CHECK (
      (value_type = 'missing' AND value_text IS NULL AND value_real IS NULL AND value_integer IS NULL AND value_boolean IS NULL AND value_json IS NULL)
      OR
      (value_type <> 'missing' AND
       (value_text IS NOT NULL) + (value_real IS NOT NULL) + (value_integer IS NOT NULL) + (value_boolean IS NOT NULL) + (value_json IS NOT NULL) = 1)
    )
);

CREATE TABLE entity_profile_assignments (
    entity_id           INTEGER NOT NULL REFERENCES experimental_entities(entity_id) ON DELETE CASCADE,
    profile_version_id  INTEGER NOT NULL REFERENCES config_profile_versions(profile_version_id) ON DELETE RESTRICT,
    assignment_role     TEXT NOT NULL,
    assigned_at_utc     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    PRIMARY KEY(entity_id, profile_version_id, assignment_role)
);

CREATE TABLE recording_profile_assignments (
    recording_id        INTEGER NOT NULL REFERENCES recordings(recording_id) ON DELETE CASCADE,
    profile_version_id  INTEGER NOT NULL REFERENCES config_profile_versions(profile_version_id) ON DELETE RESTRICT,
    assignment_role     TEXT NOT NULL,
    inheritance_source  TEXT NOT NULL DEFAULT 'direct' CHECK (inheritance_source IN ('direct','project_default','entity','session_like_entity','other')),
    assigned_at_utc     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    PRIMARY KEY(recording_id, profile_version_id, assignment_role)
);

-- Optional named epochs/behavioral windows inside recordings.
CREATE TABLE recording_epochs (
    epoch_id            INTEGER PRIMARY KEY,
    recording_id        INTEGER NOT NULL REFERENCES recordings(recording_id) ON DELETE CASCADE,
    parent_epoch_id     INTEGER REFERENCES recording_epochs(epoch_id) ON DELETE CASCADE,
    epoch_name          TEXT NOT NULL,
    epoch_type          TEXT,
    start_time_s        REAL NOT NULL CHECK (start_time_s >= 0),
    end_time_s          REAL NOT NULL CHECK (end_time_s >= start_time_s),
    source              TEXT NOT NULL DEFAULT 'manual_or_imported',
    source_file_id      INTEGER REFERENCES source_files(source_file_id) ON DELETE SET NULL,
    notes               TEXT,
    UNIQUE(recording_id, epoch_name, start_time_s, end_time_s)
);

-- A declared spatial frame. Project-scoped shared reference data: microphone
-- placement cites it here, and canonicalized tracking streams cite the same
-- table, so both sides of a spatial comparison name one frame.
--
-- Compatibility is IDENTITY of coordinate_system_id, never structural
-- similarity. Two systems that both declare 2 dimensions and 'cm' are not
-- interchangeable: they may have different origins, different axis directions,
-- or describe different arenas. Treating matching metadata as licence to compare
-- coordinates is how a confident, wrong distance gets computed.
--
-- VAWLUME performs no transformation between spatial frames - no rotation,
-- translation, rescaling, or projection. origin_description and
-- orientation_description are human-readable provenance, never machine-applied.
-- The asymmetry with the temporal layer, which does fit and apply clock
-- transforms, is deliberate: clock transforms are identifiable from explicit
-- anchor observations users supply, and no equivalent spatial evidence exists.
CREATE TABLE coordinate_systems (
    coordinate_system_id INTEGER PRIMARY KEY,
    project_id          INTEGER NOT NULL REFERENCES projects(project_id) ON DELETE CASCADE,
    coordinate_system_key TEXT NOT NULL,
    coordinate_system_name TEXT NOT NULL,
    -- 2D is the working case; 3D is representable and never required.
    dimensionality      INTEGER NOT NULL CHECK (dimensionality IN (2,3)),
    -- A property of the frame, so units cannot disagree between two compatible
    -- facts. Free text: 'cm', 'mm', 'm', 'px'. Pixel frames are permitted and
    -- support no real-distance computation; a later phase needing metric
    -- distance must require a metric unit or an explicit provenance-bearing
    -- scale, and must never treat pixels as centimetres.
    unit                TEXT NOT NULL,
    origin_description  TEXT,
    orientation_description TEXT,
    notes               TEXT,
    UNIQUE(project_id, coordinate_system_key)
);

-- Where one recording channel's microphone was, in one declared frame.
--
-- Placement attaches to the channel because a microphone reaches VAWLUME as a
-- recording channel. A channel belongs to exactly one recording, so a placement
-- row is session-specific by construction and cannot claim a position that
-- outlives the session it was measured in. A four-microphone interface produces
-- four channels with four placements; those are four different microphones in
-- four different places, not duplication.
--
-- Reusable recording-device and experimental-setup profiles are placement
-- PROVENANCE, not placement authority. Their geometry blocks may be applied to
-- many sessions, so neither can answer "where was this microphone during this
-- recording". A registration call may read a setup profile and write these rows,
-- citing the profile version in source_profile_version_id; the database then
-- holds exactly one answer per channel. A two-level model (reusable geometry
-- plus per-recording override) was rejected for creating two competing answers
-- to one question - the failure the alignment layer corrected when it removed
-- the direct source columns from external_streams.
--
-- One placement per channel: a microphone moved mid-recording is not
-- representable and needs an explicit time-bounded model, not a quietly added
-- nullable interval.
CREATE TABLE channel_placements (
    channel_placement_id INTEGER PRIMARY KEY,
    recording_channel_id INTEGER NOT NULL UNIQUE REFERENCES recording_channels(recording_channel_id) ON DELETE CASCADE,
    coordinate_system_id INTEGER NOT NULL REFERENCES coordinate_systems(coordinate_system_id) ON DELETE RESTRICT,
    position_x          REAL NOT NULL,
    position_y          REAL NOT NULL,
    -- Permitted only under a 3-dimensional frame (see trigger below), and
    -- optional even then: an unknown height is missing data, not an error.
    position_z          REAL,
    placement_role      TEXT,
    orientation_description TEXT,
    source_profile_version_id INTEGER REFERENCES config_profile_versions(profile_version_id) ON DELETE SET NULL,
    notes               TEXT
);

-- ============================================================================
-- 5. Extractor identity, artifacts, and extraction runs
-- ============================================================================

CREATE TABLE extractors (
    extractor_id        INTEGER PRIMARY KEY,
    extractor_key       TEXT NOT NULL UNIQUE,
    extractor_name      TEXT NOT NULL,
    description         TEXT,
    source_repository   TEXT
);

CREATE TABLE extractor_versions (
    extractor_version_id INTEGER PRIMARY KEY,
    extractor_id        INTEGER NOT NULL REFERENCES extractors(extractor_id) ON DELETE CASCADE,
    version_label       TEXT NOT NULL,
    source_commit_or_tag TEXT,
    build_identifier    TEXT,
    implementation_language TEXT,
    notes               TEXT,
    UNIQUE(extractor_id, version_label, source_commit_or_tag)
);

-- Registration identity is extractor + version label + normalized source commit/tag.
-- build_identifier and the descriptive fields are conflict-checked values: an
-- identical registration is accepted, while differing values for the same identity
-- must be rejected rather than silently creating another semantic version row.

-- Generic immutable/referential artifacts: native output files, detector models,
-- classifier models, exports, settings copies, transformed audio, etc.
CREATE TABLE artifacts (
    artifact_id         INTEGER PRIMARY KEY,
    project_id          INTEGER NOT NULL REFERENCES projects(project_id) ON DELETE CASCADE,
    source_file_id      INTEGER REFERENCES source_files(source_file_id) ON DELETE SET NULL,
    parent_artifact_id  INTEGER REFERENCES artifacts(artifact_id) ON DELETE SET NULL,
    artifact_type       TEXT NOT NULL,
    native_artifact_type TEXT,
    path_or_uri         TEXT NOT NULL,
    file_format         TEXT,
    checksum_sha256     TEXT,
    is_native           INTEGER NOT NULL DEFAULT 0 CHECK (is_native IN (0,1)),
    created_at_source   TEXT,
    imported_at_utc     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    metadata_json       TEXT,
    UNIQUE(project_id, path_or_uri)
);

CREATE TABLE extraction_runs (
    extraction_run_id   INTEGER PRIMARY KEY,
    project_id          INTEGER NOT NULL REFERENCES projects(project_id) ON DELETE CASCADE,
    extractor_version_id INTEGER NOT NULL REFERENCES extractor_versions(extractor_version_id) ON DELETE RESTRICT,
    run_key             TEXT NOT NULL,
    run_label           TEXT,
    output_mapping_profile_version_id INTEGER REFERENCES config_profile_versions(profile_version_id) ON DELETE RESTRICT,
    settings_profile_version_id INTEGER REFERENCES config_profile_versions(profile_version_id) ON DELETE RESTRICT,
    started_at_utc      TEXT,
    completed_at_utc    TEXT,
    imported_at_utc     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    status              TEXT NOT NULL DEFAULT 'imported' CHECK (status IN ('planned','running','completed','imported','failed')),
    notes               TEXT,
    UNIQUE(project_id, run_key)
);

CREATE TABLE extraction_run_inputs (
    extraction_run_id   INTEGER NOT NULL REFERENCES extraction_runs(extraction_run_id) ON DELETE CASCADE,
    recording_id        INTEGER NOT NULL REFERENCES recordings(recording_id) ON DELETE CASCADE,
    recording_channel_id INTEGER REFERENCES recording_channels(recording_channel_id) ON DELETE SET NULL,
    input_role          TEXT NOT NULL DEFAULT 'source_audio',
    PRIMARY KEY(extraction_run_id, recording_id, input_role, recording_channel_id)
);

-- Device/setup profiles are normally inherited from the recording but are snapshotted
-- here when materially relevant to the extraction run. Direct overrides remain explicit.
CREATE TABLE extraction_run_profiles (
    extraction_run_id   INTEGER NOT NULL REFERENCES extraction_runs(extraction_run_id) ON DELETE CASCADE,
    profile_version_id  INTEGER NOT NULL REFERENCES config_profile_versions(profile_version_id) ON DELETE RESTRICT,
    assignment_role     TEXT NOT NULL,
    inheritance_source  TEXT NOT NULL DEFAULT 'direct' CHECK (inheritance_source IN ('direct','recording','project_default','entity','other')),
    PRIMARY KEY(extraction_run_id, profile_version_id, assignment_role)
);

CREATE TABLE extraction_run_artifacts (
    extraction_run_id   INTEGER NOT NULL REFERENCES extraction_runs(extraction_run_id) ON DELETE CASCADE,
    artifact_id         INTEGER NOT NULL REFERENCES artifacts(artifact_id) ON DELETE CASCADE,
    artifact_role       TEXT NOT NULL,
    PRIMARY KEY(extraction_run_id, artifact_id, artifact_role)
);

-- Preserves extractor-native higher-order hierarchy such as MUPET workspace/data set,
-- refined event sets, and other source-specific objects without confusing them with
-- biological hierarchy. Classification runs/classes are additionally normalized below.
CREATE TABLE extractor_objects (
    extractor_object_id INTEGER PRIMARY KEY,
    extraction_run_id   INTEGER NOT NULL REFERENCES extraction_runs(extraction_run_id) ON DELETE CASCADE,
    parent_object_id    INTEGER REFERENCES extractor_objects(extractor_object_id) ON DELETE CASCADE,
    source_artifact_id  INTEGER REFERENCES artifacts(artifact_id) ON DELETE SET NULL,
    native_level        TEXT NOT NULL,
    canonical_level     TEXT,
    canonical_subtype   TEXT,
    equivalence_class   TEXT,
    native_id           TEXT,
    native_label        TEXT,
    mapping_strength    TEXT,
    lineage_note        TEXT,
    UNIQUE(extraction_run_id, native_level, native_id, parent_object_id)
);

CREATE TABLE extractor_object_recordings (
    extractor_object_id INTEGER NOT NULL REFERENCES extractor_objects(extractor_object_id) ON DELETE CASCADE,
    recording_id        INTEGER NOT NULL REFERENCES recordings(recording_id) ON DELETE CASCADE,
    membership_role     TEXT NOT NULL DEFAULT 'member',
    PRIMARY KEY(extractor_object_id, recording_id, membership_role)
);

-- ============================================================================
-- 6. Feature semantics and source-mapping layer
-- ============================================================================

CREATE TABLE canonical_features (
    canonical_feature_id INTEGER PRIMARY KEY,
    canonical_name      TEXT NOT NULL UNIQUE,
    feature_domain      TEXT,
    value_type          TEXT NOT NULL DEFAULT 'real' CHECK (value_type IN ('real','integer','text','boolean','json')),
    canonical_unit      TEXT,
    definition          TEXT,
    is_vawlume_derived  INTEGER NOT NULL DEFAULT 0 CHECK (is_vawlume_derived IN (0,1))
);

CREATE TABLE extractor_features (
    extractor_feature_id INTEGER PRIMARY KEY,
    extractor_version_id INTEGER NOT NULL REFERENCES extractor_versions(extractor_version_id) ON DELETE CASCADE,
    native_name         TEXT NOT NULL,
    native_unit         TEXT,
    value_type          TEXT NOT NULL DEFAULT 'real' CHECK (value_type IN ('real','integer','text','boolean','json')),
    native_definition   TEXT,
    source_artifact_type TEXT,
    derivation_stage    TEXT,
    measurement_method  TEXT,
    operational_variant TEXT,
    equivalence_class   TEXT,
    source_reference    TEXT,
    notes               TEXT
);

-- The Phase 1 registration identity for a native feature is:
-- extractor version + native name + source artifact type + derivation stage +
-- operational variant. source_artifact_type stores the mapping profile's stable
-- artifact_key (for example, event_stats_excel or per_syllable_csv). Registration
-- normalizes absent optional identity components to NULL and rejects a conflicting
-- definition for an existing identity.

CREATE TABLE feature_mappings (
    feature_mapping_id  INTEGER PRIMARY KEY,
    extractor_feature_id INTEGER NOT NULL REFERENCES extractor_features(extractor_feature_id) ON DELETE CASCADE,
    canonical_feature_id INTEGER NOT NULL REFERENCES canonical_features(canonical_feature_id) ON DELETE CASCADE,
    mapping_profile_version_id INTEGER REFERENCES config_profile_versions(profile_version_id) ON DELETE SET NULL,
    mapping_type        TEXT NOT NULL CHECK (mapping_type IN (
                            'transform_equivalent',
                            'conceptually_equivalent',
                            'comparable',
                            'related',
                            'noncomparable'
                        )),
    transform_key       TEXT,
    preserve_raw        INTEGER NOT NULL DEFAULT 1 CHECK (preserve_raw IN (0,1)),
    notes               TEXT,
    UNIQUE(extractor_feature_id, canonical_feature_id, mapping_profile_version_id)
);

-- Native-to-canonical mappings use transform_equivalent only when the canonical
-- value differs from the same operational quantity solely by a declared deterministic
-- representation/unit transform. Broader construct mappings remain
-- conceptually_equivalent, comparable, related, or noncomparable as warranted.

-- Pairwise relationships are explicit because a shared canonical name must not imply
-- interchangeability (e.g. contour median frequency vs MUPET mean frequency).
-- Profile relationship phrases project into the constrained relational vocabulary:
--   comparable_same_intended_construct                         -> conceptually_equivalent
--   comparable_not_metric_equivalent / comparable_method_specific
--   / comparable_not_equivalent_to_*                           -> comparable
--   related_not_equivalent_to_*                                -> related
--   no_direct_* / no_clear_direct_* / extractor_specific       -> noncomparable
-- A noncomparable row is only required when preserving an explicit assessed pair;
-- absence of a supported counterpart does not require inventing a pair. The original
-- profile phrase belongs in justification/source_reference rather than relationship_type.
CREATE TABLE feature_relationships (
    feature_relationship_id INTEGER PRIMARY KEY,
    feature_a_id        INTEGER NOT NULL REFERENCES extractor_features(extractor_feature_id) ON DELETE CASCADE,
    feature_b_id        INTEGER NOT NULL REFERENCES extractor_features(extractor_feature_id) ON DELETE CASCADE,
    relationship_type   TEXT NOT NULL CHECK (relationship_type IN (
                            'transform_equivalent',
                            'conceptually_equivalent',
                            'comparable',
                            'related',
                            'noncomparable'
                        )),
    comparison_method   TEXT,
    unit_normalization  TEXT,
    consilience_eligible INTEGER NOT NULL DEFAULT 0 CHECK (consilience_eligible IN (0,1)),
    default_role        TEXT,
    justification       TEXT,
    source_reference    TEXT,
    CHECK(feature_a_id < feature_b_id),
    UNIQUE(feature_a_id, feature_b_id)
);

-- ============================================================================
-- 7. Extractor-specific detections and native measurements
-- ============================================================================

-- A detection is an extractor/run-specific observation, not a biological truth claim.
-- start/end are the mapping-profile-selected canonical event geometry used for indexing
-- and matching; native operational measurements remain in event_measurements.
CREATE TABLE detections (
    detection_id        INTEGER PRIMARY KEY,
    extraction_run_id   INTEGER NOT NULL REFERENCES extraction_runs(extraction_run_id) ON DELETE CASCADE,
    recording_id        INTEGER NOT NULL REFERENCES recordings(recording_id) ON DELETE CASCADE,
    source_artifact_id  INTEGER REFERENCES artifacts(artifact_id) ON DELETE SET NULL,
    extractor_object_id INTEGER REFERENCES extractor_objects(extractor_object_id) ON DELETE SET NULL,
    native_event_id     TEXT,
    event_subtype       TEXT NOT NULL DEFAULT 'vocalization_detection',
    start_time_s        REAL NOT NULL CHECK (start_time_s >= 0),
    end_time_s          REAL NOT NULL CHECK (end_time_s >= start_time_s),
    timing_basis        TEXT,
    detection_score     REAL,
    imported_at_utc     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    notes               TEXT,
    UNIQUE(extraction_run_id, recording_id, source_artifact_id, native_event_id)
);

CREATE TABLE event_measurements (
    event_measurement_id INTEGER PRIMARY KEY,
    detection_id        INTEGER NOT NULL REFERENCES detections(detection_id) ON DELETE CASCADE,
    extractor_feature_id INTEGER NOT NULL REFERENCES extractor_features(extractor_feature_id) ON DELETE RESTRICT,
    canonical_feature_id INTEGER REFERENCES canonical_features(canonical_feature_id) ON DELETE SET NULL,
    source_artifact_id  INTEGER REFERENCES artifacts(artifact_id) ON DELETE SET NULL,
    native_value_type   TEXT NOT NULL CHECK (native_value_type IN ('real','integer','text','boolean','json','missing')),
    -- Original lexical token, including a sentinel/blank represented as explicit missingness.
    native_raw_token    TEXT,
    native_value_real   REAL,
    native_value_integer INTEGER,
    native_value_text   TEXT,
    native_value_boolean INTEGER CHECK (native_value_boolean IS NULL OR native_value_boolean IN (0,1)),
    native_value_json   TEXT,
    native_unit         TEXT,
    canonical_value_real REAL,
    canonical_value_integer INTEGER,
    canonical_value_text TEXT,
    canonical_value_boolean INTEGER CHECK (canonical_value_boolean IS NULL OR canonical_value_boolean IN (0,1)),
    canonical_value_json TEXT,
    canonical_unit      TEXT,
    transform_key       TEXT,
    operational_variant TEXT,
    source_locator      TEXT,
    notes               TEXT,
    CHECK (
      (native_value_type = 'missing' AND native_value_real IS NULL AND native_value_integer IS NULL AND native_value_text IS NULL AND native_value_boolean IS NULL AND native_value_json IS NULL)
      OR
      (native_value_type <> 'missing' AND
       (native_value_real IS NOT NULL) + (native_value_integer IS NOT NULL) + (native_value_text IS NOT NULL) + (native_value_boolean IS NOT NULL) + (native_value_json IS NOT NULL) = 1)
    )
);

-- Safety valve required by structure-agnostic imports: source fields unknown to the
-- current mapping profile are preserved rather than discarded.
CREATE TABLE unmapped_source_values (
    unmapped_value_id   INTEGER PRIMARY KEY,
    extraction_run_id   INTEGER REFERENCES extraction_runs(extraction_run_id) ON DELETE CASCADE,
    detection_id        INTEGER REFERENCES detections(detection_id) ON DELETE CASCADE,
    extractor_object_id INTEGER REFERENCES extractor_objects(extractor_object_id) ON DELETE CASCADE,
    source_artifact_id  INTEGER REFERENCES artifacts(artifact_id) ON DELETE SET NULL,
    native_field_name   TEXT NOT NULL,
    raw_value_text      TEXT,
    native_unit         TEXT,
    source_locator      TEXT,
    reason_unmapped     TEXT,
    mapping_profile_version_id INTEGER REFERENCES config_profile_versions(profile_version_id) ON DELETE SET NULL
);

-- Review/curation history is evidence about extractor/user state, not ground truth.
CREATE TABLE curation_events (
    curation_event_id   INTEGER PRIMARY KEY,
    detection_id        INTEGER NOT NULL REFERENCES detections(detection_id) ON DELETE CASCADE,
    source_artifact_id  INTEGER REFERENCES artifacts(artifact_id) ON DELETE SET NULL,
    action_type         TEXT NOT NULL,
    status_after        TEXT,
    actor_type          TEXT NOT NULL DEFAULT 'extractor' CHECK (actor_type IN ('extractor','human','vawlume','unknown')),
    actor_label         TEXT,
    event_time_utc      TEXT,
    details_json        TEXT,
    notes               TEXT
);

-- ============================================================================
-- 8. Extractor-native classification / repertoire outputs
-- ============================================================================

CREATE TABLE classification_runs (
    classification_run_id INTEGER PRIMARY KEY,
    project_id          INTEGER NOT NULL REFERENCES projects(project_id) ON DELETE CASCADE,
    parent_extraction_run_id INTEGER NOT NULL REFERENCES extraction_runs(extraction_run_id) ON DELETE CASCADE,
    extractor_object_id INTEGER REFERENCES extractor_objects(extractor_object_id) ON DELETE SET NULL,
    model_artifact_id   INTEGER REFERENCES artifacts(artifact_id) ON DELETE SET NULL,
    settings_profile_version_id INTEGER REFERENCES config_profile_versions(profile_version_id) ON DELETE SET NULL,
    method              TEXT NOT NULL,
    run_label           TEXT,
    number_of_classes   INTEGER CHECK (number_of_classes IS NULL OR number_of_classes >= 1),
    created_at_utc      TEXT,
    notes               TEXT
);

CREATE TABLE classification_classes (
    classification_class_id INTEGER PRIMARY KEY,
    classification_run_id INTEGER NOT NULL REFERENCES classification_runs(classification_run_id) ON DELETE CASCADE,
    native_class_id      TEXT,
    native_class_label   TEXT,
    canonical_class_label TEXT,
    description          TEXT,
    UNIQUE(classification_run_id, native_class_id)
);

CREATE TABLE classification_assignments (
    classification_assignment_id INTEGER PRIMARY KEY,
    detection_id        INTEGER NOT NULL REFERENCES detections(detection_id) ON DELETE CASCADE,
    classification_run_id INTEGER NOT NULL REFERENCES classification_runs(classification_run_id) ON DELETE CASCADE,
    classification_class_id INTEGER NOT NULL REFERENCES classification_classes(classification_class_id) ON DELETE CASCADE,
    score_or_distance   REAL,
    assignment_source   TEXT NOT NULL DEFAULT 'extractor',
    notes               TEXT,
    UNIQUE(detection_id, classification_run_id)
);

-- ============================================================================
-- 9. General analysis-run provenance
-- ============================================================================

CREATE TABLE analysis_runs (
    analysis_run_id     INTEGER PRIMARY KEY,
    project_id          INTEGER NOT NULL REFERENCES projects(project_id) ON DELETE CASCADE,
    parent_analysis_run_id INTEGER REFERENCES analysis_runs(analysis_run_id) ON DELETE SET NULL,
    run_type            TEXT NOT NULL,
    run_key             TEXT NOT NULL,
    run_label           TEXT,
    vawlume_version     TEXT,
    source_commit       TEXT,
    status              TEXT NOT NULL DEFAULT 'started' CHECK (status IN ('started','completed','completed_with_warnings','failed')),
    started_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    completed_at_utc    TEXT,
    notes               TEXT,
    UNIQUE(project_id, run_key)
);

CREATE TABLE analysis_run_profiles (
    analysis_run_id     INTEGER NOT NULL REFERENCES analysis_runs(analysis_run_id) ON DELETE CASCADE,
    profile_version_id  INTEGER NOT NULL REFERENCES config_profile_versions(profile_version_id) ON DELETE RESTRICT,
    assignment_role     TEXT NOT NULL,
    PRIMARY KEY(analysis_run_id, profile_version_id, assignment_role)
);

CREATE TABLE analysis_run_extraction_inputs (
    analysis_run_id     INTEGER NOT NULL REFERENCES analysis_runs(analysis_run_id) ON DELETE CASCADE,
    extraction_run_id   INTEGER NOT NULL REFERENCES extraction_runs(extraction_run_id) ON DELETE CASCADE,
    input_role          TEXT NOT NULL DEFAULT 'input',
    PRIMARY KEY(analysis_run_id, extraction_run_id, input_role)
);

-- One derived analysis may consume several source analyses. analysis_runs
-- .parent_analysis_run_id cannot express that: an arbitrary-N agreement
-- derivation over three extractors composes three pairwise analyses and there is
-- no single parent among them. parent_analysis_run_id keeps its existing meaning
-- for genuinely single-parent child runs, such as the pairwise agreement
-- statistics run, and is not overloaded here.
--
-- source_analysis_run_id is RESTRICT on purpose. A derived result must not
-- silently outlive the evidence it was composed from, so deleting a source
-- analysis fails while a derived analysis still cites it; the derived analysis
-- must be deleted first, which cascades these rows away.
--
-- dependency_role is descriptive, not part of identity: one source analysis
-- contributes to one derived analysis once.
CREATE TABLE analysis_run_sources (
    analysis_run_id        INTEGER NOT NULL REFERENCES analysis_runs(analysis_run_id) ON DELETE CASCADE,
    source_analysis_run_id INTEGER NOT NULL REFERENCES analysis_runs(analysis_run_id) ON DELETE RESTRICT,
    dependency_role        TEXT NOT NULL DEFAULT 'source_analysis',
    notes                  TEXT,
    PRIMARY KEY(analysis_run_id, source_analysis_run_id),
    CHECK(analysis_run_id <> source_analysis_run_id)
);

-- ============================================================================
-- 10. Cross-extractor correspondence and consilience
-- ============================================================================

CREATE TABLE candidate_pairs (
    candidate_pair_id   INTEGER PRIMARY KEY,
    analysis_run_id     INTEGER NOT NULL REFERENCES analysis_runs(analysis_run_id) ON DELETE CASCADE,
    recording_id        INTEGER NOT NULL REFERENCES recordings(recording_id) ON DELETE CASCADE,
    detection_a_id      INTEGER NOT NULL REFERENCES detections(detection_id) ON DELETE CASCADE,
    detection_b_id      INTEGER NOT NULL REFERENCES detections(detection_id) ON DELETE CASCADE,
    temporal_overlap_s  REAL CHECK (temporal_overlap_s IS NULL OR temporal_overlap_s >= 0),
    temporal_iou        REAL CHECK (temporal_iou IS NULL OR (temporal_iou >= 0 AND temporal_iou <= 1)),
    onset_difference_s  REAL,
    offset_difference_s REAL,
    duration_difference_s REAL,
    candidate_score     REAL,
    candidate_status    TEXT NOT NULL DEFAULT 'candidate',
    details_json        TEXT,
    CHECK(detection_a_id < detection_b_id),
    UNIQUE(analysis_run_id, detection_a_id, detection_b_id)
);

CREATE TABLE match_groups (
    match_group_id      INTEGER PRIMARY KEY,
    analysis_run_id     INTEGER NOT NULL REFERENCES analysis_runs(analysis_run_id) ON DELETE CASCADE,
    recording_id        INTEGER NOT NULL REFERENCES recordings(recording_id) ON DELETE CASCADE,
    match_type          TEXT NOT NULL CHECK (match_type IN ('one_to_one','one_to_many','many_to_one','many_to_many','unmatched','ambiguous')),
    ambiguity_status    TEXT,
    match_score         REAL,
    notes               TEXT
);

CREATE TABLE match_group_members (
    match_group_id      INTEGER NOT NULL REFERENCES match_groups(match_group_id) ON DELETE CASCADE,
    detection_id        INTEGER NOT NULL REFERENCES detections(detection_id) ON DELETE CASCADE,
    member_role         TEXT,
    PRIMARY KEY(match_group_id, detection_id)
);

-- A consensus event is VAWLUME-derived. It does not replace native detections.
CREATE TABLE consensus_events (
    consensus_event_id  INTEGER PRIMARY KEY,
    analysis_run_id     INTEGER NOT NULL REFERENCES analysis_runs(analysis_run_id) ON DELETE CASCADE,
    match_group_id      INTEGER REFERENCES match_groups(match_group_id) ON DELETE SET NULL,
    recording_id        INTEGER NOT NULL REFERENCES recordings(recording_id) ON DELETE CASCADE,
    start_time_s        REAL NOT NULL CHECK (start_time_s >= 0),
    end_time_s          REAL NOT NULL CHECK (end_time_s >= start_time_s),
    derivation_method   TEXT NOT NULL,
    consensus_status    TEXT,
    confidence_score    REAL,
    notes               TEXT
);

CREATE TABLE consensus_event_members (
    consensus_event_id  INTEGER NOT NULL REFERENCES consensus_events(consensus_event_id) ON DELETE CASCADE,
    detection_id        INTEGER NOT NULL REFERENCES detections(detection_id) ON DELETE CASCADE,
    member_role         TEXT,
    PRIMARY KEY(consensus_event_id, detection_id)
);

CREATE TABLE consilience_assessments (
    consilience_assessment_id INTEGER PRIMARY KEY,
    analysis_run_id     INTEGER NOT NULL REFERENCES analysis_runs(analysis_run_id) ON DELETE CASCADE,
    match_group_id      INTEGER REFERENCES match_groups(match_group_id) ON DELETE CASCADE,
    consensus_event_id  INTEGER REFERENCES consensus_events(consensus_event_id) ON DELETE CASCADE,
    status              TEXT NOT NULL,
    score               REAL,
    rationale_json      TEXT,
    assessed_at_utc     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    CHECK ((match_group_id IS NOT NULL) + (consensus_event_id IS NOT NULL) = 1)
);

-- Manual QC/adjudication may target one native detection, a proposed match group,
-- or a consensus event. These are deliberately separate evidentiary layers.
CREATE TABLE manual_reviews (
    manual_review_id    INTEGER PRIMARY KEY,
    analysis_run_id     INTEGER REFERENCES analysis_runs(analysis_run_id) ON DELETE SET NULL,
    detection_id        INTEGER REFERENCES detections(detection_id) ON DELETE CASCADE,
    match_group_id      INTEGER REFERENCES match_groups(match_group_id) ON DELETE CASCADE,
    consensus_event_id  INTEGER REFERENCES consensus_events(consensus_event_id) ON DELETE CASCADE,
    reviewer_label      TEXT,
    review_status       TEXT NOT NULL,
    corrected_start_time_s REAL,
    corrected_end_time_s REAL,
    reviewed_at_utc     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    notes               TEXT,
    CHECK ((detection_id IS NOT NULL) + (match_group_id IS NOT NULL) + (consensus_event_id IS NOT NULL) = 1),
    CHECK (corrected_end_time_s IS NULL OR corrected_start_time_s IS NULL OR corrected_end_time_s >= corrected_start_time_s)
);

-- Reviewer-authored events, independent of any extractor and of any analysis.
--
-- manual_reviews adjudicates something that already exists: a detection, a match
-- group, or a consensus event. It therefore cannot represent an event that no
-- extractor found, which makes recall and false negatives unrepresentable. These
-- rows are the missing half: a reviewer asserting that a vocalization occurred,
-- attached to the recording rather than to anything an extractor produced.
--
-- Scoped to the recording and to a named reference set, not to an analysis run,
-- so one reviewed subset anchors every matching configuration compared against
-- it. Nothing here is derived from extractor curation; a reference set built from
-- an extractor's own accept flag would not be independent evidence.
--
-- Whether a set annotates the whole recording exhaustively is a methodological
-- property of how it was produced, so it is declared in the versioned matching
-- and consilience specification rather than assumed here. Precision needs no such
-- claim; recall is only meaningful under exhaustive coverage.
CREATE TABLE manual_reference_events (
    manual_reference_event_id INTEGER PRIMARY KEY,
    recording_id        INTEGER NOT NULL REFERENCES recordings(recording_id) ON DELETE CASCADE,
    reference_set_key   TEXT NOT NULL,
    native_reference_id TEXT,
    reviewer_label      TEXT,
    start_time_s        REAL NOT NULL CHECK (start_time_s >= 0),
    end_time_s          REAL NOT NULL CHECK (end_time_s >= start_time_s),
    event_status        TEXT NOT NULL DEFAULT 'reference_event' CHECK (event_status IN (
                            'reference_event',
                            'reference_event_uncertain'
                        )),
    reviewed_at_utc     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    notes               TEXT,
    UNIQUE(recording_id, reference_set_key, native_reference_id)
);

-- Generic storage for detection- or feature-agreement statistics produced after matching.
CREATE TABLE agreement_statistics (
    agreement_statistic_id INTEGER PRIMARY KEY,
    analysis_run_id     INTEGER NOT NULL REFERENCES analysis_runs(analysis_run_id) ON DELETE CASCADE,
    statistic_kind      TEXT NOT NULL CHECK (statistic_kind IN ('detection_agreement','feature_agreement','matching_diagnostic','other')),
    feature_a_id        INTEGER REFERENCES extractor_features(extractor_feature_id) ON DELETE SET NULL,
    feature_b_id        INTEGER REFERENCES extractor_features(extractor_feature_id) ON DELETE SET NULL,
    scope_entity_id     INTEGER REFERENCES experimental_entities(entity_id) ON DELETE SET NULL,
    statistic_name      TEXT NOT NULL,
    statistic_value     REAL,
    lower_bound         REAL,
    upper_bound         REAL,
    n_observations      INTEGER CHECK (n_observations IS NULL OR n_observations >= 0),
    notes               TEXT
);

-- --------------------------------------------------------------------------
-- Arbitrary-N extractor agreement: a derived layer over pairwise evidence
-- --------------------------------------------------------------------------
--
-- Pairwise correspondence remains the primitive. An agreement group is a derived
-- component over native detections for one recording, composed from the exact
-- candidate edges of the pairwise analyses declared in analysis_run_sources. It
-- does not replace match_groups, which remain the authoritative partition of one
-- ordered run pair, and it does not replace consensus_events, which remain the
-- derived interval geometry of one pairwise group.
--
-- Nothing summarising is stored in this layer. Participating extractor count,
-- supported-edge count, possible-edge count, support fraction, pattern labels
-- such as '2 of 3', feature-support capacity counts, extractor-set labels, and
-- confidence categories are all derivable from agreement_group_members,
-- agreement_supporting_edges, the source analyses' declared extraction inputs,
-- and feature_relationships. Storing any of them would create a second answer
-- that can drift out of agreement with the evidence it summarises.
CREATE TABLE agreement_groups (
    agreement_group_id  INTEGER PRIMARY KEY,
    analysis_run_id     INTEGER NOT NULL REFERENCES analysis_runs(analysis_run_id) ON DELETE CASCADE,
    recording_id        INTEGER NOT NULL REFERENCES recordings(recording_id) ON DELETE CASCADE,
    group_key           TEXT NOT NULL,
    derivation_method   TEXT NOT NULL,
    notes               TEXT,
    UNIQUE(analysis_run_id, group_key)
);

-- group_key is this group's deterministic identity within its agreement run, in
-- the sense the pairwise layer already uses for components: an ordered member
-- identity string. A rerun needs it before members exist in order to decide
-- reuse versus conflict, which is why it is stored rather than derived. It is an
-- identity, not a summary, and must not encode counts, fractions, or agreement
-- labels.

-- A detection joins an agreement group on temporal correspondence evidence
-- alone. Membership is deliberately not gated on feature support: whether any
-- eligible non-timing feature relationship exists for the participating
-- extractor versions (potential), whether both events carried usable values
-- (realized availability), and whether the comparison fell within tolerance
-- (observed outcome) are three separate dimensions, each separately queryable.
-- A group whose members have no comparable non-timing feature at all is a real
-- observation about the extractors, not a defective row to be filtered out.
-- The two foreign keys carry deliberately different delete policies.
-- agreement_group_id cascades: deleting the derivation should remove the whole
-- derived layer and nothing else. detection_id restricts: a group_key is the
-- sorted list of its members' selectors, so a member that disappeared would
-- leave a stored identity naming a detection that is no longer there. A matched
-- member is already protected indirectly, because agreement_supporting_edges
-- restricts its candidate_pair_id. A singleton or extractor-unique member
-- participates in no candidate pair and would otherwise have nothing protecting
-- it, which is precisely the member the composition policy deliberately keeps.
CREATE TABLE agreement_group_members (
    agreement_group_id  INTEGER NOT NULL REFERENCES agreement_groups(agreement_group_id) ON DELETE CASCADE,
    detection_id        INTEGER NOT NULL REFERENCES detections(detection_id) ON DELETE RESTRICT,
    member_role         TEXT,
    PRIMARY KEY(agreement_group_id, detection_id)
);

-- The exact pairwise edge is the stored authority for why a group holds together.
-- candidate_pair_id reaches the producing analysis, its recording, its temporal
-- metrics, its versioned matching specification, and its pairwise match group,
-- so none of those is copied here.
--
-- Topology needs no second stored FK: a pairwise analysis assigns each detection
-- to at most one match group, and a candidate edge's two endpoints are joined
-- into the same component, so the edge's pairwise group is reachable and unique.
-- A candidate-only source analysis simply has no group to report, which is
-- absence rather than ambiguity.
--
-- This row is never gated on consilience_assessments.status. A pairwise edge
-- stays queryable evidence when no eligible non-timing feature relationship
-- exists, when only one exists, when a measurement is missing for this event,
-- when the group is only temporally_matched under the current categorical rule,
-- and when the feature evidence is discrepant. Those conditions are for later
-- surfaces to label, sort, and filter on, not for this layer to erase.
--
-- RESTRICT for the same reason as analysis_run_sources: deleting a candidate
-- pair, or an analysis run whose deletion would cascade into candidate_pairs, is
-- refused while a derived agreement group cites that edge.
CREATE TABLE agreement_supporting_edges (
    agreement_supporting_edge_id INTEGER PRIMARY KEY,
    agreement_group_id  INTEGER NOT NULL REFERENCES agreement_groups(agreement_group_id) ON DELETE CASCADE,
    candidate_pair_id   INTEGER NOT NULL REFERENCES candidate_pairs(candidate_pair_id) ON DELETE RESTRICT,
    notes               TEXT,
    UNIQUE(agreement_group_id, candidate_pair_id)
);

-- ============================================================================
-- 11. External behavioral/neural streams and temporal alignment
-- ============================================================================

-- A timebase defines the native clock of a recording, video, operant controller,
-- photometry file, etc. It allows TTL and non-TTL workflows to share one model.
--
-- timebase_kind stays free text on purpose. VAWLUME does not own a vocabulary of
-- acquisition devices, and constraining it would push users toward miscategorizing
-- an unfamiliar clock rather than describing it. The one thing alignment genuinely
-- needs is a resolvable audio clock per recording, and that is carried by the
-- explicit is_recording_native marker instead.
--
-- Reference status is deliberately NOT a column here. Being the reference is a
-- property of one alignment set, not an intrinsic property of a clock; the same
-- neural clock may be the reference in one alignment and a source in another.
-- It lives on alignment_sets.reference_timebase_id.
CREATE TABLE timebases (
    timebase_id         INTEGER PRIMARY KEY,
    project_id          INTEGER NOT NULL REFERENCES projects(project_id) ON DELETE CASCADE,
    recording_id        INTEGER REFERENCES recordings(recording_id) ON DELETE CASCADE,
    timebase_name       TEXT NOT NULL,
    timebase_kind       TEXT NOT NULL,
    -- 1 marks the single clock a VAWLUME recording's detections are expressed in.
    -- Detections inherit it through recording_id and carry no timebase FK of their own.
    is_recording_native INTEGER NOT NULL DEFAULT 0 CHECK (is_recording_native IN (0,1)),
    native_unit         TEXT NOT NULL DEFAULT 's',
    nominal_rate_hz     REAL CHECK (nominal_rate_hz IS NULL OR nominal_rate_hz > 0),
    origin_description  TEXT,
    clock_identifier    TEXT,
    notes               TEXT,
    CHECK (is_recording_native = 0 OR recording_id IS NOT NULL)
);

-- Continuous neural traces remain external artifacts; SQLite stores stream identity,
-- provenance, timing, and event/annotation records rather than millions of samples.
--
-- A stream is a LOGICAL object: "the behaviour scoring for this session", not "this
-- CSV". The files it was read from live in external_stream_sources, so a stream
-- split across two exports, or re-exported later, does not become two streams.
-- The former direct source_file_id / artifact_id / mapping_profile_version_id
-- columns were removed for exactly that reason: keeping both would create two
-- competing provenance authorities. external_stream_sources is the only one.
CREATE TABLE external_streams (
    external_stream_id  INTEGER PRIMARY KEY,
    project_id          INTEGER NOT NULL REFERENCES projects(project_id) ON DELETE CASCADE,
    recording_id        INTEGER REFERENCES recordings(recording_id) ON DELETE CASCADE,
    timebase_id         INTEGER NOT NULL REFERENCES timebases(timebase_id) ON DELETE RESTRICT,
    stream_name         TEXT NOT NULL,
    stream_kind         TEXT NOT NULL CHECK (stream_kind IN ('event','continuous','annotation','video','ttl','tracking','other')),
    modality            TEXT,
    units               TEXT,
    notes               TEXT
);

-- Where one logical stream's records actually came from. Exactly one of
-- source_file_id / artifact_id identifies each row, and several rows per stream
-- are legal because one stream may span several exports.
CREATE TABLE external_stream_sources (
    external_stream_source_id INTEGER PRIMARY KEY,
    external_stream_id  INTEGER NOT NULL REFERENCES external_streams(external_stream_id) ON DELETE CASCADE,
    source_file_id      INTEGER REFERENCES source_files(source_file_id) ON DELETE RESTRICT,
    artifact_id         INTEGER REFERENCES artifacts(artifact_id) ON DELETE RESTRICT,
    source_role         TEXT NOT NULL DEFAULT 'events' CHECK (source_role IN (
                            'events',
                            'anchors',
                            'coverage',
                            'attributes',
                            'other'
                        )),
    mapping_profile_version_id INTEGER REFERENCES config_profile_versions(profile_version_id) ON DELETE SET NULL,
    source_locator      TEXT,
    notes               TEXT,
    CHECK ((source_file_id IS NOT NULL) + (artifact_id IS NOT NULL) = 1)
);

-- native_event_label preserves the source's own vocabulary; event_type is the
-- normalized operational key VAWLUME queries. When no mapping profile supplies a
-- normalization, event_type may simply repeat the native label. Neither is a
-- universal behavioural or neural taxonomy, and normalization never overwrites
-- the native term.
CREATE TABLE external_events (
    external_event_id   INTEGER PRIMARY KEY,
    external_stream_id  INTEGER NOT NULL REFERENCES external_streams(external_stream_id) ON DELETE CASCADE,
    entity_id           INTEGER REFERENCES experimental_entities(entity_id) ON DELETE SET NULL,
    native_event_id     TEXT,
    native_event_label  TEXT,
    event_type          TEXT NOT NULL,
    start_time_native   REAL NOT NULL,
    end_time_native     REAL,
    value_text          TEXT,
    value_real          REAL,
    unit                TEXT,
    mapping_rule_key    TEXT,
    source_locator      TEXT,
    notes               TEXT,
    CHECK (end_time_native IS NULL OR end_time_native >= start_time_native),
    UNIQUE(external_stream_id, native_event_id)
);

-- Arbitrary mapped event fields (actor, cell_id, confidence, prominence, ...) in
-- long form, following the entity_attributes typed-value convention. Missingness
-- is explicit via value_type='missing' rather than being coerced to 0 or ''.
CREATE TABLE external_event_attributes (
    external_event_attribute_id INTEGER PRIMARY KEY,
    external_event_id   INTEGER NOT NULL REFERENCES external_events(external_event_id) ON DELETE CASCADE,
    attribute_name      TEXT NOT NULL,
    native_field_name   TEXT,
    value_type          TEXT NOT NULL CHECK (value_type IN ('text','real','integer','boolean','json','missing')),
    value_text          TEXT,
    value_real          REAL,
    value_integer       INTEGER,
    value_boolean       INTEGER CHECK (value_boolean IS NULL OR value_boolean IN (0,1)),
    value_json          TEXT,
    native_raw_token    TEXT,
    unit                TEXT,
    source_locator      TEXT,
    mapping_rule_key    TEXT,
    UNIQUE(external_event_id, attribute_name),
    CHECK (
      (value_type = 'missing' AND value_text IS NULL AND value_real IS NULL AND value_integer IS NULL AND value_boolean IS NULL AND value_json IS NULL)
      OR
      (value_type <> 'missing' AND
       (value_text IS NOT NULL) + (value_real IS NOT NULL) + (value_integer IS NOT NULL) + (value_boolean IS NOT NULL) + (value_json IS NOT NULL) = 1)
    )
);

-- When a stream was actually being observed, in its own native clock.
--
-- This is what lets a regularized timeline distinguish "no event occurred here"
-- from "nobody was watching here". Several segments per stream are the point: a
-- dropout, a paused camera, or a scorer who annotated two windows must not be
-- flattened into one continuous interval.
--
-- The prototype stores only observed intervals. Any span outside every segment of
-- a stream is unknown/unavailable, not empty. If further statuses are ever needed
-- the vocabulary stays small and each value gets defined here.
CREATE TABLE external_stream_coverage (
    external_stream_coverage_id INTEGER PRIMARY KEY,
    external_stream_id  INTEGER NOT NULL REFERENCES external_streams(external_stream_id) ON DELETE CASCADE,
    segment_index       INTEGER NOT NULL CHECK (segment_index >= 1),
    start_time_native   REAL NOT NULL,
    end_time_native     REAL NOT NULL,
    observation_status  TEXT NOT NULL DEFAULT 'observed' CHECK (observation_status IN ('observed')),
    source_locator      TEXT,
    notes               TEXT,
    CHECK (end_time_native >= start_time_native),
    UNIQUE(external_stream_id, segment_index)
);

-- Tracking is an external stream, not a parallel ontology. Stream identity,
-- sources, timebase, and coverage all stay on the tables above; this 1:1
-- subtype adds only the facts that are specific to canonicalized tracking.
--
-- stream_kind = 'tracking' rather than the existing 'continuous': a pose trace
-- is not a continuous signal in the sense a photometry trace is, and conflating
-- them would blur the distinction the coverage and window-reading semantics
-- depend on.
--
-- DENSE SAMPLES ARE NEVER STORED. Positions, frames, and confidences stay in
-- the registered artifact and are read window-wise on demand. This mirrors the
-- policy already applied to continuous neural data and is a hard boundary: an
-- itinerary that wants a tracking_samples table has left the multimodal input
-- contract and needs an explicit decision, not a migration.
CREATE TABLE tracking_streams (
    external_stream_id  INTEGER PRIMARY KEY REFERENCES external_streams(external_stream_id) ON DELETE CASCADE,
    coordinate_system_id INTEGER NOT NULL REFERENCES coordinate_systems(coordinate_system_id) ON DELETE RESTRICT,
    -- Which native basis the artifact actually carries. 'frame' alone requires a
    -- frame rate, because without one a frame index cannot be related to any
    -- clock; 'time' and 'both' do not.
    native_time_basis   TEXT NOT NULL CHECK (native_time_basis IN ('time','frame','both')),
    nominal_frame_rate_hz REAL CHECK (nominal_frame_rate_hz IS NULL OR nominal_frame_rate_hz > 0),
    -- Confidence is optional in the contract. 0 means the upstream tracker
    -- emitted none, which readers report rather than imputing a value.
    has_confidence      INTEGER NOT NULL DEFAULT 0 CHECK (has_confidence IN (0,1)),
    -- Declared by the registering caller from the artifact it read, so a later
    -- window read can sanity-check the file it opens against what was registered.
    declared_sample_count INTEGER CHECK (declared_sample_count IS NULL OR declared_sample_count >= 0),
    notes               TEXT,
    CHECK (native_time_basis <> 'frame' OR nominal_frame_rate_hz IS NOT NULL)
);

-- One (native track, bodypart) trace within a tracking stream. Metadata, not
-- data: tens of rows per stream, one per trace, never one per sample.
--
-- native_track_id is the UPSTREAM TRAJECTORY LABEL - 'track0', 'individual1',
-- or an animal-like name the tracker happened to use. It is deliberately NOT
-- called an entity label: a tracker may emit a stable-looking name while still
-- permitting identity swaps, ambiguous crossings, and uncalibrated identity
-- evidence, so a trajectory label is not proof of which animal it follows.
--
-- There is therefore NO entity_id here. Associating a native track with a
-- canonical experimental entity is time-varying evidence with its own score
-- semantics, calibration status, review state and provenance - it is a separate
-- layer, not a column. Putting a nullable entity_id on this row would make an
-- unverified guess indistinguishable from a verified assertion, and would force
-- one identity per trace for a whole session.
--
-- Native track and bodypart labels are preserved verbatim and are always
-- queryable. VAWLUME defines no bodypart ontology; canonical_bodypart_role is
-- optional, additive, and justified per project - the same additive rule
-- external_events.event_type follows beside native_event_label.
CREATE TABLE tracking_series (
    tracking_series_id  INTEGER PRIMARY KEY,
    external_stream_id  INTEGER NOT NULL REFERENCES tracking_streams(external_stream_id) ON DELETE CASCADE,
    native_track_id     TEXT NOT NULL,
    native_bodypart_label TEXT NOT NULL,
    canonical_bodypart_role TEXT,
    notes               TEXT,
    UNIQUE(external_stream_id, native_track_id, native_bodypart_label)
);

-- Evidence that a native trajectory corresponds to a canonical experimental
-- entity over some interval. This is the ONLY place the two identities are
-- related, and every relation is an interval-scoped, provenance-bearing claim
-- rather than a property of the trajectory.
--
-- Keyed on (stream, native_track_id, interval) and NOT on tracking_series_id:
-- identity belongs to a trajectory over time, not to one (track, bodypart)
-- trace. When two animals cross and their labels swap, every bodypart of that
-- track is affected at once.
--
-- SEVERAL ROWS MAY COVER ONE INTERVAL. That is the ambiguity model, not a
-- defect: during an uncertain crossing a track may be compatible with entity A
-- and with entity B, and both candidates are kept. Nothing here forces one
-- entity per track per interval, and no query may assume it.
--
-- entity_id IS NULL means identity is explicitly UNRESOLVED for that interval.
-- It is not a missing foreign key: it is the recorded statement that nothing
-- known identifies the animal. A trigger keeps that meaning honest by requiring
-- assignment_state 'unresolved' exactly when entity_id is NULL, so an unknown
-- identity can never be read as a candidate and a candidate can never hide as
-- an unknown.
--
-- identity_value is NULL unless the source supplied a number. A manual
-- assertion, or an upstream tool that emits only a label, records NULL - never
-- 1.0. Converting a name into certainty is the specific failure this table
-- exists to prevent. When a number IS present, identity_value_semantics must say
-- what it means, because a re-identification similarity, an upstream likelihood
-- and a calibrated probability are not comparable quantities.
--
-- evidence_kind and identity_value_semantics are free text. A closed vocabulary
-- would force an unfamiliar upstream system into the wrong category or block it
-- entirely, the same reasoning that keeps timebase_kind and reference_type open.
--
-- Dense framewise identity traces stay external, under the same policy as dense
-- tracking samples. What is persisted here is interval-level association,
-- review, and the provenance needed to reproduce it.
CREATE TABLE tracking_identity_associations (
    tracking_identity_association_id INTEGER PRIMARY KEY,
    external_stream_id  INTEGER NOT NULL REFERENCES tracking_streams(external_stream_id) ON DELETE CASCADE,
    native_track_id     TEXT NOT NULL,
    entity_id           INTEGER REFERENCES experimental_entities(entity_id) ON DELETE RESTRICT,
    start_time_native   REAL NOT NULL,
    end_time_native     REAL NOT NULL,
    assignment_state    TEXT NOT NULL CHECK (assignment_state IN (
                            'candidate',
                            'assigned',
                            'ambiguous',
                            'unresolved',
                            'rejected'
                        )),
    -- What KIND of evidence this is. Always required: an association with no
    -- stated basis is an opinion with no provenance.
    evidence_kind       TEXT NOT NULL,
    identity_value      REAL,
    identity_value_semantics TEXT,
    calibration_status  TEXT,
    review_state        TEXT,
    method              TEXT,
    analysis_run_id     INTEGER REFERENCES analysis_runs(analysis_run_id) ON DELETE SET NULL,
    source_file_id      INTEGER REFERENCES source_files(source_file_id) ON DELETE RESTRICT,
    mapping_profile_version_id INTEGER REFERENCES config_profile_versions(profile_version_id) ON DELETE SET NULL,
    source_locator      TEXT,
    notes               TEXT,
    CHECK (end_time_native >= start_time_native),
    -- A number without stated semantics is not interpretable evidence.
    CHECK (identity_value IS NULL OR identity_value_semantics IS NOT NULL)
);

-- A declared interval in a recording's native audio clock that is asserted to
-- contain a useful reference signal. This is the CLAIM about where a tone,
-- noise band, background interval, or user-defined signal occurs; later
-- measured channel response is derived evidence and does not belong here.
--
-- recording_channel_id NULL means the declaration applies to every channel in
-- the recording. A channel-specific row must name a channel owned by that same
-- recording; trigger pairs below enforce the cross-table scope on insert and
-- update.
--
-- reference_type is deliberately free text. VAWLUME does not privilege tones,
-- noise, or any hardware-specific calibration sequence. A zero-duration row is
-- a legitimate point-like reference, while end_time_s > start_time_s describes
-- an interval.
--
-- external_event_id is optional provenance only. Existing profile-driven event
-- import may identify the source row, but linking it never turns the reference
-- into an alignment anchor and never makes a clock transform necessary for an
-- audio-native measurement.
CREATE TABLE acoustic_references (
    acoustic_reference_id INTEGER PRIMARY KEY,
    recording_id        INTEGER NOT NULL REFERENCES recordings(recording_id) ON DELETE CASCADE,
    recording_channel_id INTEGER REFERENCES recording_channels(recording_channel_id) ON DELETE CASCADE,
    external_event_id   INTEGER REFERENCES external_events(external_event_id) ON DELETE SET NULL,
    reference_key       TEXT NOT NULL,
    reference_type      TEXT NOT NULL,
    native_label        TEXT,
    start_time_s        REAL NOT NULL CHECK (start_time_s >= 0),
    end_time_s          REAL NOT NULL CHECK (end_time_s >= start_time_s),
    frequency_min_hz    REAL CHECK (frequency_min_hz IS NULL OR frequency_min_hz >= 0),
    frequency_max_hz    REAL CHECK (frequency_max_hz IS NULL OR frequency_max_hz >= 0),
    source_file_id      INTEGER REFERENCES source_files(source_file_id) ON DELETE RESTRICT,
    source_locator      TEXT,
    mapping_profile_version_id INTEGER REFERENCES config_profile_versions(profile_version_id) ON DELETE SET NULL,
    notes               TEXT,
    CHECK (frequency_max_hz IS NULL OR frequency_min_hz IS NULL
           OR frequency_max_hz >= frequency_min_hz),
    UNIQUE(recording_id, reference_key)
);

-- One user-facing multimodal alignment operation: "express this session's clocks
-- relative to the neural clock". It owns the analysis-run identity, the chosen
-- reference timebase, and the exact manifest evidence. The pairwise transforms
-- below are its children, not separate user-facing analyses.
--
-- reference_timebase_id is a coordinate choice, not a claim that the reference
-- device is more accurate than the clocks aligned to it.
--
-- Manifest provenance reuses the existing source_files / artifacts registries
-- rather than adding a parallel one; at most one of the two identifies the
-- manifest, and neither is required while a set is still being assembled.
CREATE TABLE alignment_sets (
    alignment_set_id    INTEGER PRIMARY KEY,
    analysis_run_id     INTEGER NOT NULL UNIQUE REFERENCES analysis_runs(analysis_run_id) ON DELETE CASCADE,
    recording_id        INTEGER REFERENCES recordings(recording_id) ON DELETE CASCADE,
    reference_timebase_id INTEGER NOT NULL REFERENCES timebases(timebase_id) ON DELETE RESTRICT,
    manifest_source_file_id INTEGER REFERENCES source_files(source_file_id) ON DELETE RESTRICT,
    manifest_artifact_id INTEGER REFERENCES artifacts(artifact_id) ON DELETE RESTRICT,
    alignment_set_key   TEXT,
    status              TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','fitted','validated','rejected','failed')),
    notes               TEXT,
    CHECK ((manifest_source_file_id IS NOT NULL) + (manifest_artifact_id IS NOT NULL) <= 1)
);

-- One source timebase expressed in the parent set's reference timebase.
--
-- target_timebase_id is retained so existing joins and aligned-event rows stay
-- readable, but it is redundant with the parent's reference and is trigger-enforced
-- to equal it. It is a convenience column, never an independent authority.
--
-- piecewise_affine is representable here and in alignment_segments, and its
-- breakpoints are declared input persisted in alignment_run_breakpoints. Fitting
-- the model is Phase 3 work: until it lands the fitting API fails clearly rather
-- than silently degrading to a single affine segment, which would answer a
-- different question than the caller asked.
CREATE TABLE time_alignment_runs (
    alignment_run_id    INTEGER PRIMARY KEY,
    alignment_set_id    INTEGER NOT NULL REFERENCES alignment_sets(alignment_set_id) ON DELETE CASCADE,
    source_timebase_id  INTEGER NOT NULL REFERENCES timebases(timebase_id) ON DELETE RESTRICT,
    target_timebase_id  INTEGER NOT NULL REFERENCES timebases(timebase_id) ON DELETE RESTRICT,
    method              TEXT NOT NULL CHECK (method IN ('offset','affine','piecewise_affine')),
    n_anchors_used      INTEGER CHECK (n_anchors_used IS NULL OR n_anchors_used >= 0),
    fit_rmse_s          REAL CHECK (fit_rmse_s IS NULL OR fit_rmse_s >= 0),
    max_error_s         REAL CHECK (max_error_s IS NULL OR max_error_s >= 0),
    -- 'registered' means the transform's identity, clocks, and anchors exist but
    -- nothing has been fitted. Defaulting to 'estimated' would have made a row
    -- with no segments and no residuals claim a fit it does not have.
    status              TEXT NOT NULL DEFAULT 'registered' CHECK (status IN ('registered','estimated','validated','rejected','failed')),
    -- Why a transform did not produce a fit. Without this, a run that was tried
    -- and could not be honoured is indistinguishable from one nobody attempted:
    -- both would sit at 'registered' with no segments. 'failed' therefore requires
    -- a code; 'rejected' may carry one, because a human may reject a fit without a
    -- machine-readable cause.
    failure_code        TEXT,
    failure_reason      TEXT,
    notes               TEXT,
    CHECK (source_timebase_id <> target_timebase_id),
    CHECK (failure_code IS NULL OR status IN ('rejected','failed')),
    CHECK (failure_code IS NULL OR failure_reason IS NOT NULL),
    CHECK (status <> 'failed' OR failure_code IS NOT NULL),
    UNIQUE(alignment_set_id, source_timebase_id)
);

-- Declared breakpoints for a piecewise-affine transform.
--
-- VAWLUME does not search for a breakpoint. Choosing one from the residuals is
-- model selection, and this prototype has no basis for preferring one
-- segmentation over another. A breakpoint is a claim that something happened to a
-- clock, and it is the caller's claim to make.
--
-- They are persisted rather than passed only as a call option because a fit must
-- stay reconstructable from what the database holds. The declared breakpoint set
-- is part of the model's identity, so refitting with a different set is a
-- different alignment rather than a correction to this one.
--
-- Monotonicity is not enforced here: the solver must reject unsorted input
-- anyway, and a CHECK cannot see the sibling rows.
CREATE TABLE alignment_run_breakpoints (
    alignment_run_breakpoint_id INTEGER PRIMARY KEY,
    alignment_run_id    INTEGER NOT NULL REFERENCES time_alignment_runs(alignment_run_id) ON DELETE CASCADE,
    breakpoint_index    INTEGER NOT NULL CHECK (breakpoint_index >= 1),
    source_time         REAL NOT NULL,
    -- How the breakpoint arrived: 'caller' today. Free text rather than a closed
    -- vocabulary, matching anchor_type and evidence_kind elsewhere, so a later
    -- manifest-declared path needs no DDL change.
    declared_by         TEXT NOT NULL,
    notes               TEXT,
    UNIQUE(alignment_run_id, breakpoint_index),
    UNIQUE(alignment_run_id, source_time)
);

-- A logical synchronization anchor: the identity of a coordinating event, not a
-- pair of timestamps. It carries no source or target time, because the whole
-- point is that one anchor is observed separately on each participating clock.
--
-- A synchronization anchor is not an experimental event. A TTL pulse fired near a
-- female-introduction transition is an anchor; the scored female_entry event is an
-- experimental event in external_events and must not be forced to equal the pulse.
CREATE TABLE alignment_anchors (
    alignment_anchor_id INTEGER PRIMARY KEY,
    alignment_set_id    INTEGER NOT NULL REFERENCES alignment_sets(alignment_set_id) ON DELETE CASCADE,
    anchor_key          TEXT NOT NULL,
    anchor_type         TEXT NOT NULL,
    expected_order      INTEGER CHECK (expected_order IS NULL OR expected_order >= 1),
    notes               TEXT,
    UNIQUE(alignment_set_id, anchor_key)
);

-- One logical anchor as seen on one timebase. Several rows per anchor and clock
-- are legal, because redundant TTL channels and duplicate marker readings are real
-- and their spread is evidence about synchronization quality.
--
-- Redundancy must not silently become extra statistical anchors, so a partial
-- unique index permits at most one included_in_fit = 1 observation per
-- (anchor, timebase). Replicates are kept with included_in_fit = 0 as QC evidence.
--
-- external_event_id is optional: a manually identified marker edge with only a
-- timestamp is legal. When it is supplied, a trigger requires that event to belong
-- to a stream on this same timebase.
CREATE TABLE alignment_anchor_observations (
    anchor_observation_id INTEGER PRIMARY KEY,
    alignment_anchor_id INTEGER NOT NULL REFERENCES alignment_anchors(alignment_anchor_id) ON DELETE CASCADE,
    timebase_id         INTEGER NOT NULL REFERENCES timebases(timebase_id) ON DELETE RESTRICT,
    external_event_id   INTEGER REFERENCES external_events(external_event_id) ON DELETE SET NULL,
    observed_time_native REAL NOT NULL,
    observation_role    TEXT NOT NULL DEFAULT 'primary' CHECK (observation_role IN (
                            'primary',
                            'replicate',
                            'excluded'
                        )),
    included_in_fit     INTEGER NOT NULL DEFAULT 1 CHECK (included_in_fit IN (0,1)),
    -- What kind of evidence this reading is. 'device_level' is a TTL, light or
    -- tone edge and is identity-independent. 'identity_dependent' is derived from
    -- a biological event whose meaning depends on which animal it concerns.
    --
    -- Nullable on purpose: an observation whose class was never declared must stay
    -- distinguishable from one declared device_level. A default would convert an
    -- unexamined case into a confident one.
    evidence_class      TEXT CHECK (evidence_class IS NULL OR evidence_class IN ('device_level','identity_dependent')),
    uncertainty_s       REAL CHECK (uncertainty_s IS NULL OR uncertainty_s >= 0),
    source_file_id      INTEGER REFERENCES source_files(source_file_id) ON DELETE SET NULL,
    mapping_profile_version_id INTEGER REFERENCES config_profile_versions(profile_version_id) ON DELETE SET NULL,
    source_locator      TEXT,
    notes               TEXT,
    CHECK (observation_role <> 'excluded' OR included_in_fit = 0)
);

-- Visual-identity evidence qualifying an identity-dependent anchor observation.
--
-- An identity-dependent anchor is admissible. An identity-dependent anchor whose
-- identity uncertainty has been silently discarded is not. This table keeps that
-- uncertainty attached to the observation, where a reader can weigh it.
--
-- It is a separate table rather than a column so that the fitting layer, which
-- reads alignment_anchors and alignment_anchor_observations, does not encounter
-- identity evidence at all. SQLite cannot forbid a join, so the separation is
-- structural here and held by test in the pass that implements the behaviour.
--
-- Several rows per observation are legal. An anchor qualified by 'ambiguous'
-- identity evidence is a real case, and refusing it would push the ambiguity out
-- of the record rather than represent it.
--
-- external_events.entity_id is deliberately NOT the link used here. It is a
-- declared label lookup, weaker than an identity association, and treating it as
-- evidence would make an unverified guess indistinguishable from an assertion.
CREATE TABLE alignment_anchor_identity_evidence (
    alignment_anchor_identity_evidence_id INTEGER PRIMARY KEY,
    anchor_observation_id INTEGER NOT NULL REFERENCES alignment_anchor_observations(anchor_observation_id) ON DELETE CASCADE,
    -- RESTRICT, not CASCADE: deleting identity evidence must not silently
    -- un-qualify an anchor that was admitted because of it.
    tracking_identity_association_id INTEGER NOT NULL REFERENCES tracking_identity_associations(tracking_identity_association_id) ON DELETE RESTRICT,
    notes               TEXT,
    UNIQUE(anchor_observation_id, tracking_identity_association_id)
);

-- Per-anchor fit evidence. A residual belongs to one pairwise transform, not to
-- the logical anchor, because the same anchor yields a different residual under
-- every fit it participates in.
--
-- Both observations are named explicitly rather than inferred, so a reader can see
-- exactly which two readings produced the number.
CREATE TABLE alignment_anchor_residuals (
    alignment_anchor_residual_id INTEGER PRIMARY KEY,
    alignment_run_id    INTEGER NOT NULL REFERENCES time_alignment_runs(alignment_run_id) ON DELETE CASCADE,
    alignment_anchor_id INTEGER NOT NULL REFERENCES alignment_anchors(alignment_anchor_id) ON DELETE CASCADE,
    source_observation_id INTEGER NOT NULL REFERENCES alignment_anchor_observations(anchor_observation_id) ON DELETE CASCADE,
    reference_observation_id INTEGER NOT NULL REFERENCES alignment_anchor_observations(anchor_observation_id) ON DELETE CASCADE,
    observed_source_time REAL NOT NULL,
    observed_reference_time REAL NOT NULL,
    predicted_reference_time REAL NOT NULL,
    residual_s          REAL NOT NULL,
    included_in_fit     INTEGER NOT NULL DEFAULT 1 CHECK (included_in_fit IN (0,1)),
    exclusion_reason    TEXT,
    notes               TEXT,
    CHECK (source_observation_id <> reference_observation_id),
    CHECK (included_in_fit = 1 OR exclusion_reason IS NOT NULL),
    UNIQUE(alignment_run_id, alignment_anchor_id)
);

-- Affine or piecewise-affine mappings: target_time = scale * source_time + offset_s
CREATE TABLE alignment_segments (
    alignment_segment_id INTEGER PRIMARY KEY,
    alignment_run_id    INTEGER NOT NULL REFERENCES time_alignment_runs(alignment_run_id) ON DELETE CASCADE,
    segment_index       INTEGER NOT NULL CHECK (segment_index >= 1),
    source_start        REAL,
    source_end          REAL,
    scale               REAL NOT NULL,
    offset_s            REAL NOT NULL,
    rmse_s              REAL CHECK (rmse_s IS NULL OR rmse_s >= 0),
    uncertainty_s       REAL CHECK (uncertainty_s IS NULL OR uncertainty_s >= 0),
    -- What the number beside it means. A stored quantity without declared
    -- semantics is not stored, the same rule tracking_identity_associations
    -- applies to identity_value. It is never a confidence interval, a standard
    -- error, or a probability, and whatever fills it must say so.
    uncertainty_semantics TEXT,
    CHECK (source_end IS NULL OR source_start IS NULL OR source_end >= source_start),
    CHECK (uncertainty_s IS NULL OR uncertainty_semantics IS NOT NULL),
    UNIQUE(alignment_run_id, segment_index)
);

-- Materialized aligned event timing: a CACHE, not the authority.
--
-- The authoritative statement of where an event falls on the reference clock is
-- always the native timestamp plus the transform in alignment_segments. These rows
-- exist so downstream joins and audits can read an aligned time without evaluating
-- a transform, and they may be regenerated or discarded at any time.
--
-- Nothing in VAWLUME may require a row here in order to align an event, and there
-- is deliberately no aligned_detections counterpart: detections already live on
-- their recording's native timebase, and materializing a second copy of their
-- timing would create exactly the competing authority this note exists to prevent.
CREATE TABLE aligned_external_events (
    aligned_external_event_id INTEGER PRIMARY KEY,
    external_event_id   INTEGER NOT NULL REFERENCES external_events(external_event_id) ON DELETE CASCADE,
    alignment_run_id    INTEGER NOT NULL REFERENCES time_alignment_runs(alignment_run_id) ON DELETE CASCADE,
    target_timebase_id  INTEGER NOT NULL REFERENCES timebases(timebase_id) ON DELETE RESTRICT,
    start_time_aligned_s REAL NOT NULL,
    end_time_aligned_s  REAL,
    uncertainty_s       REAL CHECK (uncertainty_s IS NULL OR uncertainty_s >= 0),
    CHECK (end_time_aligned_s IS NULL OR end_time_aligned_s >= start_time_aligned_s),
    UNIQUE(external_event_id, alignment_run_id)
);

-- ============================================================================
-- 12. Sequence, bout, and hierarchy-aware derived analyses
-- ============================================================================

CREATE TABLE sequences (
    sequence_id         INTEGER PRIMARY KEY,
    analysis_run_id     INTEGER NOT NULL REFERENCES analysis_runs(analysis_run_id) ON DELETE CASCADE,
    recording_id        INTEGER REFERENCES recordings(recording_id) ON DELETE CASCADE,
    epoch_id            INTEGER REFERENCES recording_epochs(epoch_id) ON DELETE CASCADE,
    scope_entity_id     INTEGER REFERENCES experimental_entities(entity_id) ON DELETE SET NULL,
    sequence_name       TEXT NOT NULL,
    event_set_kind      TEXT NOT NULL CHECK (event_set_kind IN ('detections','consensus_events','external_events','mixed')),
    source_extraction_run_id INTEGER REFERENCES extraction_runs(extraction_run_id) ON DELETE SET NULL,
    source_consensus_analysis_run_id INTEGER REFERENCES analysis_runs(analysis_run_id) ON DELETE SET NULL,
    ordering_basis      TEXT NOT NULL DEFAULT 'start_time',
    notes               TEXT
);

CREATE TABLE sequence_members (
    sequence_member_id  INTEGER PRIMARY KEY,
    sequence_id         INTEGER NOT NULL REFERENCES sequences(sequence_id) ON DELETE CASCADE,
    ordinal_position    INTEGER NOT NULL CHECK (ordinal_position >= 1),
    detection_id        INTEGER REFERENCES detections(detection_id) ON DELETE CASCADE,
    consensus_event_id  INTEGER REFERENCES consensus_events(consensus_event_id) ON DELETE CASCADE,
    external_event_id   INTEGER REFERENCES external_events(external_event_id) ON DELETE CASCADE,
    aligned_external_event_id INTEGER REFERENCES aligned_external_events(aligned_external_event_id) ON DELETE CASCADE,
    start_time_s        REAL,
    end_time_s          REAL,
    CHECK (
      (detection_id IS NOT NULL) +
      (consensus_event_id IS NOT NULL) +
      (external_event_id IS NOT NULL) +
      (aligned_external_event_id IS NOT NULL) = 1
    ),
    CHECK (end_time_s IS NULL OR start_time_s IS NULL OR end_time_s >= start_time_s),
    UNIQUE(sequence_id, ordinal_position)
);

CREATE TABLE bouts (
    bout_id             INTEGER PRIMARY KEY,
    analysis_run_id     INTEGER NOT NULL REFERENCES analysis_runs(analysis_run_id) ON DELETE CASCADE,
    sequence_id         INTEGER NOT NULL REFERENCES sequences(sequence_id) ON DELETE CASCADE,
    bout_index          INTEGER NOT NULL CHECK (bout_index >= 1),
    start_time_s        REAL NOT NULL,
    end_time_s          REAL NOT NULL,
    derivation_method   TEXT NOT NULL,
    CHECK(end_time_s >= start_time_s),
    UNIQUE(sequence_id, bout_index)
);

CREATE TABLE bout_members (
    bout_id             INTEGER NOT NULL REFERENCES bouts(bout_id) ON DELETE CASCADE,
    sequence_member_id  INTEGER NOT NULL REFERENCES sequence_members(sequence_member_id) ON DELETE CASCADE,
    ordinal_within_bout INTEGER NOT NULL CHECK (ordinal_within_bout >= 1),
    PRIMARY KEY(bout_id, sequence_member_id),
    UNIQUE(bout_id, ordinal_within_bout)
);

CREATE TABLE metric_definitions (
    metric_definition_id INTEGER PRIMARY KEY,
    metric_key          TEXT NOT NULL UNIQUE,
    metric_name         TEXT NOT NULL,
    value_type          TEXT NOT NULL DEFAULT 'real' CHECK (value_type IN ('real','integer','text','boolean','json')),
    canonical_unit      TEXT,
    definition          TEXT NOT NULL,
    allowed_scope       TEXT,
    derivation_family   TEXT,
    notes               TEXT
);

-- Generic derived metrics with explicit scope. Exactly one target must be supplied.
CREATE TABLE derived_measurements (
    derived_measurement_id INTEGER PRIMARY KEY,
    analysis_run_id     INTEGER NOT NULL REFERENCES analysis_runs(analysis_run_id) ON DELETE CASCADE,
    metric_definition_id INTEGER NOT NULL REFERENCES metric_definitions(metric_definition_id) ON DELETE RESTRICT,
    detection_id        INTEGER REFERENCES detections(detection_id) ON DELETE CASCADE,
    consensus_event_id  INTEGER REFERENCES consensus_events(consensus_event_id) ON DELETE CASCADE,
    external_event_id   INTEGER REFERENCES external_events(external_event_id) ON DELETE CASCADE,
    acoustic_reference_id INTEGER REFERENCES acoustic_references(acoustic_reference_id) ON DELETE CASCADE,
    recording_id        INTEGER REFERENCES recordings(recording_id) ON DELETE CASCADE,
    -- Optional qualifier, not an additional measurement target. For targets
    -- whose recording can be resolved, triggers below enforce channel scope.
    recording_channel_id INTEGER REFERENCES recording_channels(recording_channel_id) ON DELETE CASCADE,
    entity_id           INTEGER REFERENCES experimental_entities(entity_id) ON DELETE CASCADE,
    epoch_id            INTEGER REFERENCES recording_epochs(epoch_id) ON DELETE CASCADE,
    sequence_id         INTEGER REFERENCES sequences(sequence_id) ON DELETE CASCADE,
    bout_id             INTEGER REFERENCES bouts(bout_id) ON DELETE CASCADE,
    value_real          REAL,
    value_integer       INTEGER,
    value_text          TEXT,
    value_boolean       INTEGER CHECK (value_boolean IS NULL OR value_boolean IN (0,1)),
    value_json          TEXT,
    unit                TEXT,
    derivation_details_json TEXT,
    CHECK (
      (detection_id IS NOT NULL) +
      (consensus_event_id IS NOT NULL) +
      (external_event_id IS NOT NULL) +
      (acoustic_reference_id IS NOT NULL) +
      (recording_id IS NOT NULL) +
      (entity_id IS NOT NULL) +
      (epoch_id IS NOT NULL) +
      (sequence_id IS NOT NULL) +
      (bout_id IS NOT NULL) = 1
    ),
    CHECK (
      (value_real IS NOT NULL) +
      (value_integer IS NOT NULL) +
      (value_text IS NOT NULL) +
      (value_boolean IS NOT NULL) +
      (value_json IS NOT NULL) = 1
    )
);

-- An analysis run is the response/QC profile; its child estimates keep
-- reference families and frequency scopes separate so contradictory evidence
-- cannot disappear into one opaque channel gain. Values are uncalibrated
-- summaries of the cited derived measurements, never correction factors.
CREATE TABLE channel_response_estimates (
    channel_response_estimate_id INTEGER PRIMARY KEY,
    analysis_run_id     INTEGER NOT NULL REFERENCES analysis_runs(analysis_run_id) ON DELETE CASCADE,
    recording_id        INTEGER NOT NULL REFERENCES recordings(recording_id) ON DELETE CASCADE,
    recording_channel_id INTEGER NOT NULL REFERENCES recording_channels(recording_channel_id) ON DELETE CASCADE,
    metric_definition_id INTEGER NOT NULL REFERENCES metric_definitions(metric_definition_id) ON DELETE RESTRICT,
    estimate_key        TEXT NOT NULL,
    reference_type      TEXT NOT NULL,
    aggregation_method  TEXT NOT NULL,
    aggregation_version TEXT NOT NULL,
    frequency_min_hz    REAL CHECK (frequency_min_hz IS NULL OR frequency_min_hz >= 0),
    frequency_max_hz    REAL CHECK (frequency_max_hz IS NULL OR frequency_max_hz >= 0),
    qc_status           TEXT NOT NULL CHECK (qc_status IN (
                            'ok',
                            'insufficient_evidence',
                            'divergent',
                            'source_qc_warning',
                            'not_comparable'
                        )),
    value_real          REAL,
    unit                TEXT,
    details_json        TEXT NOT NULL,
    notes               TEXT,
    CHECK (frequency_max_hz IS NULL OR frequency_min_hz IS NULL
           OR frequency_max_hz >= frequency_min_hz),
    UNIQUE(analysis_run_id, estimate_key)
);

-- RESTRICT is intentional: an estimate must be removed before any supporting
-- measurement can be deleted. Deleting the estimate run cascades through this
-- junction without touching its source evidence.
CREATE TABLE channel_response_estimate_sources (
    channel_response_estimate_id INTEGER NOT NULL REFERENCES channel_response_estimates(channel_response_estimate_id) ON DELETE CASCADE,
    derived_measurement_id INTEGER NOT NULL REFERENCES derived_measurements(derived_measurement_id) ON DELETE RESTRICT,
    PRIMARY KEY(channel_response_estimate_id, derived_measurement_id)
);

-- ============================================================================
-- 13. Integrity triggers for cross-table invariants SQLite cannot express as CHECKs
-- ============================================================================
--
-- CONVENTION: most cross-table scope guards below fire on INSERT only.
--
-- That is deliberate and it is repository-wide, not an oversight in any one
-- section: registration APIs insert rows or refuse, and none of them UPDATEs a
-- scope-bearing column, so the insert guard is the path that actually gets
-- exercised. A handful of invariants are reinforced with an explicit _update
-- twin where getting them wrong would silently change the MEANING of a stored
-- row rather than merely misfile it - the identity unresolved/candidate pairing,
-- placement dimensionality, acoustic reference channel and event scope,
-- derived-measurement channel scope, and the channel-response estimate scopes.
-- Each of those states its own reason above itself.
--
-- The consequence, which is worth knowing before relying on it: a direct UPDATE
-- issued outside the public API can still move an insert-guarded row across a
-- project boundary - for example repointing channel_placements.coordinate_system_id,
-- tracking_streams.coordinate_system_id, or tracking_identity_associations.entity_id
-- at another project's row. PRAGMA foreign_key_check will not see it, because no
-- foreign key is violated. Do not assume symmetry here; if a later phase starts
-- updating these columns, the guards it depends on must be added with it.

-- 'unresolved' and a named candidate are mutually exclusive statements, and the
-- distinction is the whole point of the table: an unknown identity must never be
-- readable as a candidate, and a candidate must never hide as an unknown. SQLite
-- CHECK could express this within the row, but it is written as a trigger pair
-- so insert and update are guarded identically - without the update guard a row
-- could be inserted honestly and then have its entity cleared or set while its
-- state stayed behind.
CREATE TRIGGER trg_identity_association_unresolved
BEFORE INSERT ON tracking_identity_associations
FOR EACH ROW
WHEN (NEW.entity_id IS NULL) <> (NEW.assignment_state = 'unresolved')
BEGIN
    SELECT RAISE(ABORT, 'Identity association must name a candidate entity unless its assignment_state is unresolved');
END;

CREATE TRIGGER trg_identity_association_unresolved_update
BEFORE UPDATE ON tracking_identity_associations
FOR EACH ROW
WHEN (NEW.entity_id IS NULL) <> (NEW.assignment_state = 'unresolved')
BEGIN
    SELECT RAISE(ABORT, 'Identity association must name a candidate entity unless its assignment_state is unresolved');
END;

-- An association's candidate entity and its tracking stream must belong to one
-- project. Without this, a track could be associated with an animal from an
-- unrelated experiment and nothing would notice.
CREATE TRIGGER trg_identity_association_project_scope
BEFORE INSERT ON tracking_identity_associations
FOR EACH ROW
WHEN NEW.entity_id IS NOT NULL AND (
    SELECT es.project_id
    FROM external_streams es
    WHERE es.external_stream_id = NEW.external_stream_id
) <> (
    SELECT e.project_id
    FROM experimental_entities e
    WHERE e.entity_id = NEW.entity_id
)
BEGIN
    SELECT RAISE(ABORT, 'Identity association candidate entity belongs to a different project than the tracking stream');
END;

-- Optional channel scope narrows a recording-level reference; it cannot point
-- at a channel owned by another recording. Both insert and update are guarded so
-- direct SQL cannot create an invalid row after registration.
CREATE TRIGGER trg_acoustic_reference_channel_scope
BEFORE INSERT ON acoustic_references
FOR EACH ROW
WHEN NEW.recording_channel_id IS NOT NULL AND (
    SELECT rc.recording_id
    FROM recording_channels rc
    WHERE rc.recording_channel_id = NEW.recording_channel_id
) IS NOT NEW.recording_id
BEGIN
    SELECT RAISE(ABORT, 'Acoustic reference channel belongs to a different recording');
END;

CREATE TRIGGER trg_acoustic_reference_channel_scope_update
BEFORE UPDATE ON acoustic_references
FOR EACH ROW
WHEN NEW.recording_channel_id IS NOT NULL AND (
    SELECT rc.recording_id
    FROM recording_channels rc
    WHERE rc.recording_channel_id = NEW.recording_channel_id
) IS NOT NEW.recording_id
BEGIN
    SELECT RAISE(ABORT, 'Acoustic reference channel belongs to a different recording');
END;

-- A linked external event is source provenance for this reference and therefore
-- must come from a stream attached to the same recording. It remains a distinct
-- object: no anchor row is created or implied by this relationship.
CREATE TRIGGER trg_acoustic_reference_event_scope
BEFORE INSERT ON acoustic_references
FOR EACH ROW
WHEN NEW.external_event_id IS NOT NULL AND (
    SELECT es.recording_id
    FROM external_events ee
    JOIN external_streams es ON es.external_stream_id = ee.external_stream_id
    WHERE ee.external_event_id = NEW.external_event_id
) IS NOT NEW.recording_id
BEGIN
    SELECT RAISE(ABORT, 'Acoustic reference external event belongs to a different recording');
END;

CREATE TRIGGER trg_acoustic_reference_event_scope_update
BEFORE UPDATE ON acoustic_references
FOR EACH ROW
WHEN NEW.external_event_id IS NOT NULL AND (
    SELECT es.recording_id
    FROM external_events ee
    JOIN external_streams es ON es.external_stream_id = ee.external_stream_id
    WHERE ee.external_event_id = NEW.external_event_id
) IS NOT NEW.recording_id
BEGIN
    SELECT RAISE(ABORT, 'Acoustic reference external event belongs to a different recording');
END;

-- A recording channel qualifies derived evidence but does not count as the
-- evidence target. Whenever the selected target has a recording identity, the
-- qualifier must name a channel belonging to that same recording.
CREATE TRIGGER trg_derived_measurement_channel_scope
BEFORE INSERT ON derived_measurements
FOR EACH ROW
WHEN NEW.recording_channel_id IS NOT NULL
 AND COALESCE(
    (SELECT ar.recording_id FROM acoustic_references ar
     WHERE ar.acoustic_reference_id=NEW.acoustic_reference_id),
    NEW.recording_id,
    (SELECT d.recording_id FROM detections d WHERE d.detection_id=NEW.detection_id),
    (SELECT ce.recording_id FROM consensus_events ce WHERE ce.consensus_event_id=NEW.consensus_event_id),
    (SELECT es.recording_id FROM external_events ee
     JOIN external_streams es ON es.external_stream_id=ee.external_stream_id
     WHERE ee.external_event_id=NEW.external_event_id),
    (SELECT re.recording_id FROM recording_epochs re WHERE re.epoch_id=NEW.epoch_id),
    (SELECT s.recording_id FROM sequences s WHERE s.sequence_id=NEW.sequence_id),
    (SELECT s.recording_id FROM bouts b JOIN sequences s ON s.sequence_id=b.sequence_id
     WHERE b.bout_id=NEW.bout_id)
 ) IS NOT NULL
 AND (SELECT rc.recording_id FROM recording_channels rc
      WHERE rc.recording_channel_id=NEW.recording_channel_id) IS NOT COALESCE(
    (SELECT ar.recording_id FROM acoustic_references ar
     WHERE ar.acoustic_reference_id=NEW.acoustic_reference_id),
    NEW.recording_id,
    (SELECT d.recording_id FROM detections d WHERE d.detection_id=NEW.detection_id),
    (SELECT ce.recording_id FROM consensus_events ce WHERE ce.consensus_event_id=NEW.consensus_event_id),
    (SELECT es.recording_id FROM external_events ee
     JOIN external_streams es ON es.external_stream_id=ee.external_stream_id
     WHERE ee.external_event_id=NEW.external_event_id),
    (SELECT re.recording_id FROM recording_epochs re WHERE re.epoch_id=NEW.epoch_id),
    (SELECT s.recording_id FROM sequences s WHERE s.sequence_id=NEW.sequence_id),
    (SELECT s.recording_id FROM bouts b JOIN sequences s ON s.sequence_id=b.sequence_id
     WHERE b.bout_id=NEW.bout_id)
 )
BEGIN
    SELECT RAISE(ABORT, 'Derived measurement channel belongs to a different recording than its target');
END;

CREATE TRIGGER trg_derived_measurement_channel_scope_update
BEFORE UPDATE ON derived_measurements
FOR EACH ROW
WHEN NEW.recording_channel_id IS NOT NULL
 AND COALESCE(
    (SELECT ar.recording_id FROM acoustic_references ar
     WHERE ar.acoustic_reference_id=NEW.acoustic_reference_id),
    NEW.recording_id,
    (SELECT d.recording_id FROM detections d WHERE d.detection_id=NEW.detection_id),
    (SELECT ce.recording_id FROM consensus_events ce WHERE ce.consensus_event_id=NEW.consensus_event_id),
    (SELECT es.recording_id FROM external_events ee
     JOIN external_streams es ON es.external_stream_id=ee.external_stream_id
     WHERE ee.external_event_id=NEW.external_event_id),
    (SELECT re.recording_id FROM recording_epochs re WHERE re.epoch_id=NEW.epoch_id),
    (SELECT s.recording_id FROM sequences s WHERE s.sequence_id=NEW.sequence_id),
    (SELECT s.recording_id FROM bouts b JOIN sequences s ON s.sequence_id=b.sequence_id
     WHERE b.bout_id=NEW.bout_id)
 ) IS NOT NULL
 AND (SELECT rc.recording_id FROM recording_channels rc
      WHERE rc.recording_channel_id=NEW.recording_channel_id) IS NOT COALESCE(
    (SELECT ar.recording_id FROM acoustic_references ar
     WHERE ar.acoustic_reference_id=NEW.acoustic_reference_id),
    NEW.recording_id,
    (SELECT d.recording_id FROM detections d WHERE d.detection_id=NEW.detection_id),
    (SELECT ce.recording_id FROM consensus_events ce WHERE ce.consensus_event_id=NEW.consensus_event_id),
    (SELECT es.recording_id FROM external_events ee
     JOIN external_streams es ON es.external_stream_id=ee.external_stream_id
     WHERE ee.external_event_id=NEW.external_event_id),
    (SELECT re.recording_id FROM recording_epochs re WHERE re.epoch_id=NEW.epoch_id),
    (SELECT s.recording_id FROM sequences s WHERE s.sequence_id=NEW.sequence_id),
    (SELECT s.recording_id FROM bouts b JOIN sequences s ON s.sequence_id=b.sequence_id
     WHERE b.bout_id=NEW.bout_id)
 )
BEGIN
    SELECT RAISE(ABORT, 'Derived measurement channel belongs to a different recording than its target');
END;

CREATE TRIGGER trg_channel_response_estimate_channel_scope
BEFORE INSERT ON channel_response_estimates
FOR EACH ROW
WHEN (SELECT rc.recording_id FROM recording_channels rc
      WHERE rc.recording_channel_id=NEW.recording_channel_id) IS NOT NEW.recording_id
BEGIN
    SELECT RAISE(ABORT, 'Channel-response estimate channel belongs to a different recording');
END;

CREATE TRIGGER trg_channel_response_estimate_channel_scope_update
BEFORE UPDATE ON channel_response_estimates
FOR EACH ROW
WHEN (SELECT rc.recording_id FROM recording_channels rc
      WHERE rc.recording_channel_id=NEW.recording_channel_id) IS NOT NEW.recording_id
BEGIN
    SELECT RAISE(ABORT, 'Channel-response estimate channel belongs to a different recording');
END;

-- One response-profile analysis run describes one recording. This keeps the
-- run-level QC/status vocabulary unambiguous.
CREATE TRIGGER trg_channel_response_estimate_run_recording_scope
BEFORE INSERT ON channel_response_estimates
FOR EACH ROW
WHEN EXISTS (
    SELECT 1 FROM channel_response_estimates cre
    WHERE cre.analysis_run_id=NEW.analysis_run_id
      AND cre.recording_id<>NEW.recording_id
)
BEGIN
    SELECT RAISE(ABORT, 'Channel-response profile run cannot span recordings');
END;

-- A supporting row must be the same metric, recording, channel, reference
-- family, and frequency scope as the estimate it supports.
CREATE TRIGGER trg_channel_response_estimate_source_scope
BEFORE INSERT ON channel_response_estimate_sources
FOR EACH ROW
WHEN NOT EXISTS (
    SELECT 1
    FROM channel_response_estimates cre
    JOIN derived_measurements dm
      ON dm.derived_measurement_id=NEW.derived_measurement_id
    JOIN acoustic_references ar
      ON ar.acoustic_reference_id=dm.acoustic_reference_id
    WHERE cre.channel_response_estimate_id=NEW.channel_response_estimate_id
      AND ar.recording_id=cre.recording_id
      AND dm.recording_channel_id=cre.recording_channel_id
      AND dm.metric_definition_id=cre.metric_definition_id
      AND ar.reference_type=cre.reference_type
      AND ar.frequency_min_hz IS cre.frequency_min_hz
      AND ar.frequency_max_hz IS cre.frequency_max_hz
)
BEGIN
    SELECT RAISE(ABORT, 'Channel-response estimate source is incompatible with the estimate scope');
END;

CREATE TRIGGER trg_channel_response_estimate_source_scope_update
BEFORE UPDATE ON channel_response_estimate_sources
FOR EACH ROW
WHEN NOT EXISTS (
    SELECT 1
    FROM channel_response_estimates cre
    JOIN derived_measurements dm
      ON dm.derived_measurement_id=NEW.derived_measurement_id
    JOIN acoustic_references ar
      ON ar.acoustic_reference_id=dm.acoustic_reference_id
    WHERE cre.channel_response_estimate_id=NEW.channel_response_estimate_id
      AND ar.recording_id=cre.recording_id
      AND dm.recording_channel_id=cre.recording_channel_id
      AND dm.metric_definition_id=cre.metric_definition_id
      AND ar.reference_type=cre.reference_type
      AND ar.frequency_min_hz IS cre.frequency_min_hz
      AND ar.frequency_max_hz IS cre.frequency_max_hz
)
BEGIN
    SELECT RAISE(ABORT, 'Channel-response estimate source is incompatible with the estimate scope');
END;

-- Updating an estimate cannot invalidate sources already linked to it.
CREATE TRIGGER trg_channel_response_estimate_scope_update
BEFORE UPDATE ON channel_response_estimates
FOR EACH ROW
WHEN EXISTS (
    SELECT 1
    FROM channel_response_estimate_sources cres
    JOIN derived_measurements dm ON dm.derived_measurement_id=cres.derived_measurement_id
    JOIN acoustic_references ar ON ar.acoustic_reference_id=dm.acoustic_reference_id
    WHERE cres.channel_response_estimate_id=OLD.channel_response_estimate_id
      AND (ar.recording_id IS NOT NEW.recording_id
       OR dm.recording_channel_id IS NOT NEW.recording_channel_id
       OR dm.metric_definition_id IS NOT NEW.metric_definition_id
       OR ar.reference_type IS NOT NEW.reference_type
       OR ar.frequency_min_hz IS NOT NEW.frequency_min_hz
       OR ar.frequency_max_hz IS NOT NEW.frequency_max_hz)
)
BEGIN
    SELECT RAISE(ABORT, 'Channel-response estimate update would invalidate supporting evidence');
END;

-- A tracking stream and the coordinate system it cites must belong to one
-- project. The stream carries project_id directly, so this is the same class of
-- guard as trg_channel_placement_project_scope: without it, a tracking stream
-- could cite a frame declared for an unrelated project and the two would look
-- compatible to any check that only compares identifiers.
CREATE TRIGGER trg_tracking_stream_project_scope
BEFORE INSERT ON tracking_streams
FOR EACH ROW
WHEN (
    SELECT es.project_id
    FROM external_streams es
    WHERE es.external_stream_id = NEW.external_stream_id
) <> (
    SELECT cs.project_id
    FROM coordinate_systems cs
    WHERE cs.coordinate_system_id = NEW.coordinate_system_id
)
BEGIN
    SELECT RAISE(ABORT, 'Tracking stream coordinate system belongs to a different project than the stream');
END;

-- The subtype is only meaningful over a stream declared as tracking. Without
-- this, an event stream could acquire tracking facts it has no samples for.
CREATE TRIGGER trg_tracking_stream_kind
BEFORE INSERT ON tracking_streams
FOR EACH ROW
WHEN (
    SELECT es.stream_kind
    FROM external_streams es
    WHERE es.external_stream_id = NEW.external_stream_id
) <> 'tracking'
BEGIN
    SELECT RAISE(ABORT, 'Tracking stream subtype requires its external stream to declare stream_kind tracking');
END;

-- A z coordinate is meaningful only under a 3-dimensional frame. Expressed as a
-- trigger rather than a CHECK because the dimensionality lives on another table
-- and SQLite CHECK constraints cannot reference one.
--
-- Insert and update are both guarded: without the update trigger, a row could be
-- inserted legally and then given a z, or its frame repointed at a 2D system,
-- reaching exactly the state the insert guard exists to prevent.
CREATE TRIGGER trg_channel_placement_dimensionality
BEFORE INSERT ON channel_placements
FOR EACH ROW
WHEN NEW.position_z IS NOT NULL AND (
    SELECT cs.dimensionality
    FROM coordinate_systems cs
    WHERE cs.coordinate_system_id = NEW.coordinate_system_id
) <> 3
BEGIN
    SELECT RAISE(ABORT, 'Channel placement declares a z coordinate under a coordinate system that is not 3-dimensional');
END;

CREATE TRIGGER trg_channel_placement_dimensionality_update
BEFORE UPDATE ON channel_placements
FOR EACH ROW
WHEN NEW.position_z IS NOT NULL AND (
    SELECT cs.dimensionality
    FROM coordinate_systems cs
    WHERE cs.coordinate_system_id = NEW.coordinate_system_id
) <> 3
BEGIN
    SELECT RAISE(ABORT, 'Channel placement declares a z coordinate under a coordinate system that is not 3-dimensional');
END;

-- A placement and the coordinate system it cites must belong to one project.
-- The channel reaches its project through its recording; without this, a
-- placement could cite a frame declared for an unrelated project.
CREATE TRIGGER trg_channel_placement_project_scope
BEFORE INSERT ON channel_placements
FOR EACH ROW
WHEN (
    SELECT r.project_id
    FROM recording_channels rc
    JOIN recordings r ON r.recording_id = rc.recording_id
    WHERE rc.recording_channel_id = NEW.recording_channel_id
) <> (
    SELECT cs.project_id
    FROM coordinate_systems cs
    WHERE cs.coordinate_system_id = NEW.coordinate_system_id
)
BEGIN
    SELECT RAISE(ABORT, 'Channel placement coordinate system belongs to a different project than the recording channel');
END;

-- Every detection's recording must be an input to its extraction run.
CREATE TRIGGER trg_detection_requires_run_input
BEFORE INSERT ON detections
FOR EACH ROW
WHEN NOT EXISTS (
    SELECT 1
    FROM extraction_run_inputs eri
    WHERE eri.extraction_run_id = NEW.extraction_run_id
      AND eri.recording_id = NEW.recording_id
)
BEGIN
    SELECT RAISE(ABORT, 'Detection recording is not registered as an input to the extraction run');
END;

-- Candidate detections must come from the stated recording and from distinct runs.
CREATE TRIGGER trg_candidate_pair_recording_and_runs
BEFORE INSERT ON candidate_pairs
FOR EACH ROW
WHEN (
    (SELECT recording_id FROM detections WHERE detection_id = NEW.detection_a_id) <> NEW.recording_id
    OR
    (SELECT recording_id FROM detections WHERE detection_id = NEW.detection_b_id) <> NEW.recording_id
    OR
    (SELECT extraction_run_id FROM detections WHERE detection_id = NEW.detection_a_id) =
    (SELECT extraction_run_id FROM detections WHERE detection_id = NEW.detection_b_id)
)
BEGIN
    SELECT RAISE(ABORT, 'Candidate pair must link detections from the stated recording and distinct extraction runs');
END;

CREATE TRIGGER trg_match_member_recording
BEFORE INSERT ON match_group_members
FOR EACH ROW
WHEN (
    SELECT d.recording_id <> mg.recording_id
    FROM detections d, match_groups mg
    WHERE d.detection_id = NEW.detection_id
      AND mg.match_group_id = NEW.match_group_id
)
BEGIN
    SELECT RAISE(ABORT, 'Match-group member recording does not match match-group recording');
END;

-- A match group partitions only detections from its analysis inputs, and a
-- detection may occur in only one group of a given analysis.
CREATE TRIGGER trg_match_member_analysis_partition
BEFORE INSERT ON match_group_members
FOR EACH ROW
WHEN NOT EXISTS (
    SELECT 1
    FROM match_groups mg
    JOIN detections d ON d.detection_id = NEW.detection_id
    JOIN analysis_run_extraction_inputs arei
      ON arei.analysis_run_id = mg.analysis_run_id
     AND arei.extraction_run_id = d.extraction_run_id
    WHERE mg.match_group_id = NEW.match_group_id
)
OR EXISTS (
    SELECT 1
    FROM match_groups target
    JOIN match_groups existing
      ON existing.analysis_run_id = target.analysis_run_id
    JOIN match_group_members member
      ON member.match_group_id = existing.match_group_id
    WHERE target.match_group_id = NEW.match_group_id
      AND existing.match_group_id <> NEW.match_group_id
      AND member.detection_id = NEW.detection_id
)
BEGIN
    SELECT RAISE(ABORT, 'Match-group member is outside the analysis inputs or already assigned in this analysis');
END;

CREATE TRIGGER trg_consensus_group_scope
BEFORE INSERT ON consensus_events
FOR EACH ROW
WHEN NEW.match_group_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM match_groups mg
    WHERE mg.match_group_id = NEW.match_group_id
      AND mg.analysis_run_id = NEW.analysis_run_id
      AND mg.recording_id = NEW.recording_id
)
BEGIN
    SELECT RAISE(ABORT, 'Consensus event group does not match its analysis and recording');
END;

CREATE TRIGGER trg_consensus_member_recording
BEFORE INSERT ON consensus_event_members
FOR EACH ROW
WHEN (
    SELECT d.recording_id <> ce.recording_id
    FROM detections d, consensus_events ce
    WHERE d.detection_id = NEW.detection_id
      AND ce.consensus_event_id = NEW.consensus_event_id
)
BEGIN
    SELECT RAISE(ABORT, 'Consensus-event member recording does not match consensus-event recording');
END;

CREATE TRIGGER trg_consensus_member_group_membership
BEFORE INSERT ON consensus_event_members
FOR EACH ROW
WHEN EXISTS (
    SELECT 1 FROM consensus_events ce
    WHERE ce.consensus_event_id = NEW.consensus_event_id
      AND ce.match_group_id IS NOT NULL
)
AND NOT EXISTS (
    SELECT 1
    FROM consensus_events ce
    JOIN match_group_members mgm ON mgm.match_group_id = ce.match_group_id
    WHERE ce.consensus_event_id = NEW.consensus_event_id
      AND mgm.detection_id = NEW.detection_id
)
BEGIN
    SELECT RAISE(ABORT, 'Consensus-event member is not a member of its match group');
END;

-- --------------------------------------------------------------------------
-- Arbitrary-N extractor-agreement invariants
-- --------------------------------------------------------------------------

-- A derived analysis and the analysis it consumes belong to one project.
CREATE TRIGGER trg_analysis_run_source_project_scope
BEFORE INSERT ON analysis_run_sources
FOR EACH ROW
WHEN (
    (SELECT project_id FROM analysis_runs WHERE analysis_run_id = NEW.analysis_run_id) <>
    (SELECT project_id FROM analysis_runs WHERE analysis_run_id = NEW.source_analysis_run_id)
)
BEGIN
    SELECT RAISE(ABORT, 'Analysis-run source belongs to a different project than the derived analysis');
END;

-- Agreement groups live only on an arbitrary-N agreement run, never grafted onto
-- a pairwise matching analysis, and their recording belongs to that run's project.
CREATE TRIGGER trg_agreement_group_run_scope
BEFORE INSERT ON agreement_groups
FOR EACH ROW
WHEN (
    (SELECT run_type FROM analysis_runs WHERE analysis_run_id = NEW.analysis_run_id)
        <> 'multi_extractor_agreement'
    OR
    (SELECT project_id FROM recordings WHERE recording_id = NEW.recording_id) <>
    (SELECT project_id FROM analysis_runs WHERE analysis_run_id = NEW.analysis_run_id)
)
BEGIN
    SELECT RAISE(ABORT, 'Agreement group requires a multi_extractor_agreement run and a recording in that project');
END;

CREATE TRIGGER trg_agreement_member_recording
BEFORE INSERT ON agreement_group_members
FOR EACH ROW
WHEN (
    SELECT d.recording_id <> ag.recording_id
    FROM detections d, agreement_groups ag
    WHERE d.detection_id = NEW.detection_id
      AND ag.agreement_group_id = NEW.agreement_group_id
)
BEGIN
    SELECT RAISE(ABORT, 'Agreement-group member recording does not match agreement-group recording');
END;

-- An agreement group partitions only detections from its own analysis inputs,
-- and a detection may occur in only one agreement group of a given agreement
-- run. The same detection may of course participate in several agreement runs.
CREATE TRIGGER trg_agreement_member_analysis_partition
BEFORE INSERT ON agreement_group_members
FOR EACH ROW
WHEN NOT EXISTS (
    SELECT 1
    FROM agreement_groups ag
    JOIN detections d ON d.detection_id = NEW.detection_id
    JOIN analysis_run_extraction_inputs arei
      ON arei.analysis_run_id = ag.analysis_run_id
     AND arei.extraction_run_id = d.extraction_run_id
    WHERE ag.agreement_group_id = NEW.agreement_group_id
)
OR EXISTS (
    SELECT 1
    FROM agreement_groups target
    JOIN agreement_groups existing
      ON existing.analysis_run_id = target.analysis_run_id
    JOIN agreement_group_members member
      ON member.agreement_group_id = existing.agreement_group_id
    WHERE target.agreement_group_id = NEW.agreement_group_id
      AND existing.agreement_group_id <> NEW.agreement_group_id
      AND member.detection_id = NEW.detection_id
)
BEGIN
    SELECT RAISE(ABORT, 'Agreement-group member is outside the analysis inputs or already assigned in this agreement run');
END;

-- A supporting edge must come from a declared source analysis, describe the same
-- recording, and join two detections that are both members of the group it
-- supports. Nothing here consults feature support or consilience status.
CREATE TRIGGER trg_agreement_supporting_edge_scope
BEFORE INSERT ON agreement_supporting_edges
FOR EACH ROW
WHEN NOT EXISTS (
    SELECT 1
    FROM agreement_groups ag
    JOIN candidate_pairs cp ON cp.candidate_pair_id = NEW.candidate_pair_id
    JOIN analysis_run_sources ars
      ON ars.analysis_run_id = ag.analysis_run_id
     AND ars.source_analysis_run_id = cp.analysis_run_id
    WHERE ag.agreement_group_id = NEW.agreement_group_id
      AND cp.recording_id = ag.recording_id
)
OR NOT EXISTS (
    SELECT 1
    FROM candidate_pairs cp
    JOIN agreement_group_members a
      ON a.agreement_group_id = NEW.agreement_group_id
     AND a.detection_id = cp.detection_a_id
    JOIN agreement_group_members b
      ON b.agreement_group_id = NEW.agreement_group_id
     AND b.detection_id = cp.detection_b_id
    WHERE cp.candidate_pair_id = NEW.candidate_pair_id
)
BEGIN
    SELECT RAISE(ABORT, 'Agreement supporting edge is outside its declared source analyses, recording, or group membership');
END;

-- Classification assignments must involve a detection from the classification run's
-- parent extraction run, and the class must belong to the same classification run.
CREATE TRIGGER trg_classification_assignment_scope
BEFORE INSERT ON classification_assignments
FOR EACH ROW
WHEN (
    (SELECT extraction_run_id FROM detections WHERE detection_id = NEW.detection_id) <>
    (SELECT parent_extraction_run_id FROM classification_runs WHERE classification_run_id = NEW.classification_run_id)
    OR
    (SELECT classification_run_id FROM classification_classes WHERE classification_class_id = NEW.classification_class_id) <>
    NEW.classification_run_id
)
BEGIN
    SELECT RAISE(ABORT, 'Classification assignment is outside its extraction/classification run scope');
END;

-- --------------------------------------------------------------------------
-- Temporal-alignment invariants
-- --------------------------------------------------------------------------

-- target_timebase_id on a pairwise transform is a convenience copy of the parent
-- set's reference. Allowing it to disagree would create two answers to "what is
-- this fit expressed in".
CREATE TRIGGER trg_alignment_run_target_is_set_reference
BEFORE INSERT ON time_alignment_runs
FOR EACH ROW
WHEN NEW.target_timebase_id <> (
    SELECT reference_timebase_id FROM alignment_sets
    WHERE alignment_set_id = NEW.alignment_set_id
)
BEGIN
    SELECT RAISE(ABORT, 'Alignment run target timebase must equal its alignment set reference timebase');
END;

CREATE TRIGGER trg_alignment_run_target_is_set_reference_update
BEFORE UPDATE ON time_alignment_runs
FOR EACH ROW
WHEN NEW.target_timebase_id <> (
    SELECT reference_timebase_id FROM alignment_sets
    WHERE alignment_set_id = NEW.alignment_set_id
)
BEGIN
    SELECT RAISE(ABORT, 'Alignment run target timebase must equal its alignment set reference timebase');
END;

-- A breakpoint is only meaningful for a transform that declares a piecewise model.
-- Without this, an offset or affine run could accumulate segmentation it will never
-- use, and a later reader could not tell which runs were actually piecewise.
CREATE TRIGGER trg_alignment_breakpoint_requires_piecewise
BEFORE INSERT ON alignment_run_breakpoints
FOR EACH ROW
WHEN (
    SELECT method FROM time_alignment_runs
    WHERE alignment_run_id = NEW.alignment_run_id
) <> 'piecewise_affine'
BEGIN
    SELECT RAISE(ABORT, 'Declared breakpoints require a piecewise_affine transform');
END;

-- The same state is reachable by moving a run off piecewise_affine after its
-- breakpoints exist, so the update path is guarded too rather than left to
-- convention.
CREATE TRIGGER trg_alignment_run_method_keeps_breakpoints
BEFORE UPDATE ON time_alignment_runs
FOR EACH ROW
WHEN NEW.method <> 'piecewise_affine' AND EXISTS (
    SELECT 1 FROM alignment_run_breakpoints
    WHERE alignment_run_id = NEW.alignment_run_id
)
BEGIN
    SELECT RAISE(ABORT, 'Transform declares breakpoints, so its method must remain piecewise_affine');
END;

-- An anchor observation that names an external event must name one recorded on the
-- same clock the observation claims to be on.
CREATE TRIGGER trg_anchor_observation_event_timebase
BEFORE INSERT ON alignment_anchor_observations
FOR EACH ROW
WHEN NEW.external_event_id IS NOT NULL AND NEW.timebase_id <> (
    SELECT es.timebase_id
    FROM external_events ee
    JOIN external_streams es ON es.external_stream_id = ee.external_stream_id
    WHERE ee.external_event_id = NEW.external_event_id
)
BEGIN
    SELECT RAISE(ABORT, 'Anchor observation event belongs to a stream on a different timebase');
END;

-- Identity evidence qualifies an anchor the fitter must treat as identity-
-- dependent. Attaching it to an observation that does not declare that class would
-- let visual-identity uncertainty sit beside a device-level anchor, where nothing
-- would ever weigh it.
CREATE TRIGGER trg_anchor_identity_evidence_requires_class
BEFORE INSERT ON alignment_anchor_identity_evidence
FOR EACH ROW
WHEN IFNULL((
    SELECT evidence_class FROM alignment_anchor_observations
    WHERE anchor_observation_id = NEW.anchor_observation_id
), '') <> 'identity_dependent'
BEGIN
    SELECT RAISE(ABORT, 'Anchor identity evidence requires an observation declared identity_dependent');
END;

-- Guarded on update as well: reclassifying an observation away from
-- identity_dependent while its evidence remains would strand that evidence in
-- exactly the state the insert guard refuses.
CREATE TRIGGER trg_anchor_observation_evidence_class_update
BEFORE UPDATE ON alignment_anchor_observations
FOR EACH ROW
WHEN IFNULL(NEW.evidence_class, '') <> 'identity_dependent' AND EXISTS (
    SELECT 1 FROM alignment_anchor_identity_evidence
    WHERE anchor_observation_id = NEW.anchor_observation_id
)
BEGIN
    SELECT RAISE(ABORT, 'Observation carries identity evidence, so its evidence_class must remain identity_dependent');
END;

-- A residual pairs two observations of the same logical anchor, taken on the two
-- clocks its transform actually relates, inside the same alignment set.
CREATE TRIGGER trg_anchor_residual_scope
BEFORE INSERT ON alignment_anchor_residuals
FOR EACH ROW
WHEN (
    (SELECT alignment_anchor_id FROM alignment_anchor_observations
     WHERE anchor_observation_id = NEW.source_observation_id) <> NEW.alignment_anchor_id
    OR
    (SELECT alignment_anchor_id FROM alignment_anchor_observations
     WHERE anchor_observation_id = NEW.reference_observation_id) <> NEW.alignment_anchor_id
    OR
    (SELECT alignment_set_id FROM alignment_anchors
     WHERE alignment_anchor_id = NEW.alignment_anchor_id) <>
    (SELECT alignment_set_id FROM time_alignment_runs
     WHERE alignment_run_id = NEW.alignment_run_id)
    OR
    (SELECT timebase_id FROM alignment_anchor_observations
     WHERE anchor_observation_id = NEW.source_observation_id) <>
    (SELECT source_timebase_id FROM time_alignment_runs
     WHERE alignment_run_id = NEW.alignment_run_id)
    OR
    (SELECT timebase_id FROM alignment_anchor_observations
     WHERE anchor_observation_id = NEW.reference_observation_id) <>
    (SELECT target_timebase_id FROM time_alignment_runs
     WHERE alignment_run_id = NEW.alignment_run_id)
)
BEGIN
    SELECT RAISE(ABORT, 'Anchor residual pairs observations outside its run, anchor, or timebases');
END;

-- A stream's coverage and its events are stated in that stream's own clock, so an
-- alignment set's reference must be a clock something in the set actually uses.
-- The set's recording, when named, must own the reference or be the recording the
-- reference belongs to.
CREATE TRIGGER trg_alignment_set_reference_scope
BEFORE INSERT ON alignment_sets
FOR EACH ROW
WHEN NEW.recording_id IS NOT NULL AND (
    SELECT project_id FROM timebases WHERE timebase_id = NEW.reference_timebase_id
) <> (
    SELECT project_id FROM recordings WHERE recording_id = NEW.recording_id
)
BEGIN
    SELECT RAISE(ABORT, 'Alignment set reference timebase belongs to a different project than its recording');
END;

-- ============================================================================
-- 14. Analysis-ready views
-- ============================================================================

-- Core call/detection view without multiplying rows by experimental participants.
CREATE VIEW v_detection_core AS
SELECT
    d.detection_id,
    d.recording_id,
    d.extraction_run_id,
    p.project_key,
    r.native_recording_id,
    sf.relative_path AS recording_relative_path,
    e.extractor_name,
    ev.version_label AS extractor_version,
    er.run_key AS extraction_run_key,
    d.native_event_id,
    d.event_subtype,
    d.start_time_s,
    d.end_time_s,
    (d.end_time_s - d.start_time_s) AS duration_s,
    d.timing_basis,
    d.detection_score
FROM detections d
JOIN extraction_runs er ON er.extraction_run_id = d.extraction_run_id
JOIN extractor_versions ev ON ev.extractor_version_id = er.extractor_version_id
JOIN extractors e ON e.extractor_id = ev.extractor_id
JOIN recordings r ON r.recording_id = d.recording_id
JOIN projects p ON p.project_id = r.project_id
JOIN source_files sf ON sf.source_file_id = r.source_file_id;

-- Long experimental context. One recording may intentionally have many rows here.
CREATE VIEW v_recording_entity_context AS
SELECT
    r.recording_id,
    p.project_key,
    sf.source_file_id,
    sf.path_or_uri AS source_path_or_uri,
    sf.relative_path AS source_relative_path,
    sf.filename AS source_filename,
    r.native_recording_id,
    et.native_name AS entity_type,
    et.canonical_role,
    ee.entity_id,
    ee.native_id AS entity_native_id,
    ee.display_label,
    rel.link_type,
    rel.role_label,
    rel.start_time_s,
    rel.end_time_s
FROM recordings r
JOIN projects p ON p.project_id = r.project_id
JOIN source_files sf ON sf.source_file_id = r.source_file_id
JOIN recording_entity_links rel ON rel.recording_id = r.recording_id
JOIN experimental_entities ee ON ee.entity_id = rel.entity_id
JOIN entity_types et ON et.entity_type_id = ee.entity_type_id;

CREATE VIEW v_event_measurements_long AS
SELECT
    em.event_measurement_id,
    em.detection_id,
    d.extraction_run_id,
    d.recording_id,
    xf.native_name,
    xf.native_unit AS feature_native_unit,
    xf.derivation_stage,
    xf.operational_variant AS feature_operational_variant,
    cf.canonical_name,
    em.native_raw_token,
    em.native_value_real,
    em.native_value_integer,
    em.native_value_text,
    em.native_value_boolean,
    em.native_unit,
    em.canonical_value_real,
    em.canonical_value_integer,
    em.canonical_value_text,
    em.canonical_value_boolean,
    em.canonical_unit,
    em.transform_key,
    em.operational_variant
FROM event_measurements em
JOIN detections d ON d.detection_id = em.detection_id
JOIN extractor_features xf ON xf.extractor_feature_id = em.extractor_feature_id
LEFT JOIN canonical_features cf ON cf.canonical_feature_id = em.canonical_feature_id;

CREATE VIEW v_match_group_members AS
SELECT
    mg.match_group_id,
    mg.analysis_run_id,
    mg.recording_id,
    mg.match_type,
    mg.ambiguity_status,
    mg.match_score,
    mgm.detection_id,
    e.extractor_name,
    ev.version_label AS extractor_version,
    er.run_key AS extraction_run_key,
    d.native_event_id,
    d.start_time_s,
    d.end_time_s
FROM match_groups mg
JOIN match_group_members mgm ON mgm.match_group_id = mg.match_group_id
JOIN detections d ON d.detection_id = mgm.detection_id
JOIN extraction_runs er ON er.extraction_run_id = d.extraction_run_id
JOIN extractor_versions ev ON ev.extractor_version_id = er.extractor_version_id
JOIN extractors e ON e.extractor_id = ev.extractor_id;

-- Long-form arbitrary-N agreement membership. Native detections remain the
-- represented observations; the agreement group adds derived connectivity but
-- does not replace their run, extractor, native identity, or timing.
CREATE VIEW v_agreement_group_members AS
SELECT
    ag.agreement_group_id,
    ag.analysis_run_id,
    ar.run_key AS agreement_run_key,
    ag.recording_id,
    r.native_recording_id,
    ag.group_key,
    ag.derivation_method,
    agm.detection_id,
    agm.member_role,
    d.extraction_run_id,
    er.run_key AS extraction_run_key,
    e.extractor_id,
    e.extractor_key,
    e.extractor_name,
    ev.extractor_version_id,
    ev.version_label AS extractor_version,
    d.native_event_id,
    d.event_subtype,
    d.start_time_s,
    d.end_time_s,
    (d.end_time_s - d.start_time_s) AS duration_s
FROM agreement_groups ag
JOIN analysis_runs ar ON ar.analysis_run_id = ag.analysis_run_id
JOIN recordings r ON r.recording_id = ag.recording_id
JOIN agreement_group_members agm
  ON agm.agreement_group_id = ag.agreement_group_id
JOIN detections d ON d.detection_id = agm.detection_id
JOIN extraction_runs er ON er.extraction_run_id = d.extraction_run_id
JOIN extractor_versions ev ON ev.extractor_version_id = er.extractor_version_id
JOIN extractors e ON e.extractor_id = ev.extractor_id;

-- One row per exact stored support edge. Candidate-pair endpoint order remains
-- visible as the authority stored by the pairwise layer. Display keys are
-- independently oriented by stable extractor key (and by native selector for
-- the detection edge) so surrogate-id allocation cannot change them.
--
-- Pairwise topology is joined through both edge endpoints and the producing
-- analysis. A candidate-only source therefore yields NULL topology columns;
-- the convenience label reports no_group_materialized, which is absence rather
-- than ambiguity.
CREATE VIEW v_agreement_supporting_edges AS
WITH pairwise_topology AS (
    SELECT
        mg.analysis_run_id,
        mg.match_group_id,
        mg.match_type,
        mg.ambiguity_status,
        a.detection_id AS detection_a_id,
        b.detection_id AS detection_b_id
    FROM match_groups mg
    JOIN match_group_members a ON a.match_group_id = mg.match_group_id
    JOIN match_group_members b
      ON b.match_group_id = mg.match_group_id
     AND a.detection_id < b.detection_id
)
SELECT
    ase.agreement_supporting_edge_id,
    ag.agreement_group_id,
    ag.analysis_run_id,
    agreement_run.run_key AS agreement_run_key,
    ag.recording_id,
    ag.group_key,
    ase.candidate_pair_id,
    cp.analysis_run_id AS source_analysis_run_id,
    source_run.run_key AS source_analysis_run_key,
    cp.detection_a_id,
    cp.detection_b_id,
    da.extraction_run_id AS extraction_run_a_id,
    era.run_key AS extraction_run_a_key,
    ea.extractor_id AS extractor_a_id,
    ea.extractor_key AS extractor_a_key,
    ea.extractor_name AS extractor_a_name,
    eva.extractor_version_id AS extractor_version_a_id,
    eva.version_label AS extractor_a_version,
    da.native_event_id AS native_event_a_id,
    db.extraction_run_id AS extraction_run_b_id,
    erb.run_key AS extraction_run_b_key,
    eb.extractor_id AS extractor_b_id,
    eb.extractor_key AS extractor_b_key,
    eb.extractor_name AS extractor_b_name,
    evb.extractor_version_id AS extractor_version_b_id,
    evb.version_label AS extractor_b_version,
    db.native_event_id AS native_event_b_id,
    CASE WHEN ea.extractor_key < eb.extractor_key
         THEN ea.extractor_key || '--' || eb.extractor_key
         ELSE eb.extractor_key || '--' || ea.extractor_key
    END AS extractor_pair_key,
    CASE WHEN ea.extractor_key < eb.extractor_key
         THEN ea.extractor_name || ' -- ' || eb.extractor_name
         ELSE eb.extractor_name || ' -- ' || ea.extractor_name
    END AS extractor_pair_label,
    CASE WHEN era.run_key || '#' || IFNULL(da.native_event_id, '')
                   < erb.run_key || '#' || IFNULL(db.native_event_id, '')
         THEN era.run_key || '#' || IFNULL(da.native_event_id, '') || '--' ||
              erb.run_key || '#' || IFNULL(db.native_event_id, '')
         ELSE erb.run_key || '#' || IFNULL(db.native_event_id, '') || '--' ||
              era.run_key || '#' || IFNULL(da.native_event_id, '')
    END AS detection_edge_key,
    cp.temporal_overlap_s,
    cp.temporal_iou,
    cp.onset_difference_s,
    cp.offset_difference_s,
    cp.duration_difference_s,
    cp.candidate_score,
    cp.candidate_status,
    cp.details_json,
    pt.match_group_id AS pairwise_match_group_id,
    pt.match_type AS pairwise_match_type,
    pt.ambiguity_status AS pairwise_ambiguity_status,
    IFNULL(pt.match_type, 'no_group_materialized') AS pairwise_topology_label
FROM agreement_supporting_edges ase
JOIN agreement_groups ag ON ag.agreement_group_id = ase.agreement_group_id
JOIN analysis_runs agreement_run
  ON agreement_run.analysis_run_id = ag.analysis_run_id
JOIN candidate_pairs cp ON cp.candidate_pair_id = ase.candidate_pair_id
JOIN analysis_runs source_run ON source_run.analysis_run_id = cp.analysis_run_id
JOIN detections da ON da.detection_id = cp.detection_a_id
JOIN extraction_runs era ON era.extraction_run_id = da.extraction_run_id
JOIN extractor_versions eva ON eva.extractor_version_id = era.extractor_version_id
JOIN extractors ea ON ea.extractor_id = eva.extractor_id
JOIN detections db ON db.detection_id = cp.detection_b_id
JOIN extraction_runs erb ON erb.extraction_run_id = db.extraction_run_id
JOIN extractor_versions evb ON evb.extractor_version_id = erb.extractor_version_id
JOIN extractors eb ON eb.extractor_id = evb.extractor_id
LEFT JOIN pairwise_topology pt
  ON pt.analysis_run_id = cp.analysis_run_id
 AND pt.detection_a_id = cp.detection_a_id
 AND pt.detection_b_id = cp.detection_b_id;

-- One row per theoretically possible unordered extractor pair represented in an
-- agreement group. This is the coarse reduction: several exact detection edges
-- may support one row, but remain individually queryable above. Unsupported rows
-- remain present, so a missing pair is identifiable rather than merely counted.
-- Phase 1 agreement runs declare exactly one source analysis for every pair of
-- participating extraction runs. source_analysis_count and is_assessed expose
-- that fact without baking it into a stored summary.
CREATE VIEW v_agreement_extractor_pair_support AS
WITH represented_runs AS (
    SELECT DISTINCT
        agreement_group_id,
        analysis_run_id,
        agreement_run_key,
        recording_id,
        group_key,
        extraction_run_id,
        extraction_run_key,
        extractor_id,
        extractor_key,
        extractor_name,
        extractor_version_id,
        extractor_version
    FROM v_agreement_group_members
),
possible_pairs AS (
    SELECT
        a.agreement_group_id,
        a.analysis_run_id,
        a.agreement_run_key,
        a.recording_id,
        a.group_key,
        a.extraction_run_id AS extraction_run_a_id,
        a.extraction_run_key AS extraction_run_a_key,
        a.extractor_id AS extractor_a_id,
        a.extractor_key AS extractor_a_key,
        a.extractor_name AS extractor_a_name,
        a.extractor_version_id AS extractor_version_a_id,
        a.extractor_version AS extractor_a_version,
        b.extraction_run_id AS extraction_run_b_id,
        b.extraction_run_key AS extraction_run_b_key,
        b.extractor_id AS extractor_b_id,
        b.extractor_key AS extractor_b_key,
        b.extractor_name AS extractor_b_name,
        b.extractor_version_id AS extractor_version_b_id,
        b.extractor_version AS extractor_b_version,
        a.extractor_key || '--' || b.extractor_key AS extractor_pair_key,
        a.extractor_name || ' -- ' || b.extractor_name AS extractor_pair_label
    FROM represented_runs a
    JOIN represented_runs b
      ON b.agreement_group_id = a.agreement_group_id
     AND a.extractor_key < b.extractor_key
),
source_pair_coverage AS (
    SELECT
        ars.analysis_run_id,
        ars.source_analysis_run_id,
        source_run.run_key AS source_analysis_run_key,
        MIN(first_input.extraction_run_id, second_input.extraction_run_id)
            AS extraction_run_low_id,
        MAX(first_input.extraction_run_id, second_input.extraction_run_id)
            AS extraction_run_high_id
    FROM analysis_run_sources ars
    JOIN analysis_runs source_run
      ON source_run.analysis_run_id = ars.source_analysis_run_id
    JOIN analysis_run_extraction_inputs first_input
      ON first_input.analysis_run_id = ars.source_analysis_run_id
    JOIN analysis_run_extraction_inputs second_input
      ON second_input.analysis_run_id = ars.source_analysis_run_id
     AND first_input.extraction_run_id < second_input.extraction_run_id
),
assessed AS (
    SELECT
        pp.agreement_group_id,
        pp.extractor_pair_key,
        COUNT(spc.source_analysis_run_id) AS source_analysis_count,
        MIN(spc.source_analysis_run_id) AS source_analysis_run_id,
        MIN(spc.source_analysis_run_key) AS source_analysis_run_key
    FROM possible_pairs pp
    LEFT JOIN source_pair_coverage spc
      ON spc.analysis_run_id = pp.analysis_run_id
     AND spc.extraction_run_low_id =
         MIN(pp.extraction_run_a_id, pp.extraction_run_b_id)
     AND spc.extraction_run_high_id =
         MAX(pp.extraction_run_a_id, pp.extraction_run_b_id)
    GROUP BY pp.agreement_group_id, pp.extractor_pair_key
),
edge_support AS (
    SELECT
        agreement_group_id,
        extractor_pair_key,
        COUNT(*) AS support_edge_count
    FROM v_agreement_supporting_edges
    GROUP BY agreement_group_id, extractor_pair_key
)
SELECT
    pp.*,
    assessed.source_analysis_count,
    assessed.source_analysis_run_id,
    assessed.source_analysis_run_key,
    CASE WHEN assessed.source_analysis_count > 0 THEN 1 ELSE 0 END AS is_assessed,
    IFNULL(edge_support.support_edge_count, 0) AS support_edge_count,
    CASE WHEN IFNULL(edge_support.support_edge_count, 0) > 0 THEN 1 ELSE 0 END
        AS is_supported
FROM possible_pairs pp
JOIN assessed
  ON assessed.agreement_group_id = pp.agreement_group_id
 AND assessed.extractor_pair_key = pp.extractor_pair_key
LEFT JOIN edge_support
  ON edge_support.agreement_group_id = pp.agreement_group_id
 AND edge_support.extractor_pair_key = pp.extractor_pair_key;

-- Group-level query summary. Every value here is derived from long-form members,
-- exact edges, possible extractor pairs, and declared source analyses. In
-- particular, complete pair support, one-detection-per-extractor membership, and
-- unambiguous one-to-one topology are three independent dimensions.
CREATE VIEW v_agreement_group_summary AS
WITH member_rows AS (
    SELECT * FROM v_agreement_group_members
),
exact_edges AS (
    SELECT * FROM v_agreement_supporting_edges
),
pair_support AS (
    SELECT * FROM v_agreement_extractor_pair_support
),
member_counts AS (
    SELECT
        agreement_group_id,
        COUNT(*) AS member_count,
        COUNT(DISTINCT extraction_run_id) AS extraction_run_count,
        COUNT(DISTINCT extractor_id) AS extractor_count
    FROM member_rows
    GROUP BY agreement_group_id
),
extractor_sets AS (
    SELECT
        agreement_group_id,
        group_concat(extractor_key, '|') AS extractor_set_key,
        group_concat(extractor_name, ' | ') AS extractor_set_label,
        group_concat(extraction_run_key, '|') AS extraction_run_set_key
    FROM (
        SELECT DISTINCT
            agreement_group_id,
            extractor_key,
            extractor_name,
            extraction_run_key
        FROM member_rows
        ORDER BY agreement_group_id, extractor_key, extraction_run_key
    )
    GROUP BY agreement_group_id
),
edge_counts AS (
    SELECT
        agreement_group_id,
        COUNT(*) AS support_edge_count,
        SUM(CASE WHEN pairwise_match_type = 'one_to_one'
                      AND pairwise_ambiguity_status = 'unambiguous'
                 THEN 0 ELSE 1 END) AS non_clean_edge_count
    FROM exact_edges
    GROUP BY agreement_group_id
),
topology_patterns AS (
    SELECT
        agreement_group_id,
        group_concat(pairwise_topology_label, '|') AS pairwise_topology_pattern
    FROM (
        SELECT DISTINCT agreement_group_id, pairwise_topology_label
        FROM exact_edges
        ORDER BY agreement_group_id, pairwise_topology_label
    )
    GROUP BY agreement_group_id
),
ambiguous_topology_patterns AS (
    SELECT
        agreement_group_id,
        group_concat(pairwise_topology_label, '|')
            AS ambiguous_pairwise_topology_pattern
    FROM (
        SELECT DISTINCT agreement_group_id, pairwise_topology_label
        FROM exact_edges
        WHERE pairwise_topology_label IN
              ('one_to_many', 'many_to_one', 'many_to_many', 'ambiguous')
        ORDER BY agreement_group_id, pairwise_topology_label
    )
    GROUP BY agreement_group_id
),
pair_counts AS (
    SELECT
        agreement_group_id,
        COUNT(*) AS possible_extractor_pair_count,
        SUM(is_assessed) AS assessed_extractor_pair_count,
        SUM(is_supported) AS supported_extractor_pair_count
    FROM pair_support
    GROUP BY agreement_group_id
),
supported_patterns AS (
    SELECT
        agreement_group_id,
        group_concat(extractor_pair_key, '|') AS supported_extractor_pair_pattern,
        group_concat(extractor_pair_label, ';') AS supported_extractor_pair_label
    FROM (
        SELECT agreement_group_id, extractor_pair_key, extractor_pair_label
        FROM pair_support
        WHERE is_supported = 1
        ORDER BY agreement_group_id, extractor_pair_key
    )
    GROUP BY agreement_group_id
),
unsupported_patterns AS (
    SELECT
        agreement_group_id,
        group_concat(extractor_pair_key, '|') AS unsupported_extractor_pair_pattern,
        group_concat(extractor_pair_label, ';') AS unsupported_extractor_pair_label
    FROM (
        SELECT agreement_group_id, extractor_pair_key, extractor_pair_label
        FROM pair_support
        WHERE is_supported = 0
        ORDER BY agreement_group_id, extractor_pair_key
    )
    GROUP BY agreement_group_id
)
SELECT
    ag.agreement_group_id,
    ag.analysis_run_id,
    ar.run_key AS agreement_run_key,
    ag.recording_id,
    r.native_recording_id,
    ag.group_key,
    ag.derivation_method,
    mc.member_count,
    mc.extraction_run_count,
    mc.extractor_count,
    es.extractor_set_key,
    es.extractor_set_label,
    es.extraction_run_set_key,
    IFNULL(ec.support_edge_count, 0) AS support_edge_count,
    IFNULL(pc.supported_extractor_pair_count, 0)
        AS supported_extractor_pair_count,
    IFNULL(pc.possible_extractor_pair_count, 0)
        AS possible_extractor_pair_count,
    IFNULL(pc.assessed_extractor_pair_count, 0)
        AS assessed_extractor_pair_count,
    CASE WHEN IFNULL(pc.possible_extractor_pair_count, 0) > 0
         THEN 1.0 * pc.supported_extractor_pair_count /
              pc.possible_extractor_pair_count
         ELSE NULL
    END AS support_fraction,
    IFNULL(sp.supported_extractor_pair_pattern, '')
        AS supported_extractor_pair_pattern,
    IFNULL(sp.supported_extractor_pair_label, '')
        AS supported_extractor_pair_label,
    IFNULL(up.unsupported_extractor_pair_pattern, '')
        AS unsupported_extractor_pair_pattern,
    IFNULL(up.unsupported_extractor_pair_label, '')
        AS unsupported_extractor_pair_label,
    CASE WHEN IFNULL(pc.possible_extractor_pair_count, 0) > 0
               AND pc.supported_extractor_pair_count =
                   pc.possible_extractor_pair_count
         THEN 1 ELSE 0
    END AS is_extractor_pair_support_complete,
    CASE WHEN IFNULL(pc.possible_extractor_pair_count, 0) > 0
               AND pc.assessed_extractor_pair_count =
                   pc.possible_extractor_pair_count
         THEN 1 ELSE 0
    END AS is_pairwise_assessment_complete,
    CASE WHEN mc.member_count = mc.extractor_count THEN 1 ELSE 0 END
        AS is_one_detection_per_extractor,
    CASE WHEN IFNULL(ec.support_edge_count, 0) > 0
               AND ec.non_clean_edge_count = 0
         THEN 1 ELSE 0
    END AS is_unambiguous_one_to_one,
    IFNULL(tp.pairwise_topology_pattern, '') AS pairwise_topology_pattern,
    IFNULL(atp.ambiguous_pairwise_topology_pattern, '')
        AS ambiguous_pairwise_topology_pattern,
    CASE WHEN mc.member_count = 1 THEN 1 ELSE 0 END AS is_singleton,
    CASE WHEN mc.extractor_count = 1 THEN 1 ELSE 0 END AS is_extractor_unique
FROM agreement_groups ag
JOIN analysis_runs ar ON ar.analysis_run_id = ag.analysis_run_id
JOIN recordings r ON r.recording_id = ag.recording_id
JOIN member_counts mc ON mc.agreement_group_id = ag.agreement_group_id
JOIN extractor_sets es ON es.agreement_group_id = ag.agreement_group_id
LEFT JOIN edge_counts ec ON ec.agreement_group_id = ag.agreement_group_id
LEFT JOIN topology_patterns tp ON tp.agreement_group_id = ag.agreement_group_id
LEFT JOIN ambiguous_topology_patterns atp
  ON atp.agreement_group_id = ag.agreement_group_id
LEFT JOIN pair_counts pc ON pc.agreement_group_id = ag.agreement_group_id
LEFT JOIN supported_patterns sp ON sp.agreement_group_id = ag.agreement_group_id
LEFT JOIN unsupported_patterns up ON up.agreement_group_id = ag.agreement_group_id;

-- Registered cross-extractor feature comparability. This is the only defensible
-- route for comparing measurements across extractors: a shared canonical_name is
-- neither necessary nor sufficient. DeepSqueak's contour median and MUPET's
-- filterbank mean carry different canonical names and are reachable only through
-- equivalence_class plus this relationship; conversely, sharing an equivalence
-- class does not make a pair eligible, which is why relationship_type and
-- consilience_eligible are exposed verbatim and nothing is filtered here.
-- feature_a/feature_b order follows feature_relationships' ascending-id CHECK and
-- carries no extractor or directional meaning; consumers must orient themselves
-- by extractor_a_name / extractor_b_name.
CREATE VIEW v_cross_extractor_feature_pairs AS
SELECT
    fr.feature_relationship_id,
    fr.relationship_type,
    fr.consilience_eligible,
    fr.comparison_method,
    fr.unit_normalization,
    fr.default_role,
    fr.justification,
    a.extractor_feature_id AS feature_a_id,
    ea.extractor_name      AS extractor_a_name,
    eva.version_label      AS extractor_a_version,
    a.native_name          AS feature_a_native_name,
    a.native_unit          AS feature_a_native_unit,
    a.derivation_stage     AS feature_a_derivation_stage,
    a.operational_variant  AS feature_a_operational_variant,
    a.measurement_method   AS feature_a_measurement_method,
    a.native_definition    AS feature_a_native_definition,
    a.equivalence_class    AS feature_a_equivalence_class,
    cfa.canonical_name     AS feature_a_canonical_name,
    cfa.canonical_unit     AS feature_a_canonical_unit,
    cfa.feature_domain     AS feature_a_domain,
    b.extractor_feature_id AS feature_b_id,
    eb.extractor_name      AS extractor_b_name,
    evb.version_label      AS extractor_b_version,
    b.native_name          AS feature_b_native_name,
    b.native_unit          AS feature_b_native_unit,
    b.derivation_stage     AS feature_b_derivation_stage,
    b.operational_variant  AS feature_b_operational_variant,
    b.measurement_method   AS feature_b_measurement_method,
    b.native_definition    AS feature_b_native_definition,
    b.equivalence_class    AS feature_b_equivalence_class,
    cfb.canonical_name     AS feature_b_canonical_name,
    cfb.canonical_unit     AS feature_b_canonical_unit,
    cfb.feature_domain     AS feature_b_domain
FROM feature_relationships fr
JOIN extractor_features a ON a.extractor_feature_id = fr.feature_a_id
JOIN extractor_features b ON b.extractor_feature_id = fr.feature_b_id
JOIN extractor_versions eva ON eva.extractor_version_id = a.extractor_version_id
JOIN extractors ea ON ea.extractor_id = eva.extractor_id
JOIN extractor_versions evb ON evb.extractor_version_id = b.extractor_version_id
JOIN extractors eb ON eb.extractor_id = evb.extractor_id
LEFT JOIN feature_mappings fma ON fma.extractor_feature_id = a.extractor_feature_id
LEFT JOIN canonical_features cfa ON cfa.canonical_feature_id = fma.canonical_feature_id
LEFT JOIN feature_mappings fmb ON fmb.extractor_feature_id = b.extractor_feature_id
LEFT JOIN canonical_features cfb ON cfb.canonical_feature_id = fmb.canonical_feature_id
WHERE ea.extractor_id <> eb.extractor_id;

-- The same registered relationships, oriented per endpoint: exactly two rows per
-- cross-extractor relationship, one from each feature's point of view.
--
-- v_cross_extractor_feature_pairs answers "what is this pair?". Feature-support
-- capacity asks the other question - "which counterparts does this feature
-- have, in which extractors?" - and answering it from the pair view requires
-- checking both orientations every time, because feature_a/feature_b order
-- follows the ascending-id CHECK and carries no extractor meaning.
--
-- How much cross-extractor feature support is potentially available is a
-- property of this relationship graph, of consilience_eligible, of equivalence
-- class and operational variant, of unit compatibility, and of the active
-- versioned comparison policy. It is deliberately not a column on
-- extractor_features: the same native feature has different support capacity
-- depending on which extractor versions are being compared. Counts, fractions,
-- and convenience categories over these rows are query products for a chosen
-- extractor set, never stored properties.
--
-- Which equivalence classes count as primary temporal evidence rather than
-- independent support is a policy statement, so equivalence_class is exposed
-- verbatim and nothing is classified here. canonical_feature is deliberately
-- not joined: a feature may carry several canonical mappings across profile
-- versions, and fanning them out here would make counterpart counting wrong.
CREATE VIEW v_feature_relationship_endpoints AS
SELECT
    fr.feature_relationship_id,
    fr.relationship_type,
    fr.consilience_eligible,
    fr.comparison_method,
    fr.unit_normalization,
    fr.default_role,
    f.extractor_feature_id  AS feature_id,
    fx.extractor_id         AS extractor_id,
    fx.extractor_name       AS extractor_name,
    fv.extractor_version_id AS extractor_version_id,
    fv.version_label        AS extractor_version,
    f.native_name           AS feature_native_name,
    f.native_unit           AS feature_native_unit,
    f.equivalence_class     AS feature_equivalence_class,
    f.operational_variant   AS feature_operational_variant,
    f.derivation_stage      AS feature_derivation_stage,
    c.extractor_feature_id  AS counterpart_feature_id,
    cx.extractor_id         AS counterpart_extractor_id,
    cx.extractor_name       AS counterpart_extractor_name,
    cv.extractor_version_id AS counterpart_extractor_version_id,
    cv.version_label        AS counterpart_extractor_version,
    c.native_name           AS counterpart_native_name,
    c.native_unit           AS counterpart_native_unit,
    c.equivalence_class     AS counterpart_equivalence_class,
    c.operational_variant   AS counterpart_operational_variant,
    c.derivation_stage      AS counterpart_derivation_stage
FROM feature_relationships fr
JOIN extractor_features f ON f.extractor_feature_id = fr.feature_a_id
JOIN extractor_features c ON c.extractor_feature_id = fr.feature_b_id
JOIN extractor_versions fv ON fv.extractor_version_id = f.extractor_version_id
JOIN extractors fx ON fx.extractor_id = fv.extractor_id
JOIN extractor_versions cv ON cv.extractor_version_id = c.extractor_version_id
JOIN extractors cx ON cx.extractor_id = cv.extractor_id
WHERE fx.extractor_id <> cx.extractor_id
UNION ALL
SELECT
    fr.feature_relationship_id,
    fr.relationship_type,
    fr.consilience_eligible,
    fr.comparison_method,
    fr.unit_normalization,
    fr.default_role,
    f.extractor_feature_id  AS feature_id,
    fx.extractor_id         AS extractor_id,
    fx.extractor_name       AS extractor_name,
    fv.extractor_version_id AS extractor_version_id,
    fv.version_label        AS extractor_version,
    f.native_name           AS feature_native_name,
    f.native_unit           AS feature_native_unit,
    f.equivalence_class     AS feature_equivalence_class,
    f.operational_variant   AS feature_operational_variant,
    f.derivation_stage      AS feature_derivation_stage,
    c.extractor_feature_id  AS counterpart_feature_id,
    cx.extractor_id         AS counterpart_extractor_id,
    cx.extractor_name       AS counterpart_extractor_name,
    cv.extractor_version_id AS counterpart_extractor_version_id,
    cv.version_label        AS counterpart_extractor_version,
    c.native_name           AS counterpart_native_name,
    c.native_unit           AS counterpart_native_unit,
    c.equivalence_class     AS counterpart_equivalence_class,
    c.operational_variant   AS counterpart_operational_variant,
    c.derivation_stage      AS counterpart_derivation_stage
FROM feature_relationships fr
JOIN extractor_features f ON f.extractor_feature_id = fr.feature_b_id
JOIN extractor_features c ON c.extractor_feature_id = fr.feature_a_id
JOIN extractor_versions fv ON fv.extractor_version_id = f.extractor_version_id
JOIN extractors fx ON fx.extractor_id = fv.extractor_id
JOIN extractor_versions cv ON cv.extractor_version_id = c.extractor_version_id
JOIN extractors cx ON cx.extractor_id = cv.extractor_id
WHERE fx.extractor_id <> cx.extractor_id;

CREATE VIEW v_external_events_aligned AS
SELECT
    ee.external_event_id,
    es.external_stream_id,
    es.stream_name,
    es.stream_kind,
    es.modality,
    ee.event_type,
    ee.start_time_native,
    ee.end_time_native,
    aee.alignment_run_id,
    aee.target_timebase_id,
    aee.start_time_aligned_s,
    aee.end_time_aligned_s,
    aee.uncertainty_s,
    es.recording_id
FROM external_events ee
JOIN external_streams es ON es.external_stream_id = ee.external_stream_id
LEFT JOIN aligned_external_events aee ON aee.external_event_id = ee.external_event_id;

CREATE VIEW v_sequence_members AS
SELECT
    sm.sequence_member_id,
    sm.sequence_id,
    s.analysis_run_id,
    s.recording_id,
    s.epoch_id,
    s.scope_entity_id,
    s.event_set_kind,
    sm.ordinal_position,
    sm.detection_id,
    sm.consensus_event_id,
    sm.external_event_id,
    sm.aligned_external_event_id,
    sm.start_time_s,
    sm.end_time_s
FROM sequence_members sm
JOIN sequences s ON s.sequence_id = sm.sequence_id;

-- ============================================================================
-- 15. Indexes for expected prototype queries
-- ============================================================================

-- SQLite UNIQUE constraints treat NULL values as distinct. These expression/partial
-- indexes close a few provenance-identity gaps where NULL means "not applicable"
-- rather than "intentionally different record".
-- Repeat-registration lookup/conflict rule for shipped semantics:
--   config_profiles         -> project_id IS NULL + profile_key
--   config_profile_versions -> profile_id + version_label
--   extractors              -> extractor_key
--   extractor_versions      -> extractor_id + version_label + normalized commit/tag
-- An existing identity is accepted only when all projected definition/provenance
-- values match; otherwise registration reports a conflict instead of updating it.
CREATE UNIQUE INDEX idx_config_profiles_builtin_key
    ON config_profiles(profile_key)
    WHERE project_id IS NULL;

-- Close nullable natural-key gaps needed by repeatable semantic registration.
CREATE UNIQUE INDEX idx_extractor_versions_identity
    ON extractor_versions(extractor_id, version_label, IFNULL(source_commit_or_tag,''));

CREATE UNIQUE INDEX idx_extractor_features_identity
    ON extractor_features(
        extractor_version_id,
        native_name,
        IFNULL(source_artifact_type,''),
        IFNULL(derivation_stage,''),
        IFNULL(operational_variant,'')
    );

CREATE UNIQUE INDEX idx_extraction_inputs_unique
    ON extraction_run_inputs(extraction_run_id, recording_id, input_role, IFNULL(recording_channel_id, -1));

CREATE UNIQUE INDEX idx_recording_entity_links_unique
    ON recording_entity_links(recording_id, entity_id, link_type, IFNULL(role_label,''), IFNULL(start_time_s,-1));

CREATE UNIQUE INDEX idx_entity_relationships_unique
    ON entity_relationships(parent_entity_id, child_entity_id, relationship_type, IFNULL(role_label,''));

CREATE UNIQUE INDEX idx_detections_native_id_scoped
    ON detections(extraction_run_id, recording_id, IFNULL(source_artifact_id,-1), native_event_id)
    WHERE native_event_id IS NOT NULL;

CREATE INDEX idx_source_files_checksum ON source_files(project_id, checksum_sha256);
CREATE INDEX idx_entity_types_role ON entity_types(project_id, canonical_role);
CREATE INDEX idx_entities_type_native ON experimental_entities(entity_type_id, native_id);
CREATE INDEX idx_entity_relationships_parent ON entity_relationships(parent_entity_id);
CREATE INDEX idx_entity_relationships_child ON entity_relationships(child_entity_id);
CREATE INDEX idx_entity_attributes_name ON entity_attributes(attribute_name);
CREATE INDEX idx_recordings_checksum ON recordings(project_id, checksum_sha256);
CREATE INDEX idx_recording_entities_recording ON recording_entity_links(recording_id);
CREATE INDEX idx_recording_entities_entity ON recording_entity_links(entity_id);
CREATE INDEX idx_recording_epochs_time ON recording_epochs(recording_id, start_time_s, end_time_s);
CREATE INDEX idx_channel_placements_system ON channel_placements(coordinate_system_id);
CREATE INDEX idx_extraction_runs_extractor ON extraction_runs(extractor_version_id);
CREATE INDEX idx_extraction_inputs_recording ON extraction_run_inputs(recording_id, extraction_run_id);
CREATE INDEX idx_artifacts_type ON artifacts(project_id, artifact_type);
CREATE INDEX idx_extractor_objects_level ON extractor_objects(extraction_run_id, canonical_level, native_level);
CREATE INDEX idx_extractor_features_name ON extractor_features(extractor_version_id, native_name);
CREATE INDEX idx_feature_mappings_canonical ON feature_mappings(canonical_feature_id);
CREATE INDEX idx_detections_run ON detections(extraction_run_id, recording_id);
CREATE INDEX idx_detections_recording_time ON detections(recording_id, start_time_s, end_time_s);
CREATE INDEX idx_event_measurements_detection ON event_measurements(detection_id);
CREATE INDEX idx_event_measurements_canonical ON event_measurements(canonical_feature_id, detection_id);
CREATE INDEX idx_class_assignments_detection ON classification_assignments(detection_id);
CREATE INDEX idx_candidate_pairs_recording ON candidate_pairs(analysis_run_id, recording_id);
CREATE INDEX idx_match_groups_recording ON match_groups(analysis_run_id, recording_id);
CREATE INDEX idx_match_members_detection ON match_group_members(detection_id);
CREATE INDEX idx_analysis_run_sources_source ON analysis_run_sources(source_analysis_run_id);
CREATE INDEX idx_agreement_groups_recording ON agreement_groups(analysis_run_id, recording_id);
CREATE INDEX idx_agreement_members_detection ON agreement_group_members(detection_id);
CREATE INDEX idx_agreement_supporting_edges_candidate ON agreement_supporting_edges(candidate_pair_id);
CREATE INDEX idx_consensus_events_recording_time ON consensus_events(recording_id, start_time_s, end_time_s);
CREATE INDEX idx_manual_reference_events_recording_time ON manual_reference_events(recording_id, reference_set_key, start_time_s, end_time_s);
CREATE INDEX idx_external_streams_recording ON external_streams(recording_id);
CREATE INDEX idx_external_events_stream_time ON external_events(external_stream_id, start_time_native);
CREATE INDEX idx_external_event_attributes_event ON external_event_attributes(external_event_id, attribute_name);
CREATE INDEX idx_external_stream_sources_stream ON external_stream_sources(external_stream_id);
CREATE INDEX idx_external_stream_coverage_time ON external_stream_coverage(external_stream_id, start_time_native, end_time_native);
CREATE INDEX idx_tracking_streams_system ON tracking_streams(coordinate_system_id);
CREATE INDEX idx_tracking_series_stream ON tracking_series(external_stream_id);
CREATE INDEX idx_identity_associations_track
    ON tracking_identity_associations(external_stream_id, native_track_id,
        start_time_native, end_time_native);
CREATE INDEX idx_identity_associations_entity
    ON tracking_identity_associations(entity_id);
CREATE INDEX idx_acoustic_references_recording_time
    ON acoustic_references(recording_id, start_time_s, end_time_s);
CREATE INDEX idx_acoustic_references_channel
    ON acoustic_references(recording_channel_id, start_time_s, end_time_s);
CREATE INDEX idx_acoustic_references_external_event
    ON acoustic_references(external_event_id);

-- The exact same candidate must not be asserted twice for one interval, but
-- SQLite treats NULLs as distinct in a UNIQUE index, so two 'unresolved' rows
-- for one interval would slip through a plain UNIQUE. Two partial indexes close
-- both halves: one for named candidates, one for the unresolved statement, which
-- can only be made once per interval.
CREATE UNIQUE INDEX idx_identity_associations_candidate
    ON tracking_identity_associations(external_stream_id, native_track_id,
        start_time_native, end_time_native, entity_id)
    WHERE entity_id IS NOT NULL;
CREATE UNIQUE INDEX idx_identity_associations_unresolved
    ON tracking_identity_associations(external_stream_id, native_track_id,
        start_time_native, end_time_native)
    WHERE entity_id IS NULL;
CREATE INDEX idx_alignment_runs_set ON time_alignment_runs(alignment_set_id, source_timebase_id);
CREATE INDEX idx_alignment_anchor_observations_anchor ON alignment_anchor_observations(alignment_anchor_id, timebase_id);
CREATE INDEX idx_alignment_anchor_observations_event ON alignment_anchor_observations(external_event_id);
CREATE INDEX idx_alignment_anchor_residuals_run ON alignment_anchor_residuals(alignment_run_id);
CREATE INDEX idx_alignment_anchor_identity_evidence_association ON alignment_anchor_identity_evidence(tracking_identity_association_id);
CREATE INDEX idx_aligned_events_time ON aligned_external_events(target_timebase_id, start_time_aligned_s);

-- Exactly one native audio clock per recording. A partial unique index states this
-- without adding a timebase FK to every detection.
CREATE UNIQUE INDEX idx_timebases_recording_native
    ON timebases(recording_id) WHERE is_recording_native = 1;

-- Timebase and stream names are unique within their scope. These are partial
-- indexes rather than table-level UNIQUE constraints because SQLite treats NULLs
-- as distinct in a UNIQUE index, so a nullable recording_id inside the constraint
-- would silently permit unlimited duplicates at project scope.
CREATE UNIQUE INDEX idx_timebases_recording_name
    ON timebases(recording_id, timebase_name) WHERE recording_id IS NOT NULL;
CREATE UNIQUE INDEX idx_timebases_project_name
    ON timebases(project_id, timebase_name) WHERE recording_id IS NULL;
CREATE UNIQUE INDEX idx_external_streams_recording_name
    ON external_streams(recording_id, stream_name) WHERE recording_id IS NOT NULL;
CREATE UNIQUE INDEX idx_external_streams_project_name
    ON external_streams(project_id, stream_name) WHERE recording_id IS NULL;

-- Redundant anchor observations are legal; redundant *included* ones are not,
-- because two included readings on one clock would silently become two statistical
-- anchors. Replicates are kept with included_in_fit = 0.
CREATE UNIQUE INDEX idx_alignment_anchor_observation_included
    ON alignment_anchor_observations(alignment_anchor_id, timebase_id)
    WHERE included_in_fit = 1;
CREATE INDEX idx_sequences_recording ON sequences(recording_id, analysis_run_id);
CREATE INDEX idx_sequence_members_sequence ON sequence_members(sequence_id, ordinal_position);
CREATE INDEX idx_derived_measurements_metric ON derived_measurements(metric_definition_id, analysis_run_id);
CREATE INDEX idx_derived_measurements_acoustic_reference
    ON derived_measurements(acoustic_reference_id, recording_channel_id);
CREATE UNIQUE INDEX idx_derived_measurements_acoustic_unique
    ON derived_measurements(analysis_run_id, metric_definition_id,
                            acoustic_reference_id, IFNULL(recording_channel_id, -1))
    WHERE acoustic_reference_id IS NOT NULL;
CREATE INDEX idx_channel_response_estimates_run
    ON channel_response_estimates(analysis_run_id, recording_channel_id,
                                  metric_definition_id, reference_type);
CREATE INDEX idx_channel_response_estimate_sources_measurement
    ON channel_response_estimate_sources(derived_measurement_id);

COMMIT;
