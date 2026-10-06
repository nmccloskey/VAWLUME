function plan = attributionBackendBuildPlan(conn, runRef, sourcePath, options)
%ATTRIBUTIONBACKENDBUILDPLAN Read, map and resolve a localization-backend export.
%
% Reads the database and the source file; writes neither. Every declared key the
% IR carried is resolved here or refused by name, so an Apply never meets a
% reference it has not already checked.

repoRoot = attributionIntakeRepoRoot(options.RepoRoot);
profilePath = options.ProfilePath;
if strlength(profilePath) == 0
    profilePath = fullfile(repoRoot, "config", "01_mapping_profiles", ...
        "attribution", "generic_backend_attribution_profile.json");
end

resolvedSource = attributionIntakeSourcePath(sourcePath, repoRoot);
loaded = vawlume.source_mapping.loadProfile(profilePath, RepoRoot=repoRoot);
assertProfileUsable(loaded, profilePath);

run = attributionImportResolveRun(conn, runRef);
assertRunImportable(conn, run);
participants = snapshotParticipants(run);

tbl = readSourceTable(resolvedSource);
ir = vawlume.source_mapping.mapTableToIR(tbl, loaded, ...
    SourceKey="source:" + filenameOf(resolvedSource), ...
    RuntimePath=resolvedSource, RepoRoot=repoRoot);

windows = ir.attribution_windows;
if height(windows) == 0
    error("vawlume:attribution:ImportEmpty", ...
        "No row of %s could be mapped into a backend window. " + ...
        "Inspect the plan's issues rather than re-running.", filenameOf(resolvedSource));
end

claims = ir.attribution_claims;
[entityIds, unresolved] = attributionIntakeResolveEntities(conn, run.project_id, ...
    participants, claims);
if ~isempty(unresolved)
    error("vawlume:attribution:CallerLabelUnresolved", ...
        "These caller labels resolve to no participating entity of run %s: %s. " + ...
        "Declare them in the profile's caller_label_resolution map, or add the " + ...
        "entities to the run. VAWLUME does not create an entity to accommodate " + ...
        "a backend's label.", run.run_key, strjoin(unresolved, ", "));
end
claims.entity_id = entityIds;

estimates = ir.attribution_localization_estimates;
[estimates, frames] = resolveFrames(conn, run, estimates);
channels = resolveChannels(conn, run, ir.attribution_channel_evidence);
tracks = resolveTracks(conn, run, ir.attribution_track_references);
nativeAttributes = nativeAttributeRows(ir.attribution_native_attributes, ...
    ir.attribution_channel_evidence, ir.attribution_track_references);

plan = struct();
plan.run = run;
plan.participating_entity_ids = participants;
plan.repo_root = repoRoot;
plan.source = struct( ...
    runtime_path=resolvedSource, ...
    relative_path=attributionIntakePortableUri(resolvedSource, repoRoot), ...
    filename=filenameOf(resolvedSource), ...
    checksum_sha256=attributionImportSha256(resolvedSource), ...
    source_row_count=height(tbl));
plan.profile = struct( ...
    profile_path=string(loaded.source_path), ...
    profile_key=string(loaded.profile.id), ...
    profile_name=string(loaded.profile.name), ...
    profile_kind=string(loaded.profile.kind), ...
    profile_schema_version=string(loaded.profile.profile_schema_version), ...
    version_label=string(loaded.profile.profile_version), ...
    checksum_sha256=string(loaded.checksum_sha256), ...
    content_uri=attributionIntakePortableUri(string(loaded.source_path), repoRoot));
plan.exporting_system = struct(name=string(ir.summary.exporting_system), ...
    version=string(ir.summary.exporting_system_version));
plan.windows = windows;
plan.claims = claims;
plan.estimates = estimates;
plan.native_attributes = nativeAttributes;
plan.declared_inputs = ir.attribution_declared_inputs;
plan.resolutions = struct(frames=frames, channels=channels, tracks=tracks);
plan.issues = ir.issues;
plan.unmapped_rows = ir.summary.unmapped_row_count;
plan.has_conflicts = false;
end

