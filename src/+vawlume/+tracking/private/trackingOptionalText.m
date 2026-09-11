function value = trackingOptionalText(spec, name)
%TRACKINGOPTIONALTEXT Read an optional text field, absent or empty becoming "".
value = "";
if ~isfield(spec, name)
    return
end
candidate = string(spec.(name));
if ~isscalar(candidate) || ismissing(candidate)
    error("vawlume:tracking:SpecificationInvalid", ...
        "trackingSpec.%s must be a scalar text value when supplied.", name);
end
value = strtrim(candidate);
end
