function report = validateMetadata(options)
%VALIDATEMETADATA Check authored semantics against the committed schema.
%
%   REPORT = VAWLUME.SCHEMA.VALIDATEMETADATA() loads
%   schema/schema_metadata.json and schema/schema.json and checks that every
%   object, column, relationship endpoint and `same_as` target the semantic
%   document names actually exists, with the kind it claims.
%
%   VAWLUME.SCHEMA.VALIDATEMETADATA() with no output argument prints the report
%   and raises if anything failed, so it is usable as a command.
%
%   Name-value arguments:
%     Path            - semantic document (default: the repository's)
%     StructuralPath  - structural representation (default: schema/schema.json)
%     RepoRoot        - repository root
%     Metadata        - an already-loaded metadata struct, instead of Path
%     Mode            - "identity" (default) or "complete"
%     Print           - print the report (default: true when nargout == 0)
%
%   TWO MODES.
%
%   "identity" asks whether everything the document says is true: no invented
%   object, no column on the wrong object, no relationship SQLite does not
%   declare. It does NOT ask whether anything is missing, so it passes on a
%   deliberately partial document -- which is what Part 3's subparts need while
%   the schema is being described domain by domain.
%
%   "complete" adds the absence checks. It enforces coverage for every domain
%   the document CLAIMS is complete, and additionally, when every domain in the
%   vocabulary is claimed, requires that the document account for the whole
%   schema: every object, every column, every relationship.
%
%   FINDINGS, NOT AN EXCEPTION PER FAULT. The report names every problem it
%   found rather than the first, because somebody describing 1,155 columns needs
%   one run to tell them all of it. Each finding carries the `vawlume:schema:*`
%   identifier for its condition in `code`, so a test can assert the exact
%   condition it injected. When exactly one finding exists the command form
%   raises that specific identifier; with several it raises
%   `vawlume:schema:MetadataInvalid` and lists them.
%
%   This layer needs no database and no tbls. It compares two committed files.
%
%   See also VAWLUME.SCHEMA.LOADMETADATA, VAWLUME.SCHEMA.REPOSITORYVERSION.

arguments
    options.Path (1,1) string = ""
    options.StructuralPath (1,1) string = ""
    options.RepoRoot (1,1) string = ""
    options.Metadata = []
    options.Mode (1,1) string {mustBeMember(options.Mode, ["identity", "complete"])} = "identity"
    options.Print = []
end

repoRoot = options.RepoRoot;
if repoRoot == ""
    repoRoot = schemaRepositoryRoot();
end

structuralPath = options.StructuralPath;
if structuralPath == ""
    structuralPath = fullfile(repoRoot, "schema", "schema.json");
end

doPrint = options.Print;
if isempty(doPrint)
    doPrint = (nargout == 0);
end

if isempty(options.Metadata)
    metadata = vawlume.schema.loadMetadata(Path=options.Path, RepoRoot=repoRoot);
else
    metadata = options.Metadata;
end

structural = schemaLoadStructural(structuralPath);

findings = emptyFindings();
findings = [findings; checkSchemaVersion(metadata, repoRoot)];
findings = [findings; checkObjects(metadata, structural)];
findings = [findings; checkColumns(metadata, structural)];
findings = [findings; checkSameAsTargets(metadata, structural)];
findings = [findings; checkRelationships(metadata, structural)];

if options.Mode == "complete"
    findings = [findings; checkCompleteness(metadata, structural)];
end

report = struct();
report.mode = options.Mode;
report.metadata_path = metadata.source_path;
report.structural_path = structural.source_path;
report.metadata_version = metadata.metadata_version;
report.schema_version = metadata.schema_version;
report.repository_schema_version = safeRepositoryVersion(repoRoot);
report.complete_domains = metadata.complete_domains;
report.described_objects = height(metadata.objects);
report.described_columns = height(metadata.columns);
report.described_relationships = height(metadata.relationships);
report.structural_objects = height(structural.objects);
report.structural_columns = height(structural.columns);
report.structural_relationships = height(structural.relations);
report.findings = findings;
report.passed = isempty(findings);

if doPrint
    printReport(report);
end

if nargout == 0 && ~report.passed
    raiseFindings(findings);
end
end

% ---------------------------------------------------------------------------
% Checks
% ---------------------------------------------------------------------------

function findings = checkSchemaVersion(metadata, repoRoot)
findings = emptyFindings();
try
    actual = vawlume.schema.repositoryVersion(RepoRoot=repoRoot);
catch exception
    findings = addFinding(findings, "vawlume:schema:SchemaVersionMismatch", "", "", ...
        sprintf("Could not read the repository schema version: %s", exception.message));
    return
end

if metadata.schema_version ~= actual
    % Not a warning. Descriptions authored against one schema version can be
    % confidently wrong about another, and a package that ships them would look
    % self-describing while misdescribing its own contents.
    findings = addFinding(findings, "vawlume:schema:SchemaVersionMismatch", "", "", ...
        sprintf("Metadata declares schema_version ""%s"" but schema/schema.sql is ""%s"". " + ...
        "Re-check the descriptions against the current schema, then update schema_version.", ...
        metadata.schema_version, actual));
end
end

function findings = checkObjects(metadata, structural)
findings = emptyFindings();
for k = 1:height(metadata.objects)
    name = metadata.objects.object_name(k);
    match = structural.objects.object_name == name;

    if ~any(match)
        findings = addFinding(findings, "vawlume:schema:MetadataUnknownObject", name, "", ...
            sprintf("No object named ""%s"" exists in the schema.", name));
        continue
    end

    actualKind = structural.objects.object_kind(match);
    if metadata.objects.object_kind(k) ~= actualKind
        findings = addFinding(findings, "vawlume:schema:MetadataObjectKindMismatch", name, "", ...
            sprintf("Metadata calls ""%s"" a %s; the schema declares it a %s.", ...
            name, metadata.objects.object_kind(k), actualKind));
    end
end
end

function findings = checkColumns(metadata, structural)
findings = emptyFindings();
known = structural.objects.object_name;
for k = 1:height(metadata.columns)
    object = metadata.columns.object_name(k);
    column = metadata.columns.column_name(k);

    if ~ismember(object, known)
        % The object itself was already reported; do not report every one of
        % its columns as well.
        continue
    end

    onObject = structural.columns.object_name == object & ...
        structural.columns.column_name == column;
    if ~any(onObject)
        findings = addFinding(findings, "vawlume:schema:MetadataUnknownColumn", object, column, ...
            sprintf("%s has no column named ""%s"".", object, column));
    end
end
end

function findings = checkSameAsTargets(metadata, structural)
findings = emptyFindings();
pointers = find(~ismissing(metadata.columns.same_as));

for index = pointers(:)'
    object = metadata.columns.object_name(index);
    column = metadata.columns.column_name(index);
    target = metadata.columns.same_as(index);

    parts = split(target, ".");
    targetObject = parts(1);
    targetColumn = parts(2);

    targetRow = structural.objects.object_name == targetObject;
    if ~any(targetRow)
        findings = addFinding(findings, "vawlume:schema:MetadataUnknownSameAsTarget", object, column, ...
            sprintf("%s.%s points at ""%s"", but no object of that name exists.", ...
            object, column, target));
        continue
    end

    if structural.objects.object_kind(targetRow) ~= "table"
        % A pointer chain between views could resolve to another pointer, or to
        % a cycle. Requiring a base table keeps resolution one hop and total.
        findings = addFinding(findings, "vawlume:schema:MetadataUnknownSameAsTarget", object, column, ...
            sprintf("%s.%s points at ""%s"", which is a view. A same_as target " + ...
            "must be a base-table column.", object, column, target));
        continue
    end

    onTarget = structural.columns.object_name == targetObject & ...
        structural.columns.column_name == targetColumn;
    if ~any(onTarget)
        findings = addFinding(findings, "vawlume:schema:MetadataUnknownSameAsTarget", object, column, ...
            sprintf("%s.%s points at ""%s"", but %s has no column named ""%s"".", ...
            object, column, target, targetObject, targetColumn));
    end
end
end

function findings = checkRelationships(metadata, structural)
findings = emptyFindings();
structuralKeys = structural.relations.relationship_key;

for k = 1:height(metadata.relationships)
    key = metadata.relationships.relationship_key(k);
    if ismember(key, structuralKeys)
        continue
    end

    % A reversed entry is the likeliest authoring mistake, and it is the one a
    % generic "unknown relationship" message helps least with, so it gets its
    % own condition and its own remedy.
    reversed = schemaRelationshipKey( ...
        metadata.relationships.target_table(k), metadata.relationships.target_columns(k), ...
        metadata.relationships.source_table(k), metadata.relationships.source_columns(k));

    if ismember(reversed, structuralKeys)
        findings = addFinding(findings, "vawlume:schema:MetadataRelationshipReversed", ...
            metadata.relationships.source_table(k), "", ...
            sprintf("%s is declared backwards. The schema declares %s. " + ...
            "source is the child -- the table holding the foreign key.", key, reversed));
    else
        findings = addFinding(findings, "vawlume:schema:MetadataRelationshipUnknown", ...
            metadata.relationships.source_table(k), "", ...
            sprintf("%s is not a foreign key the schema declares. Semantic " + ...
            "relationships must match a structural relation exactly.", key));
    end
end
end

function findings = checkCompleteness(metadata, structural)
findings = emptyFindings();

% Per-domain: every object claiming a complete domain must have all of its
% structural columns described, and the object count must match what the
% document claims for that domain.
for k = 1:height(metadata.complete_domains)
    domain = metadata.complete_domains.domain(k);
    claimed = metadata.complete_domains.object_count(k);

    inDomain = metadata.objects.object_name(metadata.objects.domain == domain);

    if numel(inDomain) ~= claimed
        findings = addFinding(findings, "vawlume:schema:MetadataIncomplete", "", "", ...
            sprintf("Domain ""%s"" is declared complete with %d objects, but %d " + ...
            "objects claim it. An object is missing, or the count is wrong.", ...
            domain, claimed, numel(inDomain)));
    end

    for object = inDomain(:)'
        expected = structural.columns.column_name(structural.columns.object_name == object);
        described = metadata.columns.column_name(metadata.columns.object_name == object);
        absent = setdiff(expected, described, "stable");
        if ~isempty(absent)
            % One finding per object rather than per column. An author who has
            % not started a table wants to be told that once, not forty times.
            findings = addFinding(findings, "vawlume:schema:MetadataIncomplete", object, "", ...
                sprintf("%s (domain ""%s"", declared complete) does not describe %d of " + ...
                "its %d columns: %s", object, domain, numel(absent), numel(expected), ...
                nameList(absent)));
        end
    end
end

% Global: only once every domain is claimed complete does the document assert
% that it covers the whole schema. Until then a missing object is expected.
if height(metadata.complete_domains) < numel(schemaDomainVocabulary())
    return
end

absentObjects = setdiff(structural.objects.object_name, metadata.objects.object_name, "stable");
if ~isempty(absentObjects)
    findings = addFinding(findings, "vawlume:schema:MetadataIncomplete", "", "", ...
        sprintf("Every domain is declared complete, but %d object(s) are not described: %s", ...
        numel(absentObjects), nameList(absentObjects)));
end

describedRelationships = metadata.relationships.relationship_key;
absentRelationships = setdiff(structural.relations.relationship_key, describedRelationships, "stable");
if ~isempty(absentRelationships)
    findings = addFinding(findings, "vawlume:schema:MetadataIncomplete", "", "", ...
        sprintf("Every domain is declared complete, but %d relationship(s) have no " + ...
        "description: %s", numel(absentRelationships), nameList(absentRelationships)));
end
end

function text = nameList(names)
% A completeness failure naming 1,155 columns is not a report, it is a wall.
% The count is the number that matters; enough names follow to make it concrete
% and to give the author somewhere to start.
limit = 10;
if numel(names) <= limit
    text = strjoin(names(:)', ", ") + ".";
    return
end
text = strjoin(names(1:limit)', ", ") + ", and " + (numel(names) - limit) + " more.";
end

% ---------------------------------------------------------------------------
% Findings
% ---------------------------------------------------------------------------

function findings = emptyFindings()
findings = table(strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    VariableNames=["code", "object_name", "column_name", "detail"]);
end

function findings = addFinding(findings, code, objectName, columnName, detail)
findings(end + 1, :) = {string(code), string(objectName), string(columnName), string(detail)};
end

function raiseFindings(findings)
codes = unique(findings.code);
lines = strjoin("  - " + findings.detail, newline);

if isscalar(codes)
    % One condition: raise it by name, so a caller that injected exactly one
    % defect can catch exactly what it injected.
    error(codes(1), "Schema metadata validation failed:\n%s", lines);
end

error("vawlume:schema:MetadataInvalid", ...
    "Schema metadata validation failed with %d findings across %d conditions:\n%s", ...
    height(findings), numel(codes), lines);
end

function value = safeRepositoryVersion(repoRoot)
try
    value = vawlume.schema.repositoryVersion(RepoRoot=repoRoot);
catch
    value = string(missing);
end
end

function printReport(report)
fprintf("Schema metadata validation (%s mode)\n", report.mode);
fprintf("  metadata:            %s\n", report.metadata_path);
fprintf("  structure:           %s\n", report.structural_path);
fprintf("  metadata_version:    %s\n", report.metadata_version);
fprintf("  schema_version:      %s (repository: %s)\n", ...
    report.schema_version, report.repository_schema_version);
fprintf("  described:           %d/%d objects, %d/%d columns, %d/%d relationships\n", ...
    report.described_objects, report.structural_objects, ...
    report.described_columns, report.structural_columns, ...
    report.described_relationships, report.structural_relationships);

if isempty(report.complete_domains)
    fprintf("  domains complete:    none yet\n");
else
    fprintf("  domains complete:    %s\n", ...
        strjoin(report.complete_domains.domain' + " (" + ...
        string(report.complete_domains.object_count') + ")", ", "));
end

if report.passed
    fprintf("  result:              PASS\n");
    return
end

fprintf("  result:              %d finding(s)\n", height(report.findings));
for k = 1:height(report.findings)
    fprintf("    [%s] %s\n", report.findings.code(k), report.findings.detail(k));
end
end
