function value = geometryPositiveInteger(raw, label)
%GEOMETRYPOSITIVEINTEGER Require one positive integer identifier or index.
if ~isnumeric(raw) || ~isscalar(raw) || ~isfinite(raw) || raw <= 0 || ...
        raw ~= floor(raw)
    error("vawlume:geometry:InvalidSelector", ...
        "%s must be a positive integer.", label);
end
value = double(raw);
end
