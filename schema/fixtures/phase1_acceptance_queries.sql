-- Phase 1 schema acceptance queries for the synthetic fixture.
--
-- Usage:
--   1. Build a fresh fixture database with vawlume.db.createPhase1FixtureDatabase.
--   2. Execute each Q01-Q14 SELECT independently against that database.
--
-- These are architectural questions, not a stable user query API. Predicates use
-- stable logical fixture keys and semantic identities rather than generated IDs.

-- Q01 - Detections by extraction run
-- Question: Which detections belong to each DeepSqueak and MUPET run?
-- Difficulty: CLEAR
-- Expected logical result:
--   8 rows total across 3 extraction runs.
--   DeepSqueak social run has native events 1, 2, 3.
--   MUPET social run has native events 1, 2, 3, 4.
--   DeepSqueak baseline run has native event 1.
SELECT
    extraction_run_key,
    extractor_name,
    extractor_version,
    native_recording_id,
    recording_relative_path,
    native_event_id,
    detection_id,
    start_time_s,
    end_time_s
FROM v_detection_core
WHERE project_key = 'phase1_synthetic_fixture'
  AND extractor_name IN ('DeepSqueak', 'MUPET')
ORDER BY
    extraction_run_key,
    CAST(native_event_id AS INTEGER),
    detection_id;

-- Q02 - Recordings analyzed by both extractors
-- Question: Which recordings have at least one DeepSqueak run and at least
-- one MUPET run?
-- Difficulty: CLEAR
-- Expected logical result:
--   REC_SOCIAL_DYAD_01 appears once.
--   REC_BASELINE_M01 does not appear.
WITH recording_extractor_runs AS (
    SELECT DISTINCT
        p.project_key,
        r.recording_id,
        r.native_recording_id,
        sf.relative_path AS recording_relative_path,
        e.extractor_name,
        er.run_key
    FROM extraction_run_inputs eri
    JOIN extraction_runs er ON er.extraction_run_id = eri.extraction_run_id
    JOIN extractor_versions ev ON ev.extractor_version_id = er.extractor_version_id
    JOIN extractors e ON e.extractor_id = ev.extractor_id
    JOIN recordings r ON r.recording_id = eri.recording_id
    JOIN projects p ON p.project_id = r.project_id
    JOIN source_files sf ON sf.source_file_id = r.source_file_id
    WHERE p.project_key = 'phase1_synthetic_fixture'
)
SELECT
    native_recording_id,
    recording_relative_path,
    SUM(CASE WHEN extractor_name = 'DeepSqueak' THEN 1 ELSE 0 END) AS deepsqueak_run_count,
    SUM(CASE WHEN extractor_name = 'MUPET' THEN 1 ELSE 0 END) AS mupet_run_count,
    GROUP_CONCAT(extractor_name || ':' || run_key, '; ') AS extractor_runs
FROM recording_extractor_runs
GROUP BY
    recording_id,
    native_recording_id,
    recording_relative_path
HAVING deepsqueak_run_count >= 1
   AND mupet_run_count >= 1
ORDER BY native_recording_id;

-- Q03 - Registered native and canonical features
-- Question: For each extractor/version, which native features are registered,
-- what canonical feature do they map to, what transform is declared, and what
-- is the mapping strength/type?
-- Difficulty: CLEAR
-- Expected logical result:
--   26 rows for the shipped DeepSqueak/MUPET event-measurement feature
--   registry. Extractor-specific/non-comparable features remain visible by
--   their mapping_type and notes rather than being dropped.
SELECT
    e.extractor_name,
    ev.version_label AS extractor_version,
    xf.extractor_feature_id,
    xf.native_name,
    IFNULL(xf.native_unit, '') AS native_unit,
    IFNULL(xf.source_artifact_type, '') AS source_artifact_type,
    IFNULL(xf.derivation_stage, '') AS derivation_stage,
    IFNULL(xf.operational_variant, '') AS operational_variant,
    IFNULL(xf.equivalence_class, '') AS equivalence_class,
    IFNULL(cf.canonical_name, '') AS canonical_name,
    IFNULL(cf.canonical_unit, '') AS canonical_unit,
    IFNULL(fm.mapping_type, 'unmapped') AS mapping_type,
    IFNULL(fm.transform_key, '') AS transform_key,
    IFNULL(CAST(fm.preserve_raw AS TEXT), '') AS preserve_raw,
    IFNULL(cp.profile_key, '') AS mapping_profile_key,
    IFNULL(cpv.version_label, '') AS mapping_profile_version
