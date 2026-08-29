function result = mupetCaptureSettings(configPath, profileDocument, options)
%MUPETCAPTURESETTINGS Capture profile-declared keys from native config.csv.
%
% The native v2.1 format is an unheaded two-column key,value CSV. Values stay
% lexical strings. Every row, including unknown keys, is retained; the profile
% alone declares which keys are required and their canonical labels/units.

arguments
    configPath (1,1) string
    profileDocument (1,1) struct
    options.ExtractorVersion (1,1) string = ""
    options.RelativePath (1,1) string = ""
    options.Roots (1,:) string = strings(1,0)
end

issues = emptyIssues();
entries = emptyEntries();
declared = declaredSettings(profileDocument);

if strlength(configPath) == 0
    issues(end + 1, :) = {"warning", "MUPET_SETTINGS_NOT_SUPPLIED", ...
        "settings_capture", ...
        "No MUPET config.csv was supplied; inspection is permitted but apply must refuse."};
    result = finish("not_supplied", false, struct(), entries, declared.native_name, ...
        issues, options.ExtractorVersion, "", "");
    return
end
if ~isfile(configPath)
    error("vawlume:ingest:MupetSettingsNotFound", ...
        "MUPET settings config does not exist: %s", configPath);
end
[~, ~, extension] = fileparts(configPath);
if lower(string(extension)) ~= ".csv"
    error("vawlume:ingest:MupetSettingsUnsupported", ...
        "MUPET settings source must be config.csv-compatible CSV: %s", configPath);
end

raw = readNativeConfig(configPath);
for row = 1:height(raw)
    nativeName = raw.native_name(row);
    rawValue = raw.raw_value(row);
    declaredIndex = find(declared.native_name == nativeName, 1);
    if isempty(declaredIndex)
        entries(end + 1, :) = {row, nativeName, rawValue, "", "", false, "unrecognized"}; %#ok<AGROW>
        issues(end + 1, :) = {"warning", "MUPET_SETTINGS_KEY_UNRECOGNIZED", ...
            string(configPath) + ":row:" + row, ...
            "Unrecognized MUPET config key was preserved: " + nativeName + "."}; %#ok<AGROW>
    else
        entries(end + 1, :) = {row, nativeName, rawValue, ...
            declared.canonical_setting(declaredIndex), declared.native_unit(declaredIndex), ...
            true, "captured"}; %#ok<AGROW>
    end
end

duplicates = repeatedValues(entries.native_name(strlength(entries.native_name) > 0));
for index = 1:numel(duplicates)
    issues(end + 1, :) = {"error", "MUPET_SETTINGS_KEY_DUPLICATE", ...
        string(configPath), "MUPET config repeats native key: " + duplicates(index) + "."}; %#ok<AGROW>
    entries.status(entries.native_name == duplicates(index)) = "duplicate";
end

presentDeclared = entries.native_name(entries.declared & strlength(entries.raw_value) > 0);
missing = declared.native_name(~ismember(declared.native_name, presentDeclared));
for index = 1:numel(missing)
    issues(end + 1, :) = {"error", "MUPET_SETTINGS_REQUIRED_KEY_MISSING", ...
        string(configPath), "MUPET config is missing required native key/value: " + ...
        missing(index) + ". No default was substituted."}; %#ok<AGROW>
end

location = mupetPortableLocation(configPath, options.RelativePath, options.Roots);
artifact = struct(artifact_key="settings_config", ...
    native_artifact_type="MUPET config.csv", ...
    canonical_artifact_type="settings", file_format="csv", ...
    runtime_path=location.runtime_path, relative_path=location.relative_path, ...
    relative_path_source=location.relative_path_source, filename=location.filename, ...
    checksum_sha256=sha256OfFile(configPath), size_bytes=fileSize(configPath), ...
    row_count=height(raw), column_count=2);

complete = isempty(missing) && isempty(duplicates);
status = "captured";
if ~complete
    status = "incomplete";
end
captureHash = structuredChecksum(entries);
result = finish(status, complete, artifact, entries, missing, issues, ...
    options.ExtractorVersion, artifact.checksum_sha256, captureHash);
end

