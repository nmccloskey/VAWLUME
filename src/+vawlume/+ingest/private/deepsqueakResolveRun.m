function run = deepsqueakResolveRun(conn, plan)
%DEEPSQUEAKRESOLVERUN Compatibility wrapper for shared run identity resolution.
roles = ["event_measurement_export", "native_detection_container", ...
    "extractor_settings", "detector_network"];
run = extractorResolveRun(conn, plan, roles);
end