FROM extractor_features xf
JOIN extractor_versions ev ON ev.extractor_version_id = xf.extractor_version_id
JOIN extractors e ON e.extractor_id = ev.extractor_id
LEFT JOIN feature_mappings fm ON fm.extractor_feature_id = xf.extractor_feature_id
LEFT JOIN canonical_features cf ON cf.canonical_feature_id = fm.canonical_feature_id
LEFT JOIN config_profile_versions cpv ON cpv.profile_version_id = fm.mapping_profile_version_id
LEFT JOIN config_profiles cp ON cp.profile_id = cpv.profile_id
WHERE e.extractor_name IN ('DeepSqueak', 'MUPET')
ORDER BY
    e.extractor_name,
    ev.version_label,
    xf.source_artifact_type,
    xf.native_name,
    cf.canonical_name;

-- Q04 - Pairwise comparability
-- Question: Which DeepSqueak-MUPET native feature pairs are explicitly
-- recorded for comparison/consilience, and at what relationship strength?
-- Difficulty: CLEAR
-- Expected logical result:
--   9 explicit DeepSqueak/MUPET feature relationships.
--   7 are consilience_eligible; 2 power/energy/amplitude relationships are
--   retained as related but not eligible by default.
WITH pairs AS (
    SELECT
        fr.feature_relationship_id,
        e_a.extractor_name AS extractor_a,
        ev_a.version_label AS version_a,
        xf_a.native_name AS native_feature_a,
        xf_a.extractor_feature_id AS feature_a_id,
        e_b.extractor_name AS extractor_b,
        ev_b.version_label AS version_b,
        xf_b.native_name AS native_feature_b,
        xf_b.extractor_feature_id AS feature_b_id,
        fr.relationship_type,
        fr.comparison_method,
        fr.unit_normalization,
        fr.consilience_eligible,
        fr.default_role,
        fr.justification,
        fr.source_reference
    FROM feature_relationships fr
    JOIN extractor_features xf_a ON xf_a.extractor_feature_id = fr.feature_a_id
    JOIN extractor_versions ev_a ON ev_a.extractor_version_id = xf_a.extractor_version_id
    JOIN extractors e_a ON e_a.extractor_id = ev_a.extractor_id
    JOIN extractor_features xf_b ON xf_b.extractor_feature_id = fr.feature_b_id
    JOIN extractor_versions ev_b ON ev_b.extractor_version_id = xf_b.extractor_version_id
    JOIN extractors e_b ON e_b.extractor_id = ev_b.extractor_id
    WHERE e_a.extractor_name IN ('DeepSqueak', 'MUPET')
      AND e_b.extractor_name IN ('DeepSqueak', 'MUPET')
      AND e_a.extractor_name <> e_b.extractor_name
)
SELECT
    feature_relationship_id,
    CASE WHEN extractor_a = 'DeepSqueak' THEN version_a ELSE version_b END AS deepsqueak_version,
    CASE WHEN extractor_a = 'DeepSqueak' THEN feature_a_id ELSE feature_b_id END AS deepsqueak_feature_id,
    CASE WHEN extractor_a = 'DeepSqueak' THEN native_feature_a ELSE native_feature_b END AS deepsqueak_native_feature,
    CASE WHEN extractor_a = 'MUPET' THEN version_a ELSE version_b END AS mupet_version,
    CASE WHEN extractor_a = 'MUPET' THEN feature_a_id ELSE feature_b_id END AS mupet_feature_id,
    CASE WHEN extractor_a = 'MUPET' THEN native_feature_a ELSE native_feature_b END AS mupet_native_feature,
    relationship_type,
    IFNULL(comparison_method, '') AS comparison_method,
    IFNULL(unit_normalization, '') AS unit_normalization,
    consilience_eligible,
    IFNULL(default_role, '') AS default_role,
    IFNULL(justification, '') AS justification,
    IFNULL(source_reference, '') AS source_reference
