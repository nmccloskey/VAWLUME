function value = trackingRequiredText(spec, name)
%TRACKINGREQUIREDTEXT Require one nonempty scalar text field of a spec struct.
if ~isfield(spec, name)
    error("vawlume:tracking:SpecificationInvalid", ...
        "trackingSpec.%s is required.", name);
end
value = string(spec.(name));
if ~isscalar(value) || ismissing(value) || strlength(strtrim(value)) == 0
    error("vawlume:tracking:SpecificationInvalid", ...
        "trackingSpec.%s must be a nonempty scalar text value.", name);
end
value = strtrim(value);
end