% ---------------------------------------------------------------- checks ---

function assertProfileUsable(loaded, profilePath)
if string(loaded.profile.kind) ~= "attribution_backend_mapping"
    error("vawlume:attribution:ProfileKindInvalid", ...
        "%s declares kind %s; a backend import requires attribution_backend_mapping.", ...
        profilePath, string(loaded.profile.kind));
end
if height(loaded.issues) > 0 && any(loaded.issues.severity == "error")
    error("vawlume:attribution:ProfileInvalid", ...
        "Mapping profile %s has validation errors and cannot be used.", profilePath);
end
end

function assertRunImportable(conn, run)
if run.attribution_path ~= "backend"
    error("vawlume:attribution:RunPathMismatch", ...
        "Run %s declares attribution_path %s; only a backend run accepts a backend import.", ...
        run.run_key, run.attribution_path);
end
if run.status ~= "planned" || run.analysis_status ~= "started"
    error("vawlume:attribution:RunNotWritable", ...
        "A backend import may only be applied while attribution status is planned " + ...
        "and analysis status is started.");
end
% Evidence is append-only and windows have no cross-import natural key, so a
% second apply would duplicate rather than reconcile. Refused by name, as the
% imported path does.
existing = fetch(conn, "SELECT COUNT(*) AS n FROM imported_attribution_windows " + ...
    "WHERE attribution_run_id=" + string(run.attribution_run_id));
if double(existing.n(1)) > 0
    error("vawlume:attribution:ImportAlreadyApplied", ...
        "Run %s already carries %d windows. Evidence is append-only, so a second " + ...
        "import would duplicate rather than reconcile. Create a new run.", ...
        run.run_key, double(existing.n(1)));
end
end

function ids = snapshotParticipants(run)
% The run's own participant snapshot, not the recording's current links: a
% candidate universe that moved when links changed would make an old import
% unreadable.
try
    provenance = jsondecode(char(run.notes));
catch
    provenance = struct();
end
if ~isstruct(provenance) || ~isfield(provenance, "schema") || ...
        string(provenance.schema) ~= "vawlume.attribution.run_provenance.v1" || ...
        ~isfield(provenance, "participating_entity_ids")
    error("vawlume:attribution:RunProvenanceInvalid", ...
        "Run %s carries no v1 provenance snapshot naming its participants. " + ...
        "Create the run with vawlume.attribution.createRun.", run.run_key);
end
ids = double(provenance.participating_entity_ids(:))';
end

% ------------------------------------------------------------ resolutions ---

function [estimates, frames] = resolveFrames(conn, run, estimates)
frames = table(strings(0, 1), zeros(0, 1), zeros(0, 1), ...
    VariableNames=["coordinate_system_key", "coordinate_system_id", "dimensionality"]);
estimates.coordinate_system_id = NaN(height(estimates), 1);
keys = unique(estimates.coordinate_system_key);
unknown = strings(0, 1);
foreign = strings(0, 1);
for index = 1:numel(keys)
    key = keys(index);
    rows = fetch(conn, "SELECT coordinate_system_id, project_id, dimensionality " + ...
        "FROM coordinate_systems WHERE coordinate_system_key=" + sqlText(key));
    own = [];
    if ~isempty(rows) && height(rows) > 0
        own = find(double(rows.project_id) == run.project_id, 1);
    end
    if isempty(rows) || height(rows) == 0
        unknown(end+1, 1) = key; %#ok<AGROW>
    elseif isempty(own)
        foreign(end+1, 1) = key; %#ok<AGROW>
    else
        frames(end+1, :) = {key, double(rows.coordinate_system_id(own)), ...
            double(rows.dimensionality(own))}; %#ok<AGROW>
    end
end
if ~isempty(unknown)
    error("vawlume:attribution:LocalizationFrameUnknown", ...
        "These coordinate-system keys name no declared frame: %s. Declare the " + ...
        "frame with vawlume.geometry.registerCoordinateSystem first; VAWLUME never " + ...
        "creates a frame to fit the data.", strjoin(unknown, ", "));
