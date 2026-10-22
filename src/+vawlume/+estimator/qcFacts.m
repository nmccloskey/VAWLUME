function result = qcFacts(conn, runRef, options)
%QCFACTS Facts in a native run's stored evidence about the method's own fit. Read-only.
%
% Status: experimental (usage guide, "Status of public functions").
%
%   result = VAWLUME.ESTIMATOR.QCFACTS(conn, runRef)
%
% For a native_estimate run, reports per target how the observed level
% difference sits against the candidates' predictions under the method's
% spreading assumption (contract 07 D8). It reads the run through
% vawlume.attribution.report and the run's registered settings profile version
% (its file must still match the stored checksum), rebuilds the method's inputs
% from the stored evidence rows, and calls the pure method
% vawlume.estimator.levelDifferenceConsistency again (invariant 23). It reads no
% audio, no tracking artifact and no alignment; it writes nothing and changes no
% score or decision. RUNREF is attribution_run_id, or project_key plus run_key.
%
% THESE ARE FACTS, NOT JUDGEMENTS. Nothing here says a decision is wrong, gates,
% weights or decides anything (that would be a new method version), or compares
% across recordings: every number is within one recording, in dB or the frame's
% distance unit, and uncalibrated.
%
% WHAT IT CANNOT DETECT, stated on every target row (D8, verbatim):
%   "A wrong animal that fits well is not detectable from these facts. When an
%   unmodelled bias moves the observed difference toward the wrong candidate's
%   prediction by more than acoustic_margin_db and less than the gap, the wrong
%   animal scores best and every fact here looks ordinary."
%
% RESULT.targets, one row per target of the run:
%   attribution_target_id
%   status                 facts, or no_facts (not two scored candidates)
%   reason                 for no_facts, the first stored no-score reason
%   observed_db            the stored normalized_level_difference
%   prediction_gap_db      |predicted_1 - predicted_2|
%   tolerance_db           half the gap: the largest unmodelled level bias that
%                          leaves the ranking unchanged
%   ranking_boundary_db    the midpoint of the two predictions
%   acoustic_margin_db     |observed - boundary|: a bias larger than this, toward
%                          the other prediction, reverses the ranking
%   observed_outside_predictions  the observed difference lies outside the
%                          interval the two predictions span
%   outside_by_db          by how much (0 when inside)
%   no_candidate_within_tolerance  no candidate's |discrepancy| is within
%                          tolerance_db
%   predictions_coincide   the two predictions are equal (gap 0): they span no
%                          interval and leave no tolerance, the method cannot
%                          rank, and the two facts above are not stated (false);
%                          outside_by_db still reports the distance
%   undetectable_failure_class    the statement above
%
% RESULT.candidates, one row per (target, candidate) with facts:
%   attribution_target_id, entity_id, channel_index_a, channel_index_b,
%   distance_a, distance_b, distance_unit
%   predicted_db, discrepancy_db   the method's own intermediates
%   within_tolerance               |discrepancy| <= tolerance_db
%   positional_margin_a, positional_margin_b   the change in this candidate's
%                          distance to channel a (holding b), or to b (holding
%                          a), that would move its prediction to the ranking
%                          boundary, in the frame's unit. Method arithmetic on
%                          two stored distances; no coordinate is read
%
% Refused: a run that is not native_estimate (vawlume:estimator:QcFactsNotNative);
% a settings file that no longer matches its checksum
% (vawlume:estimator:SettingsChecksumMismatch).
%
% Name-value option: RepoRoot (for a repository-relative settings URI).
%
% See also VAWLUME.ESTIMATOR.LEVELDIFFERENCECONSISTENCY,
% VAWLUME.ESTIMATOR.ATTRIBUTECALLERS, VAWLUME.ATTRIBUTION.REPORT

arguments
    conn
    runRef (1,1) struct
    options.RepoRoot (1,1) string = ""
end

repoRoot = options.RepoRoot;
if strlength(repoRoot) == 0
    repoRoot = string(fileparts(fileparts(fileparts(fileparts(mfilename("fullpath"))))));
end
r = vawlume.attribution.report(conn, runRef, ...
    Tables=["targets", "candidates", "evidence", "no_score_reasons"]);
if r.attribution_path ~= "native_estimate"
    error("vawlume:estimator:QcFactsNotNative", ...
        "Run %d is a %s run; QC facts are about the native method's own fit.", ...
        r.attribution_run_id, r.attribution_path);
end
settings = registeredSettings(conn, r.settings_profile_version_id, repoRoot);
p = settings.parameters;

