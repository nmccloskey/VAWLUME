function plan = attributionBuildCorrespondencePlan(conn, runRef, options)
%ATTRIBUTIONBUILDCORRESPONDENCEPLAN Which imported windows refer to which events.
%
% Reads; writes nothing. All clock arithmetic goes through
% vawlume.alignment.applyTransformInterval, and all interval arithmetic through
% vawlume.interval.relation. Neither is reimplemented here.

run = attributionResolveRun(conn, runRef);

% Exactly one clock declaration. Guessing would produce a plausible number from
% incomparable clocks, and nothing downstream could tell.
hasAlignment = ~isempty(options.AlignmentRun);
if hasAlignment == options.SameClock
    error("vawlume:attribution:ClockRelationUndeclared", ...
        "Say how the exporter's clock relates to the recording's: pass " + ...
        "AlignmentRun to transform through a stored fit, or SameClock=true to " + ...
        "assert they are already one clock. A correspondence computed on " + ...
        "incomparable clocks is a plausible number and a wrong one.");
end

windows = readWindows(conn, run.attribution_run_id);
if height(windows) == 0
    error("vawlume:attribution:NoImportedWindows", ...
        "Run %s carries no imported windows to correspond.", run.run_key);
end
targets = attributionReadTargetGeometry(conn, run.attribution_run_id);
if height(targets) == 0
    error("vawlume:attribution:TargetSetEmpty", ...
        "Attribution run %s has no targets to correspond against.", run.run_key);
end
assertOneRecording(windows, targets, run);

rule = loadCorrespondenceRule(conn, windows, options.RepoRoot);

alignmentRunId = NaN;
iouBasis = "native";
if hasAlignment
    alignmentRunId = double(options.AlignmentRun);
    iouBasis = "aligned";
    assertTransformUsable(conn, alignmentRunId, run);
end

correspondences = emptyCorrespondences();
consideredPairs = 0;
for windowIndex = 1:height(windows)
    window = windows(windowIndex, :);
    [startTime, endTime, startExtrapolated, endExtrapolated] = ...
        expressOnTargetClock(conn, window, alignmentRunId, hasAlignment);

    for targetIndex = 1:height(targets)
        target = targets(targetIndex, :);
        if isnan(target.start_time_s) || isnan(target.end_time_s)
            % An agreement group whose declared extent is empty has no interval
            % to compare against. Skipping is correct; inventing one is not.
            continue
        end
        consideredPairs = consideredPairs + 1;
        relation = vawlume.interval.relation(startTime, endTime, ...
            double(target.start_time_s), double(target.end_time_s));
        if ~isEligible(relation, rule)
            continue
        end
        correspondences = [correspondences; correspondenceRow(window, target, ...
            relation, startTime, endTime, startExtrapolated, endExtrapolated, ...
            alignmentRunId, iouBasis, rule)]; %#ok<AGROW>
    end
end

plan = struct();
plan.run = run;
plan.rule = rule;
plan.iou_basis = iouBasis;
plan.alignment_run_id = alignmentRunId;
plan.correspondences = correspondences;
plan.considered_pairs = consideredPairs;
plan.windows_without_correspondence = countUnmatchedWindows(windows, correspondences);
plan.ambiguous_window_count = countAmbiguousWindows(correspondences);
end

% ------------------------------------------------------------- the rule ---

function tf = isEligible(relation, rule)
%ISELIGIBLE Attribution's own rule. Not the matching specification's.
tf = false;
if rule.require_positive_overlap && ~(relation.intersection_s > 0)
    return
end
if isnan(relation.temporal_iou)
    % Two zero-duration intervals at one instant: no overlap fraction exists.
    % Treated as ineligible rather than as a perfect match.
    return
end
tf = relation.temporal_iou >= rule.min_temporal_iou;
end

% ---------------------------------------------------------------- helpers ---

function [startTime, endTime, startExtrapolated, endExtrapolated] = ...
        expressOnTargetClock(conn, window, alignmentRunId, hasAlignment)
startExtrapolated = NaN;
endExtrapolated = NaN;
if ~hasAlignment
    % The caller asserted one clock. The native times are already comparable,
    % and nothing is transformed.
    startTime = double(window.start_time_native);
    endTime = double(window.end_time_native);
    return
