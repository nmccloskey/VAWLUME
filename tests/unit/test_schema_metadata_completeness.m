function tests = test_schema_metadata_completeness
% Guards the gate that turns "described" from a claim into a measurement.
%
% Identity validation proves that everything the semantic document says is
% true. It says nothing about what the document has left out, and omission is
% the failure this workstream is most exposed to: an export package renders one
% row per schema object whether or not anybody described it, so a missing
% description becomes a blank cell in a file that presents itself as complete
% schema documentation.
%
% Completeness is declared per domain rather than globally, because the schema
% is described one domain at a time. A domain listed in `coverage` is a claim
% the document makes about itself, and this gate is what tests that claim. Only
% when every domain is claimed does the document assert it covers the whole
% schema, and only then does the global check run.
%
% The mechanism is Part 2's. The claim that every domain is complete was Part
% 3's to make, and part3g made it. testTheCommittedDocumentIsGloballyComplete
% keeps that claim a property of the repository rather than of one session.
tests = functiontests({ ...
    @testTheCommittedDocumentSurvivesItsOwnClaims, ...
    @testTheCommittedDocumentIsGloballyComplete, ...
    @testAPartialDocumentPassesIdentityButClaimsNothing, ...
    @testADeclaredDomainMustDescribeEveryColumnOfItsObjects, ...
    @testADeclaredDomainMustMatchItsOwnObjectCount, ...
    @testADeclaredDomainThatIsCompleteIsAccepted, ...
    @testTheGlobalGateStaysQuietUntilEveryDomainIsClaimed, ...
    @testTheGlobalGateDetectsUndescribedObjects, ...
    @testTheGlobalGateDetectsUndescribedRelationships});
end

% ---------------------------------------------------------------------------
% The committed document
% ---------------------------------------------------------------------------

function testTheCommittedDocumentSurvivesItsOwnClaims(testCase)
% Whatever the document claims about itself must be true of it.
%
% This replaces testTheCommittedDocumentIsNotYetComplete, which asserted that
% NO domain was declared complete. That assertion was Part 2's way of saying it
% shipped a seed rather than schema documentation, and Part 3a retired it by
% completing the first three domains -- which is what it was written to detect.
%
% Deleting it outright would have left the committed document unguarded between
% here and part3g, which is the one pass that adds the global assertion. So the
% weaker claim is replaced by a stronger one that holds at every point in
% between: a domain declared complete must actually be complete. A later subpart
% that claims a domain while leaving one of its columns undescribed fails here,
% in the ordinary suite, rather than at the end of Part 3.
%
% It deliberately asserts nothing about HOW MANY domains are claimed. part3g
% owns that, and a count here would be a literal this test would have to chase.
cleanup = addSourcePath(); %#ok<NASGU>

report = vawlume.schema.validateMetadata( ...
    RepoRoot=repoRootForTest(), Mode="complete", Print=false);

verifyTrue(testCase, report.passed, ...
    "The committed metadata does not survive its own completeness claims: " + ...
    newline + strjoin(report.findings.detail, newline));

% A claim of zero domains would pass the gate vacuously. Part 3 has begun, so
% at least one domain is claimed and the gate above had something to check.
verifyNotEmpty(testCase, report.complete_domains, ...
    "No domain is declared complete, so the completeness gate proved nothing.");
end

function testTheCommittedDocumentIsGloballyComplete(testCase)
% The committed document describes the whole supported schema: every object,
% every column and every relationship. An export package renders all of them,
% so any one left out would ship as a blank cell in a package that presents
% itself as self-describing.
%
% Passing Mode="complete" is not enough on its own. The global check runs only
% once every domain is claimed, so a document that quietly dropped one claim
% would still pass while no longer asserting that it covers the schema. The
% test therefore also requires that no described object sits in an unclaimed
% domain, and that the described counts equal the structural ones. Both are
% stated without literals, so a schema change moves them with it.
cleanup = addSourcePath(); %#ok<NASGU>

report = vawlume.schema.validateMetadata( ...
    RepoRoot=repoRootForTest(), Mode="complete", Print=false);

verifyTrue(testCase, report.passed, ...
    "The committed metadata is not globally complete: " + ...
    newline + strjoin(report.findings.detail, newline));

