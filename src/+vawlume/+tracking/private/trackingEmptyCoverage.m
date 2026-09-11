function value = trackingEmptyCoverage()
%TRACKINGEMPTYCOVERAGE The declared-coverage summary shape.
names = ["segment_index", "start_time_native", "end_time_native", ...
    "observation_status"];
types = repmat("double", 1, numel(names));
types(ismember(names, "observation_status")) = "string";
value = table(Size=[0, numel(names)], VariableTypes=cellstr(types), ...
    VariableNames=cellstr(names));
end
