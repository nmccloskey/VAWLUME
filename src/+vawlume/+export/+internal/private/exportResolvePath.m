function path = exportResolvePath(value, what)
%EXPORTRESOLVEPATH Make a caller-supplied path absolute and canonical.
%
% A relative path is resolved against MATLAB's current folder (pwd), which is
% what the caller sees. It must not be handed to java.io.File as it is: Java
% resolves a relative path against the JVM's user.dir, which is fixed when Java
% starts and which MATLAB's cd never moves. Measured in Part 7: after a cd, a
% relative source and destination resolved that way silently exported a
% different database of the same name and published it elsewhere.
%
% On Windows two forms are refused rather than resolved, with
% vawlume:export:AmbiguousPath:
%
%   "C:data\x"   drive-relative: relative to drive C's own current directory
%   "\data\x"    rooted without a drive: on the current folder's drive
%
% Either depends on state that is invisible at the call site. Write the path
% out in full, or make it relative to the current folder.
%
% WHAT names the argument in the error message ("Output", "the database path").

arguments
    value (1,1) string
    what (1,1) string
end

if ispc && (~isempty(regexp(value, "^[A-Za-z]:(?![\\/])", "once")) || ...
        ~isempty(regexp(value, "^[\\/](?![\\/])", "once")))
    error("vawlume:export:AmbiguousPath", ...
        "%s ""%s"" is drive-relative or rooted without a drive, so where it points " + ...
        "depends on hidden per-drive state. Give a full path such as ""C:\\data\\x"", " + ...
        "or a path relative to the current folder.", what, value);
end

if ~java.io.File(char(value)).isAbsolute()
    value = fullfile(string(pwd), value);
end
% Absolute from here on, so user.dir cannot influence canonicalization.
path = string(java.io.File(char(value)).getCanonicalPath());
end
