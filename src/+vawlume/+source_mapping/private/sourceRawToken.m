function token = sourceRawToken(value)
%SOURCERAWTOKEN Preserve lexical source evidence without fabricating NaN text.
if isempty(value)
    token = "";
elseif iscell(value)
    token = sourceRawToken(value{1});
elseif isstring(value) || ischar(value) || iscellstr(value)
    token = string(value);
    if ~isscalar(token)
        token = strjoin(token, " ");
    end
elseif isnumeric(value) || islogical(value)
    if isscalar(value) && isnumeric(value) && isnan(value)
        token = "";
    elseif isscalar(value)
        token = string(sprintf("%.15g", double(value)));
    else
        token = string(mat2str(double(value)));
    end
else
    try
        token = string(value);
    catch
        token = "<unsupported>";
    end
end
if ismissing(token)
    token = "";
end
end
