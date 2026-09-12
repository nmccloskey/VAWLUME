function tests = test_repository_self_description
% Guards the repository's description of itself.
%
% The software state is authoritative; the documentation describes that state
% rather than maintaining a second, manually synchronized version of it. This
% suite is what makes that a property of the repository rather than a habit.
%
% It is deliberately non-executing: it discovers tests without running them,
% opens no database, and writes nothing, so it is cheap enough to run on every
% itinerary rather than only at a phase gate.
%
% Claim semantics: docs/development/30_repository_self_description.md.
tests = functiontests({ ...
    @testPublishedClaimsMatchTheRepository, ...
    @testInventoryDescribesADiscoverableRepository});
end

function testPublishedClaimsMatchTheRepository(testCase)
repoRoot = repoRootForTest();
cleanupPath = addToolsPath(repoRoot); %#ok<NASGU>

report = check_repository_self_description(RepoRoot=repoRoot, Print=false);

% Report every stale claim, not just the first, so one run names all the work.
for k = 1:numel(report.checks)
    check = report.checks(k);
    verifyTrue(testCase, check.passed, ...
        "Stale self-description (" + check.name + "): " + ...
        strjoin(check.failures, "; "));
end

verifyTrue(testCase, report.passed, ...
    "Failed checks: " + strjoin(report.failures, ", "));
end

function testInventoryDescribesADiscoverableRepository(testCase)
repoRoot = repoRootForTest();
cleanupPath = addToolsPath(repoRoot); %#ok<NASGU>

inventory = repository_inventory(RepoRoot=repoRoot, Print=false);

% Discovery that silently finds nothing would let every claim check pass
% vacuously, so assert the inventory is non-empty before trusting it.
verifyGreaterThan(testCase, inventory.tests.count, 0);
verifyGreaterThan(testCase, inventory.tests.file_count, 0);
verifyGreaterThanOrEqual(testCase, inventory.tests.count, inventory.tests.file_count);
verifyGreaterThan(testCase, inventory.examples.count, 0);
verifyGreaterThan(testCase, inventory.config.file_count, 0);
verifyGreaterThan(testCase, inventory.packages.count, 0);
verifyGreaterThan(testCase, inventory.documents.count, 0);

% This file must be among the tests it counts; a discovery path that misses
% itself would also miss the next suite that regresses.
verifyTrue(testCase, ismember("test_repository_self_description.m", inventory.tests.files));

verifyTrue(testCase, inventory.schema.coherent, ...
    "schema.sql header, schema_info, and user_version disagree.");
verifyEqual(testCase, inventory.schema.header_version, inventory.schema.schema_info_version);
verifyFalse(testCase, ismissing(inventory.schema.header_version));
verifyFalse(testCase, isnan(inventory.schema.user_version));

verifyTrue(testCase, all(endsWith(inventory.examples.files, ".m")));
verifyTrue(testCase, all(startsWith(inventory.config.files, "config/")));
verifyTrue(testCase, all(endsWith(inventory.documents.files, ".md")));
end

function cleanupPath = addToolsPath(repoRoot)
toolsFolder = fullfile(repoRoot, "tools");
addpath(toolsFolder);
cleanupPath = onCleanup(@() rmpath(toolsFolder));
end

function repoRoot = repoRootForTest()
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
