function tests = test_export_selection
% Selection is where a caller's strings meet the schema, so every refusal is
% asserted here, before any SQL exists. The resolver is pure: these tests open no
% database, which is itself part of the claim.
%
% The committed structure is the supported set (contract §B.2). The resolver
% selects from it in schema order, whatever order the request used (§D.4), and
% applies §D.3's grammar exactly: "all" or exact, case-sensitive names; tables
% and views alike; duplicates, unknowns, empties, and unsafe names refused.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
addpath(fullfile(repoRoot, "src"));
testCase.addTeardown(@() rmpath(fullfile(repoRoot, "src")));
testCase.TestData.structure = vawlume.schema.loadStructure(RepoRoot=repoRoot);
end

% --- "all" and IncludeViews -------------------------------------------------

function testDefaultSelectsEveryTableAndNoViewInSchemaOrder(testCase)
structure = testCase.TestData.structure;
selection = vawlume.export.internal.resolveSelection(structure, "all", false);

objects = sortrows(structure.objects, "position");
tables = objects(objects.object_kind == "table", :);
verifyEqual(testCase, selection.object_name, tables.object_name);
verifyEqual(testCase, unique(selection.object_kind), "table");
verifyTrue(testCase, issorted(selection.schema_position));
end

function testIncludeViewsAddsEveryViewToAll(testCase)
structure = testCase.TestData.structure;
selection = vawlume.export.internal.resolveSelection(structure, "all", true);

objects = sortrows(structure.objects, "position");
verifyEqual(testCase, selection.object_name, objects.object_name);
verifyEqual(testCase, sum(selection.object_kind == "view"), ...
    sum(structure.objects.object_kind == "view"));
end

% --- explicit names -----------------------------------------------------------

function testExplicitNamesComeBackInSchemaOrder(testCase)
structure = testCase.TestData.structure;
selection = vawlume.export.internal.resolveSelection(structure, ...
    ["detections", "projects", "recordings"], false);
verifyEqual(testCase, selection.object_name, ["projects"; "recordings"; "detections"]);
end

function testAnExplicitViewIsExportedWhateverIncludeViewsSays(testCase)
% IncludeViews governs only what "all" means; it never overrides a request.
structure = testCase.TestData.structure;
selection = vawlume.export.internal.resolveSelection(structure, ...
    ["v_detection_core", "detections"], false);
verifyEqual(testCase, selection.object_name, ["detections"; "v_detection_core"]);
verifyEqual(testCase, selection.object_kind, ["table"; "view"]);
end

function testEachRowCarriesFilenameAndCanonicalColumns(testCase)
structure = testCase.TestData.structure;
selection = vawlume.export.internal.resolveSelection(structure, "all", true);

verifyEqual(testCase, selection.filename, "csv/" + selection.object_name + ".csv");
for k = 1:height(selection)
    expected = structure.columns(structure.columns.object_name == selection.object_name(k), :);
    expected = sortrows(expected, "position");
    verifyEqual(testCase, selection.columns{k}, expected.column_name', ...
        "Column order for " + selection.object_name(k));
    verifyEqual(testCase, selection.column_count(k), height(expected));
end
verifyEqual(testCase, sum(selection.column_count), height(structure.columns));
end

function testAValidAwkwardIdentifierIsSelectedExactly(testCase)
% Mixed case, digits, and underscores are legal and must survive untouched.
% Upper-case letters never appear in VAWLUME's own names, so this uses a
% synthetic structure.
structure = syntheticStructure(["MixedCase_Name9", "plain"]);
selection = vawlume.export.internal.resolveSelection(structure, "MixedCase_Name9", false);
verifyEqual(testCase, selection.object_name, "MixedCase_Name9");
verifyEqual(testCase, selection.filename, "csv/MixedCase_Name9.csv");
end

% --- refusals -----------------------------------------------------------------

function testEmptySelectionsAreRefused(testCase)
structure = testCase.TestData.structure;
verifyError(testCase, @() vawlume.export.internal.resolveSelection(structure, [], false), ...
    "vawlume:export:EmptySelection");
verifyError(testCase, @() vawlume.export.internal.resolveSelection(structure, string.empty, false), ...
    "vawlume:export:EmptySelection");
end

function testNonTextSelectionIsRefused(testCase)
verifyError(testCase, @() vawlume.export.internal.resolveSelection( ...
    testCase.TestData.structure, 42, false), "vawlume:export:InvalidSelection");
end

function testDuplicatesAreRefusedNotDeduplicated(testCase)
exception = captureError(testCase, @() vawlume.export.internal.resolveSelection( ...
    testCase.TestData.structure, ["projects", "detections", "projects"], false), ...
    "vawlume:export:DuplicateObject");
verifySubstring(testCase, exception.message, "projects");
end

function testEveryUnknownNameIsReportedAtOnce(testCase)
exception = captureError(testCase, @() vawlume.export.internal.resolveSelection( ...
    testCase.TestData.structure, ["projects", "nonesuch", "missing_too"], false), ...
    "vawlume:export:UnknownObject");
verifySubstring(testCase, exception.message, """nonesuch""");
verifySubstring(testCase, exception.message, """missing_too""");
verifySubstring(testCase, exception.message, "Available objects:");
end

function testACaseMismatchIsRefusedWithAHint(testCase)
exception = captureError(testCase, @() vawlume.export.internal.resolveSelection( ...
    testCase.TestData.structure, "Projects", false), "vawlume:export:UnknownObject");
verifySubstring(testCase, exception.message, "did you mean ""projects""");
end

function testInjectionShapedAndUnsafeNamesAreRefusedBeforeAnyLookup(testCase)
structure = testCase.TestData.structure;
unsafe = ["projects; DROP TABLE projects", "projects""--", "1starts_with_digit", ...
    "has-hyphen", "has space", "", "CON", "lpt1", "Nul", "../escape"];
for name = unsafe
    verifyError(testCase, @() vawlume.export.internal.resolveSelection(structure, name, false), ...
        "vawlume:export:UnsafeObjectName", "Expected refusal of: " + name);
end
verifyError(testCase, @() vawlume.export.internal.resolveSelection( ...
    structure, string(missing), false), "vawlume:export:UnsafeObjectName");
end

function testTheResolverNeverOpensTheDatabase(testCase)
% A structure with no repository behind it, and an object name no database has:
% if the resolver touched a database this could not succeed.
structure = syntheticStructure(["alpha", "beta"]);
selection = vawlume.export.internal.resolveSelection(structure, "all", false);
verifyEqual(testCase, selection.object_name, ["alpha"; "beta"]);
end

% --- fixture ------------------------------------------------------------------

function exception = captureError(testCase, action, identifier)
exception = [];
try
    action();
catch exception
end
verifyNotEmpty(testCase, exception, "Expected an error: " + identifier);
if ~isempty(exception)
    verifyEqual(testCase, string(exception.identifier), identifier);
else
    exception = MException("test:none", "no error");
end
end

function structure = syntheticStructure(names)
names = names(:);
objects = table(names, repmat("table", numel(names), 1), (1:numel(names))', ...
    VariableNames=["object_name", "object_kind", "position"]);
columns = table(names, repmat("id", numel(names), 1), ones(numel(names), 1), ...
    VariableNames=["object_name", "column_name", "position"]);
structure = struct(objects=objects, columns=columns);
end
