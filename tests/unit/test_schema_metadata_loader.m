function tests = test_schema_metadata_loader
% Guards the grammar of schema/schema_metadata.json.
%
% The semantic document is the only place VAWLUME's schema semantics are
% written down, and an export package presents them as though they were
% complete. So the failure that matters most here is not a malformed file --
% that is loud on its own -- but a file that loads happily while quietly
% dropping something. A misspelled "descripton" silently ignored produces a
% package that advertises itself as self-describing and ships a blank cell.
%
% Every negative test below therefore starts from a document that is KNOWN to
% load, injects exactly one defect, and requires the specific identifier for
% that defect. A suite that only loaded good metadata would have tested
% nothing: it is the rejections that carry the guarantee.
%
% These tests need no database, no tbls, no Node, no npm, and no network. They
% read two committed files and some temporary ones.
tests = functiontests({ ...
    @testTheCommittedDocumentLoads, ...
    @testTheFixtureLoadsAndHasTheDocumentedShape, ...
    @testAStructuralFieldIsRefused, ...
    @testAMisspelledFieldFailsRatherThanBeingDropped, ...
    @testADuplicateObjectIsReportedAsADuplicate, ...
    @testADuplicateColumnIsReportedAsADuplicate, ...
    @testADuplicateRelationshipIsRejected, ...
    @testAMissingRequiredFieldNamesItsJsonPath, ...
    @testPlaceholderProseIsRejected, ...
    @testAColumnNeedsExactlyOneOfDescriptionOrSameAs, ...
    @testSameAsIsRefusedOnABaseTableColumn, ...
    @testAnUnknownDomainIsRejected, ...
    @testAnUnknownObjectKindIsRejected, ...
    @testAMissingFileAndInvalidJsonAreDistinguished, ...
    @testTheDefaultPathDoesNotDependOnTheWorkingDirectory});
end

% ---------------------------------------------------------------------------
% Positive
% ---------------------------------------------------------------------------

function testTheCommittedDocumentLoads(testCase)
cleanup = addSourcePath(); %#ok<NASGU>

metadata = vawlume.schema.loadMetadata(RepoRoot=repoRootForTest());

verifyGreaterThan(testCase, strlength(metadata.metadata_version), 0);
verifyEqual(testCase, metadata.schema_version, ...
    vawlume.schema.repositoryVersion(RepoRoot=repoRootForTest()), ...
    "The committed metadata declares a schema version the repository no longer has.");
verifyGreaterThan(testCase, height(metadata.objects), 0);
end

function testTheFixtureLoadsAndHasTheDocumentedShape(testCase)
cleanup = addSourcePath(); %#ok<NASGU>
path = writeDocument(testCase, validDocumentText());

metadata = vawlume.schema.loadMetadata(Path=path);

verifyEqual(testCase, string(metadata.objects.Properties.VariableNames), ...
    ["object_name", "object_kind", "domain", "description"]);
verifyEqual(testCase, string(metadata.columns.Properties.VariableNames), ...
    ["object_name", "column_name", "description", "same_as", "description_source"]);
verifyEqual(testCase, string(metadata.relationships.Properties.VariableNames), ...
    ["source_table", "source_columns", "target_table", "target_columns", ...
     "description", "relationship_key"]);

% Document order, not alphabetical: `schema_info` is written first.
verifyEqual(testCase, metadata.objects.object_name(1), "schema_info");

% A view column that points at a table column records where it borrowed from,
% so an inherited meaning is visible in the projection rather than passing as
% an authored one.
pointer = metadata.columns.description_source(metadata.columns.column_name == "sequence_id");
verifyEqual(testCase, pointer, "inherited:sequence_members.sequence_id");
verifyTrue(testCase, ismissing(metadata.columns.description( ...
    metadata.columns.column_name == "sequence_id")));
end

% ---------------------------------------------------------------------------
% The structural-authority tripwire
% ---------------------------------------------------------------------------

function testAStructuralFieldIsRefused(testCase)
% The semantic document must never acquire a second opinion about types, keys
% or nullability. Rejecting unknown fields is what enforces that, so every
% structural field name is refused by construction rather than by a list this
% test would have to keep current.
cleanup = addSourcePath(); %#ok<NASGU>

