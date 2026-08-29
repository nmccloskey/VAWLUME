function result = mupetExport(artifactPath, options)
%MUPETEXPORT Read a MUPET per-syllable CSV into validated extractor IR.
%
% RESULT = vawlume.ingest.mupetExport(ARTIFACTPATH, ...) reads one supported
% MUPET CSV with its native labels and lexical missing tokens preserved, then
% delegates all field semantics and unit transforms to SOURCE_MAPPING.
%
% This adapter performs no database access. MUPET version evidence must be
% supplied by the caller because the CSV does not carry a trustworthy version.
% SettingsConfigPath optionally captures the native two-column config.csv. A
% missing settings source is reported for later planning/apply policy but does
% not prevent inspection of otherwise valid event IR.

arguments
    artifactPath (1,1) string
    options.ProfilePath (1,1) string = ""
    options.Profile = []
    options.RepoRoot (1,1) string = ""
    options.ArtifactRoot (1,1) string = ""
    options.RelativePath (1,1) string = ""
    options.ArtifactKey (1,1) string = ""
    options.ExtractorVersion (1,1) string = ""
    options.SourceKey (1,1) string = ""
    options.SettingsConfigPath (1,1) string = ""
    options.SettingsArtifactRoot (1,1) string = ""
    options.SettingsRelativePath (1,1) string = ""
end

loaded = resolveProfile(options);
profileDocument = loaded.document;
assertMupetOutputProfile(profileDocument, loaded);

spec = mupetExportArtifactSpec(profileDocument, options.ArtifactKey);
readResult = mupetReadExportTable(artifactPath, spec, profileDocument);
location = mupetPortableLocation(artifactPath, options.RelativePath, ...
    [options.ArtifactRoot, options.RepoRoot]);
sourceKey = resolveSourceKey(options.SourceKey, spec, location);

ir = vawlume.source_mapping.mapTableToIR(readResult.table, loaded, ...
    SourceKey=sourceKey, ArtifactKey=spec.artifact_key, ...
    RuntimePath=location.runtime_path, RelativePath=location.relative_path, ...
    Filename=location.filename, RepoRoot=options.RepoRoot);

issues = emptyAdapterIssues();
issues = appendIssue(issues, emptyExportIssue(readResult, artifactPath));

% This helper is profile-driven and already proved correct for MUPET in the
% Phase 5 audit. Pass 3 owns its neutral rename alongside the other shared core.
versionAssessment = deepsqueakVersionCompatibility( ...
    profileDocument, options.ExtractorVersion);
issues = appendIssue(issues, versionIssue(versionAssessment));

settingsRoots = [options.SettingsArtifactRoot, options.ArtifactRoot, options.RepoRoot];
settings = mupetCaptureSettings(options.SettingsConfigPath, profileDocument, ...
    ExtractorVersion=options.ExtractorVersion, ...
    RelativePath=options.SettingsRelativePath, Roots=settingsRoots);
issues = appendIssues(issues, settings.issues);

result = struct();
result.ir = ir;
result.table = readResult.table;
result.artifact = artifactProvenance(artifactPath, spec, readResult, location);
result.profile = profileProvenanceSummary(loaded, ir);
result.profile_document = profileDocument;
result.extractor_version = versionAssessment;
result.settings = settings;
result.issues = issues;
result.source_key = sourceKey;
result.adapter_error_count = nnz(issues.severity == "error");
result.adapter_warning_count = nnz(issues.severity == "warning");
result.valid_for_ingest = ir.valid_for_ingest && result.adapter_error_count == 0;
end

function loaded = resolveProfile(options)
if ~isempty(options.Profile)
    loaded = options.Profile;
    if ~isstruct(loaded) || ~isfield(loaded, "document")
        error("vawlume:ingest:MupetProfileUnsupported", ...
            "Profile must be a loaded profile bundle from vawlume.source_mapping.loadProfile.");
    end
    return
end

