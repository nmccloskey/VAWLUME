function [fig, ax] = edaPlotFigure(visible, sizeInches, caution, note)
%EDAPLOTFIGURE Shared plain figure frame with the canonical caution attached.
visibility = "off";
if visible
    visibility = "on";
end
fig = figure(Visible=visibility, Color="white", ...
    Position=[100 100 100 * sizeInches(1) 100 * sizeInches(2)], ...
    Tag="vawlume-eda-figure");
% Reserve enough lower margin for long, rotated exact-pattern labels and the
% travelling caution. Poster exports must not let either text block overlap.
ax = axes(fig, Position=[0.10 0.50 0.84 0.40], Tag="vawlume-eda-axes");
% Prevent the first high-level plotting command from resetting shared axes
% metadata such as the stable tag used by tests and downstream composition.
hold(ax, "on");

textValue = strings(0, 1);
if strlength(note) > 0
    textValue(end + 1) = note;
end
textValue = [textValue; string(caution(:))];
box = annotation(fig, "textbox", [0.04 0.025 0.92 0.22], ...
    String=strjoin(textValue, string(newline) + string(newline)), ...
    Interpreter="none", EdgeColor=[0.78 0.78 0.78], FontSize=7.5, ...
    FitBoxToText="off", Tag="vawlume-eda-caution");
fig.UserData = struct(caution=string(caution(:)), note=string(note), ...
    caution_textbox=box, colormap_policy="parula or neutral categorical " + ...
        "colours; no red-to-green good/bad scale");
end
