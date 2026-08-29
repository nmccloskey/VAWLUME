function report = deepsqueakValidateEvents(routed, profileDocument)
%DEEPSQUEAKVALIDATEEVENTS Apply the profile's declared event validation checks.
%
% Check identity and severity are read from the profile's validation.checks
% block, so the profile decides what blocks an import and what is merely
% reported. The comparison for each known check id is implemented here; a
% general evaluator for the profile's expression strings remains future work and
% is reported as an unevaluated check rather than silently passing.
%
% Error-severity checks are write guards: they run before any row is planned, so
% a bad export is refused rather than aborting mid-transaction on a schema CHECK.

arguments
    routed (1,1) struct
    profileDocument (1,1) struct
end

declared = declaredChecks(profileDocument);
report = struct();
report.errors = strings(0, 1);
report.warnings = strings(0, 1);
report.unevaluated_checks = strings(0, 1);
report.evaluated_checks = strings(0, 1);

implemented = ["event_time_order", "duration_consistency", "frequency_order", ...
    "bandwidth_consistency", "native_event_id_uniqueness"];
names = string(fieldnames(declared));
for index = 1:numel(names)
    if ~ismember(names(index), implemented)
        report.unevaluated_checks(end + 1, 1) = names(index);
    end
end

report = runIdentityChecks(report, routed, declared);
for index = 1:numel(routed.rows)
    report = runRowChecks(report, routed.rows{index}, declared);
end
report.evaluated_checks = intersect(names, implemented);
report.is_valid = isempty(report.errors);
end

function report = runIdentityChecks(report, routed, declared)
check = "native_event_id_uniqueness";
if ~isfield(declared, check)
    return
end

identifiers = strings(0, 1);
for index = 1:numel(routed.rows)
    row = routed.rows{index};
    if row.native_event_id_status ~= "present"
        report = appendFinding(report, declared.(check), ...
            "Row " + string(row.source_row) + " has no native call identifier. " + ...
            "An identifier is required and is never fabricated from row order.");
        continue
    end
    identifiers(end + 1, 1) = row.native_event_id; %#ok<AGROW>
end

if numel(identifiers) < 2
    return
end
sorted = sort(identifiers);
repeated = unique(sorted(sorted(1:end - 1) == sorted(2:end)));
for index = 1:numel(repeated)
    report = appendFinding(report, declared.(check), ...
        "Native call identifier '" + repeated(index) + ...
        "' appears more than once in one artifact.");
end
end

function report = runRowChecks(report, row, declared)
label = "Row " + string(row.source_row) + " (call " + row.native_event_id + ")";

if isfield(declared, "event_time_order")
    if isnan(row.start_time_s) || isnan(row.end_time_s)
        report = appendFinding(report, declared.event_time_order, ...
            label + " is missing a start or end time.");
    elseif row.start_time_s < 0
        report = appendFinding(report, declared.event_time_order, ...
            label + " has a negative start time.");
    elseif row.end_time_s < row.start_time_s
        report = appendFinding(report, declared.event_time_order, ...
            label + " ends before it starts.");
    end
end

if isfield(declared, "frequency_order") && ...
        ~isnan(row.frequency_min) && ~isnan(row.frequency_max) && ...
        row.frequency_min > row.frequency_max
    report = appendFinding(report, declared.frequency_order, ...
        label + " reports a minimum frequency above its maximum frequency.");
end

if isfield(declared, "duration_consistency") && ~isnan(row.duration_s) && ...
        ~isnan(row.start_time_s) && ~isnan(row.end_time_s)
    expected = row.end_time_s - row.start_time_s;
    if abs(row.duration_s - expected) > consistencyTolerance()
        % Reported, never repaired. Overwriting one timing field with another
        % would destroy the extractor's own measurement.
        report = appendFinding(report, declared.duration_consistency, ...
            label + " reports duration " + string(row.duration_s) + " s, but " + ...
            "its end minus start is " + string(expected) + " s.");
    end
end

if isfield(declared, "bandwidth_consistency") && ~isnan(row.frequency_bandwidth) && ...
        ~isnan(row.frequency_min) && ~isnan(row.frequency_max)
    expected = row.frequency_max - row.frequency_min;
    if abs(row.frequency_bandwidth - expected) > consistencyTolerance()
        report = appendFinding(report, declared.bandwidth_consistency, ...
            label + " reports bandwidth " + string(row.frequency_bandwidth) + ...
            ", but its maximum minus minimum frequency is " + string(expected) + ".");
    end
end
end

function tolerance = consistencyTolerance()
% The profile declares tolerance_source as profile_or_project_config, and
% neither currently declares a value. This default absorbs spreadsheet rounding
% without hiding a real disagreement, and applies only to warning-severity
% consistency checks.
tolerance = 1e-6;
end

function report = appendFinding(report, check, message)
message = "[" + check.id + "] " + message;
switch check.severity
    case "error"
        report.errors(end + 1, 1) = message;
    otherwise
        report.warnings(end + 1, 1) = message;
end
end

function declared = declaredChecks(profileDocument)
declared = struct();
if ~isfield(profileDocument, "validation") || ~isstruct(profileDocument.validation)
    return
end
validation = profileDocument.validation;
if ~isfield(validation, "checks")
    return
end

items = validation.checks;
if iscell(items)
    items = items(:)';
elseif isstruct(items)
    items = arrayfun(@(item) item, items(:)', UniformOutput=false);
else
    return
end

for index = 1:numel(items)
    item = items{index};
    id = fieldText(item, "id");
    if strlength(id) == 0 || ~isvarname(char(id))
        continue
    end
    severity = lower(fieldText(item, "severity"));
    if ~ismember(severity, ["info", "warning", "error"])
        severity = "warning";
    end
    declared.(char(id)) = struct(id=id, severity=severity);
end
end

function value = fieldText(container, field)
value = "";
if ~isstruct(container) || ~isfield(container, char(field))
    return
end
try
    candidate = string(container.(char(field)));
catch
    return
end
if isscalar(candidate) && ~ismissing(candidate)
    value = strtrim(candidate);
end
end
