function value = geometryOptionalText(spec, name)
%GEOMETRYOPTIONALTEXT Read an optional text field, absent or empty becoming "".
%
% "" reaches geometryInsertRow, which omits the column so the row stores NULL.
% An unsupplied description is therefore genuinely absent rather than an empty
% string masquerading as a supplied value.
value = "";
if ~isfield(spec, name)
    return
end
candidate = string(spec.(name));
if ~isscalar(candidate) || ismissing(candidate)
    error("vawlume:geometry:SpecificationInvalid", ...
        "Specification field '%s' must be a scalar text value when supplied.", ...
        name);
end
value = strtrim(candidate);
end