targets = emptyTargets();
candidates = emptyCandidates();
for k = 1:height(r.targets)
    targetId = r.targets.attribution_target_id(k);
    evidence = r.evidence(r.evidence.attribution_target_id == targetId, :);
    rows = r.candidates(r.candidates.attribution_target_id == targetId, :);
    [entities, geometry] = storedGeometry(evidence, rows, r.no_score_reasons, p);
    t = r.targets(k, :);
    eventId = t.detection_id;
    if t.target_kind == "consensus_event"
        eventId = t.consensus_event_id;
    end
    difference = storedDifference(evidence, p, t.target_kind, eventId);
    method = vawlume.estimator.levelDifferenceConsistency(entities, geometry, ...
        difference, settings).candidates;
    observed = evidence.value_real(evidence.evidence_kind == "normalized_level_difference" & ...
        isnan(evidence.attribution_candidate_id));
    scored = method(method.status == "scored", :);
    if height(scored) ~= 2 || isempty(observed)
        targets(end + 1, :) = {targetId, "no_facts", firstReason(method, ...
            r.no_score_reasons, rows), NaN, NaN, NaN, NaN, NaN, false, NaN, false, ...
            false, undetectableText()}; %#ok<AGROW>
        continue
    end
    o = observed(1);
    predicted = scored.predicted_difference_db;
    gap = abs(predicted(1) - predicted(2));
    tolerance = gap / 2;
    boundary = mean(predicted);
    outside = max([0, min(predicted) - o, o - max(predicted)]);
    discrepancy = o - predicted;
    % Two predictions that coincide span no interval and leave no tolerance: the
    % method cannot rank, so "outside the predictions" and "within tolerance"
    % are not stated as facts there (outside_by_db still reports the distance).
    coincide = gap == 0;
    targets(end + 1, :) = {targetId, "facts", "", o, gap, tolerance, boundary, ...
        abs(o - boundary), ~coincide && outside > 0, outside, ...
        ~coincide && all(abs(discrepancy) > tolerance), coincide, ...
        undetectableText()}; %#ok<AGROW>
    for c = 1:height(scored)
        s = scored(c, :);
        marginA = estimatorDistanceForPrediction(s.distance_b, boundary, "a") - s.distance_a;
        marginB = estimatorDistanceForPrediction(s.distance_a, boundary, "b") - s.distance_b;
        candidates(end + 1, :) = {targetId, s.entity_id, s.channel_index_a, ...
            s.channel_index_b, s.distance_a, s.distance_b, s.distance_unit, ...
            s.predicted_difference_db, s.discrepancy_db, ...
            abs(s.discrepancy_db) <= tolerance, marginA, marginB}; %#ok<AGROW>
    end
end

result = struct(attribution_run_id=r.attribution_run_id, run_key=r.run_key, ...
    recording_id=r.recording_id, method_key=settings.method_key, ...
    method_version=settings.method_version, ...
    settings_profile_version_id=r.settings_profile_version_id, ...
    primary_instant_basis=string(p.primary_instant_basis), ...
    channel_pair=double(p.channel_pair(:))', targets=targets, candidates=candidates, ...
    undetectable_failure_class=undetectableText(), semantics=semanticsText(settings));
end

% ---------------------------------------------------------------- inputs ---

function settings = registeredSettings(conn, versionId, repoRoot)
rows = fetch(conn, "SELECT content_uri, IFNULL(checksum_sha256,'') AS checksum " + ...
    "FROM config_profile_versions WHERE profile_version_id=" + string(versionId));
settings = vawlume.estimator.loadSettings(string(rows.content_uri(1)), RepoRoot=repoRoot);
if settings.checksum_sha256 ~= string(rows.checksum(1))
    error("vawlume:estimator:SettingsChecksumMismatch", ...
        "The settings file at %s no longer matches registered version %d.", ...
        string(rows.content_uri(1)), versionId);
end
end

function d = storedDifference(evidence, p, kind, eventId)
% The method's acoustic input, rebuilt from the two stored per-channel rows, as
% the reconstruction test does. A missing side stays not_normalized.
perChannel = evidence(evidence.evidence_kind == "call_band_power_normalized" & ...
    isnan(evidence.attribution_candidate_id), :);
sides = repmat(struct(target_kind=string(kind), target_id=eventId, channel_index=NaN, ...
    normalized_metric="call_band_power_normalized", unit="", status="not_normalized", ...
    reason="not_stored", value=NaN, qc_flags=strings(0, 1), derived_measurement_id=NaN), 1, 2);
for k = 1:2
    sides(k).channel_index = p.channel_pair(k);
    row = perChannel(perChannel.recording_channel_index == p.channel_pair(k), :);
    if height(row) == 1
        sides(k).status = "normalized";
        sides(k).reason = "";
        sides(k).value = row.value_real;
        sides(k).unit = row.value_units;
        sides(k).derived_measurement_id = row.derived_measurement_id;
        flags = semanticsField(row.value_semantics, "qc_flags");
        sides(k).qc_flags = strings(0, 1);
        if strlength(flags) > 0
            sides(k).qc_flags = split(flags, ",");
        end
    end