end
if ~isempty(foreign)
    error("vawlume:attribution:LocalizationFrameScopeMismatch", ...
        "These coordinate-system keys name frames declared only for other projects: " + ...
        "%s. A frame from another project is not this experiment's frame, whatever " + ...
        "its units.", strjoin(foreign, ", "));
end
flat = strings(0, 1);
for index = 1:height(estimates)
    match = frames.coordinate_system_key == estimates.coordinate_system_key(index);
    estimates.coordinate_system_id(index) = frames.coordinate_system_id(match);
    if ~isnan(estimates.position_z(index)) && frames.dimensionality(match) ~= 3
        flat(end+1, 1) = estimates.estimate_key(index); %#ok<AGROW>
    end
end
if ~isempty(flat)
    error("vawlume:attribution:LocalizationDimensionMismatch", ...
        "These estimates report a height under a 2-dimensional frame: %s. " + ...
        "Declare a 3-dimensional frame, or do not map a z.", strjoin(flat, ", "));
end
end

function channels = resolveChannels(conn, run, channelEvidence)
channels = table(zeros(0, 1), zeros(0, 1), ...
    VariableNames=["channel_index", "recording_channel_id"]);
indices = unique(channelEvidence.channel_index);
missing = [];
for index = 1:numel(indices)
    rows = fetch(conn, "SELECT recording_channel_id FROM recording_channels " + ...
        "WHERE recording_id=" + string(run.recording_id) + ...
        " AND channel_index=" + string(indices(index)));
    if isempty(rows) || height(rows) == 0
        missing(end+1) = indices(index); %#ok<AGROW>
    else
        channels(end+1, :) = {indices(index), double(rows.recording_channel_id(1))}; %#ok<AGROW>
    end
end
if ~isempty(missing)
    error("vawlume:attribution:ChannelIndexUndeclared", ...
        "The backend reports evidence for channel(s) %s, which the recording does " + ...
        "not declare. Register them with vawlume.geometry.registerRecordingChannel; " + ...
        "a channel index is the backend's assertion and is not inferred.", ...
        strjoin(string(missing), ", "));
end
end

function tracks = resolveTracks(conn, run, references)
% A video-derived association is evidence somebody recorded, not something an
% importer may assert: the stream and at least one identity association for the
% track must already exist. Which association applies at the window's time is
% NOT decided here -- the window is on the backend's clock and the association on
% the tracking stream's, and relating them is correspondence and alignment work.
tracks = table(strings(0, 1), zeros(0, 1), strings(0, 1), zeros(0, 1), ...
    VariableNames=["tracking_stream_key", "external_stream_id", "native_track_id", ...
    "association_count"]);
streamKeys = unique(references.tracking_stream_key);
unknownStreams = strings(0, 1);
streamIds = containers.Map("KeyType", "char", "ValueType", "double");
for index = 1:numel(streamKeys)
    rows = fetch(conn, "SELECT es.external_stream_id FROM external_streams es " + ...
        "JOIN tracking_streams ts ON ts.external_stream_id = es.external_stream_id " + ...
        "WHERE es.stream_name=" + sqlText(streamKeys(index)) + ...
        " AND es.project_id=" + string(run.project_id) + ...
        " AND (es.recording_id=" + string(run.recording_id) + " OR es.recording_id IS NULL)");
    if isempty(rows) || height(rows) == 0
        unknownStreams(end+1, 1) = streamKeys(index); %#ok<AGROW>
    else
        streamIds(char(streamKeys(index))) = double(rows.external_stream_id(1));
    end
end
if ~isempty(unknownStreams)
    error("vawlume:attribution:TrackingStreamUnknown", ...
        "These tracking-stream keys name no tracking stream of this recording: %s.", ...
        strjoin(unknownStreams, ", "));