FROM pairs
ORDER BY
    consilience_eligible DESC,
    relationship_type,
    deepsqueak_native_feature,
    mupet_native_feature;

-- Q05 - Recording device/setup context
-- Question: Which recording-device and experimental-setup profile versions are
-- linked to each fixture recording, and how were they assigned/inherited?
-- Difficulty: VIEW CANDIDATE
-- Expected logical result:
--   4 rows: device and setup profile assignments for each of 2 recordings.
SELECT
    p.project_key,
    r.native_recording_id,
    rpa.assignment_role,
    rpa.inheritance_source,
    cp.profile_kind,
    cp.profile_key,
    cp.profile_name,
    cpv.version_label AS profile_version,
    IFNULL(cpv.profile_schema_version, '') AS profile_schema_version,
    cpv.content_uri,
    IFNULL(cpv.checksum_sha256, '') AS checksum_sha256
FROM recording_profile_assignments rpa
JOIN recordings r ON r.recording_id = rpa.recording_id
JOIN projects p ON p.project_id = r.project_id
JOIN config_profile_versions cpv ON cpv.profile_version_id = rpa.profile_version_id
JOIN config_profiles cp ON cp.profile_id = cpv.profile_id
WHERE p.project_key = 'phase1_synthetic_fixture'
  AND cp.profile_kind IN ('recording_device', 'experimental_setup')
ORDER BY
    r.native_recording_id,
    rpa.assignment_role,
    cp.profile_key;

-- Q06 - Experimental participants and roles
-- Question: Which experimental entities participate in the multi-subject
-- recording, what are their entity types, and what role labels do they carry?
-- Difficulty: CLEAR
-- Expected logical result:
--   REC_SOCIAL_DYAD_01 has 4 linked context rows: the dyad, male subject,
--   female subject, and session. The two subject rows carry male/female roles.
SELECT
    project_key,
    native_recording_id,
    entity_type,
    canonical_role,
    entity_native_id,
    display_label,
    link_type,
    IFNULL(role_label, '') AS role_label,
    IFNULL(CAST(start_time_s AS TEXT), '') AS start_time_s,
    IFNULL(CAST(end_time_s AS TEXT), '') AS end_time_s
FROM v_recording_entity_context
WHERE project_key = 'phase1_synthetic_fixture'
  AND native_recording_id = 'REC_SOCIAL_DYAD_01'
ORDER BY
    CASE entity_type
        WHEN 'dyad' THEN 1
        WHEN 'subject' THEN 2
        WHEN 'session' THEN 3
        ELSE 4
    END,
    role_label,
    entity_native_id;

-- Q07 - Scoped native IDs
-- Question: Show repeated native event IDs that are legal because they belong
-- to different extraction runs/artifacts.
-- Difficulty: CLEAR
-- Expected logical result:
--   7 rows. Native event id 1 appears in 3 rows; native event ids 2 and 3
--   each appear in 2 rows. Each repeat is scoped by run/recording/artifact.
WITH repeated_native_ids AS (
    SELECT native_event_id
    FROM v_detection_core
    WHERE project_key = 'phase1_synthetic_fixture'
      AND native_event_id IS NOT NULL
    GROUP BY native_event_id
    HAVING COUNT(*) > 1
)
SELECT
    vc.native_event_id,
    vc.detection_id,
    vc.extractor_name,
    vc.extractor_version,
    vc.extraction_run_key,
    vc.native_recording_id,
    a.artifact_id AS source_artifact_id,
    a.path_or_uri AS source_artifact_uri,
    vc.start_time_s,
    vc.end_time_s
