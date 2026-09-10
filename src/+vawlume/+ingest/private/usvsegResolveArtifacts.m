function artifacts = usvsegResolveArtifacts(conn, projectId, export, context, roots)
%USVSEGRESOLVEARTIFACTS Classify the CSV and optional weak settings evidence.
candidates={exportCandidate(export)};
if context.settings.mode=="artifact", candidates{end+1}=settingsCandidate(context.settings,roots); end
artifacts=extractorClassifyArtifacts(conn,projectId,candidates);
end

function candidate=exportCandidate(export)
p=export.artifact; assertPortable(p.relative_path,p.runtime_path,"event CSV");
candidate=struct(role="event_measurement_export",artifact_type="extractor_event_export", ...
    native_artifact_type=p.native_artifact_type,file_format=p.file_format,is_native=false, ...
    path_or_uri=p.relative_path,runtime_path=p.runtime_path,checksum_sha256=p.checksum_sha256, ...
    checksum_status="computed",description="USVSEG per-syllable summary CSV imported by VAWLUME",metadata_json="");
end

function candidate=settingsCandidate(settings,roots)
path=settings.artifact_path;
if ~isfile(path), error("vawlume:ingest:UsvsegSettingsNotFound","Declared settings artifact does not exist: %s",path); end
[~,name,extension]=fileparts(path);
if lower(string(extension))~=".mat"||lower(string(name))~="usvseg_prm"
    error("vawlume:ingest:UsvsegSettingsUnsupported","Settings evidence must be a usvseg_prm.mat file.");
end
try info=whos('-file',char(path),'prm'); catch exception
    error("vawlume:ingest:UsvsegSettingsInvalid","Could not inspect %s: %s",path,exception.message);
end
if isempty(info)||~strcmp(info(1).class,'struct')||prod(info(1).size)~=1
    error("vawlume:ingest:UsvsegSettingsInvalid","usvseg_prm.mat must contain one scalar struct named prm.");
end
location=extractorPortableLocation(path,settings.relative_path,roots,"Usvseg");
assertPortable(location.relative_path,location.runtime_path,"settings artifact");
metadata=struct(status="captured",evidence_strength=settings.evidence_strength, ...
    evidence_scope="application_state_at_file_save_not_verified_run_configuration", ...
    attribution_source="caller",native_variable="prm",native_variable_class="struct", ...
    policy="preserved_as_weak_evidence_without_default substitution");
candidate=struct(role="extractor_settings",artifact_type="extractor_settings", ...
    native_artifact_type=settings.native_type,file_format="mat",is_native=true, ...
    path_or_uri=location.relative_path,runtime_path=location.runtime_path, ...
    checksum_sha256=sha256OfFile(path),checksum_status="computed", ...
    description="USVSEG application-scoped saved parameters; weak caller-attributed evidence", ...
    metadata_json=string(jsonencode(metadata)));
end
function assertPortable(relative,runtime,subject)
if strlength(relative)==0, error("vawlume:ingest:UsvsegArtifactNotPortable", ...
    "No portable path could be derived for the USVSEG %s (%s).",subject,runtime); end
end
