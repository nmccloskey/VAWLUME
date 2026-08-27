function tests = test_json_profile_migration
tests = functiontests({ ...
    @testEveryJsonConfigProfileParsesDeterministically, ...
    @testNoYamlConfigArtifactsRemain, ...
    @testExecutableJsonProfilesLoadNatively, ...
    @testMultiProfileSelectionAndContentVersions, ...
    @testScalarTypesAndFragileMapsRemainExplicit, ...
    @testRegexDialectIsMatlabNative});
end

function testEveryJsonConfigProfileParsesDeterministically(testCase)
repoRoot = repoRootForTest();
profiles = canonicalProfiles(repoRoot);

jsonFiles = dir(fullfile(repoRoot, "config", "**", "*.json"));
verifyEqual(testCase, numel(jsonFiles), numel(profiles));

for index = 1:numel(profiles)
    verifyTrue(testCase, isfile(profiles(index).json_path));

    first = jsondecode(fileread(profiles(index).json_path));
    second = jsondecode(fileread(profiles(index).json_path));
    verifyEqual(testCase, second, first);
end
end

function testNoYamlConfigArtifactsRemain(testCase)
repoRoot = repoRootForTest();
yamlFiles = [
    dir(fullfile(repoRoot, "config", "**", "*.yaml"))
    dir(fullfile(repoRoot, "config", "**", "*.yml"))
    ];
verifyEmpty(testCase, yamlFiles);
end

function testExecutableJsonProfilesLoadNatively(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));
profiles = canonicalProfiles(repoRoot);

for index = find([profiles.executable])
    [loaded, report] = vawlume.source_mapping.loadProfile( ...
        profiles(index).json_path, ...
        ExpectedKind=profiles(index).expected_kind, ...
        RepoRoot=repoRoot);
    repeated = vawlume.source_mapping.loadProfile( ...
        profiles(index).json_path, ...
        ExpectedKind=profiles(index).expected_kind, ...
        RepoRoot=repoRoot);
    jsonDocument = jsondecode(fileread(profiles(index).json_path));

    verifyTrue(testCase, report.is_valid);
    verifyEqual(testCase, report.error_count, 0);
    verifyEqual(testCase, loaded.document, jsonDocument);
    verifyEqual(testCase, loaded.relative_path, profiles(index).relative_path);
    verifyEqual(testCase, loaded.checksum_sha256, repeated.checksum_sha256);
    verifyEqual(testCase, strlength(loaded.checksum_sha256), 64);
    verifyTrue(testCase, all(loaded.profile_version_labels == "0.1.0"));
end

clear cleanupPath
end

function testMultiProfileSelectionAndContentVersions(testCase)
repoRoot = repoRootForTest();
profiles = canonicalProfiles(repoRoot);
project = jsondecode(fileread(profiles(1).json_path));

verifyEqual(testCase, numel(project.profiles), 3);
profileEnvelopes = [project.profiles.profile];
verifyEqual(testCase, string({profileEnvelopes.id})', [
    "example.project.mouse_courtship.folder_driven"
    "example.project.rat_self_admin.filename_driven"
    "example.project.social_dyad.multi_subject"
    ]);
verifyEqual(testCase, string({profileEnvelopes.profile_version})', ...
    repmat("0.1.0", 3, 1));

deepSqueak = jsondecode(fileread(profiles(2).json_path));
mupet = jsondecode(fileread(profiles(3).json_path));
verifyEqual(testCase, string(deepSqueak.profile.profile_version), "0.1.0");
verifyEqual(testCase, string(mupet.profile.profile_version), "0.1.0");
verifyEqual(testCase, string(deepSqueak.extractor.version_scope.preferred), "3.2.x");
verifyEqual(testCase, string(mupet.extractor.version_scope.preferred), "2.1");
end

function testScalarTypesAndFragileMapsRemainExplicit(testCase)
repoRoot = repoRootForTest();
profiles = canonicalProfiles(repoRoot);
deepSqueak = jsondecode(fileread(profiles(2).json_path));
mupet = jsondecode(fileread(profiles(3).json_path));
project = jsondecode(fileread(profiles(1).json_path));

accepted = mappingBySourceField(deepSqueak.field_mappings, "Accepted");
verifyClass(testCase, accepted.allowed_raw_values, "double");
verifyEqual(testCase, accepted.allowed_raw_values, [0; 1]);
verifyTrue(testCase, isfield(accepted.value_mapping, "x0"));
verifyTrue(testCase, isfield(accepted.value_mapping, "x1"));
verifyEqual(testCase, string(accepted.value_mapping.x0), "rejected");
verifyEqual(testCase, string(accepted.value_mapping.x1), "accepted");

interval = mappingBySourceField(mupet.field_mappings, ...
    "inter-syllable interval (sec)");
verifyEqual(testCase, string(interval.data_type), "float_or_missing");
verifyTrue(testCase, isfield(interval, "missing_value_policy"));
verifyFalse(testCase, isfield(interval.missing_value_policy, "missing_tokens"));
verifyTrue(testCase, logical(interval.missing_value_policy.preserve_raw_token));

filenameProfile = project.profiles(2);
phenotype = filenameProfile.mappings.captures.phenotype;
verifyEqual(testCase, string(phenotype.normalize.PR), "punishment_resistant");
verifyEqual(testCase, string(phenotype.normalize.PS), "punishment_sensitive");
verifyTrue(testCase, logical(deepSqueak.mapping_policy.preserve_raw_values));
end