FROM v_detection_core vc
JOIN repeated_native_ids rni ON rni.native_event_id = vc.native_event_id
JOIN detections d ON d.detection_id = vc.detection_id
LEFT JOIN artifacts a ON a.artifact_id = d.source_artifact_id
WHERE vc.project_key = 'phase1_synthetic_fixture'
ORDER BY
    vc.native_event_id,
    vc.extraction_run_key,
    vc.detection_id;

-- Q08 - Legal cross-extractor candidate/match rows
-- Question: For each fixture candidate pair, show temporal evidence and whether
-- it satisfies same-recording and different-run legality.
-- Difficulty: VIEW CANDIDATE
-- Expected logical result:
--   3 rows. same_recording_rule_ok and different_run_rule_ok are both 1 for
--   every row because candidate_pairs is protected by schema triggers/checks.
SELECT
    ar.run_key AS analysis_run_key,
    cp.candidate_pair_id,
    rec.native_recording_id,
    a.detection_id AS detection_a_id,
    a.extractor_name AS detection_a_extractor,
    a.extraction_run_key AS detection_a_run_key,
    a.native_event_id AS detection_a_native_event_id,
    a.start_time_s AS detection_a_start_time_s,
    a.end_time_s AS detection_a_end_time_s,
    b.detection_id AS detection_b_id,
    b.extractor_name AS detection_b_extractor,
    b.extraction_run_key AS detection_b_run_key,
    b.native_event_id AS detection_b_native_event_id,
    b.start_time_s AS detection_b_start_time_s,
    b.end_time_s AS detection_b_end_time_s,
    cp.temporal_overlap_s,
    cp.temporal_iou,
    cp.onset_difference_s,
    cp.offset_difference_s,
    cp.duration_difference_s,
    cp.candidate_score,
    cp.candidate_status,
    CASE WHEN a.recording_id = cp.recording_id AND b.recording_id = cp.recording_id THEN 1 ELSE 0 END AS same_recording_rule_ok,
    CASE WHEN a.extraction_run_id <> b.extraction_run_id THEN 1 ELSE 0 END AS different_run_rule_ok
FROM candidate_pairs cp
JOIN analysis_runs ar ON ar.analysis_run_id = cp.analysis_run_id
JOIN projects p ON p.project_id = ar.project_id
JOIN recordings rec ON rec.recording_id = cp.recording_id
JOIN v_detection_core a ON a.detection_id = cp.detection_a_id
JOIN v_detection_core b ON b.detection_id = cp.detection_b_id
WHERE p.project_key = 'phase1_synthetic_fixture'
  AND ar.run_key = 'fixture_cross_extractor_matching_v1'
ORDER BY
    rec.native_recording_id,
    a.start_time_s,
    b.start_time_s,
    cp.candidate_pair_id;

