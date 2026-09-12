function [target, run, candidate] = attributionResolveEvidenceRef(conn, ref)
%ATTRIBUTIONRESOLVEEVIDENCEREF Resolve target- or candidate-level evidence scope.

if ~isstruct(ref) || ~isscalar(ref)
    error("vawlume:attribution:EvidenceRefInvalid", ...
        "Evidence ref must be a scalar struct.");
end
candidate = struct(attribution_candidate_id=NaN, entity_id=NaN, ...
    candidate_status="");
if ~isfield(ref, "attribution_candidate_id")
    [target, run] = attributionResolveTarget(conn, ref);
    return
end
if numel(fieldnames(ref)) ~= 1
    error("vawlume:attribution:EvidenceRefInvalid", ...
        "A candidate evidence ref contains attribution_candidate_id only.");
end
candidateId = positiveInteger(ref.attribution_candidate_id);
rows = fetch(conn, "SELECT attribution_target_id, entity_id, candidate_status " + ...
    "FROM attribution_candidates WHERE attribution_candidate_id=" + ...
    string(candidateId));
if isempty(rows) || height(rows) == 0
    error("vawlume:attribution:CandidateNotFound", ...
        "Attribution candidate %d does not exist.", candidateId);
end
[target, run] = attributionResolveTarget(conn, struct( ...
    attribution_target_id=double(rows.attribution_target_id(1))));
candidate = struct(attribution_candidate_id=candidateId, ...
    entity_id=double(rows.entity_id(1)), ...
    candidate_status=presentText(rows.candidate_status(1)));
end

function value = positiveInteger(raw)
if ~isnumeric(raw) || ~isscalar(raw) || ~isfinite(raw) || ...
        raw < 1 || fix(raw) ~= raw
    error("vawlume:attribution:EvidenceRefInvalid", ...
        "attribution_candidate_id must be a positive integer.");
end
value = double(raw);
end

function value = presentText(raw)
value = string(raw);
value(ismissing(value)) = "";
end
