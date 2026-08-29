function extractor = extractorResolveIdentity(conn, irProfile, declaredVersion, errorToken)
%EXTRACTORRESOLVEIDENTITY Resolve extractor and exact run-version provenance.

arguments
    conn
    irProfile (1,1) struct
    declaredVersion (1,1) string
    errorToken (1,1) string
end

name = string(irProfile.extractor_name);
if strlength(name) == 0
    error(errorId(errorToken, "ExtractorUnregistered"), ...
        "The mapping profile declares no extractor name.");
end
rows = fetch(conn, "SELECT extractor_id, extractor_key FROM extractors WHERE extractor_name = " + sqlText(name));
if isempty(rows) || height(rows) == 0
    error(errorId(errorToken, "ExtractorUnregistered"), ...
        "Extractor '%s' is not registered. Run vawlume.db.registerBuiltinSemantics first.", name);
end
extractor = struct(extractor_name=name, extractor_id=double(rows.extractor_id(1)), ...
    extractor_key=string(rows.extractor_key(1)), declared_version=declaredVersion, ...
    scope_version_label=string(irProfile.extractor_version_scope_preferred), ...
    version_action="reuse", conflict_message="", warnings=strings(0,1));
versions = fetch(conn, "SELECT extractor_version_id, version_label FROM extractor_versions " + ...
    "WHERE extractor_id = " + string(extractor.extractor_id));
extractor.feature_version_id = versionIdFor(versions, extractor.scope_version_label);
if isnan(extractor.feature_version_id)
    error(errorId(errorToken, "ExtractorUnregistered"), ...
        "No extractor_versions row exists for %s version scope '%s'.", ...
        name, extractor.scope_version_label);
end
extractor.run_version_id = versionIdFor(versions, declaredVersion);
if isnan(extractor.run_version_id), extractor.version_action = "create"; end
extractor.run_version_label = declaredVersion;
extractor.version_matches_feature_scope = extractor.version_action == "reuse" && ...
    extractor.run_version_id == extractor.feature_version_id;
if ~extractor.version_matches_feature_scope
    extractor.warnings(end+1,1) = "Run extractor version '" + declaredVersion + ...
        "' differs from the profile-registered feature scope '" + ...
        extractor.scope_version_label + "'. Feature semantics resolve against the scope row.";
end
end

function id = versionIdFor(rows, label)
id = NaN;
if isempty(rows) || height(rows) == 0 || strlength(label) == 0, return, end
matches = string(rows.version_label) == label;
if any(matches), id = double(rows.extractor_version_id(find(matches,1))); end
end
function value = errorId(token, suffix), value = "vawlume:ingest:" + token + suffix; end
function value = sqlText(text), value = "'" + replace(string(text), "'", "''") + "'"; end
