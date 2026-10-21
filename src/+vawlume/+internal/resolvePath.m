function value = resolvePath(value, options)
%RESOLVEPATH Resolve a path against an explicit base; the one home for path resolution.
%
%   path = vawlume.internal.resolvePath(value)
%   path = vawlume.internal.resolvePath(value, Base=root)
%   path = vawlume.internal.resolvePath(value, Mode="absolute")
%   tf   = vawlume.internal.resolvePath(value, Mode="isAbsolute")
%
% Not user API. Every VAWLUME function that resolves a path to an absolute
% filesystem location calls this, so that the rule is written once.
%
% A relative VALUE is resolved against an explicit base:
%
%   (default)   MATLAB's current folder (pwd): what the caller sees
%   Base=root   the named base, such as a repository or source root; a
%               relative base is itself resolved against pwd first
%
% It is never handed to java.io.File as it is. Java resolves a relative path
% against the JVM's user.dir, which is fixed when Java starts and which MATLAB's
% cd never moves, so the same relative path would name a different file
% depending on how MATLAB was started. Once the path is absolute, user.dir can
% no longer influence it.
%
% Modes:
%
%   "canonical"   (default) absolute, then java.io.File getCanonicalPath:
%                 "." and ".." removed, and whatever links the host
%                 filesystem resolves for Java resolved
%   "absolute"    absolute, then java.io.File getAbsolutePath: separators
%                 normalized, nothing else
%   "isAbsolute"  return java.io.File isAbsolute as a logical; nothing is
%                 resolved and nothing is refused
%
% No case folding is applied in any mode.
%
% On Windows two forms are refused rather than resolved, with
% vawlume:internal:AmbiguousPath:
%
%   "C:data\x"   drive-relative: relative to drive C's own current directory
%   "\data\x"    rooted without a drive: on the current folder's drive
%
% Either depends on state that is invisible at the call site. With Base= the
% second form is not refused: it is joined to the base, as every base-relative
% site did before this helper existed, so no input those sites resolved changes.
%
% WHAT names the argument in the error message ("Output", "the database path").
%
% See also vawlume.export.internal.runExport.

arguments
    value (1,1) string
    options.Base (1,1) string = missing
    options.Mode (1,1) string {mustBeMember(options.Mode, ...
        ["canonical", "absolute", "isAbsolute"])} = "canonical"
    options.What (1,1) string = "Path"
end

if options.Mode == "isAbsolute"
    value = java.io.File(char(value)).isAbsolute();
    return
end

refuseAmbiguous(value, options.What, ismissing(options.Base));
if ~java.io.File(char(value)).isAbsolute()
    if ismissing(options.Base)
        base = string(pwd);
    elseif strlength(options.Base) == 0
        error("vawlume:internal:InvalidBase", ...
            "The base for %s ""%s"" is empty. Name the folder it is relative to.", ...
            options.What, value);
    else
        base = vawlume.internal.resolvePath(options.Base, Mode="absolute", ...
            What="The base for " + options.What);
    end
    value = fullfile(base, value);
end
% Absolute from here on, so user.dir cannot influence the result.
if options.Mode == "canonical"
    value = string(java.io.File(char(value)).getCanonicalPath());
else
    value = string(java.io.File(char(value)).getAbsolutePath());
end
end

function refuseAmbiguous(value, what, againstPwd)
if ispc && (~isempty(regexp(value, "^[A-Za-z]:(?![\\/])", "once")) || ...
        (againstPwd && ~isempty(regexp(value, "^[\\/](?![\\/])", "once"))))
    error("vawlume:internal:AmbiguousPath", ...
        "%s ""%s"" is drive-relative or rooted without a drive, so where it points " + ...
        "depends on hidden per-drive state. Give a full path such as ""C:\\data\\x"", " + ...
        "or a path relative to the current folder.", what, value);
end
end
