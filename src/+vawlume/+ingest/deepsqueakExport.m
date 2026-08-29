function result = deepsqueakExport(artifactPath, options)
%DEEPSQUEAKEXPORT Read a DeepSqueak call-statistics export into validated IR.
%
% RESULT = vawlume.ingest.deepsqueakExport(ARTIFACTPATH) opens a supported
% DeepSqueak Excel call-statistics export, reads the profile-selected sheet with
% source column labels preserved, and routes the resulting MATLAB table through
% VAWLUME.SOURCE_MAPPING.MAPTABLETOIR using the tracked DeepSqueak
% extractor-output mapping profile.
%
% The function owns workbook mechanics only. Field semantics - canonical names,
% units, transforms, value maps, operational definitions, and missing-value
% policy - remain entirely in the tracked mapping profile and are applied by
% VAWLUME.SOURCE_MAPPING. This function contains no native-to-canonical
% dictionary.
%
% It performs no database access. The returned IR is the input to the Phase 4
% database-facing importer, and it can be inspected first with:
%
%   preview = vawlume.source_mapping.preview(result.ir);
%
% Name-value options:
%   ProfilePath      Mapping profile JSON to use. Defaults to the tracked
%                    DeepSqueak profile beneath RepoRoot.
%   Profile          Already-loaded profile bundle, used instead of reading the
%                    profile JSON again.
%   RepoRoot         Repository root used to locate the default profile and, as
%                    a fallback, to derive a portable artifact path.
%   ArtifactRoot     Root the artifact's portable relative path is taken from.
%   RelativePath     Explicit portable artifact path, overriding root-derived
%                    values.
%   Sheet            Explicit sheet name, overriding the profile's selector.
%   ArtifactKey      Declared artifact to read. Defaults to the profile's
%                    field_mapping_source.artifact_key.
%   ExtractorVersion Caller-supplied DeepSqueak version. The workbook does not
%                    encode a trustworthy version, so none is invented when this
%                    is omitted.
%   SourceKey        Explicit IR source key, overriding the derived one.
%
% RESULT fields:
%   ir                 unified source-mapping IR for the export
%   table              the read MATLAB table, with source labels preserved
%   artifact           file/workbook provenance for later artifact registration
%   profile            resolved mapping-profile identity and provenance
%   extractor_version  version-scope assessment
%   issues             adapter-level diagnostics (workbook and version scope)
%   source_key         the IR source key used
%   valid_for_ingest   IR validity combined with adapter-level errors
%
% Supported artifact class: DeepSqueak Excel call-statistics export
% ("event_stats_excel"), profile version scope 3.2.x preferred / 3.x family.
% Native .mat detection containers, detector networks, and classification models
% are not read by this function.
%
% See also VAWLUME.SOURCE_MAPPING.MAPTABLETOIR, VAWLUME.SOURCE_MAPPING.PREVIEW.

arguments
    artifactPath (1,1) string
    options.ProfilePath (1,1) string = ""
    options.Profile = []
    options.RepoRoot (1,1) string = ""
    options.ArtifactRoot (1,1) string = ""
    options.RelativePath (1,1) string = ""
    options.Sheet (1,1) string = ""
    options.ArtifactKey (1,1) string = ""
    options.ExtractorVersion (1,1) string = ""
    options.SourceKey (1,1) string = ""
end

loaded = resolveProfile(options);
profileDocument = loaded.document;
assertDeepSqueakOutputProfile(profileDocument, loaded);

spec = deepsqueakExportArtifactSpec(profileDocument, options.ArtifactKey);
readResult = deepsqueakReadExportTable(artifactPath, spec, options.Sheet);

issues = emptyAdapterIssues();
issues = appendAdapterIssue(issues, sheetIssue(readResult, artifactPath));
issues = appendAdapterIssue(issues, emptyExportIssue(readResult, artifactPath));

versionAssessment = deepsqueakVersionCompatibility(profileDocument, options.ExtractorVersion);
issues = appendAdapterIssue(issues, versionIssue(versionAssessment));

location = artifactLocation(artifactPath, options);
sourceKey = resolveSourceKey(options.SourceKey, spec, location);

ir = vawlume.source_mapping.mapTableToIR(readResult.table, loaded, ...
    SourceKey=sourceKey, ...
    ArtifactKey=spec.artifact_key, ...
    RuntimePath=location.runtime_path, ...
    RelativePath=location.relative_path, ...
    Filename=location.filename, ...
    RepoRoot=options.RepoRoot);

result = struct();
result.ir = ir;
result.table = readResult.table;
result.artifact = artifactProvenance(artifactPath, spec, readResult, location);
result.profile = profileProvenanceSummary(loaded, ir);
result.extractor_version = versionAssessment;
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
        error("vawlume:ingest:DeepSqueakProfileUnsupported", ...
            "Profile must be a loaded profile bundle from vawlume.source_mapping.loadProfile.");
    end
    return
end

profilePath = options.ProfilePath;
if strlength(profilePath) == 0
    repoRoot = options.RepoRoot;
    if strlength(repoRoot) == 0
        error("vawlume:ingest:DeepSqueakProfileUnsupported", ...
            ['Supply ProfilePath, Profile, or RepoRoot so the tracked ' ...
            'DeepSqueak output mapping profile can be located.']);
    end
    profilePath = fullfile(repoRoot, "config", "01_mapping_profiles", ...
        "extractors", "deepsqueak", "deepsqueak_output_mapping_profile.json");
end

loaded = vawlume.source_mapping.loadProfile(profilePath, ...
    ExpectedKind="extractor_output", RepoRoot=options.RepoRoot);
