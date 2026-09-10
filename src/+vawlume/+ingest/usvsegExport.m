function result = usvsegExport(artifactPath, options)
%USVSEGEXPORT Read a USVSEG event CSV into validated extractor IR.
%
% RESULT = vawlume.ingest.usvsegExport(ARTIFACTPATH, ...) preserves the source
% CSV's literal labels and value tokens, then delegates field semantics and
% unit transforms to SOURCE_MAPPING. This adapter performs no database access,
% so it is the boundary at which an export can be inspected before anything is
% written:
%
%   export = vawlume.ingest.usvsegExport(csvPath, RepoRoot=repoRoot, ...
%       ExtractorVersion="0.9r2");
%   vawlume.source_mapping.preview(export.ir, Print=true);
%
% Only the profile-selected `usvseg_dat_csv` artifact is read. The adapter does
% not wrap or run USVSEG, and does not read the optional peak-trace CSVs,
% segment WAVs, or spectrogram images.
%
% The literal `#` identifier column is preserved rather than rewritten into a
% reader-generated variable name, and every cell is read as a string before
% source mapping, so the exact printed token stays recoverable while the
% profile performs numeric typing and unit transforms. A header-only export is
% a valid zero-detection result; a zero-byte file is unreadable. Unknown source
% columns remain in RESULT.table and are reported by the shared mapper under
% the profile's preserve_and_warn policy.
%
% USVSEG writes no version into its outputs, so ExtractorVersion is caller
% evidence and is assessed against the mapping profile's declared scope.
% RESULT.extractor_version reports that assessment and RESULT.issues carries
% the corresponding adapter warning; enforcing the profile's
% required-at-ingest policy is the database-facing importer's job.
%
% RESULT fields: ir, table, artifact, profile, profile_document,
% extractor_version, issues, source_key, adapter_error_count,
% adapter_warning_count, and valid_for_ingest.
%
% See also VAWLUME.INGEST.USVSEG, VAWLUME.SOURCE_MAPPING.PREVIEW.

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
end

loaded = resolveProfile(options);
profileDocument = loaded.document;
assertUsvsegOutputProfile(profileDocument, loaded);

spec = usvsegExportArtifactSpec(profileDocument, options.ArtifactKey);
readResult = usvsegReadExportTable(artifactPath, spec);
location = usvsegPortableLocation(artifactPath, options.RelativePath, ...
    [options.ArtifactRoot, options.RepoRoot]);
sourceKey = resolveSourceKey(options.SourceKey, spec, location);

ir = vawlume.source_mapping.mapTableToIR(readResult.table, loaded, ...
    SourceKey=sourceKey, ArtifactKey=spec.artifact_key, ...
    RuntimePath=location.runtime_path, RelativePath=location.relative_path, ...
    Filename=location.filename, RepoRoot=options.RepoRoot);

issues = emptyAdapterIssues();
versionAssessment = extractorVersionCompatibility( ...
    profileDocument, options.ExtractorVersion);
issues = appendIssue(issues, versionIssue(versionAssessment));
issues = appendIssues(issues, numericCompletenessIssues( ...
    readResult.table, profileDocument, artifactPath));

result = struct();
result.ir = ir;
result.table = readResult.table;
result.artifact = artifactProvenance(artifactPath, spec, readResult, location);
result.profile = profileProvenanceSummary(loaded, ir);
result.profile_document = profileDocument;
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
        error("vawlume:ingest:UsvsegProfileUnsupported", ...
            "Profile must be a loaded profile bundle from vawlume.source_mapping.loadProfile.");
    end
    return
end

profilePath = options.ProfilePath;
if strlength(profilePath) == 0
    if strlength(options.RepoRoot) == 0
        error("vawlume:ingest:UsvsegProfileUnsupported", ...
            ['Supply ProfilePath, Profile, or RepoRoot so the tracked USVSEG ' ...
            'output mapping profile can be located.']);
    end
    profilePath = fullfile(options.RepoRoot, "config", "01_mapping_profiles", ...
        "extractors", "usvseg", "usvseg_output_mapping_profile.json");
end
loaded = vawlume.source_mapping.loadProfile(profilePath, ...
    ExpectedKind="extractor_output", RepoRoot=options.RepoRoot);
end

function assertUsvsegOutputProfile(document, loaded)
kind = profileText(document.profile, "kind");
extractorName = profileText(document.extractor, "name");
if lower(kind) ~= "extractor_output" || lower(extractorName) ~= "usvseg"
    identity = "unknown profile";
    try
        identity = string(loaded.document.profile.id);
    catch
    end
    error("vawlume:ingest:UsvsegProfileUnsupported", ...
        "Expected a USVSEG extractor-output profile, found '%s' (%s).", ...
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
sourceKey = "usvseg:" + spec.artifact_key + ":" + identity;
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

function issues = numericCompletenessIssues(tbl, document, artifactPath)
issues = emptyAdapterIssues();
columns = declaredNumericColumns(document);
for column = columns(:)'
    if ~ismember(column, string(tbl.Properties.VariableNames))
        continue
    end
    tokens = string(tbl.(char(column)));
    values = str2double(tokens);
    badRows = find(strlength(strtrim(tokens)) == 0 | ~isfinite(values));
    for row = badRows(:)'
        issue = adapterIssue("warning", "USVSEG_NUMERIC_TOKEN_NONFINITE", ...
            artifactPath, "Row " + row + ", column '" + column + ...
            "' is not a finite numeric token; source token was preserved: '" + ...
            tokens(row) + "'.");
        issues = appendIssue(issues, issue);
    end
end
end

function columns = declaredNumericColumns(document)
columns = strings(0, 1);
mappings = normalizeSequence(document.field_mappings);
for index = 1:numel(mappings)
    mapping = mappings{index};
    type = profileText(mapping, "data_type");
    if ismember(type, ["integer", "float", "float_or_missing"])
        columns(end + 1, 1) = profileText(mapping, "source_field"); %#ok<AGROW>
    end
end
columns = unique(columns(strlength(columns) > 0), "stable");
end

function items = normalizeSequence(raw)
if iscell(raw)
    items = raw(:);
elseif isstruct(raw)
    items = num2cell(raw(:));
else
    items = {};
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
        candidate = string(container.(char(field)));
        if isscalar(candidate) && ~ismissing(candidate)
            value = candidate;
        end
    catch
    end
end
end
