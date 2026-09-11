function value = trackingEmptySamples()
%TRACKINGEMPTYSAMPLES The canonical tracking-sample result shape.
%
% native_track_id is the upstream trajectory label. There is deliberately no
% entity column: this reader resolves no canonical animal identity.
%
% pose_confidence is localization quality only, and is all-NaN when the upstream
% tracker supplied none. time_reference_s is NaN unless a stored alignment
% transform was applied.
names = ["time_native_s", "frame_native", "native_track_id", ...
    "native_bodypart_label", "position_x", "position_y", "position_z", ...
    "pose_confidence", "time_reference_s"];
types = repmat("double", 1, numel(names));
types(ismember(names, ["native_track_id", "native_bodypart_label"])) = "string";
value = table(Size=[0, numel(names)], VariableTypes=cellstr(types), ...
    VariableNames=cellstr(names));
end
