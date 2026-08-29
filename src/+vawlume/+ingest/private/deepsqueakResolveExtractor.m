function extractor = deepsqueakResolveExtractor(conn, irProfile, declaredVersion)
%DEEPSQUEAKRESOLVEEXTRACTOR Resolve extractor identity and the run's version row.
%
% The extractor dictionary belongs to the semantic seed layer, so this function
% never inserts an extractors row. It resolves DeepSqueak by the name the tracked
% profile declares, then separates two distinct version concepts:
%
%   feature_version_id - the row seed registration attached extractor_features
%                        to, which is the profile's declared compatibility scope
%                        (for example 3.2.x). Event measurements resolve their
%                        feature identity against this row.
%   run_version_id     - the exact DeepSqueak version this run actually used, as
%                        declared by the caller. This is what the extraction run
%                        records as its software provenance.
%
% They coincide when the caller declares the scope label itself. When they do
% not, both are reported rather than one being silently substituted for the
% other: no foreign key ties event_measurements to the run's version, so the
% exact software version and the feature semantics each stay answerable.

arguments
    conn
    irProfile (1,1) struct
    declaredVersion (1,1) string
end

extractorName = string(irProfile.extractor_name);
if strlength(extractorName) == 0
    error("vawlume:ingest:DeepSqueakExtractorUnregistered", ...
        "The mapping profile declares no extractor name.");
end

rows = fetch(conn, ...
    "SELECT extractor_id, extractor_key FROM extractors " + ...
    "WHERE extractor_name = " + sqlText(extractorName));
if isempty(rows) || height(rows) == 0
    error("vawlume:ingest:DeepSqueakExtractorUnregistered", ...
        ['Extractor ''%s'' is not registered. Run ' ...
        'vawlume.db.registerBuiltinSemantics before importing extractor output.'], ...
        extractorName);
end

extractor = struct();
extractor.extractor_name = extractorName;
extractor.extractor_id = double(rows.extractor_id(1));
extractor.extractor_key = string(rows.extractor_key(1));
extractor.declared_version = declaredVersion;
extractor.scope_version_label = string(irProfile.extractor_version_scope_preferred);
extractor.version_action = "reuse";
extractor.conflict_message = "";
extractor.warnings = strings(0, 1);

versions = fetch(conn, ...
    "SELECT extractor_version_id, version_label FROM extractor_versions " + ...
    "WHERE extractor_id = " + string(extractor.extractor_id));

extractor.feature_version_id = versionIdFor(versions, extractor.scope_version_label);
if isnan(extractor.feature_version_id)
    error("vawlume:ingest:DeepSqueakExtractorUnregistered", ...
        ['No extractor_versions row exists for %s version scope ''%s''. ' ...
        'Run vawlume.db.registerBuiltinSemantics before importing extractor output.'], ...
        extractorName, extractor.scope_version_label);
end

extractor.run_version_id = versionIdFor(versions, declaredVersion);
if isnan(extractor.run_version_id)
    extractor.version_action = "create";
    extractor.run_version_id = NaN;
end
extractor.run_version_label = declaredVersion;
extractor.version_matches_feature_scope = ...
    extractor.version_action == "reuse" && ...
    extractor.run_version_id == extractor.feature_version_id;

if ~extractor.version_matches_feature_scope
    extractor.warnings(end + 1, 1) = ...
        "Run extractor version '" + declaredVersion + "' differs from the " + ...
        "profile-registered feature scope '" + extractor.scope_version_label + ...
        "'. Feature semantics resolve against the scope row.";
end
end

function id = versionIdFor(versions, label)
id = NaN;
if isempty(versions) || height(versions) == 0 || strlength(label) == 0
    return
end
matches = string(versions.version_label) == label;
if any(matches)
    id = double(versions.extractor_version_id(find(matches, 1)));
end
end

function text = sqlText(value)
text = "'" + replace(string(value), "'", "''") + "'";
end
