function extractor = deepsqueakResolveExtractor(conn, irProfile, declaredVersion)
%DEEPSQUEAKRESOLVEEXTRACTOR Compatibility wrapper for shared extractor resolution.
extractor = extractorResolveIdentity(conn, irProfile, declaredVersion, "DeepSqueak");
end
