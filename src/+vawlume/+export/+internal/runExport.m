function result = runExport(request)
%RUNEXPORT Build, validate, and atomically publish one export package.
%
%   RESULT = vawlume.export.internal.runExport(REQUEST)
%
%   The body of vawlume.export.database, which validates the caller's options
%   and passes them here as REQUEST, a struct with fields:
%
%     db_path, output, format, schema_only, tables, include_views, overwrite,
%     allow_schema_version_mismatch, source_identifier, vawlume_version,
%     repo_root
%
%   and three TEST SEAMS the public function never sets:
%
%     exported_at_utc     a fixed timestamp, so a package is byte-deterministic
%     before_publish_fcn  called as fcn(stagingPath) after the staged package has
%                         been validated and immediately before publication
%     after_object_fcn    passed to the export core; called after each data file
%
%   Sequence. Every refusal a caller can cause comes before anything is created:
%
%     1. the destination is checked (contract §F.2 guards, §F.1 policy);
%     2. the semantic metadata is loaded and must pass complete validation, so
%        a package can never ship a blank description;
%     3. a staging directory <Output>.<uuid>.partial is created beside the
%        destination, on the same volume, so publication is a rename;
%     4. normal mode: the core writes csv/ from the source, read-only;
%     5. one package record is built, and meta/ and README.md are rendered from
%        it, with the manifest last;
%     6. the staged package is read back and validated;
%     7. it is published by rename. Under Overwrite, the previous package is
%        first moved aside, restored if the rename fails, and removed only
%        after the new package is in place.
%
%   On ANY failure the staging directory is removed and the destination is
%   untouched: absent, still empty, or still the previous valid package
%   (contract §F.4). The source database is never written.

arguments
    request (1,1) struct
end

mode = "normal";
if request.schema_only
    mode = "schema_only";
end
repoRoot = request.repo_root;

sourcePath = "";
if mode == "normal"
    sourcePath = string(request.db_path);
    if ~isfile(sourcePath)
        error("vawlume:export:SourceNotFound", ...
            "No database file at ""%s"". The exporter opens an existing database " + ...
            "read-only and never creates one.", sourcePath);
    end
end

destination = vawlume.export.internal.checkDestination( ...
    request.output, request.overwrite, sourcePath);

structure = vawlume.schema.loadStructure(RepoRoot=repoRoot);
metadata = vawlume.schema.loadMetadata(RepoRoot=repoRoot);
report = vawlume.schema.validateMetadata(Metadata=metadata, RepoRoot=repoRoot, ...
    Mode="complete", Print=false);
if ~report.passed
    error("vawlume:export:MetadataInvalid", ...
        "The repository's schema metadata failed validation, so a package would " + ...
        "not describe itself fully. Run vawlume.schema.validateMetadata(Mode=""complete""):\n  %s", ...
        strjoin(report.findings.detail, newline + "  "));
end

exportedAt = request.exported_at_utc;
if exportedAt == ""
    exportedAt = string(datetime("now", TimeZone="UTC"), "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'");
end
facts = struct(format=request.format, exported_at_utc=exportedAt, ...
    source_identifier=request.source_identifier, vawlume_version=request.vawlume_version, ...
    repository_schema_version=vawlume.schema.repositoryVersion(RepoRoot=repoRoot));

token = string(java.util.UUID.randomUUID);
staging = destination.path + "." + token + ".partial";
mkdir(staging);
try
    exportRecord = [];
    if mode == "normal"
        exportRecord = vawlume.export.internal.writeObjects(sourcePath, staging, ...
            Tables=request.tables, IncludeViews=request.include_views, ...
            AllowSchemaVersionMismatch=request.allow_schema_version_mismatch, ...
            RepoRoot=repoRoot, AfterObjectFcn=request.after_object_fcn);
    end
    record = vawlume.export.internal.buildPackageRecord(mode, structure, metadata, ...
        exportRecord, facts);
    vawlume.export.internal.writePackageFiles(record, staging);
    vawlume.export.internal.validatePackage(staging, record);
    if ~isempty(request.before_publish_fcn)
        request.before_publish_fcn(staging);
    end
    publish(staging, destination, request.overwrite, sourcePath, token);
catch exception
    if isfolder(staging)
        rmdir(staging, "s");
    end
    rethrow(exception);
end

result = struct();
result.output_dir = destination.path;
result.mode = mode;
result.format = record.format;
result.exported_at_utc = record.exported_at_utc;
if mode == "normal"
    result.source = struct(filename=record.source.filename, bytes=record.source.bytes, ...
        schema_version=record.source.schema_version, user_version=record.source.user_version);
else
    result.source = [];
end
result.supported_object_count = record.supported_object_count;
result.selected_object_count = record.selected_object_count;
result.exported_object_count = record.exported_object_count;
result.exported_row_total = record.exported_row_total;
result.objects = record.objects;
result.files = record.files;
result.warnings = record.warnings.code + ": " + record.warnings.message;
result.metadata_version = record.metadata_version;
result.package_format_version = record.package_format_version;
end

% ---------------------------------------------------------------------------

function publish(staging, destination, overwrite, sourcePath, token)
% The destination is checked again immediately before it is touched, so a
% directory that appeared or changed since the first check is not replaced.
current = vawlume.export.internal.checkDestination(destination.path, overwrite, sourcePath);
if current.state ~= destination.state
    error("vawlume:export:DestinationChanged", ...
        "Output ""%s"" changed while the package was being built (it was %s, " + ...
        "now %s). Nothing was published.", destination.path, destination.state, current.state);
end

switch current.state
    case "absent"
        moveOrFail(staging, current.path);
    case "empty"
        % Non-recursive: rmdir without "s" cannot remove a directory that has
        % gained content.
        rmdir(current.path);
        moveOrFail(staging, current.path);
    case "package"
        previous = current.path + "." + token + ".previous";
        moveOrFail(current.path, previous);
        try
            moveOrFail(staging, current.path);
        catch exception
            moveOrFail(previous, current.path);
            rethrow(exception);
        end
        [removed, message] = rmdir(previous, "s");
        if ~removed
            warning("vawlume:export:PreviousPackageNotRemoved", ...
                "The new package is published, but the previous one could not be " + ...
                "removed from ""%s"": %s", previous, message);
        end
end
end

function moveOrFail(from, to)
[moved, message] = movefile(from, to);
if ~moved
    error("vawlume:export:PublicationFailed", ...
        "Could not move ""%s"" to ""%s"": %s", from, to, message);
end
end
