function values = normalizeMappingSequence(rawValue)
%NORMALIZEMAPPINGSEQUENCE Normalize YAML/JSON sequence-shaped values.
if iscell(rawValue)
    values = rawValue(:);
elseif isstruct(rawValue)
    values = num2cell(rawValue(:));
else
    values = {};
end
end
