function tests = test_schema_metadata_validation
% Guards the join between authored semantics and the committed schema.
%
% The loader proves a document is well formed. It cannot prove the document is
% ABOUT this schema: a description of a column that was renamed two versions
% ago is perfectly well formed and completely wrong, and it would travel into
% an export package looking exactly like a correct one. That is what this layer
% catches, and what these tests hold it to.
%
% Each negative test starts from a document that is known to pass validation,
% breaks exactly one identity, and requires the specific condition for that
% break. The reversed-relationship case has its own condition on purpose: it is
% the likeliest authoring mistake and the one a generic "unknown relationship"
% message helps least with.
%
% This layer compares two committed files. It opens no database and runs no
% tbls, so these tests need neither.
tests = functiontests({ ...
    @testTheCommittedMetadataPassesIdentityValidation, ...
    @testAnInventedObjectIsReported, ...
    @testAKindMismatchIsReported, ...
    @testAnInventedColumnIsReported, ...
    @testColumnsOfAnInventedObjectAreNotAlsoReported, ...
    @testAnUnresolvableSameAsTargetIsReported, ...
    @testASameAsPointingAtAViewIsReported, ...
    @testAnInventedRelationshipIsReported, ...
    @testAReversedRelationshipIsReportedAsReversedNotUnknown, ...
    @testASchemaVersionMismatchIsReported, ...
    @testOneRunReportsEveryFinding, ...
    @testTheCommandFormRaisesTheConditionItFound, ...
    @testAMissingStructuralArtifactIsRefused, ...
    @testValidationReachesNoDatabaseAndNoToolchain});
end

% ---------------------------------------------------------------------------
% Positive
% ---------------------------------------------------------------------------

function testTheCommittedMetadataPassesIdentityValidation(testCase)
cleanup = addSourcePath(); %#ok<NASGU>

report = vawlume.schema.validateMetadata(RepoRoot=repoRootForTest(), Print=false);

verifyTrue(testCase, report.passed, ...
    "The committed semantic metadata no longer matches the committed schema: " + ...
    newline + strjoin(report.findings.detail, newline));
verifyEqual(testCase, report.mode, "identity");
verifyEqual(testCase, report.structural_objects, 107);
end

% ---------------------------------------------------------------------------
% Object and column identity
% ---------------------------------------------------------------------------

function testAnInventedObjectIsReported(testCase)
cleanup = addSourcePath(); %#ok<NASGU>

document = validDocument();
document.objects.detections_v2 = document.objects.projects;
report = validateFixture(testCase, document);

verifyFinding(testCase, report, "vawlume:schema:MetadataUnknownObject", "detections_v2");
end

function testAKindMismatchIsReported(testCase)
cleanup = addSourcePath(); %#ok<NASGU>

document = validDocument();
document.objects.projects.kind = "view";
report = validateFixture(testCase, document);

verifyFinding(testCase, report, "vawlume:schema:MetadataObjectKindMismatch", "projects");
end

function testAnInventedColumnIsReported(testCase)
cleanup = addSourcePath(); %#ok<NASGU>

document = validDocument();
document.objects.projects.columns.project_owner = struct( ...
    "description", "A column this schema has never had.");
report = validateFixture(testCase, document);

verifyFinding(testCase, report, "vawlume:schema:MetadataUnknownColumn", "project_owner");
end

function testColumnsOfAnInventedObjectAreNotAlsoReported(testCase)
% An object that does not exist has no columns that could. Reporting six
% unknown columns underneath one unknown object buries the finding that
% actually tells the author what to fix.
cleanup = addSourcePath(); %#ok<NASGU>

document = validDocument();
document.objects.projects_archive = document.objects.projects;
report = validateFixture(testCase, document);

related = report.findings(report.findings.object_name == "projects_archive", :);
verifyEqual(testCase, height(related), 1);
verifyEqual(testCase, related.code(1), "vawlume:schema:MetadataUnknownObject");
end

% ---------------------------------------------------------------------------
% same_as targets
% ---------------------------------------------------------------------------

