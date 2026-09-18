function styles = exampleStyles(extractorKeys)
%EXAMPLESTYLES Stable, print-conscious overlay styles from extractor identity.
%
% STYLES = vawlume.eda.EXAMPLESTYLES(EXTRACTORKEYS) returns one row per
% extractor. Colour and dash pattern are derived from a SHA-256 digest of the
% extractor key, so a key keeps its style when examples are rendered separately
% or when gallery order changes. The ordering is lexical and carries no
% scientific meaning.

arguments
    extractorKeys string
end

keys = sort(unique(strtrim(extractorKeys(:))));
keys = keys(strlength(keys) > 0 & ~ismissing(keys));
maximum = 8;
if numel(keys) > maximum
    error("vawlume:eda:ExtractorStyleCapacityExceeded", ...
        "The overlay style set supports at most %d extractors; %d were " + ...
        "requested. Refusing is safer than silently reusing a style.", ...
        maximum, numel(keys));
end

% Okabe-Ito-derived hues remain distinguishable for common colour-vision
% deficiencies. The spectrogram renderer uses greyscale underneath them.
palette = [ ...
      0 114 178; ... % blue
    213  94   0; ... % vermillion
      0 158 115; ... % bluish green
    204 121 167; ... % reddish purple
    230 159   0; ... % orange
     86 180 233; ... % sky blue
    240 228  66; ... % yellow
      0   0   0] / 255;
lineStyles = ["-", "--", ":", "-."];

count = numel(keys);
colorIndex = zeros(count, 1);
lineIndex = zeros(count, 1);
for index = 1:count
    digest = edaSha256OfText(keys(index));
    colorIndex(index) = mod(hex2dec(extractBetween(digest, 1, 8)), ...
        size(palette, 1)) + 1;
    % Couple dash to the stable colour slot. The three pilot extractors occupy
    % different slots and therefore remain distinct in greyscale as well as by
    % hue; slots beyond four deliberately reuse a dash and are documented as
    % the high-count greyscale limitation.
    lineIndex(index) = mod(colorIndex(index) - 1, numel(lineStyles)) + 1;
end

signature = string(colorIndex) + "/" + string(lineIndex);
if numel(unique(signature)) ~= count
    error("vawlume:eda:ExtractorStyleCollision", ...
        "Two extractor keys map to the same colour-and-dash style. Pass a " + ...
        "smaller extractor set or rename the colliding development key; " + ...
        "styles are never silently reused.");
end

styles = table(keys, colorIndex, palette(colorIndex, 1), ...
    palette(colorIndex, 2), palette(colorIndex, 3), ...
    lineStyles(lineIndex)', lineIndex, ...
    VariableNames=["extractor_key", "color_index", "color_r", "color_g", ...
    "color_b", "line_style", "line_style_index"]);
end
