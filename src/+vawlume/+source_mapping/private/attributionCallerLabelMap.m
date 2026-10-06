function map = attributionCallerLabelMap(resolution)
%ATTRIBUTIONCALLERLABELMAP The declared caller-label-to-entity map, and nothing else.
%
% Declared resolution only. A label is a string in somebody else's file; nothing
% here matches on string similarity, case folding or edit distance, and a label
% absent from this map is a surfaced problem for the caller, never a guess.
map = containers.Map("KeyType", "char", "ValueType", "char");
declared = resolution.map;
if isstruct(declared)
    entries = num2cell(declared(:));
elseif iscell(declared)
    entries = declared(:);
else
    entries = {};
end
for index = 1:numel(entries)
    item = entries{index};
    map(char(string(item.caller_label))) = char(string(item.entity_native_id));
end
end