function testAnUnresolvableSameAsTargetIsReported(testCase)
cleanup = addSourcePath(); %#ok<NASGU>

document = validDocument();
document.objects.v_sequence_members.columns.sequence_id.same_as = "sequence_members.sequence_ordinal";
report = validateFixture(testCase, document);

verifyFinding(testCase, report, "vawlume:schema:MetadataUnknownSameAsTarget", "v_sequence_members");
end

function testASameAsPointingAtAViewIsReported(testCase)
% A pointer into another view could resolve to another pointer, or to a cycle.
% Requiring a base table keeps resolution one hop and guarantees it terminates.
cleanup = addSourcePath(); %#ok<NASGU>

document = validDocument();
document.objects.v_sequence_members.columns.sequence_id.same_as = "v_detection_core.detection_id";
report = validateFixture(testCase, document);

verifyFinding(testCase, report, "vawlume:schema:MetadataUnknownSameAsTarget", "v_sequence_members");
end

% ---------------------------------------------------------------------------
% Relationships
% ---------------------------------------------------------------------------

function testAnInventedRelationshipIsReported(testCase)
cleanup = addSourcePath(); %#ok<NASGU>

document = validDocument();
document.relationships{1}.target_table = "schema_info";
document.relationships{1}.target_columns = {"schema_version"};
report = validateFixture(testCase, document);

verifyFinding(testCase, report, "vawlume:schema:MetadataRelationshipUnknown", "config_profiles");
end

function testAReversedRelationshipIsReportedAsReversedNotUnknown(testCase)
% Both endpoints exist and both columns exist, so every identity check passes
% individually. Only the direction is wrong, and a generic "unknown" would send
% the author hunting for a missing column that is not missing.
cleanup = addSourcePath(); %#ok<NASGU>

document = validDocument();
relationship = document.relationships{1};
document.relationships{1}.source_table = relationship.target_table;
document.relationships{1}.source_columns = relationship.target_columns;
document.relationships{1}.target_table = relationship.source_table;
document.relationships{1}.target_columns = relationship.source_columns;

report = validateFixture(testCase, document);

verifyFinding(testCase, report, "vawlume:schema:MetadataRelationshipReversed", "projects");
verifyEmpty(testCase, find(report.findings.code == "vawlume:schema:MetadataRelationshipUnknown"), ...
    "A reversed relationship was also reported as unknown, which is the message it exists to replace.");
% The remedy has to say which way round is right.
verifySubstring(testCase, char(report.findings.detail(1)), "config_profiles(project_id)->projects(project_id)");
end

% ---------------------------------------------------------------------------
% Version agreement
% ---------------------------------------------------------------------------

function testASchemaVersionMismatchIsReported(testCase)
% Descriptions authored against one schema version can be confidently wrong
% about another. This is what makes the semantic document go stale loudly when
% schema.sql is bumped, instead of quietly misdescribing the new model.
cleanup = addSourcePath(); %#ok<NASGU>

document = validDocument();
document.schema_version = "0.1-not-a-real-version";
report = validateFixture(testCase, document);

verifyFinding(testCase, report, "vawlume:schema:SchemaVersionMismatch", "");
verifySubstring(testCase, char(report.findings.detail(1)), ...
    char(vawlume.schema.repositoryVersion(RepoRoot=repoRootForTest())));
end

% ---------------------------------------------------------------------------
% Reporting behaviour
% ---------------------------------------------------------------------------

function testOneRunReportsEveryFinding(testCase)
% Somebody describing 1,155 columns needs one run to name all of it. A
% validator that stopped at the first fault would make that a fifty-run loop.
cleanup = addSourcePath(); %#ok<NASGU>

document = validDocument();
document.objects.projects.kind = "view";
document.objects.invented_table = document.objects.schema_info;
document.objects.schema_info.columns.invented_column = struct( ...
    "description", "A column that this table does not have at all.");
document.relationships{1}.target_columns = {"project_name"};

report = validateFixture(testCase, document);