function raw = readNativeConfig(path)
try
    options = detectImportOptions(path, FileType="text", Delimiter=",", ...
        ReadVariableNames=false, VariableNamingRule="preserve");
    if numel(options.VariableNames) ~= 2
        error("vawlume:ingest:MupetSettingsUnsupported", ...
            "MUPET config.csv must contain exactly two columns (key,value): %s", path);
    end
    options.DataLines = [1, Inf];
    options = setvartype(options, options.VariableNames, "string");
    options = setvaropts(options, options.VariableNames, ...
        TreatAsMissing={}, FillValue="", WhitespaceRule="preserve");
    tbl = readtable(path, options);
catch exception
    if startsWith(string(exception.identifier), "vawlume:")
        rethrow(exception);
    end
    error("vawlume:ingest:MupetSettingsUnreadable", ...
        "Could not read MUPET config.csv %s: %s", path, exception.message);
end
if height(tbl) == 0
    error("vawlume:ingest:MupetSettingsUnreadable", ...
        "MUPET config.csv contains no settings rows: %s", path);
end
raw = table(string(tbl{:,1}), string(tbl{:,2}), ...
    VariableNames=["native_name", "raw_value"]);
end

function declared = declaredSettings(document)
if ~isfield(document, "settings_capture") || ...
        ~isfield(document.settings_capture, "native_settings")
    error("vawlume:ingest:MupetSettingsUnsupported", ...
        "MUPET profile declares no settings_capture.native_settings block.");
end
items = normalizeSequence(document.settings_capture.native_settings);
declared = table(strings(numel(items),1), strings(numel(items),1), ...
    strings(numel(items),1), ...
    VariableNames=["native_name", "canonical_setting", "native_unit"]);
for index = 1:numel(items)
    declared.native_name(index) = profileText(items{index}, "native_name");
    declared.canonical_setting(index) = profileText(items{index}, "canonical_setting");
    declared.native_unit(index) = profileText(items{index}, "native_unit");
end
end

function result = finish(status, complete, artifact, entries, missing, issues, ...
        extractorVersion, sourceHash, captureHash)
result = struct(status=string(status), complete=logical(complete), ...
    extractor_name="MUPET", extractor_version=string(extractorVersion), ...
    source_artifact=artifact, entries=entries, ...
    missing_required_keys=string(missing(:)), issues=issues, ...
    source_checksum_sha256=string(sourceHash), ...
    structured_capture_checksum_sha256=string(captureHash), ...
    lineage=struct(derivation="faithful_config_csv_capture", ...
        source_checksum_sha256=string(sourceHash)));
end

function entries = emptyEntries()
entries = table(zeros(0,1), strings(0,1), strings(0,1), strings(0,1), ...
    strings(0,1), false(0,1), strings(0,1), ...
    VariableNames=["source_row", "native_name", "raw_value", ...
    "canonical_setting", "native_unit", "declared", "status"]);
end

function issues = emptyIssues()
issues = table(strings(0,1), strings(0,1), strings(0,1), strings(0,1), ...
    VariableNames=["severity", "code", "location", "message"]);
end

function repeats = repeatedValues(values)
values = sort(values(:));
if numel(values) < 2
    repeats = strings(0,1);
else
    repeats = unique(values(values(1:end-1) == values(2:end)));
end
end

function hash = structuredChecksum(entries)
ordered = sortrows(entries, ["native_name", "source_row"]);
lines = ordered.native_name + "=" + ordered.raw_value;
payload = unicode2native(char(strjoin(lines, newline)), "UTF-8");
digest = java.security.MessageDigest.getInstance("SHA-256");
digest.update(typecast(uint8(payload(:)'), "int8"));
bytes = typecast(digest.digest(), "uint8");
hash = lower(string(reshape(dec2hex(bytes, 2).', 1, [])));
end

function bytes = fileSize(path)
info = dir(path);
bytes = double(info(1).bytes);
end

function value = profileText(container, field)
value = "";
if isstruct(container) && isfield(container, char(field))
    candidate = string(container.(char(field)));
    if isscalar(candidate) && ~ismissing(candidate)
        value = candidate;
    end
end
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
