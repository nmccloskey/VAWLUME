function contract = trackingColumnContract(conn, stream, tbl, repoRoot)
%TRACKINGCOLUMNCONTRACT Which artifact column plays which tracking role.
%
% The contract lives in the mapping profile, which registration recorded as a
% checksummed config_profile_versions row. The reader loads that exact profile
% and resolves the roles through **the mapper itself** rather than reimplementing
% the role-to-column rules.
%
% That matters: a second implementation of "which column is position_x" would
% drift from the first, and the drift would appear as samples silently read from
% the wrong column rather than as an error. Calling the mapper costs one extra
% pass that is O(series) and O(1) in the artifact's height - it derives the same
% summaries registration did, which is also a free consistency check.

rows = fetch(conn, "SELECT cpv.content_uri, cp.profile_key " + ...
    "FROM external_stream_sources ess " + ...
    "JOIN config_profile_versions cpv " + ...
    "ON cpv.profile_version_id=ess.mapping_profile_version_id " + ...
    "JOIN config_profiles cp ON cp.profile_id=cpv.profile_id " + ...
    "WHERE ess.external_stream_id=" + string(stream.external_stream_id));

if isempty(rows) || height(rows) == 0
    error("vawlume:tracking:MappingProfileUnregistered", ...
        "Tracking stream '%s' has no registered mapping profile version, so " + ...
        "its column contract cannot be resolved. The reader never guesses " + ...
        "which artifact column holds which role.", stream.stream_name);
end

contentUri = trackingPresentText(rows.content_uri(1));
profileKey = trackingPresentText(rows.profile_key(1));
profilePath = resolveProfilePath(contentUri, repoRoot);

ir = vawlume.source_mapping.mapTableToIR(tbl, profilePath, ...
    ProfileId=profileKey, RepoRoot=repoRoot);

contract = struct(position_x="", position_y="", position_z="", ...
    track_label="", bodypart_label="", native_time="", native_frame="", ...
    confidence="");

for index = 1:height(ir.tracking_columns)
    row = ir.tracking_columns(index, :);
    role = trackingPresentText(row.role);
    if ~isfield(contract, role)
        continue
    end
    contract.(role) = trackingPresentText(row.actual_source_field);
end

missing = strings(0, 1);
for role = ["position_x", "position_y", "track_label", "bodypart_label"]
    if strlength(contract.(role)) == 0
        missing(end + 1, 1) = role; %#ok<AGROW>
    end
end
if ~isempty(missing)
    error("vawlume:tracking:ColumnContractUnresolved", ...
        "The registered mapping profile does not resolve %s against this " + ...
        "artifact. The file may have changed since registration.", ...
        strjoin(missing(:)', ", "));
end
end

function path = resolveProfilePath(contentUri, repoRoot)
path = string(contentUri);
if isfile(path)
    return
end
candidate = string(fullfile(repoRoot, contentUri));
if isfile(candidate)
    path = candidate;
    return
end
error("vawlume:tracking:MappingProfileNotFound", ...
    "The registered mapping profile '%s' could not be located. Supply " + ...
    "RepoRoot if the repository moved since registration.", contentUri);
end
