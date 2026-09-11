function value = geometryScalarText(raw, label)
%GEOMETRYSCALARTEXT Require one nonempty scalar text value.
value = string(raw);
if ~isscalar(value) || ismissing(value) || strlength(strtrim(value)) == 0
    error("vawlume:geometry:InvalidSelector", ...
        "%s must be a nonempty scalar text value.", label);
end
value = strtrim(value);
end