-- Q09 - Match/consensus group membership
-- Question: Which source detections belong to each match/consensus group?
-- Difficulty: VIEW CANDIDATE
-- Expected logical result:
--   12 rows total: 7 match-group member rows plus 5 consensus-event member
--   rows. Each row keeps extractor/run/native event context visible.
WITH match_members AS (
    SELECT
        'match_group' AS membership_layer,
        ar.run_key AS analysis_run_key,
        CAST(mg.match_group_id AS TEXT) AS result_id,
        mg.match_group_id,
        CAST(NULL AS INTEGER) AS consensus_event_id,
        mg.match_type AS result_type,
        IFNULL(mg.ambiguity_status, '') AS result_status,
        CAST(vc.detection_id AS TEXT) AS detection_id,
        vc.native_recording_id,
        vc.extractor_name,
        vc.extractor_version,
        vc.extraction_run_key,
        vc.native_event_id,
        vc.start_time_s,
        vc.end_time_s,
        IFNULL(mgm.member_role, '') AS member_role
    FROM match_groups mg
    JOIN analysis_runs ar ON ar.analysis_run_id = mg.analysis_run_id
    JOIN projects p ON p.project_id = ar.project_id
    JOIN match_group_members mgm ON mgm.match_group_id = mg.match_group_id
    JOIN v_detection_core vc ON vc.detection_id = mgm.detection_id
    WHERE p.project_key = 'phase1_synthetic_fixture'
      AND ar.run_key = 'fixture_cross_extractor_matching_v1'
),
consensus_members AS (
    SELECT
        'consensus_event' AS membership_layer,
        ar.run_key AS analysis_run_key,
        CAST(ce.consensus_event_id AS TEXT) AS result_id,
        ce.match_group_id,
        ce.consensus_event_id,
        ce.derivation_method AS result_type,
        IFNULL(ce.consensus_status, '') AS result_status,
        vc.detection_id,
        vc.native_recording_id,
        vc.extractor_name,
        vc.extractor_version,
        vc.extraction_run_key,
        vc.native_event_id,
        vc.start_time_s,
        vc.end_time_s,
        IFNULL(cem.member_role, '') AS member_role
    FROM consensus_events ce
    JOIN analysis_runs ar ON ar.analysis_run_id = ce.analysis_run_id
    JOIN projects p ON p.project_id = ar.project_id
    JOIN consensus_event_members cem ON cem.consensus_event_id = ce.consensus_event_id
    JOIN v_detection_core vc ON vc.detection_id = cem.detection_id
    WHERE p.project_key = 'phase1_synthetic_fixture'
      AND ar.run_key = 'fixture_cross_extractor_matching_v1'
)
SELECT *
FROM match_members
UNION ALL
SELECT *
FROM consensus_members
ORDER BY
    membership_layer,
    result_id,
    start_time_s,
    extractor_name,
    native_event_id;

-- Q10 - Ambiguous split/merge representation
-- Question: Return the intentionally ambiguous group and show all member
-- detections plus its match/ambiguity status.
-- Difficulty: CLEAR
-- Expected logical result:
--   3 rows in one one_to_many group: DeepSqueak native event 3 and MUPET native
--   events 3 and 4.
SELECT
    ar.run_key AS analysis_run_key,
    mg.match_group_id,
    rec.native_recording_id,
    mg.match_type,
    IFNULL(mg.ambiguity_status, '') AS ambiguity_status,
    mg.match_score,
    vc.detection_id,
    vc.extractor_name,
    vc.extractor_version,
    vc.extraction_run_key,
    vc.native_event_id,
    vc.start_time_s,
    vc.end_time_s,
    IFNULL(mgm.member_role, '') AS member_role
FROM match_groups mg
JOIN analysis_runs ar ON ar.analysis_run_id = mg.analysis_run_id
JOIN projects p ON p.project_id = ar.project_id
JOIN recordings rec ON rec.recording_id = mg.recording_id
JOIN match_group_members mgm ON mgm.match_group_id = mg.match_group_id
JOIN v_detection_core vc ON vc.detection_id = mgm.detection_id
WHERE p.project_key = 'phase1_synthetic_fixture'
  AND ar.run_key = 'fixture_cross_extractor_matching_v1'
  AND mg.match_type IN ('one_to_many', 'many_to_one')
ORDER BY
    mg.match_group_id,
    vc.start_time_s,
    vc.extractor_name,
    vc.native_event_id;

-- Q11 - Native plus canonical measurements
-- Question: For selected fixture detections, show native feature/value/unit
-- alongside canonical feature/value/unit and transform.
-- Difficulty: CLEAR
-- Expected logical result:
--   10 rows: 4 DeepSqueak kHz_to_Hz rows for social native event 1, 4 MUPET
--   kHz_to_Hz rows for social native event 1, 1 MUPET ms_to_s row for social
--   native event 1, and 1 final MUPET missing inter-syllable interval row.
SELECT
    vc.extractor_name,
    vc.extractor_version,
    vc.extraction_run_key,
    vc.native_recording_id,
    vc.native_event_id,
    vc.detection_id,
    vml.native_name,
    vml.canonical_name,
    vml.native_raw_token,
    IFNULL(CAST(vml.native_value_real AS TEXT), '') AS native_value_real,
    IFNULL(vml.native_unit, '') AS native_unit,
    IFNULL(CAST(vml.canonical_value_real AS TEXT), '') AS canonical_value_real,
    IFNULL(vml.canonical_unit, '') AS canonical_unit,
    IFNULL(vml.transform_key, '') AS transform_key,
    IFNULL(vml.operational_variant, '') AS operational_variant
