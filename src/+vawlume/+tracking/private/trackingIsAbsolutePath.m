function value = trackingIsAbsolutePath(path)
%TRACKINGISABSOLUTEPATH Recognize absolute paths on Windows and POSIX alike.
path = string(path);
value = startsWith(path, "/") || startsWith(path, "\") || ...
    ~isempty(regexp(path, "^[A-Za-z]:[\\/]", "once"));
end
