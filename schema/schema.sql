-- VAWLUME prototype relational schema
-- Version: 0.1-draft
-- Date: 2026-08-21
-- Target: SQLite (MATLAB-centered workflow)
--
-- Design priorities:
--   * extractor-independent event representation without erasing native semantics
--   * structure-agnostic experimental hierarchy parsed by source_mapping profiles
--   * YAML/JSON profile artifacts for source mappings, extractor settings,
--     recording devices, experimental setups, and analysis policies
--   * multiple extraction runs per recording with full provenance
--   * explicit artifact/model/settings lineage
--   * conservative native-to-canonical feature mapping
--   * cross-extractor candidate matching, match groups, consensus, and review
--   * sequence/hierarchy-aware derived analyses
--   * lightweight support for external behavioral/neural streams and time alignment
--
-- Conventions:
--   * INTEGER PRIMARY KEY values are VAWLUME-generated surrogate IDs.
--   * User/extractor-native identifiers remain TEXT and are scoped explicitly.
--   * Timestamps are UTC ISO-8601 TEXT unless a source-native timestamp is retained.
--   * Detailed profile contents remain external YAML/JSON artifacts; the database
--     stores stable IDs, versions, paths/URIs, and checksums.
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
VALUES ('0.2-draft', 'Phase 1 relational vocabulary and registration identity freeze');

PRAGMA user_version = 2;

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
                            'analysis_settings',
                            'consilience_policy',
                            'other'
                        )),
    is_builtin          INTEGER NOT NULL DEFAULT 0 CHECK (is_builtin IN (0,1)),
    description         TEXT,
    created_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    UNIQUE(project_id, profile_key)
);

-- Immutable/versioned profile snapshots. The detailed YAML/JSON is referenced,
-- not decomposed into bespoke schema columns.
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

-- ============================================================================
-- 11. External behavioral/neural streams and temporal alignment
-- ============================================================================

-- A timebase defines the native clock of a recording, video, operant controller,
-- photometry file, etc. It allows TTL and non-TTL workflows to share one model.
CREATE TABLE timebases (
    timebase_id         INTEGER PRIMARY KEY,
    project_id          INTEGER NOT NULL REFERENCES projects(project_id) ON DELETE CASCADE,
    recording_id        INTEGER REFERENCES recordings(recording_id) ON DELETE CASCADE,
    timebase_name       TEXT NOT NULL,
    timebase_kind       TEXT NOT NULL,
    native_unit         TEXT NOT NULL DEFAULT 's',
    nominal_rate_hz     REAL CHECK (nominal_rate_hz IS NULL OR nominal_rate_hz > 0),
    origin_description  TEXT,
    clock_identifier    TEXT,
    notes               TEXT,
    UNIQUE(project_id, recording_id, timebase_name)
);

-- Continuous neural traces remain external artifacts; SQLite stores stream identity,
-- provenance, timing, and event/annotation records rather than millions of samples.
CREATE TABLE external_streams (
    external_stream_id  INTEGER PRIMARY KEY,
    project_id          INTEGER NOT NULL REFERENCES projects(project_id) ON DELETE CASCADE,
    recording_id        INTEGER REFERENCES recordings(recording_id) ON DELETE CASCADE,
    source_file_id      INTEGER REFERENCES source_files(source_file_id) ON DELETE SET NULL,
    artifact_id         INTEGER REFERENCES artifacts(artifact_id) ON DELETE SET NULL,
    timebase_id         INTEGER NOT NULL REFERENCES timebases(timebase_id) ON DELETE RESTRICT,
    mapping_profile_version_id INTEGER REFERENCES config_profile_versions(profile_version_id) ON DELETE SET NULL,
    stream_name         TEXT NOT NULL,
    stream_kind         TEXT NOT NULL CHECK (stream_kind IN ('event','continuous','annotation','video','ttl','other')),
    modality            TEXT,
    units               TEXT,
    notes               TEXT,
    UNIQUE(project_id, stream_name, source_file_id)
);

CREATE TABLE external_events (
    external_event_id   INTEGER PRIMARY KEY,
    external_stream_id  INTEGER NOT NULL REFERENCES external_streams(external_stream_id) ON DELETE CASCADE,
    entity_id           INTEGER REFERENCES experimental_entities(entity_id) ON DELETE SET NULL,
    native_event_id     TEXT,
    event_type          TEXT NOT NULL,
    start_time_native   REAL NOT NULL,
    end_time_native     REAL,
    value_text          TEXT,
    value_real          REAL,
    unit                TEXT,
    source_locator      TEXT,
    notes               TEXT,
    CHECK (end_time_native IS NULL OR end_time_native >= start_time_native),
    UNIQUE(external_stream_id, native_event_id)
);

CREATE TABLE time_alignment_runs (
    alignment_run_id    INTEGER PRIMARY KEY,
    analysis_run_id     INTEGER NOT NULL UNIQUE REFERENCES analysis_runs(analysis_run_id) ON DELETE CASCADE,
    source_timebase_id  INTEGER NOT NULL REFERENCES timebases(timebase_id) ON DELETE RESTRICT,
    target_timebase_id  INTEGER NOT NULL REFERENCES timebases(timebase_id) ON DELETE RESTRICT,
    method              TEXT NOT NULL,
    fit_rmse_s          REAL CHECK (fit_rmse_s IS NULL OR fit_rmse_s >= 0),
    max_error_s         REAL CHECK (max_error_s IS NULL OR max_error_s >= 0),
    status              TEXT NOT NULL DEFAULT 'estimated' CHECK (status IN ('estimated','validated','rejected','failed')),
    notes               TEXT,
    CHECK (source_timebase_id <> target_timebase_id)
);

CREATE TABLE alignment_anchors (
    alignment_anchor_id INTEGER PRIMARY KEY,
    alignment_run_id    INTEGER NOT NULL REFERENCES time_alignment_runs(alignment_run_id) ON DELETE CASCADE,
    source_time         REAL NOT NULL,
    target_time         REAL NOT NULL,
    anchor_type         TEXT NOT NULL,
    source_reference    TEXT,
    target_reference    TEXT,
    uncertainty_s       REAL CHECK (uncertainty_s IS NULL OR uncertainty_s >= 0),
    notes               TEXT
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
    CHECK (source_end IS NULL OR source_start IS NULL OR source_end >= source_start),
    UNIQUE(alignment_run_id, segment_index)
);

-- Materialized aligned event timing, useful for downstream joins and auditing.
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
    recording_id        INTEGER REFERENCES recordings(recording_id) ON DELETE CASCADE,
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

-- ============================================================================
-- 13. Integrity triggers for cross-table invariants SQLite cannot express as CHECKs
-- ============================================================================

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
CREATE INDEX idx_consensus_events_recording_time ON consensus_events(recording_id, start_time_s, end_time_s);
CREATE INDEX idx_external_streams_recording ON external_streams(recording_id);
CREATE INDEX idx_external_events_stream_time ON external_events(external_stream_id, start_time_native);
CREATE INDEX idx_alignment_anchors_run ON alignment_anchors(alignment_run_id, source_time);
CREATE INDEX idx_aligned_events_time ON aligned_external_events(target_timebase_id, start_time_aligned_s);
CREATE INDEX idx_sequences_recording ON sequences(recording_id, analysis_run_id);
CREATE INDEX idx_sequence_members_sequence ON sequence_members(sequence_id, ordinal_position);
CREATE INDEX idx_derived_measurements_metric ON derived_measurements(metric_definition_id, analysis_run_id);

COMMIT;
