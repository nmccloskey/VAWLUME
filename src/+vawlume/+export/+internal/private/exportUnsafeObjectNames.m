function unsafe = exportUnsafeObjectNames(names)
%EXPORTUNSAFEOBJECTNAMES The names that may not be used as an object or filename.
%
% A selected name becomes both an SQL identifier and csv/<name>.csv, so it must
% match ^[A-Za-z][A-Za-z0-9_]*$ and must not be a Windows reserved device name
% (CON, PRN, AUX, NUL, COM1-COM9, LPT1-LPT9, in any case). Measured in Part 1:
% every one of the schema's names passes. The guard exists because the
% selection string is supplied by a caller, not because the schema needs it.

arguments
    names string
end

names = names(:);
absent = ismissing(names);
text = names;
text(absent) = "";
pattern = ~cellfun(@isempty, regexp(cellstr(text), "^[A-Za-z][A-Za-z0-9_]*$", "once"));
reserved = ~cellfun(@isempty, regexp(cellstr(text), ...
    "^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$", "once", "ignorecase"));
unsafe = names(~pattern | reserved | absent);
end
