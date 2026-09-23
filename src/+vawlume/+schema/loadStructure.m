function structure = loadStructure(options)
%LOADSTRUCTURE Read the committed structural representation of the schema.
%
%   STRUCTURE = VAWLUME.SCHEMA.LOADSTRUCTURE() reads schema/schema.json and
%   returns the identities it declares:
%
%     objects    table: object_name, object_kind ("table" | "view"), position
%                -- in schema order, which is creation order
%     columns    table: object_name, column_name, position -- declared order
%     relations  table: source_table, source_columns, target_table,
%                target_columns, relationship_key
%     source_path
%
%   Name-value arguments:
%     Path      - structural representation (default: <RepoRoot>/schema/schema.json)
%     RepoRoot  - repository root (default: derived from this file, never `pwd`)
%
%   This is the public entry point to the same reader validateMetadata uses, so
%   the exporter and the validator cannot disagree about what the supported
%   schema is. Only identity is returned. Types, keys, and constraints belong to
%   schema/schema.sql, and nothing here offers a second opinion about them.
%
%   See also VAWLUME.SCHEMA.LOADMETADATA, VAWLUME.SCHEMA.VALIDATEMETADATA.

arguments
    options.Path (1,1) string = ""
    options.RepoRoot (1,1) string = ""
end

structuralPath = options.Path;
if structuralPath == ""
    repoRoot = options.RepoRoot;
    if repoRoot == ""
        repoRoot = schemaRepositoryRoot();
    end
    structuralPath = fullfile(repoRoot, "schema", "schema.json");
end

structure = schemaLoadStructural(structuralPath);
end