end
d = vawlume.acoustic.levelDifference(sides(1), sides(2), p.refuse_clipped_channels);
end

function [entities, geometry] = storedGeometry(evidence, candidates, reasons, p)
% Each candidate's two stored distances on the primary instant basis.
count = height(candidates);
entities = table(candidates.entity_id, true(count, 1), strings(count, 1), ...
    VariableNames=["entity_id", "has_geometry", "reason"]);
geometry = table(zeros(0, 1), zeros(0, 1), strings(0, 1), zeros(0, 1), strings(0, 1), ...
    strings(0, 1), strings(0, 1), false(0, 1), false(0, 1), VariableNames=["entity_id", ...
    "channel_index", "instant_basis", "distance", "unit", "status", "reason", ...
    "event_extrapolated", "bracket_extrapolated"]);
for k = 1:count
    rows = evidence(evidence.attribution_candidate_id == candidates.attribution_candidate_id(k) & ...
        evidence.evidence_kind == "bodypoint_microphone_distance", :);
    primary = rows(contains(rows.value_semantics, ...
        "instant_basis=" + p.primary_instant_basis + ";"), :);
    if height(primary) < 2
        entities.has_geometry(k) = false;
        mine = reasons(reasons.attribution_candidate_id == candidates.attribution_candidate_id(k) & ...
            reasons.reason_ordinal == 1, :);
        entities.reason(k) = "track_not_covered";
        if height(mine) > 0
            entities.reason(k) = mine.reason_code(1);
        end
        continue
    end
    for r = 1:height(primary)
        geometry(end + 1, :) = {candidates.entity_id(k), primary.recording_channel_index(r), ...
            string(p.primary_instant_basis), primary.value_real(r), primary.value_units(r), ...
            "computed", "", semanticsField(primary.value_semantics(r), "event_extrapolated") == "true", ...
            semanticsField(primary.value_semantics(r), "bracket_extrapolated") == "true"}; %#ok<AGROW>
    end
end
end

function value = semanticsField(semantics, key)
token = regexp(semantics, "(^|; )" + key + "=([^;]*)", "tokens", "once");
value = "";
if ~isempty(token)
    value = string(token{2});
end
end

function value = firstReason(method, reasons, candidates)
value = "fewer than two scored candidates";
unscored = method(method.status ~= "scored", :);
if height(unscored) > 0 && strlength(unscored.no_score_reason(1)) > 0
    value = unscored.no_score_reason(1);
    return
end
stated = reasons(ismember(reasons.attribution_candidate_id, candidates.attribution_candidate_id) & ...
    reasons.reason_ordinal == 1, :);
if height(stated) > 0
    value = stated.reason_code(1);
end
end

% ---------------------------------------------------------------- output ---

function value = emptyTargets()
value = table(zeros(0, 1), strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), false(0, 1), zeros(0, 1), false(0, 1), ...
    false(0, 1), strings(0, 1), VariableNames=["attribution_target_id", "status", "reason", ...
    "observed_db", "prediction_gap_db", "tolerance_db", "ranking_boundary_db", ...
    "acoustic_margin_db", "observed_outside_predictions", "outside_by_db", ...
    "no_candidate_within_tolerance", "predictions_coincide", "undetectable_failure_class"]);
end

function value = emptyCandidates()
value = table(zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), false(0, 1), zeros(0, 1), ...
    zeros(0, 1), VariableNames=["attribution_target_id", "entity_id", "channel_index_a", ...
    "channel_index_b", "distance_a", "distance_b", "distance_unit", "predicted_db", ...
    "discrepancy_db", "within_tolerance", "positional_margin_a", "positional_margin_b"]);
end

function value = undetectableText()
value = "A wrong animal that fits well is not detectable from these facts. When an " + ...
    "unmodelled bias moves the observed difference toward the wrong candidate's " + ...
    "prediction by more than acoustic_margin_db and less than the gap, the wrong " + ...
    "animal scores best and every fact here looks ordinary.";
end

function value = semanticsText(settings)
value = sprintf("Facts from stored evidence under %s %s and settings %s %s: dB " + ...
    "differences for the ordered channel pair, distances in the frame's unit, " + ...
    "within this recording only, uncalibrated. They describe the method's fit to " + ...
    "its own spreading assumption; they are not a judgement of any decision.", ...
    settings.method_key, settings.method_version, settings.profile_key, ...
    settings.version_label);
end