profilePath = options.ProfilePath;
if strlength(profilePath) == 0
    if strlength(options.RepoRoot) == 0
        error("vawlume:ingest:MupetProfileUnsupported", ...
            ['Supply ProfilePath, Profile, or RepoRoot so the tracked MUPET ' ...
            'output mapping profile can be located.']);
    end
    profilePath = fullfile(options.RepoRoot, "config", "01_mapping_profiles", ...
        "extractors", "mupet", "mupet_output_mapping_profile.json");
end
loaded = vawlume.source_mapping.loadProfile(profilePath, ...
    ExpectedKind="extractor_output", RepoRoot=options.RepoRoot);
end

function assertMupetOutputProfile(document, loaded)
kind = profileText(document.profile, "kind");
extractorName = profileText(document.extractor, "name");
if lower(kind) ~= "extractor_output" || lower(extractorName) ~= "mupet"
    identity = "unknown profile";
    try
        identity = string(loaded.document.profile.id);
    catch
    end
    error("vawlume:ingest:MupetProfileUnsupported", ...
        "Expected a MUPET extractor-output profile, found '%s' (%s).", ...
        extractorName, identity);
end
end

function sourceKey = resolveSourceKey(explicitKey, spec, location)
if strlength(explicitKey) > 0
    sourceKey = explicitKey;
    return
end
identity = location.relative_path;
if strlength(identity) == 0
    identity = location.filename;
end
sourceKey = "mupet:" + spec.artifact_key + ":" + identity;
end

function provenance = artifactProvenance(path, spec, readResult, location)
provenance = struct( ...
    artifact_key=spec.artifact_key, ...
    native_artifact_type=spec.native_artifact_type, ...
    canonical_artifact_type=spec.canonical_artifact_type, ...
    file_format=spec.file_format, ...
    runtime_path=location.runtime_path, ...
    relative_path=location.relative_path, ...
    relative_path_source=location.relative_path_source, ...
    filename=location.filename, ...
    checksum_sha256=sha256OfFile(path), ...
    size_bytes=fileSizeBytes(path), ...
    delimiter=readResult.delimiter, ...
    header_row=readResult.header_row, ...
    row_count=readResult.row_count, ...
    column_count=readResult.column_count, ...
    source_columns=readResult.source_columns, ...
    lexical_columns=readResult.lexical_columns);
end

function summary = profileProvenanceSummary(loaded, ir)
summary = ir.profile;
summary.profile_source_path = string(loaded.source_path);
summary.profile_relative_path = string(loaded.relative_path);
summary.profile_checksum_sha256 = string(loaded.checksum_sha256);
end

function bytes = fileSizeBytes(path)
bytes = NaN;
info = dir(path);
if ~isempty(info)
    bytes = double(info(1).bytes);
end
end

function issue = emptyExportIssue(readResult, path)
issue = [];
if readResult.row_count == 0
    issue = adapterIssue("warning", "CSV_NO_DATA_ROWS", path, ...
        "MUPET CSV contains native headers but no event rows.");
end
end

function issue = versionIssue(assessment)
issue = [];
if assessment.status ~= "preferred"
    issue = adapterIssue(assessment.severity, ...
        "EXTRACTOR_VERSION_" + upper(assessment.status), ...
        "extractor.version_scope", assessment.message);
end
end

function issues = emptyAdapterIssues()
issues = table(strings(0,1), strings(0,1), strings(0,1), strings(0,1), ...
    VariableNames=["severity", "code", "location", "message"]);
end

function issue = adapterIssue(severity, code, location, message)
issue = struct(severity=string(severity), code=string(code), ...
    location=string(location), message=string(message));
end

function issues = appendIssues(issues, additions)
for index = 1:height(additions)
    issues(end + 1, :) = additions(index, :); %#ok<AGROW>
end
end

function issues = appendIssue(issues, issue)
if ~isempty(issue)
    issues(end + 1, :) = {issue.severity, issue.code, issue.location, issue.message};
end
end

function value = profileText(container, field)
value = "";
if isstruct(container) && isfield(container, char(field))
    try
        value = string(container.(char(field)));
    catch
    end
end
end
