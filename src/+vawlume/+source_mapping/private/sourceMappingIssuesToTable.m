function tableValue = sourceMappingIssuesToTable(issues)
%SOURCEMAPPINGISSUESTOTABLE Convert source_mapping issues to a stable table.
if isempty(issues)
    tableValue = table(strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
        VariableNames=["severity", "code", "profile_location", "message"]);
else
    tableValue = struct2table(issues);
end
end