FROM v_event_measurements_long vml
JOIN v_detection_core vc ON vc.detection_id = vml.detection_id
JOIN event_measurements em ON em.event_measurement_id = vml.event_measurement_id
WHERE vc.project_key = 'phase1_synthetic_fixture'
  AND vc.native_recording_id = 'REC_SOCIAL_DYAD_01'
  AND (
      (vc.extractor_name = 'DeepSqueak'
       AND vc.native_event_id = '1'
       AND vml.transform_key = 'kHz_to_Hz')
      OR
      (vc.extractor_name = 'MUPET'
       AND vc.native_event_id = '1'
       AND vml.transform_key IN ('kHz_to_Hz', 'ms_to_s'))
      OR
      (vc.extractor_name = 'MUPET'
       AND vc.native_event_id = '4'
       AND vml.canonical_name = 'inter_call_interval'
       AND em.native_value_type = 'missing')
  )
ORDER BY
    vc.extractor_name,
    CAST(vc.native_event_id AS INTEGER),
    vml.transform_key,
    vml.native_name;

-- Q12 - External event alignment
-- Question: Which external behavioral events are linked/aligned to the shared
-- recording, showing native time, aligned time, target timebase, and
-- uncertainty?
-- Difficulty: CLEAR
-- Expected logical result:
--   2 rows. Each aligned start time is source/native start time plus 0.55 s.
SELECT
    p.project_key,
    r.native_recording_id,
    vea.stream_name,
    vea.event_type,
    ee.native_event_id,
    source_tb.timebase_name AS source_timebase_name,
    target_tb.timebase_name AS target_timebase_name,
    vea.start_time_native,
    vea.end_time_native,
    vea.start_time_aligned_s,
    vea.end_time_aligned_s,
    vea.uncertainty_s,
    ROUND(vea.start_time_aligned_s - vea.start_time_native, 6) AS start_offset_s,
    tar.method AS alignment_method,
    tar.status AS alignment_status
FROM v_external_events_aligned vea
JOIN external_events ee ON ee.external_event_id = vea.external_event_id
JOIN recordings r ON r.recording_id = vea.recording_id
JOIN projects p ON p.project_id = r.project_id
JOIN time_alignment_runs tar ON tar.alignment_run_id = vea.alignment_run_id
JOIN alignment_sets aset ON aset.alignment_set_id = tar.alignment_set_id
JOIN timebases source_tb ON source_tb.timebase_id = tar.source_timebase_id
JOIN timebases target_tb ON target_tb.timebase_id = aset.reference_timebase_id
WHERE p.project_key = 'phase1_synthetic_fixture'
  AND r.native_recording_id = 'REC_SOCIAL_DYAD_01'
ORDER BY
    vea.start_time_aligned_s,
    ee.native_event_id;

