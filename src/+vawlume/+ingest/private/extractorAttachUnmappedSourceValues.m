function routed = extractorAttachUnmappedSourceValues(routed, ir, sourceTable)
%EXTRACTORATTACHUNMAPPEDSOURCEVALUES Preserve unclaimed source columns per event.

arguments
    routed (1,1) struct
    ir (1,1) struct
    sourceTable table
end

claimed = unique(string(ir.values.actual_source_field), "stable");
sourceNames = string(sourceTable.Properties.VariableNames);
unmappedNames = sourceNames(~ismember(sourceNames, claimed));

for index = 1:numel(routed.rows)
    row = routed.rows{index};
    values = unmappedValueTable(unmappedNames);
    for valueIndex = 1:numel(unmappedNames)
        name = unmappedNames(valueIndex);
        raw = rawToken(sourceTable, row.source_row, name);
        values.raw_value_text(valueIndex) = raw;
        values.source_locator(valueIndex) = ...
            "row=" + string(row.source_row) + "; column=" + name;
    end
    row.unmapped_values = values;
    routed.rows{index} = row;
end
end

function value = rawToken(tbl, row, name)
item = tbl.(char(name))(row,:);
if iscell(item), item = item{1}; end
if isstring(item) || ischar(item)
    value = string(item);
elseif isnumeric(item) || islogical(item)
    value = string(item);
elseif iscategorical(item)
    value = string(item);
else
    try
        value = string(item);
    catch
        value = "";
    end
end
if isempty(value), value = ""; else, value = value(1); end
if ismissing(value), value = ""; end
end

function value = unmappedValueTable(names)
count = numel(names);
value = table(names(:), strings(count,1), strings(count,1), strings(count,1), ...
    repmat("source column is not claimed by the output mapping profile",count,1), ...
    repmat("create",count,1), VariableNames=["native_field_name", ...
    "raw_value_text", "native_unit", "source_locator", "reason_unmapped", "action"]);
end
