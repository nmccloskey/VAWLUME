function report = check_repository_self_description(options)
%CHECK_REPOSITORY_SELF_DESCRIPTION Verify published claims against the repository.
%
%   REPORT = CHECK_REPOSITORY_SELF_DESCRIPTION() compares every literal
%   current-state claim VAWLUME's documentation makes about the repository
%   against the repository itself, and returns a report struct with fields
%   `passed`, `checks`, `failures`, and `inventory`.
%
%   CHECK_REPOSITORY_SELF_DESCRIPTION() with no output argument prints the
%   report and raises `vawlume:repository:SelfDescriptionStale` if any check
%   failed.
%
%   Name-value arguments:
%     RepoRoot  - repository root (default: the parent of this file's folder)
%     Print     - print the report (default: true when nargout == 0)
%
%   The principle: the software state is authoritative and the documentation
%   describes it. This check exists so that no published literal about the
%   repository is maintained by hand and verified by nothing.
%
%   Claim semantics are defined in
%   docs/development/30_repository_self_description.md. In short:
%
%     * a CURRENT-STATE claim asserts a present repository fact and must be
%       verified here;
%     * a HISTORICAL claim records a past checkpoint, is frozen, and is exempt.
%       It is recognized by a marker phrase in its paragraph, or by living under
%       docs/design/;
%     * a QUALITATIVE description stays true across ordinary change and is
%       preferred wherever the exact number carries no reader value.
%
%   Like REPOSITORY_INVENTORY, this check is non-executing: it runs no test,
%   opens no database, and writes nothing.
%
%   See also REPOSITORY_INVENTORY.

arguments
    options.RepoRoot (1,1) string = ""
    options.Print = []
end

repoRoot = options.RepoRoot;
if repoRoot == ""
    repoRoot = string(fileparts(fileparts(mfilename("fullpath"))));
end

doPrint = options.Print;
if isempty(doPrint)
    doPrint = (nargout == 0);
end

inventory = repository_inventory(RepoRoot=repoRoot, Print=false);

checks = struct("name", {}, "passed", {}, "detail", {}, "failures", {});
checks(end+1) = checkSchemaCoherence(inventory);
checks(end+1) = checkSchemaClaims(repoRoot, inventory);
checks(end+1) = checkExampleInventory(repoRoot, inventory);
checks(end+1) = checkExampleTestCoverage(repoRoot, inventory);
checks(end+1) = checkConfigInventory(repoRoot, inventory);
checks(end+1) = checkRelativeLinks(repoRoot, inventory);
checks(end+1) = checkNoUnverifiedSuiteCounts(repoRoot);

report = struct();
report.inventory = inventory;
report.checks = checks;
report.passed = all([checks.passed]);
report.failures = toStringColumn({checks(~[checks.passed]).name});

if doPrint
    printReport(report);
end

if nargout == 0 && ~report.passed
    error("vawlume:repository:SelfDescriptionStale", ...
        "Repository self-description is stale: %s.", ...
        strjoin(report.failures, ", "));
end
end

% ---------------------------------------------------------------------------
% Checks
% ---------------------------------------------------------------------------

function check = checkSchemaCoherence(inventory)
% The three spellings of the schema version inside schema.sql must agree.
schema = inventory.schema;
detail = sprintf("header %s, schema_info %s, user_version %d", ...
    schema.header_version, schema.schema_info_version, schema.user_version);
check = makeCheck("schema version internally coherent", schema.coherent, detail);
end

function check = checkSchemaClaims(repoRoot, inventory)
% Every non-historical relational-schema-version literal published in a
% current-state document must name the version the schema actually carries.
%
% `X.Y-draft` is a shape shared by four independent version namespaces: the
% relational schema, the profile language (`profile_schema_version`), the
% intermediate representation (`ir_schema_version`), and the alignment manifest
% (`manifest_schema_version`). Only the first is this check's business; the
% other three are validated by the loader and its tests.
%
% The discriminator is `PRAGMA user_version`, which belongs to the relational
% schema alone. A published relational-schema version must therefore be stated
% together with its `user_version`, and a paragraph naming `user_version` is
% read as a relational-schema claim.
current = inventory.schema.header_version;
currentUserVersion = inventory.schema.user_version;
failures = strings(0, 1);
claimCount = 0;

documents = currentStateDocuments(inventory.documents.files);
for k = 1:numel(documents)
    relPath = documents(k);
    paragraphs = paragraphsOf(fullfile(repoRoot, relPath));
    for p = 1:numel(paragraphs)
        paragraph = paragraphs(p);
        if isHistorical(paragraph) || ~contains(paragraph, "user_version")
            continue
        end

        versions = allTokens(paragraph, "(\d+\.\d+-draft)");
        for v = 1:numel(versions)
            claimCount = claimCount + 1;
            if versions(v) ~= current
                failures(end+1, 1) = sprintf("%s claims schema version %s; schema.sql carries %s", ...
                    relPath, versions(v), current); %#ok<AGROW>
            end
        end

        userVersions = allTokens(paragraph, "user_version\s*=\s*(\d+)");
        for v = 1:numel(userVersions)
            claimCount = claimCount + 1;
            if double(userVersions(v)) ~= currentUserVersion
                failures(end+1, 1) = sprintf("%s claims user_version %s; schema.sql sets %d", ...
                    relPath, userVersions(v), currentUserVersion); %#ok<AGROW>
            end
        end
    end
end

detail = sprintf("%d current-state schema-version claims checked against %s", ...
    claimCount, current);
check = makeCheck("schema version claims current", isempty(failures), detail, failures);
end

function check = checkExampleInventory(repoRoot, inventory)
% The demonstrations named in the two current-state documents and the files in
% examples/ must be the same set, in both directions.
documents = ["README.md", "docs/usage/01_prototype_usage_guide.md"];
actual = inventory.examples.names;
failures = strings(0, 1);

for k = 1:numel(documents)
    text = string(fileread(fullfile(repoRoot, documents(k))));
    named = unique(allTokens(text, "(\w+_demo)(?!\w)"));

    missingFromDoc = setdiff(actual, named);
    for m = 1:numel(missingFromDoc)
        failures(end+1, 1) = sprintf("%s never names examples/%s.m", ...
            documents(k), missingFromDoc(m)); %#ok<AGROW>
    end

    absentFromRepo = setdiff(named, actual);
    for m = 1:numel(absentFromRepo)
        failures(end+1, 1) = sprintf("%s names %s, which is not in examples/", ...
            documents(k), absentFromRepo(m)); %#ok<AGROW>
    end
end

detail = sprintf("%d demonstrations in examples/, named in %d documents", ...
    inventory.examples.count, numel(documents));
check = makeCheck("example inventory matches documentation", isempty(failures), detail, failures);
end

function check = checkExampleTestCoverage(repoRoot, inventory)
% Both documents claim every demonstration is covered by an integration test.
listing = dir(fullfile(repoRoot, "tests", "integration", "*.m"));
listing = listing(~[listing.isdir]);
corpus = "";
for k = 1:numel(listing)
    corpus = corpus + string(fileread(fullfile(listing(k).folder, listing(k).name)));
end

failures = strings(0, 1);
for k = 1:numel(inventory.examples.names)
    name = inventory.examples.names(k);
    if ~contains(corpus, name)
        failures(end+1, 1) = sprintf("no integration test calls %s", name); %#ok<AGROW>
    end
end

detail = sprintf("%d demonstrations checked against %d integration test files", ...
    inventory.examples.count, numel(listing));
check = makeCheck("every demonstration has an integration test", isempty(failures), detail, failures);
end

function check = checkConfigInventory(repoRoot, inventory)
% Every configuration directory that holds a tracked artifact must be named in
% the configuration README, and every config/ path the documentation names must
% exist.
documents = ["config/README.md", "docs/usage/01_prototype_usage_guide.md", "README.md"];
readmeText = string(fileread(fullfile(repoRoot, "config", "README.md")));
corpus = "";
for k = 1:numel(documents)
    corpus = corpus + string(fileread(fullfile(repoRoot, documents(k))));
end

failures = strings(0, 1);
for k = 1:numel(inventory.config.directories)
    directory = inventory.config.directories(k);
    if ~contains(readmeText, directory)
        failures(end+1, 1) = sprintf("config/README.md never names %s/", directory); %#ok<AGROW>
    end
end

referenced = unique(allTokens(corpus, "(config/[A-Za-z0-9_./-]+)"));
for k = 1:numel(referenced)
    candidate = regexprep(referenced(k), "[./]+$", "");
    if ~isfile(fullfile(repoRoot, candidate)) && ~isfolder(fullfile(repoRoot, candidate))
        failures(end+1, 1) = sprintf("documented path %s does not exist", referenced(k)); %#ok<AGROW>
    end
end

detail = sprintf("%d directories documented, %d referenced paths resolved", ...
    numel(inventory.config.directories), numel(referenced));
check = makeCheck("configuration inventory documented", isempty(failures), detail, failures);
end

function check = checkRelativeLinks(repoRoot, inventory)
% A relative link that no longer resolves is a stale claim about the repository
% in the same sense a stale count is.
failures = strings(0, 1);
linkCount = 0;

for k = 1:numel(inventory.documents.files)
    relPath = inventory.documents.files(k);
    documentFolder = fileparts(fullfile(repoRoot, relPath));
    text = string(fileread(fullfile(repoRoot, relPath)));
    targets = allTokens(text, "\]\(([^)]+)\)");

    for t = 1:numel(targets)
        target = strtrim(targets(t));
        target = regexprep(target, '\s+".*"$', "");
        if target == "" || startsWith(target, "#") || contains(target, "://") ...
                || startsWith(target, "mailto:")
            continue
        end
        target = extractBefore(target + "#", "#");
        target = replace(target, "%20", " ");
        linkCount = linkCount + 1;
        resolved = fullfile(documentFolder, target);
        if ~isfile(resolved) && ~isfolder(resolved)
            failures(end+1, 1) = sprintf("%s links to %s, which does not exist", ...
                relPath, target); %#ok<AGROW>
        end
    end
end

detail = sprintf("%d relative links across %d documents", linkCount, inventory.documents.count);
check = makeCheck("relative documentation links resolve", isempty(failures), detail, failures);
end

function check = checkNoUnverifiedSuiteCounts(repoRoot)
% Guard against the failure this check was written to end: a hand-maintained
% test count reappearing in a current-state document. The size of the suite is a
% derived fact; report it with repository_inventory instead of publishing it.
documents = ["README.md", "docs/usage/01_prototype_usage_guide.md"];
failures = strings(0, 1);

for k = 1:numel(documents)
    paragraphs = paragraphsOf(fullfile(repoRoot, documents(k)));
    for p = 1:numel(paragraphs)
        if isHistorical(paragraphs(p))
            continue
        end
        % MATLAB regexp has no \b; (?!\w) is the portable word-boundary form.
        offenders = allTokens(paragraphs(p), "(\d+\s+test files|\d+\s+tests?(?!\w))");
        for o = 1:numel(offenders)
            failures(end+1, 1) = sprintf("%s states a literal suite size (%s); use repository_inventory", ...
                documents(k), strtrim(offenders(o))); %#ok<AGROW>
        end
    end
end

detail = sprintf("%d current-state documents scanned", numel(documents));
check = makeCheck("no hand-maintained suite counts", isempty(failures), detail, failures);
end

% ---------------------------------------------------------------------------
% Claim semantics
% ---------------------------------------------------------------------------

function documents = currentStateDocuments(allDocuments)
% docs/design/ is the frozen design-record layer: contracts as written and
% audits as performed, including past checkpoints. It does not describe the
% repository as it stands today, so it is exempt.
documents = allDocuments(~startsWith(allDocuments, "docs/design/"));
end

function flag = isHistorical(paragraph)
% A paragraph carrying one of these markers records a past state deliberately.
markers = [
    "Introduced at"
    "Added at"
    "Pre-existing"
    "regression floor"
    "exit state"
    "historical record"];
flag = any(contains(paragraph, markers));
end

function paragraphs = paragraphsOf(filePath)
text = string(fileread(filePath));
paragraphs = toStringColumn(regexp(text, "\r?\n\s*\r?\n", "split"));
paragraphs = paragraphs(strlength(strtrim(paragraphs)) > 0);
end

% ---------------------------------------------------------------------------
% Helpers
% ---------------------------------------------------------------------------

function check = makeCheck(name, passed, detail, failures)
if nargin < 4
    failures = strings(0, 1);
end
check = struct("name", string(name), "passed", logical(passed), ...
    "detail", string(detail), "failures", {failures});
end

function tokens = allTokens(text, pattern)
matches = regexp(text, pattern, "tokens");
if isempty(matches)
    tokens = strings(0, 1);
    return
end
tokens = strings(numel(matches), 1);
for k = 1:numel(matches)
    tokens(k) = string(matches{k}{1});
end
end

function values = toStringColumn(cellValues)
if isempty(cellValues)
    values = strings(0, 1);
else
    values = string(cellValues(:));
end
end

function printReport(report)
fprintf("VAWLUME repository self-description check\n");
fprintf("  schema %s | %d tests in %d files | %d demonstrations\n\n", ...
    report.inventory.schema.header_version, report.inventory.tests.count, ...
    report.inventory.tests.file_count, report.inventory.examples.count);

for k = 1:numel(report.checks)
    check = report.checks(k);
    if check.passed
        status = "PASS";
    else
        status = "FAIL";
    end
    fprintf("  [%s] %-45s %s\n", status, check.name, check.detail);
    for f = 1:numel(check.failures)
        fprintf("         - %s\n", check.failures(f));
    end
end

fprintf("\n");
if report.passed
    fprintf("  All %d checks passed.\n", numel(report.checks));
else
    fprintf("  %d of %d checks FAILED.\n", numel(report.failures), numel(report.checks));
end
end
