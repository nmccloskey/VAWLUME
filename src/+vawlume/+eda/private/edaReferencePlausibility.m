function reference = edaReferencePlausibility(source)
%EDAREFERENCEPLAUSIBILITY Read the reference configuration's declared bounds, for comparison only.
%
% The governing contract anchors support-pattern characterization on one named
% reference configuration, and requires the screen to report whether each probed
% interval brackets that configuration's value. This reads those values.
%
% IT IS NOT A SECOND SPECIFICATION LOADER, and it must not become one. It
% validates nothing, applies no default, and never feeds execution: the
% authoritative interpretation of a matching specification is
% vawlume.matching.compare's own private loader, which refuses a malformed file.
% This read exists so a REPORT can say where the reference sits relative to a
% probed interval. If the two ever disagreed about a value, the matcher would be
% right and this report would be wrong, which is the correct way round.
%
% Absent means unconstrained, exactly as the matching contract fixes it, and is
% returned as NaN. That case is not hypothetical: the tracked reference
% configuration declares min_temporal_iou and none of the three max_abs_ bounds,
% so three of four factors have no reference value for an interval to bracket.
%
% SOURCE is a path to a specification file, or a struct already holding a
% plausibility rule.
%
% The calibration status is carried out with the identity, because using a file
% as a reference configuration does not make it calibrated and a report naming it
% must say so.

reference = emptyReference();
if isstruct(source)
    reference.available = true;
    reference.source = "supplied_struct";
    reference = readRule(reference, source);
    return
end

path = string(source);
if ~isscalar(path) || ismissing(path) || strlength(path) == 0
    return
end
if ~isfile(path)
    reference.source = string(path);
    reference.unavailable_reason = "file_not_found";
    return
end
try
    document = jsondecode(fileread(path));
catch exception
    reference.source = string(path);
    reference.unavailable_reason = "undecodable: " + string(exception.message);
    return
end

reference.available = true;
reference.source = string(path);
reference = readIdentity(reference, document);
if isfield(document, "candidate_generation") && ...
        isfield(document.candidate_generation, "plausibility_rule")
    reference = readRule(reference, document.candidate_generation.plausibility_rule);
end
end

function reference = readIdentity(reference, document)
if isfield(document, "profile")
    reference.profile_key = textField(document.profile, "id");
    reference.profile_version = textField(document.profile, "profile_version");
end
if isfield(document, "calibration_status")
    reference.calibration_state = textField(document.calibration_status, "state");
    reference.calibration_meaning = textField(document.calibration_status, ...
        "meaning");
end
end

function reference = readRule(reference, rule)
if ~isstruct(rule) || ~isscalar(rule)
    return
end
for name = ["min_temporal_iou", edaGateBoundNames()]
    if ~isfield(rule, name)
        continue
    end
    value = rule.(name);
    if isnumeric(value) && isscalar(value) && isreal(value) && isfinite(value)
        reference.values.(name) = double(value);
    end
end
end

function value = textField(container, name)
value = "";
if ~isfield(container, name)
    return
end
try
    value = string(container.(name));
catch
    return
end
if ~isscalar(value) || ismissing(value)
    value = "";
end
end

function reference = emptyReference()
values = struct();
for name = ["min_temporal_iou", edaGateBoundNames()]
    values.(name) = NaN;
end
reference = struct( ...
    available=false, ...
    source="", ...
    unavailable_reason="not_supplied", ...
    profile_key="", ...
    profile_version="", ...
    calibration_state="", ...
    calibration_meaning="", ...
    values=values);
end
