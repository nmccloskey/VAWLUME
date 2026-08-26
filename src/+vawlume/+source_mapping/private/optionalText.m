function text = optionalText(container, field)
%OPTIONALTEXT Return a scalar string field or "" when absent/unusable.
text = "";
if ~hasProfileField(container, field)
    return
end
try
    raw = string(container.(char(field)));
catch
    return
end
if isscalar(raw) && ~ismissing(raw) && strlength(raw) > 0
    text = raw(1);
end
end
