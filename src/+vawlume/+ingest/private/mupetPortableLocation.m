function location = mupetPortableLocation(path, declaredRelativePath, roots)
%MUPETPORTABLELOCATION Compatibility wrapper for shared artifact identity.
arguments
    path (1,1) string
    declaredRelativePath (1,1) string
    roots (1,:) string
end
location = extractorPortableLocation(path, declaredRelativePath, roots, "Mupet");
end
