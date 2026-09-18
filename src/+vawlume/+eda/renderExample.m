function result = renderExample(prepared, options)
%RENDEREXAMPLE Draw one combined spectrogram overlay from a display plan.

arguments
    prepared (1,1) struct
    options.Styles table = table()
    options.ReferenceConfigurationId (1,1) string = ""
    options.Visible (1,1) logical = false
end

plan = vawlume.eda.exampleDisplayPlan(prepared, Styles=options.Styles, ...
    ReferenceConfigurationId=options.ReferenceConfigurationId);
visibility = "off";
if options.Visible
    visibility = "on";
end

fig = figure(Visible=visibility, Color="white", ...
    Position=[100 100 1400 1100], Tag="vawlume-example-figure");
ax = axes(fig, Position=[0.08 0.48 0.84 0.46], ...
    Tag="vawlume-example-spectrogram");
imageHandle = imagesc(ax, plan.spectrogram_time_s, ...
    plan.spectrogram_frequency_hz, plan.spectrogram_matrix);
imageHandle.Tag = "vawlume-example-spectrogram-image";
axis(ax, "xy");
colormap(ax, gray(256));
colorbar(ax);
xlim(ax, plan.x_limits_s);
ylim(ax, plan.y_limits_hz);
xlabel(ax, "Recording time (s)");
ylabel(ax, "Frequency (Hz)");
title(ax, "Shared raw-audio spectrogram with measured extractor annotations", ...
    Interpreter="none");
hold(ax, "on");

groups = gobjects(height(plan.annotations), 1);
for index = 1:height(plan.annotations)
    row = plan.annotations(index, :);
    color = [row.color_r, row.color_g, row.color_b];
    group = hggroup(ax, Tag="vawlume-example-annotation");
    group.UserData = struct(detection_id=row.detection_id, ...
        extractor_key=row.extractor_key, ...
        frequency_extent_source=row.frequency_extent_source, ...
        has_measured_band=row.has_measured_band);
    if row.has_measured_band
        rectangle(group, Position=[row.rectangle_x, row.rectangle_y, ...
            row.rectangle_width, row.rectangle_height], ...
            EdgeColor=color, LineStyle=row.line_style, LineWidth=2.2, ...
            FaceColor="none", Tag="vawlume-measured-band");
    else
        for time = [row.start_time_s, row.end_time_s]
            line(group, [time time], plan.y_limits_hz, Color=color, ...
                LineStyle=row.line_style, LineWidth=1.8, ...
                Tag="vawlume-time-boundary");
        end
        markerValues = row.marker_frequencies_hz{1};
        for marker = markerValues
            line(group, [row.start_time_s row.end_time_s], [marker marker], ...
                Color=color, LineStyle=row.line_style, LineWidth=2.4, ...
                Marker="|", MarkerSize=8, Tag="vawlume-frequency-marker");
        end
    end
    groups(index) = group;
end

legendHandles = gobjects(height(plan.legend), 1);
for index = 1:height(plan.legend)
    row = plan.legend(index, :);
    legendHandles(index) = line(ax, NaN, NaN, ...
        Color=[row.color_r row.color_g row.color_b], ...
        LineStyle=row.line_style, LineWidth=2.2, ...
        DisplayName=row.legend_label, Tag="vawlume-example-legend-key");
end
legendHandle = legend(ax, legendHandles, plan.legend.legend_label, ...
    Location="southoutside", Interpreter="none", NumColumns=1);
legendHandle.Tag = "vawlume-example-legend";

identityBox = annotation(fig, "textbox", [0.06 0.34 0.88 0.11], ...
    String=plan.identity_text, Interpreter="none", EdgeColor=[0.75 0.75 0.75], ...
    FontSize=9, FitBoxToText="off", Tag="vawlume-example-identity");
noteText = plan.approximate_extent_note + newline + newline + ...
    strjoin(plan.caution, string(newline) + string(newline));
noteBox = annotation(fig, "textbox", [0.06 0.035 0.88 0.28], ...
    String=noteText, Interpreter="none", EdgeColor=[0.75 0.75 0.75], ...
    FontSize=8, FitBoxToText="off", Tag="vawlume-example-caution");

result = struct(status="rendered", figure=fig, axes=ax, ...
    spectrogram_image=imageHandle, annotation_groups=groups, ...
    legend=legendHandle, identity_textbox=identityBox, caution_textbox=noteBox, ...
    plan=plan);
end