metadata = vawlume.schema.loadMetadata(RepoRoot=repoRootForTest());
unclaimed = setdiff(unique(metadata.objects.domain), report.complete_domains.domain);
verifyEmpty(testCase, unclaimed, ...
    "Objects are described in domains the document does not claim complete, " + ...
    "so the global check never ran: " + strjoin(unclaimed, ", "));

verifyEqual(testCase, report.described_objects, report.structural_objects, ...
    "Every schema object must be described.");
verifyEqual(testCase, report.described_columns, report.structural_columns, ...
    "Every schema column must be described or, on a view, explicitly pointed.");
verifyEqual(testCase, report.described_relationships, report.structural_relationships, ...
    "Every structural relationship must be described.");
end

function testAPartialDocumentPassesIdentityButClaimsNothing(testCase)
% A document describing three of 107 objects is not wrong, it is unfinished.
% Identity mode must not confuse the two, or Part 3's subparts could never run.
cleanup = addSourcePath(); %#ok<NASGU>

report = validateFixture(testCase, validDocument(), "identity");
verifyTrue(testCase, report.passed);
verifyEqual(testCase, report.described_objects, 2);
verifyEqual(testCase, report.structural_objects, 107);
end

% ---------------------------------------------------------------------------
% Domain-scoped completeness
% ---------------------------------------------------------------------------

function testADeclaredDomainMustDescribeEveryColumnOfItsObjects(testCase)
% The injected omission: `projects` really has six columns and the fixture
% describes five of them while claiming its domain is finished.
cleanup = addSourcePath(); %#ok<NASGU>

document = completeFixture();
document.objects.projects.columns = rmfield(document.objects.projects.columns, "archived_at_utc");

report = validateFixture(testCase, document, "complete");

verifyFalse(testCase, report.passed);
verifyEqual(testCase, unique(report.findings.code), "vawlume:schema:MetadataIncomplete");
% Grouped by object and naming what is absent: a completeness failure over
% 1,155 columns is only actionable if it says which ones.
detail = char(strjoin(report.findings.detail, " "));
verifySubstring(testCase, detail, "projects");
verifySubstring(testCase, detail, "archived_at_utc");
end

function testADeclaredDomainMustMatchItsOwnObjectCount(testCase)
% An entirely absent object cannot be detected by looking at the objects that
% are present, so the claim carries the count it is claiming for. Getting the
% count wrong, or dropping an object without adjusting it, both fail here.
cleanup = addSourcePath(); %#ok<NASGU>

document = completeFixture();
document.objects = rmfield(document.objects, "schema_info");

report = validateFixture(testCase, document, "complete");

verifyFalse(testCase, report.passed);
verifyFinding(testCase, report, "vawlume:schema:MetadataIncomplete");
detail = char(strjoin(report.findings.detail, " "));
verifySubstring(testCase, detail, "identity_config_provenance");
end

function testADeclaredDomainThatIsCompleteIsAccepted(testCase)
% The gate has to be passable, or the tests above would prove only that it
% always fails.
cleanup = addSourcePath(); %#ok<NASGU>

report = validateFixture(testCase, completeFixture(), "complete");

verifyTrue(testCase, report.passed, ...
    "A genuinely complete domain was rejected: " + ...
    newline + strjoin(report.findings.detail, newline));
verifyEqual(testCase, report.complete_domains.domain, "identity_config_provenance");
end

% ---------------------------------------------------------------------------
% The global gate
% ---------------------------------------------------------------------------

function testTheGlobalGateStaysQuietUntilEveryDomainIsClaimed(testCase)
% With one domain claimed, the 105 objects in the other nine are expected to be
% absent. Reporting them would make the per-domain gate unusable.
cleanup = addSourcePath(); %#ok<NASGU>

report = validateFixture(testCase, completeFixture(), "complete");

verifyTrue(testCase, report.passed);
verifyLessThan(testCase, report.described_objects, report.structural_objects);
end

function testTheGlobalGateDetectsUndescribedObjects(testCase)
% Claiming every domain is the document asserting it covers the whole schema.
% That assertion is checked against the schema, not taken.
cleanup = addSourcePath(); %#ok<NASGU>

document = claimEveryDomain(completeFixture());
report = validateFixture(testCase, document, "complete");

verifyFalse(testCase, report.passed);
detail = char(strjoin(report.findings.detail, " "));
verifySubstring(testCase, detail, "not described");
% 107 structural objects, 3 described by the fixture.
verifySubstring(testCase, detail, "104 object(s)");
end

