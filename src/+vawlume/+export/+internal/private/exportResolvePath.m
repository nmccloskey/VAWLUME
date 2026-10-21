function path = exportResolvePath(value, what)
%EXPORTRESOLVEPATH Make a caller-supplied path absolute and canonical.
%
% A thin wrapper over vawlume.internal.resolvePath, the one home for path
% resolution, which was promoted from this function. It keeps the export's own
% error identifier.
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

try
    path = vawlume.internal.resolvePath(value, What=what);
catch err
    if err.identifier == "vawlume:internal:AmbiguousPath"
        error("vawlume:export:AmbiguousPath", "%s", err.message);
    end
    rethrow(err);
end
end