end
% Every clock transformation goes through the public interval form. No local
% offset, no scale applied by hand.
intervals = vawlume.alignment.applyTransformInterval(conn, alignmentRunId, ...
    double(window.start_time_native), double(window.end_time_native));
startTime = double(intervals.start_aligned(1));
endTime = double(intervals.end_aligned(1));
startExtrapolated = double(intervals.start_extrapolated(1));
endExtrapolated = double(intervals.end_extrapolated(1));
end

function rule = loadCorrespondenceRule(conn, windows, repoRoot)
%LOADCORRESPONDENCERULE Read the rule the import registered.
%
% The rule travels with the import rather than being supplied at correspondence
% time, so a stored correspondence names a profile version that still exists and
% still says what it meant.
profileVersionId = double(windows.mapping_profile_version_id(1));
profilePath = "";
if ~isnan(profileVersionId) && profileVersionId > 0
    rows = fetch(conn, "SELECT IFNULL(content_uri,'') AS uri " + ...
        "FROM config_profile_versions WHERE profile_version_id=" + ...
        string(profileVersionId));
    if height(rows) > 0
        profilePath = presentText(rows.uri(1));
    end
end
root = resolveRepoRoot(repoRoot);
if strlength(profilePath) == 0
    profilePath = fullfile(root, "config", "01_mapping_profiles", ...
        "attribution", "generic_imported_attribution_profile.json");
elseif ~java.io.File(char(profilePath)).isAbsolute()
    profilePath = fullfile(root, profilePath);
end
if ~isfile(profilePath)
    error("vawlume:attribution:CorrespondenceRuleNotFound", ...
        "The mapping profile this import registered is no longer readable at %s. " + ...
        "A correspondence must name a rule that still exists.", profilePath);
end
document = jsondecode(fileread(profilePath));
entry = document;
if isfield(document, "profiles")
    entries = document.profiles;
    if iscell(entries)
        entry = entries{1};
    else
        entry = entries(1);
    end
end
if ~isfield(entry, "correspondence")
    error("vawlume:attribution:CorrespondenceRuleUndeclared", ...
        "Mapping profile %s declares no correspondence rule. Attribution does " + ...
        "not borrow the matching specification's.", profilePath);
end
declared = entry.correspondence;
rule = struct( ...
    eligibility_rule=string(declared.eligibility_rule), ...
    min_temporal_iou=double(declared.min_temporal_iou), ...
    require_positive_overlap=true, ...
    profile_version_id=profileVersionId, ...
    calibration_status="illustrative_prototype");
if isfield(declared, "require_positive_overlap")
    rule.require_positive_overlap = logical(declared.require_positive_overlap);
end
if isfield(declared, "calibration_status")
    rule.calibration_status = string(declared.calibration_status);
end
end

function assertTransformUsable(conn, alignmentRunId, run)
rows = fetch(conn, "SELECT status, IFNULL(failure_code,'') AS failure_code " + ...
    "FROM time_alignment_runs WHERE alignment_run_id=" + string(alignmentRunId));
if isempty(rows) || height(rows) == 0
    error("vawlume:attribution:TransformNotFound", ...
        "No alignment run %d exists to relate the exporter's clock to run %s.", ...
        alignmentRunId, run.run_key);
end
status = presentText(rows.status(1));
if status ~= "estimated"
    error("vawlume:attribution:TransformNotUsable", ...
        "Alignment run %d has status '%s'. A correspondence may only rest on a " + ...
        "fitted transform; a failed or unfitted one would produce a plausible " + ...
        "number from no fit at all.", alignmentRunId, status);
end
end

function assertOneRecording(windows, targets, run)
recordings = unique([double(windows.recording_id); ...
    double(targets.recording_id(~isnan(targets.recording_id)))]);
