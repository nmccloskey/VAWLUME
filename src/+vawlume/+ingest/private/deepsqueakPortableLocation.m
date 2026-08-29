function location = deepsqueakPortableLocation(path, declaredRelativePath, roots)
%DEEPSQUEAKPORTABLELOCATION Compatibility wrapper for shared artifact identity.
arguments
    path (1,1) string
    declaredRelativePath (1,1) string
    roots (1,:) string
end
location = extractorPortableLocation(path, declaredRelativePath, roots, "DeepSqueak");
end
