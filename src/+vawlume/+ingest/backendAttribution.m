function result = backendAttribution(conn, runRef, sourcePath, options)
%BACKENDATTRIBUTION Plan or atomically import one localization-backend export.
%
% RESULT = vawlume.ingest.backendAttribution(CONN, RUNREF, SOURCEPATH) maps a
% localization backend's export through its declared attribution_backend_mapping
% profile, resolves every declared key against the database, and reports what
% would be created. Planning is the default and writes nothing.
%
% RESULT = vawlume.ingest.backendAttribution(..., Apply=true) commits a
% conflict-free plan in ONE transaction covering the source-file and
% mapping-profile provenance, the backend's windows, its caller claims, its
% localization estimates, its preserved native fields, and its declared inputs.
% A failure anywhere rolls all of it back.
%
% RUNREF contains attribution_run_id, or project_key and run_key. The run must
% be `planned`, with attribution_path `backend`. The run's provenance snapshot
% supplies the participant set caller labels resolve against.
%
% RESOLUTIONS, each refused by name, every offender listed at once:
%
%   coordinate_system_key -> coordinate_system_id    LocalizationFrameUnknown,
%                                                    LocalizationFrameScopeMismatch
%   a z under a 2-dimensional frame                  LocalizationDimensionMismatch
%   caller label -> entity_id (participant snapshot) CallerLabelUnresolved
%   channel index -> one of the recording's channels ChannelIndexUndeclared
%   tracking_stream_key -> a tracking stream         TrackingStreamUnknown
%   (stream, native track) -> an existing identity   IdentityAssociationNotFound
%     association, which is checked, never created
%
% A frame key naming no declared frame and a key naming another project's frame
% are DIFFERENT errors: the first is a missing declaration, the second a
% cross-project reference, and they have different fixes.
%
% THE BACKEND'S NUMBERS ARE STORED EXACTLY AS THE FILE CARRIED THEM. Every
% column is read as text and parsed once by the mapper. No rescaling, clamping,
% unit conversion, frame transformation, or promotion of a score or confidence
% to a probability. A 2D estimate stores no z; an absent confidence stores NULL.
%
% PER-CHANNEL EVIDENCE AND TRACK REFERENCES (F5.3-1, option a). The schema can
% cite a recording channel or an identity association only on target-grain
% evidence, and intake has no target. Both are therefore preserved as
% producer-native attributes -- `channel:<index>:<kind>` (with a companion
% `...:semantics` text attribute) on the window, and
% `track_reference:<stream key>` on the claim -- AFTER intake has verified the
% channel and the track association exist. They become relational citations
% when explicit promotion writes target-grain evidence.
%
% NOTHING HERE WRITES A CANDIDATE, AN EVIDENCE ROW, OR A CORRESPONDENCE. A
% backend window is related to no VAWLUME event; a claim is not a candidate and
% an estimate is not evidence until explicit promotion. A second Apply to a run
% that already carries windows is refused (vawlume:attribution:ImportAlreadyApplied).
%
% Name-value arguments:
%   Apply        persist the plan (default false)
%   ProfilePath  mapping profile (default: the shipped generic backend profile)
%   RepoRoot     repository root, inferred from this file by default
%
% See also VAWLUME.INGEST.ATTRIBUTION, VAWLUME.SOURCE_MAPPING.MAPTABLETOIR,
% VAWLUME.SOURCE_MAPPING.PREVIEW

arguments
    conn
    runRef (1,1) struct
    sourcePath (1,1) string
    options.Apply (1,1) logical = false
    options.ProfilePath (1,1) string = ""
    options.RepoRoot (1,1) string = ""
end

plan = attributionBackendBuildPlan(conn, runRef, sourcePath, options);
result = backendResult(plan);
if options.Apply && ~plan.has_conflicts
    [plan, counts] = attributionBackendApplyPlan(conn, plan);
    result = backendResult(plan);
    result.committed = true;
    result.applied_counts = counts;
    result.status = "imported";
end
end

function result = backendResult(plan)
if plan.has_conflicts
    status = "conflict";
else
    status = "planned";
end
result = struct( ...
    status=status, ...
    committed=false, ...
    attribution_run_id=plan.run.attribution_run_id, ...
    run_key=plan.run.run_key, ...
    source=plan.source, ...
    profile=plan.profile, ...
    exporting_system=plan.exporting_system, ...
    windows=plan.windows, ...
    claims=plan.claims, ...
    estimates=plan.estimates, ...
    native_attributes=plan.native_attributes, ...
    declared_inputs=plan.declared_inputs, ...
    resolutions=plan.resolutions, ...
    unmapped_rows=plan.unmapped_rows, ...
    issues=plan.issues, ...
    has_conflicts=plan.has_conflicts, ...
    timing_basis="native_to_backend", ...
    correspondence="none; backend windows are related to no VAWLUME event here", ...
    not_written=["attribution_candidates"; "attribution_evidence"; ...
        "attribution_window_correspondences"], ...
    proves="a localization backend's export was read and stored with its provenance", ...
    does_not_prove=["that any localized source was an animal, or the right one"; ...
        "that the backend's coordinates, confidences or scores are accurate or calibrated"; ...
        "that the backend's frame is the frame its coordinates were measured in"; ...
        "that these windows refer to calls VAWLUME detected"]);
end
