function [fig, ax] = edaPlotFigure(visible, sizeInches, caution, note)
%EDAPLOTFIGURE Shared plain figure frame with the canonical caution attached.
visibility = "off";
if visible
    visibility = "on";
end
fig = figure(Visible=visibility, Color="white", ...
    Position=[100 100 100 * sizeInches(1) 100 * sizeInches(2)], ...
    Tag="vawlume-eda-figure");

noteLines = string(note(:));
noteLines = noteLines(strlength(noteLines) > 0);
noteText = strjoin(noteLines, string(newline) + string(newline));
longNote = strlength(noteText) > 450;
axesPosition = [0.10 0.50 0.84 0.40];
notePosition = [0.04 0.27 0.92 0.17];
if longNote
    % A long interpretation belongs beside the plot. It may be clipped within
    % its own box when a caller supplies unreasonable prose, but it can never
    % displace the canonical caution that must travel intact with the figure.
    axesPosition = [0.09 0.50 0.56 0.40];
    notePosition = [0.68 0.50 0.29 0.40];
end
ax = axes(fig, Position=axesPosition, Tag="vawlume-eda-axes");
% Prevent the first high-level plotting command from resetting shared axes
% metadata such as the stable tag used by tests and downstream composition.
hold(ax, "on");

noteBox = gobjects(0);
if strlength(noteText) > 0
    noteBox = annotation(fig, "textbox", notePosition, String=noteText, ...
        Interpreter="none", EdgeColor=[0.86 0.86 0.86], FontSize=7, ...
        VerticalAlignment="top", FitBoxToText="off", ...
        Tag="vawlume-eda-interpretation-note");
end
box = annotation(fig, "textbox", [0.04 0.025 0.92 0.22], ...
    String=strjoin(string(caution(:)), string(newline) + string(newline)), ...
    Interpreter="none", EdgeColor=[0.78 0.78 0.78], FontSize=7.5, ...
    VerticalAlignment="top", FitBoxToText="off", ...
    Tag="vawlume-eda-caution");
fig.UserData = struct(caution=string(caution(:)), note=noteLines, ...
    caution_textbox=box, interpretation_textbox=noteBox, ...
    long_note_layout=longNote, ...
    colormap_policy="parula or neutral categorical colours; no " + ...
        "red-to-green good/bad scale");
end