-- Q13 - Manual review/adjudication provenance
-- Question: Which fixture detections/consensus records have manual review or
-- adjudication, and how is that distinct from extractor-native review state?
-- Difficulty: VIEW CANDIDATE
-- Expected logical result:
--   3 rows: one detection-level manual false-positive review that coexists
--   with DeepSqueak Accepted curation, one split/merge match-group review, and
--   one consensus-event review.
WITH detection_reviews AS (
    SELECT
        'detection' AS review_target_type,
        CAST(mr.detection_id AS TEXT) AS review_target_id,
        ar.run_key AS analysis_run_key,
        vc.native_recording_id,
        vc.detection_id,
        vc.extractor_name,
        vc.extraction_run_key,
        vc.native_event_id,
        '' AS match_type_or_derivation,
        mr.review_status AS manual_review_status,
        IFNULL(ce.status_after, '') AS extractor_status_after,
        IFNULL(ce.actor_type, '') AS extractor_status_actor_type,
        IFNULL(ce.actor_label, '') AS extractor_status_actor_label,
        mr.reviewer_label,
        IFNULL(CAST(mr.corrected_start_time_s AS TEXT), '') AS corrected_start_time_s,
        IFNULL(CAST(mr.corrected_end_time_s AS TEXT), '') AS corrected_end_time_s,
        IFNULL(mr.notes, '') AS manual_review_notes
    FROM manual_reviews mr
    JOIN analysis_runs ar ON ar.analysis_run_id = mr.analysis_run_id
    JOIN projects p ON p.project_id = ar.project_id
    JOIN v_detection_core vc ON vc.detection_id = mr.detection_id
    LEFT JOIN curation_events ce ON ce.detection_id = mr.detection_id
    WHERE p.project_key = 'phase1_synthetic_fixture'
      AND mr.detection_id IS NOT NULL
),
match_group_reviews AS (
    SELECT
        'match_group' AS review_target_type,
        CAST(mr.match_group_id AS TEXT) AS review_target_id,
        ar.run_key AS analysis_run_key,
        r.native_recording_id,
        '' AS detection_id,
        '' AS extractor_name,
        '' AS extraction_run_key,
        '' AS native_event_id,
        mg.match_type || ':' || IFNULL(mg.ambiguity_status, '') AS match_type_or_derivation,
        mr.review_status AS manual_review_status,
        '' AS extractor_status_after,
        '' AS extractor_status_actor_type,
        '' AS extractor_status_actor_label,
        mr.reviewer_label,
        IFNULL(CAST(mr.corrected_start_time_s AS TEXT), '') AS corrected_start_time_s,
        IFNULL(CAST(mr.corrected_end_time_s AS TEXT), '') AS corrected_end_time_s,
        IFNULL(mr.notes, '') AS manual_review_notes
    FROM manual_reviews mr
    JOIN analysis_runs ar ON ar.analysis_run_id = mr.analysis_run_id
    JOIN projects p ON p.project_id = ar.project_id
    JOIN match_groups mg ON mg.match_group_id = mr.match_group_id
    JOIN recordings r ON r.recording_id = mg.recording_id
    WHERE p.project_key = 'phase1_synthetic_fixture'
      AND mr.match_group_id IS NOT NULL
),
consensus_reviews AS (
    SELECT
        'consensus_event' AS review_target_type,
        CAST(mr.consensus_event_id AS TEXT) AS review_target_id,
        ar.run_key AS analysis_run_key,
        r.native_recording_id,
        '' AS detection_id,
        '' AS extractor_name,
        '' AS extraction_run_key,
        '' AS native_event_id,
        ce.derivation_method AS match_type_or_derivation,
        mr.review_status AS manual_review_status,
        '' AS extractor_status_after,
        '' AS extractor_status_actor_type,
        '' AS extractor_status_actor_label,
        mr.reviewer_label,
        IFNULL(CAST(mr.corrected_start_time_s AS TEXT), '') AS corrected_start_time_s,
        IFNULL(CAST(mr.corrected_end_time_s AS TEXT), '') AS corrected_end_time_s,
        IFNULL(mr.notes, '') AS manual_review_notes
    FROM manual_reviews mr
    JOIN analysis_runs ar ON ar.analysis_run_id = mr.analysis_run_id
    JOIN projects p ON p.project_id = ar.project_id
    JOIN consensus_events ce ON ce.consensus_event_id = mr.consensus_event_id
    JOIN recordings r ON r.recording_id = ce.recording_id
    WHERE p.project_key = 'phase1_synthetic_fixture'
      AND mr.consensus_event_id IS NOT NULL
)
SELECT *
FROM detection_reviews
UNION ALL
SELECT *
FROM match_group_reviews
UNION ALL
SELECT *
FROM consensus_reviews
ORDER BY
    review_target_type,
    review_target_id;

