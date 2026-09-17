function value = edaPresentText(raw)
%EDAPRESENTTEXT Normalize a fetched text column to present scalar-or-array string.
%
% MATLAB's SQLite interface cannot return a NULL text column at all, so every
% nullable text column is selected through IFNULL and arrives as ''. This maps
% any residual missing string to "" so downstream comparisons never silently
% propagate <missing>.
value = string(raw);
value(ismissing(value)) = "";
end
