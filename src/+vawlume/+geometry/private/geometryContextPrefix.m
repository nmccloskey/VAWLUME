function value = geometryContextPrefix(context)
%GEOMETRYCONTEXTPREFIX Prefix an error message with the caller's operation name.
value = "";
if strlength(context) > 0
    value = context + ": ";
end
end