end
pairs = unique(references(:, ["tracking_stream_key", "native_track_id"]), "rows");
missing = strings(0, 1);
for index = 1:height(pairs)
    streamId = streamIds(char(pairs.tracking_stream_key(index)));
    rows = fetch(conn, "SELECT COUNT(*) AS n FROM tracking_identity_associations " + ...
        "WHERE external_stream_id=" + string(streamId) + ...
        " AND native_track_id=" + sqlText(pairs.native_track_id(index)));
    count = double(rows.n(1));
    if count == 0
        missing(end+1, 1) = pairs.tracking_stream_key(index) + "/" + ...
            pairs.native_track_id(index); %#ok<AGROW>
    else
        tracks(end+1, :) = {pairs.tracking_stream_key(index), streamId, ...
            pairs.native_track_id(index), count}; %#ok<AGROW>
    end
end
if ~isempty(missing)
    error("vawlume:attribution:IdentityAssociationNotFound", ...
        "No identity association exists for these stream/track pairs: %s. " + ...
        "Record the association with vawlume.tracking.registerIdentityAssociation; " + ...
        "an importer does not create one.", strjoin(missing, ", "));
end
end

% -------------------------------------------- native-attribute folding ---

function rows = nativeAttributeRows(declared, channelEvidence, trackReferences)
% One table of every producer-native value intake will preserve: the profile's
% declared native attributes, plus -- under F5.3-1 option (a) -- per-channel
% evidence on its window and track references on their claims. The reserved
% name prefixes keep the folded rows distinguishable from declared ones.
reserved = startsWith(declared.attribute_name, ["channel:", "track_reference:"]);
if any(reserved)
    error("vawlume:attribution:NativeAttributeNameReserved", ...
        "Native attribute name(s) %s use a prefix VAWLUME reserves for channel " + ...
        "evidence and track references. Rename them in the profile.", ...
        strjoin(unique(declared.attribute_name(reserved)), ", "));
end
rows = declared(:, ["owner_kind", "owner_key", "source_locator", "attribute_name", ...
    "native_field_name", "value_type", "value_text", "value_real", "value_integer", ...
    "value_boolean", "native_raw_token", "unit", "mapping_rule_key"]);
rows.origin = repmat("declared", height(rows), 1);
for index = 1:height(channelEvidence)
    row = channelEvidence(index, :);
    name = "channel:" + string(row.channel_index) + ":" + row.evidence_kind;
    rows(end+1, :) = {"window", row.window_key, row.source_locator, name, ...
        row.native_field_name, "real", "", row.value_real, NaN, NaN, ...
        row.native_raw_token, row.value_units, row.mapping_rule, "channel_evidence"}; %#ok<AGROW>
    rows(end+1, :) = {"window", row.window_key, row.source_locator, ...
        name + ":semantics", row.native_field_name, "text", row.value_semantics, ...
        NaN, NaN, NaN, "", "", row.mapping_rule, "channel_evidence"}; %#ok<AGROW>
end
for index = 1:height(trackReferences)
    row = trackReferences(index, :);
    rows(end+1, :) = {"claim", row.claim_key, row.source_locator, ...
        "track_reference:" + row.tracking_stream_key, "", "text", ...
        row.native_track_id, NaN, NaN, NaN, row.native_track_id, "", ...
        row.mapping_rule, "track_reference"}; %#ok<AGROW>
end
end

% ---------------------------------------------------------------- helpers ---

function tbl = readSourceTable(path)
% Every column is read as TEXT, so the mapper performs the one and only parse
% of every number. Letting readtable type numeric columns would put a second
% text-to-double conversion between the source and the stored value.
if ~isfile(path)
    error("vawlume:attribution:SourceNotFound", ...
        "Backend export does not exist: %s", path);
end
try
    opts = detectImportOptions(path, TextType="string", VariableNamingRule="preserve");
    opts = setvartype(opts, opts.VariableNames, "string");
    tbl = readtable(path, opts);
catch exception
    error("vawlume:attribution:SourceUnreadable", ...
        "Could not read backend export %s: %s", path, exception.message);
end
end

function value = filenameOf(path)
[~, name, ext] = fileparts(string(path));
value = name + ext;
end

function value = sqlText(text)
value = "'" + replace(string(text), "'", "''") + "'";
end
