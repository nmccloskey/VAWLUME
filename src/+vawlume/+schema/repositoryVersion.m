function version = repositoryVersion(options)
%REPOSITORYVERSION The schema version declared by schema/schema.sql.
%
%   VERSION = VAWLUME.SCHEMA.REPOSITORYVERSION() reads the authoritative
%   schema's `-- Version:` header and returns it as a string, for example
%   "0.10-draft".
%
%   Name-value arguments:
%     RepoRoot    - repository root (default: derived from this file's location)
%     SchemaPath  - authoritative schema (default: <RepoRoot>/schema/schema.sql)
%
%   This is the ONLY reader of that header. schema/schema.json does not carry
%   the schema version -- tbls exports DDL, and the version lives in a seed
%   INSERT and a pragma, neither of which is DDL -- so the header is the only
%   place a caller without a database can read it from. A second parser of the
%   same line would be a second answer to the same question.
%
%   schema.sql carries its version in three places that must agree: this
%   header, the `schema_info` seed, and `PRAGMA user_version`. This function
%   reads the header and does not attempt to reconcile the three; that
%   agreement is asserted by tests/unit/test_schema_creation.m against a real
%   database.
%
%   See also VAWLUME.SCHEMA.LOADMETADATA, VAWLUME.SCHEMA.VALIDATEMETADATA.

arguments
    options.RepoRoot (1,1) string = ""
    options.SchemaPath (1,1) string = ""
end

schemaPath = options.SchemaPath;
if schemaPath == ""
    repoRoot = options.RepoRoot;
    if repoRoot == ""
        repoRoot = schemaRepositoryRoot();
    end
    schemaPath = fullfile(repoRoot, "schema", "schema.sql");
end

if ~isfile(schemaPath)
    error("vawlume:schema:SchemaFileNotFound", ...
        "Authoritative schema not found: %s", schemaPath);
end

% Read only the header. The version is declared in the first few lines and the
% file is large; a full read to find line 2 is waste, and scanning the whole
% file would also let a `-- Version:` inside a later comment win.
text = fileread(schemaPath);
lines = splitlines(string(text));
lines = lines(1:min(numel(lines), 40));

tokens = regexp(lines, "^\s*--\s*Version:\s*(\S+)\s*$", "tokens", "once");
matched = ~cellfun(@isempty, tokens);

if ~any(matched)
    error("vawlume:schema:SchemaVersionUnreadable", ...
        "No `-- Version:` header in the first %d lines of %s. " + ...
        "The authoritative schema must declare its version there.", ...
        numel(lines), schemaPath);
end

if sum(matched) > 1
    error("vawlume:schema:SchemaVersionUnreadable", ...
        "More than one `-- Version:` header in the first %d lines of %s, " + ...
        "so which one is authoritative is ambiguous.", numel(lines), schemaPath);
end

matchedTokens = tokens{find(matched, 1)};
version = string(matchedTokens{1});
end
