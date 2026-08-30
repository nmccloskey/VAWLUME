function bundle = alignmentManifest(manifestPath, options)
%ALIGNMENTMANIFEST Read one session alignment manifest into a validated bundle.
%
% BUNDLE = vawlume.ingest.alignmentManifest(MANIFESTPATH) reads a compact session
% manifest, resolves the event and anchor tables it points at, maps each one
% through its declared mapping profile, and returns the validated,
% provenance-bearing intermediate representations plus manifest and source
% checksums. It performs no database access whatsoever.
%
% The manifest names data rather than embedding it. Each declared stream supplies
% a source table and a mapping profile; the anchors block does the same. Mapping
% semantics stay entirely in VAWLUME.SOURCE_MAPPING — nothing here reinterprets a
% column, chooses a timestamp, or normalizes a label.
%
% Name-value options:
%   RepoRoot    root for repository-relative mapping-profile paths
%   SourceRoot  root for manifest-relative data paths (defaults to the manifest's
%               own directory, so a session folder is self-contained)
%   Tables      struct mapping a stream_key, or "anchors", to an already-loaded
%               MATLAB table, for callers that hold their data in memory
%
% BUNDLE.valid_for_ingest is true only when the manifest resolved and every
% mapped IR is itself ready. Structured mapping issues survive in each IR rather
% than being flattened into one message.

arguments
    manifestPath (1,1) string
    options.RepoRoot (1,1) string = ""
    options.SourceRoot (1,1) string = ""
    options.Tables (1,1) struct = struct()
end

repoRoot = alignmentRepoRoot(options.RepoRoot);
manifestFull = alignmentResolvePath(manifestPath, repoRoot);
sourceRoot = options.SourceRoot;
if strlength(sourceRoot) == 0
    sourceRoot = string(fileparts(manifestFull));
end

manifest = alignmentLoadManifest(manifestFull, repoRoot, sourceRoot);

streams = repmat(emptyStreamBundle(), 0, 1);
for index = 1:numel(manifest.streams)
    declaration = manifest.streams(index);
    streams(end + 1, 1) = mapDeclaredStream( ...
        declaration, repoRoot, options.Tables); %#ok<AGROW>
end

anchors = struct(declared=false, ir=[], source=emptySourceEvidence(), ...
    profile=emptyProfileEvidence());
if manifest.anchors.declared
    anchors = mapDeclaredAnchors(manifest.anchors, repoRoot, ...
        options.Tables, streams);
end

bundle = struct( ...
    manifest=manifest, ...
    repo_root=repoRoot, ...
    source_root=string(sourceRoot), ...
    streams=streams, ...
    anchors=anchors, ...
    issues=collectIssues(streams, anchors), ...
    valid_for_ingest=false);
bundle.valid_for_ingest = readiness(streams, anchors);
end

% ---------------------------------------------------------------- mapping ---

function value = mapDeclaredStream(declaration, repoRoot, tables)
tbl = suppliedTable(tables, declaration.stream_key);
source = emptySourceEvidence();
if isempty(tbl)
    requireFile(declaration.source_path, "stream '" + declaration.stream_key + "'");
    tbl = alignmentReadSourceTable(declaration.source_path);
    source = sourceEvidence(declaration.source_path, repoRoot, declaration.file_role);
else
    source.mode = "supplied_table";
    source.file_role = declaration.file_role;
end
source.row_count = height(tbl);

loaded = vawlume.source_mapping.loadProfile( ...
    declaration.mapping_profile_path, RepoRoot=repoRoot);
ir = vawlume.source_mapping.mapTableToIR(tbl, loaded, ...
    ProfileId=declaration.mapping_profile_id, RepoRoot=repoRoot, ...
    RuntimePath=source.runtime_path, RelativePath=source.relative_path, ...
    Filename=source.filename);

value = emptyStreamBundle();
value.declaration = declaration;
value.ir = ir;
value.source = source;
value.profile = profileEvidence(loaded, declaration.mapping_profile_path, repoRoot);
value.stream_key = declaredStreamKey(ir, declaration);
value.timebase_key = declaredTimebaseKey(ir, declaration);
end

function value = mapDeclaredAnchors(declaration, repoRoot, tables, streams)
tbl = suppliedTable(tables, "anchors");
source = emptySourceEvidence();
if isempty(tbl)
    requireFile(declaration.source_path, "anchor table");
    tbl = alignmentReadSourceTable(declaration.source_path);
    source = sourceEvidence(declaration.source_path, repoRoot, declaration.file_role);
else
    source.mode = "supplied_table";
    source.file_role = declaration.file_role;
end
source.row_count = height(tbl);

loaded = vawlume.source_mapping.loadProfile( ...
    declaration.mapping_profile_path, RepoRoot=repoRoot);

% Anchor observations may cite an external event by its native ID. Passing the
% already-mapped event IRs lets source mapping resolve that reference itself
% instead of this layer guessing which stream an ID belongs to.
context = eventContext(streams);
ir = vawlume.source_mapping.mapTableToIR(tbl, loaded, ...
    ProfileId=declaration.mapping_profile_id, RepoRoot=repoRoot, ...
    RuntimePath=source.runtime_path, RelativePath=source.relative_path, ...
    Filename=source.filename, EventContext=context);

value = struct(declared=true, declaration=declaration, ir=ir, source=source, ...
    profile=profileEvidence(loaded, declaration.mapping_profile_path, repoRoot));
end

