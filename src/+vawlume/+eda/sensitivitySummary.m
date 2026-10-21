function result = sensitivitySummary(conn, familyRef, options)
%SENSITIVITYSUMMARY How conclusions move across one sensitivity family. Read-only.
%
% RESULT = VAWLUME.EDA.SENSITIVITYSUMMARY(CONN, FAMILYREF) reads a family that
% VAWLUME.EDA.ATTRIBUTIONSENSITIVITY recorded, compares every variant with the
% family's declared reference through VAWLUME.ATTRIBUTION.COMPARE, and returns
% one tidy row per variant plus one row per handle that was not varied
% (contract 07 D1, D6). FAMILYREF is struct(analysis_run_id=...) or
% struct(project_key=..., run_key=<family_key>).
%
% IT SELECTS NOTHING. A row says how the comparison categories fall when one
% declared input differs from the reference, and nothing more. Rows are ordered
% by handle and handle value, never by outcome. No row, column or note ranks
% variants or prefers one, and the reference is only the configuration the
% others are compared with. On synthetic data every movement shown is the
% generator's, not evidence about any real recording.
%
% ROWS (one per variant; reported handles carry status and reason, counts NaN):
%   family_key, handle, configuration_id, handle_value, variant_kind
%     (decision_set: a second decision set on the reference run; run: a new run)
%   status        variant, not_variable, not_measurable, reported_elsewhere,
%                 not_exercised
%   reason        why a handle is not varied ("" for a variant)
%   score_comparability   as compare states it for the pair
%   one_to_one_units
%   top_same, top_different, top_tie, top_unscored, top_orientation_unknown
%   sets_equal, sets_both_empty, sets_differ   selected-set relation: equal
%                 non-empty sets; neither run selected anyone (kept apart from
%                 equal, as compare keeps them, contract 07 D4); any other relation
%   status_agree, status_disagree, status_structural_empty, status_excluded,
%     status_undecided    compare's status cross-tab, by cell kind
%   reasons_changed   (target, entity) pairs whose stored no-score reasons,
%                 in order, differ from the reference's
%   scores_changed    score pairs that differ, counted only where compare
%                 allows a value comparison (score_comparability comparable);
%                 NaN otherwise
%   units_one_to_one, units_one_to_many, units_many_to_one, units_many_to_many,
%   units_unmatched_left, units_unmatched_right   correspondence units by
%                 category (on one event set, all one_to_one)
%   targets_lost, targets_gained   reference targets with no counterpart in the
%                 variant, and variant targets with none in the reference
%   pairs, pairs_top_same, pairs_top_different   within-unit target pairs
%
% A MATCHING-SIDE FAMILY (vawlume.eda.correspondenceSensitivity, family_kind
% "correspondence") compares each configuration's consensus-event run with the
% reference configuration's, joined by their stored shared member detections
% (compare's Correspondence=struct(shared_member_detections=true)). Its counts
% are the same columns; the reference configuration itself has no row.
%
% Every count is over the reference's one_to_one units; the per-unit detail is
% in COMPARISONS(k).comparison, compare's own result.
%
% Name-value options:
%   Export   a CSV path: the rows are written with vawlume.eda.writeTableExport,
%            with the family id, reference run, every variant's profile versions
%            and the schema version as provenance
%
% See also VAWLUME.EDA.ATTRIBUTIONSENSITIVITY, VAWLUME.ATTRIBUTION.COMPARE

arguments
    conn
    familyRef (1,1) struct
    options.Export (1,1) string = ""
    options.Overwrite (1,1) logical = false
end

family = readFamily(conn, familyRef);
record = family.record;
reference = struct(attribution_run_id=double(record.reference_attribution_run_id));
referencePolicy = double(record.reference_policy_profile_version_id);
variants = record.variants;
% A matching-side family (correspondenceSensitivity, 7.9) compares consensus
% events of two configurations, joined by their stored shared member detections.
correspondence = isfield(record, "family_kind") && ...
    string(record.family_kind) == "correspondence";
extra = {};
if correspondence
    extra = {"Correspondence", struct(shared_member_detections=true)};
    reported = edaSensitivityHandles("correspondence").reported;
else
    reported = edaSensitivityHandles("attribution").reported;
end
rows = emptyRows();
comparisons = struct(configuration_id={}, comparison={});
for k = 1:numel(variants)
    v = variants(k);
    if string(v.handle) == "reference"
        continue
    end
    if string(v.variant_kind) == "decision_set"
        right = reference;
    else
        right = struct(attribution_run_id=double(v.attribution_run_id));
    end
    policies = {"LeftPolicy", referencePolicy, "RightPolicy", ...
        double(v.policy_profile_version_id)};
    c = vawlume.attribution.compare(conn, reference, right, policies{:}, extra{:});
    oneToOne = c.units.correspondence_unit == "one_to_one";
    comparable = any(oneToOne) && all(c.units.score_comparability == "comparable");
    if comparable
        c = vawlume.attribution.compare(conn, reference, right, policies{:}, ...
            "CompareScores", true, extra{:});
    end
    rows(end + 1, :) = [variantRow(record.family_key, v, c, comparable), unitColumns(c)]; %#ok<AGROW>
    comparisons(end + 1) = struct(configuration_id=string(v.configuration_id), ...
        comparison=c); %#ok<AGROW>
end
for k = 1:height(reported)
    rows(end + 1, :) = [{string(record.family_key), reported.handle(k), "", "", "", ...
        reported.status(k), reported.reason(k), ""}, num2cell(NaN(1, 27))]; %#ok<AGROW>
end
rows = sortrows(rows, ["handle", "handle_value"]);

result = struct(family_key=string(record.family_key), ...
    family_analysis_run_id=family.analysis_run_id, ...
    reference_attribution_run_id=reference.attribution_run_id, ...
    reference_policy_profile_version_id=referencePolicy, rows=rows, ...
    comparisons=comparisons, note=summaryNote());
if strlength(options.Export) > 0
    result.export = vawlume.eda.writeTableExport(rows, options.Export, ...
        Overwrite=options.Overwrite, Provenance=provenance(conn, family, record));
end
end

function family = readFamily(conn, ref)
if isfield(ref, "analysis_run_id")
    predicate = "a.analysis_run_id=" + string(double(ref.analysis_run_id));
elseif isfield(ref, "project_key") && isfield(ref, "run_key")
    predicate = "p.project_key='" + replace(string(ref.project_key), "'", "''") + ...
        "' AND a.run_key='" + replace(string(ref.run_key), "'", "''") + "'";
else
    error("vawlume:eda:SensitivityFamilyNotFound", ...
        "familyRef must contain analysis_run_id, or project_key plus run_key.");
end
rows = fetch(conn, "SELECT a.analysis_run_id, v.content_uri FROM analysis_runs a " + ...
    "JOIN projects p ON p.project_id=a.project_id " + ...
    "JOIN analysis_run_profiles arp ON arp.analysis_run_id=a.analysis_run_id " + ...
    "AND arp.assignment_role='sensitivity_design' " + ...
    "JOIN config_profile_versions v ON v.profile_version_id=arp.profile_version_id " + ...
    "WHERE a.run_type='attribution_sensitivity' AND " + predicate);
if isempty(rows) || height(rows) == 0
    error("vawlume:eda:SensitivityFamilyNotFound", "No sensitivity family matches familyRef.");
end
family = struct(analysis_run_id=double(rows.analysis_run_id(1)), ...
    record=jsondecode(fileread(string(rows.content_uri(1)))));
end

function row = variantRow(familyKey, v, c, comparable)
u = c.units(c.units.correspondence_unit == "one_to_one", :);
top = u.top_entity_agreement;
sets = u.selected_set_relation;
counts = c.status_counts;
kind = @(name) counts.unit_count(counts.cell_kind == name);
scoresChanged = NaN;
if comparable
    s = c.scores;
    differs = ~(s.left_score == s.right_score | (isnan(s.left_score) & isnan(s.right_score)));
    scoresChanged = nnz(differs);
end
comparability = "";
if height(u) > 0
    comparability = string(u.score_comparability(1));
end
row = {string(familyKey), string(v.handle), string(v.configuration_id), ...
    string(v.handle_value), string(v.variant_kind), "variant", "", ...
    comparability, height(u), nnz(top == "same"), ...
    nnz(top == "different"), nnz(ismember(top, ["tie_left", "tie_right"])), ...
    nnz(ismember(top, ["left_unscored", "right_unscored", "both_unscored"])), ...
    nnz(top == "orientation_unknown"), nnz(sets == "equal"), nnz(sets == "both_empty"), ...
    nnz(~ismember(sets, ["equal", "both_empty"])), ...
    kind("agree"), kind("disagree"), kind("structural_empty"), kind("excluded"), ...
    kind("undecided"), reasonsChanged(c, u), scoresChanged};
end

function values = unitColumns(c)
% Correspondence units by category, the targets a configuration lost or gained
% (reference targets with no counterpart; variant targets with none), and the
% within-unit pairs with their top-entity agreement. On one event set every
% unit is one_to_one and the rest are zero.
category = c.units.correspondence_unit;
counts = arrayfun(@(name) nnz(category == name), ["one_to_one", "one_to_many", ...
    "many_to_one", "many_to_many", "unmatched_left", "unmatched_right"]);
lost = sum(cellfun(@numel, c.units.left_target_ids(category == "unmatched_left")));
gained = sum(cellfun(@numel, c.units.right_target_ids(category == "unmatched_right")));
paired = c.pairs(~isnan(c.pairs.left_target_id) & ~isnan(c.pairs.right_target_id), :);
values = [num2cell(counts), {lost, gained, height(paired), ...
    nnz(paired.top_entity_agreement == "same"), ...
    nnz(paired.top_entity_agreement == "different")}];
end

function value = reasonsChanged(c, units)
% Per (one_to_one unit, entity): the reference's stored reasons in order against
% the variant's. A candidate that became scored, or unscored, counts as changed.
value = 0;
r = c.reasons(c.reasons.category == "unscored_candidate", :);
for k = 1:height(units)
    left = r(r.side == "left" & r.attribution_target_id == units.left_target_ids{k}, :);
    right = r(r.side == "right" & r.attribution_target_id == units.right_target_ids{k}, :);
    for entity = union(left.entity_id, right.entity_id)'
        a = sortrows(left(left.entity_id == entity, :), "reason_ordinal").reason_code;
        b = sortrows(right(right.entity_id == entity, :), "reason_ordinal").reason_code;
        value = value + ~isequal(a, b);
    end
end
end

function rows = emptyRows()
names = ["family_key", "handle", "configuration_id", "handle_value", "variant_kind", ...
    "status", "reason", "score_comparability", "one_to_one_units", "top_same", ...
    "top_different", "top_tie", "top_unscored", "top_orientation_unknown", ...
    "sets_equal", "sets_both_empty", "sets_differ", "status_agree", "status_disagree", ...
    "status_structural_empty", "status_excluded", "status_undecided", ...
    "reasons_changed", "scores_changed", "units_one_to_one", "units_one_to_many", ...
    "units_many_to_one", "units_many_to_many", "units_unmatched_left", ...
    "units_unmatched_right", "targets_lost", "targets_gained", "pairs", ...
    "pairs_top_same", "pairs_top_different"];
rows = table();
for name = names
    if ismember(name, names(1:8))
        rows.(name) = strings(0, 1);
    else
        rows.(name) = zeros(0, 1);
    end
end
end

function value = provenance(conn, family, record)
versions = fetch(conn, "SELECT schema_version AS version FROM schema_info");
v = record.variants;
value = struct(family_analysis_run_id=family.analysis_run_id, ...
    family_key=string(record.family_key), ...
    family_kind=fieldOr(record, "family_kind", "attribution"), ...
    reference_attribution_run_id=double(record.reference_attribution_run_id), ...
    reference_settings_profile_version_id=double(fieldOr(record, ...
        "reference_settings_profile_version_id", NaN)), ...
    reference_policy_profile_version_id=double(record.reference_policy_profile_version_id), ...
    variant_policy_profile_version_ids=[v.policy_profile_version_id], ...
    variant_settings_profile_version_ids=collect(v, "settings_profile_version_id"), ...
    variant_consensus_analysis_run_ids=collect(v, "consensus_analysis_run_id"), ...
    reference_specification=fieldOr(record, "reference_specification", struct()), ...
    design_sha256=string(record.design_sha256), ...
    schema_version=string(versions.version(1)), matlab_version=string(version));
end

function value = fieldOr(s, name, fallback)
value = fallback;
if isfield(s, name)
    value = s.(name);
end
end

function value = collect(v, name)
value = [];
if isfield(v, name)
    value = [v.(name)];
end
end

function value = summaryNote()
value = "Each row says how the comparison categories fall when one declared input " + ...
    "differs from the declared reference. Rows are ordered by handle and value, " + ...
    "never by outcome, and no row prefers a configuration. A handle that was not " + ...
    "varied is a row with its reason. On data this repository generated, every " + ...
    "movement is the generator's, and says nothing about any real recording.";
end