for field = ["type", "nullable", "default", "pk", "notnull", "constraints", "indexes"]
    document = validDocument();
    document.objects.projects.columns.project_id.(field) = "TEXT";
    path = writeDocument(testCase, encode(document));

    verifyError(testCase, @() vawlume.schema.loadMetadata(Path=path), ...
        "vawlume:schema:MetadataUnknownField", ...
        "A structural field named """ + field + """ was accepted into the semantic document.");
end
end

function testAMisspelledFieldFailsRatherThanBeingDropped(testCase)
cleanup = addSourcePath(); %#ok<NASGU>

document = validDocument();
document.objects.projects.columns.project_id = struct("descripton", "A plausible looking description.");
path = writeDocument(testCase, encode(document));

% Not MetadataMissingField: the useful message names the field that is not
% recognized, because that is the typo the author has to find.
verifyError(testCase, @() vawlume.schema.loadMetadata(Path=path), ...
    "vawlume:schema:MetadataUnknownField");
end

% ---------------------------------------------------------------------------
% Duplicates
% ---------------------------------------------------------------------------

function testADuplicateObjectIsReportedAsADuplicate(testCase)
% JSON permits a repeated member and `jsondecode` renames the second rather
% than dropping it, so a duplicate arrives as an unrecognized field. Saying
% "duplicate" is more useful than saying "unknown", and this is the only route
% by which a duplicate can reach the loader at all.
cleanup = addSourcePath(); %#ok<NASGU>
path = writeDocument(testCase, duplicateObjectText());

verifyLoadFails(testCase, path, "vawlume:schema:MetadataDuplicateEntry", "projects");
end

function testADuplicateColumnIsReportedAsADuplicate(testCase)
cleanup = addSourcePath(); %#ok<NASGU>
path = writeDocument(testCase, duplicateColumnText());

verifyLoadFails(testCase, path, "vawlume:schema:MetadataDuplicateEntry", "project_key");
end

function testADuplicateRelationshipIsRejected(testCase)
% Inside a JSON array repetition is legal and decodes to two elements, so this
% one is caught on the decoded keys rather than on field names.
cleanup = addSourcePath(); %#ok<NASGU>

document = validDocument();
document.relationships = [document.relationships, document.relationships];
path = writeDocument(testCase, encode(document));

verifyError(testCase, @() vawlume.schema.loadMetadata(Path=path), ...
    "vawlume:schema:MetadataDuplicateEntry");
end

% ---------------------------------------------------------------------------
% Required fields and prose
% ---------------------------------------------------------------------------

function testAMissingRequiredFieldNamesItsJsonPath(testCase)
cleanup = addSourcePath(); %#ok<NASGU>

document = validDocument();
document.objects.projects = rmfield(document.objects.projects, "domain");
path = writeDocument(testCase, encode(document));

% The author has to be able to find it in a document with a thousand entries.
verifyLoadFails(testCase, path, "vawlume:schema:MetadataMissingField", ...
    ["objects.projects", "domain"]);
end

function testPlaceholderProseIsRejected(testCase)
cleanup = addSourcePath(); %#ok<NASGU>

% Five ways of appearing to have described a column without having done so.
% The last is the one that matters at this scale: "Project key" as the
% description of `project_key` is the filler that would otherwise accumulate
% over 1,155 columns, and it is indistinguishable from real work in a diff.
cases = ["", "   ", "Too short.", "TODO: describe this column later.", "Project key"];
reasons = ["empty", "whitespace only", "under the minimum length", ...
    "a placeholder marker", "restates the name and nothing else"];

for k = 1:numel(cases)
    document = validDocument();
    document.objects.projects.columns.project_key.description = cases(k);
    path = writeDocument(testCase, encode(document));

    verifyError(testCase, @() vawlume.schema.loadMetadata(Path=path), ...
        "vawlume:schema:MetadataPlaceholderDescription", ...
        "Accepted a description that is " + reasons(k) + ": """ + cases(k) + """");
end
end

function testAColumnNeedsExactlyOneOfDescriptionOrSameAs(testCase)
% Both would be two answers to one question, which is the drift the pointer
% exists to prevent. Neither would be an undescribed column that validation
% could not tell from a described one.
cleanup = addSourcePath(); %#ok<NASGU>

both = validDocument();
both.objects.v_sequence_members.columns.sequence_id = struct( ...
    "description", "An independently authored description of the same column.", ...
    "same_as", "sequence_members.sequence_id");
verifyError(testCase, ...
    @() vawlume.schema.loadMetadata(Path=writeDocument(testCase, encode(both))), ...
    "vawlume:schema:MetadataInvalidValue");

neither = validDocument();
neither.objects.projects.columns.project_key = struct();
verifyError(testCase, ...
    @() vawlume.schema.loadMetadata(Path=writeDocument(testCase, encode(neither))), ...
    "vawlume:schema:MetadataMissingField");
end

function testSameAsIsRefusedOnABaseTableColumn(testCase)
% A base table is where meaning is authored. If a table column could point
% somewhere else, the chain would have no end that owns the description.
cleanup = addSourcePath(); %#ok<NASGU>

document = validDocument();
document.objects.projects.columns.project_id = struct("same_as", "schema_info.schema_version");
path = writeDocument(testCase, encode(document));

verifyError(testCase, @() vawlume.schema.loadMetadata(Path=path), ...
    "vawlume:schema:MetadataSameAsNotPermitted");
end

% ---------------------------------------------------------------------------
% Closed vocabularies
% ---------------------------------------------------------------------------

function testAnUnknownDomainIsRejected(testCase)
% The domain set is closed so that a typo fails here rather than creating a
% domain nobody will ever declare complete -- which would leave its objects
% permanently outside every completeness check.
cleanup = addSourcePath(); %#ok<NASGU>

document = validDocument();
document.objects.projects.domain = "identity_config_provenence";
path = writeDocument(testCase, encode(document));

% The message lists the vocabulary, because a near-miss is the likely mistake.
verifyLoadFails(testCase, path, "vawlume:schema:MetadataInvalidValue", ...
    "identity_config_provenance");
end

function testAnUnknownObjectKindIsRejected(testCase)
cleanup = addSourcePath(); %#ok<NASGU>

document = validDocument();
document.objects.projects.kind = "relation";
path = writeDocument(testCase, encode(document));

verifyError(testCase, @() vawlume.schema.loadMetadata(Path=path), ...
    "vawlume:schema:MetadataInvalidValue");
end

% ---------------------------------------------------------------------------
% Reaching the file at all
% ---------------------------------------------------------------------------

function testAMissingFileAndInvalidJsonAreDistinguished(testCase)
% "There is no file" and "the file is not JSON" are different problems with
% different remedies, so they do not share an identifier.
cleanup = addSourcePath(); %#ok<NASGU>

absent = fullfile(workspaceForTest(testCase), "does_not_exist.json");
verifyError(testCase, @() vawlume.schema.loadMetadata(Path=absent), ...
    "vawlume:schema:MetadataNotFound");

malformed = writeDocument(testCase, "{ this is not json ");
verifyError(testCase, @() vawlume.schema.loadMetadata(Path=malformed), ...
    "vawlume:schema:MetadataInvalidJson");
end

function testTheDefaultPathDoesNotDependOnTheWorkingDirectory(testCase)
% A loader whose default depends on `pwd` loads a different file depending on
% where MATLAB happens to be. Two runs from one directory would agree with each
% other all day, so the second run is made from somewhere else.
cleanup = addSourcePath(); %#ok<NASGU>

here = vawlume.schema.loadMetadata(RepoRoot=repoRootForTest());

originalDirectory = pwd;
testCase.addTeardown(@() cd(originalDirectory));
cd(workspaceForTest(testCase));
elsewhere = vawlume.schema.loadMetadata(RepoRoot=repoRootForTest());
cd(originalDirectory);

verifyEqual(testCase, elsewhere.source_path, here.source_path);
verifyEqual(testCase, elsewhere.objects, here.objects);
end

% ---------------------------------------------------------------------------
% Fixture
% ---------------------------------------------------------------------------

function document = validDocument()
% A small document built from real schema identities, so it passes structural
% validation as well as the grammar. Deliberately not the committed production
% document: these tests guard the grammar, and should not start failing because
% Part 3 described another table.
document = struct();
document.metadata_version = "0.1.0";
% Read rather than hard-coded, so a schema version bump does not silently turn
% every test in this file into a version-mismatch test.
document.schema_version = vawlume.schema.repositoryVersion(RepoRoot=repoRootForTest());
document.coverage = struct("complete_domains", []);

document.objects = struct();
document.objects.schema_info = struct( ...
    "kind", "table", ...
    "domain", "identity_config_provenance", ...
    "description", "One row per schema version applied to this database.", ...
    "columns", struct( ...
        "schema_version", struct("description", "Version label of the applied schema."), ...
        "applied_at_utc", struct("description", "UTC timestamp recorded when the schema was applied."), ...
        "description", struct("description", "Free-text note shipped with the schema version seed.")));

document.objects.projects = struct( ...
    "kind", "table", ...
    "domain", "identity_config_provenance", ...
    "description", "A research project: the outermost scope owning recordings and entities.", ...
    "columns", struct( ...
        "project_id", struct("description", "VAWLUME surrogate key for the project."), ...
        "project_key", struct("description", "Caller-supplied stable identifier for the project."), ...
        "project_name", struct("description", "Human-readable name used when reporting to a person."), ...
        "description", struct("description", "Free-text account of what the project covers."), ...
        "created_at_utc", struct("description", "UTC timestamp recorded when the row was created."), ...
        "archived_at_utc", struct("description", "UTC timestamp recorded when the project was archived.")));

document.objects.v_sequence_members = struct( ...
    "kind", "view", ...
    "domain", "views", ...
    "description", "Sequence membership joined to its owning sequence for one-query reads.", ...
    "columns", struct( ...
        "sequence_member_id", struct("same_as", "sequence_members.sequence_member_id"), ...
        "sequence_id", struct("same_as", "sequence_members.sequence_id")));

document.relationships = {struct( ...
    "source_table", "config_profiles", ...
    "source_columns", {{"project_id"}}, ...
    "target_table", "projects", ...
    "target_columns", {{"project_id"}}, ...
    "description", "Each configuration profile naming a project belongs to that project.")};
end

function text = validDocumentText()
text = encode(validDocument());
end

function text = encode(document)
text = string(jsonencode(document, PrettyPrint=true));
end

function text = duplicateObjectText()
% Written as literal text: a repeated JSON member cannot be produced from a
% MATLAB struct, which is exactly why the loader has to cope with one.
entry = """kind"": ""table"", ""domain"": ""identity_config_provenance"", " + ...
    """description"": ""A research project scope owning recordings."", " + ...
    """columns"": {""project_id"": {""description"": ""Surrogate key for the project.""}}";
text = "{" + ...
    """metadata_version"": ""0.1.0""," + ...
    """schema_version"": """ + vawlume.schema.repositoryVersion(RepoRoot=repoRootForTest()) + """," + ...
    """coverage"": {""complete_domains"": []}," + ...
    """objects"": {""projects"": {" + entry + "}, ""projects"": {" + entry + "}}," + ...
    """relationships"": []}";
end

function text = duplicateColumnText()
column = """description"": ""Caller-supplied stable identifier for the project.""";
text = "{" + ...
    """metadata_version"": ""0.1.0""," + ...
    """schema_version"": """ + vawlume.schema.repositoryVersion(RepoRoot=repoRootForTest()) + """," + ...
    """coverage"": {""complete_domains"": []}," + ...
    """objects"": {""projects"": {""kind"": ""table"", " + ...
        """domain"": ""identity_config_provenance"", " + ...
        """description"": ""A research project scope owning recordings."", " + ...
        """columns"": {""project_key"": {" + column + "}, ""project_key"": {" + column + "}}}}," + ...
    """relationships"": []}";
end

% ---------------------------------------------------------------------------
% Test plumbing
% ---------------------------------------------------------------------------

function verifyLoadFails(testCase, path, identifier, substrings)
% Require the specific identifier AND, where given, the text an author needs in
% order to find the defect. An identifier alone would let a message degrade to
% "something is wrong somewhere" without any test noticing.
arguments
    testCase
    path (1,1) string
    identifier (1,1) string
    substrings (1,:) string = strings(1, 0)
end

try
    vawlume.schema.loadMetadata(Path=path);
    verifyFail(testCase, "Expected " + identifier + ", but the document loaded.");
    return
catch exception
    verifyEqual(testCase, string(exception.identifier), identifier, ...
        "Failed for the wrong reason: " + exception.message);
    for k = 1:numel(substrings)
        verifySubstring(testCase, exception.message, char(substrings(k)));
    end
end
end

function path = writeDocument(testCase, text)
workspace = workspaceForTest(testCase);
path = fullfile(workspace, "metadata_" + string(java.util.UUID.randomUUID) + ".json");
fid = fopen(path, "w", "n", "UTF-8");
fwrite(fid, unicode2native(text, "UTF-8"));
fclose(fid);
end

function workspace = workspaceForTest(testCase)
workspace = fullfile(tempdir, "vawlume_metadata_grammar_" + string(java.util.UUID.randomUUID));
mkdir(workspace);
testCase.addTeardown(@() removeTree(workspace));
end

function removeTree(path)
if isfolder(path)
    rmdir(path, "s");
end
end

function cleanup = addSourcePath()
% Add and restore here rather than relying on the caller's path. Neighbouring
% suites remove src/ in their own teardown, so a test that assumes it is
% present passes alone and errors inside the full suite.
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
