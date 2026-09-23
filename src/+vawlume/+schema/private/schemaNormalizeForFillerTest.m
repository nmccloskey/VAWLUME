function normalized = schemaNormalizeForFillerTest(text)
%SCHEMANORMALIZEFORFILLERTEST Reduce text for the name-restatement comparison.
%
% Case, surrounding punctuation, and runs of whitespace are removed so that
% "Detection score.", "detection score" and "DETECTION  SCORE" all compare
% equal to the de-underscored column name. Nothing else is stripped: a
% description that adds a single real word is allowed through, because the test
% is meant to catch mechanical filler rather than to referee prose quality.

arguments
    text (1,1) string
end

normalized = lower(strtrim(text));
normalized = regexprep(normalized, "[.;:,!?]+$", "");
normalized = regexprep(normalized, "\s+", " ");
normalized = strtrim(normalized);
end
