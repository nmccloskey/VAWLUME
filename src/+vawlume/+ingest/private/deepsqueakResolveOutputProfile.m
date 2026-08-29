function profile = deepsqueakResolveOutputProfile(conn, irProfile)
%DEEPSQUEAKRESOLVEOUTPUTPROFILE Compatibility wrapper for shared profile resolution.
profile = extractorResolveOutputProfile(conn, irProfile, "DeepSqueak");
end
