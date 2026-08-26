function [conn, summary] = createPhase1FixtureDatabase(dbFile, repoRoot)
%CREATEPHASE1FIXTUREDATABASE Create and populate a Phase 1 fixture database.
%
% The returned connection is left open for the caller. The database file is
% expected to be disposable test output, not a tracked binary artifact.

arguments
    dbFile (1,1) string = string(tempname) + ".sqlite"
    repoRoot (1,1) string = ""
end

if strlength(repoRoot) == 0
    repoRoot = defaultRepoRoot();
else
    repoRoot = normalizePath(repoRoot);
end

if isfile(dbFile)
    error("vawlume:db:FixtureDatabaseExists", ...
        "Fixture database already exists: %s", dbFile);
end

conn = sqlite(char(dbFile), "create");
try
    schemaPath = fullfile(repoRoot, "schema", "schema.sql");
    schemaSummary = vawlume.db.applySchema(conn, schemaPath);
    fixtureSummary = vawlume.db.buildPhase1Fixture(conn, repoRoot);

    summary = struct();
    summary.db_file = dbFile;
    summary.schema = schemaSummary;
    summary.fixture = fixtureSummary;
catch exception
    if isopen(conn)
        close(conn);
    end
    deleteIfExists(dbFile);
    deleteIfExists(dbFile + "-journal");
    deleteIfExists(dbFile + "-wal");
    deleteIfExists(dbFile + "-shm");
    rethrow(exception);
end
end

function repoRoot = defaultRepoRoot()
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename("fullpath")))));
repoRoot = string(repoRoot);
end

function path = normalizePath(path)
path = string(path);
if strlength(path) == 0
    return
end
try
    path = string(java.io.File(char(path)).getCanonicalPath());
catch
    path = string(path);
end
end

function deleteIfExists(path)
if isfile(path)
    delete(path);
end
end