function testTheGlobalGateDetectsUndescribedRelationships(testCase)
% Objects and columns are not the whole schema. A package whose
% relationships.csv is empty is not self-describing either.
cleanup = addSourcePath(); %#ok<NASGU>

document = claimEveryDomain(completeFixture());
report = validateFixture(testCase, document, "complete");

% Matched on the sentence, not the word: several TABLES are named
% `*_relationships`, so a looser filter would find the object finding instead
% and pass while proving nothing about relationships.
relationshipFindings = report.findings.detail( ...
    contains(report.findings.detail, "relationship(s) have no description"));
verifyNotEmpty(testCase, relationshipFindings, ...
    "Every domain was claimed complete with 1 of 245 relationships described, " + ...
    "and nothing was reported.");
verifySubstring(testCase, char(relationshipFindings(1)), "244");
end

% ---------------------------------------------------------------------------
% Fixtures
% ---------------------------------------------------------------------------

function document = validDocument()
% Partial by construction: two objects of 107, and no domain claimed.
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

document.relationships = {struct( ...
    "source_table", "config_profiles", ...
    "source_columns", {{"project_id"}}, ...
    "target_table", "projects", ...
    "target_columns", {{"project_id"}}, ...
    "description", "Each configuration profile naming a project belongs to that project.")};
end

function document = completeFixture()
% The same two objects, plus a third, with their domain declared complete. The
% claim is about the three objects the document assigns to that domain, not
% about the ten the real schema puts there -- which is exactly what makes the
% count part of the claim.
document = validDocument();
document.objects.config_profiles = struct( ...
    "kind", "table", ...
    "domain", "identity_config_provenance", ...
    "description", "A named configuration profile: one interpretation contract cited as provenance.", ...
    "columns", struct( ...
        "profile_id", struct("description", "VAWLUME surrogate key for the configuration profile."), ...
        "project_id", struct("description", "Project owning this profile; null for a built-in one."), ...
        "profile_key", struct("description", "Stable identifier cited by assignments and run provenance."), ...
        "profile_name", struct("description", "Human-readable name used when reporting configuration."), ...
        "profile_kind", struct("description", "Which interpretation contract this profile expresses."), ...
        "is_builtin", struct("description", "Whether VAWLUME shipped this profile or a user authored it."), ...
        "description", struct("description", "Free-text account of what the profile interprets."), ...
        "created_at_utc", struct("description", "UTC timestamp recorded when the row was created.")));

document.coverage = struct("complete_domains", ...
    {{struct("domain", "identity_config_provenance", "object_count", 3)}});
end

function document = claimEveryDomain(document)
% Claim every domain in the vocabulary, with an honest count for each: the
% document then asserts it covers the whole schema, and the global check runs.
domains = ["identity_config_provenance", "entities_experiment", ...
    "recordings_geometry", "extractors_features", "detections_curation", ...
    "matching_agreement", "alignment_external", "tracking_acoustic_derived", ...
    "attribution", "views"];

described = string(fieldnames(document.objects));
claimed = cell(1, numel(domains));
for k = 1:numel(domains)
    count = 0;
    for j = 1:numel(described)
        if string(document.objects.(described(j)).domain) == domains(k)
            count = count + 1;
        end
    end
    claimed{k} = struct("domain", domains(k), "object_count", count);
end

document.coverage = struct("complete_domains", {claimed});
end

function report = validateFixture(testCase, document, mode)
path = writeDocument(testCase, string(jsonencode(document, PrettyPrint=true)));
report = vawlume.schema.validateMetadata( ...
    Path=path, RepoRoot=repoRootForTest(), Mode=mode, Print=false);
end

function verifyFinding(testCase, report, code)
verifyTrue(testCase, any(report.findings.code == code), ...
    "Expected " + code + ". Got: " + strjoin(report.findings.code', ", "));
end

% ---------------------------------------------------------------------------
% Test plumbing
% ---------------------------------------------------------------------------

function path = writeDocument(testCase, text)
workspace = fullfile(tempdir, "vawlume_metadata_coverage_" + string(java.util.UUID.randomUUID));
mkdir(workspace);
testCase.addTeardown(@() removeTree(workspace));
path = fullfile(workspace, "metadata.json");
fid = fopen(path, "w", "n", "UTF-8");
fwrite(fid, unicode2native(text, "UTF-8"));
fclose(fid);
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
