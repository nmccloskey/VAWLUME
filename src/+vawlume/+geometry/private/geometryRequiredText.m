function value = geometryRequiredText(spec, name)
%GEOMETRYREQUIREDTEXT Require one nonempty scalar text field of a spec struct.
if ~isfield(spec, name)
    error("vawlume:geometry:SpecificationInvalid", ...
        "Specification field '%s' is required.", name);
end
value = string(spec.(name));
if ~isscalar(value) || ismissing(value) || strlength(strtrim(value)) == 0
    error("vawlume:geometry:SpecificationInvalid", ...
        "Specification field '%s' must be a nonempty scalar text value.", name);
end
value = strtrim(value);
end