function value = eventContext(streams)
%EVENTCONTEXT Every mapped event, so a reference resolves against the right stream.
%
% Each stream's events keep their own source key, so concatenating them lets the
% anchor mapper match a reference to the stream that actually declared it. Passing
% only one stream would make a reference into any other stream look unresolvable.
value = struct();
events = [];
for index = 1:numel(streams)
    ir = streams(index).ir;
    if height(ir.events) == 0
        continue
    end
    if isempty(events)
        events = ir.events;
    else
        events = [events; ir.events]; %#ok<AGROW>
    end
end
if isempty(events)
    return
end
value = struct(events=events);
end

% --------------------------------------------------------------- evidence ---

function value = sourceEvidence(path, repoRoot, fileRole)
value = emptySourceEvidence();
value.mode = "file";
value.runtime_path = alignmentCanonicalPath(path);
value.relative_path = alignmentPortableUri(path, repoRoot);
value.filename = alignmentFilenameOf(path);
value.file_role = fileRole;
value.checksum_sha256 = sha256OfFile(path);
value.size_bytes = fileSizeOf(path);
end

function value = profileEvidence(loaded, path, repoRoot)
value = emptyProfileEvidence();
value.profile_key = firstText(loaded, "profile_ids");
value.profile_name = profileDisplayName(loaded);
value.profile_kind = firstText(loaded, "profile_kinds");
value.profile_schema_version = firstText(loaded, "profile_schema_versions");
value.version_label = firstText(loaded, "profile_version_labels");
value.checksum_sha256 = firstText(loaded, "checksum_sha256");
value.runtime_path = alignmentCanonicalPath(path);
value.content_uri = alignmentPortableUri(path, repoRoot);
end

function value = profileDisplayName(loaded)
%PROFILEDISPLAYNAME Authored profile name, falling back to its stable id.
%
% config_profiles.profile_name is NOT NULL, and the loader reports ids but not
% names, so the name is read from the profile document itself.
value = "";
if isstruct(loaded) && isfield(loaded, "profile") && isstruct(loaded.profile) && ...
        isfield(loaded.profile, "name")
    value = string(loaded.profile.name);
    if ismissing(value)
        value = "";
    end
end
if strlength(strtrim(value)) == 0
    value = firstText(loaded, "profile_ids");
end
value = strtrim(value);
end

function value = firstText(loaded, field)
value = "";
if ~isstruct(loaded) || ~isfield(loaded, field)
    return
end
candidate = string(loaded.(field));
if isempty(candidate)
    return
end
value = candidate(1);
if ismissing(value)
    value = "";
end
end

% ---------------------------------------------------------------- shaping ---

function value = declaredStreamKey(ir, declaration)
value = declaration.stream_key;
if height(ir.streams) == 1
    mapped = string(ir.streams.stream_key(1));
    if strlength(mapped) > 0 && mapped ~= value
        error("vawlume:ingest:AlignmentStreamKeyMismatch", ...
            ['Manifest declares stream_key ''%s'' but its mapping profile ' ...
            'produces ''%s''. The manifest and the profile must agree about ' ...
            'which logical stream is being registered.'], value, mapped);
    end
end
end

function value = declaredTimebaseKey(ir, declaration)
value = declaration.timebase_key;
if height(ir.streams) == 1
    mapped = string(ir.streams.timebase_key(1));
    if strlength(mapped) > 0 && mapped ~= value
        error("vawlume:ingest:AlignmentTimebaseKeyMismatch", ...
            ['Manifest places stream ''%s'' on timebase ''%s'' but its mapping ' ...
            'profile states ''%s''. A clock disagreement must be corrected ' ...
            'rather than silently resolved.'], declaration.stream_key, value, mapped);
    end
end
end

function value = collectIssues(streams, anchors)
value = table(strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    strings(0, 1), false(0, 1), ...
    VariableNames=["scope", "issue_key", "severity", "code", "message", ...
    "affects_validity"]);
for index = 1:numel(streams)
    value = appendIssues(value, "stream:" + streams(index).stream_key, ...
        streams(index).ir.issues);
end
if anchors.declared
    value = appendIssues(value, "anchors", anchors.ir.issues);
end
end

function value = appendIssues(value, scope, issues)
for index = 1:height(issues)
    value(end + 1, :) = {scope, string(issues.issue_key(index)), ...
        string(issues.severity(index)), string(issues.code(index)), ...
        string(issues.message(index)), logical(issues.affects_validity(index))}; %#ok<AGROW>
end
end

function value = readiness(streams, anchors)
value = true;
for index = 1:numel(streams)
    value = value && streams(index).ir.valid_for_ingest;
end
if anchors.declared
    value = value && anchors.ir.valid_for_ingest;
end
end

function value = emptyStreamBundle()
value = struct(declaration=struct(), ir=[], source=emptySourceEvidence(), ...
    profile=emptyProfileEvidence(), stream_key="", timebase_key="");
end

function value = emptySourceEvidence()
value = struct(mode="none", runtime_path="", relative_path="", filename="", ...
    file_role="", checksum_sha256="", size_bytes=NaN, row_count=0);
end

function value = emptyProfileEvidence()
value = struct(profile_key="", profile_name="", profile_kind="", ...
    profile_schema_version="", version_label="", checksum_sha256="", ...
    runtime_path="", content_uri="");
end

% --------------------------------------------------------------- plumbing ---

function value = suppliedTable(tables, key)
value = [];
name = matlab.lang.makeValidName(key);
if isfield(tables, name) && istable(tables.(name))
    value = tables.(name);
end
end

function requireFile(path, label)
if ~isfile(path)
    error("vawlume:ingest:AlignmentSourceNotFound", ...
        "The manifest declares a source for %s that does not exist: %s", label, path);
end
end

function value = fileSizeOf(path)
info = dir(path);
if isempty(info)
    value = NaN;
    return
end
value = double(info(1).bytes);
end