if numel(recordings) > 1
    error("vawlume:attribution:CorrespondenceCrossesRecording", ...
        "Run %s mixes recordings %s. A correspondence across recordings compares " + ...
        "events that never co-occurred.", run.run_key, ...
        strjoin(string(recordings'), ", "));
end
end

function windows = readWindows(conn, attributionRunId)
% Correspondence compares INTERVALS. It reads no caller label, because which
% animal an exporting system named has no bearing on whether its window refers to
% a call VAWLUME detected -- and letting a label influence that would make the
% correspondence a caller judgement in disguise.
rows = fetch(conn, "SELECT imported_attribution_window_id AS window_id, " + ...
    "recording_id, IFNULL(native_window_id,'') AS native_window_id, " + ...
    "start_time_native, end_time_native, " + ...
    "IFNULL(mapping_profile_version_id,-1) AS mapping_profile_version_id " + ...
    "FROM imported_attribution_windows WHERE attribution_run_id=" + ...
    string(attributionRunId) + " ORDER BY imported_attribution_window_id");
count = height(rows);
windows = table(NaN(count, 1), NaN(count, 1), strings(count, 1), ...
    NaN(count, 1), NaN(count, 1), NaN(count, 1), ...
    VariableNames=["imported_attribution_window_id", "recording_id", ...
    "native_window_id", "start_time_native", "end_time_native", ...
    "mapping_profile_version_id"]);
if count == 0
    return
end
windows.imported_attribution_window_id = double(rows.window_id);
windows.recording_id = double(rows.recording_id);
windows.native_window_id = presentText(rows.native_window_id);
windows.start_time_native = double(rows.start_time_native);
windows.end_time_native = double(rows.end_time_native);
windows.mapping_profile_version_id = double(rows.mapping_profile_version_id);
end

function row = correspondenceRow(window, target, relation, startTime, endTime, ...
        startExtrapolated, endExtrapolated, alignmentRunId, iouBasis, rule)
row = table( ...
    double(window.imported_attribution_window_id), ...
    string(window.native_window_id), ...
    double(target.attribution_target_id), ...
    string(target.target_kind), ...
    alignmentRunId, string(iouBasis), ...
    startTime, endTime, ...
    relation.intersection_s, relation.temporal_iou, ...
    relation.onset_difference_s, relation.offset_difference_s, ...
    startExtrapolated, endExtrapolated, ...
    string(rule.eligibility_rule), rule.min_temporal_iou, ...
    VariableNames=["imported_attribution_window_id", "native_window_id", ...
    "attribution_target_id", "target_kind", "alignment_run_id", "iou_basis", ...
    "aligned_start_s", "aligned_end_s", "temporal_overlap_s", "temporal_iou", ...
    "onset_difference_s", "offset_difference_s", "start_extrapolated", ...
    "end_extrapolated", "eligibility_rule", "min_temporal_iou"]);
end

function value = countUnmatchedWindows(windows, correspondences)
if height(correspondences) == 0
    value = height(windows);
    return
end
matched = unique(double(correspondences.imported_attribution_window_id));
value = height(windows) - numel(matched);
end

function value = countAmbiguousWindows(correspondences)
% A window corresponding to more than one event. Counted and reported, never
% resolved.
value = 0;
if height(correspondences) == 0
    return
end
ids = double(correspondences.imported_attribution_window_id);
unique_ids = unique(ids);
for index = 1:numel(unique_ids)
    if nnz(ids == unique_ids(index)) > 1
        value = value + 1;
    end
end
end

function root = resolveRepoRoot(root)
root = string(root);
if strlength(root) == 0
    root = fileparts(fileparts(fileparts(fileparts(fileparts( ...
        mfilename("fullpath"))))));
end
root = string(java.io.File(char(root)).getCanonicalPath());
end

function value = emptyCorrespondences()
value = table('Size', [0 16], ...
    'VariableTypes', ["double", "string", "double", "string", "double", ...
    "string", "double", "double", "double", "double", "double", "double", ...
    "double", "double", "string", "double"], ...
    'VariableNames', ["imported_attribution_window_id", "native_window_id", ...
    "attribution_target_id", "target_kind", "alignment_run_id", "iou_basis", ...
    "aligned_start_s", "aligned_end_s", "temporal_overlap_s", "temporal_iou", ...
    "onset_difference_s", "offset_difference_s", "start_extrapolated", ...
    "end_extrapolated", "eligibility_rule", "min_temporal_iou"]);
end

function value = presentText(raw)
value = string(raw);
value(ismissing(value)) = "";
end
