function recording = deepsqueakResolveRecording(conn, recordingRef)
%DEEPSQUEAKRESOLVERECORDING Compatibility wrapper for shared recording resolution.
recording = extractorResolveRecording(conn, recordingRef, "DeepSqueak");
end