function testRegexDialectIsMatlabNative(testCase)
repoRoot = repoRootForTest();
profiles = canonicalProfiles(repoRoot);

projectText = string(fileread(profiles(1).json_path));
deepSqueakText = string(fileread(profiles(2).json_path));
mupetText = string(fileread(profiles(3).json_path));

verifyEqual(testCase, count(projectText, "(?P<"), 0);
verifyEqual(testCase, count(deepSqueakText, "(?P<"), 0);
verifyEqual(testCase, count(mupetText, "(?P<"), 0);
verifyEqual(testCase, count(projectText, "(?<"), 15);
verifyEqual(testCase, count(deepSqueakText, "(?<"), 0);
verifyEqual(testCase, count(mupetText, "(?<"), 4);

project = jsondecode(fileread(profiles(1).json_path));
mupet = jsondecode(fileread(profiles(3).json_path));
patterns = allRegexPatterns(project);
patterns = [patterns; allRegexPatterns(mupet)];
verifyEqual(testCase, numel(patterns), 14);
for index = 1:numel(patterns)
    verifyWarningFree(testCase, @() regexp("", char(patterns(index)), "once"));
end

mousePattern = project.profiles(1).mappings{3}.path_component_regex;
mouseNames = regexp("mouse_001", mousePattern, "names");
verifyEqual(testCase, string(mouseNames.animal_id), "001");
verifyTrue(testCase, contains(mousePattern, "\d"));

ratPattern = project.profiles(2).mappings.filename_regex;
ratNames = regexp("OXY_PR_R03_SA07_001.wav", ratPattern, "names");
verifyEqual(testCase, string(ratNames.phenotype), "PR");
verifyEqual(testCase, string(ratNames.segment), "001");
verifyTrue(testCase, contains(ratPattern, "\."));

artifactPattern = mupet.artifact_discovery.artifacts{3}.include.path_regex{1};
artifactNames = regexp("audio/dataset_a/CSV/recording_001.csv", ...
    artifactPattern, "names");
verifyEqual(testCase, string(artifactNames.native_dataset_path), "dataset_a");
verifyEqual(testCase, string(artifactNames.recording_stem), "recording_001");
end

function mapping = mappingBySourceField(mappings, sourceField)
if iscell(mappings)
    fields = cellfun(@(item) string(item.source_field), mappings);
    mapping = mappings{find(fields == sourceField, 1)};
else
    index = find(string({mappings.source_field}) == sourceField, 1);
    mapping = mappings(index);
end
end

function patterns = allRegexPatterns(document)
patterns = strings(0, 1);
if isfield(document, "profiles")
    profiles = normalizeSequence(document.profiles);
    for profileIndex = 1:numel(profiles)
        patterns = [patterns; allRegexPatterns(profiles{profileIndex})]; %#ok<AGROW>
    end
end
if isfield(document, "mappings")
    mappings = normalizeSequence(document.mappings);
    for mappingIndex = 1:numel(mappings)
        mapping = mappings{mappingIndex};
        if isfield(mapping, "path_component_regex")
            patterns(end + 1, 1) = string(mapping.path_component_regex); %#ok<AGROW>
        end
        if isfield(mapping, "filename_regex")
            patterns(end + 1, 1) = string(mapping.filename_regex); %#ok<AGROW>
        end
    end
end
if isfield(document, "artifact_discovery") && ...
        isfield(document.artifact_discovery, "artifacts")
    artifacts = normalizeSequence(document.artifact_discovery.artifacts);
    for artifactIndex = 1:numel(artifacts)
        artifact = artifacts{artifactIndex};
        if isfield(artifact, "include") && isfield(artifact.include, "path_regex")
            patterns = [patterns; string(artifact.include.path_regex(:))]; %#ok<AGROW>
        end
    end
end
end

function items = normalizeSequence(rawValue)
if iscell(rawValue)
    items = rawValue(:);
elseif isstruct(rawValue)
    items = num2cell(rawValue(:));
else
    items = {};
end
end

function profiles = canonicalProfiles(repoRoot)
profiles = [
    profile(repoRoot, ...
        "config/01_mapping_profiles/project_inputs/project_input_source_mapping_examples", ...
        true, "project_input")
    profile(repoRoot, ...
        "config/01_mapping_profiles/extractors/deepsqueak/deepsqueak_output_mapping_profile", ...
        true, "extractor_output")
    profile(repoRoot, ...
        "config/01_mapping_profiles/extractors/mupet/mupet_output_mapping_profile", ...
        true, "extractor_output")
    profile(repoRoot, ...
        "config/02_device_profiles/recording_device_profile_examples", ...
        false, "")
    profile(repoRoot, ...
        "config/03_setup_profiles/experimental_setup_profile_examples", ...
        false, "")
    profile(repoRoot, ...
        "config/04_examples/profile_linkage_example", ...
        false, "")
    ];
end

function value = profile(repoRoot, relativeStem, executable, expectedKind)
relativeStem = replace(string(relativeStem), "/", string(filesep));
relativePath = replace(relativeStem + ".json", filesep, "/");
value = struct( ...
    json_path=fullfile(repoRoot, relativeStem + ".json"), ...
    relative_path=relativePath, ...
    executable=logical(executable), ...
    expected_kind=string(expectedKind));
end

function repoRoot = repoRootForTest()
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
