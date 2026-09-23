function index = schemaFirstDuplicate(values)
%SCHEMAFIRSTDUPLICATE Index of the first repeated value, or empty if all unique.
%
% Used where duplicates cannot arrive as a `jsondecode` rename -- inside JSON
% arrays, where repetition is legal JSON and therefore has to be caught on the
% decoded values rather than on field names.

arguments
    values (:,1) string
end

index = zeros(0, 1);
[~, firstIndex] = unique(values, "stable");
repeated = setdiff((1:numel(values))', firstIndex);
if ~isempty(repeated)
    index = repeated(1);
end
end
