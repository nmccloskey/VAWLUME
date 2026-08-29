function assessment = deepsqueakVersionCompatibility(profileDocument, declaredVersion)
%DEEPSQUEAKVERSIONCOMPATIBILITY Compatibility wrapper for shared version scope.
arguments
    profileDocument (1,1) struct
    declaredVersion (1,1) string
end
assessment = extractorVersionCompatibility(profileDocument, declaredVersion);
end
