function tests = test_eda_configuration_identity
%TEST_EDA_CONFIGURATION_IDENTITY The configuration-id rule, pinned (itinerary 7.8, C9).
%
% Numeric identities must stay bit-identical to the ones every exploration so far
% recorded; text values (an instant basis, a reference type) enter verbatim.
% The pinned values were printed by the function before 7.8 extended it.
tests = functiontests(localfunctions);
end

function setup(testCase)
root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
here = pwd;
cd(fullfile(root, "src", "+vawlume", "+eda", "private"));
testCase.addTeardown(@() cd(here));
end

function testNumericIdentitiesAreBitIdentical(testCase)
pinned = {["min_temporal_iou", "spectral_tolerance"], [0.1, 0.25], "cfg-f9af230384", ...
        "min_temporal_iou=0.10000000000000001;spectral_tolerance=0.25", ...
        "f9af230384fced097903f3c347a871d108c05e9dceaa033df9d07b24b347e7ca"
    "min_temporal_iou", 1/3, "cfg-0041e8eed6", "min_temporal_iou=0.33333333333333331", ...
        "0041e8eed6044dcd2c072624a5d39ad0b98fd8a12cfb1e43f27ae4e179704ecb"
    ["z"; "a"; "m"], [3; -0.0; 1e-300], "cfg-0acc6a2acf", "a=-0;m=1e-300;z=3", ...
        "0acc6a2acf32144c03888d12855c72ebb462b3143dc7e2a1a4cda73a25fceb10"};
for k = 1:size(pinned, 1)
    id = edaConfigurationIdentity(pinned{k, 1}, pinned{k, 2});
    verifyEqual(testCase, [id.configuration_id, id.identity_payload, id.digest_sha256], ...
        [pinned{k, 3}, pinned{k, 4}, pinned{k, 5}]);
    % The cell form of the same numbers is the same identity.
    cellForm = edaConfigurationIdentity(pinned{k, 1}, num2cell(pinned{k, 2}));
    verifyEqual(testCase, cellForm.configuration_id, pinned{k, 3});
end
end

function testTextEntersVerbatimAndVectorsJoin(testCase)
id = edaConfigurationIdentity(["estimator_settings.primary_instant_basis", ...
    "estimator_settings.channel_pair"], {"onset", [2 1]});
verifyEqual(testCase, id.identity_payload, ...
    "estimator_settings.channel_pair=2,1;estimator_settings.primary_instant_basis=onset");
verifyTrue(testCase, startsWith(id.configuration_id, "cfg-"));
verifyNotEqual(testCase, edaConfigurationIdentity("x", {"onset"}).configuration_id, ...
    edaConfigurationIdentity("x", {"offset"}).configuration_id);
verifyError(testCase, @() edaConfigurationIdentity("x", {struct()}), ...
    "vawlume:eda:ConfigurationIdentityInvalid");
end