-- Q14 - Provenance trace
-- Question: Starting from one matched fixture result, trace back to source
-- detections, extraction runs, extractor/version, recording, source artifacts,
-- mapping profile versions, and acquisition context.
-- Difficulty: VIEW CANDIDATE
-- Expected logical result:
--   2 rows for the one-to-one consensus event: one DeepSqueak source detection
--   and one MUPET source detection, both linked to REC_SOCIAL_DYAD_01 with
--   output mapping profile and recording device/setup context visible.
WITH recording_profile_items AS (
    SELECT
        rpa.recording_id,
        cp.profile_kind || ':' || cp.profile_key || '@' || cpv.version_label ||
            ' as ' || rpa.assignment_role || ' via ' || rpa.inheritance_source AS profile_context
    FROM recording_profile_assignments rpa
    JOIN config_profile_versions cpv ON cpv.profile_version_id = rpa.profile_version_id
    JOIN config_profiles cp ON cp.profile_id = cpv.profile_id
    ORDER BY
        rpa.recording_id,
        rpa.assignment_role,
        cp.profile_key
),
recording_profile_context AS (
    SELECT
        recording_id,
        GROUP_CONCAT(profile_context, '; ') AS acquisition_profile_context
    FROM recording_profile_items
    GROUP BY recording_id
)
SELECT
    ar.run_key AS analysis_run_key,
    ce.consensus_event_id,
    ce.derivation_method,
    ce.consensus_status,
    ce.start_time_s AS consensus_start_time_s,
    ce.end_time_s AS consensus_end_time_s,
    cem.member_role AS consensus_member_role,
    d.detection_id,
    d.native_event_id,
    d.start_time_s AS detection_start_time_s,
    d.end_time_s AS detection_end_time_s,
    e.extractor_name,
    ev.version_label AS extractor_version,
    er.run_key AS extraction_run_key,
    r.native_recording_id,
    sf.relative_path AS recording_relative_path,
    a.path_or_uri AS detection_source_artifact_uri,
    a.native_artifact_type AS detection_source_artifact_type,
    cp.profile_key AS output_mapping_profile_key,
    cpv.version_label AS output_mapping_profile_version,
    cpv.content_uri AS output_mapping_profile_uri,
    IFNULL(cpv.checksum_sha256, '') AS output_mapping_profile_checksum,
    rpc.acquisition_profile_context
FROM consensus_events ce
JOIN analysis_runs ar ON ar.analysis_run_id = ce.analysis_run_id
JOIN projects p ON p.project_id = ar.project_id
JOIN consensus_event_members cem ON cem.consensus_event_id = ce.consensus_event_id
JOIN detections d ON d.detection_id = cem.detection_id
JOIN extraction_runs er ON er.extraction_run_id = d.extraction_run_id
JOIN extractor_versions ev ON ev.extractor_version_id = er.extractor_version_id
JOIN extractors e ON e.extractor_id = ev.extractor_id
JOIN recordings r ON r.recording_id = d.recording_id
JOIN source_files sf ON sf.source_file_id = r.source_file_id
LEFT JOIN artifacts a ON a.artifact_id = d.source_artifact_id
LEFT JOIN config_profile_versions cpv ON cpv.profile_version_id = er.output_mapping_profile_version_id
LEFT JOIN config_profiles cp ON cp.profile_id = cpv.profile_id
LEFT JOIN recording_profile_context rpc ON rpc.recording_id = r.recording_id
WHERE p.project_key = 'phase1_synthetic_fixture'
  AND ar.run_key = 'fixture_cross_extractor_matching_v1'
  AND r.native_recording_id = 'REC_SOCIAL_DYAD_01'
  AND ce.derivation_method = 'mean_boundary_consensus'
ORDER BY
    ce.consensus_event_id,
    e.extractor_name,
    d.native_event_id;
