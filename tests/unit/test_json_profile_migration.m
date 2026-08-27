function tests = test_json_profile_migration
tests = functiontests({ ...
    @testEveryJsonCounterpartParsesDeterministically, ...
    @testExecutablePairsAreSemanticallyEquivalent, ...
    @testMultiProfileSelectionAndContentVersions, ...
    @testScalarTypesAndFragileMapsRemainExplicit, ...
    @testRegexDialectIsUnchanged});
end

function testEveryJsonCounterpartParsesDeterministically(testCase)
repoRoot = repoRootForTest();
pairs = migrationPairs(repoRoot);

jsonFiles = dir(fullfile(repoRoot, "config", "**", "*.json"));
verifyEqual(testCase, numel(jsonFiles), numel(pairs));

for index = 1:numel(pairs)
    verifyTrue(testCase, isfile(pairs(index).yaml_path));
    verifyTrue(testCase, isfile(pairs(index).json_path));

    first = jsondecode(fileread(pairs(index).json_path));
    second = jsondecode(fileread(pairs(index).json_path));
    verifyEqual(testCase, second, first);
end
end

function testExecutablePairsAreSemanticallyEquivalent(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));
pairs = migrationPairs(repoRoot);

for index = find([pairs.executable])
    [yaml, report] = vawlume.source_mapping.loadProfile( ...
        pairs(index).yaml_path, ...
        ExpectedKind=pairs(index).expected_kind, ...
        RepoRoot=repoRoot);
    jsonDocument = jsondecode(fileread(pairs(index).json_path));

    verifyTrue(testCase, report.is_valid);
    verifyEqual(testCase, stripContentVersions(jsonDocument), yaml.document);
end

clear cleanupPath
end

function testMultiProfileSelectionAndContentVersions(testCase)
repoRoot = repoRootForTest();
pairs = migrationPairs(repoRoot);
project = jsondecode(fileread(pairs(1).json_path));

verifyEqual(testCase, numel(project.profiles), 3);
profiles = [project.profiles.profile];
verifyEqual(testCase, string({profiles.id})', [
    "example.project.mouse_courtship.folder_driven"
    "example.project.rat_self_admin.filename_driven"
    "example.project.social_dyad.multi_subject"
    ]);
verifyEqual(testCase, string({profiles.profile_version})', ...
    repmat("0.1.0", 3, 1));

deepSqueak = jsondecode(fileread(pairs(2).json_path));
mupet = jsondecode(fileread(pairs(3).json_path));
verifyEqual(testCase, string(deepSqueak.profile.profile_version), "0.1.0");
verifyEqual(testCase, string(mupet.profile.profile_version), "0.1.0");
verifyEqual(testCase, string(deepSqueak.extractor.version_scope.preferred), "3.2.x");
verifyEqual(testCase, string(mupet.extractor.version_scope.preferred), "2.1");
end

function testScalarTypesAndFragileMapsRemainExplicit(testCase)
repoRoot = repoRootForTest();
pairs = migrationPairs(repoRoot);
deepSqueak = jsondecode(fileread(pairs(2).json_path));
mupet = jsondecode(fileread(pairs(3).json_path));
project = jsondecode(fileread(pairs(1).json_path));

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

function testRegexDialectIsUnchanged(testCase)
repoRoot = repoRootForTest();
pairs = migrationPairs(repoRoot);

projectText = string(fileread(pairs(1).json_path));
deepSqueakText = string(fileread(pairs(2).json_path));
mupetText = string(fileread(pairs(3).json_path));

verifyEqual(testCase, count(projectText, "(?P<"), 15);
verifyEqual(testCase, count(deepSqueakText, "(?P<"), 0);
verifyEqual(testCase, count(mupetText, "(?P<"), 4);
end

function document = stripContentVersions(document)
if isfield(document, "profiles")
    for index = 1:numel(document.profiles)
        document.profiles(index).profile = rmfield( ...
            document.profiles(index).profile, "profile_version");
    end
else
    document.profile = rmfield(document.profile, "profile_version");
end
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

function pairs = migrationPairs(repoRoot)
pairs = [
    pair(repoRoot, ...
        "config/01_mapping_profiles/project_inputs/project_input_source_mapping_examples", ...
        true, "project_input")
    pair(repoRoot, ...
        "config/01_mapping_profiles/extractors/deepsqueak/deepsqueak_output_mapping_profile", ...
        true, "extractor_output")
    pair(repoRoot, ...
        "config/01_mapping_profiles/extractors/mupet/mupet_output_mapping_profile", ...
        true, "extractor_output")
    pair(repoRoot, ...
        "config/02_device_profiles/recording_device_profile_examples", ...
        false, "")
    pair(repoRoot, ...
        "config/03_setup_profiles/experimental_setup_profile_examples", ...
        false, "")
    pair(repoRoot, ...
        "config/04_examples/profile_linkage_example", ...
        false, "")
    ];
end

function value = pair(repoRoot, relativeStem, executable, expectedKind)
relativeStem = replace(string(relativeStem), "/", string(filesep));
value = struct( ...
    yaml_path=fullfile(repoRoot, relativeStem + ".yaml"), ...
    json_path=fullfile(repoRoot, relativeStem + ".json"), ...
    executable=logical(executable), ...
    expected_kind=string(expectedKind));
end

function repoRoot = repoRootForTest()
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
