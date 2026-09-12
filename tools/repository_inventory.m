function inventory = repository_inventory(options)
%REPOSITORY_INVENTORY Discover what the VAWLUME repository currently contains.
%
%   INVENTORY = REPOSITORY_INVENTORY() returns a struct of facts derived from
%   the repository on disk: the schema version triple, the test-suite size, the
%   shipped demonstrations, the configuration tree, the MATLAB packages, and the
%   Markdown documents.
%
%   REPOSITORY_INVENTORY() with no output argument prints a compact report.
%
%   Name-value arguments:
%     RepoRoot  - repository root (default: the parent of this file's folder)
%     Print     - print the report (default: true when nargout == 0)
%
%   This function is NON-EXECUTING. It discovers tests without running them,
%   opens no database, and writes nothing. It is safe and cheap enough to run on
%   every itinerary.
%
%   The repository is the authority. This function reports what is there; it
%   makes no claim about what any document says. Comparing the two is the job of
%   CHECK_REPOSITORY_SELF_DESCRIPTION.
%
%   See also CHECK_REPOSITORY_SELF_DESCRIPTION.

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

inventory = struct();
inventory.repo_root = repoRoot;
inventory.schema = schemaFacts(repoRoot);
inventory.tests = testFacts(repoRoot);
inventory.examples = exampleFacts(repoRoot);
inventory.config = configFacts(repoRoot);
inventory.packages = packageFacts(repoRoot);
inventory.documents = documentFacts(repoRoot);

if doPrint
    printInventory(inventory);
end
end

% ---------------------------------------------------------------------------
% Facts
% ---------------------------------------------------------------------------

function facts = schemaFacts(repoRoot)
facts = struct();
facts.file = "schema/schema.sql";
text = string(fileread(fullfile(repoRoot, "schema", "schema.sql")));

facts.header_version = firstToken(text, "--\s*Version:\s*(\S+)");
facts.schema_info_version = firstToken(text, ...
    "INSERT\s+OR\s+IGNORE\s+INTO\s+schema_info[^;]*?VALUES\s*\(\s*'([^']+)'");
userVersionToken = firstToken(text, "PRAGMA\s+user_version\s*=\s*(\d+)");
if ismissing(userVersionToken)
    facts.user_version = NaN;
else
    facts.user_version = double(userVersionToken);
end

% The declared version and the numeric user_version are two spellings of one
% fact. The repository uses "0.<user_version>-draft".
facts.expected_header_for_user_version = "0." + string(facts.user_version) + "-draft";
facts.coherent = ~ismissing(facts.header_version) ...
    && facts.header_version == facts.schema_info_version ...
    && facts.header_version == facts.expected_header_for_user_version;
end

function facts = testFacts(repoRoot)
facts = struct();
testsRoot = fullfile(repoRoot, "tests");

listing = dir(fullfile(testsRoot, "**", "test_*.m"));
listing = listing(~[listing.isdir]);
facts.files = sort(toStringColumn({listing.name}));
facts.file_count = numel(facts.files);

% Suite construction discovers tests; it does not run them.
suite = matlab.unittest.TestSuite.fromFolder(testsRoot, IncludingSubfolders=true);
facts.count = numel(suite);
end

function facts = exampleFacts(repoRoot)
facts = struct();
listing = dir(fullfile(repoRoot, "examples", "*.m"));
listing = listing(~[listing.isdir]);
facts.files = sort(toStringColumn({listing.name}));
facts.names = erase(facts.files, ".m");
facts.count = numel(facts.files);
end

function facts = configFacts(repoRoot)
facts = struct();
listing = dir(fullfile(repoRoot, "config", "**", "*"));
listing = listing(~[listing.isdir]);

files = strings(numel(listing), 1);
for k = 1:numel(listing)
    files(k) = relativePath(repoRoot, fullfile(listing(k).folder, listing(k).name));
end
facts.files = sort(files);

directories = strings(0, 1);
for k = 1:numel(facts.files)
    parent = string(fileparts(facts.files(k)));
    if parent ~= "config"
        directories(end+1, 1) = parent; %#ok<AGROW>
    end
end
facts.directories = unique(directories);
facts.file_count = numel(facts.files);
end

function facts = packageFacts(repoRoot)
facts = struct();
listing = dir(fullfile(repoRoot, "src", "+vawlume", "+*"));
listing = listing([listing.isdir]);
facts.names = sort(erase(toStringColumn({listing.name}), "+"));
facts.count = numel(facts.names);
end

function facts = documentFacts(repoRoot)
facts = struct();
listing = dir(fullfile(repoRoot, "**", "*.md"));
listing = listing(~[listing.isdir]);

files = strings(numel(listing), 1);
for k = 1:numel(listing)
    files(k) = relativePath(repoRoot, fullfile(listing(k).folder, listing(k).name));
end
files = files(~startsWith(files, ".git/"));
facts.files = sort(files);
facts.count = numel(facts.files);
end

% ---------------------------------------------------------------------------
% Reporting
% ---------------------------------------------------------------------------

function printInventory(inventory)
fprintf("VAWLUME repository inventory\n");
fprintf("  root                : %s\n", inventory.repo_root);
fprintf("  schema version      : %s (header), %s (schema_info), user_version %d\n", ...
    inventory.schema.header_version, inventory.schema.schema_info_version, ...
    inventory.schema.user_version);
fprintf("  schema coherent     : %s\n", yesNo(inventory.schema.coherent));
fprintf("  tests               : %d tests in %d files (discovered, not run)\n", ...
    inventory.tests.count, inventory.tests.file_count);
fprintf("  examples            : %d\n", inventory.examples.count);
for k = 1:inventory.examples.count
    fprintf("                        %s\n", inventory.examples.names(k));
end
fprintf("  config files        : %d in %d directories\n", ...
    inventory.config.file_count, numel(inventory.config.directories));
fprintf("  vawlume packages    : %d (%s)\n", inventory.packages.count, ...
    strjoin(inventory.packages.names, ", "));
fprintf("  markdown documents  : %d\n", inventory.documents.count);
end

% ---------------------------------------------------------------------------
% Helpers
% ---------------------------------------------------------------------------

function token = firstToken(text, pattern)
match = regexpi(text, pattern, "tokens", "once");
if isempty(match)
    token = string(missing);
else
    token = string(match{1});
end
end

function values = toStringColumn(cellValues)
if isempty(cellValues)
    values = strings(0, 1);
else
    values = string(cellValues(:));
end
end

function rel = relativePath(repoRoot, absPath)
rel = replace(string(absPath), "\", "/");
root = replace(string(repoRoot), "\", "/");
if ~endsWith(root, "/")
    root = root + "/";
end
if startsWith(rel, root)
    rel = extractAfter(rel, strlength(root));
end
end

function text = yesNo(flag)
if flag
    text = "yes";
else
    text = "NO";
end
end