verifyEqual(testCase, sort(unique(report.findings.code)), sort([ ...
    "vawlume:schema:MetadataObjectKindMismatch"
    "vawlume:schema:MetadataRelationshipUnknown"
    "vawlume:schema:MetadataUnknownColumn"
    "vawlume:schema:MetadataUnknownObject"]));
end

function testTheCommandFormRaisesTheConditionItFound(testCase)
% With one fault the caller gets that fault's identifier, so a test can catch
% exactly what it injected; with several it gets the aggregate and the list.
cleanup = addSourcePath(); %#ok<NASGU>

single = validDocument();
single.objects.projects.kind = "view";
singlePath = writeDocument(testCase, encode(single));
verifyError(testCase, @() vawlume.schema.validateMetadata( ...
    Path=singlePath, RepoRoot=repoRootForTest(), Print=false), ...
    "vawlume:schema:MetadataObjectKindMismatch");

several = validDocument();
several.objects.projects.kind = "view";
several.objects.invented_table = several.objects.schema_info;
severalPath = writeDocument(testCase, encode(several));
verifyError(testCase, @() vawlume.schema.validateMetadata( ...
    Path=severalPath, RepoRoot=repoRootForTest(), Print=false), ...
    "vawlume:schema:MetadataInvalid");
end

% ---------------------------------------------------------------------------
% Dependencies
% ---------------------------------------------------------------------------

function testAMissingStructuralArtifactIsRefused(testCase)
% Absent structure is a check that cannot run, not a document that failed.
cleanup = addSourcePath(); %#ok<NASGU>

absent = fullfile(workspaceForTest(testCase), "no_schema.json");
verifyError(testCase, @() vawlume.schema.validateMetadata( ...
    RepoRoot=repoRootForTest(), StructuralPath=absent, Print=false), ...
    "vawlume:schema:StructuralArtifactMissing");
end

function testValidationReachesNoDatabaseAndNoToolchain(testCase)
% Boundary 8: ordinary runtime use needs no schema-documentation toolchain.
% A dynamic test cannot prove absence here, so this reads the sources. It is
% deliberately a scan for the names that would betray a dependency, paired with
% the fact that every other test in this file runs without any of them present.
cleanup = addSourcePath(); %#ok<NASGU>

namespace = fullfile(repoRootForTest(), "src", "+vawlume", "+schema");
files = [dir(fullfile(namespace, "*.m")); dir(fullfile(namespace, "private", "*.m"))];
verifyGreaterThan(testCase, numel(files), 0, "Found no sources to scan.");

forbidden = ["sqlite(", "system(", "webread", "websave", "urlread", ...
    "schema_documentation", "tbls"];

% Prove the scan can still fail before trusting it to pass. Stripping strings
% is what makes this check correct, and it is also what could quietly make it
% vacuous, so a real call and a mere mention are both put through the stripper
% and required to come out different.
realCall = stripToExecutableText("conn = sqlite(char(dbPath), ""readonly"");");
mereMention = stripToExecutableText("error(""id"", ""Run sqlite(...) yourself."");");
verifyTrue(testCase, contains(realCall, "sqlite("), ...
    "The stripper removed a genuine call, so this scan proves nothing.");
verifyFalse(testCase, contains(mereMention, "sqlite("), ...
    "The stripper left a mention inside a string, so this scan would misfire.");

for k = 1:numel(files)
    source = string(fileread(fullfile(files(k).folder, files(k).name)));
    code = stripToExecutableText(source);
    for token = forbidden
        verifyFalse(testCase, contains(code, token), ...
            files(k).name + " reaches " + token + ", which the semantic " + ...
            "loader and validator must never need.");
    end
end
end

function code = stripToExecutableText(source)
% A raw-text scan would be wrong in both directions here. It would pass
% vacuously on a file whose comments discuss the dependencies it must not have
% -- these files do discuss them at length -- and it would fail spuriously on
% schemaLoadStructural, whose error message TELLS the user to run
% schema_documentation when the structural artifact is missing. Naming the
% remedy is the opposite of depending on it.
%
% So comments and string literals both come out, and what is scanned is code.
lines = splitlines(source);
lines(startsWith(strtrim(lines), "%")) = [];
code = strjoin(lines, newline);