end

function assertDeepSqueakOutputProfile(profileDocument, loaded)
kind = "";
if isfield(profileDocument, "profile") && isfield(profileDocument.profile, "kind")
    kind = lower(string(profileDocument.profile.kind));
end
if kind ~= "extractor_output"
    error("vawlume:ingest:DeepSqueakProfileUnsupported", ...
        "Expected an extractor_output profile, found '%s'.", kind);
end

extractorName = "";
if isfield(profileDocument, "extractor") && isfield(profileDocument.extractor, "name")
    extractorName = string(profileDocument.extractor.name);
end
if lower(extractorName) ~= "deepsqueak"
    error("vawlume:ingest:DeepSqueakProfileUnsupported", ...
        "Expected a DeepSqueak extractor-output profile, found '%s' (%s).", ...
        extractorName, profileIdentity(loaded));
end
end

function identity = profileIdentity(loaded)
identity = "unknown profile";
try
    identity = string(loaded.document.profile.id);
catch
end
end

function location = artifactLocation(artifactPath, options)
runtimePath = string(java.io.File(char(artifactPath)).getAbsolutePath());
[~, stem, extension] = fileparts(runtimePath);

location = struct();
location.runtime_path = runtimePath;
location.filename = string(stem) + string(extension);
location.relative_path = "";
location.relative_path_source = "unavailable";

if strlength(options.RelativePath) > 0
    location.relative_path = replace(options.RelativePath, "\", "/");
    location.relative_path_source = "declared";
    return
end

roots = [ ...
    struct(path=options.ArtifactRoot, label="artifact_root"), ...
    struct(path=options.RepoRoot, label="repo_root")];
for index = 1:numel(roots)
    root = roots(index);
    if strlength(root.path) == 0
        continue
    end
    info = vawlume.source_mapping.normalizeRelativePath(runtimePath, root.path, ...
        MustBeInsideRoot=false);
    if info.is_inside_root
        location.relative_path = info.relative_path;
        location.relative_path_source = root.label;
        return
    end
end
end

function sourceKey = resolveSourceKey(explicitKey, spec, location)
%RESOLVESOURCEKEY Build a deterministic, root-independent IR source key.
%
% The key is derived from the artifact's portable identity when one is known and
% from its filename otherwise. It never embeds an absolute runtime root, so the
% same artifact under a different checkout yields the same key.

if strlength(explicitKey) > 0
    sourceKey = explicitKey;
    return
end

identity = location.relative_path;
if strlength(identity) == 0
    identity = location.filename;
end
sourceKey = "deepsqueak:" + spec.artifact_key + ":" + identity;
end

function provenance = artifactProvenance(artifactPath, spec, readResult, location)
provenance = struct();
provenance.artifact_key = spec.artifact_key;
provenance.native_artifact_type = spec.native_artifact_type;
provenance.canonical_artifact_type = spec.canonical_artifact_type;
provenance.file_format = spec.file_format;
provenance.runtime_path = location.runtime_path;
provenance.relative_path = location.relative_path;
provenance.relative_path_source = location.relative_path_source;
provenance.filename = location.filename;
provenance.checksum_sha256 = sha256OfFile(artifactPath);
provenance.size_bytes = fileSizeBytes(artifactPath);
provenance.sheet_name = readResult.sheet_name;
provenance.sheet_index = readResult.sheet_index;
provenance.sheet_names = readResult.sheet_names;
provenance.sheet_selection_rule = readResult.sheet_selection_rule;
provenance.header_row = readResult.header_row;
provenance.row_count = readResult.row_count;
provenance.column_count = readResult.column_count;
provenance.source_columns = readResult.source_columns;
end

function summary = profileProvenanceSummary(loaded, ir)
summary = ir.profile;
summary.profile_source_path = string(loaded.source_path);
summary.profile_relative_path = string(loaded.relative_path);
summary.profile_checksum_sha256 = string(loaded.checksum_sha256);
end

function bytes = fileSizeBytes(artifactPath)
bytes = NaN;
info = dir(artifactPath);
if ~isempty(info)
    bytes = double(info(1).bytes);
end
end

function issue = sheetIssue(readResult, artifactPath)
issue = [];
if numel(readResult.sheet_names) <= 1
    return
end
issue = makeAdapterIssue("info", "WORKBOOK_MULTIPLE_SHEETS", artifactPath, ...
    "Workbook contains " + numel(readResult.sheet_names) + " sheets; read '" + ...
    readResult.sheet_name + "' by rule " + readResult.sheet_selection_rule + ".");
end

function issue = emptyExportIssue(readResult, artifactPath)
issue = [];
if readResult.row_count > 0
    return
end
issue = makeAdapterIssue("warning", "WORKBOOK_NO_DATA_ROWS", artifactPath, ...
    "Sheet '" + readResult.sheet_name + "' contains header labels but no data rows.");
end

function issue = versionIssue(assessment)
issue = [];
if assessment.severity == "info" && assessment.status == "preferred"
    return
end
issue = makeAdapterIssue(assessment.severity, ...
    "EXTRACTOR_VERSION_" + upper(assessment.status), ...
    "extractor.version_scope", assessment.message);
end

function issues = emptyAdapterIssues()
issues = table(strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    VariableNames=["severity", "code", "location", "message"]);
end

function issue = makeAdapterIssue(severity, code, location, message)
issue = struct(severity=string(severity), code=string(code), ...
    location=string(location), message=string(message));
end

function issues = appendAdapterIssue(issues, issue)
if isempty(issue)
    return
end
issues(end + 1, :) = {issue.severity, issue.code, issue.location, issue.message};
end
