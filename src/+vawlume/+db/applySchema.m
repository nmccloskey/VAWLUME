function summary = applySchema(conn, schemaPath)
%APPLYSCHEMA Apply the VAWLUME SQLite schema file to an open connection.
%
% MATLAB Database Toolbox does not support executeSQLScript for sqlite
% connections in this environment, so this helper executes complete SQL
% statements while preserving CREATE TRIGGER ... END; blocks.

arguments
    conn
    schemaPath (1,1) string
end

if ~isfile(schemaPath)
    error("vawlume:db:SchemaNotFound", ...
        "Schema file does not exist: %s", schemaPath);
end

statements = splitSqlStatements(fileread(schemaPath));
executed = 0;
skipped = 0;
for index = 1:numel(statements)
    statement = strtrim(statements(index));
    if statement == "" || statement == "BEGIN TRANSACTION;" || statement == "COMMIT;"
        skipped = skipped + 1;
        continue
    end
    execute(conn, statement);
    executed = executed + 1;
end

summary = struct( ...
    statements_executed=executed, ...
    statements_skipped=skipped, ...
    schema_path=schemaPath);
end

function statements = splitSqlStatements(sqlText)
lines = splitlines(string(sqlText));
statements = strings(0, 1);
buffer = strings(0, 1);
inTrigger = false;

for index = 1:numel(lines)
    line = lines(index);
    trimmed = strtrim(line);
    if startsWith(upper(trimmed), "CREATE TRIGGER")
        inTrigger = true;
    end

    buffer(end + 1, 1) = line; %#ok<AGROW>
    if inTrigger
        if upper(trimmed) == "END;"
            statements(end + 1, 1) = strjoin(buffer, newline); %#ok<AGROW>
            buffer = strings(0, 1);
            inTrigger = false;
        end
    elseif endsWith(trimmed, ";")
        statements(end + 1, 1) = strjoin(buffer, newline); %#ok<AGROW>
        buffer = strings(0, 1);
    end
end

if ~isempty(buffer)
    statements(end + 1, 1) = strjoin(buffer, newline);
end
end