% MATLAB doubles an embedded quote inside a double-quoted string, so the span
% is "(?:[^"]|"")*" rather than "[^"]*".
code = regexprep(code, '"(?:[^"]|"")*"', '""');
end

% ---------------------------------------------------------------------------
% Fixture
% ---------------------------------------------------------------------------

function document = validDocument()
document = struct();
document.metadata_version = "0.1.0";
document.schema_version = vawlume.schema.repositoryVersion(RepoRoot=repoRootForTest());
document.coverage = struct("complete_domains", []);

document.objects = struct();
document.objects.schema_info = struct( ...
    "kind", "table", ...
    "domain", "identity_config_provenance", ...
    "description", "One row per schema version applied to this database.", ...
    "columns", struct( ...
        "schema_version", struct("description", "Version label of the applied schema.")));

document.objects.projects = struct( ...
    "kind", "table", ...
    "domain", "identity_config_provenance", ...
    "description", "A research project: the outermost scope owning recordings and entities.", ...
    "columns", struct( ...
        "project_id", struct("description", "VAWLUME surrogate key for the project."), ...
        "project_key", struct("description", "Caller-supplied stable identifier for the project.")));

document.objects.v_sequence_members = struct( ...
    "kind", "view", ...
    "domain", "views", ...
    "description", "Sequence membership joined to its owning sequence for one-query reads.", ...
    "columns", struct( ...
        "sequence_id", struct("same_as", "sequence_members.sequence_id")));

document.relationships = {struct( ...
    "source_table", "config_profiles", ...
    "source_columns", {{"project_id"}}, ...
    "target_table", "projects", ...
    "target_columns", {{"project_id"}}, ...
    "description", "Each configuration profile naming a project belongs to that project.")};
end

function report = validateFixture(testCase, document)
path = writeDocument(testCase, encode(document));
report = vawlume.schema.validateMetadata( ...
    Path=path, RepoRoot=repoRootForTest(), Print=false);
end

function verifyFinding(testCase, report, code, subject)
% `subject` is whatever the finding should point at -- an object for an
% object-level condition, a column for a column-level one -- so the test says
% what it means without needing to know which field the validator files it under.
verifyFalse(testCase, report.passed, "Expected " + code + ", but validation passed.");
matching = report.findings(report.findings.code == code, :);
verifyNotEmpty(testCase, matching, ...
    "Expected " + code + ". Got: " + strjoin(report.findings.code', ", "));
if subject ~= ""
    named = matching.object_name == subject | matching.column_name == subject;
    verifyTrue(testCase, any(named), ...
        "Expected " + code + " to name """ + subject + """, but it named: " + ...
        strjoin(matching.object_name' + "." + matching.column_name', ", "));
end
end

function text = encode(document)
text = string(jsonencode(document, PrettyPrint=true));
end

% ---------------------------------------------------------------------------
% Test plumbing
% ---------------------------------------------------------------------------

function path = writeDocument(testCase, text)
workspace = workspaceForTest(testCase);
path = fullfile(workspace, "metadata_" + string(java.util.UUID.randomUUID) + ".json");
fid = fopen(path, "w", "n", "UTF-8");
fwrite(fid, unicode2native(text, "UTF-8"));
fclose(fid);
end

function workspace = workspaceForTest(testCase)
workspace = fullfile(tempdir, "vawlume_metadata_identity_" + string(java.util.UUID.randomUUID));
mkdir(workspace);
testCase.addTeardown(@() removeTree(workspace));
end

function removeTree(path)
if isfolder(path)
    rmdir(path, "s");
end
end

function cleanup = addSourcePath()
sourcePath = fullfile(repoRootForTest(), "src");
if contains(path, sourcePath)
    cleanup = onCleanup(@() []);
    return
end
addpath(sourcePath);
cleanup = onCleanup(@() rmpath(sourcePath));
end

function repoRoot = repoRootForTest()
repoRoot = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
end
